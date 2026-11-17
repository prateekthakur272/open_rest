import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/http/generated_headers.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/storage/storage.dart';

import 'helpers.dart';

void main() {
  late AppState s;
  late String dir;

  Future<void> open({NodeConfig? config}) async {
    useTempHome();
    dir = Collections.create(tempDir('gh'), 'G');
    if (config != null) Collections.saveCollectionConfig(dir, config);
    s = AppState()..addCollection(dir, false);
  }

  List<GeneratedHeader> of(ApiRequest r) => Execution(
    s.runCtx(s.collection(dir)!),
    RequestNode(path: '$dir/r.yaml', name: r.name, request: r),
  ).generatedHeaders(s.settings);

  String names(List<GeneratedHeader> h) => h.map((x) => x.name).join(', ');
  GeneratedHeader pick(List<GeneratedHeader> h, String name) =>
      h.firstWhere((x) => x.name.toLowerCase() == name.toLowerCase());

  setUp(() async => open());

  test('a plain GET lists what the client adds', () {
    final h = of(const ApiRequest(url: 'http://example.test:8080/a'));
    expect(names(h), 'Host, User-Agent, Accept, Accept-Encoding');
    expect(pick(h, 'Host').value, 'example.test:8080');
    expect(pick(h, 'User-Agent').value, s.settings.effectiveUserAgent);
    expect(pick(h, 'Accept').value, '*/*');
    expect(pick(h, 'Accept-Encoding').value, 'gzip, deflate');
    expect(h.every((x) => x.source == HeaderSource.client), isTrue);
  });

  test('the default port is left out of Host', () {
    expect(
      pick(of(const ApiRequest(url: 'https://example.test/a')), 'Host').value,
      'example.test',
    );
    expect(
      pick(of(const ApiRequest(url: 'http://example.test/a')), 'Host').value,
      'example.test',
    );
  });

  test('a header the request sets itself is not listed again (any case)', () {
    final h = of(
      const ApiRequest(
        url: 'http://example.test/',
        headers: [
          KV(name: 'user-agent', value: 'Mine/1'),
          KV(name: 'ACCEPT', value: 'text/plain'),
          KV(name: 'X-Off', value: '1', enabled: false),
        ],
      ),
    );
    expect(names(h), 'Host, Accept-Encoding');
  });

  test('no URL yet: no Host, nothing breaks', () {
    expect(
      names(of(const ApiRequest())),
      'User-Agent, Accept, Accept-Encoding',
    );
  });

  group('auth', () {
    GeneratedHeader auth(Auth a, {String url = 'http://example.test/'}) =>
        of(ApiRequest(url: url, auth: a)).first;

    test('basic', () {
      final h = auth(
        const Auth(mode: AuthMode.Basic, username: 'u', password: 'p'),
      );
      expect(
        (h.name, h.value, h.source),
        ('Authorization', 'Basic dTpw', HeaderSource.auth),
      );
    });

    test('bearer, with variables resolved', () {
      s.runtime(dir)['tok'] = 'abc';
      final h = auth(const Auth(mode: AuthMode.Bearer, token: '{{tok}}'));
      expect(h.value, 'Bearer abc');
    });

    test(
      'api key goes in a header, or not at all when it goes in the query',
      () {
        final h = auth(
          const Auth(mode: AuthMode.ApiKey, keyName: 'X-Key', keyValue: 'k1'),
        );
        expect((h.name, h.value), ('X-Key', 'k1'));
        final q = of(
          const ApiRequest(
            url: 'http://example.test/',
            auth: Auth(
              mode: AuthMode.ApiKey,
              keyName: 'key',
              keyValue: 'k1',
              placement: 'queryparams',
            ),
          ),
        );
        expect(q.any((x) => x.name == 'key'), isFalse);
      },
    );

    test('OAuth 2 and digest show a placeholder instead of calling anyone', () {
      expect(
        auth(const Auth(mode: AuthMode.OAuth2)).value,
        contains('fetched when sent'),
      );
      expect(
        auth(const Auth(mode: AuthMode.Digest)).value,
        contains('challenge'),
      );
    });

    test('auth inherited from the collection is shown', () async {
      await open(
        config: const NodeConfig(
          name: 'G',
          auth: Auth(mode: AuthMode.Bearer, token: 'from-collection'),
        ),
      );
      final h = of(const ApiRequest(url: 'http://example.test/'));
      expect(pick(h, 'Authorization').value, 'Bearer from-collection');
    });

    test('no auth, no Authorization', () {
      expect(
        of(const ApiRequest(url: 'http://example.test/'))
            .any((x) => x.name == 'Authorization'),
        isFalse,
      );
    });
  });

  group('body', () {
    test('raw JSON: type and byte length (not character count)', () {
      final h = of(
        const ApiRequest(
          method: 'POST',
          url: 'http://example.test/',
          bodyMode: BodyMode.Json,
          bodyJson: '{"a":"é"}',
        ),
      );
      expect(pick(h, 'Content-Type').value, 'application/json');
      expect(pick(h, 'Content-Length').value, '10');
      expect(pick(h, 'Content-Type').source, HeaderSource.body);
    });

    test(
      'a Content-Type the request sets is kept, the length is still listed',
      () {
        final h = of(
          const ApiRequest(
            method: 'POST',
            url: 'http://example.test/',
            bodyMode: BodyMode.Json,
            bodyJson: '{}',
            headers: [
              KV(name: 'content-type', value: 'application/vnd.x+json'),
            ],
          ),
        );
        expect(h.any((x) => x.name == 'Content-Type'), isFalse);
        expect(pick(h, 'Content-Length').value, '2');
      },
    );

    test('form: type and encoded length', () {
      final h = of(
        const ApiRequest(
          method: 'POST',
          url: 'http://example.test/',
          bodyMode: BodyMode.Form,
          formUrlEncoded: [
            KV(name: 'a', value: '1 2'),
            KV(name: 'b', value: 'x'),
          ],
        ),
      );
      expect(
        pick(h, 'Content-Type').value,
        'application/x-www-form-urlencoded',
      );
      expect(pick(h, 'Content-Length').value, '${'a=1+2&b=x'.length}');
    });

    test('binary file: octet-stream and the file size', () {
      final f = File('$dir/blob.bin')..writeAsBytesSync(List.filled(37, 7));
      final h = of(
        ApiRequest(
          method: 'POST',
          url: 'http://example.test/',
          bodyMode: BodyMode.File,
          bodyFile: f.path,
        ),
      );
      expect(pick(h, 'Content-Type').value, 'application/octet-stream');
      expect(pick(h, 'Content-Length').value, '37');
    });

    test('multipart: boundary and length are generated when sent', () {
      final h = of(
        const ApiRequest(
          method: 'POST',
          url: 'http://example.test/',
          bodyMode: BodyMode.Multipart,
          multipart: [KV(name: 'a', value: 'b')],
        ),
      );
      expect(
        pick(h, 'Content-Type').value,
        startsWith('multipart/form-data; boundary='),
      );
      expect(pick(h, 'Content-Length').value, calculatedWhenSent);
    });
  });

  test('cookies from the jar are listed', () {
    final uri = Uri.parse('http://cookie-preview.test/');
    HttpExecutor.cookies.store(uri, ['sid=xyz; Path=/']);
    final h = of(const ApiRequest(url: 'http://cookie-preview.test/x'));
    expect(pick(h, 'Cookie').value, contains('sid=xyz'));
    expect(pick(h, 'Cookie').source, HeaderSource.cookies);
    expect(
      of(const ApiRequest(url: 'http://no-cookies.test/'))
          .any((x) => x.name == 'Cookie'),
      isFalse,
    );
  });

  test('a WebSocket request lists the handshake headers instead', () {
    final h = of(
      const ApiRequest(
        kind: RequestKind.ws,
        url: 'wss://example.test/live',
        wsProtocols: 'graphql-transport-ws, v2',
      ),
    );
    expect(
      names(h),
      'Host, User-Agent, Upgrade, Connection, Sec-WebSocket-Version, Sec-WebSocket-Key, Sec-WebSocket-Protocol',
    );
    expect(pick(h, 'Sec-WebSocket-Protocol').value, 'graphql-transport-ws, v2');
    expect(pick(h, 'Upgrade').source, HeaderSource.websocket);
  });

  test('every listed header is really sent, with the same value', () async {
    final seen = <String, String>{};
    final srv = await startServer((r) async {
      r.headers.forEach((k, v) => seen[k.toLowerCase()] = v.join(', '));
      await r.drain<void>();
      await respond(r, '{}');
    });
    addTearDown(() => srv.close(force: true));
    s.runtime(dir)['tok'] = 'real-token';
    s.createRequest(dir, dir, 'R', 'POST', 'http://127.0.0.1:${srv.port}/p');
    final tab = s.activeTab!;
    s.update(
      tab,
      (r) => r.copyWith(
        bodyMode: BodyMode.Json,
        bodyJson: '{"name":"é"}',
        auth: const Auth(mode: AuthMode.Bearer, token: '{{tok}}'),
      ),
    );
    final listed = of(tab.draft);
    await s.send(tab);

    expect(
      listed.map((x) => x.name.toLowerCase()),
      containsAll([
        'host',
        'user-agent',
        'accept',
        'accept-encoding',
        'authorization',
        'content-type',
        'content-length',
      ]),
    );
    for (final h in listed) {
      expect(seen[h.name.toLowerCase()], h.value, reason: h.name);
    }
  });
}
