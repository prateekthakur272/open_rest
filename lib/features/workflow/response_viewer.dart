import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/test_results.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/run/workflow_builder.dart';
import 'package:open_rest/features/workflow/value_inputs.dart';
import 'package:open_rest/features/workflow/workflow_view.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/format.dart';
import 'package:open_rest/utils/json.dart';

/// The complete last response of one step, in its own dialog (the side pane is for configuration only).
class ResponseDialog extends StatelessWidget {
  const ResponseDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalViewResponse m;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    RequestTab? tab;
    for (final t in state.tabs) {
      if (t.id == m.tabId) tab = t;
    }
    final col = tab == null ? null : state.collection(tab.collectionPath);
    final c = tab != null && col != null && tab.workflow != null
        ? Wf(state, tab, col)
        : null;
    final st = c?.steps.findStep(m.stepId);
    if (c == null || st == null) {
      return ModalBox(
        title: 'Response',
        onClose: () => state.modal = null,
        width: 460,
        actions: [
          Btn(label: 'Close', onClick: () => state.modal = null, primary: true),
        ],
        content: [
          T(
            'This step is no longer in the workflow, so there is no response to show.',
            color: context.pal.muted,
          ),
        ],
      );
    }
    return ModalBox(
      title: 'Response — ${c.name(st)}',
      onClose: () => state.modal = null,
      width: 940,
      height: 720,
      actions: [
        Btn(label: 'Close', onClick: () => state.modal = null, primary: true),
      ],
      content: [
        Expanded(
          child: SingleChildScrollView(
            child: _ResponsePanel(key: ValueKey('rp-${st.id}'), c: c, st: st),
          ),
        ),
      ],
    );
  }
}

/// The complete response of a step: summary, body, fields to pass on, headers, the request as sent, and tests.
class _ResponsePanel extends StatefulWidget {
  const _ResponsePanel({super.key, required this.c, required this.st});
  final Wf c;
  final WorkflowStep st;

  @override
  State<_ResponsePanel> createState() => _ResponsePanelState();
}

class _ResponsePanelState extends State<_ResponsePanel> {
  String sub = 'Body';
  int round = -1; // -1 follows the latest execution
  bool pretty = true;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c, st = widget.st;
    final ws = c.ws;
    final all = ws.history[st.id] ?? const <StepRun>[];
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          spacing: 8,
          children: [
            T(
              ws.running ? 'Running…' : 'No response yet',
              weight: FontWeight.w600,
            ),
            T(
              'Run the workflow (or just up to this step) to see the complete response here.',
              color: pal.muted,
              size: 12,
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
      );
    }
    final idx = round >= 0 && round < all.length ? round : all.length - 1;
    final run = all[idx];
    final r = run.result;
    final resp = r?.response != null && r!.response!.error == null
        ? r.response
        : null;
    final text = resp?.text ?? '';
    final ct = (resp?.contentType ?? '').toLowerCase();
    final isJson =
        ct.contains('json') || (text.trim().isNotEmpty && Json.isValid(text));
    final lang = isJson
        ? 'json'
        : (ct.contains('xml') || ct.contains('html') ? 'xml' : 'text');

    Widget bodyTab;
    switch (sub) {
      case 'Body':
        if (resp == null) {
          bodyTab = T('There is no response body.', color: pal.muted, size: 12);
        } else if (text.isEmpty) {
          bodyTab = T(
            'The response body is empty.',
            color: pal.muted,
            size: 12,
          );
        } else {
          final shown = isJson && pretty
              ? (Json.prettyText(text) ?? text)
              : text;
          final cut = shown.length > 1500000;
          bodyTab = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              if (isJson)
                Row(
                  spacing: 8,
                  children: [
                    Btn(
                      label: 'Pretty',
                      onClick: () => setState(() => pretty = true),
                      primary: pretty,
                    ),
                    Btn(
                      label: 'Raw',
                      onClick: () => setState(() => pretty = false),
                      primary: !pretty,
                    ),
                    T('${text.length} characters', color: pal.muted, size: 11),
                  ],
                ),
              SizedBox(
                height: 420,
                child: CodeEditor(
                  key: ValueKey('body-$sub-$pretty-$idx'),
                  value: cut ? shown.substring(0, 1500000) : shown,
                  onChange: (_) {},
                  lang: lang,
                  readOnly: true,
                ),
              ),
              if (cut)
                T(
                  'Showing the first 1,500,000 of ${shown.length} characters — use Copy body for everything.',
                  color: pal.muted,
                  size: 11,
                ),
            ],
          );
        }
      case 'Fields':
        bodyTab = resp == null
            ? T(
                'There is no response to take values from.',
                color: pal.muted,
                size: 12,
              )
            : _FieldsView(c: c, st: st, r: r);
      case 'Headers':
        bodyTab = resp == null || resp.headers.isEmpty
            ? T('No response headers.', color: pal.muted, size: 12)
            : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: pal.bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    for (final h in resp.headers)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          SizedBox(
                            width: 180,
                            child: T(
                              h.$1,
                              mono: true,
                              size: 12,
                              color: pal.syntaxKey,
                            ),
                          ),
                          Expanded(child: T(h.$2, mono: true, size: 12)),
                        ],
                      ),
                  ],
                ),
              );
      case 'Sent':
        bodyTab = _SentView(sent: r?.request);
      default:
        bodyTab = r == null || r.tests.isEmpty
            ? T(
                'This request has no tests or assertions.',
                color: pal.muted,
                size: 12,
              )
            : TestsList(tests: r.tests);
    }

    final labels = [
      for (var i = 0; i < all.length; i++)
        all.map((x) => x.iteration).toSet().length < all.length
            ? 'Run ${i + 1} of ${all.length}'
            : 'Round ${all[i].iteration > 0 ? all[i].iteration : i + 1} of ${all.length}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 10,
          children: [
            if (resp != null) ...[
              Chip(
                '${resp.status}${resp.statusText.trim().isNotEmpty ? " ${resp.statusText}" : ""}',
                color: statusColor(resp.status, pal),
              ),
              T('${resp.timeMs} ms', color: pal.muted, size: 12),
              T(formatSize(resp.size), color: pal.muted, size: 12),
            ] else
              Flexible(
                child: T(
                  r?.error ??
                      r?.response?.error ??
                      (run.node == null
                          ? 'The request no longer exists'
                          : 'No response'),
                  color: pal.err,
                  size: 13,
                  weight: FontWeight.w600,
                ),
              ),
            if (all.length > 1)
              Dropdown(
                selected: labels[idx],
                options: labels,
                onSelect: (l) => setState(() => round = labels.indexOf(l)),
              ),
            const Spacer(),
            if (resp != null)
              Btn(
                label: 'Copy body',
                onClick: () {
                  Platform.copy(
                    isJson && pretty ? (Json.prettyText(text) ?? text) : text,
                  );
                  c.state.showToast('Response body copied');
                },
                icon: Ic.copy,
              ),
          ],
        ),
        if (resp != null && resp.finalUrl.trim().isNotEmpty)
          T(
            resp.finalUrl,
            color: pal.muted,
            size: 11,
            mono: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (r?.error != null && resp == null)
          T(r!.error!, color: pal.err, mono: true, size: 12),
        for (final n in run.notes) T('⚠ $n', color: pal.err, size: 12),
        Tabs(
          items: const ['Body', 'Fields', 'Headers', 'Sent', 'Tests'],
          selected: sub,
          onSelect: (v) => setState(() => sub = v),
          badge: (t) {
            if (t == 'Headers') {
              final n = resp?.headers.length ?? 0;
              return n > 0 ? '$n' : null;
            }
            if (t == 'Tests') {
              final n = r?.tests.length ?? 0;
              if (n == 0) return null;
              return r!.tests.every((x) => x.passed)
                  ? '$n'
                  : '${r.tests.where((x) => !x.passed).length} failed';
            }
            return null;
          },
        ),
        bodyTab,
        if (r != null && r.logs.isNotEmpty && sub == 'Body') ...[
          const SectionLabel('SCRIPT LOGS'),
          T(r.logs.join('\n'), mono: true, size: 12, color: pal.muted),
        ],
      ],
    );
  }
}

/// The request as it went out: method, URL, headers and body after overrides and substitution.
class _SentView extends StatelessWidget {
  const _SentView({required this.sent});
  final PreparedRequest? sent;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = sent;
    if (s == null) {
      return T(
        'Nothing was sent (the step failed before the request was built).',
        color: pal.muted,
        size: 12,
      );
    }
    Widget kv(String k, String v) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: T(k, mono: true, size: 12, color: pal.syntaxKey),
        ),
        Expanded(child: T(v, mono: true, size: 12)),
      ],
    );
    final Widget body = switch (s.body) {
      BodyNone() => T('no body', color: pal.muted, size: 12),
      BodyRaw b => () {
        final json = b.contentType.contains('json');
        final txt = json ? (Json.prettyText(b.text) ?? b.text) : b.text;
        return SizedBox(
          height: 220,
          child: CodeEditor(
            value: txt,
            onChange: (_) {},
            lang: json
                ? 'json'
                : (b.contentType.contains('xml') ? 'xml' : 'text'),
            readOnly: true,
          ),
        );
      }(),
      BodyForm b => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [for (final f in b.fields) kv(f.$1, f.$2)],
      ),
      BodyMultipart b => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final part in b.parts)
            kv(part.name, part.isFile ? 'file: ${part.value}' : part.value),
        ],
      ),
      BodyFileBody b => T('file: ${b.path}', mono: true, size: 12),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            MethodPill(s.method),
            Expanded(child: T(s.url, mono: true, size: 12)),
          ],
        ),
        const SectionLabel('HEADERS'),
        if (s.headers.isEmpty) T('none', color: pal.muted, size: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: pal.bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [for (final h in s.headers) kv(h.$1, h.$2)],
          ),
        ),
        const SectionLabel('BODY'),
        body,
      ],
    );
  }
}

/// Every field of the response, with one-click "Pass on".
class _FieldsView extends StatelessWidget {
  const _FieldsView({required this.c, required this.st, required this.r});
  final Wf c;
  final WorkflowStep st;
  final ExecResult? r;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fields = ResponseFields.of(r);
    // Reads the step as it is now so a new output shows a tick immediately.
    final cur = c.steps.findStep(st.id) ?? st;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        T(
          'Click “Pass on” to hand a value to the steps after this one.',
          color: pal.muted,
          size: 11,
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 420),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: pal.bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in fields)
                  () {
                    StepOutput? existing;
                    for (final o in cur.outputs) {
                      if (o.kind == f.kind &&
                          o.path == f.path &&
                          o.name.trim().isNotEmpty) {
                        existing = o;
                        break;
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
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
                          if (existing != null)
                            SizedBox(
                              width: 150,
                              child: T(
                                '✓ ${existing.name}',
                                color: pal.ok,
                                size: 12,
                              ),
                            )
                          else
                            SizedBox(
                              width: 150,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Btn(
                                  label: 'Pass on',
                                  onClick: () => c.update(
                                    st.id,
                                    (s) => s.copyWith(
                                      outputs: [
                                        ...s.outputs,
                                        StepOutput(
                                          name: uniqueName(
                                            s.outputs,
                                            suggestName(f),
                                          ),
                                          kind: f.kind,
                                          path: f.path,
                                        ),
                                      ],
                                    ),
                                  ),
                                  icon: Ic.add,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
