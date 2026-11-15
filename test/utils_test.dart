import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/utils/bru.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/url_codec.dart';
import 'package:open_rest/utils/yml.dart';

void main() {
  group('UrlCodec', () {
    test('decode', () {
      expect(UrlCodec.decode('a%20b%26c%3Dd%2F%C3%A9'), 'a b&c=d/é');
      expect(
        UrlCodec.decode('1+2'),
        '1+2',
      ); // '+' is kept, like decodeURIComponent
      expect(
        UrlCodec.decode('100%'),
        '100%',
      ); // malformed input is returned unchanged
    });
    test('encode', () {
      expect(UrlCodec.encode('a b&c'), 'a%20b%26c');
      expect(
        UrlCodec.encode('{{host}}/a b').replaceAll('%2F', '/'),
        '{{host}}/a%20b',
      ); // variables are never encoded
      expect(UrlCodec.encode('~-_.'), '~-_.');
    });
    test('roundTrip', () {
      const s = 'name=Zoë & co/100%?x';
      expect(UrlCodec.decode(UrlCodec.encode(s)), s);
    });
    test('detect', () {
      expect(UrlCodec.looksEncoded('a%20b'), isTrue);
      expect(UrlCodec.looksEncoded('plain 100%'), isFalse);
    });
  });

  group('Core', () {
    test('bruRoundTrip', () {
      final r = ApiRequest(
        name: 'Create user',
        seq: 3,
        method: 'POST',
        url: '{{host}}/users?a=1',
        params: [const KV(name: 'a', value: '1')],
        headers: [
          const KV(name: 'X-A', value: 'b'),
          const KV(name: 'X-Off', value: 'c', enabled: false),
        ],
        bodyMode: BodyMode.Json,
        bodyJson: '{\n  "a": 1\n}',
        auth: const Auth(mode: AuthMode.Bearer, token: 'tok'),
        postVars: [const KV(name: 'id', value: 'res.body.id')],
        assertions: [const KV(name: 'res.status', value: 'eq 201')],
        tests: "test('x', () => {\n  expect(1).to.equal(1);\n});",
        multipart: [
          const KV(name: 'f', value: '/tmp/x', isFile: true),
          const KV(name: 't', value: 'v'),
        ],
      );
      final back = Bru.parseRequest(Bru.serializeRequest(r));
      expect(back, r.copyWith());
    });

    test('jsonPretty', () {
      expect(
        Json.prettyText('{"a":[1,2],"b":{}}'),
        '{\n  "a": [\n    1,\n    2\n  ],\n  "b": {}\n}',
      );
      expect(Json.prettyText('{bad'), isNull);
    });

    test('json numbers and paths', () {
      expect(Json.parse('{"a":1,"b":1.5,"c":[true,null]}'), {
        'a': 1,
        'b': 1.5,
        'c': [true, null],
      });
      expect(Json.str(2.0), '2');
      expect(Json.str(1.0e20), '1.0E20');
      expect(javaDouble(12345678.5), '1.23456785E7');
      expect(javaDouble(0.0001), '1.0E-4');
      expect(javaDouble(0.5), '0.5');
      final v = Json.parse('{"a":{"b":[{"c":7}]}}');
      expect(JsonPath.query(v, r'$.a.b[0].c'), 7);
      expect(JsonPath.query(v, 'a.b.length'), 1);
    });
  });

  group('Yml', () {
    test('dump matches SnakeYAML layout', () {
      final r = ApiRequest(
        name: 'R',
        url: 'http://x/{{id}}',
        headers: [
          const KV(name: 'A', value: 'b: c'),
          const KV(name: 'B', value: 'true', enabled: false),
        ],
        bodyMode: BodyMode.Json,
        bodyJson: '{\n  "a": 1\n}',
      );
      expect(
        OrYaml.requestText(r),
        'name: R\n'
        'seq: 1\n'
        'method: GET\n'
        'url: http://x/{{id}}\n'
        'headers:\n'
        "- name: A\n"
        "  value: 'b: c'\n"
        "- name: B\n"
        "  value: 'true'\n"
        '  enabled: false\n'
        'body:\n'
        '  type: json\n'
        '  json: |-\n'
        '    {\n'
        '      "a": 1\n'
        '    }\n',
      );
    });

    test('request round trip', () {
      final r = ApiRequest(
        name: 'Create',
        seq: 4,
        method: 'POST',
        url: 'http://x',
        params: [const KV(name: 'a', value: '1')],
        bodyMode: BodyMode.Form,
        formUrlEncoded: [const KV(name: 'k', value: 'v w')],
        auth: const Auth(mode: AuthMode.ApiKey, keyName: 'K', keyValue: 'V'),
        tests: "test('x', () => {\n  expect(1).to.equal(1);\n});",
        timeoutMs: 500,
        encodeUrl: false,
      );
      expect(
        OrYaml.parseRequest(OrYaml.requestText(r), fallbackName: 'Create'),
        r,
      );
    });
  });
}
