import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart'
    show
        Scrollbar,
        ScrollbarTheme,
        ScrollbarThemeData,
        WidgetState,
        WidgetStateProperty,
        WidgetStatePropertyAll;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/sidebar/history.dart';
import 'package:open_rest/features/sidebar/rows.dart';
import 'package:open_rest/features/sidebar/tree.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.icon,
    required this.selected,
    this.badge,
    required this.onClick,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final String? badge;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Clickable(
      onClick: onClick,
      cursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? p.panel : const Color(0x00000000),
          borderRadius: BorderRadius.circular(6),
        ),
        // Borders are painted over the content so they take no layout space.
        foregroundDecoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.border, width: 1),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Ico(icon, tint: selected ? p.accent : p.muted, size: 15),
            const SizedBox(width: 6),
            T(
              label,
              color: selected ? p.text : p.muted,
              size: 12,
              weight: selected ? FontWeight.w600 : null,
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: T(
                  badge!,
                  color: p.accent,
                  size: 10,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Left pane with the collection tree, history and search.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.state});
  final AppState state;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final FocusNode fr = FocusNode();
  final ScrollController scroll = ScrollController();
  String? dragKey;
  (int, DropMode)? drop;
  double startMid = 0;
  double acc = 0;
  List<SRow> rows = const [];
  String? _lastCursor;

  AppState get state => widget.state;

  @override
  void dispose() {
    fr.dispose();
    scroll.dispose();
    super.dispose();
  }

  /// y offset (inside the scrollable content) of each row; the list has 4dp vertical padding.
  List<double> _offsets() {
    final out = <double>[];
    var y = 4.0;
    for (final r in rows) {
      out.add(y);
      y += rowHeight(r);
    }
    return out;
  }

  void performDrop() {
    final list = rows;
    SRow? src;
    for (final r in list) {
      if (rowKey(r) == dragKey) src = r;
    }
    final d = drop;
    final tgt = d != null && d.$1 >= 0 && d.$1 < list.length
        ? list[d.$1]
        : null;
    if (src == null ||
        tgt == null ||
        src is SRowCol ||
        src is SRowWf ||
        tgt is SRowWf) {
      return;
    }
    String srcCol;
    Node srcNode;
    switch (src) {
      case SRowReq():
        srcCol = src.col;
        srcNode = src.r;
      case SRowFolder():
        srcCol = src.col;
        srcNode = src.f;
      default:
        return;
    }
    final String tgtCol = switch (tgt) {
      SRowCol() => tgt.c.path,
      SRowFolder() => tgt.col,
      SRowReq() => tgt.col,
      SRowWf() => '',
    };
    if (tgtCol != srcCol) {
      state.showToast("Can't move between collections");
      return;
    }
    switch (tgt) {
      case SRowWf():
        break;
      case SRowCol():
        state.moveNode(srcCol, srcNode.path, tgt.c.path);
      case SRowFolder():
        if (!tgt.f.path.startsWith(srcNode.path)) {
          state.moveNode(srcCol, srcNode.path, tgt.f.path);
        }
      case SRowReq():
        if (tgt.r.path != srcNode.path) {
          if (srcNode is RequestNode) {
            state.dropRequest(srcCol, srcNode, tgt.r, d!.$2 == DropMode.AFTER);
          } else if (!_parent(tgt.r.path).startsWith(srcNode.path)) {
            state.moveNode(srcCol, srcNode.path, _parent(tgt.r.path));
          }
        }
    }
  }

  String _parent(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? path : path.substring(0, i);
  }

  DragCtx dragCtx(int index, SRow row) {
    final key = rowKey(row);
    return DragCtx(
      onStart: () {
        if (row is! SRowCol) {
          final off = _offsets();
          setState(() {
            dragKey = key;
            startMid = off[index] + rowHeight(row) / 2;
            acc = 0;
          });
        }
      },
      onMove: (dy) {
        if (dragKey != null) {
          acc += dy;
          final y = startMid + acc;
          final off = _offsets();
          int? hit;
          for (var i = 0; i < rows.length; i++) {
            if (y >= off[i] && y < off[i] + rowHeight(rows[i])) hit = i;
          }
          setState(() {
            drop = hit == null
                ? null
                : (
                    hit,
                    rows[hit] is SRowReq
                        ? ((y - off[hit]) / rowHeight(rows[hit]) < 0.5
                              ? DropMode.BEFORE
                              : DropMode.AFTER)
                        : DropMode.INTO,
                  );
          });
        }
      },
      onEnd: () {
        if (dragKey != null) performDrop();
        setState(() {
          dragKey = null;
          drop = null;
        });
      },
      mode: dragKey != null && drop != null && drop!.$1 == index
          ? drop!.$2
          : null,
      dragging: dragKey == key,
    );
  }

  void toggle(SRow r, bool open) {
    final String k;
    if (r is SRowCol) {
      k = r.c.path;
    } else if (r is SRowFolder) {
      k = r.f.path;
    } else {
      return;
    }
    state.expanded[k] = open;
  }

  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (!fr.hasPrimaryFocus ||
        state.sidebarTab != 'Collections' ||
        state.renaming != null) {
      return KeyEventResult.ignored;
    }
    final keys = rows.map(rowKey).toList();
    final k = e.logicalKey;
    if (const [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.f2,
    ].contains(k)) {
      state.cursorVisible = true;
    }
    final i = state.cursor == null ? -1 : keys.indexOf(state.cursor!);
    final SRow? cur = i >= 0 && i < rows.length ? rows[i] : null;
    String? at(int j) => j >= 0 && j < keys.length ? keys[j] : null;
    bool isOpen(SRow r) =>
        state.expanded[r is SRowCol ? r.c.path : (r as SRowFolder).f.path] ==
        true;

    if (k == LogicalKeyboardKey.arrowDown) {
      state.cursor = at(i + 1) ?? (keys.isEmpty ? null : keys.first);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      state.cursor = at(i - 1) ?? (keys.isEmpty ? null : keys.last);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (cur != null && cur is! SRowReq && cur is! SRowWf) {
        if (!isOpen(cur)) {
          toggle(cur, true);
        } else {
          state.cursor = at(i + 1);
        }
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (cur != null && cur is! SRowReq && cur is! SRowWf && isOpen(cur)) {
        toggle(cur, false);
      } else if (cur != null) {
        final depth = switch (cur) {
          SRowCol() => 0,
          SRowFolder() => cur.depth,
          SRowReq() => cur.depth,
          SRowWf() => 1,
        };
        int? parent;
        for (var j = i - 1; j >= 0; j--) {
          final r = rows[j];
          final d = r is SRowCol ? 0 : (r is SRowFolder ? r.depth : 1 << 30);
          if (d < depth) {
            parent = j;
            break;
          }
        }
        if (parent != null) state.cursor = keys[parent];
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      switch (cur) {
        case SRowReq():
          state.openRequest(cur.col, cur.r);
        case SRowWf():
          state.openWorkflow(cur.col, cur.w.name);
        case SRowFolder():
          state.expanded[cur.f.path] = state.expanded[cur.f.path] != true;
        case SRowCol():
          state.expanded[cur.c.path] = state.expanded[cur.c.path] != true;
        case null:
          break;
      }
      return cur != null ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.f2) {
      switch (cur) {
        case SRowReq():
          state.renaming = cur.r.path;
        case SRowFolder():
          state.renaming = cur.f.path;
        case SRowCol():
          state.promptRename(cur.c.path, null);
        case SRowWf():
          state.promptRenameWorkflow(cur.col, cur.w.name);
        case null:
          break;
      }
      return cur != null ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      switch (cur) {
        case SRowReq():
          state.promptDelete(cur.col, cur.r);
        case SRowFolder():
          state.promptDelete(cur.col, cur.f);
        case SRowWf():
          state.promptDeleteWorkflow(cur.col, cur.w.name);
        default:
          break;
      }
      return cur != null && cur is! SRowCol
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    rows = buildRows(state);
    final cursorKey = state.cursor;
    if (cursorKey != _lastCursor) {
      _lastCursor = cursorKey;
      final i = rows.indexWhere((r) => rowKey(r) == cursorKey);
      if (i >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          final top = _offsets()[i];
          final bottom = top + rowHeight(rows[i]);
          final vp = scroll.position.viewportDimension;
          if (top < scroll.offset) {
            scroll.jumpTo(
              (top - 60).clamp(0.0, scroll.position.maxScrollExtent),
            );
          } else if (bottom > scroll.offset + vp) {
            scroll.jumpTo(
              (bottom - vp + 60).clamp(0.0, scroll.position.maxScrollExtent),
            );
          }
        });
      }
    }

    return LocalTreeNav(
      nav: (k) {
        state.cursor = k;
        state.cursorVisible = false;
        fr.requestFocus();
      },
      child: Focus(
        focusNode: fr,
        onKeyEvent: onKey,
        child: Container(
          color: p.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    spacing: 3,
                    children: [
                      Expanded(
                        child: _SegTab(
                          label: 'Collections',
                          icon: Ic.folder,
                          selected: state.sidebarTab == 'Collections',
                          onClick: () => state.sidebarTab = 'Collections',
                        ),
                      ),
                      Expanded(
                        child: _SegTab(
                          label: 'History',
                          icon: Ic.history,
                          selected: state.sidebarTab == 'History',
                          badge: state.history.isNotEmpty
                              ? state.history.length.toString()
                              : null,
                          onClick: () => state.sidebarTab = 'History',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.sidebarTab == 'History')
                HistoryView(state: state)
              else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 6, bottom: 8),
                  child: Row(
                    spacing: 2,
                    children: [
                      Expanded(
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: p.field,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: p.border, width: 1),
                          ),
                          child: Row(
                            children: [
                              Ico(Ic.search, tint: p.muted, size: 15),
                              Expanded(
                                child: Field(
                                  value: state.sidebarFilter,
                                  onChange: (v) => state.sidebarFilter = v,
                                  placeholder: 'Filter requests…',
                                  bordered: false,
                                  highlightVars: false,
                                ),
                              ),
                              if (state.sidebarFilter.isNotEmpty)
                                IconBtn(
                                  icon: Ic.close,
                                  onClick: () => state.sidebarFilter = '',
                                  size: 13,
                                ),
                            ],
                          ),
                        ),
                      ),
                      IconBtn(
                        icon: Ic.collapseAll,
                        onClick: () => state.collapseAll(),
                        size: 17,
                      ),
                      IconBtn(
                        icon: Ic.refresh,
                        onClick: () {
                          state.reloadAll();
                          state.showToast('Collections reloaded');
                        },
                        size: 17,
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: p.border),
                if (state.collections.isEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Ico(
                            Ic.folder,
                            tint: p.muted.withValues(alpha: 0.5),
                            size: 44,
                          ),
                          const SizedBox(height: 10),
                          const T(
                            'No collections yet',
                            weight: FontWeight.w600,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: DefaultTextStyle.merge(
                              textWidthBasis: TextWidthBasis.longestLine,
                              child: T(
                                'Create one, open a folder, or import from Postman, Bruno or OpenAPI.',
                                color: p.muted,
                                size: 12,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: Btn(
                              label: 'New Collection',
                              onClick: () =>
                                  state.modal = const ModalNewCollection(),
                              primary: true,
                              icon: Ic.newFolder,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: Btn(
                              label: 'Open Collection',
                              onClick: () =>
                                  state.modal = const ModalOpenCollection(),
                              icon: Ic.folderOpen,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: Btn(
                              label: 'Import',
                              onClick: () => state.modal = const ModalImport(),
                              icon: Ic.import,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Stack(
                      children: [
                        if (rows.isEmpty ||
                            (state.sidebarFilter.trim().isNotEmpty &&
                                rows.every((r) => r is SRowCol)))
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: T(
                              'No requests match “${state.sidebarFilter}”',
                              color: p.muted,
                              size: 12,
                            ),
                          ),
                        ScrollbarTheme(
                          // Scrollbar is 8px wide and always visible.
                          data: ScrollbarThemeData(
                            thumbVisibility: const WidgetStatePropertyAll(true),
                            thickness: const WidgetStatePropertyAll(8),
                            radius: const Radius.circular(4),
                            minThumbLength: 16,
                            thumbColor: WidgetStateProperty.resolveWith(
                              (s) => const Color(0xFF000000).withValues(
                                alpha: s.contains(WidgetState.hovered)
                                    ? 0.5
                                    : 0.12,
                              ),
                            ),
                          ),
                          child: Scrollbar(
                            controller: scroll,
                            child: ListView.builder(
                              controller: scroll,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: rows.length,
                              itemExtentBuilder: (i, _) => rowHeight(rows[i]),
                              itemBuilder: (ctx, index) {
                                final row = rows[index];
                                final cursor =
                                    state.cursorVisible &&
                                    state.cursor == rowKey(row);
                                final key = ValueKey(rowKey(row));
                                return switch (row) {
                                  SRowCol() => CollectionRow(
                                    key: key,
                                    state: state,
                                    c: row.c,
                                    drag: dragCtx(index, row),
                                    cursor: cursor,
                                  ),
                                  SRowFolder() => FolderRow(
                                    key: key,
                                    state: state,
                                    row: row,
                                    drag: dragCtx(index, row),
                                    cursor: cursor,
                                  ),
                                  SRowReq() => RequestRow(
                                    key: key,
                                    state: state,
                                    row: row,
                                    drag: dragCtx(index, row),
                                    cursor: cursor,
                                  ),
                                  SRowWf() => WorkflowRow(
                                    key: key,
                                    state: state,
                                    row: row,
                                    cursor: cursor,
                                  ),
                                };
                              },
                            ),
                          ),
                        ),
                        if (dragKey != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: p.panel,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                foregroundDecoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: p.border, width: 1),
                                ),
                                child: T(
                                  'Drop on a folder to move · between requests to reorder',
                                  color: p.muted,
                                  size: 11,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  // The line is painted and takes no layout space.
                  foregroundDecoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.border, width: 1)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  child: Row(
                    spacing: 2,
                    children: [
                      Expanded(
                        child: _FooterBtn(
                          label: 'New',
                          icon: Ic.newFolder,
                          onClick: () =>
                              state.modal = const ModalNewCollection(),
                        ),
                      ),
                      Expanded(
                        child: _FooterBtn(
                          label: 'Open',
                          icon: Ic.folderOpen,
                          onClick: () =>
                              state.modal = const ModalOpenCollection(),
                        ),
                      ),
                      Expanded(
                        child: _FooterBtn(
                          label: 'Import',
                          icon: Ic.import,
                          onClick: () => state.modal = const ModalImport(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterBtn extends StatelessWidget {
  const _FooterBtn({
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
      borderRadius: BorderRadius.circular(6),
      cursor: SystemMouseCursors.click,
      onTap: onClick,
      builder: (ctx, hov) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: hov ? p.hover : const Color(0x00000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Ico(icon, tint: hov ? p.accent : p.muted, size: 15),
            const SizedBox(width: 5),
            T(label, color: hov ? p.text : p.muted, size: 12),
          ],
        ),
      ),
    );
  }
}
