import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/interop/exporters.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  setUpAll(useTempHome);

  const sample = ApiRequest(
    name: 'Create user',
    seq: 2,
    method: 'POST',
    url: '{{baseUrl}}/users/:id?a=1',
    params: [
      KV(name: 'a', value: '1'),
      KV(name: 'off', value: 'x', enabled: false),
    ],
    pathParams: [KV(name: 'id', value: '5')],
    headers: [
      KV(name: 'X-A', value: 'b: c'),
      KV(name: 'X-Off', value: 'c', enabled: false),
    ],
    bodyMode: BodyMode.Json,
    bodyJson: '{\n  "name": "Ada",\n  "n": 1\n}',
    bodyText: 'note: with colon',
    multipart: [
      KV(name: 'f', value: '/tmp/x', isFile: true, contentType: 'text/plain'),
      KV(name: 't', value: 'v'),
    ],
    auth: Auth(mode: AuthMode.Bearer, token: 'tok'),
    preVars: [KV(name: 'a', value: 'true')],
    postVars: [KV(name: 'id', value: 'res.body.id')],
    assertions: [KV(name: 'res.status', value: 'eq 201')],
    preScript: "bru.setVar('x', 1);\n  // indented",
    tests: "test('x', () => {\n  expect(1).to.equal(1);\n});",
    docs: '# Title\n\ntext',
    timeoutMs: 5000,
    encodeUrl: false,
  );

  Collection collection() {
    useTempHome();
    final dir = Collections.create(tempDir('c'), 'Shop API');
    Collections.saveCollectionConfig(
      dir,
      const NodeConfig(
        name: 'Shop API',
        auth: Auth(mode: AuthMode.Bearer, token: 'root'),
        preVars: [KV(name: 'version', value: 'v1')],
        docs: 'hello',
      ),
    );
    Collections.saveEnvironment(
      dir,
      const Environment(
        name: 'dev',
        vars: [
          KV(name: 'baseUrl', value: 'https://api.shop.io/v1'),
          KV(name: 'key', value: 's3'),
        ],
        secrets: {'key'},
      ),
    );
    final f = Collections.createFolder(dir, 'Users');
    Collections.saveFolderConfig(
      f,
      const NodeConfig(
        name: 'Users',
        seq: 1,
        headers: [KV(name: 'X-F', value: '1')],
      ),
    );
    Collections.createRequest(f, sample);
    Collections.createRequest(
      dir,
      const ApiRequest(name: 'Ping', url: '{{baseUrl}}/ping'),
    );
    return Collections.load(dir);
  }

  test('yamlRoundTrip', () {
    expect(
      OrYaml.mapToRequest(Yml.parse(OrYaml.requestText(sample)) as Map),
      sample,
    );
  });

  test('collectionOnDisk', () {
    final c = collection();
    expect(c.name, 'Shop API');
    expect(c.config.auth.mode, AuthMode.Bearer);
    expect(c.config.preVars[0].value, 'v1');
    expect(c.allRequests().length, 2);
    expect(c.environments[0].secrets, {'key'});
    expect(
      c.children.whereType<FolderNode>().first.config.headers[0].name,
      'X-F',
    );
    expect(File(p.join(c.path, 'openrest.yaml')).existsSync(), isTrue);
  });

  test('allFormats', () {
    final c = collection();
    final out = tempDir('exp');
    for (final f in Exporters.formats) {
      final dest = f.isDirectory ? out : p.join(out, 'x${f.ext}');
      final written = Exporters.export(f.id, c, dest);
      expect(
        FileSystemEntity.typeSync(written) != FileSystemEntityType.notFound,
        isTrue,
        reason: f.id,
      );
      if (!f.isDirectory) {
        expect(
          File(written).readAsStringSync().trim().isNotEmpty,
          isTrue,
          reason: f.id,
        );
      }
    }
    final oa = Yml.parse(
      File(p.join(out, 'x.openapi.yaml')).readAsStringSync(),
    ) as Map;
    final paths = oa['paths'] as Map;
    expect(
      paths.containsKey('/users/{id}'),
      isTrue,
      reason: paths.keys.toString(),
    );
    expect(paths.containsKey('/ping'), isTrue);
    expect(
      ((oa['servers'] as List)[0] as Map)['url'],
      'https://api.shop.io/v1',
    );
    expect(
      Json.isValid(File(p.join(out, 'x.openapi.json')).readAsStringSync()),
      isTrue,
    );
    expect(
      Json.isValid(File(p.join(out, 'x.insomnia.json')).readAsStringSync()),
      isTrue,
    );
    final http = File(p.join(out, 'x.http')).readAsStringSync();
    expect(
      http.contains('POST https://') || http.contains('POST {{baseUrl}}'),
      isTrue,
    );
  });

  test('bundleRoundTrip', () {
    final c = collection();
    final f = p.join(tempDir('b'), 'b.yaml');
    Exporters.export('bundle', c, f);
    final back = Collections.load(
      Importers.importBundle(File(f).readAsStringSync(), tempDir('bi')),
    );
    List<ApiRequest> norm(Collection x) =>
        (x.allRequests().map((r) => r.request.copyWith(seq: 0)).toList()
          ..sort((a, b) => a.name.compareTo(b.name)));
    expect(norm(back), norm(c));
    expect(back.config.auth, c.config.auth);
    expect(back.environments.length, 1);
  });

  test('brunoRoundTrip', () {
    final c = collection();
    final out = tempDir('br');
    final bru = Exporters.export('bruno', c, out);
    expect(File(p.join(bru, 'bruno.json')).existsSync(), isTrue);
    final back = Collections.load(Importers.importBruno(bru, tempDir('brin')));
    expect(back.allRequests().length, 2);
    final r = back
        .allRequests()
        .firstWhere((x) => x.name == 'Create user')
        .request;
    expect(
      r.headers,
      sample
          .copyWith(seq: r.seq, bodyText: r.bodyText, params: r.params)
          .headers,
    );
    expect(r.auth.token, 'tok');
    expect(r.bodyMode, BodyMode.Json);
    expect(back.config.auth.mode, AuthMode.Bearer);
  });

  test('openApiRoundTrip', () {
    final c = collection();
    final f = p.join(tempDir('o'), 'o.yaml');
    Exporters.export('openapi-yaml', c, f);
    final back = Collections.load(
      Importers.importOpenApi(File(f).readAsStringSync(), tempDir('oi')),
    );
    expect(back.allRequests().length, 2);
  });
}
