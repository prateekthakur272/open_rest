import 'package:flutter/widgets.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/test_results.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

String _digits(String s, int max) {
  final d = s
      .split('')
      .where((c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)
      .join();
  return d.length > max ? d.substring(0, max) : d;
}

/// Collection / folder runner, shown as a regular editor tab. Settings on the left, requests (then results) on the right.
class RunnerView extends StatelessWidget {
  const RunnerView({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, tab]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final pal = context.pal;
    final rs = tab.runner;
    if (rs == null) return const SizedBox.shrink();
    final col = state.collection(tab.collectionPath);
    if (col == null) return const SizedBox.shrink();
    final all = state.runnerRequests(col, rs.folder);
    final chosen = rs.chosen;
    final count = chosen.length * rs.iters;
    final showResults = rs.results.isNotEmpty || rs.running;
    final passed = rs.results
        .where(
          (it) =>
              it.result.error == null &&
              it.result.tests.every((t) => t.passed) &&
              !it.result.skipped,
        )
        .length;
    final total = rs.results.fold<int>(
      0,
      (a, it) => a + (it.result.response?.timeMs ?? 0),
    );

    // The hand cursor stays even when disabled.
    Widget link(String text, VoidCallback onClick, [bool enabled = true]) =>
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Clickable(
            onClick: onClick,
            enabled: enabled,
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: T(text, color: enabled ? pal.accent : pal.muted, size: 13),
            ),
          ),
        );

    final envLine =
        'Env: ${state.envName(col.path) ?? "No Environment"}${state.globalEnvName() != null ? " · Global: ${state.globalEnvName()}" : ""}';

    return Container(
      color: pal.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 10,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Ico(Ic.play, tint: pal.text, size: 18),
                      const T('Runner', size: 16, weight: FontWeight.w600),
                    ],
                  ),
                  T(
                    'You have ${all.length} request${all.length == 1 ? "" : "s"} in this ${rs.folder == null ? "collection" : "folder"}.',
                    size: 14,
                  ),
                  T(envLine, color: pal.muted, size: 12),
                  const SizedBox(height: 8),
                  const T('Timings', weight: FontWeight.w600, size: 14),
                  const T('Delay between requests (ms)', size: 13),
                  SizedBox(
                    width: double.infinity,
                    child: Field(
                      value: rs.delay,
                      onChange: (v) => rs.delay = _digits(v, 6),
                      placeholder: 'e.g. 5',
                      highlightVars: false,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const T('Execution', weight: FontWeight.w600, size: 14),
                  const T('Iterations', size: 13),
                  SizedBox(
                    width: 160,
                    child: Field(
                      value: rs.iterations,
                      onChange: (v) => rs.iterations = _digits(v, 3),
                      placeholder: '1',
                      highlightVars: false,
                    ),
                  ),
                  LabeledCheck(
                    label: 'Stop on first failure',
                    checked: rs.stopOnFail,
                    onChange: (v) => rs.stopOnFail = v,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      if (rs.running)
                        Btn(
                          label: 'Stop',
                          onClick: () => rs.cancelled = true,
                          danger: true,
                          icon: Ic.stop,
                        )
                      else
                        Btn(
                          label: chosen.isEmpty
                              ? 'Run'
                              : 'Run $count Request${count == 1 ? "" : "s"}',
                          icon: Ic.play,
                          onClick: () => state.startRunner(tab),
                          primary: true,
                          enabled: chosen.isNotEmpty,
                        ),
                      link('Reset', () {
                        rs.resetOrder(all);
                        rs.results.clear();
                        rs.delay = '';
                        rs.iterations = '1';
                        rs.stopOnFail = false;
                      }, !rs.running),
                    ],
                  ),
                  if (showResults) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      children: [
                        Chip('${rs.results.length} run', color: pal.accent),
                        Chip('$passed passed', color: pal.ok),
                        if (rs.results.length - passed > 0)
                          Chip(
                            '${rs.results.length - passed} failed',
                            color: pal.err,
                          ),
                        T('$total ms', color: pal.muted, size: 12),
                      ],
                    ),
                    if (rs.running)
                      T('Running: ${rs.current}…', color: pal.muted, size: 12),
                  ],
                ],
              ),
            ),
          ),
          Container(width: 1, color: pal.border),
          Expanded(
            flex: 13,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  if (!showResults) ...[
                    Container(
                      color: pal.field,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: T(
                              '${chosen.length} of ${rs.order.length} selected',
                              color: pal.muted,
                            ),
                          ),
                          if (chosen.isEmpty)
                            link('Select All', () {
                              for (final it in all) {
                                rs.selected[it.path] = true;
                              }
                            })
                          else
                            link('Deselect All', () {
                              for (final it in all) {
                                rs.selected[it.path] = false;
                              }
                            }),
                          link('Reset', () => rs.resetOrder(all)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rs.order.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final n = rs.order[i];
                          return Container(
                            color: pal.field,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              spacing: 10,
                              children: [
                                Check(
                                  checked: rs.selected[n.path] == true,
                                  onChange: (v) => rs.selected[n.path] = v,
                                ),
                                SizedBox(
                                  width: 54,
                                  child: T(
                                    n.request.method,
                                    color: methodColor(n.request.method, pal),
                                    size: 12,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                Expanded(
                                  child: T(
                                    n.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconBtn(
                                  icon: Ic.moveUp,
                                  onClick: () {
                                    if (i > 0) {
                                      final t = rs.order[i];
                                      rs.order[i] = rs.order[i - 1];
                                      rs.order[i - 1] = t;
                                    }
                                  },
                                  size: 14,
                                ),
                                IconBtn(
                                  icon: Ic.moveDown,
                                  onClick: () {
                                    if (i < rs.order.length - 1) {
                                      final t = rs.order[i];
                                      rs.order[i] = rs.order[i + 1];
                                      rs.order[i + 1] = t;
                                    }
                                  },
                                  size: 14,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    Container(
                      color: pal.field,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: T('Results', color: pal.muted)),
                          link(
                            'Back to selection',
                            () => rs.results.clear(),
                            !rs.running,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rs.results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final it0 = rs.results[i];
                          final r = it0.result;
                          final ok =
                              r.error == null &&
                              !r.skipped &&
                              r.tests.every((t) => t.passed);
                          final resp =
                              r.response != null && r.response!.error == null
                              ? r.response
                              : null;
                          return Clickable(
                            onClick: () =>
                                rs.expanded = rs.expanded == i ? null : i,
                            child: Container(
                              color: pal.field,
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    spacing: 8,
                                    children: [
                                      Ico(
                                        r.skipped
                                            ? Ic.skip
                                            : (ok ? Ic.checkCircle : Ic.cancel),
                                        tint: ok
                                            ? pal.ok
                                            : (r.skipped ? pal.muted : pal.err),
                                        size: 16,
                                      ),
                                      SizedBox(
                                        width: 52,
                                        child: T(
                                          it0.node.request.method,
                                          color: methodColor(
                                            it0.node.request.method,
                                            pal,
                                          ),
                                          size: 11,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                      Expanded(
                                        child: T(it0.node.name, maxLines: 1),
                                      ),
                                      if (resp != null) ...[
                                        T(
                                          '${resp.status}',
                                          color: statusColor(resp.status, pal),
                                          weight: FontWeight.w600,
                                        ),
                                        T(
                                          '${resp.timeMs} ms',
                                          color: pal.muted,
                                          size: 12,
                                        ),
                                      ],
                                      if (r.tests.isNotEmpty)
                                        T(
                                          '${r.tests.where((t) => t.passed).length}/${r.tests.length} tests',
                                          color: r.tests.every((t) => t.passed)
                                              ? pal.ok
                                              : pal.err,
                                          size: 12,
                                        ),
                                    ],
                                  ),
                                  if (rs.expanded == i) ...[
                                    if (r.error != null)
                                      T(
                                        r.error!,
                                        color: pal.err,
                                        mono: true,
                                        size: 12,
                                      ),
                                    if (r.tests.isNotEmpty)
                                      TestsList(tests: r.tests),
                                    if (r.logs.isNotEmpty)
                                      T(
                                        r.logs.join('\n'),
                                        mono: true,
                                        color: pal.muted,
                                        size: 12,
                                      ),
                                    if (resp != null)
                                      T(
                                        resp.text.length > 1500
                                            ? resp.text.substring(0, 1500)
                                            : resp.text,
                                        mono: true,
                                        size: 12,
                                        color: pal.muted,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
