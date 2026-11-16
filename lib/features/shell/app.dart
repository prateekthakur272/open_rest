// ignore_for_file: constant_identifier_names, non_constant_identifier_names, deprecated_member_use
import 'dart:async';

import 'package:flutter/gestures.dart'
    show
        kMiddleMouseButton,
        PointerScrollEvent,
        PointerDeviceKind,
        HorizontalDragGestureRecognizer;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/context_menu.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/features/request/request_pane.dart';
import 'package:open_rest/features/collection/collection_view.dart';
import 'package:open_rest/features/runner/runner_view.dart';
import 'package:open_rest/features/shell/env_selector.dart';
import 'package:open_rest/features/shell/menus.dart';
import 'package:open_rest/features/shell/modals.dart';
import 'package:open_rest/features/shell/title_menus.dart';
import 'package:open_rest/features/shell/window_chrome.dart';
import 'package:open_rest/features/sidebar/sidebar.dart';
import 'package:open_rest/features/sidebar/tree.dart' show MiniSpinner;
import 'package:open_rest/features/workflow/workflow_view.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:window_manager/legacy.dart' as wm;

/// Esc closes an open title-bar menu; returns false (leaving Esc to others) when none is open.
bool closeTitleMenu(AppState state) {
  if (state.titleMenu.open == null) return false;
  state.titleMenu.close();
  return true;
}

/// The window-wide keyboard shortcuts. Call it for key events before the focused widget sees them.
bool handleKey(AppState state, KeyEvent e) {
  if (e is KeyUpEvent) return false;
  final k = e.logicalKey;
  if (k == LogicalKeyboardKey.escape && closeTitleMenu(state)) return true;
  final kb = HardwareKeyboard.instance;
  final mod = kb.isMetaPressed || kb.isControlPressed;
  final shift = kb.isShiftPressed;
  final anyTab = state.activeTab;
  final tab = (anyTab != null && anyTab.isRequest) ? anyTab : null;
  if (k == LogicalKeyboardKey.tab && kb.isControlPressed) {
    state.nextTab(shift ? -1 : 1);
    return true;
  }
  if (!mod) return false;
  const digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  final di = digits.indexOf(k);
  if (di >= 0) {
    state.gotoTab(di == 8 ? state.tabs.length - 1 : di);
    return true;
  }
  if (k == LogicalKeyboardKey.keyK || k == LogicalKeyboardKey.keyP) {
    state.modal = state.modal is ModalPalette ? null : const ModalPalette();
    return true;
  }
  if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
    if (tab != null) state.send(tab);
    return tab != null;
  }
  if (k == LogicalKeyboardKey.keyS) {
    if (shift) {
      state.saveAll();
    } else if (anyTab != null) {
      state.save(anyTab);
    }
    return true;
  }
  if (k == LogicalKeyboardKey.keyW) {
    if (anyTab != null) state.closeTab(anyTab.id);
    return anyTab != null;
  }
  if (k == LogicalKeyboardKey.keyN) {
    final c = state.currentCollection;
    state.modal = c != null
        ? ModalNewRequest(collection: c.path, dir: c.path)
        : const ModalNewCollection();
    return true;
  }
  if (k == LogicalKeyboardKey.keyB) {
    state.sidebarVisible = !state.sidebarVisible;
    return true;
  }
  if (k == LogicalKeyboardKey.keyL) {
    if (shift) {
      state.toggleLayout();
      return true;
    }
    state.urlFocus.requestFocus();
    return tab != null;
  }
  if (k == LogicalKeyboardKey.keyC) {
    if (shift && tab != null) {
      state.copyCurl(tab);
      return true;
    }
    return false;
  }
  if (k == LogicalKeyboardKey.bracketLeft ||
      k == LogicalKeyboardKey.braceLeft) {
    if (shift) {
      state.nextTab(-1);
      return true;
    }
    return false;
  }
  if (k == LogicalKeyboardKey.bracketRight ||
      k == LogicalKeyboardKey.braceRight) {
    if (shift) {
      state.nextTab(1);
      return true;
    }
    return false;
  }
  if (k == LogicalKeyboardKey.comma) {
    state.modal = const ModalSettings();
    return true;
  }
  if (k == LogicalKeyboardKey.equal ||
      k == LogicalKeyboardKey.add ||
      k == LogicalKeyboardKey.numpadAdd) {
    state.zoom(1);
    return true;
  }
  if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
    state.zoom(-1);
    return true;
  }
  if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0) {
    state.zoom(0);
    return true;
  }
  return false;
}

/// The window's content: title bar, header, sidebar, tabs, the active tab's view, status bar and the modal layer.
/// Place it below the theme / [AppScope] (see `main.dart`).
class OpenRestApp extends StatefulWidget {
  const OpenRestApp({
    super.key,
    required this.state,
    this.chrome = WindowChrome.none,
  });

  final AppState state;
  final WindowChrome chrome;

  @override
  State<OpenRestApp> createState() => _OpenRestAppState();
}

class _OpenRestAppState extends State<OpenRestApp> with wm.WindowListener {
  final MenuOverlay menuOverlay = MenuOverlay();
  bool wasFocused = true;
  bool _listening = false;
  List<Object?> _layout = const [];
  Timer? _layoutTimer;

  // Layout changes are saved as they happen, not only on quit.
  void _layoutChanged() {
    final now = widget.state.layoutSnapshot();
    if (_snapshotEq(now, _layout)) return;
    _layout = now;
    _layoutTimer?.cancel();
    _layoutTimer = Timer(
      const Duration(milliseconds: 500),
      () => widget.state.persist(),
    );
  }

  static bool _snapshotEq(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x is Set && y is Set) {
        if (x.length != y.length || !x.containsAll(y)) return false;
      } else if (x != y) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _layout = widget.state.layoutSnapshot();
    widget.state.addListener(_layoutChanged);
    try {
      wm.windowManager.addListener(this);
      _listening = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    _layoutTimer?.cancel();
    widget.state.removeListener(_layoutChanged);
    if (_listening) {
      try {
        wm.windowManager.removeListener(this);
      } catch (_) {}
    }
    menuOverlay.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() {
    if (!wasFocused) widget.state.reloadAll();
    wasFocused = true;
  }

  @override
  void onWindowBlur() => wasFocused = false;

  void _pointerDown(PointerDownEvent e) {
    // A press outside the open title-bar menu closes it without being consumed.
    final tm = widget.state.titleMenu;
    if (tm.open != null) {
      final pos = e.position;
      final inPanel = tm.panel?.contains(pos) == true;
      final inAnchor = tm.anchors.values.any((r) => r.contains(pos));
      if (!inPanel && !inAnchor) tm.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final p = context.pal;
        return LocalMenuOverlay(
          value: menuOverlay,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _pointerDown,
            child: Container(
              color: p.bg,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleBar(state: state, chrome: widget.chrome),
                      _TopBar(state: state),
                      Expanded(child: _Body(state: state)),
                      _StatusBar(state: state),
                    ],
                  ),
                  Modals(state: state),
                  MenuOverlayHost(overlay: menuOverlay),
                  if (state.toast != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: p.dark
                                    ? const Color(0xFF3A3F47)
                                    : const Color(0xFF1F2328),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: T(
                                state.toast!,
                                color: const Color(0xFFFFFFFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return LayoutBuilder(
      builder: (context, c) {
        final totalPx = c.maxWidth;
        final sidebarDp = (c.maxWidth * state.sidebarWidth)
            .clamp(210.0, 480.0)
            .toDouble();
        final tab = state.activeTab;
        Widget content;
        if (tab?.collection != null) {
          content = CollectionView(
            key: ValueKey(tab!.id),
            state: state,
            tab: tab,
          );
        } else if (tab?.workflow != null) {
          content = WorkflowView(
            key: ValueKey(tab!.id),
            state: state,
            tab: tab,
          );
        } else if (tab?.runner != null) {
          content = RunnerView(key: ValueKey(tab!.id), state: state, tab: tab);
        } else if (tab != null) {
          content = RequestView(key: ValueKey(tab.id), state: state, tab: tab);
        } else {
          content = _Welcome(state: state);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.sidebarVisible)
              SizedBox(
                width: sidebarDp,
                child: Sidebar(state: state),
              ),
            if (state.sidebarVisible)
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) => state.sidebarWidth =
                      (state.sidebarWidth + d.delta.dx / totalPx)
                          .clamp(0.12, 0.45)
                          .toDouble(),
                  child: Container(width: 5, color: p.border),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.tabs.isNotEmpty) _TabStrip(state: state),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopBtn extends StatelessWidget {
  const _TopBtn({
    required this.label,
    required this.icon,
    required this.onClick,
  });
  final String label;
  final IconData icon;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HoverBuilder(
      indicate: true,
      borderRadius: BorderRadius.circular(5),
      cursor: SystemMouseCursors.click,
      onTap: onClick,
      builder: (ctx, hov) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: hov ? p.hover : const Color(0x00000000),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Ico(icon, tint: hov ? p.text : p.muted, size: 15),
            T(label, color: hov ? p.text : p.muted, size: 12),
          ],
        ),
      ),
    );
  }
}

/// The slim title bar above the header: it moves the window and (on Windows / Linux) carries the window buttons.
const double TITLE_BAR_HEIGHT = 30;

/// The window's own title bar. macOS keeps its native traffic-light buttons floating over its left end ([WindowChrome.leftInset]);
/// Windows / Linux get our buttons on the right. In the middle: which collection and tab you are working in.
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.state, required this.chrome});
  final AppState state;
  final WindowChrome chrome;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = state.currentCollection;
    final tab = state.activeTab;
    return chrome.dragArea(
      Container(
        height: TITLE_BAR_HEIGHT,
        color: p.panel,
        child: DrawBottomBorder(
          color: p.border,
          child: TitleBarDoubleClick(
            chrome: chrome,
            child: LayoutBuilder(
              builder: (context, c) {
                // Shows the open item's name; the app name when nothing is open.
                // Hidden in narrow windows where the menus use the space.
                final where = [
                  if (col != null) col.name,
                  if (tab != null) tab.title,
                ].join('  ›  ');
                final title = where.isEmpty ? AppInfo.NAME : where;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Row(
                          spacing: 6,
                          children: [
                            if (chrome.leftInset > 0)
                              SizedBox(width: chrome.leftInset),
                            if (chrome.inlineMenus) ...[
                              Ico(Ic.logo, tint: p.accent, size: 16),
                              TitleMenus(
                                menus: AppMenus.build(
                                  state,
                                  isMac: false,
                                  quit: chrome.onQuit,
                                  minimize: chrome.onMinimize,
                                ),
                                tm: state.titleMenu,
                              ),
                            ],
                            const Spacer(),
                            if (chrome.controls != null) chrome.controls!,
                          ],
                        ),
                      ),
                    ),
                    if (!chrome.inlineMenus || c.maxWidth >= 1000)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: T(
                                title,
                                color: p.muted,
                                size: 12,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The header, as it always was: logo, name, collection, environments and the main actions.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = state.currentCollection;
    return Container(
      height: 44,
      color: p.panel,
      child: DrawBottomBorder(
        color: p.border,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 4,
            children: [
              Ico(Ic.logo, tint: p.accent, size: 24),
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: T('OpenRest', weight: FontWeight.w700, size: 15),
              ),
              if (col != null) ...[
                Clickable(
                  key: const ValueKey('top-collection'),
                  onClick: () => state.openCollectionTab(col.path),
                  cursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: T(
                      col.name,
                      color: p.muted,
                      size: 12,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              EnvSelector(state: state, collection: col),
              if (col != null) ...[
                _TopBtn(
                  label: 'Environments',
                  icon: Ic.environments,
                  onClick: () => state.modal = ModalEnvs(collection: col.path),
                ),
                _TopBtn(
                  label: 'Variables',
                  icon: Ic.variables,
                  onClick: () => state.modal = ModalVars(collection: col.path),
                ),
                _TopBtn(
                  label: 'Run',
                  icon: Ic.play,
                  onClick: () => state.openRunner(col.path, null),
                ),
              ],
              if (col == null)
                _TopBtn(
                  label: 'Environments',
                  icon: Ic.environments,
                  onClick: () => state.modal = const ModalEnvs(),
                ),
              _TopBtn(
                label: 'Cookies',
                icon: Ic.cookie,
                onClick: () => state.modal = const ModalCookies(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabStrip extends StatefulWidget {
  const _TabStrip({required this.state});
  final AppState state;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  // Dragging a tab swaps it with a neighbour once it crosses half the neighbour's width.
  final Map<int, GlobalKey> _keys = {};
  final Map<int, bool> _menu = {};
  int? dragId;
  double dragDx = 0;
  final ScrollController _scroll = ScrollController();

  // Last state the strip was scrolled for, so it only follows when the active tab or the tab count changes.
  int? _shownActiveId;
  int _shownTabCount = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the strip so the active tab is fully visible (after selecting, opening or closing a tab).
  void _revealActiveTab() {
    final id = state.activeTabId;
    final count = state.tabs.length;
    if (id == _shownActiveId && count == _shownTabCount) return;
    _shownActiveId = id;
    _shownTabCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabContext = _keys[id]?.currentContext;
      if (!mounted || tabContext == null || !_scroll.hasClients) return;
      final tab = tabContext.findRenderObject() as RenderBox?;
      final viewport =
          _scroll.position.context.notificationContext?.findRenderObject()
              as RenderBox?;
      if (tab == null || viewport == null || !tab.attached) return;
      // Tab edges in the strip's own coordinates; leave the scroll position alone while the tab is fully in view.
      final left = viewport.globalToLocal(tab.localToGlobal(Offset.zero)).dx;
      final right = left + tab.size.width;
      final double target;
      if (left < 0) {
        target = _scroll.offset + left;
      } else if (right > viewport.size.width) {
        target = _scroll.offset + right - viewport.size.width;
      } else {
        return;
      }
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  AppState get state => widget.state;

  double _width(int id) {
    final box = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size.width : 0;
  }

  void _drag(RequestTab t, double dx) {
    dragDx += dx;
    final i = state.tabs.indexWhere((x) => x.id == t.id);
    final ni = dragDx > 0 ? i + 1 : i - 1;
    if (ni < 0 || ni >= state.tabs.length) {
      setState(() {});
      return;
    }
    final next = state.tabs[ni];
    final w = _width(next.id);
    if (dragDx.abs() > w / 2) {
      state.moveTab(i, state.tabs.indexOf(next));
      dragDx -= dragDx > 0 ? w : -w;
    }
    setState(() {});
  }

  Widget _tab(BuildContext context, RequestTab t) {
    final p = context.pal;
    final sel = t.id == state.activeTabId;
    final key = _keys.putIfAbsent(t.id, () => GlobalKey());
    final menu = _menu[t.id] ?? false;
    final res = t.result?.response;
    return Transform.translate(
      offset: Offset(dragId == t.id ? dragDx : 0, 0),
      child: HoverBuilder(
        builder: (ctx, hov) => Listener(
          onPointerDown: (e) {
            if (e.buttons == kMiddleMouseButton) state.closeTab(t.id);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTap: () => setState(() => _menu[t.id] = true),
            // Only pointer drags reorder tabs; a trackpad swipe scrolls the strip.
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer
                    >(
                      () => HorizontalDragGestureRecognizer(
                        supportedDevices: const {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      (r) {
                        r.onStart = (_) {
                          setState(() {
                            dragId = t.id;
                            dragDx = 0;
                            state.activeTabId = t.id;
                          });
                        };
                        r.onUpdate = (d) => _drag(t, d.delta.dx);
                        r.onEnd = (_) {
                          setState(() {
                            dragId = null;
                            dragDx = 0;
                          });
                        };
                        r.onCancel = () {
                          setState(() {
                            dragId = null;
                            dragDx = 0;
                          });
                        };
                      },
                    ),
              },
              child: Clickable(
                onClick: () => state.activeTabId = t.id,
                cursor: SystemMouseCursors.click,
                child: Stack(
                  key: key,
                  children: [
                    Container(
                      height: 36,
                      constraints: const BoxConstraints(maxWidth: 220),
                      color: sel
                          ? p.bg
                          : (hov ? p.hover : const Color(0x00000000)),
                      foregroundDecoration: sel
                          ? BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: p.accent, width: 2),
                              ),
                            )
                          : null,
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          if (t.sending) const MiniSpinner(),
                          if (t.collection != null)
                            Ico(Ic.folder, tint: p.accent, size: 14)
                          else if (t.workflow != null)
                            Ico(
                              Ic.workflow,
                              tint: t.workflow!.running ? p.accent : p.muted,
                              size: 13,
                            )
                          else if (t.runner != null)
                            Ico(
                              Ic.play,
                              tint: t.runner!.running ? p.accent : p.muted,
                              size: 13,
                            )
                          else
                            T(
                              t.draft.displayMethod == 'DELETE'
                                  ? 'DEL'
                                  : t.draft.displayMethod,
                              color: methodColor(t.draft.displayMethod, p),
                              size: 10,
                              weight: FontWeight.w700,
                            ),
                          Flexible(
                            child: T(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              color: sel ? p.text : p.muted,
                            ),
                          ),
                          if (res != null && res.error == null)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor(res.status, p),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          if (t.dirty && !hov)
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Center(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: p.accent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            )
                          else
                            IconBtn(
                              icon: Ic.close,
                              onClick: () => state.closeTab(t.id),
                              size: 14,
                            ),
                        ],
                      ),
                    ),
                    ContextMenu(
                      open: menu,
                      onDismiss: () => setState(() => _menu[t.id] = false),
                      items: [
                        if (t.isRequest) ...[
                          MenuItem('Send', action: () => state.send(t)),
                          MenuItem('Save', action: () => state.save(t)),
                          MenuItem(
                            'Copy as cURL',
                            action: () => state.copyCurl(t),
                          ),
                          MenuItem(
                            'Generate Code…',
                            action: () =>
                                state.modal = ModalCodegen(tabId: t.id),
                          ),
                          const MenuItem(null),
                        ],
                        MenuItem('Close', action: () => state.closeTab(t.id)),
                        MenuItem(
                          'Close Others',
                          action: () => state.closeOthers(t.id),
                        ),
                        MenuItem(
                          'Close All Saved',
                          action: () => state.closeAll(),
                        ),
                        if (t.isRequest)
                          MenuItem(
                            Platform.revealLabel,
                            action: () => Platform.reveal(t.filePath),
                          ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    _revealActiveTab();
    return Container(
      color: p.panel,
      child: DrawBottomBorder(
        color: p.border,
        // A vertical mouse wheel scrolls the strip sideways.
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent &&
                e.scrollDelta.dx == 0 &&
                _scroll.hasClients) {
              final d = e.scrollDelta.dx != 0
                  ? e.scrollDelta.dx
                  : e.scrollDelta.dy;
              final pos = _scroll.position;
              _scroll.jumpTo((pos.pixels + d).clamp(0.0, pos.maxScrollExtent));
            }
          },
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in state.tabs.toList()) ...[
                  KeyedSubtree(key: ValueKey(t.id), child: _tab(context, t)),
                  Container(width: 1, height: 36, color: p.border),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: IconBtn(
                    icon: Ic.add,
                    onClick: () {
                      final c = state.currentCollection;
                      if (c != null) {
                        state.modal = ModalNewRequest(
                          collection: c.path,
                          dir: c.path,
                        );
                      }
                    },
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = state.currentCollection;
    final tab = state.activeTab;
    final env = col != null ? state.envName(col.path) : null;
    final res = tab?.result?.response;
    Widget click(VoidCallback f, Widget child) =>
        Clickable(onClick: f, cursor: SystemMouseCursors.click, child: child);
    return Container(
      height: 24,
      color: p.panel,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      // The 1px line is painted and takes no layout space.
      child: CustomPaint(
        painter: _TopBorderPainter(p.border),
        child: Row(
          spacing: 14,
          children: [
            Row(
              spacing: 2,
              children: [
                IconBtn(
                  icon: Ic.sidebar,
                  onClick: () => state.sidebarVisible = !state.sidebarVisible,
                  color: state.sidebarVisible ? p.accent : p.muted,
                  size: 15,
                ),
                IconBtn(
                  icon: Ic.settings,
                  onClick: () => state.modal = const ModalSettings(),
                  color: p.muted,
                  size: 15,
                ),
                IconBtn(
                  icon: Ic.gitHub,
                  onClick: () => state.modal = const ModalDeveloper(),
                  color: p.muted,
                  size: 15,
                ),
              ],
            ),
            if (col != null) ...[
              T(col.name, size: 11, color: p.muted, maxLines: 1),
              click(
                () => state.modal = ModalEnvs(collection: col.path),
                Row(
                  spacing: 4,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: env != null ? p.ok : p.muted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    T(
                      env ?? 'no environment',
                      size: 11,
                      color: env != null ? p.text : p.muted,
                    ),
                  ],
                ),
              ),
              if (state.globalEnvName() != null)
                click(
                  () => state.modal = const ModalEnvs(),
                  Row(
                    spacing: 4,
                    children: [
                      T('global:', size: 11, color: p.muted),
                      T(state.globalEnvName()!, size: 11, color: p.text),
                    ],
                  ),
                ),
              Builder(
                builder: (context) {
                  final rt = state.runtime(col.path).length;
                  if (rt <= 0) return const SizedBox.shrink();
                  return Clickable(
                    onClick: () =>
                        state.modal = ModalVars(collection: col.path),
                    child: T(
                      '$rt runtime var${rt == 1 ? '' : 's'}',
                      size: 11,
                      color: p.muted,
                    ),
                  );
                },
              ),
            ],
            const Spacer(),
            if (tab?.sending == true)
              T('sending…', size: 11, color: p.accent)
            else if (res != null && res.error == null)
              T(
                '${res.status} · ${res.timeMs} ms',
                size: 11,
                color: statusColor(res.status, p),
              )
            else if (tab?.result?.error != null)
              T('error', size: 11, color: p.err),
            if (tab != null && tab.dirty)
              T('unsaved', size: 11, color: p.accent),
            click(
              () => state.modal = const ModalPalette(),
              Row(
                spacing: 4,
                children: [
                  T('⌘K', size: 11, color: p.accent, mono: true),
                  T('commands', size: 11, color: p.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBorderPainter extends CustomPainter {
  _TopBorderPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    const Offset(0, 0.5),
    Offset(size.width, 0.5),
    Paint()
      ..color = color
      ..strokeWidth = 1,
  );
  @override
  bool shouldRepaint(_TopBorderPainter o) => o.color != color;
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const tips = <(String, String)>[
      ('⌘/Ctrl + K', 'Command palette: jump to any request or action'),
      ('⌘/Ctrl + Enter', 'Send request'),
      ('⌘/Ctrl + S', 'Save request'),
      ('⌘/Ctrl + L', 'Focus URL bar'),
      ('⌘/Ctrl + B', 'Toggle sidebar'),
      ('⌘/Ctrl + 1…9', 'Switch tab'),
      ('⌘/Ctrl + Shift + C', 'Copy as cURL'),
      ('⌘/Ctrl + N', 'New request'),
      ('⌘/Ctrl + + / − / 0', 'Zoom UI'),
    ];
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Ico(Ic.logo, tint: p.accent, size: 56),
              const T('OpenRest', size: 28, weight: FontWeight.w700),
              const SizedBox(height: 4),
              T(
                'Open-source API client — collections are plain files on disk.',
                color: p.muted,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Btn(
                    label: 'New Collection',
                    onClick: () => state.modal = const ModalNewCollection(),
                    primary: true,
                    icon: Ic.newFolder,
                  ),
                  Btn(
                    label: 'Open Collection',
                    onClick: () => state.modal = const ModalOpenCollection(),
                    icon: Ic.folderOpen,
                  ),
                  Btn(
                    label: 'Import',
                    onClick: () => state.modal = const ModalImport(),
                    icon: Ic.import,
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  for (final t in tips)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: [
                        SizedBox(
                          width: 160,
                          child: T(t.$1, mono: true, color: p.accent, size: 12),
                        ),
                        T(t.$2, color: p.muted, size: 12),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
