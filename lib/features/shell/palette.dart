import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/theme/theme.dart';

class _Cmd {
  const _Cmd({
    required this.title,
    this.sub = '',
    this.badge,
    this.badgeColor,
    required this.group,
    required this.run,
  });
  final String title;
  final String sub;
  final String? badge;
  final Color? badgeColor;
  final String group;
  final VoidCallback run;
}

int _fuzzy(String q, String t) {
  if (q.isEmpty) return 0;
  final ql = q.toLowerCase();
  final tl = t.toLowerCase();
  var qi = 0, score = 0, last = -2;
  for (var i = 0; i < tl.length; i++) {
    if (qi < ql.length && tl[i] == ql[qi]) {
      score += i == last + 1 ? 6 : 1;
      if (i == 0 || ' /-_.:'.contains(tl[i - 1])) score += 4;
      last = i;
      qi++;
    }
  }
  return qi == ql.length ? score - t.length ~/ 25 : -1;
}

String _take(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Command palette for jumping to requests and actions.
class Palette extends StatefulWidget {
  const Palette({super.key, required this.state});
  final AppState state;

  @override
  State<Palette> createState() => _PaletteState();
}

class _PaletteState extends State<Palette> {
  String q = '';
  int sel = 0;
  final FocusNode fr = FocusNode();
  final ScrollController scroll = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int _lastIndex = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fr.requestFocus();
    });
  }

  @override
  void dispose() {
    fr.dispose();
    scroll.dispose();
    super.dispose();
  }

  void close() => state.modal = null;
  VoidCallback go(VoidCallback f) => () {
    close();
    f();
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = <_Cmd>[];
    for (final c in state.collections) {
      for (final r in c.allRequests()) {
        final folder = c.ancestorFolders(r.path).map((f) => f.name).join(' / ');
        all.add(
          _Cmd(
            title: r.name,
            sub:
                '${[c.name, folder].where((s) => s.isNotEmpty).join(' / ')}  ·  ${_take(r.request.url, 60)}',
            badge: r.request.method,
            badgeColor: methodColor(r.request.method, p),
            group: 'Requests',
            run: go(() => state.openRequest(c.path, r)),
          ),
        );
      }
    }
    final tab = (state.activeTab != null && state.activeTab!.isRequest)
        ? state.activeTab
        : null;
    final col = state.currentCollection;
    void act(String t, VoidCallback f, [String sub = '']) => all.add(
      _Cmd(
        title: t,
        sub: sub,
        badge: '›',
        badgeColor: p.muted,
        group: 'Commands',
        run: go(f),
      ),
    );
    if (tab != null) {
      act('Send request', () => state.send(tab), '⌘↵');
      act('Save request', () => state.save(tab), '⌘S');
      act(
        'Generate code…',
        () => state.modal = ModalCodegen(tabId: tab.id),
        '',
      );
      act('Copy as cURL', () => state.copyCurl(tab), '⌘⇧C');
      act('Close tab', () => state.closeTab(tab.id), '⌘W');
      act('Focus URL bar', () => state.urlFocus.requestFocus(), '⌘L');
    }
    act('Save all', () => state.saveAll(), '⌘⇧S');
    act('Environments: Global', () => state.modal = const ModalEnvs());
    act('Switch global environment: None', () => state.setGlobalEnv(null));
    for (final e in state.globalEnvs) {
      act(
        'Switch global environment: ${e.name}',
        () => state.setGlobalEnv(e.name),
      );
    }
    if (col != null) {
      act(
        'New request',
        () =>
            state.modal = ModalNewRequest(collection: col.path, dir: col.path),
        '⌘N',
      );
      act('New folder', () => state.promptNewFolder(col.path, col.path));
      act(
        'Run collection: ${col.name}',
        () => state.openRunner(col.path, null),
      );
      act('New workflow', () => state.promptNewWorkflow(col.path));
      for (final w in col.workflows) {
        act(
          'Open workflow: ${w.name}',
          () => state.openWorkflow(col.path, w.name),
          col.name,
        );
      }
      act(
        'Environments: ${col.name}',
        () => state.modal = ModalEnvs(collection: col.path),
      );
      act(
        'Variables inspector',
        () => state.modal = ModalVars(collection: col.path),
      );
      act(
        'Collection settings',
        () => state.openCollectionTab(col.path, page: NodeSection.headers),
      );
      act('Collection overview', () => state.openCollectionTab(col.path));
      act(
        'Export collection…',
        () => state.modal = ModalExport(collection: col.path),
      );
      act('Switch environment: None', () => state.setEnv(col.path, null));
      for (final e in col.environments) {
        act(
          'Switch environment: ${e.name}',
          () => state.setEnv(col.path, e.name),
        );
      }
    }
    act('New collection…', () => state.modal = const ModalNewCollection());
    act('Open collection…', () => state.modal = const ModalOpenCollection());
    act('Import…', () => state.modal = const ModalImport());
    act('Cookies', () => state.modal = const ModalCookies());
    act('Welcome tour', () => state.modal = const ModalOnboarding());
    act('Preferences', () => state.modal = const ModalSettings(), '⌘,');
    for (final m in ThemeMode.values.where((m) => m != state.settings.theme)) {
      act(
        'Theme: ${m.label}',
        () => state.updateSettings(state.settings.copyWith(theme: m)),
      );
    }
    act(
      'Toggle layout (stacked / side by side)',
      () => state.toggleLayout(),
      '⌘⇧L',
    );
    act('Zoom in', () => state.zoom(1), '⌘+');
    act('Zoom out', () => state.zoom(-1), '⌘−');
    act('Reset zoom', () => state.zoom(0), '⌘0');
    act(
      'Toggle sidebar',
      () => state.sidebarVisible = !state.sidebarVisible,
      '⌘B',
    );
    act('Show request history', () {
      state.sidebarVisible = true;
      state.sidebarTab = 'History';
    });
    act('Collapse all folders', () => state.collapseAll());
    act('Expand all folders', () => state.expandAll());
    act('Reload collections from disk', () => state.reloadAll());

    List<_Cmd> results;
    if (q.trim().isEmpty) {
      results = all.take(40).toList();
    } else {
      final scored = [
        for (final c in all) (c, _fuzzy(q.trim(), '${c.title} ${c.sub}')),
      ].where((e) => e.$2 >= 0).toList();
      // Stable sort by descending score (+2 for requests).
      final idx = List<int>.generate(scored.length, (i) => i);
      int key(int i) =>
          scored[i].$2 + (scored[i].$1.group == 'Requests' ? 2 : 0);
      idx.sort((a, b) {
        final c = key(b).compareTo(key(a));
        return c != 0 ? c : a.compareTo(b);
      });
      results = idx.take(60).map((i) => scored[i].$1).toList();
    }
    final index = results.isEmpty ? 0 : sel.clamp(0, results.length - 1);
    if (index != _lastIndex) {
      _lastIndex = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || results.isEmpty) return;
        final target =
            _itemKeys[(index - 3).clamp(0, results.length - 1)]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 120),
            alignment: 0,
          );
        }
      });
    }

    return ClickableNoRipple(
      onClick: close,
      child: Container(
        color: const Color(0xFF000000).withValues(alpha: 0.45),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 80),
        child: Align(
          alignment: Alignment.topCenter,
          child: ClickableNoRipple(
            child: Focus(
              onKeyEvent: (n, e) {
                if (e is KeyUpEvent) return KeyEventResult.ignored;
                final k = e.logicalKey;
                if (k == LogicalKeyboardKey.arrowDown) {
                  setState(
                    () => sel = (index + 1).clamp(
                      0,
                      results.isEmpty ? 0 : results.length - 1,
                    ),
                  );
                  return KeyEventResult.handled;
                }
                if (k == LogicalKeyboardKey.arrowUp) {
                  setState(() => sel = (index - 1) < 0 ? 0 : index - 1);
                  return KeyEventResult.handled;
                }
                if (k == LogicalKeyboardKey.enter ||
                    k == LogicalKeyboardKey.numpadEnter) {
                  if (index < results.length) results[index].run();
                  return KeyEventResult.handled;
                }
                if (k == LogicalKeyboardKey.escape) {
                  close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: 680,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(12),
                ),
                // Borders are painted over the content so they take no layout space.
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        spacing: 10,
                        children: [
                          T(
                            '⌘K',
                            color: p.accent,
                            mono: true,
                            weight: FontWeight.w700,
                          ),
                          Expanded(
                            child: Field(
                              value: q,
                              onChange: (v) => setState(() {
                                q = v;
                                sel = 0;
                              }),
                              placeholder: 'Search requests, run commands, switch environments…',
                              bordered: false,
                              focusRequester: fr,
                              highlightVars: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: p.border),
                    if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: T('No matches', color: p.muted),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: SingleChildScrollView(
                          controller: scroll,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < results.length; i++)
                                ..._row(p, results, i, index),
                            ],
                          ),
                        ),
                      ),
                    Container(height: 1, color: p.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        spacing: 16,
                        children: [
                          T('↑↓ navigate', color: p.muted, size: 11),
                          T('↵ run', color: p.muted, size: 11),
                          T('esc close', color: p.muted, size: 11),
                          const Spacer(),
                          T(
                            '${results.length} results',
                            color: p.muted,
                            size: 11,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _row(Pal p, List<_Cmd> results, int i, int index) {
    final c = results[i];
    final prevGroup = i > 0 ? results[i - 1].group : null;
    return [
      if (c.group != prevGroup)
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 2),
          child: SectionLabel(c.group.toUpperCase()),
        ),
      Clickable(
        onClick: c.run,
        cursor: SystemMouseCursors.basic,
        child: Container(
          key: _itemKeys.putIfAbsent(i, () => GlobalKey()),
          color: i == index ? p.selected : const Color(0x00000000),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            spacing: 10,
            children: [
              if (c.badge != null)
                SizedBox(
                  width: 44,
                  child: T(
                    c.badge!,
                    color: c.badgeColor ?? p.muted,
                    size: 11,
                    weight: FontWeight.w700,
                  ),
                ),
              Flexible(
                child: T(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (c.sub.isNotEmpty)
                Flexible(
                  child: T(
                    c.sub,
                    color: p.muted,
                    size: 12,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }
}
