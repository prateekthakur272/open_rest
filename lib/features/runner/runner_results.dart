import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/app/sessions.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/test_results.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/features/runner/runner_logic.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/format.dart';

/// Icon and colour for a run status.
(IconData, Color) statusStyle(RunStatus s, Pal pal) => switch (s) {
  RunStatus.passed => (Ic.checkCircle, pal.ok),
  RunStatus.failed => (Ic.cancel, pal.err),
  RunStatus.skipped => (Ic.skip, pal.muted),
};

/// Disclosure chevron: points down when open, right when closed.
class Chevron extends StatelessWidget {
  const Chevron({super.key, required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? 0 : -0.25,
    duration: const Duration(milliseconds: 150),
    child: Ico(Ic.down, size: 16),
  );
}

/// Right pane of the runner: filter chips and the (optionally iteration-grouped) result rows.
class RunnerResults extends StatelessWidget {
  const RunnerResults({super.key, required this.rs});

  final RunnerSession rs;

  static const _labels = {
    ResultFilter.all: 'All',
    ResultFilter.failed: 'Failed',
    ResultFilter.passed: 'Passed',
    ResultFilter.skipped: 'Skipped',
  };

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final items = rs.results.toList();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Ico(Ic.play, tint: pal.muted, size: 28),
            T(
              rs.running ? 'Waiting for the first response…' : 'No results yet',
              weight: FontWeight.w600,
            ),
            if (!rs.running)
              T(
                'Choose the requests to run and press Run.',
                color: pal.muted,
                size: 12,
              ),
          ],
        ),
      );
    }
    final sum = summarize(items);
    final counts = {
      ResultFilter.all: sum.total,
      ResultFilter.failed: sum.failed,
      ResultFilter.passed: sum.passed,
      ResultFilter.skipped: sum.skipped,
    };
    final shown = filterIndices(items, rs.filter);
    final grouped = rs.iters > 1 || items.any((it) => it.iteration > 0);
    final entries = <Object>[];
    if (grouped) {
      final all = {
        for (final g in groupByIteration(items, [
          for (var i = 0; i < items.length; i++) i,
        ]))
          g.iteration: g,
      };
      for (final g in groupByIteration(items, shown)) {
        entries.add(all[g.iteration]!);
        if (rs.collapsed[g.iteration] != true) entries.addAll(g.indices);
      }
    } else {
      entries.addAll(shown);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            spacing: 6,
            children: [
              const SectionLabel('RESULTS'),
              const SizedBox(width: 6),
              for (final f in ResultFilter.values)
                _FilterChip(
                  label: '${_labels[f]} ${counts[f]}',
                  selected: rs.filter == f,
                  onClick: () => rs.filter = f,
                ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: T(
                    'No ${_labels[rs.filter]!.toLowerCase()} results.',
                    color: pal.muted,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    if (e is IterationGroup) {
                      return _GroupHeader(rs: rs, group: e);
                    }
                    final idx = e as int;
                    return _ResultRow(rs: rs, index: idx, item: items[idx]);
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onClick,
  });

  final String label;
  final bool selected;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Clickable(
      onClick: onClick,
      cursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? pal.accent.withValues(alpha: 0.16) : pal.field,
          borderRadius: BorderRadius.circular(12),
        ),
        child: T(
          label,
          size: 12,
          color: selected ? pal.accent : pal.muted,
          weight: selected ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.rs, required this.group});

  final RunnerSession rs;
  final IterationGroup group;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final open = rs.collapsed[group.iteration] != true;
    final s = group.summary;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Clickable(
        onClick: () => rs.collapsed[group.iteration] = open,
        cursor: SystemMouseCursors.click,
        child: Container(
          color: pal.panel,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            spacing: 8,
            children: [
              Chevron(open: open),
              T('Iteration ${group.iteration + 1}', weight: FontWeight.w600),
              const Spacer(),
              T('${s.passed} passed', color: pal.ok, size: 12),
              if (s.failed > 0)
                T('${s.failed} failed', color: pal.err, size: 12),
              if (s.skipped > 0)
                T('${s.skipped} skipped', color: pal.muted, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.rs, required this.index, required this.item});

  final RunnerSession rs;
  final int index;
  final RunnerItem item;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = item.result;
    final st = statusOf(item);
    final (icon, color) = statusStyle(st, pal);
    final resp = responseOf(item);
    final open = rs.expanded == index;
    final passedTests = r.tests.where((t) => t.passed).length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        color: pal.field,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Clickable(
              onClick: () => rs.expanded = open ? null : index,
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  spacing: 10,
                  children: [
                    Ico(icon, tint: color),
                    MethodPill(requestLine(item).$1),
                    Expanded(
                      child: T(
                        item.node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: T(
                        resp == null ? '-' : '${resp.status}',
                        color: resp == null
                            ? pal.muted
                            : statusColor(resp.status, pal),
                        weight: FontWeight.w600,
                        size: 12,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: T(
                        resp == null ? '' : '${resp.timeMs} ms',
                        color: pal.muted,
                        size: 12,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: T(
                        resp == null ? '' : formatSize(resp.size),
                        color: pal.muted,
                        size: 12,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: T(
                        r.tests.isEmpty
                            ? ''
                            : '$passedTests/${r.tests.length} tests',
                        color: passedTests == r.tests.length ? pal.ok : pal.err,
                        size: 12,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open) _Detail(item: item),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.item});

  final RunnerItem item;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = item.result;
    final resp = responseOf(item);
    final (method, url) = requestLine(item);
    final failed = r.tests.where((t) => !t.passed).toList();
    final error = r.error ?? r.response?.error;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: pal.border)),
      ),
      padding: const EdgeInsets.fromLTRB(36, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          T('$method $url', mono: true, size: 12),
          if (resp != null)
            T(
              '${resp.status} ${resp.statusText} · ${resp.timeMs} ms · ${formatSize(resp.size)}',
              color: statusColor(resp.status, pal),
              size: 12,
            ),
          if (r.skipped) T('Skipped by a script.', color: pal.muted, size: 12),
          if (error != null) T(error, color: pal.err, mono: true, size: 12),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 4),
            const SectionLabel('FAILED TESTS'),
            TestsList(tests: failed),
          ] else if (r.tests.isNotEmpty)
            T('All ${r.tests.length} tests passed.', color: pal.ok, size: 12),
          if (r.logs.isNotEmpty) ...[
            const SizedBox(height: 4),
            const SectionLabel('CONSOLE'),
            T(r.logs.join('\n'), mono: true, color: pal.muted, size: 12),
          ],
          if (resp != null && resp.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            const SectionLabel('RESPONSE'),
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
    );
  }
}
