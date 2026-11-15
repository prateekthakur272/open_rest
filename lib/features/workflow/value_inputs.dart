import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state_workflows.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_builder.dart';
import 'package:open_rest/features/workflow/workflow_view.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

Widget _click(VoidCallback onTap, Widget child, {BorderRadius? radius}) =>
    Clickable(
      onClick: onTap,
      cursor: SystemMouseCursors.click,
      borderRadius: radius,
      child: child,
    );

/// A text field for a template value; `{` completes passed-on values, `{{` environment variables, and a button opens the list of available values.
class ValueInput extends StatefulWidget {
  const ValueInput({
    super.key,
    required this.c,
    required this.forId,
    required this.value,
    required this.onChange,
    required this.placeholder,
    this.mono = true,
  });
  final Wf c;
  final String forId;
  final String value;
  final ValueChanged<String> onChange;
  final String placeholder;
  final bool mono;

  @override
  State<ValueInput> createState() => _ValueInputState();
}

class _ValueInputState extends State<ValueInput> {
  bool picking = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c, forId = widget.forId, value = widget.value;
    final canLink =
        c.available(forId).isNotEmpty ||
        c.steps.requestsBefore(forId).isNotEmpty;
    final pv = c.preview(value, forId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          spacing: 6,
          children: [
            Expanded(
              child: WithVars(
                c: c,
                forId: forId,
                child: Field(
                  value: value,
                  onChange: widget.onChange,
                  placeholder: widget.placeholder,
                  mono: widget.mono,
                  highlightVars: true,
                ),
              ),
            ),
            if (canLink)
              Btn(
                label: 'Use value',
                onClick: () => setState(() => picking = !picking),
                primary: picking,
                icon: Ic.variables,
              ),
          ],
        ),
        if (pv != null)
          T('= $pv', color: pal.ok, size: 11, mono: true, maxLines: 1),
        if (c.usedIn(value, forId).isNotEmpty)
          UsedInfo(used: c.usedIn(value, forId)),
        if (picking)
          ValuePicker(
            c: c,
            forId: forId,
            onInsert: (tok) {
              widget.onChange(value + tok);
              setState(() => picking = false);
            },
            onClose: () => setState(() => picking = false),
          ),
      ],
    );
  }
}

/// The values available at this point, by name. Click one to insert `{name}`. A value that no step passes on yet can be
/// picked straight from a response; that adds it to the producing step's "Pass on" list.
class ValuePicker extends StatefulWidget {
  const ValuePicker({
    super.key,
    required this.c,
    required this.forId,
    required this.onInsert,
    this.targetLabel,
    required this.onClose,
  });
  final Wf c;
  final String forId;
  final ValueChanged<String> onInsert;
  final String? targetLabel;
  final VoidCallback onClose;

  @override
  State<ValuePicker> createState() => _ValuePickerState();
}

class _ValuePickerState extends State<ValuePicker> {
  String filter = '';
  String manual = '';
  late bool more;
  late String stepId;

  @override
  void initState() {
    super.initState();
    final avail = widget.c.available(widget.forId);
    final reqs = widget.c.steps.requestsBefore(widget.forId);
    more = avail.isEmpty && reqs.isNotEmpty;
    String? id;
    for (final r in reqs) {
      if (widget.c.ws.runs[r.id] != null) id = r.id;
    }
    stepId = id ?? (reqs.isEmpty ? '' : reqs.last.id);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c, forId = widget.forId;
    final avail = c.available(forId);
    final reqs = c.steps.requestsBefore(forId);
    final f = filter.trim().toLowerCase();
    final shown = avail
        .where(
          (a) =>
              f.isEmpty ||
              a.name.toLowerCase().contains(f) ||
              (a.value ?? '').toLowerCase().contains(f),
        )
        .toList();
    final nums = c.numbers;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              T(
                widget.targetLabel != null
                    ? 'Fill “${widget.targetLabel}” with'
                    : 'Use a value',
                color: pal.muted,
                size: 12,
              ),
              if (avail.length > 6)
                Expanded(
                  child: Field(
                    value: filter,
                    onChange: (v) => setState(() => filter = v),
                    placeholder: 'Search…',
                    highlightVars: false,
                  ),
                )
              else
                const Spacer(),
              IconBtn(icon: Ic.close, onClick: widget.onClose, size: 14),
            ],
          ),
          if (avail.isEmpty)
            T(
              'Nothing is passed on yet. Add values under “Pass on to later steps” in the step that produces them — or pick one from a response below.',
              color: pal.muted,
              size: 12,
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in shown)
                    _click(
                      () => widget.onInsert('{${a.name}}'),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        child: Row(
                          spacing: 12,
                          children: [
                            Expanded(
                              child: T(
                                '{${a.name}}',
                                mono: true,
                                size: 13,
                                weight: FontWeight.w600,
                                color: pal.accent,
                                maxLines: 1,
                              ),
                            ),
                            Expanded(
                              child: T(
                                a.value == null
                                    ? (a.variable ? '' : 'run to see the value')
                                    : a.value!.isEmpty
                                    ? '(empty)'
                                    : (() {
                                        final v = a.value!.replaceAll(
                                          '\n',
                                          ' ',
                                        );
                                        return v.length > 60
                                            ? v.substring(0, 60)
                                            : v;
                                      })(),
                                mono: true,
                                size: 12,
                                color: pal.muted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            T(a.from, size: 11, color: pal.muted, maxLines: 1),
                          ],
                        ),
                      ),
                      radius: BorderRadius.circular(4),
                    ),
                  if (shown.isEmpty && avail.isNotEmpty)
                    T('Nothing matches “$filter”.', color: pal.muted, size: 12),
                ],
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              T('or type a name / field', color: pal.muted, size: 12),
              Expanded(
                child: Field(
                  value: manual,
                  onChange: (v) => setState(() => manual = v),
                  placeholder: 'e.g. item.id or user.name (Enter)',
                  mono: true,
                  highlightVars: false,
                  onEnter: () {
                    if (manual.trim().isNotEmpty) {
                      widget.onInsert('{${manual.trim()}}');
                    }
                  },
                ),
              ),
            ],
          ),
          if (reqs.isNotEmpty) ...[
            Row(
              children: [
                _click(
                  () => setState(() => more = !more),
                  T(
                    more
                        ? 'Hide response fields ▲'
                        : 'Pick a field from a response ▼',
                    color: pal.accent,
                    size: 12,
                  ),
                ),
              ],
            ),
            if (more) ..._responseFields(context, reqs, nums),
          ],
        ],
      ),
    );
  }

  List<Widget> _responseFields(
    BuildContext context,
    List<WorkflowStep> reqs,
    Map<String, int> nums,
  ) {
    final pal = context.pal;
    final c = widget.c;
    final options = [
      for (final r in reqs) ('${c.name(r)}  (step ${nums[r.id]})', r.id),
    ];
    final run = c.ws.runs[stepId];
    final fields = ResponseFields.of(run?.result);
    String? curLabel;
    for (final o in options) {
      if (o.$2 == stepId) curLabel = o.$1;
    }
    return [
      Row(
        spacing: 8,
        children: [
          T('From the response of', color: pal.muted, size: 12),
          Flexible(
            child: Dropdown(
              selected: curLabel ?? '',
              options: options.map((o) => o.$1).toList(),
              onSelect: (l) => setState(
                () => stepId = options.firstWhere((o) => o.$1 == l).$2,
              ),
            ),
          ),
        ],
      ),
      if (run == null)
        Row(
          spacing: 8,
          children: [
            T("That step hasn't run yet.", color: pal.muted, size: 12),
            Btn(
              label: 'Run up to it',
              onClick: () => c.state.runWorkflow(c.tab, stepId),
              icon: Ic.play,
              primary: true,
              enabled: !c.ws.running,
            ),
          ],
        )
      else if (fields.isEmpty)
        T('That step has no usable response.', color: pal.err, size: 12)
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in fields)
                  _click(
                    () {
                      final taken = c.steps
                          .walk()
                          .expand((s) => s.outputs)
                          .map((o) => o.name.trim())
                          .toSet();
                      StepOutput? existing;
                      for (final o
                          in c.steps.findStep(stepId)?.outputs ??
                              const <StepOutput>[]) {
                        if (o.kind == f.kind &&
                            o.path == f.path &&
                            o.name.trim().isNotEmpty) {
                          existing = o;
                          break;
                        }
                      }
                      String name;
                      if (existing != null) {
                        name = existing.name.trim();
                      } else {
                        name = suggestName(f);
                        var i = 2;
                        while (taken.contains(name)) {
                          name = suggestName(f) + (i++).toString();
                        }
                      }
                      if (existing == null) {
                        c.update(
                          stepId,
                          (s) => s.copyWith(
                            outputs: [
                              ...s.outputs,
                              StepOutput(
                                name: name,
                                kind: f.kind,
                                path: f.path,
                              ),
                            ],
                          ),
                        );
                      }
                      widget.onInsert('{$name}');
                    },
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          Expanded(
                            child: T(
                              f.label,
                              mono: true,
                              size: 12,
                              color: pal.syntaxKey,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: T(
                              f.preview,
                              mono: true,
                              size: 12,
                              color: pal.muted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    radius: BorderRadius.circular(4),
                  ),
              ],
            ),
          ),
        ),
      T(
        "Picking a field adds it to that step's “Pass on to later steps” so it keeps flowing.",
        color: pal.muted,
        size: 11,
      ),
    ];
  }
}

/// A short, valid output name for a response field (`data.items[0].id` → `id`, `header Content-Type` → `contentType`).
String suggestName(ResponseField f) {
  String raw;
  switch (f.kind) {
    case SourceKind.Field:
      final after = f.path.contains('.')
          ? f.path.substring(f.path.lastIndexOf('.') + 1)
          : f.path;
      final b = after.contains('[')
          ? after.substring(0, after.indexOf('['))
          : after;
      if (b.isNotEmpty) {
        raw = b;
      } else {
        raw = f.path.contains('[')
            ? f.path.substring(0, f.path.indexOf('['))
            : f.path;
      }
    case SourceKind.Header:
      raw = f.path;
    case SourceKind.Status:
      raw = 'status';
    case SourceKind.Time:
      raw = 'responseTime';
    case SourceKind.Body:
      raw = 'body';
    case SourceKind.Response:
      raw = 'response';
  }
  final parts = raw
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  String cap(String w, bool up) => w.isEmpty
      ? w
      : (up ? w[0].toUpperCase() : w[0].toLowerCase()) + w.substring(1);
  final out = [for (var i = 0; i < parts.length; i++) cap(parts[i], i != 0)]
      .join();
  return out.isEmpty ? 'value' : out;
}

/// One value of a request (a header value, a path param, the URL, a body field…).
/// Shows the request's real value; typing changes it for this workflow only. `{name}` uses a value passed on by an earlier step.
class ValueCell extends StatefulWidget {
  const ValueCell({
    super.key,
    required this.c,
    required this.forId,
    required this.value,
    required this.current,
    required this.onSet,
    required this.targetLabel,
    this.resolved,
    this.needsValue = false,
  });

  final Wf c;
  final String forId;
  final String value;
  final String current;
  final ValueChanged<String> onSet;
  final String targetLabel;
  final String? resolved;
  final bool needsValue;

  @override
  State<ValueCell> createState() => _ValueCellState();
}

class _ValueCellState extends State<ValueCell> {
  bool picking = false;

  // Local text so clearing the field while typing does not snap back.
  late String text = widget.value.trim().isNotEmpty
      ? widget.value
      : widget.current;

  @override
  void didUpdateWidget(ValueCell old) {
    super.didUpdateWidget(old);
    final has = widget.value.trim().isNotEmpty;
    final want = has ? widget.value : widget.current;
    if ((old.value != widget.value || old.current != widget.current) &&
        want != text &&
        !(text.isEmpty && !has)) {
      text = want;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c,
        forId = widget.forId,
        value = widget.value,
        current = widget.current;
    final canLink =
        c.available(forId).isNotEmpty ||
        c.steps.requestsBefore(forId).isNotEmpty;
    final has = value.trim().isNotEmpty;
    final shownText = has ? value : text;
    final preview = widget.resolved ?? c.preview(shownText, forId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: WithVars(
                c: c,
                forId: forId,
                child: Field(
                  value: text,
                  onChange: (v) {
                    setState(() => text = v);
                    widget.onSet(v == current ? '' : v);
                  },
                  placeholder: widget.needsValue
                      ? 'needs a value — type { to use a passed-on value'
                      : (current.isEmpty ? '(empty)' : current),
                  mono: true,
                  highlightVars: true,
                ),
              ),
            ),
            if (canLink)
              Btn(
                label: 'Use value',
                onClick: () => setState(() => picking = !picking),
                primary: picking || (widget.needsValue && !has),
                icon: Ic.variables,
              ),
            if (has)
              IconBtn(
                icon: Ic.refresh,
                onClick: () {
                  widget.onSet('');
                  setState(() => text = current);
                },
                color: pal.accent,
                size: 15,
              ),
          ],
        ),
        if (preview != null)
          T(
            '= ${(() {
              final v = preview.replaceAll('\n', ' ');
              final cut = v.length > 120 ? v.substring(0, 120) : v;
              return cut.isEmpty ? '(empty)' : cut;
            })()}',
            color: preview.isEmpty && widget.resolved != null
                ? pal.err
                : pal.ok,
            size: 11,
            mono: true,
            maxLines: 1,
          ),
        if (c.usedIn(shownText, forId).isNotEmpty)
          UsedInfo(used: c.usedIn(shownText, forId)),
        if (picking)
          ValuePicker(
            c: c,
            forId: forId,
            onInsert: (tok) {
              // a value that is just one {{name}} gets replaced; otherwise the name is added to what was typed (e.g. "Bearer ")
              final single =
                  has && RegExp(r'^\s*\{\{?[^{}]+\}\}?\s*$').hasMatch(value);
              widget.onSet(has && !single ? value + tok : tok);
              setState(() => picking = false);
            },
            targetLabel: widget.targetLabel,
            onClose: () => setState(() => picking = false),
          ),
      ],
    );
  }
}

/// A labelled [ValueCell] bound to the step's override for ([target], [name]).
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.c,
    required this.st,
    required this.target,
    required this.name,
    required this.current,
    required this.label,
    this.needsValue = false,
  });
  final Wf c;
  final WorkflowStep st;
  final InputTarget target;
  final String name;
  final String current;
  final String label;
  final bool needsValue;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    var value = '';
    for (final i in st.inputs) {
      if (i.target == target && i.name.trim() == name) {
        value = i.value;
        break;
      }
    }
    String? resolved;
    final key = target.needsKey ? '${target.label} $name' : target.label;
    final run = c.ws.runs[st.id];
    if (run != null) {
      for (final i in run.inputs) {
        if (i.$1 == key) {
          resolved = i.$2;
          break;
        }
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        SizedBox(
          width: 190,
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Row(
              spacing: 5,
              children: [
                if (value.trim().isNotEmpty)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: pal.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Flexible(
                  child: T(
                    label,
                    size: 12,
                    color: needsValue && value.trim().isEmpty
                        ? pal.err
                        : pal.text,
                    mono: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ValueCell(
            c: c,
            forId: st.id,
            value: value,
            current: current,
            onSet: (v) =>
                c.update(st.id, (s) => setOverride(s, target, name, v)),
            targetLabel: Slots.label(target, name),
            resolved: resolved,
            needsValue: needsValue,
          ),
        ),
      ],
    );
  }
}

/// Rows added only for this workflow (a header the request doesn't have, an extra query parameter or body field).
/// Returned as a list so they spread straight into the caller's column (an empty list adds no spacing).
List<Widget> addedRows({
  required Wf c,
  required WorkflowStep st,
  required InputTarget target,
  required List<Slot> slots,
  required String nameHint,
}) {
  Widget row(int k) {
    final inp = st.inputs[k];
    void setAt(StepInput Function(StepInput) f) => c.update(
      st.id,
      (s) => s.copyWith(
        inputs: [
          for (var i = 0; i < s.inputs.length; i++)
            i == k ? f(s.inputs[i]) : s.inputs[i],
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        SizedBox(
          width: 190,
          child: Field(
            value: inp.name,
            onChange: (n) => setAt((x) => x.copyWith(name: n)),
            placeholder: nameHint,
            mono: true,
            highlightVars: false,
          ),
        ),
        Expanded(
          child: ValueCell(
            key: ValueKey('added-${st.id}-$k'),
            c: c,
            forId: st.id,
            value: inp.value,
            current: '',
            onSet: (v) => setAt((x) => x.copyWith(value: v)),
            targetLabel: Slots.label(
              target,
              inp.name.trim().isEmpty ? '…' : inp.name.trim(),
            ),
          ),
        ),
        IconBtn(
          icon: Ic.close,
          onClick: () => c.update(
            st.id,
            (s) => s.copyWith(
              inputs: [
                for (var i = 0; i < s.inputs.length; i++)
                  if (i != k) s.inputs[i],
              ],
            ),
          ),
          size: 14,
        ),
      ],
    );
  }

  return [
    for (var k = 0; k < st.inputs.length; k++)
      if (st.inputs[k].target == target &&
          !slots.any(
            (it) =>
                it.target == target &&
                it.name == st.inputs[k].name.trim() &&
                st.inputs[k].name.trim().isNotEmpty,
          ))
        row(k),
  ];
}

/// Small button that appends a new row to a list editor.
class AddRowButton extends StatelessWidget {
  const AddRowButton({
    super.key,
    required this.c,
    required this.st,
    required this.target,
    required this.label,
  });
  final Wf c;
  final WorkflowStep st;
  final InputTarget target;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Btn(
        label: label,
        onClick: () => c.update(
          st.id,
          (it) => it.copyWith(
            inputs: [
              ...it.inputs,
              StepInput(target: target),
            ],
          ),
        ),
        icon: Ic.add,
      ),
    ],
  );
}

String uniqueName(List<StepOutput> existing, String base) {
  var n = base;
  var i = 2;
  while (existing.any((it) => it.name == n)) {
    n = '$base${i++}';
  }
  return n;
}
