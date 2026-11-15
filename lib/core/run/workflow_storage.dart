// ignore_for_file: constant_identifier_names
import 'dart:io';

import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as p;

/// Reads and writes workflow files.
class WorkflowIO {
  WorkflowIO._();

  static String _s(dynamic v) => v?.toString() ?? '';
  static List<Map> _maps(dynamic v) => v is List
      ? [
          for (final x in v)
            if (x is Map) x,
        ]
      : <Map>[];

  static Map<String, dynamic> _stepToMap(WorkflowStep st) {
    final c = Yml.m([
      ('id', st.id),
      ('kind', st.kind == StepKind.Request ? null : st.kind.id),
      ('title', st.title),
      ('enabled', st.enabled ? null : false),
    ]);
    switch (st.kind) {
      case StepKind.Request:
        c.addAll(
          Yml.m([
            ('request', st.request),
            ('continueOnFail', st.continueOnFail ? true : null),
            (
              'inputs',
              [
                for (final i in st.inputs)
                  Yml.m([
                    (
                      'target',
                      i.target == InputTarget.Variable ? null : i.target.id,
                    ),
                    ('name', i.name),
                    ('value', i.value),
                  ]),
              ],
            ),
            (
              'outputs',
              [
                for (final o in st.outputs)
                  Yml.m([
                    ('name', o.name),
                    ('from', o.kind.id),
                    ('path', o.path),
                  ]),
              ],
            ),
          ]),
        );
      case StepKind.If:
        c.addAll(
          Yml.m([
            ('conditions', st.conditions.map(_condToMap).toList()),
            ('match', st.matchAll ? null : 'any'),
            ('then', st.children.map(_stepToMap).toList()),
            ('else', st.otherwise.map(_stepToMap).toList()),
          ]),
        );
      case StepKind.Loop:
        c.addAll(
          Yml.m([
            ('mode', st.loop.id),
            ('list', st.list),
            ('count', st.count),
            ('item', st.itemVar),
            ('index', st.indexVar),
            ('max', st.maxIterations == 100 ? null : st.maxIterations),
            ('conditions', st.conditions.map(_condToMap).toList()),
            ('match', st.matchAll ? null : 'any'),
            ('do', st.children.map(_stepToMap).toList()),
          ]),
        );
      case StepKind.Set:
        c.addAll(
          Yml.m([
            ('op', st.setOp.id),
            ('name', st.varName),
            ('list', st.list),
            ('value', st.value),
            ('path', st.path),
          ]),
        );
      case StepKind.Wait:
        c.addAll(Yml.m([('ms', st.value)]));
      case StepKind.Stop:
        c.addAll(
          Yml.m([
            ('scope', st.stopScope.id),
            ('fail', st.stopFail ? true : null),
            ('message', st.value),
          ]),
        );
    }
    return c;
  }

  static Map<String, dynamic> _condToMap(Condition c) =>
      Yml.m([('left', c.left), ('op', c.op.id), ('right', c.right)]);
  static Condition _condFrom(Map m) => Condition(
    left: _s(m['left']),
    op: CondOp.of(_s(m['op'])),
    right: _s(m['right']),
  );

  static WorkflowStep _stepFrom(Map st, int idx) {
    final kindStr = _s(st['kind']);
    final kind = StepKind.of(kindStr.trim().isEmpty ? 'request' : kindStr);
    final idStr = _s(st['id']);
    final base = WorkflowStep(
      id: idStr.trim().isEmpty ? 's${idx + 1}' : idStr,
      kind: kind,
      title: _s(st['title']),
      enabled: st['enabled'] != false,
    );
    List<WorkflowStep> kids(String key) {
      final ms = _maps(st[key]);
      return [for (var i = 0; i < ms.length; i++) _stepFrom(ms[i], i)];
    }

    switch (kind) {
      case StepKind.Request:
        return base.copyWith(
          request: _s(st['request']),
          continueOnFail: st['continueOnFail'] == true,
          outputs: [
            for (final o in _maps(st['outputs']))
              StepOutput.of(_s(o['name']), _s(o['from']), _s(o['path'])),
          ],
          inputs: [
            for (final i in _maps(st['inputs']))
              () {
                // older files stored (from, source, path); turn those into the equivalent reference
                String? legacy;
                final f = _s(i['from']);
                if (f.trim().isNotEmpty) {
                  var src = _s(i['source']);
                  if (src.trim().isEmpty) src = 'body';
                  if (src == 'field') src = 'body';
                  final path = _s(i['path']);
                  legacy =
                      '{{$f.$src${path.trim().isNotEmpty ? '.$path' : ''}}}';
                }
                return StepInput(
                  target: InputTarget.of(_s(i['target'])),
                  name: _s(i['name']),
                  value: i.containsKey('value')
                      ? _s(i['value'])
                      : (legacy ?? ''),
                );
              }(),
          ],
        );
      case StepKind.If:
        return base.copyWith(
          conditions: _maps(st['conditions']).map(_condFrom).toList(),
          matchAll: _s(st['match']) != 'any',
          children: kids('then'),
          otherwise: kids('else'),
        );
      case StepKind.Loop:
        final item = _s(st['item']);
        final index = _s(st['index']);
        return base.copyWith(
          loop: LoopMode.of(_s(st['mode'])),
          list: _s(st['list']),
          count: _s(st['count']),
          itemVar: item.trim().isEmpty ? 'item' : item,
          indexVar: index.trim().isEmpty ? 'index' : index,
          maxIterations: st['max'] is num ? (st['max'] as num).toInt() : 100,
          conditions: _maps(st['conditions']).map(_condFrom).toList(),
          matchAll: _s(st['match']) != 'any',
          children: kids('do'),
        );
      case StepKind.Set:
        return base.copyWith(
          setOp: SetOp.of(_s(st['op'])),
          varName: _s(st['name']),
          list: _s(st['list']),
          value: _s(st['value']),
          path: _s(st['path']),
        );
      case StepKind.Wait:
        return base.copyWith(value: _s(st['ms']));
      case StepKind.Stop:
        return base.copyWith(
          stopScope: StopScope.of(_s(st['scope'])),
          stopFail: st['fail'] == true,
          value: _s(st['message']),
        );
    }
  }

  static Map<String, dynamic> toMap(Workflow w) => Yml.m([
    ('name', w.name),
    ('description', w.description),
    ('stopOnFail', w.stopOnFail ? null : false),
    ('steps', w.steps.map(_stepToMap).toList()),
  ]);

  static Workflow fromMap(Map m, String fallbackName) {
    final n = _s(m['name']);
    final steps = _maps(m['steps']);
    return Workflow(
      name: n.trim().isEmpty ? fallbackName : n,
      steps: [for (var i = 0; i < steps.length; i++) _stepFrom(steps[i], i)],
      stopOnFail: m['stopOnFail'] != false,
      description: _s(m['description']),
    );
  }
}

/// One YAML file per workflow, in the collection's `workflows` folder.
class WorkflowStore {
  WorkflowStore._();

  static String dir(String col) => p.join(col, 'workflows');
  static String file(String col, String name) =>
      p.join(dir(col), '${Collections.sanitize(name)}.yaml');

  static List<Workflow> load(String col) {
    final d = Directory(dir(col));
    if (!d.existsSync()) return const [];
    final files =
        d.listSync().whereType<File>().where((f) {
          final e = p.extension(f.path);
          return e == '.yaml' || e == '.yml';
        }).toList()..sort(
          (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );
    final out = <Workflow>[];
    for (final f in files) {
      Map? m;
      try {
        final v = Yml.parse(f.readAsStringSync());
        m = v is Map ? v : null;
      } catch (_) {
        m = null;
      }
      if (m == null) continue;
      out.add(WorkflowIO.fromMap(m, p.basenameWithoutExtension(f.path)));
    }
    return out;
  }

  static void save(String col, Workflow w, [String? oldName]) {
    Directory(dir(col)).createSync(recursive: true);
    final target = file(col, w.name);
    if (oldName != null && oldName != w.name) {
      if (File(target).existsSync()) {
        throw ArgumentError("A workflow named '${w.name}' already exists");
      }
      final old = File(file(col, oldName));
      if (old.existsSync()) old.deleteSync();
    }
    File(target).writeAsStringSync(Yml.dump(WorkflowIO.toMap(w)));
  }

  static void delete(String col, String name) {
    final f = File(file(col, name));
    if (f.existsSync()) f.deleteSync();
  }
}
