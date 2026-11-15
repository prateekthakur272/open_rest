import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/features/request/request_pane.dart';
import 'package:open_rest/features/request/tls_editor.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

const _icons = {
  NodeSection.general: Ic.info,
  NodeSection.headers: Ic.formBody,
  NodeSection.auth: Ic.key,
  NodeSection.variables: Ic.variables,
  NodeSection.scripts: Ic.code,
  NodeSection.tests: Ic.checklist,
  NodeSection.docs: Ic.fmtRaw,
  NodeSection.tls: Ic.shield,
};

/// Dialog for editing collection or folder settings.
class NodeSettingsDialog extends StatefulWidget {
  const NodeSettingsDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalNodeSettings m;

  @override
  State<NodeSettingsDialog> createState() => _NodeSettingsDialogState();
}

class _NodeSettingsDialogState extends State<NodeSettingsDialog> {
  /// Last saved config and the draft being edited.
  NodeConfig? _saved;
  NodeConfig? _draft;
  NodeSection _section = NodeSection.headers;
  String _scriptTab = 'Pre Request';
  String _varsTab = 'Pre Request';

  /// Bumped on revert so editors rebuild from the restored config.
  int _rev = 0;

  /// Confirmation shown over the dialog (inside it, so the draft survives).
  bool _asking = false;

  AppState get state => widget.state;
  bool get _dirty => _saved != null && nodeConfigDirty(_saved!, _draft!);

  void _upd(NodeConfig c) => setState(() => _draft = c);

  void _close() {
    if (_asking) return setState(() => _asking = false);
    if (_dirty) return setState(() => _asking = true);
    state.modal = null;
  }

  void _save({bool close = false}) {
    if (!_dirty) {
      if (close) state.modal = null;
      return;
    }
    state.saveNodeConfig(widget.m.collection, widget.m.node, _draft!);
    if (close) {
      state.modal = null;
    } else {
      setState(() => _saved = _draft);
    }
  }

  void _revert() => setState(() {
    _draft = _saved;
    _rev++;
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final hw = HardwareKeyboard.instance;
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyS &&
        (hw.isMetaPressed || hw.isControlPressed)) {
      if (!_asking) _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = state.collection(widget.m.collection);
    if (col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final isCol = widget.m.node == col.path;
    final folder = isCol ? null : findFolder(col.children, widget.m.node);
    _saved ??= isCol ? col.config : (folder?.config ?? const NodeConfig());
    final c = _draft ??= _saved!;
    final name = isCol ? col.name : (folder?.name ?? c.name);

    return Focus(
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBox(
            title: '${isCol ? 'Collection' : 'Folder'} Settings — $name',
            onClose: _close,
            width: 900,
            height: 620,
            actions: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _dirty ? _unsaved(p) : null,
                ),
              ),
              Btn(label: 'Revert', onClick: _revert, enabled: _dirty),
              Btn(label: 'Close', onClick: _close),
              Btn(
                label: 'Save',
                onClick: _save,
                primary: true,
                enabled: _dirty,
              ),
            ],
            content: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    SizedBox(width: 190, child: _nav(p, c, isCol)),
                    Expanded(child: _page(p, c, isCol, col, name, folder)),
                  ],
                ),
              ),
            ],
          ),
          if (_asking)
            ModalBox(
              title: 'Unsaved changes',
              onClose: () => setState(() => _asking = false),
              width: 420,
              actions: [
                Btn(
                  label: 'Cancel',
                  onClick: () => setState(() => _asking = false),
                ),
                Btn(
                  label: 'Discard',
                  onClick: () => state.modal = null,
                  danger: true,
                ),
                Btn(
                  label: 'Save',
                  onClick: () => _save(close: true),
                  primary: true,
                ),
              ],
              content: [
                T(
                  'This ${isCol ? 'collection' : 'folder'} has unsaved settings changes.',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _unsaved(Pal p) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
      ),
      T('Unsaved changes', color: p.muted, size: 12),
    ],
  );

  /// Bordered section tinted with the background colour.
  Widget _box(Pal p, Widget child, {EdgeInsets? padding}) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: p.bg,
      borderRadius: BorderRadius.circular(6),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: p.border),
    ),
    child: child,
  );

  Widget _nav(Pal p, NodeConfig c, bool isCol) => _box(
    p,
    SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final s in NodeSection.values) _navRow(p, c, s)],
      ),
    ),
  );

  Widget _navRow(Pal p, NodeConfig c, NodeSection s) {
    final sel = s == _section;
    final badge = sectionBadge(s, c);
    return Clickable(
      key: ValueKey('nav-${s.name}'),
      onClick: () => setState(() => _section = s),
      child: Container(
        height: 34,
        color: sel ? p.selected : const Color(0x00000000),
        child: Row(
          children: [
            Container(width: 3, color: sel ? p.accent : null),
            const SizedBox(width: 9),
            Ico(_icons[s]!, tint: sel ? p.accent : p.muted, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: T(
                s.label,
                color: sel ? p.text : p.muted,
                weight: sel ? FontWeight.w600 : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: T(
                  badge,
                  key: ValueKey('badge-${s.name}'),
                  color: p.accent,
                  size: 11,
                  weight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _page(
    Pal p,
    NodeConfig c,
    bool isCol,
    Collection col,
    String name,
    FolderNode? folder,
  ) {
    final s = _section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            T(s.label, size: 15, weight: FontWeight.w600),
            T(sectionHint(s, isCol: isCol), color: p.muted, size: 12),
          ],
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('${s.name}/$_rev'),
            child: _editor(p, c, isCol, col, name, folder),
          ),
        ),
      ],
    );
  }

  Widget _editor(
    Pal p,
    NodeConfig c,
    bool isCol,
    Collection col,
    String name,
    FolderNode? folder,
  ) {
    switch (_section) {
      case NodeSection.general:
        return _general(p, isCol, col, name, folder);
      case NodeSection.headers:
        return _box(
          p,
          ScrollBox(
            content: [
              KVTable(
                items: c.headers,
                onChange: (v) => _upd(c.copyWith(headers: v)),
                keyHint: 'Header',
                valueHint: 'Value',
              ),
            ],
          ),
        );
      case NodeSection.auth:
        final modes = isCol
            ? AuthMode.values.where((x) => x != AuthMode.Inherit).toList()
            : AuthMode.values.where((x) => x != AuthMode.None).toList();
        // For folders, "Inherit" is stored as no auth so the parent's auth applies.
        final shown = (!isCol && c.auth.mode == AuthMode.None)
            ? c.auth.copyWith(mode: AuthMode.Inherit)
            : c.auth;
        return _box(
          p,
          ScrollBox(
            content: [
              AuthEditor(
                auth: shown,
                onChange: (a) => _upd(
                  c.copyWith(
                    auth: (!isCol && a.mode == AuthMode.Inherit)
                        ? a.copyWith(mode: AuthMode.None)
                        : a,
                  ),
                ),
                modes: modes,
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        );
      case NodeSection.tls:
        return _box(
          p,
          ScrollBox(
            content: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TlsEditor(
                  config: c.tls,
                  onChange: (t) => _upd(c.copyWith(tls: t)),
                  inheritLabel: isCol
                      ? 'No certificate'
                      : 'Inherit from parent folder / collection',
                  allowNone: !isCol,
                  baseDir: col.path,
                ),
              ),
            ],
          ),
        );
      case NodeSection.variables:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Tabs(
              items: const ['Pre Request', 'Post Response'],
              selected: _varsTab,
              onSelect: (t) => setState(() => _varsTab = t),
            ),
            Expanded(
              child: _box(
                p,
                ScrollBox(
                  content: [
                    if (_varsTab == 'Pre Request')
                      KVTable(
                        items: c.preVars,
                        onChange: (v) => _upd(c.copyWith(preVars: v)),
                        keyHint: 'Name',
                        valueHint: 'Value',
                      )
                    else
                      KVTable(
                        items: c.postVars,
                        onChange: (v) => _upd(c.copyWith(postVars: v)),
                        keyHint: 'Name',
                        valueHint: 'Expression  (res.body.id)',
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      case NodeSection.scripts:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Tabs(
              items: const ['Pre Request', 'Post Response'],
              selected: _scriptTab,
              onSelect: (t) => setState(() => _scriptTab = t),
              badge: (t) =>
                  (t == 'Pre Request' ? c.preScript : c.postScript)
                      .trim()
                      .isEmpty
                  ? null
                  : dotBadge,
            ),
            Expanded(
              child: _scriptTab == 'Pre Request'
                  ? CodeEditor(
                      value: c.preScript,
                      onChange: (v) => _upd(c.copyWith(preScript: v)),
                      lang: 'js',
                    )
                  : CodeEditor(
                      value: c.postScript,
                      onChange: (v) => _upd(c.copyWith(postScript: v)),
                      lang: 'js',
                    ),
            ),
          ],
        );
      case NodeSection.tests:
        return CodeEditor(
          value: c.tests,
          onChange: (v) => _upd(c.copyWith(tests: v)),
          lang: 'js',
        );
      case NodeSection.docs:
        return CodeEditor(
          value: c.docs,
          onChange: (v) => _upd(c.copyWith(docs: v)),
          lang: 'text',
        );
    }
  }

  Widget _general(
    Pal p,
    bool isCol,
    Collection col,
    String name,
    FolderNode? folder,
  ) {
    final stats = nodeStats(isCol ? col.children : (folder?.children ?? []));
    final path = widget.m.node;
    final kind = isCol ? 'Collection' : 'Folder';
    Widget row(String label, Widget value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 90, child: T(label, color: p.muted, size: 12)),
        Expanded(child: value),
      ],
    );
    final reveal = Platform.isMac
        ? 'Reveal in Finder'
        : (Platform.isWindows ? 'Show in Explorer' : 'Show in file manager');
    return ScrollBox(
      content: [
        SizedBox(
          width: double.infinity,
          child: _box(
            p,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                row('Name', T(name, weight: FontWeight.w600)),
                row('Kind', T(kind)),
                row('Path', T(path, mono: true, size: 12)),
                row(
                  'Contents',
                  T(
                    [
                      countLabel(stats.requests, 'request'),
                      countLabel(stats.folders, 'folder'),
                      if (isCol) countLabel(col.workflows.length, 'workflow'),
                    ].join('  ·  '),
                  ),
                ),
                Row(
                  spacing: 8,
                  children: [
                    const SizedBox(width: 90),
                    Btn(
                      label: reveal,
                      icon: Ic.reveal,
                      onClick: () => Platform.reveal(path),
                    ),
                    Btn(
                      label: 'Copy path',
                      icon: Ic.copy,
                      onClick: () {
                        Platform.copy(path);
                        state.showToast('Path copied');
                      },
                    ),
                  ],
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 12),
        T(
          'Settings made here are inherited by every request ${isCol ? 'in this collection' : 'inside this folder'}, '
          'applied in the order collection, folder, request. A request or a deeper folder can override them.',
          color: p.muted,
          size: 12,
        ),
      ],
    );
  }
}
