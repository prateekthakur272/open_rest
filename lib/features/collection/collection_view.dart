import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/markdown_view.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/features/dialogs/node_settings_view.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as path;

/// Pages of a collection tab, in order; [NodeSection.general] is the overview.
const collectionPages = [
  NodeSection.general,
  NodeSection.headers,
  NodeSection.auth,
  NodeSection.variables,
  NodeSection.scripts,
  NodeSection.tests,
  NodeSection.tls,
];

/// Tab label of a collection page.
String collectionPageLabel(NodeSection s) => switch (s) {
  NodeSection.general => 'Overview',
  NodeSection.tls => 'TLS',
  _ => s.label,
};

const _gap = 16.0;

/// Flat card surface, the same as the runner's summary tiles.
BoxDecoration _surface(Pal p) => BoxDecoration(
  color: p.bg,
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: p.border),
);
const _pad = 24.0;

/// Collection editor tab: header with actions, page tabs, the page and a save bar.
class CollectionView extends StatelessWidget {
  const CollectionView({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, tab]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final p = context.pal;
    final cs = tab.collection;
    final col = state.collection(tab.collectionPath);
    if (cs == null || col == null) return const SizedBox.shrink();
    final page = cs.page;
    return Container(
      color: p.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, col: col),
          _PageTabs(cs: cs),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              // Fill the page and pin content to the top; the default stack centres a page shorter than the viewport.
              child: KeyedSubtree(
                key: ValueKey(page),
                child: page == NodeSection.general
                    ? _Overview(state: state, cs: cs, col: col)
                    : _SettingsPage(state: state, cs: cs, page: page),
              ),
            ),
          ),
          _SaveBar(cs: cs),
        ],
      ),
    );
  }
}

/// Bordered card on the background tint with a small uppercase title.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.trailing,
    this.fill = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// Expand the body to the card's height (the card must be height-bounded).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(_gap),
      decoration: _surface(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            children: [
              Expanded(
                child: T(
                  title.toUpperCase(),
                  color: p.muted,
                  size: 11,
                  weight: FontWeight.w600,
                ),
              ),
              ?trailing,
            ],
          ),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.col});

  final AppState state;
  final Collection col;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 20),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: T(
              col.name.isEmpty ? '?' : col.name.characters.first.toUpperCase(),
              color: p.accent,
              size: 20,
              weight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(
                  col.name,
                  size: 20,
                  weight: FontWeight.w600,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  spacing: 2,
                  children: [
                    Flexible(
                      child: T(
                        col.path,
                        mono: true,
                        color: p.muted,
                        size: 12,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconBtn(
                      icon: Ic.copy,
                      size: 14,
                      onClick: () {
                        Platform.copy(col.path);
                        state.showToast('Path copied');
                      },
                    ),
                    IconBtn(
                      icon: Ic.reveal,
                      size: 14,
                      onClick: () => Platform.reveal(col.path),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                Btn(
                  label: 'Run',
                  icon: Ic.play,
                  primary: true,
                  onClick: () => state.openRunner(col.path, null),
                ),
                Btn(
                  label: 'New request',
                  icon: Ic.add,
                  onClick: () => state.modal = ModalNewRequest(
                    collection: col.path,
                    dir: col.path,
                  ),
                ),
                Btn(
                  label: 'Environments',
                  icon: Ic.environments,
                  onClick: () => state.modal = ModalEnvs(collection: col.path),
                ),
                Btn(
                  label: 'Export…',
                  icon: Ic.export,
                  onClick: () =>
                      state.modal = ModalExport(collection: col.path),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Underline page tabs with the same badges as the settings navigation.
class _PageTabs extends StatelessWidget {
  const _PageTabs({required this.cs});

  final CollectionSession cs;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cfg = cs.controller.config;
    return Container(
      height: 37,
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _pad - 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in collectionPages)
              _PageTab(
                key: ValueKey('page-${s.name}'),
                label: collectionPageLabel(s),
                badge: sectionBadge(s, cfg),
                selected: s == cs.page,
                onClick: () => cs.page = s,
              ),
          ],
        ),
      ),
    );
  }
}

class _PageTab extends StatelessWidget {
  const _PageTab({
    super.key,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onClick,
  });

  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Clickable(
      onClick: onClick,
      cursor: SystemMouseCursors.click,
      child: HoverBuilder(
        builder: (context, hov) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: !selected && hov ? p.hover : const Color(0x00000000),
            border: Border(
              bottom: BorderSide(
                color: selected ? p.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Row(
            spacing: 6,
            children: [
              T(
                label,
                color: selected ? p.text : p.muted,
                weight: selected ? FontWeight.w600 : null,
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: T(
                    badge!,
                    color: p.accent,
                    size: 11,
                    weight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings page: title, description and the editor, left aligned with a readable width.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.state,
    required this.cs,
    required this.page,
  });

  final AppState state;
  final CollectionSession cs;
  final NodeSection page;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860 + 2 * _pad),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  T(
                    collectionPageLabel(page),
                    size: 16,
                    weight: FontWeight.w600,
                  ),
                  T(sectionHint(page, isCol: true), color: p.muted, size: 12),
                ],
              ),
              Expanded(
                child: NodeSettingsView(
                  state: state,
                  controller: cs.controller,
                  showNav: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.cs});

  final CollectionSession cs;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dirty = cs.dirty;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 10),
      child: Row(
        spacing: 8,
        children: [
          if (dirty) ...[
            Container(
              key: const ValueKey('collection-unsaved'),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
            ),
            T('Unsaved changes', color: p.muted, size: 12),
          ],
          const Spacer(),
          Btn(label: 'Revert', onClick: cs.controller.revert, enabled: dirty),
          Btn(
            label: 'Save',
            onClick: cs.controller.save,
            primary: true,
            enabled: dirty,
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.state, required this.cs, required this.col});

  final AppState state;
  final CollectionSession cs;
  final Collection col;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final stats = nodeStats(col.children);
    final stat = [
      _Stat('requests', 'Requests', stats.requests, Ic.send, p.accent),
      _Stat('folders', 'Folders', stats.folders, Ic.folderOpen, p.warn),
      _Stat('workflows', 'Workflows', col.workflows.length, Ic.workflow, p.ok),
      _Stat(
        'environments',
        'Environments',
        col.environments.length,
        Ic.environments,
        p.syntaxKeyword,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900 && c.maxHeight >= 460;
        final details = _Details(state: state, col: col);
        final stats = Row(
          spacing: _gap,
          children: [for (final s in stat) Expanded(child: s)],
        );
        if (wide) {
          // Docs own the page: they fill every pixel the stats and sidebar leave.
          return Padding(
            padding: const EdgeInsets.all(_pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _gap,
              children: [
                stats,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: _gap,
                    children: [
                      Expanded(child: _Docs(cs: cs, fill: true)),
                      SizedBox(
                        width: 340,
                        child: SingleChildScrollView(child: details),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(_pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: _gap,
            children: [
              if (c.maxWidth >= 560)
                stats
              else ...[
                Row(
                  spacing: _gap,
                  children: [
                    Expanded(child: stat[0]),
                    Expanded(child: stat[1]),
                  ],
                ),
                Row(
                  spacing: _gap,
                  children: [
                    Expanded(child: stat[2]),
                    Expanded(child: stat[3]),
                  ],
                ),
              ],
              _Docs(cs: cs, fill: false),
              details,
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.id, this.label, this.count, this.icon, this.color);

  final String id;
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: color),
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
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Ico(icon, tint: color, size: 16)),
                    ),
                    Flexible(
                      child: T(
                        label.toUpperCase(),
                        color: p.muted,
                        size: 10.5,
                        weight: FontWeight.w600,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                T(
                  '$count',
                  key: ValueKey('stat-$id'),
                  size: 24,
                  weight: FontWeight.w600,
                  mono: true,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Location, environments, method breakdown and recent runs.
class _Details extends StatelessWidget {
  const _Details({required this.state, required this.col});

  final AppState state;
  final Collection col;

  String? get _modified {
    try {
      final m = File(path.join(col.path, OrYaml.ROOT_FILE)).statSync().modified;
      String two(int n) => n.toString().padLeft(2, '0');
      return '${m.year}-${two(m.month)}-${two(m.day)} ${two(m.hour)}:${two(m.minute)}';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final env = state.envName(col.path);
    final global = state.globalEnvName();
    final methods = methodCounts(col.children);
    final runs = state.history.where((h) => h.collection == col.path).take(5);
    final modified = _modified;
    Widget row(String label, Widget value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        T(label, color: p.muted, size: 12),
        value,
      ],
    );
    Widget envChip(String? v) =>
        Chip(v ?? 'None', color: v == null ? p.muted : p.accent);
    return _Card(
      title: 'Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          row('Location', T(col.path, mono: true, size: 12, softWrap: true)),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              row('Active environment', envChip(env)),
              row('Global environment', envChip(global)),
              if (modified != null) row('Last modified', T(modified, size: 12)),
            ],
          ),
          if (methods.isNotEmpty)
            row(
              'Requests by method',
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in methods)
                    Chip(
                      '${m.key == 'DELETE' ? 'DEL' : m.key} ${m.value}',
                      color: methodColor(m.key, p),
                    ),
                ],
              ),
            ),
          if (runs.isNotEmpty)
            row(
              'Recent runs',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final h in runs)
                    Row(
                      spacing: 8,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: h.error != null
                                ? p.err
                                : statusColor(h.status, p),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: T(
                            h.name,
                            size: 12,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        T(
                          h.error != null ? 'error' : '${h.status}',
                          color: p.muted,
                          size: 12,
                        ),
                        T('${h.timeMs} ms', color: p.muted, size: 12),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Docs extends StatelessWidget {
  const _Docs({required this.cs, required this.fill});

  final CollectionSession cs;

  /// Fill the available height (wide layout) instead of using fixed sizes.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ctl = cs.controller;
    final docs = ctl.config.docs;
    final editing = cs.editingDocs;
    Widget preview() => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: MarkdownView(docs),
    );
    final code = CodeEditor(
      key: ValueKey('docs/${ctl.revision}'),
      value: docs,
      onChange: (v) => ctl.update(ctl.config.copyWith(docs: v)),
      lang: 'text',
    );
    Widget editor() => fill ? code : SizedBox(height: 420, child: code);
    Widget body;
    if (editing) {
      body = cs.previewingDocs
          ? SingleChildScrollView(
              child: Align(alignment: Alignment.topLeft, child: preview()),
            )
          : editor();
    } else if (docs.trim().isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              T('No documentation yet', weight: FontWeight.w600, size: 15),
              T(
                'Describe what this collection is for, how to authenticate and where to start. Markdown is supported.',
                color: p.muted,
                size: 12,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Btn(
                label: 'Add documentation',
                icon: Ic.edit,
                onClick: () => cs.editingDocs = true,
              ),
            ],
          ),
        ),
      );
    } else {
      body = Align(alignment: Alignment.topLeft, child: preview());
      if (fill) body = SingleChildScrollView(child: body);
    }
    return _Card(
      fill: fill,
      title: 'Documentation',
      trailing: Row(
        spacing: 8,
        children: [
          if (editing) ...[
            Btn(
              key: const ValueKey('docs-preview'),
              label: cs.previewingDocs ? 'Edit' : 'Preview',
              icon: cs.previewingDocs ? Ic.edit : Ic.eye,
              onClick: () => cs.previewingDocs = !cs.previewingDocs,
            ),
            Btn(
              key: const ValueKey('docs-save'),
              label: 'Save',
              primary: true,
              onClick: ctl.save,
              enabled: ctl.dirty,
            ),
            Btn(
              key: const ValueKey('docs-close'),
              label: 'Close',
              onClick: () => cs.editingDocs = false,
            ),
          ] else
            IconBtn(
              key: const ValueKey('docs-edit'),
              icon: Ic.edit,
              onClick: () => cs.editingDocs = true,
            ),
        ],
      ),
      child: body,
    );
  }
}
