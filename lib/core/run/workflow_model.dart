// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart' show listEquals;
import 'package:open_rest/core/model/model.dart';
import 'package:path/path.dart' as p;

/// What part of an earlier step's response a `{{sN.…}}` reference points at.
enum SourceKind {
  Response('response', 'Whole response (status, headers, body)', false, ''),
  Body('body', 'Full body', false, ''),
  Field('body', 'Body field', true, 'e.g. data.token or items[0].id'),
  Status('status', 'Status code', false, ''),
  Header('header', 'Response header', true, 'header name, e.g. Location'),
  Time('time', 'Response time (ms)', false, '');

  final String id;
  final String label;
  final bool needsPath;
  final String pathHint;
  const SourceKind(this.id, this.label, this.needsPath, this.pathHint);

  /// The `{{…}}` reference for this selection, e.g. `{{s1.body.data.id}}`.
  String token(String stepId, [String path = '']) {
    final pp = path.trim();
    return '{{$stepId.$id${needsPath && pp.isNotEmpty ? '.$pp' : ''}}}';
  }
}

/// Where a value is written into a request step.
enum InputTarget {
  PathParam('path', 'URL path parameter', true, 'the :name in the URL'),
  Query('query', 'Query parameter', true, 'parameter name'),
  Header('header', 'Header', true, 'header name'),
  Body('body', 'JSON body field', true, 'e.g. user.id'),
  BodyRaw('body_raw', 'Whole body', false, ''),
  Bearer('bearer', 'Auth bearer token', false, ''),
  Url('url', 'Whole URL', false, ''),
  Method('method', 'HTTP method', false, ''),
  PathAppend('path_append', 'Add to end of URL path', false, ''),
  Variable('variable', 'Variable {{name}}', true, 'variable name');

  final String id;
  final String label;
  final bool needsKey;
  final String keyHint;
  const InputTarget(this.id, this.label, this.needsKey, this.keyHint);

  static InputTarget of(String? id) {
    for (final e in InputTarget.values) {
      if (e.id == id) return e;
    }
    return InputTarget.Variable;
  }
}

/// Writes [value] into a request step at [target]/[name]. The value is a template: plain text, `{{vars}}`,
/// loop variables (`{{item.id}}`) and references to earlier steps' responses (`{{s1.body.data.id}}`,
/// `{{s2.header.X-Id}}`, `{{s1.status}}`), mixed freely.
class StepInput {
  final InputTarget target;
  final String name;
  final String value;
  const StepInput({
    this.target = InputTarget.Variable,
    this.name = '',
    this.value = '',
  });

  StepInput copyWith({InputTarget? target, String? name, String? value}) =>
      StepInput(
        target: target ?? this.target,
        name: name ?? this.name,
        value: value ?? this.value,
      );

  @override
  bool operator ==(Object other) =>
      other is StepInput &&
      other.target == target &&
      other.name == name &&
      other.value == value;
  @override
  int get hashCode => Object.hash(target, name, value);
}

/// A named value a request step passes on to later steps, e.g. `userId` ← body field `data.id`.
/// Later steps use it as `{{s1.out.userId}}` (shown as `[Create user › userId]`).
class StepOutput {
  final String name;
  final SourceKind kind;
  final String path;
  const StepOutput({
    this.name = '',
    this.kind = SourceKind.Field,
    this.path = '',
  });

  StepOutput copyWith({String? name, SourceKind? kind, String? path}) =>
      StepOutput(
        name: name ?? this.name,
        kind: kind ?? this.kind,
        path: path ?? this.path,
      );

  /// The `sN.what[.path]` reference that reads this output straight from the response.
  String reference(String stepId) =>
      '$stepId.${kind.id}${kind.needsPath && path.trim().isNotEmpty ? '.${path.trim()}' : ''}';

  /// Restores the kind from a file: "body" with a path is a field, without a path the whole body.
  static StepOutput of(String name, String from, String path) {
    final k = switch (from) {
      'body' => path.trim().isEmpty ? SourceKind.Body : SourceKind.Field,
      'status' => SourceKind.Status,
      'header' => SourceKind.Header,
      'time' => SourceKind.Time,
      'response' => SourceKind.Response,
      _ => SourceKind.Field,
    };
    return StepOutput(name: name, kind: k, path: path);
  }

  @override
  bool operator ==(Object other) =>
      other is StepOutput &&
      other.name == name &&
      other.kind == kind &&
      other.path == path;
  @override
  int get hashCode => Object.hash(name, kind, path);
}

enum StepKind {
  Request('request', 'Request', 'Call an API'),
  If('if', 'If / else', 'Run different steps depending on a condition'),
  Loop(
    'loop',
    'Loop',
    'Repeat steps for every item in a list, N times, or while something is true',
  ),
  Set(
    'set',
    'Set variable',
    'Store a value, or count / add up / pick items from a list',
  ),
  Wait('wait', 'Wait', 'Pause before the next step'),
  Stop('stop', 'Stop', 'End the loop or the whole workflow');

  final String id;
  final String label;
  final String hint;
  const StepKind(this.id, this.label, this.hint);

  static StepKind of(String? id) {
    for (final e in StepKind.values) {
      if (e.id == id) return e;
    }
    return StepKind.Request;
  }
}

enum CondOp {
  Eq('eq', 'equals', true),
  Ne('ne', 'does not equal', true),
  Contains('contains', 'contains', true),
  NotContains('not_contains', 'does not contain', true),
  StartsWith('starts', 'starts with', true),
  Gt('gt', 'is greater than', true),
  Gte('gte', 'is at least', true),
  Lt('lt', 'is less than', true),
  Lte('lte', 'is at most', true),
  Empty('empty', 'is empty', false),
  NotEmpty('not_empty', 'is not empty', false),
  Matches('matches', 'matches pattern', true);

  final String id;
  final String label;
  final bool needsRight;
  const CondOp(this.id, this.label, this.needsRight);

  static CondOp of(String? id) {
    for (final e in CondOp.values) {
      if (e.id == id) return e;
    }
    return CondOp.Eq;
  }
}

/// `left op right`; both sides are templates (`{{s1.status}}`, `{{count}}`, `{{item.id}}`, plain text).
class Condition {
  final String left;
  final CondOp op;
  final String right;
  const Condition({this.left = '', this.op = CondOp.Eq, this.right = ''});

  Condition copyWith({String? left, CondOp? op, String? right}) => Condition(
    left: left ?? this.left,
    op: op ?? this.op,
    right: right ?? this.right,
  );

  @override
  bool operator ==(Object other) =>
      other is Condition &&
      other.left == left &&
      other.op == op &&
      other.right == right;
  @override
  int get hashCode => Object.hash(left, op, right);
}

enum LoopMode {
  ForEach('each', 'For each item in a list'),
  Repeat('repeat', 'Repeat a number of times'),
  While('while', 'Repeat while a condition is true');

  final String id;
  final String label;
  const LoopMode(this.id, this.label);

  static LoopMode of(String? id) {
    for (final e in LoopMode.values) {
      if (e.id == id) return e;
    }
    return LoopMode.ForEach;
  }
}

enum SetOp {
  Value('value', 'Set to a value', false),
  Count('count', 'Count items in a list', true),
  Sum('sum', 'Add up numbers in a list', true),
  First('first', 'First item of a list', true),
  Last('last', 'Last item of a list', true);

  final String id;
  final String label;
  final bool needsList;
  const SetOp(this.id, this.label, this.needsList);

  static SetOp of(String? id) {
    for (final e in SetOp.values) {
      if (e.id == id) return e;
    }
    return SetOp.Value;
  }
}

enum StopScope {
  Loop('loop', 'Stop this loop'),
  Workflow('workflow', 'Stop the workflow');

  final String id;
  final String label;
  const StopScope(this.id, this.label);

  static StopScope of(String? id) {
    for (final e in StopScope.values) {
      if (e.id == id) return e;
    }
    return StopScope.Workflow;
  }
}

/// One block of a workflow. [kind] decides which fields matter:
///  - Request: [request] (file relative to the collection root, '/'-separated) customised by [inputs].
///  - If: [conditions] / [matchAll]; [children] run when true, [otherwise] when false.
///  - Loop: [loop] with [list] / [count] / [conditions]; [children] is the body; [itemVar] / [indexVar] are set per round.
///  - Set: stores [varName] using [setOp] on [value] (a template) or [list] (a template that yields a JSON list).
///  - Wait: [value] is milliseconds.  Stop: [stopScope], [stopFail], [value] is the message.
class WorkflowStep {
  final String id;
  final String request;
  final List<StepInput> inputs;
  final bool enabled;
  final StepKind kind;

  /// Request steps: named values this step hands on to the steps after it.
  final List<StepOutput> outputs;
  final String title;
  final bool continueOnFail;
  final List<Condition> conditions;
  final bool matchAll;
  final List<WorkflowStep> children;
  final List<WorkflowStep> otherwise;
  final LoopMode loop;
  final String list;
  final String count;
  final String itemVar;
  final String indexVar;
  final int maxIterations;
  final SetOp setOp;
  final String varName;
  final String value;
  final String path;
  final StopScope stopScope;
  final bool stopFail;

  const WorkflowStep({
    required this.id,
    this.request = '',
    this.inputs = const [],
    this.enabled = true,
    this.kind = StepKind.Request,
    this.outputs = const [],
    this.title = '',
    this.continueOnFail = false,
    this.conditions = const [],
    this.matchAll = true,
    this.children = const [],
    this.otherwise = const [],
    this.loop = LoopMode.ForEach,
    this.list = '',
    this.count = '',
    this.itemVar = 'item',
    this.indexVar = 'index',
    this.maxIterations = 100,
    this.setOp = SetOp.Value,
    this.varName = '',
    this.value = '',
    this.path = '',
    this.stopScope = StopScope.Workflow,
    this.stopFail = false,
  });

  WorkflowStep copyWith({
    String? id,
    String? request,
    List<StepInput>? inputs,
    bool? enabled,
    StepKind? kind,
    List<StepOutput>? outputs,
    String? title,
    bool? continueOnFail,
    List<Condition>? conditions,
    bool? matchAll,
    List<WorkflowStep>? children,
    List<WorkflowStep>? otherwise,
    LoopMode? loop,
    String? list,
    String? count,
    String? itemVar,
    String? indexVar,
    int? maxIterations,
    SetOp? setOp,
    String? varName,
    String? value,
    String? path,
    StopScope? stopScope,
    bool? stopFail,
  }) => WorkflowStep(
    id: id ?? this.id,
    request: request ?? this.request,
    inputs: inputs ?? this.inputs,
    enabled: enabled ?? this.enabled,
    kind: kind ?? this.kind,
    outputs: outputs ?? this.outputs,
    title: title ?? this.title,
    continueOnFail: continueOnFail ?? this.continueOnFail,
    conditions: conditions ?? this.conditions,
    matchAll: matchAll ?? this.matchAll,
    children: children ?? this.children,
    otherwise: otherwise ?? this.otherwise,
    loop: loop ?? this.loop,
    list: list ?? this.list,
    count: count ?? this.count,
    itemVar: itemVar ?? this.itemVar,
    indexVar: indexVar ?? this.indexVar,
    maxIterations: maxIterations ?? this.maxIterations,
    setOp: setOp ?? this.setOp,
    varName: varName ?? this.varName,
    value: value ?? this.value,
    path: path ?? this.path,
    stopScope: stopScope ?? this.stopScope,
    stopFail: stopFail ?? this.stopFail,
  );

  @override
  bool operator ==(Object other) =>
      other is WorkflowStep &&
      other.id == id &&
      other.request == request &&
      listEquals(other.inputs, inputs) &&
      other.enabled == enabled &&
      other.kind == kind &&
      listEquals(other.outputs, outputs) &&
      other.title == title &&
      other.continueOnFail == continueOnFail &&
      listEquals(other.conditions, conditions) &&
      other.matchAll == matchAll &&
      listEquals(other.children, children) &&
      listEquals(other.otherwise, otherwise) &&
      other.loop == loop &&
      other.list == list &&
      other.count == count &&
      other.itemVar == itemVar &&
      other.indexVar == indexVar &&
      other.maxIterations == maxIterations &&
      other.setOp == setOp &&
      other.varName == varName &&
      other.value == value &&
      other.path == path &&
      other.stopScope == stopScope &&
      other.stopFail == stopFail;

  @override
  int get hashCode => Object.hashAll([
    id,
    request,
    Object.hashAll(inputs),
    enabled,
    kind,
    Object.hashAll(outputs),
    title,
    continueOnFail,
    Object.hashAll(conditions),
    matchAll,
    Object.hashAll(children),
    Object.hashAll(otherwise),
    loop,
    list,
    count,
    itemVar,
    indexVar,
    maxIterations,
    setOp,
    varName,
    value,
    path,
    stopScope,
    stopFail,
  ]);
}

/// A named list of blocks stored in a collection.
class Workflow {
  final String name;
  final List<WorkflowStep> steps;
  final bool stopOnFail;
  final String description;
  const Workflow({
    required this.name,
    this.steps = const [],
    this.stopOnFail = true,
    this.description = '',
  });

  Workflow copyWith({
    String? name,
    List<WorkflowStep>? steps,
    bool? stopOnFail,
    String? description,
  }) => Workflow(
    name: name ?? this.name,
    steps: steps ?? this.steps,
    stopOnFail: stopOnFail ?? this.stopOnFail,
    description: description ?? this.description,
  );

  @override
  bool operator ==(Object other) =>
      other is Workflow &&
      other.name == name &&
      listEquals(other.steps, steps) &&
      other.stopOnFail == stopOnFail &&
      other.description == description;
  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(steps), stopOnFail, description);
}

extension CollectionWorkflowRefs on Collection {
  String requestRef(RequestNode node) =>
      p.split(p.relative(node.path, from: path)).join('/');
  RequestNode? requestByRef(String ref) =>
      findRequest(p.normalize(p.join(path, ref)));
}
