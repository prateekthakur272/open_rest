import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/features/workflow/logic_steps.dart';
import 'package:open_rest/features/workflow/request_step.dart';
import 'package:open_rest/features/workflow/run_log.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// A value available by `{name}` to a block: passed on by earlier steps, or made by loops / Set blocks.
class Avail {
  const Avail(this.name, this.value, this.from, this.variable);
  final String name;
  final String? value;
  final String from;
  final bool variable;
}

/// What the two kinds of braces complete to inside a block.
class WfVars {
  const WfVars(this.env, this.envInfo, this.flow, this.flowInfo);
  final Set<String> env;
  final Map<String, VarInfo> envInfo;
  final Set<String> flow;
  final Map<String, VarInfo> flowInfo;
}

String _afterLast(String s, String d) =>
    s.contains(d) ? s.substring(s.lastIndexOf(d) + d.length) : s;

/// Everything a block card needs; passed down instead of a dozen parameters.
class Wf {
  Wf(this.state, this.tab, this.col) : ws = tab.workflow!;

  final AppState state;
  final RequestTab tab;
  final Collection col;
  final WorkflowSession ws;

  List<WorkflowStep> get steps => ws.draft.steps;

  /// The block open in the side pane, or null when the pane is closed.
  String? get selectedId {
    final s = ws.selected;
    return s != null && steps.findStep(s) != null ? s : null;
  }

  String summary(WorkflowStep st) {
    String conds() {
      final s = st.conditions
          .map(
            (it) =>
                '${it.left.trim().isEmpty ? "…" : it.left} ${it.op.label}${it.op.needsRight ? " ${it.right.trim().isEmpty ? "…" : it.right}" : ""}',
          )
          .join(st.matchAll ? ' and ' : ' or ');
      return s.trim().isEmpty ? '(no conditions yet)' : s;
    }

    switch (st.kind) {
      case StepKind.Request:
        return '';
      case StepKind.If:
        return conds();
      case StepKind.Loop:
        switch (st.loop) {
          case LoopMode.ForEach:
            return 'for each ${st.itemVar.trim().isEmpty ? "item" : st.itemVar} in ${st.list.trim().isEmpty ? "…" : st.list}';
          case LoopMode.Repeat:
            return 'repeat ${st.count.trim().isEmpty ? "…" : st.count} times';
          case LoopMode.While:
            return 'while ${conds()}';
        }
      case StepKind.Set:
        return '${st.varName.trim().isEmpty ? "…" : st.varName} = ${st.setOp.label.toLowerCase()}${st.setOp.needsList ? " ${st.list.trim().isEmpty ? "…" : st.list}" : " ${st.value}"}';
      case StepKind.Wait:
        return 'wait ${st.value.trim().isEmpty ? "…" : st.value} ms';
      case StepKind.Stop:
        return st.stopScope.label +
            (st.value.trim().isNotEmpty ? ' — ${st.value}' : '');
    }
  }

  Map<String, int> get numbers {
    final out = <String, int>{};
    var i = 0;
    for (final s in steps.walk().where((s) => s.kind == StepKind.Request)) {
      out[s.id] = ++i;
    }
    return out;
  }

  String name(WorkflowStep st) {
    if (st.title.trim().isNotEmpty) return st.title;
    if (st.kind == StepKind.Request) {
      final n = col.requestByRef(st.request)?.name;
      if (n != null) return n;
      final last = _afterLast(st.request, '/');
      return last.endsWith('.yaml') ? last.substring(0, last.length - 5) : last;
    }
    return st.kind.label;
  }

  void update(String id, WorkflowStep Function(WorkflowStep) f) =>
      ws.updateStep(id, f);

  /// Things a block can read data from: earlier requests and the variables made before it.
  (List<WorkflowStep>, List<String>) sources(String id) =>
      (steps.requestsBefore(id), steps.variablesBefore(id));

  List<Avail> available(String forId) {
    final out = <String, Avail>{};
    final (reqs, vars) = sources(forId);
    for (final st in reqs) {
      final res = ws.runs[st.id]?.result;
      for (final o in st.outputs.where((o) => o.name.trim().isNotEmpty)) {
        out[o.name.trim()] = Avail(
          o.name.trim(),
          res == null ? null : o.valueIn(res).$1,
          'from ${name(st)}',
          false,
        ); // a later step's value replaces an earlier one
      }
    }
    for (final v in vars) {
      out[v] = Avail(v, null, 'loop / Set variable', true);
    }
    return out.values.toList();
  }

  /// The recorded execution behind log entry [index] (the n-th time that request block ran), if it still exists.
  StepRun? runFor(int index) {
    final all = ws.events;
    if (index < 0 || index >= all.length) return null;
    final e = all[index];
    if (!(e.kind == StepKind.Request && !e.sub)) return null;
    final hist = ws.history[e.stepId];
    if (hist == null) return null;
    bool same(RunEvent x) =>
        x.stepId == e.stepId && x.kind == StepKind.Request && !x.sub;
    final nth = all.take(index).where(same).length;
    final i = nth - (all.where(same).length - hist.length);
    return i >= 0 && i < hist.length ? hist[i] : null;
  }

  /// The passed-on values (with where they come from) that [text] uses, as known at block [forId].
  List<Avail> usedIn(String text, String forId) {
    if (!text.contains('{')) return const [];
    final av = {for (final a in available(forId)) a.name: a};
    return [
      for (final n in FlowRefs.names(text))
        if (av[n] != null) av[n]!,
    ];
  }

  /// Everything a request step takes from earlier steps: in the request itself and in this workflow's edits of it.
  List<Avail> usedBy(WorkflowStep st) {
    final req = col.requestByRef(st.request)?.request;
    final sb = StringBuffer();
    if (req != null) {
      sb.write('${req.url}\n');
      for (final h in req.headers) {
        sb.write('${h.value}\n');
      }
      for (final h in req.params) {
        sb.write('${h.value}\n');
      }
      for (final h in req.pathParams) {
        sb.write('${h.value}\n');
      }
      sb
        ..write(req.bodyJson)
        ..write(req.bodyText)
        ..write(req.bodyXml)
        ..write(req.auth.token);
    }
    for (final i in st.inputs) {
      sb.write('\n${i.value}');
    }
    return usedIn(sb.toString(), st.id);
  }

  static final RegExp _tpl = RegExp(
    r'(?<!\{)\{([A-Za-z_][A-Za-z0-9_]*)((?:\.[^{}\s]*)?)\}|\{\{\s*([A-Za-z_][A-Za-z0-9_]*)((?:\.[^{}\s]*)?)\s*\}\}',
  );

  /// `{name}` / `{name.field}` in [text] replaced by the values known from the last run; null if nothing could be filled in.
  String? preview(String text, String forId) {
    if (!text.contains('{')) return null;
    final known = {
      for (final a in available(forId).where((a) => a.value != null)) a.name: a,
    };
    var hit = false;
    final r = text.replaceAllMapped(_tpl, (m) {
      final nm = (m.group(1) ?? '').isNotEmpty
          ? m.group(1)!
          : (m.group(3) ?? '');
      final dotted = (m.group(2) ?? '').isNotEmpty
          ? m.group(2)!
          : (m.group(4) ?? '');
      final a = known[nm];
      if (a == null) return m.group(0)!;
      final rest = dotted.startsWith('.') ? dotted.substring(1) : dotted;
      String v;
      if (rest.isEmpty) {
        v = a.value!;
      } else {
        final f = WorkflowRunner.field(a.value!, rest);
        if (f == null) return m.group(0)!;
        v = f;
      }
      hit = true;
      return v;
    });
    return hit ? r.replaceAll('\n', ' ') : null;
  }

  WfVars fieldVars(String forId) {
    final flow = <String>{};
    final flowInfo = <String, VarInfo>{};
    for (final a in available(forId)) {
      flow.add(a.name);
      final v = a.value;
      flowInfo[a.name] = VarInfo(
        v != null
            ? (v.replaceAll('\n', ' ').isEmpty
                  ? '(empty)'
                  : v.replaceAll('\n', ' '))
            : (a.variable ? '' : 'passed on — run to see the value'),
        a.from,
      );
    }
    final env = <String>{...state.knownVars(tab)};
    final envInfo = <String, VarInfo>{};
    state.varInfo(tab).forEach((k, v) => envInfo[k] = VarInfo(v.$1, v.$2));
    return WfVars(env, envInfo, flow, flowInfo);
  }
}

WorkflowStep setOverride(WorkflowStep s, InputTarget t, String name, String v) {
  final i = s.inputs.indexWhere(
    (it) => it.target == t && it.name.trim() == name,
  );
  List<StepInput> inputs;
  if (v.trim().isEmpty && i >= 0) {
    inputs = [
      for (var k = 0; k < s.inputs.length; k++)
        if (k != i) s.inputs[k],
    ];
  } else if (i >= 0) {
    inputs = [
      for (var k = 0; k < s.inputs.length; k++)
        k == i ? s.inputs[k].copyWith(value: v) : s.inputs[k],
    ];
  } else if (v.trim().isEmpty) {
    inputs = s.inputs;
  } else {
    inputs = [...s.inputs, StepInput(target: t, name: name, value: v)];
  }
  return s.copyWith(inputs: inputs);
}

/// Workflow builder + runner, shown as an editor tab.
class WorkflowView extends StatelessWidget {
  const WorkflowView({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, tab]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final pal = context.pal;
    final ws = tab.workflow;
    if (ws == null) return const SizedBox.shrink();
    final col = state.collection(tab.collectionPath);
    if (col == null) return const SizedBox.shrink();
    final c = Wf(state, tab, col);
    final wf = ws.draft;
    final failed = ws.events.where((e) => !e.ok).length;
    final reqMs = ws.runs.values.fold<int>(
      0,
      (a, r) => a + (r.result?.response?.timeMs ?? 0),
    );
    return Container(
      color: pal.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DrawBottomBorder(
            color: pal.border,
            child: Container(
              color: pal.panel,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                spacing: 12,
                children: [
                  Ico(Ic.workflow, tint: pal.accent, size: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 160,
                      maxWidth: 320,
                    ),
                    child: Field(
                      value: wf.name,
                      onChange: (n) => ws.update((it) => it.copyWith(name: n)),
                      placeholder: 'Workflow name',
                      highlightVars: false,
                    ),
                  ),
                  LabeledCheck(
                    label: 'Stop when a request fails',
                    checked: wf.stopOnFail,
                    onChange: (v) =>
                        ws.update((it) => it.copyWith(stopOnFail: v)),
                  ),
                  const Spacer(),
                  if (ws.events.isNotEmpty) ...[
                    Chip(
                      '${ws.events.length} step${ws.events.length == 1 ? "" : "s"} ran',
                      color: failed == 0 ? pal.ok : pal.muted,
                    ),
                    if (failed > 0)
                      Chip(
                        '$failed problem${failed == 1 ? "" : "s"}',
                        color: pal.err,
                      ),
                    T('$reqMs ms in requests', color: pal.muted, size: 12),
                  ],
                  Btn(
                    label: 'Save',
                    onClick: () => state.saveWorkflow(tab),
                    icon: Ic.save,
                    primary: ws.dirty && !ws.running,
                    enabled: ws.dirty,
                  ),
                  if (ws.running)
                    Btn(
                      label: 'Stop',
                      onClick: () => ws.cancelled = true,
                      danger: true,
                      icon: Ic.stop,
                    )
                  else
                    Btn(
                      label: 'Run',
                      onClick: () => state.runWorkflow(tab),
                      primary: !ws.dirty,
                      icon: Ic.play,
                      enabled: wf.steps.walk().any((it) => it.enabled),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wf.steps.isEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(24),
                            // The border only paints, so it stays out of the layout.
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: pal.border, width: 1),
                            ),
                            child: Column(
                              spacing: 8,
                              children: [
                                Ico(Ic.workflow, tint: pal.muted, size: 34),
                                const T(
                                  'Build a business process from API calls and logic',
                                  weight: FontWeight.w600,
                                  size: 15,
                                ),
                                T(
                                  'Add requests from this collection, then click a step to configure it. Add If / else, loops, counters and variables to control the flow.',
                                  color: pal.muted,
                                  size: 12,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        ...blockList(c, null, 0, wf.steps),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
                if (c.selectedId != null) ...[
                  Container(width: 1, color: pal.border),
                  Container(
                    width: 560,
                    color: pal.panel,
                    child: _ConfigPane(c: c),
                  ),
                ],
              ],
            ),
          ),
          DockedLog(c: c),
        ],
      ),
    );
  }
}

/// The side pane: header (what is selected, run to here) and the block's full configuration.
class _ConfigPane extends StatelessWidget {
  const _ConfigPane({required this.c});
  final Wf c;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final id = c.selectedId;
    final st = id == null ? null : c.steps.findStep(id);
    if (st == null) return const SizedBox.shrink();
    final isReq = st.kind == StepKind.Request;
    return Column(
      key: ValueKey('cfg-${st.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DrawBottomBorder(
          color: pal.border,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              spacing: 10,
              children: [
                if (isReq)
                  Expanded(
                    child: T(
                      c.name(st),
                      weight: FontWeight.w600,
                      size: 15,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Expanded(
                    child: Field(
                      value: st.title,
                      onChange: (v) =>
                          c.update(st.id, (it) => it.copyWith(title: v)),
                      placeholder: '${st.kind.label} — name (optional)',
                      bordered: false,
                      highlightVars: false,
                    ),
                  ),
                T(
                  isReq ? 'REQUEST STEP' : st.kind.label.toUpperCase(),
                  color: pal.muted,
                  size: 10,
                  weight: FontWeight.w600,
                ),
                LabeledCheck(
                  label: 'On',
                  checked: st.enabled,
                  onChange: (v) =>
                      c.update(st.id, (it) => it.copyWith(enabled: v)),
                ),
                IconBtn(
                  icon: Ic.close,
                  onClick: () => c.ws.selected = null,
                  size: 17,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                if (!st.enabled)
                  T(
                    'This block is switched off — it is skipped when the workflow runs.',
                    color: pal.muted,
                    size: 12,
                  ),
                if (isReq)
                  RequestConfig(c: c, st: st)
                else
                  LogicConfig(c: c, st: st),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Thin vertical guide lines, one per nesting level.
class GuidesPainter extends CustomPainter {
  GuidesPainter(this.levels, this.color);
  final int levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i < levels; i++) {
      final x = (i * 14 + 6).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(GuidesPainter old) =>
      old.levels != levels || old.color != color;
}

/// A list of blocks with the "add" button below; used for the top level and for every branch of If / Loop.
/// Returns the widgets so the caller can splice them into its own column.
List<Widget> blockList(
  Wf c,
  String? parent,
  int branch,
  List<WorkflowStep> steps,
) {
  return [
    for (final st in steps) ...[
      KeyedSubtree(
        key: ValueKey('blk-${st.id}'),
        child: _BlockCard(c: c, st: st),
      ),
      Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.only(left: 25),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 2, height: 14, color: context.pal.border),
          ),
        ),
      ),
    ],
    Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Btn(
          label: steps.isEmpty && parent == null
              ? 'Add first step'
              : 'Add step',
          onClick: () => c.state.modal = ModalAddStep(
            tabId: c.tab.id,
            parent: parent,
            branch: branch,
          ),
          icon: Ic.add,
          primary: steps.isEmpty && parent == null,
        ),
      ],
    ),
  ];
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  Widget build(BuildContext context) => st.kind == StepKind.Request
      ? RequestRow(c: c, st: st)
      : LogicRow(c: c, st: st);
}

/// One block in the outline: badge, name, status, actions; clicking it opens its configuration in the side pane.
class Frame extends StatelessWidget {
  const Frame({
    super.key,
    required this.c,
    required this.st,
    required this.badge,
    required this.title,
    this.trailing = const [],
    this.sub,
    this.extra = const [],
  });

  final Wf c;
  final WorkflowStep st;
  final Widget badge;

  /// Placed in the header row; should size itself (usually an `Expanded`).
  final Widget title;
  final List<Widget> trailing;
  final Widget? sub;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final active = c.ws.current == st.id && c.ws.running;
    final selected = c.selectedId == st.id;
    return Container(
      // The border is painted on top of the content and takes no layout space.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          width: selected || active ? 2 : 1,
          color: active
              ? pal.accent
              : (selected ? pal.accent.withValues(alpha: 0.75) : pal.border),
        ),
      ),
      child: Clickable(
        onClick: () => c.ws.selected = st.id,
        cursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? pal.accent.withValues(alpha: 0.09) : pal.field,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Row(
                spacing: 8,
                children: [
                  badge,
                  Check(
                    checked: st.enabled,
                    onChange: (v) =>
                        c.update(st.id, (it) => it.copyWith(enabled: v)),
                  ),
                  title,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      ...trailing,
                      if (!c.ws.running && st.enabled)
                        IconBtn(
                          icon: Ic.play,
                          onClick: () => c.state.runWorkflow(c.tab, st.id),
                          color: pal.accent,
                          size: 15,
                        ),
                      IconBtn(
                        icon: Ic.moveUp,
                        onClick: () =>
                            c.state.moveWorkflowStep(c.tab, st.id, -1),
                        size: 14,
                      ),
                      IconBtn(
                        icon: Ic.moveDown,
                        onClick: () =>
                            c.state.moveWorkflowStep(c.tab, st.id, 1),
                        size: 14,
                      ),
                      IconBtn(
                        icon: Ic.delete,
                        onClick: () => c.state.removeWorkflowStep(c.tab, st.id),
                        color: pal.err,
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
              if (sub != null)
                Padding(padding: const EdgeInsets.only(left: 36), child: sub),
              ...extra,
            ],
          ),
        ),
      ),
    );
  }
}

/// "Where does this come from": one line per passed-on value a field uses.
class UsedInfo extends StatelessWidget {
  const UsedInfo({super.key, required this.used});
  final List<Avail> used;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        for (final a in used)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              T('←', color: pal.muted, size: 11),
              T(
                '{${a.name}}',
                color: pal.accent,
                size: 11,
                mono: true,
                weight: FontWeight.w600,
              ),
              T(a.from, color: pal.muted, size: 11),
              if (a.value != null)
                Flexible(
                  child: T(
                    '·  ${(() {
                      final v = a.value!.replaceAll('\n', ' ');
                      final cut = v.length > 60 ? v.substring(0, 60) : v;
                      return cut.isEmpty ? '(empty)' : cut;
                    })()}',
                    color: pal.muted,
                    size: 11,
                    mono: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Provides the two completion lists (`{{env}}` and `{passed-on}`) for fields of block [forId].
class WithVars extends StatelessWidget {
  const WithVars({
    super.key,
    required this.c,
    required this.forId,
    required this.child,
  });
  final Wf c;
  final String forId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final v = c.fieldVars(forId);
    return LocalVars(
      value: v.env,
      child: LocalVarInfo(
        value: v.envInfo,
        child: LocalFlowVars(
          value: v.flow,
          child: LocalFlowInfo(value: v.flowInfo, child: child),
        ),
      ),
    );
  }
}
