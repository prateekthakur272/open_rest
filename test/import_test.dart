import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/json.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  setUpAll(useTempHome);

  test('postman', () {
    const json = r'''{"info":{"name":"Pm Col","schema":"x"},"variable":[{"key":"host","value":"https://x.io"}],
          "auth":{"type":"bearer","bearer":[{"key":"token","value":"abc"}]},
          "item":[{"name":"Folder","item":[{"name":"Create","event":[{"listen":"test","script":{"exec":["pm.test('ok', function(){ pm.expect(pm.response.code).to.equal(200) })"]}}],
            "request":{"method":"POST","header":[{"key":"X-A","value":"1"}],"url":{"raw":"{{host}}/a?b=1","query":[{"key":"b","value":"1"}]},
            "body":{"mode":"raw","raw":"{\"a\":1}","options":{"raw":{"language":"json"}}}}}]},
            {"name":"Plain","request":{"method":"GET","url":"{{host}}/p"}}]}''';
    final dir = Importers.importPostman(json, tempDir('pm'));
    final col = Collections.load(dir);
    expect(col.name, 'Pm Col');
    expect(col.config.auth.mode, AuthMode.Bearer);
    expect(col.config.preVars[0].name, 'host');
    final reqs = col.allRequests();
    expect(reqs.length, 2);
    final create = reqs.firstWhere((r) => r.name == 'Create').request;
    expect(create.bodyMode, BodyMode.Json);
    expect(create.tests.contains('expect(res.status)'), isTrue);
    expect(create.params[0].name, 'b');
    expect(col.children.whereType<FolderNode>().length, 1);
  });

  test('openapi', () {
    const spec = r'''{"openapi":"3.0.0","info":{"title":"Pets"},"servers":[{"url":"https://pets.io/v1"}],
          "paths":{"/pets/{id}":{"get":{"tags":["pets"],"summary":"Get pet","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}]},
          "put":{"tags":["pets"],"operationId":"updPet","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/Pet"}}}}}}},
          "components":{"schemas":{"Pet":{"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}}}}}}''';
    final dir = Importers.importOpenApi(spec, tempDir('oa'));
    final col = Collections.load(dir);
    expect(col.environments[0].vars[0].name, 'baseUrl');
    final put = col
        .allRequests()
        .firstWhere((r) => r.request.method == 'PUT')
        .request;
    expect(put.url, '{{baseUrl}}/pets/:id');
    expect(put.bodyJson.contains('"name": "string"'), isTrue);
  });

  test('exportRoundTrip', () {
    final dir = Importers.importPostman(
      '{"info":{"name":"X"},"item":[{"name":"A","request":{"method":"GET","url":"http://a"}}]}',
      tempDir('ex'),
    );
    final out = Importers.exportPostman(Collections.load(dir));
    expect(Json.isValid(out) && out.contains('http://a'), isTrue);
  });

  test('urlSync', () {
    final ps = UrlSync.paramsFromUrl('http://a/b?x=1&y=two%20words', const []);
    expect(ps.map((k) => k.name).toList(), ['x', 'y']);
    expect(ps[1].value, 'two words');
    expect(
      UrlSync.urlWithParams('http://a/b?old=1', ps),
      'http://a/b?x=1&y=two%20words',
    );
  });

  test('envSecrets', () {
    useTempHome();
    final dir = Collections.create(tempDir('c'), 'S');
    Collections.saveEnvironment(
      dir,
      const Environment(
        name: 'dev',
        vars: [
          KV(name: 'a', value: '1'),
          KV(name: 'tok', value: 's3cret'),
        ],
        secrets: {'tok'},
      ),
    );
    expect(
      File(p.join(dir, 'environments/dev.yaml'))
          .readAsStringSync()
          .contains('s3cret'),
      isFalse,
    );
    final e = Collections.load(dir).environments[0];
    expect(e.secrets, {'tok'});
  });
}
