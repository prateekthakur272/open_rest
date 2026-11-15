import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_storage.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/run/workflow_builder.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/json.dart';

import 'helpers.dart';

Future<HttpServer> server() => startServer((r) async {
  final path = r.uri.path;
  final body = path == '/list'
      ? '{"items":[{"id":1,"price":10.5,"name":"a"},{"id":2,"price":5,"name":"b"},{"id":3,"price":7,"name":"c"}],"empty":[]}'
      : '{"path":"$path","q":"${r.uri.query}"}';
  await respond(r, body);
});

class Fixture {
  Collection col;
  final String base;
  final HttpServer srv;
  Fixture(this.col, this.base, this.srv);

  String ref(String n) =>
      col.requestRef(col.allRequests().firstWhere((r) => r.name == n));

  Future<(List<StepRun>, List<RunEvent>)> run(
    Workflow wf, {
    String? stopAfter,
  }) async {
    final runs = <StepRun>[];
    final events = <RunEvent>[];
    await WorkflowRunner.run(
      RunCtx(col, null, {}, const AppSettings()),
      wf,
      () => false,
      (_) {},
      runs.add,
      events.add,
      stopAfter,
    );
    return (runs, events);
  }
}

Future<void> fixture(Future<void> Function(Fixture f) block) async {
  final srv = await server();
  final base = 'http://127.0.0.1:${srv.port}';
  try {
    final dir = Collections.create(tempDir('wfl'), 'W');
    Collections.createRequest(dir, ApiRequest(name: 'List', url: '$base/list'));
    Collections.createRequest(
      dir,
      ApiRequest(name: 'Item', url: '$base/item/:id'),
    );
    await block(Fixture(Collections.load(dir), base, srv));
  } finally {
    await srv.close(force: true);
  }
}

WorkflowStep step(
  String id,
  String ref, [
  List<StepInput> inputs = const [],
  List<StepOutput> outputs = const [],
]) => WorkflowStep(id: id, request: ref, inputs: inputs, outputs: outputs);
List<String> texts(List<RunEvent> e) => e.map((x) => x.text).toList();
StepInput inp(InputTarget t, String n, String v) =>
    StepInput(target: t, name: n, value: v);
Map<String, dynamic> bodyOf(StepRun r) =>
    Json.obj(Json.parse(r.result!.response!.text))!;

void main() {
  setUpAll(useTempHome);

  test(
    'forEachCountSumAndIf',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List')),
          const WorkflowStep(
            id: 's2',
            kind: StepKind.Set,
            setOp: SetOp.Count,
            varName: 'count',
            list: '{{s1.body.items}}',
          ),
          const WorkflowStep(
            id: 's3',
            kind: StepKind.Set,
            setOp: SetOp.Sum,
            varName: 'total',
            list: '{{s1.body.items}}',
            path: 'price',
          ),
          WorkflowStep(
            id: 's4',
            kind: StepKind.Loop,
            loop: LoopMode.ForEach,
            list: '{{s1.body.items}}',
            children: [
              step('s5', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '{{item.id}}'),
                inp(InputTarget.Query, 'n', '{{index}}-{{item.name}}'),
              ]),
            ],
          ),
          const WorkflowStep(
            id: 's6',
            kind: StepKind.If,
            conditions: [
              Condition(left: '{{count}}', op: CondOp.Gt, right: '2'),
            ],
            children: [
              WorkflowStep(
                id: 's7',
                kind: StepKind.Set,
                varName: 'size',
                value: 'many',
              ),
            ],
            otherwise: [
              WorkflowStep(
                id: 's8',
                kind: StepKind.Set,
                varName: 'size',
                value: 'few',
              ),
            ],
          ),
        ],
      );
      final (runs, events) = await f.run(wf);
      final items = runs.where((r) => r.step.id == 's5').toList();
      expect(items.length, 3);
      expect(items.map((r) => r.iteration).toList(), [1, 2, 3]);
      expect(items.map((r) => bodyOf(r)['path']).toList(), [
        '/item/1',
        '/item/2',
        '/item/3',
      ]);
      expect(items.map((r) => bodyOf(r)['q']).toList(), [
        'n=0-a',
        'n=1-b',
        'n=2-c',
      ]);
      final t = texts(events);
      expect(
        t.any((x) => x.contains('count = 3')),
        isTrue,
        reason: t.toString(),
      );
      expect(
        t.any((x) => x.contains('total = 22.5')),
        isTrue,
        reason: t.toString(),
      );
      expect(t.any((x) => x.contains('→ then')), isTrue, reason: t.toString());
      expect(
        t.any((x) => x.contains('size = many')) &&
            t.every((x) => !x.contains('size = few')),
        isTrue,
        reason: t.toString(),
      );
    }),
  );

  test(
    'ifElseTakesTheOtherBranchAndAnyAll',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List')),
          const WorkflowStep(
            id: 's2',
            kind: StepKind.If,
            conditions: [
              Condition(left: '{{s1.status}}', op: CondOp.Eq, right: '500'),
              Condition(
                left: '{{s1.body.items[0].name}}',
                op: CondOp.Contains,
                right: 'A',
              ),
            ],
            matchAll: false,
            children: [
              WorkflowStep(
                id: 's3',
                kind: StepKind.Set,
                varName: 'r',
                value: 'any-hit',
              ),
            ],
            otherwise: [
              WorkflowStep(
                id: 's4',
                kind: StepKind.Set,
                varName: 'r',
                value: 'miss',
              ),
            ],
          ),
          const WorkflowStep(
            id: 's5',
            kind: StepKind.If,
            conditions: [
              Condition(left: '{{s1.status}}', op: CondOp.Eq, right: '200'),
              Condition(left: '{{s1.body.empty}}', op: CondOp.NotEmpty),
            ],
            matchAll: true,
            children: [
              WorkflowStep(
                id: 's6',
                kind: StepKind.Set,
                varName: 'r2',
                value: 'yes',
              ),
            ],
            otherwise: [
              WorkflowStep(
                id: 's7',
                kind: StepKind.Set,
                varName: 'r2',
                value: 'no',
              ),
            ],
          ),
        ],
      );
      final t = texts((await f.run(wf)).$2);
      expect(
        t.any((x) => x.contains('r = any-hit')),
        isTrue,
        reason: t.toString(),
      ); // 'A' matches 'a' case-insensitively
      expect(
        t.any((x) => x.contains('r2 = no')),
        isTrue,
        reason: t.toString(),
      ); // empty list is "empty"
    }),
  );

  test(
    'repeatWhileBreakAndStop',
    () => fixture((f) async {
      final repeat = Workflow(
        name: 'w',
        steps: [
          WorkflowStep(
            id: 's1',
            kind: StepKind.Loop,
            loop: LoopMode.Repeat,
            count: '2',
            children: [
              step('s2', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '{{index}}'),
              ]),
            ],
          ),
        ],
      );
      expect((await f.run(repeat)).$1.map((r) => r.iteration - 1).toList(), [
        0,
        1,
      ]);

      final whileLoop = Workflow(
        name: 'w',
        steps: [
          WorkflowStep(
            id: 's1',
            kind: StepKind.Loop,
            loop: LoopMode.While,
            conditions: const [
              Condition(left: '{{index}}', op: CondOp.Lt, right: '3'),
            ],
            children: [
              step('s2', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', 'x'),
              ]),
            ],
          ),
        ],
      );
      expect((await f.run(whileLoop)).$1.length, 3);

      final capped = Workflow(
        name: 'w',
        steps: [
          WorkflowStep(
            id: 's1',
            kind: StepKind.Loop,
            loop: LoopMode.While,
            maxIterations: 4,
            conditions: const [Condition(left: '1', op: CondOp.Eq, right: '1')],
            children: [
              step('s2', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', 'x'),
              ]),
            ],
          ),
        ],
      );
      final (cr, ce) = await f.run(capped);
      expect(cr.length, 4);
      expect(texts(ce).any((x) => x.contains('limit')), isTrue);

      // break out of a loop on the second round, then keep going after the loop
      final brk = Workflow(
        name: 'w',
        steps: [
          step('s0', f.ref('List')),
          WorkflowStep(
            id: 's1',
            kind: StepKind.Loop,
            list: '{{s0.body.items}}',
            children: [
              step('s2', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '{{item.id}}'),
              ]),
              const WorkflowStep(
                id: 's3',
                kind: StepKind.If,
                conditions: [
                  Condition(left: '{{item.id}}', op: CondOp.Eq, right: '2'),
                ],
                children: [
                  WorkflowStep(
                    id: 's4',
                    kind: StepKind.Stop,
                    stopScope: StopScope.Loop,
                  ),
                ],
              ),
            ],
          ),
          step('s5', f.ref('Item'), [
            inp(InputTarget.PathParam, 'id', 'after'),
          ]),
        ],
      );
      final (br, _) = await f.run(brk);
      expect(br.map((r) => r.step.id).toList(), ['s0', 's2', 's2', 's5']);

      // stopping the workflow ends everything, and marks failure in the log
      final stop = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List')),
          const WorkflowStep(
            id: 's2',
            kind: StepKind.Stop,
            stopFail: true,
            value: 'no stock',
          ),
          step('s3', f.ref('List')),
        ],
      );
      final (sr, se) = await f.run(stop);
      expect(sr.length, 1);
      expect(se.last.text.contains('no stock') && !se.last.ok, isTrue);
    }),
  );

  test(
    'notAListAndMissingReferencesAreReportedNotCrashing',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List')),
          WorkflowStep(
            id: 's2',
            kind: StepKind.Loop,
            list: '{{s1.body.items[0].name}}',
            children: [
              step('s3', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '1'),
              ]),
            ],
          ),
          const WorkflowStep(
            id: 's4',
            kind: StepKind.Set,
            setOp: SetOp.Count,
            varName: 'n',
            list: '{{s9.body.x}}',
          ),
          WorkflowStep(
            id: 's5',
            kind: StepKind.Loop,
            list: '{{s1.body.empty}}',
            children: [
              step('s6', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '1'),
              ]),
            ],
          ),
        ],
      );
      final (runs, events) = await f.run(wf);
      expect(runs.length, 1); // nothing from the loops
      final t = texts(events);
      expect(
        t.any((x) => x.contains('is not a list')),
        isTrue,
        reason: t.toString(),
      );
      expect(t.any((x) => x.contains('n = 0')), isTrue, reason: t.toString());
      expect(
        t.any((x) => x.contains('for each of 0 items')),
        isTrue,
        reason: t.toString(),
      );
    }),
  );

  test(
    'customisingEveryPartOfARequest',
    () => fixture((f) async {
      Collections.createRequest(
        f.col.path,
        ApiRequest(
          name: 'Echo',
          method: 'POST',
          url: '${f.base}/echo/:kind?keep=1',
          bodyMode: BodyMode.Json,
          bodyJson: '{"a":1}',
          headers: const [KV(name: 'X-A', value: '1')],
        ),
      );
      f.col = Collections.load(f.col.path);
      Future<PreparedRequest> go(List<StepInput> i) async => (await f.run(
        Workflow(name: 'w', steps: [step('s1', f.ref('Echo'), i)]),
      )).$1.single.result!.request!;
      expect((await go([inp(InputTarget.Method, '', 'put')])).method, 'PUT');
      expect(
        (await go([inp(InputTarget.Url, '', '${f.base}/other')])).url
            .endsWith('/other'),
        isTrue,
      );
      expect(
        (await go([inp(InputTarget.PathParam, 'kind', 'k1')])).url
            .contains('/echo/k1?keep=1'),
        isTrue,
      );
      expect(
        (await go([inp(InputTarget.Query, 'page', '2')])).url
            .endsWith('keep=1&page=2'),
        isTrue,
      );
      expect(
        (await go([inp(InputTarget.Header, 'x-a', '9')])).headers
            .firstWhere((h) => h.$1.toLowerCase() == 'x-a')
            .$2,
        '9',
      );
      expect(
        Json.stringify(
          Json.parse(
            ((await go([inp(InputTarget.BodyRaw, '', '{"z": true}')])).body
                    as BodyRaw)
                .text,
          ),
        ),
        '{"z":true}',
      );
      expect(
        (Json.obj(
                  Json.parse(
                    ((await go([inp(InputTarget.Body, 'a', '2')])).body
                            as BodyRaw)
                        .text,
                  ),
                )!['a']
                as num)
            .toInt(),
        2,
      );
      // blank values never override the request
      expect((await go([inp(InputTarget.Method, '', '')])).method, 'POST');
    }),
  );

  test(
    'runToHereStopsAfterThatBlock',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List')),
          step('s2', f.ref('List')),
          step('s3', f.ref('List')),
        ],
      );
      expect(
        (await f.run(wf, stopAfter: 's2')).$1.map((r) => r.step.id).toList(),
        ['s1', 's2'],
      );
    }),
  );

  test('treeHelpersAndFileRoundTrip', () {
    final wf = Workflow(
      name: 'tree',
      stopOnFail: false,
      description: 'd',
      steps: [
        WorkflowStep(
          id: 's1',
          request: 'a.yaml',
          inputs: [inp(InputTarget.Header, 'X', '{{s1.status}}')],
          continueOnFail: true,
          title: 'First',
        ),
        WorkflowStep(
          id: 's2',
          kind: StepKind.If,
          conditions: const [
            Condition(left: '{{s1.status}}', op: CondOp.Gte, right: '200'),
            Condition(left: 'a', op: CondOp.Empty),
          ],
          matchAll: false,
          children: [
            const WorkflowStep(id: 's3', request: 'b.yaml'),
            const WorkflowStep(
              id: 's4',
              kind: StepKind.Loop,
              loop: LoopMode.Repeat,
              count: '3',
              maxIterations: 9,
              itemVar: 'x',
              indexVar: 'i',
              children: [
                WorkflowStep(id: 's5', kind: StepKind.Wait, value: '10'),
              ],
            ),
          ],
          otherwise: const [
            WorkflowStep(
              id: 's6',
              kind: StepKind.Set,
              setOp: SetOp.Sum,
              varName: 't',
              list: '{{x}}',
              path: 'p',
            ),
            WorkflowStep(
              id: 's7',
              kind: StepKind.Stop,
              stopScope: StopScope.Loop,
              stopFail: true,
              value: 'bad',
              enabled: false,
            ),
          ],
        ),
      ],
    );
    final dir = tempDir('wfio');
    WorkflowStore.save(dir, wf);
    expect(WorkflowStore.load(dir).single, wf);

    expect(wf.steps.walk().map((s) => s.id).toList(), [
      's1',
      's2',
      's3',
      's4',
      's5',
      's6',
      's7',
    ]);
    expect(newStepId(wf.steps), 's8');
    expect(wf.steps.requestsBefore('s4').map((s) => s.id).toList(), [
      's1',
      's3',
    ]);
    expect(wf.steps.variablesBefore('s5').toSet(), {
      'i',
    }); // a Repeat loop only has its index
    expect(wf.steps.variablesBefore('s6'), ['i']);
    expect(wf.steps.removeStep('s3').map((s) => s.id).take(2).toList(), [
      's1',
      's2',
    ]);
    expect(wf.steps.removeStep('s5').findStep('s5'), isNull);
    final added = wf.steps.addStep(
      's2',
      1,
      const WorkflowStep(id: 's9', kind: StepKind.Wait),
    );
    expect(added.findStep('s2')!.otherwise.map((s) => s.id).toList(), [
      's6',
      's7',
      's9',
    ]);
    expect(
      wf.steps
          .moveStep('s7', -1)
          .findStep('s2')!
          .otherwise
          .map((s) => s.id)
          .toList(),
      ['s7', 's6'],
    );
    expect(
      wf.steps.moveStep('s1', -1).map((s) => s.id).toList(),
      wf.steps.map((s) => s.id).toList(),
    ); // already first
    expect(
      wf.steps
          .mapStep('s5', (s) => s.copyWith(title: 'renamed'))
          .findStep('s5')!
          .title,
      'renamed',
    );
  });

  test(
    'namedOutputsAreConfiguredOnTheProducerAndUsedByName',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        stopOnFail: false,
        steps: [
          step('s1', f.ref('List'), const [], const [
            StepOutput(
              name: 'firstId',
              kind: SourceKind.Field,
              path: 'items[0].id',
            ),
            StepOutput(name: 'all', kind: SourceKind.Field, path: 'items'),
            StepOutput(name: 'code', kind: SourceKind.Status),
            StepOutput(
              name: 'ctype',
              kind: SourceKind.Header,
              path: 'content-type',
            ),
            StepOutput(name: 'whole', kind: SourceKind.Body),
            StepOutput(
              name: 'nope',
              kind: SourceKind.Field,
              path: 'missing.deep',
            ),
          ]),
          step('s2', f.ref('Item'), [
            inp(InputTarget.PathParam, 'id', '{{s1.out.firstId}}'),
            inp(InputTarget.Query, 'c', '{{s1.out.code}}-{{s1.out.ctype}}'),
            inp(InputTarget.Header, 'X-Missing', '{{s1.out.unknown}}'),
          ]),
          const WorkflowStep(
            id: 's3',
            kind: StepKind.Set,
            setOp: SetOp.Count,
            varName: 'n',
            list: '{{s1.out.all}}',
          ),
          WorkflowStep(
            id: 's4',
            kind: StepKind.Loop,
            list: '{{s1.out.all}}',
            children: [
              step(
                's5',
                f.ref('Item'),
                [inp(InputTarget.PathParam, 'id', '{{item.id}}')],
                const [
                  StepOutput(
                    name: 'seen',
                    kind: SourceKind.Field,
                    path: 'path',
                  ),
                ],
              ),
            ],
          ),
          step('s6', f.ref('Item'), [
            inp(InputTarget.PathParam, 'id', 'last:{{s5.out.seen}}'),
          ]),
        ],
      );
      final (runs, events) = await f.run(wf);
      final s2 = runs.firstWhere((r) => r.step.id == 's2');
      expect(bodyOf(s2)['path'], '/item/1');
      expect(
        s2.result!.request!.url.contains('c=200-application%2Fjson'),
        isTrue,
        reason: s2.result!.request!.url,
      );
      expect(
        s2.notes.any(
          (x) => x.contains("does not pass on an output called 'unknown'"),
        ),
        isTrue,
        reason: s2.notes.toString(),
      );
      final t = texts(events);
      expect(
        t.any(
          (x) =>
              x.contains('passes on') &&
              x.contains('firstId = 1') &&
              x.contains('code = 200'),
        ),
        isTrue,
        reason: t.toString(),
      );
      final s1 = runs.firstWhere((r) => r.step.id == 's1');
      expect(
        s1.notes.any((x) => x.contains("output 'nope'")),
        isTrue,
        reason: s1.notes.toString(),
      );
      expect(t.any((x) => x.contains('n = 3')), isTrue, reason: t.toString());
      // a loop overwrites its outputs every round; the step after the loop sees the last one
      expect(bodyOf(runs.last)['path'], '/item/last:/item/3');
      expect(runs.where((r) => r.step.id == 's5').length, 3);
      // the preview helper used by the builder reads the same value
      expect(
        const StepOutput(
          name: 'x',
          kind: SourceKind.Field,
          path: 'items[0].id',
        ).valueIn(runs.first.result).$1,
        '1',
      );
      expect(
        const StepOutput(
          name: 'x',
          kind: SourceKind.Field,
          path: 'zzz',
        ).valueIn(runs.first.result).$2,
        isNotNull,
      );
    }),
  );

  test('outputsRoundTripAndShowFriendlyNames', () {
    final wf = Workflow(
      name: 'o',
      steps: [
        const WorkflowStep(
          id: 's1',
          request: 'a.yaml',
          outputs: [
            StepOutput(name: 'id', kind: SourceKind.Field, path: 'data.id'),
            StepOutput(name: 'raw', kind: SourceKind.Body),
            StepOutput(name: 'st', kind: SourceKind.Status),
            StepOutput(name: 'loc', kind: SourceKind.Header, path: 'Location'),
            StepOutput(name: 't', kind: SourceKind.Time),
            StepOutput(name: 'r', kind: SourceKind.Response),
          ],
        ),
      ],
    );
    final dir = tempDir('wfo');
    WorkflowStore.save(dir, wf);
    expect(WorkflowStore.load(dir).single, wf);
    expect(
      Slots.friendly('{{s1.out.id}}', wf.steps, (_) => 'Login'),
      '[Login › id]',
    );
    expect(wf.steps[0].outputs[0].reference('s1'), 's1.body.data.id');
    expect(wf.steps[0].outputs[3].reference('s1'), 's1.header.Location');
  });

  test(
    'passedOnValuesAreAlsoPlainVariables',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List'), const [], const [
            StepOutput(name: 'first', kind: SourceKind.Field, path: 'items[0]'),
            StepOutput(name: 'orders', kind: SourceKind.Field, path: 'items'),
            StepOutput(name: 'ok', kind: SourceKind.Status),
          ]),
          // {{first.id}} reads a field of a JSON output, {{ok}} a plain one, {{orders}} a whole list
          step('s2', f.ref('Item'), [
            inp(InputTarget.PathParam, 'id', '{{first.id}}-{{first.name}}'),
            inp(InputTarget.Query, 's', '{{ok}}'),
          ]),
          const WorkflowStep(
            id: 's3',
            kind: StepKind.Set,
            setOp: SetOp.Count,
            varName: 'n',
            list: '{{orders}}',
          ),
          const WorkflowStep(
            id: 's4',
            kind: StepKind.If,
            conditions: [
              Condition(left: '{{first.price}}', op: CondOp.Gt, right: '10'),
            ],
            children: [
              WorkflowStep(
                id: 's5',
                kind: StepKind.Set,
                varName: 'big',
                value: 'yes',
              ),
            ],
            otherwise: [
              WorkflowStep(
                id: 's6',
                kind: StepKind.Set,
                varName: 'big',
                value: 'no',
              ),
            ],
          ),
        ],
      );
      final (runs, events) = await f.run(wf);
      final sent = runs
          .firstWhere((r) => r.step.id == 's2')
          .result!
          .request!
          .url;
      expect(
        sent.contains('/item/1-a') && sent.endsWith('s=200'),
        isTrue,
        reason: sent,
      );
      final t = texts(events);
      expect(t.any((x) => x.contains('n = 3')), isTrue, reason: t.toString());
      expect(
        t.any((x) => x.contains('big = yes')),
        isTrue,
        reason: t.toString(),
      ); // first.price is 10.5
    }),
  );

  test('plainOutputNamesAreShownFriendly', () {
    const steps = [
      WorkflowStep(
        id: 's1',
        request: 'a.yaml',
        outputs: [
          StepOutput(name: 'token', kind: SourceKind.Field, path: 't'),
          StepOutput(name: 'user', kind: SourceKind.Field, path: 'u'),
        ],
      ),
      WorkflowStep(id: 's2', request: 'b.yaml'),
    ];
    String name(WorkflowStep st) => st.id == 's1' ? 'Login' : 'Other';
    expect(
      Slots.friendlyAll('Bearer {{token}}', steps, name),
      'Bearer [Login › token]',
    );
    expect(
      Slots.friendlyAll('{{user.id}} and {{baseUrl}}', steps, name),
      '[Login › user.id] and {{baseUrl}}',
    );
    expect(
      Slots.friendlyAll('{{s1.out.token}}', steps, name),
      '[Login › token]',
    );
  });

  test(
    'singleBracesUsePassedOnValuesAndLeaveEverythingElseAlone',
    () => fixture((f) async {
      Collections.createRequest(
        f.col.path,
        ApiRequest(
          name: 'Echo',
          method: 'POST',
          url:
              '${f.base}/echo/{id}/{nope}/:kind?who={user.name}&env={{baseUrl}}',
          headers: const [
            KV(name: 'X-Tok', value: 'Bearer {token}'),
            KV(name: 'X-Env', value: '{{baseUrl}}'),
          ],
          bodyMode: BodyMode.Json,
          bodyJson: '{"id":{id},"name":"{user.name}","literal":{"a":1},"keep":"{unknown}","nested":{"id":{id}}}',
        ),
      );
      f.col = Collections.load(f.col.path);
      final wf = Workflow(
        name: 'w',
        stopOnFail: false,
        steps: [
          step('s1', f.ref('List'), const [], const [
            StepOutput(name: 'id', kind: SourceKind.Field, path: 'items[1].id'),
            StepOutput(name: 'user', kind: SourceKind.Field, path: 'items[0]'),
            StepOutput(name: 'token', kind: SourceKind.Status),
          ]),
          step('s2', f.ref('Echo'), [
            inp(InputTarget.PathParam, 'kind', 'k-{index}'),
          ]),
          const WorkflowStep(
            id: 's3',
            kind: StepKind.If,
            conditions: [
              Condition(left: '{id}', op: CondOp.Eq, right: '2'),
              Condition(left: '{user.price}', op: CondOp.Gt, right: '10'),
            ],
            children: [
              WorkflowStep(
                id: 's4',
                kind: StepKind.Set,
                varName: 'msg',
                value: 'id={id};{unknown}',
              ),
            ],
          ),
        ],
      );
      final (runs, events) = await f.run(wf);
      final sent = runs.firstWhere((r) => r.step.id == 's2').result!.request!;
      expect(
        sent.url.contains('/echo/2/%7Bnope%7D/k-%7Bindex%7D?'),
        isTrue,
        reason: sent.url,
      );
      expect(
        sent.url.contains('who=a'),
        isTrue,
        reason: sent.url,
      ); // {user.name} read a field of a JSON value
      expect(sent.headers.firstWhere((h) => h.$1 == 'X-Tok').$2, 'Bearer 200');
      final body = Json.obj(Json.parse((sent.body as BodyRaw).text))!;
      expect((body['id'] as num).toInt(), 2); // stays a JSON number
      expect(body['name'], 'a');
      expect(
        Json.obj(body['literal'])!
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        {'a': 1},
      ); // real JSON braces left alone
      expect(body['keep'], '{unknown}');
      expect((Json.obj(body['nested'])!['id'] as num).toInt(), 2);
      final t = texts(events);
      expect(
        t.any((x) => x.contains('→ then')),
        isTrue,
        reason: t.toString(),
      ); // {id} = 2 and {user.price} = 10.5 > 10
      expect(
        t.any((x) => x.contains('msg = id=2;{unknown}')),
        isTrue,
        reason: t.toString(),
      );
    }),
  );

  test(
    'loopVariablesAndSetVariablesWorkWithSingleBraces',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        steps: [
          step('s1', f.ref('List')),
          const WorkflowStep(
            id: 's2',
            kind: StepKind.Set,
            setOp: SetOp.Count,
            varName: 'total',
            list: '{{s1.body.items}}',
          ),
          WorkflowStep(
            id: 's3',
            kind: StepKind.Loop,
            list: '{{s1.body.items}}',
            itemVar: 'row',
            children: [
              step('s4', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '{row.id}'),
                inp(InputTarget.Query, 'of', '{index}/{total}'),
              ]),
            ],
          ),
        ],
      );
      final items = (await f.run(wf)).$1
          .where((r) => r.step.id == 's4')
          .toList();
      expect(
        items.map((r) => r.result!.request!.url.split('?').last).toList(),
        ['of=0%2F3', 'of=1%2F3', 'of=2%2F3'],
      );
      expect(items.map((r) => bodyOf(r)['path']).toList(), [
        '/item/1',
        '/item/2',
        '/item/3',
      ]);
    }),
  );

  test(
    'runLogEventsCarryStructureForTheLogView',
    () => fixture((f) async {
      final wf = Workflow(
        name: 'w',
        stopOnFail: false,
        steps: [
          step('s1', f.ref('List'), const [], const [
            StepOutput(name: 'n', kind: SourceKind.Status),
          ]),
          WorkflowStep(
            id: 's2',
            kind: StepKind.Loop,
            list: '{{s1.body.items}}',
            children: [
              step('s3', f.ref('Item'), [
                inp(InputTarget.PathParam, 'id', '{item.id}'),
              ]),
            ],
          ),
          step('s4', 'gone.yaml'),
        ],
      );
      final ev = (await f.run(wf)).$2;
      final req = ev.firstWhere((e) => e.stepId == 's1' && !e.sub);
      expect(req.label, 'List');
      expect(req.status, 200);
      expect(req.ms, isNotNull);
      final passOn = ev.firstWhere((e) => e.sub);
      expect(
        passOn.text.startsWith('passes on n = 200') &&
            passOn.stepId == 's1' &&
            passOn.depth == req.depth,
        isTrue,
      );
      expect(passOn.fields, [('n', '200')]); // the table behind the log line
      final rounds = ev.where((e) => e.stepId == 's3').toList();
      expect(rounds.length, 3);
      expect(
        rounds.every(
          (e) => e.depth == 1 && e.label == 'Item' && e.status == 200,
        ),
        isTrue,
      );
      expect(ev.firstWhere((e) => e.stepId == 's2').depth, 0);
      for (var i = 0; i + 1 < ev.length; i++) {
        expect(ev[i].at <= ev[i + 1].at, isTrue); // time only moves forward
      }
      final missing = ev.firstWhere((e) => e.stepId == 's4');
      expect(missing.ok, isFalse);
      expect(missing.status, isNull);
    }),
  );

  test('flowRefsFindThePassedOnNamesATextUses', () {
    expect(FlowRefs.names('t={token}&u=${"http://h/users/{id}?t={token}"}'), [
      'token',
      'id',
    ]); // order of first use
    expect(FlowRefs.names('{user.id} {{n}} {user.name} {user}'), [
      'user',
      'n',
    ]); // dotted paths and older {{n}} count, once each
    expect(FlowRefs.names('{"a": 1, "b": {"c": 2}} {{ x.y }}-{ spaced }'), [
      'x',
    ]); // JSON and "{ spaced }" are not references
  });
}
