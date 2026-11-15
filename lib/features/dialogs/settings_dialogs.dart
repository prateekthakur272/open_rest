import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/request/request_pane.dart';
import 'package:open_rest/theme/theme.dart';

/// Dialog for editing collection or folder settings.
class NodeSettingsDialog extends StatefulWidget {
  const NodeSettingsDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalNodeSettings m;

  @override
  State<NodeSettingsDialog> createState() => _NodeSettingsDialogState();
}

class _NodeSettingsDialogState extends State<NodeSettingsDialog> {
  NodeConfig? cfg;
  String tab = 'Headers';
  String scriptTab = 'Pre Request';
  String varsTab = 'Pre Request';

  FolderNode? _findFolder(List<Node> nodes) {
    for (final n in nodes) {
      if (n is FolderNode) {
        if (n.path == widget.m.node) return n;
        final r = _findFolder(n.children);
        if (r != null) return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final m = widget.m;
    final p = context.pal;
    final col = state.collection(m.collection);
    if (col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final isCol = m.node == col.path;
    final c = cfg ??= isCol
        ? col.config
        : (_findFolder(col.children)?.config ?? const NodeConfig());
    void upd(NodeConfig n) => setState(() => cfg = n);
    final title = isCol
        ? 'Collection Settings — ${col.name}'
        : 'Folder Settings — ${c.name}';

    Widget body;
    switch (tab) {
      case 'Headers':
        body = ScrollBox(
          content: [
            KVTable(
              items: c.headers,
              onChange: (v) => upd(c.copyWith(headers: v)),
              keyHint: 'Header',
              valueHint: 'Value',
            ),
          ],
        );
      case 'Auth':
        final modes = isCol
            ? AuthMode.values.where((x) => x != AuthMode.Inherit).toList()
            : AuthMode.values.where((x) => x != AuthMode.None).toList();
        // For folders, "Inherit" is stored as no auth so the parent's auth applies.
        final shown = (!isCol && c.auth.mode == AuthMode.None)
            ? c.auth.copyWith(mode: AuthMode.Inherit)
            : c.auth;
        body = ScrollBox(
          content: [
            AuthEditor(
              auth: shown,
              onChange: (a) => upd(
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
        );
      case 'Vars':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tabs(
              items: const ['Pre Request', 'Post Response'],
              selected: varsTab,
              onSelect: (t) => setState(() => varsTab = t),
            ),
            Expanded(
              child: ScrollBox(
                content: [
                  if (varsTab == 'Pre Request')
                    KVTable(
                      items: c.preVars,
                      onChange: (v) => upd(c.copyWith(preVars: v)),
                      keyHint: 'Name',
                      valueHint: 'Value',
                    )
                  else
                    KVTable(
                      items: c.postVars,
                      onChange: (v) => upd(c.copyWith(postVars: v)),
                      keyHint: 'Name',
                      valueHint: 'Expression  (res.body.id)',
                    ),
                ],
              ),
            ),
          ],
        );
      case 'Script':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Tabs(
              items: const ['Pre Request', 'Post Response'],
              selected: scriptTab,
              onSelect: (t) => setState(() => scriptTab = t),
            ),
            Expanded(
              child: scriptTab == 'Pre Request'
                  ? CodeEditor(
                      value: c.preScript,
                      onChange: (v) => upd(c.copyWith(preScript: v)),
                      lang: 'js',
                    )
                  : CodeEditor(
                      value: c.postScript,
                      onChange: (v) => upd(c.copyWith(postScript: v)),
                      lang: 'js',
                    ),
            ),
          ],
        );
      case 'Tests':
        body = CodeEditor(
          value: c.tests,
          onChange: (v) => upd(c.copyWith(tests: v)),
          lang: 'js',
        );
      default:
        body = CodeEditor(
          value: c.docs,
          onChange: (v) => upd(c.copyWith(docs: v)),
          lang: 'text',
        );
    }

    return ModalBox(
      title: title,
      onClose: () => state.modal = null,
      width: 760,
      height: 560,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: 'Save',
          onClick: () {
            state.saveNodeConfig(col.path, m.node, c);
            state.modal = null;
          },
          primary: true,
        ),
      ],
      content: [
        SizedBox(
          width: double.infinity,
          child: Tabs(
            items: const ['Headers', 'Auth', 'Vars', 'Script', 'Tests', 'Docs'],
            selected: tab,
            onSelect: (t) => setState(() => tab = t),
          ),
        ),
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: KeyedSubtree(key: ValueKey(tab), child: body),
          ),
        ),
        T(
          'Applies to every request ${isCol ? 'in this collection' : 'inside this folder'}. Collection → folder → request order.',
          color: p.muted,
          size: 12,
        ),
      ],
    );
  }
}
