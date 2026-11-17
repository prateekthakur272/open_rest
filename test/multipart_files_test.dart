import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';

import 'helpers.dart';

void main() {
  test(
    'several file rows with the same field name are sent as separate parts',
    () async {
      final dir = tempDir('mp');
      final a = File('$dir/one.txt')..writeAsStringSync('AAA');
      final b = File('$dir/two.txt')..writeAsStringSync('BBB');
      String? body;
      String? contentType;
      final srv = await startServer((r) async {
        contentType = r.headers.contentType?.toString();
        body = utf8.decode(await r.fold<List<int>>([], (x, y) => x..addAll(y)));
        await respond(r, '{}');
      });
      addTearDown(() => srv.close(force: true));

      final res = await HttpExecutor.execute(
        PreparedRequest(
          method: 'POST',
          url: 'http://127.0.0.1:${srv.port}/upload',
          headers: const [],
          body: BodyMultipart(
            parts: [
              const Part(name: 'title', value: 'hi', isFile: false),
              Part(name: 'files', value: a.path, isFile: true),
              Part(name: 'files', value: b.path, isFile: true),
            ],
          ),
          timeoutMs: 0,
        ),
        const AppSettings(),
      );
      expect(res.status, 200);
      expect(contentType, startsWith('multipart/form-data'));
      expect(
        RegExp('name="files"; filename="one.txt"').hasMatch(body!),
        isTrue,
      );
      expect(
        RegExp('name="files"; filename="two.txt"').hasMatch(body!),
        isTrue,
      );
      expect(body, contains('AAA'));
      expect(body, contains('BBB'));
      expect('name="files"'.allMatches(body!).length, 2);
      expect(body, contains('name="title"'));
    },
  );
}
