import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state_workflows.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/run/workflow_builder.dart';
import 'package:open_rest/features/workflow/value_inputs.dart';
import 'package:open_rest/features/workflow/workflow_view.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Row for a request step in the flow outline.
class RequestRow extends StatelessWidget {
  const RequestRow({super.key, required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final ws = c.ws;
    final node = c.col.requestByRef(st.request);
    final req = node?.request;
    final run = ws.runs[st.id];
    final times = ws.counts[st.id] ?? 0;
    final active = ws.current == st.id && ws.running;
    final badge = active
        ? pal.accent
        : (run == null ? pal.muted : (run.failed ? pal.err : pal.ok));
    final changes = st.inputs.where((it) => it.value.trim().isNotEmpty).length;
    String? ovv(InputTarget t) {
      for (final i in st.inputs) {
        if (i.target == t && i.value.trim().isNotEmpty) return i.value;
      }
      return null;
    }

    final method =
        ovv(InputTarget.Method)?.trim().toUpperCase() ?? req?.method ?? '';
    final url = ovv(InputTarget.Url) ?? req?.url ?? '';
    final named = st.outputs.where((o) => o.name.trim().isNotEmpty).toList();
    final takes = c.usedBy(st);
    final resp =
        run?.result?.response != null && run!.result!.response!.error == null
        ? run.result!.response
        : null;
    return Frame(
      c: c,
      st: st,
      badge: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: badge.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: active
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: pal.accent,
                  strokeWidth: 2,
                  strokeCap: StrokeCap.round,
                ),
              )
            : T(
                '${c.numbers[st.id] ?? ""}',
                color: badge,
                weight: FontWeight.w700,
              ),
      ),
      title: Expanded(
        child: node != null
            ? T(
                c.name(st),
                weight: FontWeight.w600,
                color: st.enabled ? pal.text : pal.muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : T(
                'Missing request: ${st.request}',
                color: pal.err,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
      sub: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 3,
        children: [
          if (node != null)
            Row(
              spacing: 8,
              children: [
                MethodPill(method),
                Expanded(
                  child: T(
                    url,
                    color: pal.muted,
                    size: 11,
                    mono: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (resp != null ||
              run?.result?.error != null ||
              times > 1 ||
              changes > 0 ||
              named.isNotEmpty ||
              takes.isNotEmpty)
            Row(
              spacing: 8,
              children: [
                if (resp != null) ...[
                  T(
                    '${resp.status}',
                    color: statusColor(resp.status, pal),
                    weight: FontWeight.w600,
                    size: 12,
                  ),
                  T('${resp.timeMs} ms', color: pal.muted, size: 11),
                ],
                if (run != null && run.result?.error != null)
                  T('error', color: pal.err, size: 12),
                if (times > 1) Chip('×$times', color: pal.accent),
                if (changes > 0)
                  T('$changes edited', color: pal.accent, size: 11),
                if (takes.isNotEmpty)
                  Flexible(
                    child: T(
                      '← ${takes.map((a) => a.name).join(", ")}',
                      color: pal.muted,
                      size: 11,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (named.isNotEmpty)
                  Flexible(
                    child: T(
                      '→ ${named.map((o) => o.name).join(", ")}',
                      color: pal.muted,
                      size: 11,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Everything about a request step, in the side pane: the request itself, what it passes on, and its last result.
class RequestConfig extends StatefulWidget {
  const RequestConfig({super.key, required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  State<RequestConfig> createState() => _RequestConfigState();
}

class _RequestConfigState extends State<RequestConfig> {
  String tab = 'Params';
  String bodyView = 'Fields';
  String? bodyText;
  bool bodyPick = false;

  @override
  void didUpdateWidget(RequestConfig old) {
    super.didUpdateWidget(old);
    if (old.st.id != widget.st.id) {
      tab = 'Params';
      bodyView = 'Fields';
      bodyText = null;
      bodyPick = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c, st = widget.st;
    final ws = c.ws;
    final node = c.col.requestByRef(st.request);
    final req = node?.request;
    final run = ws.runs[st.id];
    final (_, vars) = c.sources(st.id);
    final slots = req == null ? const <Slot>[] : Slots.of(req);
    final known = c.state.knownVars(c.tab);
    final needs = req == null
        ? const <StepNeed>[]
        : StepNeeds.of(req, st.inputs, {...known, ...vars});
    String? ov(InputTarget t) {
      for (final i in st.inputs) {
        if (i.target == t && i.value.trim().isNotEmpty) return i.value;
      }
      return null;
    }

    int count(List<InputTarget> t) => st.inputs
        .where((it) => t.contains(it.target) && it.value.trim().isNotEmpty)
        .length;
    final changes = st.inputs.where((it) => it.value.trim().isNotEmpty).length;
    final method =
        ov(InputTarget.Method)?.trim().toUpperCase() ?? req?.method ?? '';
    if (node == null || req == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          T(
            'Missing request: ${st.request}',
            color: pal.err,
            weight: FontWeight.w600,
          ),
          T(
            'It was renamed, moved or deleted. Remove this step and add the request again.',
            color: pal.muted,
            size: 12,
          ),
        ],
      );
    }
    void upd(WorkflowStep Function(WorkflowStep) f) => c.update(st.id, f);

    final tabs = ['Params', 'Headers', 'Body', 'Auth'];
    final List<Widget> panel;
    switch (tab) {
      case 'Params':
        final path = slots
            .where((it) => it.target == InputTarget.PathParam)
            .toList();
        final query = slots
            .where((it) => it.target == InputTarget.Query)
            .toList();
        panel = [
          if (path.isNotEmpty) ...[
            const SectionLabel('PATH PARAMETERS'),
            for (final it in path)
              FieldRow(
                c: c,
                st: st,
                target: it.target,
                name: it.name,
                current: it.current,
                label: ':${it.name}',
              ),
          ],
          const SectionLabel('QUERY PARAMETERS'),
          if (query.isEmpty &&
              !st.inputs.any((it) => it.target == InputTarget.Query))
            T('None yet.', color: pal.muted, size: 12),
          for (final it in query)
            FieldRow(
              c: c,
              st: st,
              target: it.target,
              name: it.name,
              current: it.current,
              label: it.name,
            ),
          ...addedRows(
            c: c,
            st: st,
            target: InputTarget.Query,
            slots: slots,
            nameHint: 'parameter name',
          ),
          AddRowButton(
            c: c,
            st: st,
            target: InputTarget.Query,
            label: 'Add query parameter',
          ),
          FieldRow(
            c: c,
            st: st,
            target: InputTarget.PathAppend,
            name: '',
            current: '',
            label: 'add to end of path',
          ),
        ];
      case 'Headers':
        final headers = slots
            .where((it) => it.target == InputTarget.Header)
            .toList();
        panel = [
          if (headers.isEmpty &&
              !st.inputs.any((it) => it.target == InputTarget.Header))
            T(
              'This request sends no custom headers.',
              color: pal.muted,
              size: 12,
            ),
          for (final it in headers)
            FieldRow(
              c: c,
              st: st,
              target: it.target,
              name: it.name,
              current: it.current,
              label: it.name,
            ),
          ...addedRows(
            c: c,
            st: st,
            target: InputTarget.Header,
            slots: slots,
            nameHint: 'header name',
          ),
          AddRowButton(
            c: c,
            st: st,
            target: InputTarget.Header,
            label: 'Add header',
          ),
        ];
      case 'Body':
        final rawOv = ov(InputTarget.BodyRaw);
        final currentBody = switch (req.bodyMode) {
          BodyMode.Text => req.bodyText,
          BodyMode.Xml => req.bodyXml,
          BodyMode.Graphql => req.bodyGraphql,
          _ => req.bodyJson,
        };
        final mode = rawOv != null ? 'Whole body' : bodyView;
        final text = bodyText ?? rawOv ?? currentBody;
        panel = [
          Row(
            spacing: 8,
            children: [
              T('Body type: ${req.bodyMode.name}', color: pal.muted, size: 12),
              const Spacer(),
              Btn(
                label: 'Fields',
                onClick: () {
                  setState(() => bodyView = 'Fields');
                  if (rawOv != null) {
                    upd((s) => setOverride(s, InputTarget.BodyRaw, '', ''));
                  }
                },
                primary: mode == 'Fields',
              ),
              Btn(
                label: 'Whole body',
                onClick: () => setState(() => bodyView = 'Whole body'),
                primary: mode == 'Whole body',
              ),
            ],
          ),
          if (mode == 'Fields') ...[
            if (!slots.any((it) => it.target == InputTarget.Body) &&
                !st.inputs.any((it) => it.target == InputTarget.Body))
              T(
                req.bodyMode == BodyMode.Json
                    ? 'No fields found in this JSON body. Add one, or switch to “Whole body”.'
                    : 'Field editing works with JSON bodies. Use “Whole body” for this request.',
                color: pal.muted,
                size: 12,
              ),
            for (final it in slots.where((it) => it.target == InputTarget.Body))
              FieldRow(
                c: c,
                st: st,
                target: it.target,
                name: it.name,
                current: it.current,
                label: it.name,
              ),
            ...addedRows(
              c: c,
              st: st,
              target: InputTarget.Body,
              slots: slots,
              nameHint: 'field, e.g. user.id',
            ),
            AddRowButton(
              c: c,
              st: st,
              target: InputTarget.Body,
              label: 'Add body field',
            ),
          ] else ...[
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: SectionLabel('WHOLE BODY SENT BY THIS STEP'),
                ),
                if (c.available(st.id).isNotEmpty ||
                    c.steps.requestsBefore(st.id).isNotEmpty)
                  Btn(
                    label: 'Use value',
                    onClick: () => setState(() => bodyPick = !bodyPick),
                    primary: bodyPick,
                    icon: Ic.variables,
                  ),
                if (rawOv != null)
                  IconBtn(
                    icon: Ic.refresh,
                    onClick: () {
                      setState(() => bodyText = currentBody);
                      upd((s) => setOverride(s, InputTarget.BodyRaw, '', ''));
                    },
                    color: pal.accent,
                    size: 15,
                  ),
              ],
            ),
            if (bodyPick)
              ValuePicker(
                c: c,
                forId: st.id,
                onInsert: (tok) {
                  setState(() {
                    bodyText = tok;
                    bodyPick = false;
                  });
                  upd((s) => setOverride(s, InputTarget.BodyRaw, '', tok));
                },
                targetLabel: 'Body · whole body',
                onClose: () => setState(() => bodyPick = false),
              ),
            WithVars(
              c: c,
              forId: st.id,
              child: SizedBox(
                height: 170,
                child: CodeEditor(
                  key: ValueKey('body-${st.id}'),
                  value: text,
                  onChange: (v) {
                    setState(() => bodyText = v);
                    upd(
                      (s) => setOverride(
                        s,
                        InputTarget.BodyRaw,
                        '',
                        v == currentBody ? '' : (v.trim().isEmpty ? ' ' : v),
                      ),
                    );
                  },
                  lang: req.bodyMode == BodyMode.Xml
                      ? 'xml'
                      : (req.bodyMode == BodyMode.Text ? 'text' : 'json'),
                ),
              ),
            ),
            if (c.preview(rawOv ?? text, st.id) case final pv?)
              T(
                '= ${pv.length > 160 ? pv.substring(0, 160) : pv}',
                color: pal.ok,
                size: 11,
                mono: true,
                maxLines: 2,
              ),
            T(
              'Tip: use {name} for values passed on by earlier steps (or “Use value”). {{name}} is for environment variables.',
              color: pal.muted,
              size: 11,
            ),
          ],
        ];
      default:
        panel = [
          FieldRow(
            c: c,
            st: st,
            target: InputTarget.Bearer,
            name: '',
            current: req.auth.mode == AuthMode.Bearer ? req.auth.token : '',
            label: 'bearer token',
          ),
          T(
            "This request's auth: ${req.auth.mode.label}.${req.auth.mode != AuthMode.Bearer ? " Entering a token here sends it as a Bearer token for this step." : ""}",
            color: pal.muted,
            size: 11,
          ),
        ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Row(
          spacing: 10,
          children: [
            Btn(
              label: 'Open request',
              onClick: () => c.state.openRequest(c.col.path, node),
              icon: Ic.open,
            ),
            if (!ws.running && st.enabled)
              Btn(
                label: 'Run to here',
                onClick: () => c.state.runWorkflow(c.tab, st.id),
                icon: Ic.play,
                primary: true,
              ),
          ],
        ),
        if (run != null)
          for (final n in run.notes) T('⚠ $n', color: pal.err, size: 12),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Dropdown(
                selected: method,
                options: HTTP_METHODS,
                onSelect: (m) => upd(
                  (s) => setOverride(
                    s,
                    InputTarget.Method,
                    '',
                    m == req.method ? '' : m,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueCell(
                c: c,
                forId: st.id,
                value: ov(InputTarget.Url) ?? '',
                current: req.url,
                onSet: (v) =>
                    upd((s) => setOverride(s, InputTarget.Url, '', v)),
                targetLabel: 'Request · URL',
                resolved: () {
                  final r = ws.runs[st.id];
                  if (r == null) return null;
                  for (final i in r.inputs) {
                    if (i.$1 == InputTarget.Url.label) return i.$2;
                  }
                  return null;
                }(),
              ),
            ),
          ],
        ),
        if (method != req.method || ov(InputTarget.Url) != null)
          T(
            'Edited for this workflow — the saved request still says ${req.method} ${req.url}',
            color: pal.muted,
            size: 11,
          ),

        if (needs.isNotEmpty) ...[
          const SectionLabel('NEEDS A VALUE'),
          for (final n in needs)
            FieldRow(
              c: c,
              st: st,
              target: n.target,
              name: n.name,
              current: '',
              label: Slots.label(n.target, n.name),
              needsValue: true,
            ),
        ],

        Tabs(
          items: tabs,
          selected: tab,
          onSelect: (v) => setState(() => tab = v),
          badge: (t) {
            final n = switch (t) {
              'Params' => count([
                InputTarget.PathParam,
                InputTarget.Query,
                InputTarget.PathAppend,
              ]),
              'Headers' => count([InputTarget.Header]),
              'Body' => count([InputTarget.Body, InputTarget.BodyRaw]),
              _ => count([InputTarget.Bearer]),
            };
            return n > 0 ? '$n' : null;
          },
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: panel,
        ),
        if (changes > 0)
          Row(
            children: [
              Clickable(
                onClick: () => upd(
                  (s) => s.copyWith(
                    inputs: s.inputs
                        .where((x) => x.target == InputTarget.Variable)
                        .toList(),
                  ),
                ),
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: T(
                    'Reset all edits in this step',
                    color: pal.accent,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(height: 1, color: pal.border),
        ),
        _OutputsSection(key: ValueKey('out-${st.id}'), c: c, st: st, run: run),
      ],
    );
  }
}

/// "Pass on to later steps": the named values this step hands over, configured here where the data is produced.
class _OutputsSection extends StatefulWidget {
  const _OutputsSection({
    super.key,
    required this.c,
    required this.st,
    required this.run,
  });
  final Wf c;
  final WorkflowStep st;
  final StepRun? run;

  @override
  State<_OutputsSection> createState() => _OutputsSectionState();
}

class _OutputsSectionState extends State<_OutputsSection> {
  int? pick;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c, st = widget.st, run = widget.run;
    void setOut(int k, StepOutput Function(StepOutput) f) => c.update(
      st.id,
      (s) => s.copyWith(
        outputs: [
          for (var i = 0; i < s.outputs.length; i++)
            i == k ? f(s.outputs[i]) : s.outputs[i],
        ],
      ),
    );
    final fields = ResponseFields.of(run?.result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        const SectionLabel('PASS ON TO LATER STEPS'),
        if (st.outputs.isEmpty)
          T(
            'Choose the values later steps will need — an id, a token, the whole body. Each one stays available to every step after this one: type {name} in any field, or click “Use value”. ({{name}} stays for environment variables.)',
            color: pal.muted,
            size: 12,
          ),
        for (var k = 0; k < st.outputs.length; k++)
          ..._outputRow(context, c, st, run, k, fields, setOut),
        Row(
          spacing: 10,
          children: [
            Btn(
              label: 'Add output',
              onClick: () {
                c.update(
                  st.id,
                  (it) =>
                      it.copyWith(outputs: [...it.outputs, const StepOutput()]),
                );
                setState(
                  () => pick = fields.isNotEmpty ? st.outputs.length : null,
                );
              },
              icon: Ic.add,
            ),
            if (fields.isEmpty && run == null)
              Flexible(
                child: T(
                  'Run this step (▶ Run to here) to pick from its real response.',
                  color: pal.muted,
                  size: 11,
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _outputRow(
    BuildContext context,
    Wf c,
    WorkflowStep st,
    StepRun? run,
    int k,
    List<ResponseField> fields,
    void Function(int, StepOutput Function(StepOutput)) setOut,
  ) {
    final pal = context.pal;
    final o = st.outputs[k];
    final value = run?.result == null ? null : o.valueIn(run!.result);
    return [
      Row(
        spacing: 8,
        children: [
          Expanded(
            child: Field(
              value: o.name,
              onChange: (n) => setOut(
                k,
                (it) => it.copyWith(
                  name: n.replaceAll(
                    RegExp(r'[^\p{L}\p{N}_]', unicode: true),
                    '',
                  ),
                ),
              ),
              placeholder: 'name',
              mono: true,
              highlightVars: false,
            ),
          ),
          T('←', color: pal.muted),
          SizedBox(
            width: 170,
            child: Dropdown(
              selected: o.kind.label,
              options: SourceKind.values.map((e) => e.label).toList(),
              onSelect: (l) => setOut(
                k,
                (it) => it.copyWith(
                  kind: SourceKind.values.firstWhere((e) => e.label == l),
                ),
              ),
            ),
          ),
          if (fields.isNotEmpty)
            Btn(
              label: 'Pick',
              onClick: () => setState(() => pick = pick == k ? null : k),
              primary: pick == k,
            ),
          IconBtn(
            icon: Ic.close,
            onClick: () {
              c.update(
                st.id,
                (s) => s.copyWith(
                  outputs: [
                    for (var i = 0; i < s.outputs.length; i++)
                      if (i != k) s.outputs[i],
                  ],
                ),
              );
              setState(() => pick = null);
            },
            size: 14,
          ),
        ],
      ),
      if (o.kind.needsPath)
        Field(
          value: o.path,
          onChange: (v) => setOut(k, (it) => it.copyWith(path: v)),
          placeholder: o.kind.pathHint,
          mono: true,
          highlightVars: false,
        ),
      if (o.name.trim().isNotEmpty &&
          c.steps
              .requestsBefore(st.id)
              .any(
                (e) => e.outputs.any((it) => it.name.trim() == o.name.trim()),
              ))
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: T(
            'An earlier step also passes on “${o.name}” — from here on this value replaces it.',
            color: pal.muted,
            size: 11,
          ),
        ),
      if (value != null && o.name.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: T(
            '= ${value.$2 != null ? "(${value.$2})" : (() {
                    final v = value.$1.replaceAll('\n', ' ');
                    final cut = v.length > 100 ? v.substring(0, 100) : v;
                    return cut.isEmpty ? '(empty)' : cut;
                  })()}',
            color: value.$2 != null ? pal.err : pal.ok,
            size: 11,
            mono: true,
          ),
        ),
      if (pick == k)
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: pal.bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in fields)
                  Clickable(
                    onClick: () {
                      setOut(
                        k,
                        (cur) => cur.copyWith(
                          name: cur.name.trim().isEmpty
                              ? suggestName(f)
                              : cur.name,
                          kind: f.kind,
                          path: f.path,
                        ),
                      );
                      setState(() => pick = null);
                    },
                    cursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
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
                  ),
              ],
            ),
          ),
        ),
    ];
  }
}
