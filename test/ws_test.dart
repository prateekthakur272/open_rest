import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/core/ws/ws_client.dart';
import 'package:open_rest/utils/yml.dart';

import 'helpers.dart';

Future<void> until(bool Function() cond, {int ms = 4000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) fail('condition not met in ${ms}ms');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// An echo server: replies `echo:<msg>`, closes with 4000 on `close-me`, records handshake headers.
Future<HttpServer> echoServer(
  List<Map<String, String>> seen, [
  List<int?>? closed,
]) async {
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  srv.listen((req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = 200;
      req.response.write('just http');
      await req.response.close();
      return;
    }
    seen.add({
      'x-test': req.headers.value('x-test') ?? '',
      'authorization': req.headers.value('authorization') ?? '',
      'user-agent': req.headers.value('user-agent') ?? '',
      'protocol': req.headers.value('sec-websocket-protocol') ?? '',
      'path': req.uri.toString(),
    });
    final ws = await WebSocketTransformer.upgrade(
      req,
      protocolSelector: (p) => p.first,
    );
    ws.listen((m) {
      if (m == 'close-me') {
        ws.close(4000, 'bye');
      } else if (m == 'binary') {
        ws.add([1, 2, 3, 255]);
      } else {
        ws.add('echo:$m');
      }
    }, onDone: () => closed?.add(ws.closeCode));
  });
  return srv;
}

void main() {
  setUp(useTempHome);

  test('ws helpers: protocols and url scheme', () {
    expect(parseProtocols('a, b  c,,'), ['a', 'b', 'c']);
    expect(parseProtocols(' '), isEmpty);
    expect(toWsUrl('https://x.test/p'), 'wss://x.test/p');
    expect(toWsUrl('http://x.test'), 'ws://x.test');
    expect(toWsUrl('ws://x.test'), 'ws://x.test');
  });

  test('ws request persists in yaml; http requests stay unchanged', () {
    const r = ApiRequest(
      name: 'Live',
      kind: RequestKind.ws,
      url: 'wss://x.test/ws',
      wsProtocols: 'graphql-transport-ws',
      wsMessage: '{"type":"ping"}',
      wsMessages: [KV(name: 'ping', value: '{"type":"ping"}')],
    );
    final text = OrYaml.requestText(r);
    expect(text, contains('kind: ws'));
    final back = OrYaml.parseRequest(text)!;
    expect(back.kind, RequestKind.ws);
    expect(back.wsProtocols, 'graphql-transport-ws');
    expect(back.wsMessage, '{"type":"ping"}');
    expect(back.wsMessages.single.name, 'ping');
    expect(back.displayMethod, 'WS');

    final http = OrYaml.requestText(const ApiRequest(url: 'http://x'));
    expect(http, isNot(contains('kind')));
    expect(http, isNot(contains('ws:')));
    expect(OrYaml.parseRequest(http)!.kind, RequestKind.http);
  });

  test('the collection runner skips websocket requests', () {
    final nodes = <Node>[
      const RequestNode(path: 'a', name: 'a', request: ApiRequest()),
      const RequestNode(
        path: 'b',
        name: 'b',
        request: ApiRequest(kind: RequestKind.ws),
      ),
    ];
    expect(Runner.flatten(nodes).map((n) => n.name), ['a']);
  });

  group('against a server', () {
    late HttpServer srv;
    late List<Map<String, String>> seen;
    late List<int?> closed;
    late AppState s;
    late String dir;

    setUp(() async {
      seen = [];
      closed = [];
      srv = await echoServer(seen, closed);
      dir = Collections.create(tempDir('ws'), 'W');
      s = AppState()..addCollection(dir, false);
      s.runtime(dir)['port'] = '${srv.port}';
    });
    tearDown(() async {
      for (final t in s.tabs.toList()) {
        s.closeTab(t.id, true);
      }
      await srv.close(force: true);
    });

    RequestTab open(String url, {String protocols = ''}) {
      s.createRequest(dir, dir, 'Live', 'GET', url, ws: true);
      final tab = s.activeTab!;
      s.update(
        tab,
        (r) => r.copyWith(
          wsProtocols: protocols,
          headers: const [KV(name: 'X-Test', value: 'hello-{{port}}')],
        ),
      );
      return tab;
    }

    test('connect, subprotocol, headers, echo, binary, close', () async {
      final tab = open(
        'ws://127.0.0.1:{{port}}/chat?room=1',
        protocols: 'v1, v2',
      );
      expect(tab.ws, isNotNull);
      expect(tab.draft.kind, RequestKind.ws);
      expect(tab.draft.method, 'GET');
      final ws = tab.ws!;

      await s.connectWs(tab);
      await until(() => ws.isOpen);
      expect(ws.protocol, 'v1');
      expect(seen.single['x-test'], 'hello-${srv.port}');
      expect(seen.single['user-agent'], AppSettings.defaultUserAgent);
      expect(seen.single['protocol'], 'v1, v2');
      expect(seen.single['path'], '/chat?room=1');

      s.update(tab, (r) => r.copyWith(wsMessage: 'hi {{port}}'));
      expect(s.sendWs(tab), isTrue);
      await until(() => ws.receivedCount == 1);
      final received = ws.messages.where((m) => m.dir == WsDir.received).single;
      expect(received.text, 'echo:hi ${srv.port}');
      expect(
        ws.messages.where((m) => m.dir == WsDir.sent).single.text,
        'hi ${srv.port}',
      );

      s.update(tab, (r) => r.copyWith(wsMessage: 'binary'));
      s.sendWs(tab);
      await until(() => ws.receivedCount == 2);
      final bin = ws.messages.where((m) => m.dir == WsDir.received).last;
      expect(bin.isBinary, isTrue);
      expect(bin.size, 4);
      expect(bin.hex, '01 02 03 ff');

      // The server closes with a code: the session reports it and drops the connection.
      s.update(tab, (r) => r.copyWith(wsMessage: 'close-me'));
      s.sendWs(tab);
      await until(() => ws.status == WsStatus.disconnected);
      expect(ws.messages.last.text, 'Closed with code 4000 (bye)');
      expect(ws.messages.last.error, isTrue);
      expect(s.sendWs(tab), isFalse);
    });

    test('disconnect closes cleanly and reconnect works', () async {
      final tab = open('ws://127.0.0.1:{{port}}/');
      final ws = tab.ws!;
      await s.connectWs(tab);
      await until(() => ws.isOpen);
      await ws.disconnect();
      expect(ws.status, WsStatus.disconnected);
      expect(ws.messages.last.text, 'Disconnected');
      await s.connectWs(tab);
      await until(() => ws.isOpen);
      expect(seen.length, 2);
    });

    test('plain http server and bad urls give readable errors', () async {
      final plain = open('ws://127.0.0.1:{{port}}/');
      // A plain HTTP server that does not upgrade.
      final http = await startServer((req) => respond(req, 'nope'));
      addTearDown(() => http.close(force: true));
      s.update(plain, (r) => r.copyWith(url: 'ws://127.0.0.1:${http.port}/'));
      await s.connectWs(plain);
      await until(
        () =>
            plain.ws!.status == WsStatus.disconnected &&
            plain.ws!.messages.length > 1,
      );
      expect(plain.ws!.messages.last.error, isTrue);

      s.update(plain, (r) => r.copyWith(url: 'not a url'));
      plain.ws!.clear();
      await s.connectWs(plain);
      await until(() => plain.ws!.messages.length >= 2);
      expect(
        plain.ws!.messages.last.text,
        'Invalid URL: use ws://host/path or wss://host/path',
      );
    });

    test('closing the tab disconnects', () async {
      final tab = open('ws://127.0.0.1:{{port}}/');
      final ws = tab.ws!;
      await s.connectWs(tab);
      await until(() => ws.isOpen);
      expect(closed, isEmpty);
      s.closeTab(tab.id, true);
      // The server sees the connection end (going away).
      await until(() => closed.isNotEmpty);
      expect(closed.single, 1001);
    });
  });
}
