import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/context_menu.dart';
import 'package:open_rest/components/inline_rename.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/features/sidebar/tree.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/core/model/model.dart';

Widget _dot(Color c) => Container(
  width: 7,
  height: 7,
  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
);

/// Collection header row with its context menu.
class CollectionRow extends StatelessWidget {
  const CollectionRow({
    super.key,
    required this.state,
    required this.c,
    required this.drag,
    required this.cursor,
  });
  final AppState state;
  final Collection c;
  final DragCtx drag;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final key = c.path;
    final open = state.expanded[key] == true;
    final env = state.envName(c.path);
    return TreeRow(
      rowKey: 'c:${c.path}',
      depth: 0,
      selected: false,
      onClick: () {
        state.expanded[key] = !open;
        state.selectedCollection = c.path;
      },
      items: [
        MenuItem(
          'New Request',
          action: () =>
              state.modal = ModalNewRequest(collection: c.path, dir: c.path),
        ),
        MenuItem(
          'New Folder',
          action: () => state.promptNewFolder(c.path, c.path),
        ),
        MenuItem('New Workflow', action: () => state.promptNewWorkflow(c.path)),
        const MenuItem(null),
        MenuItem(
          'Run Collection',
          action: () => state.openRunner(c.path, null),
        ),
        MenuItem(
          'Environments',
          action: () => state.modal = ModalEnvs(collection: c.path),
        ),
        MenuItem(
          'Overview / Settings',
          action: () => state.openCollectionTab(c.path),
        ),
        MenuItem(
          'Variables',
          action: () => state.modal = ModalVars(collection: c.path),
        ),
        const MenuItem(null),
        MenuItem('Rename', action: () => state.promptRename(c.path, null)),
        MenuItem(
          'Export…',
          action: () => state.modal = ModalExport(collection: c.path),
        ),
        MenuItem(Platform.revealLabel, action: () => Platform.reveal(c.path)),
        MenuItem('Reload', action: () => state.reload(c.path)),
        MenuItem(
          'Close Collection',
          danger: true,
          action: () => state.closeCollection(c.path),
        ),
      ],
      drag: drag,
      cursor: cursor,
      height: 34,
      quickAdd: () =>
          state.modal = ModalNewRequest(collection: c.path, dir: c.path),
      content: (hovered) => [
        Chevron(open: open),
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
            textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            style: TextStyle(
              color: p.accent,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: bodyLetterSpacing,
              leadingDistribution: TextLeadingDistribution.even,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        Expanded(
          child: T(
            c.name,
            weight: FontWeight.w600,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hovered)
          IconBtn(
            key: ValueKey('overview:${c.path}'),
            icon: Ic.info,
            size: 15,
            onClick: () => state.openCollectionTab(c.path),
          ),
        if (!hovered) ...[
          if (env != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: p.ok.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: T(env, color: p.ok, size: 10, maxLines: 1),
            ),
          T(countReqs(c.children).toString(), color: p.muted, size: 11),
        ],
      ],
    );
  }
}

/// Folder row with its context menu.
class FolderRow extends StatelessWidget {
  const FolderRow({
    super.key,
    required this.state,
    required this.row,
    required this.drag,
    required this.cursor,
  });
  final AppState state;
  final SRowFolder row;
  final DragCtx drag;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = row.f;
    final key = f.path;
    final open =
        state.expanded[key] == true || state.sidebarFilter.trim().isNotEmpty;
    return TreeRow(
      rowKey: 'f:${f.path}',
      depth: row.depth,
      selected: false,
      onClick: () => state.expanded[key] = !(state.expanded[key] == true),
      items: [
        MenuItem(
          'New Request',
          action: () =>
              state.modal = ModalNewRequest(collection: row.col, dir: f.path),
        ),
        MenuItem(
          'New Folder',
          action: () => state.promptNewFolder(row.col, f.path),
        ),
        const MenuItem(null),
        MenuItem('Run Folder', action: () => state.openRunner(row.col, f.path)),
        MenuItem(
          'Settings',
          action: () => state.modal = ModalNodeSettings(
            collection: row.col,
            node: f.path,
          ),
        ),
        const MenuItem(null),
        MenuItem('Rename', action: () => state.promptRename(row.col, f)),
        MenuItem('Clone', action: () => state.promptClone(row.col, f)),
        MenuItem(Platform.revealLabel, action: () => Platform.reveal(f.path)),
        MenuItem(
          'Delete',
          danger: true,
          action: () => state.promptDelete(row.col, f),
        ),
      ],
      drag: drag,
      cursor: cursor,
      quickAdd: () =>
          state.modal = ModalNewRequest(collection: row.col, dir: f.path),
      content: (hovered) => [
        Chevron(open: open),
        FolderIcon(open: open),
        if (state.renaming == f.path)
          Expanded(
            child: InlineRename(
              initial: f.name,
              onDone: (n) {
                state.renaming = null;
                if (n != null && n != f.name) state.renameNode(row.col, f, n);
              },
            ),
          )
        else
          Expanded(
            child: T(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        if (!hovered)
          T(countReqs(f.children).toString(), color: p.muted, size: 11),
      ],
    );
  }
}

/// Workflow row with its context menu.
class WorkflowRow extends StatelessWidget {
  const WorkflowRow({
    super.key,
    required this.state,
    required this.row,
    required this.cursor,
  });
  final AppState state;
  final SRowWf row;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tab = state.workflowTab(row.col, row.w.name);
    return TreeRow(
      rowKey: 'w:${row.col}|${row.w.name}',
      depth: 1,
      selected: state.activeTab != null && identical(state.activeTab, tab),
      onClick: () => state.openWorkflow(row.col, row.w.name),
      items: [
        MenuItem('Open', action: () => state.openWorkflow(row.col, row.w.name)),
        MenuItem(
          'Run',
          action: () {
            state.openWorkflow(row.col, row.w.name);
            final t = state.workflowTab(row.col, row.w.name);
            if (t != null) state.runWorkflow(t);
          },
        ),
        const MenuItem(null),
        MenuItem(
          'Rename',
          action: () => state.promptRenameWorkflow(row.col, row.w.name),
        ),
        MenuItem(
          'Clone',
          action: () => state.cloneWorkflow(row.col, row.w.name),
        ),
        MenuItem(
          'Delete',
          danger: true,
          action: () => state.promptDeleteWorkflow(row.col, row.w.name),
        ),
      ],
      drag: DragCtx.none(),
      cursor: cursor,
      content: (_) => [
        const SizedBox(width: 6),
        SizedBox(
          width: METHOD_SLOT,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Ico(Ic.workflow, tint: p.accent, size: 15),
          ),
        ),
        Expanded(
          child: T(row.w.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (tab?.workflow?.running == true)
          const MiniSpinner()
        else if (tab?.dirty == true)
          _dot(p.accent),
      ],
    );
  }
}

/// Request row with its context menu.
class RequestRow extends StatelessWidget {
  const RequestRow({
    super.key,
    required this.state,
    required this.row,
    required this.drag,
    required this.cursor,
  });
  final AppState state;
  final SRowReq row;
  final DragCtx drag;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = row.r;
    final reqs = row.siblings.whereType<RequestNode>().toList();
    final ri = reqs.indexOf(r);
    RequestTab? tab;
    for (final t in state.tabs) {
      if (t.filePath == r.path) {
        tab = t;
        break;
      }
    }
    final raw = <MenuItem>[
      MenuItem('Open', action: () => state.openRequest(row.col, r)),
      MenuItem('Rename', action: () => state.promptRename(row.col, r)),
      MenuItem('Clone', action: () => state.promptClone(row.col, r)),
      if (ri > 0)
        MenuItem(
          'Move Up',
          action: () => state.move(row.col, row.siblings, row.index, -1),
        )
      else
        const MenuItem(null),
      if (ri >= 0 && ri < reqs.length - 1)
        MenuItem(
          'Move Down',
          action: () => state.move(row.col, row.siblings, row.index, 1),
        )
      else
        const MenuItem(null),
      MenuItem(Platform.revealLabel, action: () => Platform.reveal(r.path)),
      MenuItem(
        'Delete',
        danger: true,
        action: () => state.promptDelete(row.col, r),
      ),
    ];
    final items = <MenuItem>[
      for (var i = 0; i < raw.length; i++)
        if (!(raw[i].label == null && (i == 0 || raw[i - 1].label == null)))
          raw[i],
    ];
    return TreeRow(
      rowKey: 'r:${r.path}',
      depth: row.depth,
      selected: state.activeTab?.filePath == r.path,
      onClick: () => state.openRequest(row.col, r),
      items: items,
      drag: drag,
      cursor: cursor,
      content: (hovered) {
        final t = tab;
        return [
          const SizedBox(width: 6),
          MethodPill(r.request.displayMethod),
          if (state.renaming == r.path)
            Expanded(
              child: InlineRename(
                initial: r.name,
                onDone: (n) {
                  state.renaming = null;
                  if (n != null && n != r.name) state.renameNode(row.col, r, n);
                },
              ),
            )
          else
            Expanded(
              child: T(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (!hovered && t != null) ...[
            if (t.sending)
              const MiniSpinner()
            else if (t.dirty)
              _dot(p.accent)
            else if (t.result?.response != null &&
                t.result!.response!.error == null)
              _dot(statusColor(t.result!.response!.status, p)),
            const SizedBox(width: 2),
          ],
        ];
      },
    );
  }
}
