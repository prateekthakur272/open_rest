import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Bordered section tinted with the background colour.
class SettingsBox extends StatelessWidget {
  const SettingsBox({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
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
  }
}

/// Name, location and contents of a collection or folder.
class NodeGeneralPage extends StatelessWidget {
  const NodeGeneralPage({
    super.key,
    required this.state,
    required this.collection,
    required this.node,
  });
  final AppState state;
  final Collection collection;

  /// Collection path or folder path.
  final String node;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isCol = node == collection.path;
    final folder = isCol ? null : findFolder(collection.children, node);
    final name = isCol ? collection.name : (folder?.name ?? '');
    final stats = nodeStats(
      isCol ? collection.children : (folder?.children ?? []),
    );
    Widget row(String label, Widget value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 90, child: T(label, color: p.muted, size: 12)),
        Expanded(child: value),
      ],
    );
    final reveal = Platform.revealLabel;
    return ScrollBox(
      content: [
        SizedBox(
          width: double.infinity,
          child: SettingsBox(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                row('Name', T(name, weight: FontWeight.w600)),
                row('Kind', T(isCol ? 'Collection' : 'Folder')),
                row('Path', T(node, mono: true, size: 12)),
                row(
                  'Contents',
                  T(
                    [
                      countLabel(stats.requests, 'request'),
                      countLabel(stats.folders, 'folder'),
                      if (isCol)
                        countLabel(collection.workflows.length, 'workflow'),
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
                      onClick: () => Platform.reveal(node),
                    ),
                    Btn(
                      label: 'Copy path',
                      icon: Ic.copy,
                      onClick: () {
                        Platform.copy(node);
                        state.showToast('Path copied');
                      },
                    ),
                  ],
                ),
              ],
            ),
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
