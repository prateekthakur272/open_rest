import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/interop/open_collection_importer.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

/// Bruno's newer YAML layout (opencollection.yml + one .yml per request).
void main() {
  setUpAll(useTempHome);

  String fixture() {
    final d = tempDir('oc');
    void w(String rel, String text) {
      final f = File(p.join(d, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }

    w(
      'opencollection.yml',
      'opencollection: 1.0.0\n\ninfo:\n  name: Demo\nbundled: false\nextensions:\n  bruno:\n    ignore:\n      - node_modules\n      - .git\n',
    );
    w('fetch sites.yml', '''
info:
  name: fetch sites
  type: http
  seq: 2

http:
  method: POST
  url: https://example.com/a
  body:
    type: json
    data: |-
      {
        "source": "dropbox"
      }
  auth: inherit

settings:
  encodeUrl: true
  timeout: 0
''');
    w('long url.yml', '''
info:
  name: long url
  type: http
  seq: 1
http:
  method: GET
  url: |-
    https://example.com/sites/10437bed
    /folders-run
  headers:
    - name: Accept
      value: application/json
    - name: X-Off
      value: "1"
      disabled: true
  params:
    - name: verbose
      value: "true"
      type: query
    - name: id
      value: "7"
      type: path
  auth:
    type: bearer
    token: '{{token}}'
runtime:
  scripts:
    - type: before-request
      code: req.setHeader('X-A', '1')
    - type: tests
      code: test('ok', () => expect(res.status).to.equal(200))
  assertions:
    - expression: res.status
      operator: eq
      value: "200"
''');
    w('Users/folder.yml', 'info:\n  name: Users\n  type: folder\n  seq: 1\n');
    w(
      'Users/get user.yml',
      'info:\n  name: get user\n  type: http\n  seq: 1\nhttp:\n  method: get\n  url: https://example.com/u\n  auth: none\n',
    );
    w(
      'environments/Local.yml',
      'name: Local\nvariables:\n  - name: baseUrl\n    value: http://localhost\n  - name: token\n    secret: true\n',
    );
    return d;
  }

  test('importsTheYamlLayoutOfABrunoCollection', () {
    final src = fixture();
    final out = tempDir('oc-out');
    expect(OpenCollectionImporter.isOpenCollection(src), isTrue);
    final dir = Importers.importBruno(
      src,
      out,
    ); // the Bruno entry point recognises the layout
    final c = Collections.load(dir);
    expect(c.name, 'Demo');
    final reqs = {for (final r in c.allRequests()) r.name: r};
    expect(reqs.keys.toSet(), {'fetch sites', 'long url', 'get user'});
    final f = reqs['fetch sites']!.request;
    expect(f.method, 'POST');
    expect(f.bodyMode, BodyMode.Json);
    expect(f.bodyJson.contains('"source": "dropbox"'), isTrue);
    expect(f.auth.mode, AuthMode.Inherit);
    final l = reqs['long url']!.request;
    expect(
      l.url.split('?').first,
      'https://example.com/sites/10437bed/folders-run',
    ); // the wrapped URL is joined
    expect(l.headers.map((h) => h.name).toList(), ['Accept', 'X-Off']);
    expect(l.headers[1].enabled, false);
    expect(l.params.singleWhere((k) => k.name == 'verbose').value, 'true');
    expect(l.pathParams.single.value, '7');
    expect(l.auth.mode, AuthMode.Bearer);
    expect(l.auth.token, '{{token}}');
    expect(l.preScript.contains('setHeader'), isTrue);
    expect(l.tests.contains("test('ok'"), isTrue);
    expect(l.assertions, [const KV(name: 'res.status', value: 'eq 200')]);
    expect(reqs['get user']!.request.method, 'GET');
    expect(c.children.whereType<FolderNode>().length, 1); // folders are kept
    final env = c.environments.singleWhere((e) => e.name == 'Local');
    expect(
      env.vars.firstWhere((v) => v.name == 'baseUrl').value,
      'http://localhost',
    );
    expect(env.secrets, {'token'});
  });

  test('theOldBruLayoutStillWorks', () {
    final src = tempDir('bru');
    File(p.join(src, 'bruno.json'))
        .writeAsStringSync('{"version":"1","name":"Old","type":"collection"}');
    File(p.join(src, 'a.bru')).writeAsStringSync(
      'meta {\n  name: a\n  type: http\n  seq: 1\n}\n\nget {\n  url: https://example.com\n  body: none\n  auth: none\n}\n',
    );
    final c = Collections.load(Importers.importBruno(src, tempDir('o')));
    expect(c.allRequests().map((r) => r.name).toList(), ['a']);
  });
}
