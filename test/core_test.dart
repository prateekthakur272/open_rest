import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/codegen/code_gen.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/script/script.dart';
import 'package:open_rest/core/storage/storage.dart';

import 'helpers.dart';

void main() {
  setUpAll(useTempHome);

  test('curlParse', () {
    final r = Importers.parseCurl(
      'curl -X POST \'https://x.io/a?b=1\' -H \'Content-Type: application/json\' -d \'{"a":1}\' -u u:p',
    )!;
    expect(r.method, 'POST');
    expect(r.bodyMode, BodyMode.Json);
    expect(r.auth.mode, AuthMode.Basic);
    expect(r.params[0].name, 'b');
  });

  test('codegen', () {
    const p = PreparedRequest(
      method: 'POST',
      url: 'https://x.io',
      headers: [('A', 'b')],
      body: BodyRaw(text: '{}', contentType: 'application/json'),
    );
    for (final l in CodeGen.languages) {
      expect(CodeGen.generate(l, p).contains('x.io'), isTrue, reason: l);
    }
  });

  test('collectionAndRun', () async {
    final tmp = tempDir('or');
    final dir = Collections.create(tmp, 'Demo');
    Collections.createRequest(
      dir,
      const ApiRequest(
        name: 'One',
        url: 'http://localhost:1/{{x}}',
        tests:
            "test('t', () => { expect(bru.getVar('q')).to.equal(undefined) })",
      ),
    );
    final col = Collections.load(dir);
    expect(col.allRequests().length, 1);
    final rc = RunCtx(col, null, {}, const AppSettings());
    final res = await Execution(rc, col.allRequests()[0]).run();
    expect(res.error, isNotNull); // connection refused
  });

  test('scripts', () async {
    final tmp = tempDir('or');
    final dir = Collections.create(tmp, 'S');
    final srv = await startServer(
      (r) => respond(
        r,
        '{"id": 7, "items": [1,2,3]}',
        headers: {'X-Echo': r.headers.value('X-Pre') ?? 'none'},
      ),
    );
    try {
      final port = srv.port;
      Collections.createRequest(
        dir,
        ApiRequest(
          name: 'R',
          url: 'http://127.0.0.1:$port/a',
          preScript: "req.setHeader('X-Pre', 'hello'); bru.setVar('k', 5)",
          postVars: const [KV(name: 'userId', value: 'res.body.id')],
          assertions: const [
            KV(name: 'res.status', value: 'eq 200'),
            KV(name: 'res.body.items', value: 'length 3'),
            KV(name: 'res.body.id', value: 'eq 8'),
          ],
          tests: "test('id', async () => { expect(res.body.id).to.equal(7); expect(res.getHeader('x-echo')).to.equal('hello'); expect(bru.getVar('userId')).to.equal('7') }); test('fails', () => { expect(1).to.equal(2) })",
        ),
      );
      final col = Collections.load(dir);
      final res = await Execution(
        RunCtx(col, null, {}, const AppSettings()),
        col.allRequests()[0],
      ).run();
      expect(res.error, isNull, reason: res.error);
      expect(res.response!.status, 200);
      final byName = {for (final t in res.tests) t.name: t};
      expect(byName['res.status: eq 200']!.passed, isTrue);
      expect(byName['res.body.items: length 3']!.passed, isTrue);
      expect(byName['res.body.id: eq 8']!.passed, isFalse);
      expect(byName['id']!.passed, isTrue, reason: byName['id']!.message);
      expect(byName['fails']!.passed, isFalse);
    } finally {
      await srv.close(force: true);
    }
  });

  test('async scripts, sleep, await and bru api', () async {
    final host = ScriptHost(
      {},
      {'a': '1'},
      {'c': 'cv'},
      {},
      'dev',
      'Coll',
      '/tmp',
      (s) => s,
    );
    final e = await ScriptEngine.create(host);
    try {
      e.setRequest(ReqView('n', 'http://x', 'GET', {'A': '1'}, '', 0, 'none'));
      final err = await e.run('''
        await bru.sleep(30);
        const v = await Promise.resolve(5);
        bru.setVar('v', v);
        bru.setEnvVar('e', 'x');
        console.log('hi', {a: 1});
        console.warn('w');
        test('async ok', async () => { await bru.sleep(10); expect(v).to.equal(5); });
        test('sync fail', () => { expect(1).to.be.above(2); });
        req.setUrl('http://y'); req.setHeader('B', '2');
        expect(bru.getEnvName()).to.equal('dev'); expect(bru.getCollectionName()).to.equal('Coll');
        expect(bru.getCollectionVar('c')).to.equal('cv'); expect(btoa('hi')).to.equal('aGk='); expect(atob('aGk=')).to.equal('hi');
      ''', syncRequest: true);
      expect(err, isNull);
      expect(host.runtime['v'], 5);
      expect(host.envVars['e'], 'x');
      expect(host.logs, ['hi {"a":1}', '[warn] w']);
      expect(host.tests.map((t) => '${t.name}:${t.passed}').toList()..sort(), [
        'async ok:true',
        'sync fail:false',
      ]);
      expect(host.req!.url, 'http://y');
      expect(host.req!.headers['B'], '2');
      final bad = await e.run('throw new Error("boom")');
      expect(bad, contains('boom'));
      expect(await e.run('let ='), isNotNull);
    } finally {
      e.close();
    }
  });

  test(
    'flutter_js prelude exists',
    () => expect(File('assets/prelude.js').existsSync(), isTrue),
  );
}
