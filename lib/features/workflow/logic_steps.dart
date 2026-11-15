import 'package:flutter/widgets.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/features/workflow/value_inputs.dart';
import 'package:open_rest/features/workflow/workflow_view.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

final RegExp _nameChars = RegExp(r'[^\p{L}\p{N}_]', unicode: true);
String _ident(String v) => v.replaceAll(_nameChars, '');
String _orDefault(String v, String d) => v.trim().isEmpty ? d : v;

/// Row for a logic step in the flow outline.
class LogicRow extends StatelessWidget {
  const LogicRow({super.key, required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final tag = switch (st.kind) {
      StepKind.If => 'IF',
      StepKind.Loop => 'LOOP',
      StepKind.Set => 'SET',
      StepKind.Wait => 'WAIT',
      _ => 'STOP',
    };
    final tagColor = switch (st.kind) {
      StepKind.If => pal.syntaxKey,
      StepKind.Loop => pal.accent,
      StepKind.Set => pal.ok,
      StepKind.Wait => pal.muted,
      _ => pal.err,
    };
    return Frame(
      c: c,
      st: st,
      badge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tagColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        child: T(tag, color: tagColor, weight: FontWeight.w700, size: 11),
      ),
      title: Expanded(
        child: T(
          _orDefault(st.title, st.kind.label),
          weight: FontWeight.w600,
          color: st.enabled ? pal.text : pal.muted,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      sub: T(
        c.summary(st),
        color: pal.muted,
        size: 12,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      extra: [
        if (st.kind == StepKind.If) ...[
          _Branch(c: c, st: st, title: 'THEN', branch: 0, steps: st.children),
          _Branch(c: c, st: st, title: 'ELSE', branch: 1, steps: st.otherwise),
        ] else if (st.kind == StepKind.Loop)
          _Branch(
            c: c,
            st: st,
            title: 'REPEAT THESE STEPS',
            branch: 0,
            steps: st.children,
          ),
      ],
    );
  }
}

/// Settings of a logic block, in the side pane. (Its nested steps live in the outline.)
class LogicConfig extends StatelessWidget {
  const LogicConfig({super.key, required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    void upd(WorkflowStep Function(WorkflowStep) f) => c.update(st.id, f);
    final id = st.id;
    final List<Widget> body;
    switch (st.kind) {
      case StepKind.If:
        body = [_Conditions(c: c, st: st)];
      case StepKind.Loop:
        body = [
          Row(
            spacing: 8,
            children: [
              Dropdown(
                selected: st.loop.label,
                options: LoopMode.values.map((e) => e.label).toList(),
                onSelect: (l) => upd((s) {
                  final m = LoopMode.values.firstWhere((e) => e.label == l);
                  return s.copyWith(
                    loop: m,
                    count: m == LoopMode.Repeat && s.count.trim().isEmpty
                        ? '3'
                        : s.count,
                    conditions: m == LoopMode.While && s.conditions.isEmpty
                        ? const [Condition()]
                        : s.conditions,
                  );
                }),
              ),
              T('at most', color: pal.muted, size: 12),
              SizedBox(
                width: 70,
                child: Field(
                  value: st.maxIterations.toString(),
                  onChange: (v) {
                    final d = v
                        .split('')
                        .where(
                          (ch) =>
                              ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57,
                        )
                        .join();
                    final n = int.tryParse(
                      d.length > 4 ? d.substring(0, 4) : d,
                    );
                    if (n != null) upd((it) => it.copyWith(maxIterations: n));
                  },
                  placeholder: '100',
                  highlightVars: false,
                ),
              ),
              T('rounds', color: pal.muted, size: 12),
            ],
          ),
          if (st.loop == LoopMode.ForEach) ...[
            T(
              'List to loop over — e.g. Insert data → a response field that is a list (items, orders…)',
              color: pal.muted,
              size: 12,
            ),
            ValueInput(
              c: c,
              forId: id,
              value: st.list,
              onChange: (v) => upd((it) => it.copyWith(list: v)),
              placeholder: 'list, e.g. a response field holding an array',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                T('Call each item', color: pal.muted, size: 12),
                SizedBox(
                  width: 110,
                  child: Field(
                    value: st.itemVar,
                    onChange: (v) =>
                        upd((it) => it.copyWith(itemVar: _ident(v))),
                    placeholder: 'item',
                    mono: true,
                    highlightVars: false,
                  ),
                ),
                T('and its position', color: pal.muted, size: 12),
                SizedBox(
                  width: 110,
                  child: Field(
                    value: st.indexVar,
                    onChange: (v) =>
                        upd((it) => it.copyWith(indexVar: _ident(v))),
                    placeholder: 'index',
                    mono: true,
                    highlightVars: false,
                  ),
                ),
                T('(starts at 0)', color: pal.muted, size: 12),
              ],
            ),
            T(
              'Inside the loop use {${_orDefault(st.itemVar, "item")}} or a field of it like {${_orDefault(st.itemVar, "item")}.id}, and {${_orDefault(st.indexVar, "index")}}.',
              color: pal.muted,
              size: 11,
            ),
          ] else if (st.loop == LoopMode.Repeat) ...[
            T('How many times', color: pal.muted, size: 12),
            ValueInput(
              c: c,
              forId: id,
              value: st.count,
              onChange: (v) => upd((it) => it.copyWith(count: v)),
              placeholder: '3  (a number, or Insert data e.g. a count)',
            ),
            T(
              'The round number is {${_orDefault(st.indexVar, "index")}} (starts at 0).',
              color: pal.muted,
              size: 11,
            ),
          ] else ...[
            _Conditions(c: c, st: st),
            T(
              'The round number is {${_orDefault(st.indexVar, "index")}} (starts at 0). Checked before every round.',
              color: pal.muted,
              size: 11,
            ),
          ],
        ];
      case StepKind.Set:
        body = [
          Row(
            spacing: 8,
            children: [
              Dropdown(
                selected: st.setOp.label,
                options: SetOp.values.map((e) => e.label).toList(),
                onSelect: (l) => upd((s) {
                  final o = SetOp.values.firstWhere((e) => e.label == l);
                  final d = switch (o) {
                    SetOp.Count => 'count',
                    SetOp.Sum => 'total',
                    SetOp.First => 'first',
                    SetOp.Last => 'last',
                    _ => '',
                  };
                  return s.copyWith(
                    setOp: o,
                    varName: s.varName.trim().isEmpty ? d : s.varName,
                  );
                }),
              ),
              T('and call it', color: pal.muted, size: 12),
              SizedBox(
                width: 150,
                child: Field(
                  value: st.varName,
                  onChange: (v) => upd((it) => it.copyWith(varName: _ident(v))),
                  placeholder: 'variable name',
                  mono: true,
                  highlightVars: false,
                ),
              ),
            ],
          ),
          if (st.setOp.needsList) ...[
            T('List', color: pal.muted, size: 12),
            ValueInput(
              c: c,
              forId: id,
              value: st.list,
              onChange: (v) => upd((it) => it.copyWith(list: v)),
              placeholder: 'list, e.g. a response field holding an array',
            ),
            if (st.setOp == SetOp.Sum)
              Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: T(
                      'Field to add up (leave empty if the list holds plain numbers)',
                      color: pal.muted,
                      size: 12,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: Field(
                      value: st.path,
                      onChange: (v) => upd((it) => it.copyWith(path: v)),
                      placeholder: 'e.g. price',
                      mono: true,
                      highlightVars: false,
                    ),
                  ),
                ],
              ),
          ] else ...[
            T('Value', color: pal.muted, size: 12),
            ValueInput(
              c: c,
              forId: id,
              value: st.value,
              onChange: (v) => upd((it) => it.copyWith(value: v)),
              placeholder: 'text, a number, or Insert data',
            ),
          ],
          if (st.varName.trim().isNotEmpty)
            T(
              'Use it in later steps as {${st.varName}}${st.setOp == SetOp.First || st.setOp == SetOp.Last ? " (or {${st.varName}.field} for one field)" : ""}',
              color: pal.muted,
              size: 11,
            ),
        ];
      case StepKind.Wait:
        body = [
          T(
            'Milliseconds to wait (1000 = 1 second, up to 60000)',
            color: pal.muted,
            size: 12,
          ),
          ValueInput(
            c: c,
            forId: id,
            value: st.value,
            onChange: (v) => upd((it) => it.copyWith(value: v)),
            placeholder: '1000',
          ),
        ];
      case StepKind.Stop:
        body = [
          Row(
            spacing: 10,
            children: [
              Dropdown(
                selected: st.stopScope.label,
                options: StopScope.values.map((e) => e.label).toList(),
                onSelect: (l) => upd(
                  (it) => it.copyWith(
                    stopScope: StopScope.values.firstWhere((s) => s.label == l),
                  ),
                ),
              ),
              LabeledCheck(
                label: 'Mark as failed',
                checked: st.stopFail,
                onChange: (v) => upd((it) => it.copyWith(stopFail: v)),
              ),
            ],
          ),
          T('Message (optional)', color: pal.muted, size: 12),
          ValueInput(
            c: c,
            forId: id,
            value: st.value,
            onChange: (v) => upd((it) => it.copyWith(value: v)),
            placeholder: 'e.g. out of stock',
            mono: false,
          ),
        ];
      case StepKind.Request:
        body = const [];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: body,
    );
  }
}

class _Conditions extends StatelessWidget {
  const _Conditions({required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    void setConds(List<Condition> Function(List<Condition>) f) =>
        c.update(st.id, (it) => it.copyWith(conditions: f(it.conditions)));
    List<Condition> mapAt(
      List<Condition> l,
      int k,
      Condition Function(Condition) f,
    ) => [for (var i = 0; i < l.length; i++) i == k ? f(l[i]) : l[i]];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (var k = 0; k < st.conditions.length; k++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SizedBox(
                width: 26,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: T(
                    k == 0 ? 'If' : (st.matchAll ? 'and' : 'or'),
                    color: pal.muted,
                    size: 12,
                  ),
                ),
              ),
              Expanded(
                child: ValueInput(
                  c: c,
                  forId: st.id,
                  value: st.conditions[k].left,
                  onChange: (v) =>
                      setConds((l) => mapAt(l, k, (x) => x.copyWith(left: v))),
                  placeholder: 'value, e.g. a response status or a variable',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Dropdown(
                  selected: st.conditions[k].op.label,
                  options: CondOp.values.map((e) => e.label).toList(),
                  onSelect: (l) => setConds(
                    (list) => mapAt(
                      list,
                      k,
                      (x) => x.copyWith(
                        op: CondOp.values.firstWhere((o) => o.label == l),
                      ),
                    ),
                  ),
                ),
              ),
              if (st.conditions[k].op.needsRight)
                Expanded(
                  child: ValueInput(
                    c: c,
                    forId: st.id,
                    value: st.conditions[k].right,
                    onChange: (v) => setConds(
                      (l) => mapAt(l, k, (x) => x.copyWith(right: v)),
                    ),
                    placeholder: 'value',
                  ),
                )
              else
                const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: IconBtn(
                  icon: Ic.close,
                  onClick: () => setConds(
                    (l) => [
                      for (var i = 0; i < l.length; i++)
                        if (i != k) l[i],
                    ],
                  ),
                  size: 14,
                ),
              ),
            ],
          ),
        Row(
          spacing: 10,
          children: [
            Btn(
              label: 'Add condition',
              onClick: () => setConds((l) => [...l, const Condition()]),
              icon: Ic.add,
            ),
            if (st.conditions.length > 1)
              Dropdown(
                selected: st.matchAll ? 'All must be true' : 'Any can be true',
                options: const ['All must be true', 'Any can be true'],
                onSelect: (v) => c.update(
                  st.id,
                  (it) => it.copyWith(matchAll: v.startsWith('All')),
                ),
              ),
            if (st.conditions.isEmpty)
              T('No conditions: this is never true.', color: pal.err, size: 12),
          ],
        ),
      ],
    );
  }
}

/// A titled, indented list of nested blocks (Then / Else / loop body).
class _Branch extends StatelessWidget {
  const _Branch({
    required this.c,
    required this.st,
    required this.title,
    required this.branch,
    required this.steps,
  });
  final Wf c;
  final WorkflowStep st;
  final String title;
  final int branch;
  final List<WorkflowStep> steps;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        SectionLabel(title),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: pal.accent.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (steps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: T(
                      'Empty — nothing happens here.',
                      color: pal.muted,
                      size: 12,
                    ),
                  ),
                ...blockList(c, st.id, branch, steps),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
