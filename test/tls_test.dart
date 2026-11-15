import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/codegen/code_gen.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/utils/yml.dart';

const _custom = TlsConfig(
  mode: TlsMode.custom,
  format: TlsFormat.pem,
  certPath: 'client.crt',
  keyPath: 'client.key',
  caPath: 'ca.pem',
  passphrase: '{{pw}}',
);

TlsConfig? _resolve({
  TlsConfig col = const TlsConfig(),
  TlsConfig folder = const TlsConfig(),
  TlsConfig req = const TlsConfig(),
  Map<String, String> vars = const {},
}) {
  final request = RequestNode(
    path: '/c/f/r.yaml',
    name: 'r',
    request: ApiRequest(url: 'https://x', tls: req),
  );
  final c = Collection(
    path: '/c',
    name: 'c',
    config: NodeConfig(tls: col),
    environments: [
      Environment(
        name: 'e',
        vars: [for (final e in vars.entries) KV(name: e.key, value: e.value)],
      ),
    ],
    children: [
      FolderNode(
        path: '/c/f',
        name: 'f',
        config: NodeConfig(tls: folder),
        children: [request],
      ),
    ],
  );
  return Execution(
    RunCtx(c, 'e', {}, const AppSettings()),
    request,
  ).effectiveTls();
}

TlsConfig _pfx(String path) =>
    TlsConfig(mode: TlsMode.custom, pfxPath: path, passphrase: 'x');

void main() {
  group('effectiveTls', () {
    test('nothing configured means no certificate', () {
      expect(_resolve(), isNull);
    });

    test('collection applies when nothing is overridden', () {
      expect(_resolve(col: _pfx('/abs/a.pfx'))?.pfxPath, '/abs/a.pfx');
    });

    test('folder overrides the collection, request overrides the folder', () {
      expect(
        _resolve(col: _pfx('/a.pfx'), folder: _pfx('/b.pfx'))?.pfxPath,
        '/b.pfx',
      );
      expect(
        _resolve(
          col: _pfx('/a.pfx'),
          folder: _pfx('/b.pfx'),
          req: _pfx('/c.pfx'),
        )?.pfxPath,
        '/c.pfx',
      );
    });

    test('none stops the walk at the request and at a folder', () {
      const none = TlsConfig(mode: TlsMode.none);
      expect(_resolve(col: _pfx('/a.pfx'), req: none), isNull);
      expect(_resolve(col: _pfx('/a.pfx'), folder: none), isNull);
      expect(
        _resolve(
          col: _pfx('/a.pfx'),
          folder: none,
          req: _pfx('/c.pfx'),
        )?.pfxPath,
        '/c.pfx',
      );
    });

    test(
      'variables are expanded and relative paths use the collection dir',
      () {
        final t = _resolve(col: _custom, vars: {'pw': 's3cret'})!;
        expect(t.certPath, '/c/client.crt');
        expect(t.keyPath, '/c/client.key');
        expect(t.caPath, '/c/ca.pem');
        expect(t.passphrase, 's3cret');
        final abs = _resolve(col: _custom.copyWith(certPath: '/etc/x.crt'))!;
        expect(abs.certPath, '/etc/x.crt');
      },
    );
  });

  group('yaml', () {
    test('collection and folder round trip', () {
      final cfg = NodeConfig(name: 'c', tls: _custom);
      final back = OrYaml.mapToConfig(
        Yml.parse(Yml.dump(OrYaml.configToMap(cfg, false))) as Map,
      );
      expect(back.tls, _custom);
      final f = OrYaml.mapToConfig(
        Yml.parse(Yml.dump(OrYaml.configToMap(cfg, true))) as Map,
      );
      expect(f.tls, _custom);
    });

    test('request round trip, none and inherit', () {
      for (final t in [
        _custom,
        const TlsConfig(mode: TlsMode.none),
        const TlsConfig(
          mode: TlsMode.custom,
          pfxPath: 'a.pfx',
          passphrase: 'p',
        ),
      ]) {
        final r = ApiRequest(url: 'https://x', tls: t);
        final back = OrYaml.parseRequest(OrYaml.requestText(r))!;
        expect(back.tls, t);
      }
    });

    test('inherit writes nothing and old files load as inherit', () {
      final text = OrYaml.requestText(const ApiRequest(url: 'https://x'));
      expect(text.contains('tls'), isFalse);
      expect(
        OrYaml.configToMap(
          const NodeConfig(name: 'c'),
          false,
        ).containsKey('tls'),
        isFalse,
      );
      const old = 'method: GET\nurl: https://x\nsettings:\n  timeout: 5\n';
      expect(OrYaml.parseRequest(old)!.tls, const TlsConfig());
      expect(
        OrYaml.mapToConfig(Yml.parse('name: c\n') as Map).tls,
        const TlsConfig(),
      );
    });
  });

  group('curl', () {
    test('imports --cert/--key/--cacert', () {
      final r = parseCurlOrFail(
        "curl --cert c.crt --key c.key --cacert ca.pem https://x",
      );
      expect(r.tls.mode, TlsMode.custom);
      expect(r.tls.format, TlsFormat.pem);
      expect(r.tls.certPath, 'c.crt');
      expect(r.tls.keyPath, 'c.key');
      expect(r.tls.caPath, 'ca.pem');
    });

    test('imports a P12 certificate with its passphrase', () {
      final r = parseCurlOrFail(
        'curl --cert-type P12 --cert client.p12:hunter2 https://x',
      );
      expect(r.tls.format, TlsFormat.pfx);
      expect(r.tls.pfxPath, 'client.p12');
      expect(r.tls.passphrase, 'hunter2');
      expect(parseCurlOrFail('curl https://x').tls, const TlsConfig());
    });

    test(
      'codegen emits the certificate flags with a passphrase placeholder',
      () {
        PreparedRequest p(TlsConfig t) => PreparedRequest(
          method: 'GET',
          url: 'https://x',
          headers: const [],
          body: const BodyNone(),
          tls: t,
        );
        final pem = CodeGen.generate(
          'cURL',
          p(_custom.copyWith(passphrase: 'real')),
        );
        expect(pem, contains("--cert 'client.crt'"));
        expect(pem, contains("--key 'client.key'"));
        expect(pem, contains("--cacert 'ca.pem'"));
        expect(pem, contains("--pass '<passphrase>'"));
        expect(pem, isNot(contains('real')));
        final pfx = CodeGen.generate(
          'cURL',
          p(
            const TlsConfig(
              mode: TlsMode.custom,
              pfxPath: 'a.pfx',
              passphrase: 'real',
            ),
          ),
        );
        expect(pfx, contains("--cert 'a.pfx:<passphrase>' --cert-type P12"));
        expect(pfx, isNot(contains('real')));
        expect(
          CodeGen.generate('cURL', p(const TlsConfig())),
          isNot(contains('--cert')),
        );
      },
    );
  });
}

ApiRequest parseCurlOrFail(String cmd) {
  final r = Importers.parseCurl(cmd);
  expect(r, isNotNull);
  return r!;
}
