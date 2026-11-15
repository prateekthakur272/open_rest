// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart' show listEquals;
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/core/run/workflow_model.dart';

/// One execution of a request block (a block inside a loop produces one per round).
class StepRun {
  final WorkflowStep step;
  final RequestNode? node;
  final ExecResult? result;

  /// Values the step's inputs resolved to, in order.
  final List<(String, String)> inputs;
  final List<String> notes;
  final int depth;
  final int iteration;

  const StepRun({
    required this.step,
    required this.node,
    required this.result,
    this.inputs = const [],
    this.notes = const [],
    this.depth = 0,
    this.iteration = 0,
  });

  bool get failed =>
      node == null ||
      result == null ||
      result!.error != null ||
      result!.response?.error != null ||
      result!.tests.any((t) => !t.passed);

  StepRun copyWith({
    WorkflowStep? step,
    RequestNode? node,
    ExecResult? result,
    List<(String, String)>? inputs,
    List<String>? notes,
    int? depth,
    int? iteration,
  }) => StepRun(
    step: step ?? this.step,
    node: node ?? this.node,
    result: result ?? this.result,
    inputs: inputs ?? this.inputs,
    notes: notes ?? this.notes,
    depth: depth ?? this.depth,
    iteration: iteration ?? this.iteration,
  );

  @override
  bool operator ==(Object other) =>
      other is StepRun &&
      other.step == step &&
      other.node == node &&
      other.result == result &&
      listEquals(other.inputs, inputs) &&
      listEquals(other.notes, notes) &&
      other.depth == depth &&
      other.iteration == iteration;
  @override
  int get hashCode => Object.hash(
    step,
    node,
    result,
    Object.hashAll(inputs),
    Object.hashAll(notes),
    depth,
    iteration,
  );
}

/// The value of [o] in [res] (what a later step would receive) and a warning when it can't be found.
extension StepOutputValue on StepOutput {
  (String, String?) valueIn(ExecResult? res) {
    final (v, w) = WorkflowRunner.resolve(reference('s0'), res);
    return (v, w == null ? null : 'not found in the response');
  }
}

/// Finds the names of passed-on values (`{token}`, `{user.id}`, older `{{token}}`) that a piece of text uses.
class FlowRefs {
  FlowRefs._();
  static final RegExp _single = RegExp(
    r'(?<!\{)\{([A-Za-z_][A-Za-z0-9_]*)(?:\.[A-Za-z0-9_\[\]-]+)*\}',
  );
  static final RegExp _double = RegExp(
    r'\{\{\s*([A-Za-z_][A-Za-z0-9_]*)(?:\.[^{}\s]*)?\s*\}\}',
  );

  /// Root names, in order of first use.
  static List<String> names(String text) {
    final all = [..._single.allMatches(text), ..._double.allMatches(text)]
      ..sort((a, b) => a.start.compareTo(b.start));
    final seen = <String>[];
    for (final m in all) {
      final n = m.group(1)!;
      if (!seen.contains(n)) seen.add(n);
    }
    return seen;
  }
}

/// A line of the run log: requests, branches taken, loop rounds, variables set.
class RunEvent {
  final String stepId;
  final int depth;
  final StepKind kind;
  final String text;
  final bool ok;

  /// Milliseconds since the run started.
  final int at;

  /// For request executions: the HTTP status and the request's own time, and the name shown for it.
  final int? status;
  final int? ms;
  final String? label;

  /// A detail entry under the step above it (what a step passes on).
  final bool sub;

  /// For [sub] entries: the name / value pairs, in full.
  final List<(String, String)> fields;

  const RunEvent({
    required this.stepId,
    required this.depth,
    required this.kind,
    required this.text,
    this.ok = true,
    this.at = 0,
    this.status,
    this.ms,
    this.label,
    this.sub = false,
    this.fields = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is RunEvent &&
      other.stepId == stepId &&
      other.depth == depth &&
      other.kind == kind &&
      other.text == text &&
      other.ok == ok &&
      other.at == at &&
      other.status == status &&
      other.ms == ms &&
      other.label == label &&
      other.sub == sub &&
      listEquals(other.fields, fields);
  @override
  int get hashCode => Object.hash(
    stepId,
    depth,
    kind,
    text,
    ok,
    at,
    status,
    ms,
    label,
    sub,
    Object.hashAll(fields),
  );
}
