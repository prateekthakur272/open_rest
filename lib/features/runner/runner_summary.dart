import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/features/runner/runner_logic.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Progress bar, summary tiles and post-run actions of a runner tab.
class RunnerSummary extends StatefulWidget {
  const RunnerSummary({
    super.key,
    required this.state,
    required this.tab,
    required this.rs,
    required this.title,
  });

  final AppState state;
  final RequestTab tab;
  final RunnerSession rs;

  /// Collection or folder name used in reports.
  final String title;

  @override
  State<RunnerSummary> createState() => _RunnerSummaryState();
}

class _RunnerSummaryState extends State<RunnerSummary> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _elapsedMs {
    final s = widget.rs.startedAt;
    if (s == null) return 0;
    return (widget.rs.finishedAt ?? DateTime.now())
        .difference(s)
        .inMilliseconds;
  }

  void _syncTimer() {
    if (widget.rs.running && _tick == null) {
      _tick = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => mounted ? setState(() {}) : null,
      );
    } else if (!widget.rs.running) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _copy() async {
    await Platform.copy(
      reportText(
        title: widget.title,
        items: widget.rs.results.toList(),
        elapsedMs: _elapsedMs,
      ),
    );
    widget.state.showToast('Summary copied');
  }

  Future<void> _export() async {
    final path = await Platform.saveFile(
      'Export results',
      'runner-results.json',
    );
    if (path == null) return;
    try {
      await File(path)
          .writeAsString(resultsJson(widget.title, widget.rs.results.toList()));
      widget.state.showToast('Results exported');
    } catch (e) {
      widget.state.showToast('Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTimer();
    final pal = context.pal;
    final rs = widget.rs;
    final items = rs.results.toList();
    final s = summarize(items);
    final finished = !rs.running;
    final planned = rs.planned < items.length ? items.length : rs.planned;
    final frac = finished
        ? 1.0
        : (planned == 0 ? 0.0 : (items.length / planned).clamp(0.0, 1.0));
    final barColor = s.failed > 0 ? pal.err : (finished ? pal.ok : pal.accent);
    final failedNodes = failedRequests(items);

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
      required String caption,
      required Color accent,
      Color? valueColor,
      bool status = false,
      bool tint = false,
    }) {
      return Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: tint ? pal.err.withValues(alpha: 0.06) : pal.bg,
            borderRadius: BorderRadius.circular(8),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: pal.border),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 3, color: status ? accent : null),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Ico(icon, tint: accent, size: 16),
                          ),
                        ),
                        Flexible(
                          child: T(
                            label.toUpperCase(),
                            color: pal.muted,
                            size: 10.5,
                            weight: FontWeight.w600,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: T(
                        value,
                        key: ValueKey(value),
                        size: 24,
                        weight: FontWeight.w600,
                        mono: true,
                        color: valueColor,
                        maxLines: 1,
                      ),
                    ),
                    T(
                      caption,
                      size: 11,
                      color: pal.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final tiles = [
      tile(
        icon: Ic.check,
        label: 'Passed',
        value: '${s.passed}',
        caption: passedCaption(s),
        accent: pal.ok,
        valueColor: s.passed > 0 ? pal.ok : null,
        status: true,
      ),
      tile(
        icon: Ic.cancel,
        label: 'Failed',
        value: '${s.failed}',
        caption: failedCaption(s),
        accent: pal.err,
        valueColor: s.failed > 0 ? pal.err : null,
        status: s.failed > 0,
        tint: s.failed > 0,
      ),
      tile(
        icon: Ic.skip,
        label: 'Skipped',
        value: '${s.skipped}',
        caption: skippedCaption(s),
        accent: pal.warn,
      ),
      tile(
        icon: Ic.timer,
        label: 'Total',
        value: formatDuration(_elapsedMs),
        caption: 'wall clock',
        accent: pal.accent,
      ),
      tile(
        icon: Ic.speed,
        label: 'Avg response',
        value: '${s.avgMs} ms',
        caption: avgCaption(s),
        accent: pal.muted,
      ),
      tile(
        icon: Ic.checklist,
        label: 'Tests',
        value: testsValue(s),
        caption: testsCaption(s),
        accent: s.testsPassed < s.testsTotal ? pal.err : pal.muted,
        valueColor: s.testsPassed < s.testsTotal ? pal.err : null,
      ),
    ];

    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: pal.field,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: frac,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              T('${(frac * 100).round()}%', weight: FontWeight.w600, size: 12),
              T(formatDuration(_elapsedMs), color: pal.muted, size: 12),
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 560 ? 3 : 2);
              final w = (c.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in tiles)
                    SizedBox(
                      width: w,
                      child: Row(children: [t]),
                    ),
                ],
              );
            },
          ),
          if (finished && items.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Btn(
                  label: 'Run again',
                  icon: Ic.refresh,
                  onClick: () => widget.state.startRunner(widget.tab),
                  enabled: rs.chosen.isNotEmpty,
                ),
                Btn(
                  label: 'Re-run failed (${failedNodes.length})',
                  icon: Ic.play,
                  onClick: () =>
                      widget.state.startRunner(widget.tab, only: failedNodes),
                  enabled: failedNodes.isNotEmpty,
                ),
                Btn(label: 'Copy summary', icon: Ic.copy, onClick: _copy),
                Btn(
                  label: 'Export results…',
                  icon: Ic.export,
                  onClick: _export,
                ),
                Btn(label: 'Clear', onClick: () => rs.results.clear()),
              ],
            ),
        ],
      ),
    );
  }
}
