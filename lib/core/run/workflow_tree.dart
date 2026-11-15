// ignore_for_file: constant_identifier_names

import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';

extension WorkflowStepList on List<WorkflowStep> {
  /// Depth-first, in execution order (a block, then its children, then its else branch).
  List<WorkflowStep> walk() => [
    for (final s in this) ...[s, ...s.children.walk(), ...s.otherwise.walk()],
  ];

  WorkflowStep? findStep(String id) {
    for (final s in walk()) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<WorkflowStep> mapStep(
    String id,
    WorkflowStep Function(WorkflowStep) f,
  ) => [
    for (final s in this)
      if (s.id == id)
        f(s)
      else
        s.copyWith(
          children: s.children.mapStep(id, f),
          otherwise: s.otherwise.mapStep(id, f),
        ),
  ];

  List<WorkflowStep> removeStep(String id) => [
    for (final s in this)
      if (s.id != id)
        s.copyWith(
          children: s.children.removeStep(id),
          otherwise: s.otherwise.removeStep(id),
        ),
  ];

  /// Appends [step] to the top level ([parentId] null) or to a block's main branch ([branch] 0) / else branch (1).
  List<WorkflowStep> addStep(String? parentId, int branch, WorkflowStep step) =>
      parentId == null
      ? [...this, step]
      : mapStep(
          parentId,
          (it) => branch == 1
              ? it.copyWith(otherwise: [...it.otherwise, step])
              : it.copyWith(children: [...it.children, step]),
        );

  /// Moves a block up/down among its siblings.
  List<WorkflowStep> moveStep(String id, int delta) {
    final i = indexWhere((s) => s.id == id);
    if (i >= 0) {
      final j = i + delta;
      if (j < 0 || j >= length) return this;
      final l = List<WorkflowStep>.of(this);
      l.insert(j, l.removeAt(i));
      return l;
    }
    return [
      for (final s in this)
        s.copyWith(
          children: s.children.moveStep(id, delta),
          otherwise: s.otherwise.moveStep(id, delta),
        ),
    ];
  }

  /// Request blocks that run before [id] (anything else can read their responses).
  List<WorkflowStep> requestsBefore(String id) {
    final out = <WorkflowStep>[];
    for (final s in walk()) {
      if (s.id == id) break;
      if (s.kind == StepKind.Request) out.add(s);
    }
    return out;
  }

  /// Names of variables made by loops and Set blocks that run before [id].
  List<String> variablesBefore(String id) {
    final out = <String>{};
    for (final s in walk()) {
      if (s.id == id) break;
      if (s.kind == StepKind.Loop) {
        if (s.itemVar.isNotEmpty &&
            s.itemVar.trim().isNotEmpty &&
            s.loop == LoopMode.ForEach) {
          out.add(s.itemVar.trim());
        }
        if (s.indexVar.trim().isNotEmpty) out.add(s.indexVar.trim());
      }
      if (s.kind == StepKind.Set && s.varName.trim().isNotEmpty) {
        out.add(s.varName.trim());
      }
    }
    // a block can also use the variables of the loops that contain it
    List<WorkflowStep>? enclosing(
      List<WorkflowStep> list,
      List<WorkflowStep> trail,
    ) {
      for (final s in list) {
        if (s.id == id) return trail;
        final a = enclosing(s.children, [...trail, s]);
        if (a != null) return a;
        final b = enclosing(s.otherwise, [...trail, s]);
        if (b != null) return b;
      }
      return null;
    }

    final enc = enclosing(this, const []);
    if (enc != null) {
      for (final l in enc.where((e) => e.kind == StepKind.Loop)) {
        if (l.itemVar.trim().isNotEmpty && l.loop == LoopMode.ForEach) {
          out.add(l.itemVar.trim());
        }
        if (l.indexVar.trim().isNotEmpty) out.add(l.indexVar.trim());
      }
    }
    return out.toList();
  }
}

String newStepId(List<WorkflowStep> existing) {
  final all = existing.walk();
  var i = all.length + 1;
  while (all.any((s) => s.id == 's$i')) {
    i++;
  }
  return 's$i';
}
