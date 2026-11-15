import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';

import 'helpers.dart';

const _openssl = '/usr/bin/openssl';
const _pass = 'p4ss';

/// Certificates generated once per run with the system openssl.
class _Pki {
  _Pki(this.dir);
  final String dir;
  String f(String n) => '$dir/$n';
}

Future<void> _run(List<String> args, String dir) async {
  final r = await Process.run(_openssl, args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('openssl ${args.first}: ${r.stderr}');
}

Future<_Pki> _generate() async {
  final d = tempDir('mtls');
  File('$d/ca.cnf').writeAsStringSync(
    '[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=v3\n'
    '[dn]\nCN=Test CA\n'
    '[v3]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n',
  );
  File('$d/server.ext').writeAsStringSync(
    'subjectAltName=IP:127.0.0.1,DNS:localhost\nbasicConstraints=CA:FALSE\n'
    'keyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n',
  );
  File('$d/client.ext').writeAsStringSync(
    'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth\n',
  );
  await _run(['genrsa', '-out', 'ca.key', '2048'], d);
  await _run([
    'req', '-x509', '-new', '-key', 'ca.key', '-sha256', '-days', '2',
    '-config', 'ca.cnf', '-out', 'ca.pem', //
  ], d);
  for (final n in ['server', 'client']) {
    await _run(['genrsa', '-out', '$n.key', '2048'], d);
    await _run([
      'req', '-new', '-key', '$n.key', '-subj', '/CN=$n', '-out', '$n.csr', //
    ], d);
    await _run([
      'x509', '-req', '-in', '$n.csr', '-CA', 'ca.pem', '-CAkey', 'ca.key',
      '-CAcreateserial', '-days', '2', '-sha256', '-extfile', '$n.ext',
      '-out', '$n.crt', //
    ], d);
  }
  await _run([
    'pkcs12', '-export', '-inkey', 'client.key', '-in', 'client.crt',
    '-certfile', 'ca.pem', '-out', 'client.pfx', '-passout', 'pass:$_pass', //
  ], d);
  return _Pki(d);
}

Future<HttpServer> _server(
  _Pki pki,
  List<String?> seen, {
  bool require = false,
}) async {
  final ctx = SecurityContext()
    ..useCertificateChain(pki.f('server.crt'))
    ..usePrivateKey(pki.f('server.key'))
    ..setTrustedCertificates(pki.f('ca.pem'));
  final srv = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    ctx,
    requestClientCertificate: true,
  );
  srv.listen((r) async {
    seen.add(r.certificate?.subject);
    if (require && r.certificate == null) {
      await respond(r, '{"error":"client certificate required"}', status: 403);
    } else {
      await respond(r, '{"ok":true}');
    }
  }, onError: (_) {});
  return srv;
}

PreparedRequest _req(HttpServer s, [TlsConfig? tls]) => PreparedRequest(
  method: 'GET',
  url: 'https://127.0.0.1:${s.port}/',
  headers: const [],
  body: const BodyNone(),
  tls: tls,
);

void main() {
  final hasOpenssl = File(_openssl).existsSync();
  late _Pki pki;

  setUpAll(() async {
    if (hasOpenssl) pki = await _generate();
  });
  tearDownAll(() {
    HttpExecutor.closeClients();
    if (hasOpenssl) Directory(pki.dir).deleteSync(recursive: true);
  });

  group('mutual TLS', () {
    const secure = AppSettings(timeoutMs: 15000);
    final skip = hasOpenssl ? null : '$_openssl is not installed';

    TlsConfig pem(_Pki k, {String ca = 'ca.pem'}) => TlsConfig(
      mode: TlsMode.custom,
      format: TlsFormat.pem,
      certPath: k.f('client.crt'),
      keyPath: k.f('client.key'),
      caPath: k.f(ca),
    );
    TlsConfig pfx(_Pki k, String passphrase) => TlsConfig(
      mode: TlsMode.custom,
      pfxPath: k.f('client.pfx'),
      caPath: k.f('ca.pem'),
      passphrase: passphrase,
    );

    test('PEM client certificate is accepted', skip: skip, () async {
      final seen = <String?>[];
      final srv = await _server(pki, seen);
      addTearDown(() => srv.close(force: true));
      final res = await HttpExecutor.execute(_req(srv, pem(pki)), secure);
      expect(res.error, isNull);
      expect(res.status, 200);
      expect(seen.single, contains('CN=client'));
    });

    test('PKCS#12 client certificate is accepted', skip: skip, () async {
      final seen = <String?>[];
      final srv = await _server(pki, seen);
      addTearDown(() => srv.close(force: true));
      final res = await HttpExecutor.execute(
        _req(srv, pfx(pki, _pass)),
        secure,
      );
      expect(res.error, isNull);
      expect(res.status, 200);
      expect(seen.single, contains('CN=client'));
    });

    test('a wrong passphrase gives a friendly error', skip: skip, () async {
      final seen = <String?>[];
      final srv = await _server(pki, seen);
      addTearDown(() => srv.close(force: true));
      final res = await HttpExecutor.execute(
        _req(srv, pfx(pki, 'nope-nope')),
        secure,
      );
      expect(res.error, contains('Could not read the client certificate'));
      expect(res.error, contains('wrong passphrase'));
      expect(res.error, isNot(contains('nope-nope')));
      expect(seen, isEmpty);
    });

    test('a missing file gives a friendly error', skip: skip, () async {
      final seen = <String?>[];
      final srv = await _server(pki, seen);
      addTearDown(() => srv.close(force: true));
      final missing = pki.f('missing.pfx');
      final res = await HttpExecutor.execute(
        _req(srv, pfx(pki, _pass).copyWith(pfxPath: missing)),
        secure,
      );
      expect(res.error, 'Client certificate not found: $missing');
    });

    test('a custom CA trusts the private server', skip: skip, () async {
      final seen = <String?>[];
      final srv = await _server(pki, seen);
      addTearDown(() => srv.close(force: true));
      final onlyCa = TlsConfig(mode: TlsMode.custom, caPath: pki.f('ca.pem'));
      final ok = await HttpExecutor.execute(_req(srv, onlyCa), secure);
      expect(ok.error, isNull);
      expect(ok.status, 200);
      expect(seen.single, isNull);
      // Without the CA the private server is not trusted.
      final bad = await HttpExecutor.execute(_req(srv), secure);
      expect(bad.error, isNotNull);
      expect(bad.status, 0);
    });

    test(
      'without a certificate the server sees none and can refuse',
      skip: skip,
      () async {
        final seen = <String?>[];
        final optional = await _server(pki, seen);
        addTearDown(() => optional.close(force: true));
        final res = await HttpExecutor.execute(
          _req(optional),
          const AppSettings(sslVerify: false, timeoutMs: 15000),
        );
        expect(res.status, 200);
        expect(seen.single, isNull);

        final required = await _server(pki, seen, require: true);
        addTearDown(() => required.close(force: true));
        final denied = await HttpExecutor.execute(
          _req(required),
          const AppSettings(sslVerify: false, timeoutMs: 15000),
        );
        expect(denied.status, 403);
      },
    );
  });
}
