import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart' show CONTROL_H;
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/response_controls.dart' show Toggle;
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/runner/runner_logic.dart';
import 'package:open_rest/features/runner/runner_results.dart';
import 'package:open_rest/features/runner/runner_summary.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

String _digits(String s, int max) {
  final d = s
      .split('')
      .where((c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)
      .join();
  return d.length > max ? d.substring(0, max) : d;
}

/// Collection / folder runner, shown as a regular editor tab: header, settings strip, then requests and results side by side.
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
    final showResults = rs.results.isNotEmpty || rs.running;
    final scope = rs.folder == null ? col.name : _base(rs.folder!);
    return Container(
      color: pal.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, tab: tab, rs: rs, col: col, scope: scope),
          _Settings(rs: rs),
          if (showResults)
            RunnerSummary(state: state, tab: tab, rs: rs, title: scope),
          Expanded(
            child: all.isEmpty
                ? _EmptyScope(folder: rs.folder != null)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _RequestList(
                          rs: rs,
                          all: all,
                          base: rs.folder ?? col.path,
                        ),
                      ),
                      Container(width: 1, color: pal.border),
                      Expanded(flex: 6, child: RunnerResults(rs: rs)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _base(String path) {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }
}

class _EmptyScope extends StatelessWidget {
  const _EmptyScope({required this.folder});

  final bool folder;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Ico(Ic.folderOpen, tint: pal.muted, size: 32),
          T(
            'No requests in this ${folder ? 'folder' : 'collection'}',
            weight: FontWeight.w600,
          ),
          T('Add a request to it and come back to run it.', color: pal.muted),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.tab,
    required this.rs,
    required this.col,
    required this.scope,
  });

  final AppState state;
  final RequestTab tab;
  final RunnerSession rs;
  final Collection col;
  final String scope;

  String get _status {
    final chosen = rs.chosen.length;
    if (rs.running) {
      final n = rs.results.length + 1;
      final of = rs.planned < n ? n : rs.planned;
      return 'Running $n of $of · ${rs.current}';
    }
    if (rs.results.isNotEmpty) {
      final s = summarize(rs.results);
      final head = rs.cancelled ? 'Stopped' : 'Finished';
      return '$head · ${s.passed} passed, ${s.failed} failed'
          '${s.skipped > 0 ? ', ${s.skipped} skipped' : ''}';
    }
    if (chosen == 0) return 'Select at least one request to run';
    final it = rs.iters;
    return '$chosen request${chosen == 1 ? '' : 's'} selected'
        '${it > 1 ? ' · $it iterations' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final env = state.envName(col.path);
    final global = state.globalEnvName();
    final count = rs.chosen.length * rs.iters;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: _headerRow(pal, env, global, count),
    );
  }

  Widget _headerRow(Pal pal, String? env, String? global, int count) {
    return Row(
      spacing: 12,
      children: [
        Ico(Ic.play, tint: pal.accent, size: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: T(
                      scope,
                      size: 16,
                      weight: FontWeight.w600,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Chip(
                    rs.folder == null ? 'Collection' : 'Folder',
                    color: pal.muted,
                  ),
                  Chip(
                    env == null ? 'No environment' : 'Env: $env',
                    color: env == null ? pal.muted : pal.accent,
                  ),
                  if (global != null)
                    Chip('Global: $global', color: pal.accent),
                ],
              ),
              T(
                _status,
                color: rs.chosen.isEmpty && !rs.running ? pal.warn : pal.muted,
                size: 12,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (rs.running)
          Btn(
            label: 'Stop',
            onClick: () => rs.cancelled = true,
            danger: true,
            icon: Ic.stop,
          )
        else
          Btn(
            label: rs.chosen.isEmpty
                ? 'Run'
                : 'Run $count Request${count == 1 ? '' : 's'}',
            icon: Ic.play,
            onClick: () => state.startRunner(tab),
            primary: true,
            enabled: rs.chosen.isNotEmpty,
          ),
      ],
    );
  }
}

/// Always-visible run settings under the header: iterations, delay and stop-on-failure.
class _Settings extends StatelessWidget {
  const _Settings({required this.rs});

  final RunnerSession rs;

  Widget _labeled(Pal pal, String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      T(label, color: pal.muted, size: 11),
      SizedBox(height: CONTROL_H, child: control),
    ],
  );

  bool get _isDefault =>
      rs.iters == 1 && (int.tryParse(rs.delay) ?? 0) == 0 && !rs.stopOnFail;

  /// Iterations / delay / stop-on-failure controls as label-above-control columns; dimmed while running.
  Widget _settingsSection(Pal pal) => Opacity(
    opacity: rs.running ? 0.5 : 1,
    child: IgnorePointer(
      ignoring: rs.running,
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _labeled(
            pal,
            'Iterations',
            SizedBox(
              width: 72,
              child: Field(
                value: rs.iterations,
                onChange: (v) => rs.iterations = _digits(v, 3),
                placeholder: '1',
                highlightVars: false,
              ),
            ),
          ),
          _labeled(
            pal,
            'Delay (ms)',
            SizedBox(
              width: 96,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  Field(
                    value: rs.delay,
                    onChange: (v) => rs.delay = _digits(v, 6),
                    placeholder: '0',
                    highlightVars: false,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: IgnorePointer(
                      child: T('ms', color: pal.muted, size: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _labeled(
            pal,
            'Stop on failure',
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Toggle(
                  checked: rs.stopOnFail,
                  onChange: (v) => rs.stopOnFail = v,
                ),
                T(
                  rs.stopOnFail ? 'On' : 'Off',
                  size: 12,
                  color: rs.stopOnFail ? pal.accent : pal.muted,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _resetLink(Pal pal) => Clickable(
    onClick: () {
      rs.iterations = '1';
      rs.delay = '';
      rs.stopOnFail = false;
    },
    enabled: !rs.running,
    cursor: SystemMouseCursors.click,
    child: T('Reset to defaults', color: pal.muted, size: 12),
  );

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final open = rs.settingsOpen;
    final summary = settingsSummary(
      iterations: rs.iters,
      delayMs: int.tryParse(rs.delay) ?? 0,
      stopOnFail: rs.stopOnFail,
    );
    return Container(
      color: pal.hover,
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Clickable(
            onClick: () => rs.settingsOpen = !open,
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                spacing: 8,
                children: [
                  Chevron(open: open),
                  const SectionLabel('SETTINGS'),
                  if (!open)
                    Expanded(
                      child: T(
                        summary,
                        color: pal.muted,
                        size: 12,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(50, 4, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: _settingsSection(pal)),
                          if (!_isDefault) _resetLink(pal),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.rs, required this.all, required this.base});

  final RunnerSession rs;
  final List<RequestNode> all;
  final String base;

  Widget _link(BuildContext context, String text, VoidCallback onClick) {
    final pal = context.pal;
    return Clickable(
      onClick: onClick,
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: T(text, color: pal.accent, size: 12),
      ),
    );
  }

  void _setAll(bool Function(RequestNode) pick) {
    for (final it in all) {
      rs.selected[it.path] = pick(it);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final last = lastStatuses(rs.results.toList());
    final failed = last.values.any((s) => s == RunStatus.failed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
          child: Row(
            children: [
              const SectionLabel('REQUESTS'),
              const SizedBox(width: 8),
              T(
                '${rs.chosen.length} of ${rs.order.length} selected',
                color: pal.muted,
                size: 12,
              ),
              const Spacer(),
              _link(context, 'Select all', () => _setAll((_) => true)),
              _link(context, 'None', () => _setAll((_) => false)),
              if (failed)
                _link(
                  context,
                  'Failed only',
                  () => _setAll((n) => last[n.path] == RunStatus.failed),
                ),
              _link(context, 'Reset order', () => rs.resetOrder(all)),
            ],
          ),
        ),
        Expanded(
          child: ReorderableList(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: rs.order.length,
            onReorderItem: (from, to) {
              if (from == to) return;
              final it = rs.order.removeAt(from);
              rs.order.insert(to, it);
            },
            itemBuilder: (context, i) {
              final n = rs.order[i];
              final on = rs.selected[n.path] == true;
              final st = last[n.path];
              final dir = folderPath(n.path, base);
              return Padding(
                key: ValueKey(n.path),
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  color: pal.field,
                  child: Clickable(
                    onClick: () => rs.selected[n.path] = !on,
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        spacing: 8,
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Ico(Ic.drag, size: 16),
                            ),
                          ),
                          Check(
                            checked: on,
                            onChange: (v) => rs.selected[n.path] = v,
                          ),
                          MethodPill(n.request.method),
                          Expanded(
                            child: Row(
                              spacing: 8,
                              children: [
                                Flexible(
                                  child: T(
                                    n.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    color: on ? null : pal.muted,
                                  ),
                                ),
                                if (dir.isNotEmpty)
                                  Expanded(
                                    child: T(
                                      dir,
                                      color: pal.muted,
                                      size: 11,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: st == null
                                ? null
                                : Align(
                                    alignment: Alignment.centerRight,
                                    child: Ico(
                                      statusStyle(st, pal).$1,
                                      tint: statusStyle(st, pal).$2,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
