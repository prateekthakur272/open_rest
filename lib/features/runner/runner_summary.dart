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

    Widget tile(String label, String value, [Color? color]) => Expanded(
      child: Container(
        color: pal.field,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(label.toUpperCase()),
            T(value, size: 18, weight: FontWeight.w600, color: color),
          ],
        ),
      ),
    );

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
                    alignment: Alignment.centerLeft,
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
          Row(
            spacing: 8,
            children: [
              tile('Passed', '${s.passed}', pal.ok),
              tile('Failed', '${s.failed}', s.failed > 0 ? pal.err : null),
              tile('Skipped', '${s.skipped}'),
              tile('Total', formatDuration(_elapsedMs)),
              tile('Avg response', '${s.avgMs} ms'),
              tile(
                'Tests',
                '${s.testsPassed}/${s.testsTotal}',
                s.testsPassed < s.testsTotal ? pal.err : null,
              ),
            ],
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
