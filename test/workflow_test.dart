import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_storage.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/run/workflow_builder.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/yml.dart';

import 'helpers.dart';

Future<HttpServer> server() => startServer((r) async {
  final path = r.uri.path;
  final body = path == '/login'
      ? '{"token":"abc123","user":{"id":7},"roles":["a","b"]}'
      : '{"path":"$path","auth":"${r.headers.value('X-Auth') ?? ''}","echo":"${r.headers.value('X-Echo') ?? ''}"}';
  await respond(
    r,
    body,
    status: path == '/missing' ? 404 : 200,
    headers: {'X-Trace': 't-1'},
  );
});

Map<String, dynamic> echo(StepRun r) =>
    Json.obj(Json.parse(r.result!.response!.text))!;

Future<List<StepRun>> runWf(Collection col, Workflow wf) async {
  final runs = <StepRun>[];
  await WorkflowRunner.run(
    RunCtx(col, null, {}, const AppSettings()),
    wf,
    () => false,
    (_) {},
    runs.add,
  );
  return runs;
}

void main() {
  setUpAll(useTempHome);

  test('inputsFlowBetweenSteps', () async {
    final srv = await server();
    final base = 'http://127.0.0.1:${srv.port}';
    try {
      final dir = Collections.create(tempDir('wf'), 'W');
      Collections.createRequest(
        dir,
        ApiRequest(name: 'Login', method: 'POST', url: '$base/login'),
      );
      Collections.createRequest(
        dir,
        ApiRequest(
          name: 'Profile',
          url: '$base/users/{{uid}}',
          headers: const [
            KV(name: 'X-Echo', value: '{{st}}|{{trace}}|{{first_role}}'),
          ],
        ),
      );
      final col = Collections.load(dir);
      final login = col.allRequests().firstWhere((r) => r.name == 'Login');
      final profile = col.allRequests().firstWhere((r) => r.name == 'Profile');
      final wf = Workflow(
        name: 'Flow',
        steps: [
          WorkflowStep(id: 's1', request: col.requestRef(login)),
          WorkflowStep(
            id: 's2',
            request: col.requestRef(profile),
            inputs: const [
              StepInput(
                target: InputTarget.Variable,
                name: 'uid',
                value: '{{s1.body.user.id}}',
              ),
              StepInput(
                target: InputTarget.Variable,
                name: 'st',
                value: '{{s1.status}}',
              ),
              StepInput(
                target: InputTarget.Variable,
                name: 'trace',
                value: '{{s1.header.x-trace}}',
              ),
              StepInput(
                target: InputTarget.Variable,
                name: 'first_role',
                value: '{{s1.body.roles[1]}}',
              ),
              StepInput(
                target: InputTarget.Header,
                name: 'X-Auth',
                value: 'Bearer {{s1.body.token}}',
              ),
            ],
          ),
        ],
      );
      WorkflowStore.save(dir, wf);
      final loaded = Collections.load(dir);
      expect(loaded.workflows.single, wf);

      final runs = await runWf(loaded, loaded.workflows[0]);
      expect(runs.length, 2);
      expect(runs.every((r) => !r.failed), isTrue, reason: runs.toString());
      final body = echo(runs[1]);
      expect(body['path'], '/users/7');
      expect(body['auth'], 'Bearer abc123');
      expect(body['echo'], '200|t-1|b');
    } finally {
      await srv.close(force: true);
    }
  });

  test('everyTargetAndManyStepsIntoOneRequest', () async {
    final srv = await server();
    final base = 'http://127.0.0.1:${srv.port}';
    try {
      final dir = Collections.create(tempDir('wf'), 'W');
      Collections.createRequest(
        dir,
        ApiRequest(name: 'A', method: 'POST', url: '$base/login'),
      );
      Collections.createRequest(dir, ApiRequest(name: 'B', url: '$base/other'));
      Collections.createRequest(
        dir,
        ApiRequest(
          name: 'Target',
          method: 'POST',
          url: '$base/items/:item?x=1',
          bodyMode: BodyMode.Json,
          bodyJson: '{"keep":true,"user":{"name":"n"}}',
        ),
      );
      final col = Collections.load(dir);
      String ref(String n) =>
          col.requestRef(col.allRequests().firstWhere((r) => r.name == n));
      final wf = Workflow(
        name: 'Many',
        steps: [
          WorkflowStep(id: 's1', request: ref('A')),
          WorkflowStep(id: 's2', request: ref('B')),
          WorkflowStep(
            id: 's3',
            request: ref('Target'),
            inputs: const [
              StepInput(
                target: InputTarget.PathParam,
                name: 'item',
                value: '{{s1.body.user.id}}',
              ),
              StepInput(
                target: InputTarget.PathAppend,
                name: '',
                value: '{{s2.status}}',
              ),
              StepInput(
                target: InputTarget.Query,
                name: 'who',
                value: '{{s1.body.token}}-{{s2.status}}',
              ), // two steps, one value
              StepInput(
                target: InputTarget.Bearer,
                name: '',
                value: '{{s1.body.token}}',
              ),
              StepInput(
                target: InputTarget.Body,
                name: 'user.id',
                value: '{{s1.body.user.id}}',
              ),
              StepInput(target: InputTarget.Body, name: 'list[1]', value: 'x'),
            ],
          ),
        ],
      );
      final runs = await runWf(col, wf);
      expect(runs.length, 3);
      expect(runs.every((r) => !r.failed), isTrue, reason: runs.toString());
      final res = runs[2].result!;
      expect(res.request!.method, 'POST');
      expect(
        res.request!.url.endsWith('/items/7/200?x=1&who=abc123-200'),
        isTrue,
        reason: res.request!.url,
      );
      expect(
        res.request!.headers.any(
          (h) => h.$1 == 'Authorization' && h.$2 == 'Bearer abc123',
        ),
        isTrue,
        reason: res.request!.headers.toString(),
      );
      final sent = Json.obj(Json.parse((res.request!.body as BodyRaw).text))!;
      expect(sent['keep'], true);
      expect(Json.obj(sent['user'])!['name'], 'n');
      expect(
        (Json.obj(sent['user'])!['id'] as num).toInt(),
        7,
      ); // typed as a number, not "7"
      expect(sent['list'], [null, 'x']);
      // the stored request is untouched
      expect(
        Collections.load(dir)
            .allRequests()
            .firstWhere((r) => r.name == 'Target')
            .request
            .bodyJson,
        '{"keep":true,"user":{"name":"n"}}',
      );
    } finally {
      await srv.close(force: true);
    }
  });

  test('tokensWorkDirectlyInTheRequest', () async {
    final srv = await server();
    final base = 'http://127.0.0.1:${srv.port}';
    try {
      final dir = Collections.create(tempDir('wf'), 'W');
      Collections.createRequest(
        dir,
        ApiRequest(name: 'A', method: 'POST', url: '$base/login'),
      );
      Collections.createRequest(
        dir,
        ApiRequest(
          name: 'B',
          url: '$base/users/{{s1.body.user.id}}',
          headers: const [KV(name: 'X-Auth', value: 't={{s1.body.token}}')],
        ),
      );
      final col = Collections.load(dir);
      String ref(String n) =>
          col.requestRef(col.allRequests().firstWhere((r) => r.name == n));
      final runs = await runWf(
        col,
        Workflow(
          name: 't',
          steps: [
            WorkflowStep(id: 's1', request: ref('A')),
            WorkflowStep(id: 's2', request: ref('B')),
          ],
        ),
      );
      final body = echo(runs[1]);
      expect(body['path'], '/users/7');
      expect(body['auth'], 't=abc123');
    } finally {
      await srv.close(force: true);
    }
  });

  test('oldInputFormatStillLoads', () {
    final m = Yml.parse('''
name: Old
steps:
  - id: s1
    request: a.yaml
  - id: s2
    request: b.yaml
    inputs:
      - name: tok
        from: s1
        source: field
        path: data.token
''') as Map;
    final wf = WorkflowIO.fromMap(m, 'x');
    expect(
      wf.steps[1].inputs.single,
      const StepInput(
        target: InputTarget.Variable,
        name: 'tok',
        value: '{{s1.body.data.token}}',
      ),
    );
  });

  test('fullResponseAndMissingValues', () {
    final resp = ExecResult(
      response: HttpResult(
        status: 201,
        headers: const [('A', 'b')],
        body: Uint8List.fromList('{"k":[1,2]}'.codeUnits),
        timeMs: 5,
      ),
    );
    final full = Json.obj(
      Json.parse(WorkflowRunner.resolve('s1.response', resp).$1),
    )!;
    expect((full['status'] as num).toInt(), 201);
    expect(Json.stringify(full['body']), '{"k":[1,2]}');
    final (v, warn) = WorkflowRunner.resolve('s1.body.nope.deep', resp);
    expect(v, '');
    expect(warn, isNotNull);
    expect(WorkflowRunner.resolve('s1.body.x', null).$2, isNotNull);
    expect(WorkflowRunner.resolve('s1.wat', resp).$2, isNotNull);
    expect(WorkflowRunner.resolve('s1.body', resp).$1, '{"k":[1,2]}');
    expect(WorkflowRunner.isStepRef('s12.body.x'), isTrue);
    expect(WorkflowRunner.isStepRef('baseUrl'), isFalse);
  });

  test('stopsOnFailureAndFlagsBadReferences', () async {
    final srv = await server();
    final base = 'http://127.0.0.1:${srv.port}';
    try {
      final dir = Collections.create(tempDir('wf'), 'W');
      Collections.createRequest(
        dir,
        const ApiRequest(name: 'Bad', url: 'http://127.0.0.1:1/x'),
      );
      Collections.createRequest(dir, ApiRequest(name: 'Ok', url: '$base/ok'));
      final col = Collections.load(dir);
      final bad = col.requestRef(
        col.allRequests().firstWhere((r) => r.name == 'Bad'),
      );
      final ok = col.requestRef(
        col.allRequests().firstWhere((r) => r.name == 'Ok'),
      );
      var runs = await runWf(
        col,
        Workflow(
          name: 'a',
          steps: [
            WorkflowStep(id: 's1', request: bad),
            WorkflowStep(id: 's2', request: ok),
          ],
        ),
      );
      expect(runs.length, 1); // stopped after the failing step
      runs = await runWf(
        col,
        Workflow(
          name: 'a',
          steps: [
            WorkflowStep(id: 's1', request: bad),
            WorkflowStep(id: 's2', request: ok),
          ],
          stopOnFail: false,
        ),
      );
      expect(runs.length, 2);
      // forward reference (source step runs later) is rejected, disabled steps are skipped, missing requests reported
      runs = await runWf(
        col,
        Workflow(
          name: 'a',
          stopOnFail: false,
          steps: [
            WorkflowStep(
              id: 's1',
              request: ok,
              inputs: const [
                StepInput(
                  target: InputTarget.Variable,
                  name: 'v',
                  value: '{{s2.status}}',
                ),
              ],
            ),
            WorkflowStep(id: 's2', request: ok, enabled: false),
            const WorkflowStep(id: 's3', request: 'gone.yaml'),
          ],
        ),
      );
      expect(runs.length, 2);
      expect(
        runs[0].notes.single.contains('not run yet'),
        isTrue,
        reason: runs[0].notes.toString(),
      );
      expect(runs[1].node, isNull);
      expect(runs[1].failed, isTrue);
    } finally {
      await srv.close(force: true);
    }
  });

  test('renameAndDelete', () {
    final dir = Collections.create(tempDir('wf'), 'W');
    WorkflowStore.save(dir, const Workflow(name: 'One'));
    WorkflowStore.save(dir, const Workflow(name: 'Two'));
    expect(
      () => WorkflowStore.save(dir, const Workflow(name: 'Two'), 'One'),
      throwsArgumentError,
    );
    WorkflowStore.save(dir, const Workflow(name: 'Three'), 'One');
    expect(WorkflowStore.load(dir).map((w) => w.name).toList(), [
      'Three',
      'Two',
    ]);
    WorkflowStore.delete(dir, 'Two');
    expect(WorkflowStore.load(dir).map((w) => w.name).toList(), ['Three']);
    expect(
      Collections.load(dir).children.isEmpty,
      isTrue,
    ); // workflows are not treated as requests
  });

  test('slotsListWhatARequestCanBeFilledWith', () {
    const req = ApiRequest(
      url: 'http://h/orders/:orderId/items/:itemId?page=1',
      params: [KV(name: 'sort', value: 'asc')],
      pathParams: [KV(name: 'itemId', value: '9')],
      headers: [
        KV(name: 'X-Trace', value: 't'),
        KV(name: 'Off', value: 'x', enabled: false),
      ],
      bodyMode: BodyMode.Json,
      bodyJson: '{"user":{"id":1,"tags":["a","b"]},"note":"hi"}',
      auth: Auth(mode: AuthMode.Bearer, token: 'tok'),
    );
    final slots = Slots.of(req)
        .map((s) => (s.target, s.name, s.current))
        .toList();
    bool has(InputTarget t, String n, String c) => slots.contains((t, n, c));
    expect(has(InputTarget.PathParam, 'orderId', ''), isTrue);
    expect(has(InputTarget.PathParam, 'itemId', '9'), isTrue);
    expect(
      has(InputTarget.Query, 'page', '1') &&
          has(InputTarget.Query, 'sort', 'asc'),
      isTrue,
    );
    expect(
      slots.any((s) => s.$1 == InputTarget.Header && s.$2 == 'X-Trace') &&
          slots.every((s) => s.$2 != 'Off'),
      isTrue,
    );
    expect(
      has(InputTarget.Body, 'user.id', '1') &&
          has(InputTarget.Body, 'user.tags[1]', 'b') &&
          has(InputTarget.Body, 'note', 'hi'),
      isTrue,
    );
    expect(has(InputTarget.Bearer, '', 'tok'), isTrue);
  });

  test('friendlyTextHidesIdsAndBraces', () {
    const steps = [
      WorkflowStep(id: 's1', request: 'a.yaml'),
      WorkflowStep(id: 's2', request: 'b.yaml'),
    ];
    String name(WorkflowStep st) => st.id == 's1' ? 'Login' : 'Create';
    expect(Slots.friendly('{{s1.body.token}}', steps, name), '[Login › token]');
    expect(
      Slots.friendly('Bearer {{s1.body.token}}-{{s2.status}}', steps, name),
      'Bearer [Login › token]-[Create › status code]',
    );
    expect(
      Slots.friendly('{{s1.header.X-Id}}', steps, name),
      '[Login › header X-Id]',
    );
    expect(
      Slots.friendly('plain {{baseUrl}}', steps, name),
      'plain {{baseUrl}}',
    );
  });
}
