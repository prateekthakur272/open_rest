import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/node_general_page.dart';
import 'package:open_rest/features/dialogs/node_settings_controller.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/features/request/request_pane.dart';
import 'package:open_rest/features/request/tls_editor.dart';
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

/// Left navigation (optional) plus the page of a collection / folder settings editor.
/// Hosts own the [controller] and provide their own save / close controls.
class NodeSettingsView extends StatefulWidget {
  const NodeSettingsView({
    super.key,
    required this.state,
    required this.controller,
    this.showNav = true,
  });
  final AppState state;
  final NodeSettingsController controller;

  /// Whether to show the left navigation; without it only the page of the controller's section is shown
  /// (the host provides its own page switcher).
  final bool showNav;

  @override
  State<NodeSettingsView> createState() => _NodeSettingsViewState();
}

class _NodeSettingsViewState extends State<NodeSettingsView> {
  String _scriptTab = 'Pre Request';
  String _varsTab = 'Pre Request';

  NodeSettingsController get ctl => widget.controller;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = widget.state.collection(ctl.collection);
    if (col == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final c = ctl.config;
        final isCol = ctl.isCollection;
        if (!widget.showNav) {
          return KeyedSubtree(
            key: ValueKey('${ctl.section.name}/${ctl.revision}'),
            child: _editor(p, c, isCol, col),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            SizedBox(width: 190, child: _nav(p, c)),
            Expanded(child: _page(p, c, isCol, col)),
          ],
        );
      },
    );
  }

  Widget _box(Pal p, Widget child) => SettingsBox(child: child);

  Widget _nav(Pal p, NodeConfig c) => _box(
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
    final sel = s == ctl.section;
    final badge = sectionBadge(s, c);
    return Clickable(
      key: ValueKey('nav-${s.name}'),
      onClick: () => ctl.section = s,
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

  Widget _page(Pal p, NodeConfig c, bool isCol, Collection col) {
    final s = ctl.section;
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
            key: ValueKey('${s.name}/${ctl.revision}'),
            child: _editor(p, c, isCol, col),
          ),
        ),
      ],
    );
  }

  Widget _editor(Pal p, NodeConfig c, bool isCol, Collection col) {
    switch (ctl.section) {
      case NodeSection.general:
        return NodeGeneralPage(
          state: widget.state,
          collection: col,
          node: ctl.node,
        );
      case NodeSection.headers:
        return _box(
          p,
          ScrollBox(
            content: [
              KVTable(
                items: c.headers,
                onChange: (v) => ctl.update(c.copyWith(headers: v)),
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
                onChange: (a) => ctl.update(
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
                  onChange: (t) => ctl.update(c.copyWith(tls: t)),
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
                        onChange: (v) => ctl.update(c.copyWith(preVars: v)),
                        keyHint: 'Name',
                        valueHint: 'Value',
                      )
                    else
                      KVTable(
                        items: c.postVars,
                        onChange: (v) => ctl.update(c.copyWith(postVars: v)),
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
                      onChange: (v) => ctl.update(c.copyWith(preScript: v)),
                      lang: 'js',
                    )
                  : CodeEditor(
                      value: c.postScript,
                      onChange: (v) => ctl.update(c.copyWith(postScript: v)),
                      lang: 'js',
                    ),
            ),
          ],
        );
      case NodeSection.tests:
        return CodeEditor(
          value: c.tests,
          onChange: (v) => ctl.update(c.copyWith(tests: v)),
          lang: 'js',
        );
      case NodeSection.docs:
        return CodeEditor(
          value: c.docs,
          onChange: (v) => ctl.update(c.copyWith(docs: v)),
          lang: 'text',
        );
    }
  }
}
