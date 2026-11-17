import 'package:flutter/widgets.dart';
import 'package:open_rest/components/drag_devices.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/test_results.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/features/workflow/workflow_view.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

String elapsed(int ms) =>
    ms < 1000 ? '+$ms ms' : '+${(ms / 1000.0).toStringAsFixed(1)} s';

String _removePrefix(String s, String p) =>
    s.startsWith(p) ? s.substring(p.length) : s;

Widget _link(
  String text,
  VoidCallback onTap, {
  double size = 11,
  EdgeInsets padding = EdgeInsets.zero,
  Color? color,
  required Pal pal,
}) => Clickable(
  onClick: onTap,
  cursor: SystemMouseCursors.click,
  child: Padding(
    padding: padding,
    child: T(text, color: color ?? pal.accent, size: size),
  ),
);

/// The run log, docked along the bottom of the editor like a console: a header bar that is always there (click to fold or unfold),
/// and below it every step of the last run. Drag the top edge to resize it.
class DockedLog extends StatefulWidget {
  const DockedLog({super.key, required this.c});
  final Wf c;

  @override
  State<DockedLog> createState() => _DockedLogState();
}

class _DockedLogState extends State<DockedLog> {
  final ScrollController scroll = ScrollController();
  int _lastCount = -1;
  bool _lastRunning = false;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = widget.c;
    final ws = c.ws;
    final all = ws.events.toList();
    final problems = all.where((e) => !e.ok).length;
    final requests = all
        .where((e) => e.kind == StepKind.Request && !e.sub)
        .length;
    final reqMs = all.fold<int>(0, (a, e) => a + (e.ms ?? 0));

    /// An entry is a group when the entries after it are nested deeper (an If branch, a loop's rounds).
    bool isGroup(int i) {
      int? next;
      for (var k = i + 1; k < all.length; k++) {
        if (!all[k].sub) {
          next = k;
          break;
        }
      }
      if (next == null) return false;
      return all[next].depth > all[i].depth;
    }

    // Groups start collapsed; "passed on" lives inside its request.
    final shown = <(int, RunEvent)>[];
    if (ws.logProblemsOnly) {
      for (var i = 0; i < all.length; i++) {
        if (!all[i].ok && !all[i].sub) shown.add((i, all[i]));
      }
    } else {
      int? hideBelow;
      for (var i = 0; i < all.length; i++) {
        final e = all[i];
        if (e.sub) continue;
        final h = hideBelow;
        if (h != null) {
          if (e.depth > h) {
            continue;
          } else {
            hideBelow = null;
          }
        }
        shown.add((i, e));
        if (isGroup(i) && ws.logOpen[i] != true) hideBelow = e.depth;
      }
    }

    if (ws.running && (all.length != _lastCount || !_lastRunning)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    }
    _lastCount = all.length;
    _lastRunning = ws.running;

    return Container(
      color: pal.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              supportedDevices: kDragDevices,
              onVerticalDragUpdate: (d) {
                ws.logHeight = (ws.logHeight - d.delta.dy)
                    .clamp(120.0, 640.0)
                    .toDouble();
                ws.logExpanded = true;
              },
              child: Container(height: 4, color: pal.border),
            ),
          ),
          Clickable(
            onClick: () => ws.logExpanded = !ws.logExpanded,
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              height: 26,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  spacing: 8,
                  children: [
                    Chevron(open: ws.logExpanded),
                    const SectionLabel('RUN LOG'),
                    if (ws.running) ...[
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          color: pal.accent,
                          strokeWidth: 1.5,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      T('running…', color: pal.accent, size: 12),
                    ] else if (all.isEmpty)
                      T(
                        'run the workflow to see every step here',
                        color: pal.muted,
                        size: 12,
                      )
                    else if (problems == 0)
                      T(
                        'all ok',
                        color: pal.ok,
                        size: 11,
                        weight: FontWeight.w600,
                      )
                    else
                      T(
                        '$problems problem${problems == 1 ? "" : "s"}',
                        color: pal.err,
                        size: 11,
                        weight: FontWeight.w600,
                      ),
                    if (all.isNotEmpty)
                      T(
                        '$requests request${requests == 1 ? "" : "s"}${reqMs > 0 ? " · $reqMs ms" : ""}',
                        color: pal.muted,
                        size: 12,
                      ),
                    const Spacer(),
                    if (all.isNotEmpty && ws.logExpanded) ...[
                      if (problems > 0)
                        Clickable(
                          onClick: () =>
                              ws.logProblemsOnly = !ws.logProblemsOnly,
                          cursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ws.logProblemsOnly
                                  ? pal.accent
                                  : const Color(0x00000000),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: T(
                              'Only problems',
                              color: ws.logProblemsOnly
                                  ? const Color(0xFF000000)
                                  : pal.accent,
                              size: 11,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      IconBtn(
                        icon: Ic.copy,
                        onClick: () {
                          Platform.copy(
                            all
                                .map((e) {
                                  final pad = '  ' * e.depth;
                                  if (e.sub && e.fields.isNotEmpty) {
                                    return e.fields
                                        .map(
                                          (f) =>
                                              '$pad  → ${f.$1} = ${f.$2.replaceAll('\n', ' ')}',
                                        )
                                        .join('\n');
                                  }
                                  return pad +
                                      (e.sub ? '  → ' : (e.ok ? '✓ ' : '✗ ')) +
                                      e.text +
                                      (e.sub ? '' : '   (${elapsed(e.at)})');
                                })
                                .join('\n'),
                          );
                          c.state.showToast('Run log copied');
                        },
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (ws.logExpanded) ...[
            Container(height: 1, color: pal.border),
            Container(
              height: ws.logHeight,
              color: pal.field,
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (all.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: T(
                          ws.running ? 'Waiting for the first step…' : 'Nothing has run yet. Press Run — or the ▶ on a step to run up to it.',
                          color: pal.muted,
                          size: 12,
                        ),
                      )
                    else if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: T('No problems.', color: pal.muted, size: 12),
                      ),
                    for (final (i, e) in shown)
                      _LogRow(
                        key: ValueKey('log-$i'),
                        c: c,
                        e: e,
                        index: i,
                        group: isGroup(i),
                        passedOn:
                            i + 1 < all.length &&
                                all[i + 1].sub &&
                                all[i + 1].stepId == e.stepId
                            ? all[i + 1]
                            : null,
                        passOnIndex: i + 1,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    super.key,
    required this.c,
    required this.e,
    required this.index,
    required this.group,
    required this.passedOn,
    required this.passOnIndex,
  });
  final Wf c;
  final RunEvent e;
  final int index;
  final bool group;
  final RunEvent? passedOn;
  final int passOnIndex;

  @override
  Widget build(BuildContext context) {
    final run = c.runFor(index);
    final expandable = group || run != null;
    final open = expandable && c.ws.logOpen[index] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LogLine(
          c: c,
          e: e,
          index: index,
          expandable: expandable,
          open: open,
          passedOn: passedOn,
          onToggle: () => c.ws.logOpen[index] = !open,
        ),
        if (open && run != null)
          Padding(
            padding: EdgeInsets.only(
              left: (e.depth * 14 + 28).toDouble(),
              bottom: 6,
              top: 2,
            ),
            child: _LogDetails(
              c: c,
              e: e,
              run: run,
              passedOn: passedOn,
              passOnIndex: passOnIndex,
            ),
          ),
      ],
    );
  }
}

/// What went out for one request entry (and what it passed on), expanded inside the log. Responses are not shown here: "View response" opens them.
class _LogDetails extends StatelessWidget {
  const _LogDetails({
    required this.c,
    required this.e,
    required this.run,
    required this.passedOn,
    required this.passOnIndex,
  });
  final Wf c;
  final RunEvent e;
  final StepRun run;
  final RunEvent? passedOn;
  final int passOnIndex;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = run.result;
    final used = c.usedBy(run.step);
    final po = passedOn != null && passedOn!.fields.isNotEmpty
        ? passedOn
        : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: pal.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          if (r?.request != null) ...[
            const SectionLabel('SENT'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                MethodPill(r!.request!.method),
                Expanded(child: T(r.request!.url, mono: true, size: 11)),
              ],
            ),
          ],
          if (run.inputs.isNotEmpty) ...[
            const SectionLabel('VALUES FILLED IN'),
            for (final (k, v) in run.inputs)
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    flex: 35,
                    child: T(k, mono: true, size: 11, color: pal.syntaxKey),
                  ),
                  Expanded(
                    flex: 65,
                    child: T(
                      v.replaceAll('\n', ' ').isEmpty
                          ? '(empty)'
                          : v.replaceAll('\n', ' '),
                      mono: true,
                      size: 11,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
          for (final n in run.notes) T('⚠ $n', color: pal.err, size: 11),
          if (r?.error != null)
            T(r!.error!, color: pal.err, mono: true, size: 11),
          if (r != null && r.tests.isNotEmpty) TestsList(tests: r.tests),
          if (used.isNotEmpty) ...[
            const SectionLabel('USED FROM EARLIER STEPS'),
            for (final a in used)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Expanded(
                    flex: 25,
                    child: T(
                      '{${a.name}}',
                      mono: true,
                      size: 11,
                      weight: FontWeight.w600,
                      color: pal.accent,
                      maxLines: 1,
                    ),
                  ),
                  Expanded(
                    flex: 50,
                    child: T(
                      (a.value ?? '').replaceAll('\n', ' ').isEmpty
                          ? '(empty)'
                          : (a.value ?? '').replaceAll('\n', ' '),
                      mono: true,
                      size: 11,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 25,
                    child: T(
                      a.from,
                      size: 11,
                      color: pal.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
          if (po != null)
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: pal.field,
                borderRadius: BorderRadius.circular(6),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: pal.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: pal.hover.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          flex: 30,
                          child: T(
                            'PASSED ON',
                            color: pal.muted,
                            size: 10,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          flex: 70,
                          child: T(
                            'VALUE',
                            color: pal.muted,
                            size: 10,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 36),
                      ],
                    ),
                  ),
                  for (final (k, v) in po.fields) ...[
                    Container(height: 1, color: pal.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          Expanded(
                            flex: 30,
                            child: T(
                              k,
                              mono: true,
                              size: 12,
                              weight: FontWeight.w600,
                              color: pal.accent,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 70,
                            child: T(
                              v.replaceAll('\n', ' ').isEmpty
                                  ? '(empty)'
                                  : v.replaceAll('\n', ' '),
                              mono: true,
                              size: 12,
                              color: v.isEmpty ? pal.muted : pal.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: _link(
                              'copy',
                              () {
                                Platform.copy(v);
                                c.state.showToast('Copied the value of $k');
                              },
                              size: 10,
                              pal: pal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              _link(
                'View full response',
                () => c.state.modal = ModalViewResponse(
                  tabId: c.tab.id,
                  stepId: e.stepId,
                ),
                pal: pal,
              ),
              _link(
                'Configure this step',
                () => c.ws.selected = e.stepId,
                pal: pal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({
    required this.c,
    required this.e,
    required this.index,
    required this.expandable,
    required this.open,
    required this.passedOn,
    required this.onToggle,
  });
  final Wf c;
  final RunEvent e;
  final int index;
  final bool expandable;
  final bool open;
  final RunEvent? passedOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final st = c.steps.findStep(e.stepId);
    final isReq = e.kind == StepKind.Request && !e.sub;
    String? method;
    if (st != null) {
      for (final i in st.inputs) {
        if (i.target == InputTarget.Method && i.value.trim().isNotEmpty) {
          method = i.value.trim().toUpperCase();
          break;
        }
      }
      method ??= c.col.requestByRef(st.request)?.request.method;
    }
    final tagColor = switch (e.kind) {
      StepKind.If => pal.syntaxKey,
      StepKind.Loop => pal.accent,
      StepKind.Set => pal.ok,
      StepKind.Wait => pal.muted,
      StepKind.Stop => pal.err,
      _ => pal.muted,
    };
    final tag = switch (e.kind) {
      StepKind.If => 'IF',
      StepKind.Loop => 'LOOP',
      StepKind.Set => 'SET',
      StepKind.Wait => 'WAIT',
      StepKind.Stop => 'STOP',
      _ => 'REQ',
    };
    final label = e.label;

    Widget textBlock;
    if (isReq && label != null) {
      var failLine = '';
      var showFail = false;
      if (e.status == null || !e.ok) {
        final m = _removePrefix(_removePrefix(e.text, label), ' · ');
        if (m.trim().isNotEmpty && !(e.status != null && e.ok)) {
          var s = m;
          if (e.status != null) {
            final key = '${e.ms} ms';
            final k = m.indexOf(key);
            s = k < 0 ? m : m.substring(k + key.length);
            s = _removePrefix(s, ' · ');
          }
          failLine = s.trim().isEmpty ? 'failed' : s;
          showFail = true;
        }
      }
      textBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 8,
            children: [
              Flexible(
                child: T(
                  label,
                  weight: FontWeight.w600,
                  size: 12,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (e.status != null) ...[
                T(
                  '${e.status}',
                  color: statusColor(e.status!, pal),
                  weight: FontWeight.w600,
                  size: 12,
                ),
                T('${e.ms ?? 0} ms', color: pal.muted, size: 11),
              ],
              if (!open && passedOn != null && passedOn!.fields.isNotEmpty)
                Flexible(
                  child: T(
                    '→ ${passedOn!.fields.map((f) => f.$1).join(", ")}',
                    color: pal.muted,
                    size: 11,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          // Errors get their own line so they are not squeezed next to the name.
          if (showFail) T(failLine, color: pal.err, size: 11, mono: true),
        ],
      );
    } else {
      textBlock = T(e.text, size: 12, color: e.ok ? pal.text : pal.err);
    }

    final line = Padding(
      // The guide column is followed by the row's 8px spacing.
      padding: EdgeInsets.only(
        left: e.depth > 0 ? (e.depth * 14 + 8).toDouble() : 0,
      ),
      child: Row(
        spacing: 8,
        children: [
          if (expandable) Chevron(open: open) else const SizedBox(width: 14),
          Ico(
            e.ok ? Ic.checkCircle : Ic.cancel,
            tint: e.ok ? pal.ok : pal.err,
            size: 14,
          ),
          if (isReq && method != null)
            MethodPill(method)
          else
            SizedBox(
              width: METHOD_SLOT + 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: T(
                    tag,
                    color: tagColor,
                    size: 9,
                    weight: FontWeight.w700,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: textBlock,
            ),
          ),
          T(elapsed(e.at), color: pal.muted, size: 11),
          if (isReq && (c.ws.history[e.stepId]?.isNotEmpty ?? false))
            _link(
              'View response',
              () => c.state.modal = ModalViewResponse(
                tabId: c.tab.id,
                stepId: e.stepId,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              pal: pal,
            ),
        ],
      ),
    );
    return Clickable(
      onClick: expandable ? onToggle : null,
      cursor: expandable ? SystemMouseCursors.click : MouseCursor.defer,
      borderRadius: BorderRadius.circular(5),
      child: CustomPaint(
        painter: GuidesPainter(e.depth, pal.border),
        child: line,
      ),
    );
  }
}
