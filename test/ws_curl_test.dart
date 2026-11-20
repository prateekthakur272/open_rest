import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/codegen/code_gen.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';

void main() {
  autoNameTests();
  checkTests();
  test('ws curl round trip', () {
    final r = Importers.parseCurl(
      "curl --no-buffer 'wss://echo.example.com/ws?x=1' -H 'Sec-WebSocket-Protocol: a, b' -H 'X-Token: t' -H 'Upgrade: websocket' --data-raw 'hello'",
    )!;
    expect(r.kind, RequestKind.ws);
    expect(r.wsProtocols, 'a, b');
    expect(r.wsMessage, 'hello');
    expect(r.headers.map((h) => h.name), ['X-Token']);
    expect(r.method, 'GET');
    final out = CodeGen.curlWebSocket(
      PreparedRequest(
        method: 'GET',
        url: r.url,
        headers: [('X-Token', 't')],
        body: Body.none,
      ),
      protocols: ['a', 'b'],
      message: 'hello',
    );
    expect(
      out,
      "curl --no-buffer 'wss://echo.example.com/ws?x=1' \\\n"
      "  -H 'X-Token: t' \\\n"
      "  -H 'Sec-WebSocket-Protocol: a, b' \\\n"
      "  --data-raw 'hello'",
    );
  });
}

void autoNameTests() {
  test('auto name: last path segment, host, fallback', () {
    expect(Importers.autoName('https://api.example.com/users'), 'users');
    expect(Importers.autoName('https://api.example.com'), 'api.example.com');
    expect(Importers.autoName('wss://echo.example.com/ws'), 'ws');
    expect(Importers.autoName('{{base}}/x'), 'New Request');
  });
}

void checkTests() {
  test('checkTarget validates URLs and cURL commands', () {
    expect(Importers.checkTarget(''), isNull);
    expect(Importers.checkTarget('https://a.com/x'), isNull);
    expect(Importers.checkTarget('{{base}}/x'), isNull);
    expect(Importers.checkTarget('a.com/x'), contains('scheme'));
    expect(Importers.checkTarget('ftp://a.com'), contains('http://'));
    expect(Importers.checkTarget('https://a b.com'), contains('spaces'));
    expect(Importers.checkTarget('https://'), contains('host'));
    expect(Importers.checkTarget('https://a.com', ws: true), contains('ws://'));
    expect(Importers.checkTarget('wss://a.com/ws', ws: true), isNull);
    expect(Importers.checkTarget('curl'), contains('cURL'));
    expect(Importers.checkTarget('curl -X POST'), contains('cURL'));
    expect(Importers.checkTarget("curl 'https://a.com/x'"), isNull);
    expect(Importers.checkTarget("curl 'wss://a.com/ws'"), isNull);
    expect(Importers.checkTarget("curl 'a.com/x'"), contains('scheme'));
  });
}
