// ignore_for_file: constant_identifier_names, non_constant_identifier_names, deprecated_member_use
import 'package:open_rest/components/modifiers.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/context_menu.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_model.dart' show Workflow;
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// A row of the sidebar's flattened tree.
sealed class SRow {
  const SRow();
}

/// Tree row for a collection root.
class SRowCol extends SRow {
  const SRowCol(this.c);
  final Collection c;
}

/// Tree row for a folder.
class SRowFolder extends SRow {
  const SRowFolder(this.col, this.f, this.depth, this.siblings, this.index);
  final String col;
  final FolderNode f;
  final int depth;
  final List<Node> siblings;
  final int index;
}

/// Tree row for a request.
class SRowReq extends SRow {
  const SRowReq(this.col, this.r, this.depth, this.siblings, this.index);
  final String col;
  final RequestNode r;
  final int depth;
  final List<Node> siblings;
  final int index;
}

/// Tree row for a workflow.
class SRowWf extends SRow {
  const SRowWf(this.col, this.w);
  final String col;
  final Workflow w;
}

List<SRow> buildRows(AppState state) {
  final f = state.sidebarFilter.trim().toLowerCase();
  final out = <SRow>[];
  bool matches(Node n) => switch (n) {
    RequestNode() =>
      n.name.toLowerCase().contains(f) ||
          n.request.url.toLowerCase().contains(f),
    FolderNode() => n.children.any(matches),
  };
  void walk(String col, List<Node> nodes, int depth) {
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (f.isNotEmpty && !matches(n)) continue;
      switch (n) {
        case FolderNode():
          out.add(SRowFolder(col, n, depth, nodes, i));
          if (f.isNotEmpty || state.expanded[n.path] == true) {
            walk(col, n.children, depth + 1);
          }
        case RequestNode():
          out.add(SRowReq(col, n, depth, nodes, i));
      }
    }
  }

  for (final c in state.collections) {
    out.add(SRowCol(c));
    if (f.isNotEmpty || state.expanded[c.path] == true) {
      walk(c.path, c.children, 1);
      for (final w in c.workflows.where(
        (w) => f.isEmpty || w.name.toLowerCase().contains(f),
      )) {
        out.add(SRowWf(c.path, w));
      }
    }
  }
  return out;
}

int countReqs(List<Node> nodes) => nodes.fold(
  0,
  (a, n) => a + (n is RequestNode ? 1 : countReqs((n as FolderNode).children)),
);

/// Where a dragged item lands relative to the drop target.
enum DropMode { INTO, BEFORE, AFTER }

/// State of an in-progress drag in the sidebar tree.
class DragCtx {
  const DragCtx({
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.mode,
    required this.dragging,
  });
  final VoidCallback onStart;
  final void Function(double) onMove;
  final VoidCallback onEnd;
  final DropMode? mode;
  final bool dragging;

  static DragCtx none() => DragCtx(
    onStart: () {},
    onMove: (_) {},
    onEnd: () {},
    mode: null,
    dragging: false,
  );
}

/// `LocalTreeNav`: moves the keyboard cursor to a row (and focuses the tree).
class LocalTreeNav extends InheritedWidget {
  const LocalTreeNav({super.key, required this.nav, required super.child});
  final void Function(String) nav;

  static void Function(String) of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LocalTreeNav>()?.nav ?? (_) {};

  @override
  bool updateShouldNotify(LocalTreeNav old) => false;
}

String rowKey(SRow r) => switch (r) {
  SRowCol() => 'c:${r.c.path}',
  SRowFolder() => 'f:${r.f.path}',
  SRowReq() => 'r:${r.r.path}',
  SRowWf() => 'w:${r.col}|${r.w.name}',
};

/// Height of a row in the tree (collections are taller).
double rowHeight(SRow r) => r is SRowCol ? 34 : 30;

/// 11dp accent progress ring used for "sending" / "running" indicators.
class MiniSpinner extends StatelessWidget {
  const MiniSpinner({super.key, this.size = 11});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CircularProgressIndicator(
      color: context.pal.accent,
      strokeWidth: 1.5,
    ),
  );
}

class _RowPainter extends CustomPainter {
  _RowPainter({
    required this.p,
    required this.depth,
    required this.selected,
    required this.cursor,
    required this.mode,
  });
  final Pal p;
  final int depth;
  final bool selected;
  final bool cursor;
  final DropMode? mode;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < depth; i++) {
      final x = (15 + i * 14).toDouble();
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = p.border.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
    }
    if (selected) {
      // Sits on the indentation guide of the parent level.
      final gx = depth > 0 ? (15 + (depth - 1) * 14).toDouble() : 1.25;
      canvas.drawRect(
        Rect.fromLTWH(gx - 1.25, 0, 2.5, size.height),
        Paint()..color = p.accent,
      );
    }
    if (cursor && !selected) {
      canvas.drawRect(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        Paint()
          ..color = p.accent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    switch (mode) {
      case DropMode.INTO:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = p.accent.withValues(alpha: 0.18),
        );
        canvas.drawRect(
          Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
          Paint()
            ..color = p.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case DropMode.BEFORE:
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, 2),
          Paint()..color = p.accent,
        );
      case DropMode.AFTER:
        canvas.drawRect(
          Rect.fromLTWH(0, size.height - 2, size.width, 2),
          Paint()..color = p.accent,
        );
      case null:
        break;
    }
  }

  @override
  bool shouldRepaint(_RowPainter o) =>
      o.p != p ||
      o.depth != depth ||
      o.selected != selected ||
      o.cursor != cursor ||
      o.mode != mode;
}

/// Single draggable row of the sidebar tree.
class TreeRow extends StatefulWidget {
  const TreeRow({
    super.key,
    required this.rowKey,
    required this.depth,
    required this.selected,
    required this.onClick,
    required this.items,
    required this.drag,
    required this.cursor,
    this.height = 30,
    this.quickAdd,
    required this.content,
  });

  final String rowKey;
  final int depth;
  final bool selected;
  final VoidCallback onClick;
  final List<MenuItem> items;
  final DragCtx drag;
  final bool cursor;
  final double height;
  final VoidCallback? quickAdd;

  /// Row content; the argument says whether the row is hovered (or its menu open).
  final List<Widget> Function(bool hovered) content;

  @override
  State<TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<TreeRow> {
  bool menu = false;
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final nav = LocalTreeNav.of(context);
    final w = widget;
    final bg = w.selected
        ? p.selected
        : (hovered ? p.hover : const Color(0x00000000));
    final show = hovered || menu;
    return Stack(
      children: [
        Opacity(
          opacity: w.drag.dragging ? 0.4 : 1,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hovered = true),
            onExit: (_) => setState(() => hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => w.drag.onStart(),
              onPanUpdate: (d) => w.drag.onMove(d.delta.dy),
              onPanEnd: (_) => w.drag.onEnd(),
              onPanCancel: () => w.drag.onEnd(),
              onSecondaryTap: () {
                nav(w.rowKey);
                setState(() => menu = true);
              },
              child: Clickable(
                onClick: () {
                  nav(w.rowKey);
                  w.onClick();
                },
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  height: w.height,
                  color: bg,
                  child: CustomPaint(
                    painter: _RowPainter(
                      p: p,
                      depth: w.depth,
                      selected: w.selected,
                      cursor: w.cursor,
                      mode: w.drag.mode,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: (8 + w.depth * 14).toDouble(),
                        right: 4,
                      ),
                      child: Row(
                        spacing: 6,
                        children: [
                          ...w.content(show),
                          if (show && w.quickAdd != null)
                            IconBtn(
                              icon: Ic.add,
                              onClick: w.quickAdd!,
                              size: 15,
                            ),
                          if (show)
                            IconBtn(
                              icon: Ic.more,
                              onClick: () => setState(() => menu = true),
                              size: 15,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: SizedBox(
            width: 0,
            height: 0,
            child: ContextMenu(
              open: menu,
              onDismiss: () => setState(() => menu = false),
              items: w.items,
            ),
          ),
        ),
      ],
    );
  }
}
