import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// One column of the environment popover: a title, a "none" entry and the available choices.
class EnvGroup {
  const EnvGroup({
    required this.title,
    required this.noneLabel,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String noneLabel;
  final List<String> options;

  /// The chosen option, or null when the "none" entry is active.
  final String? selected;

  /// Called with the chosen option, or null for the "none" entry.
  final ValueChanged<String?> onSelect;
}

/// Header control for choosing the collection environment and the global environment.
class EnvSelector extends StatelessWidget {
  const EnvSelector({super.key, required this.state, required this.collection});

  final AppState state;

  /// The open collection, or null when none is open (only the global environment can be chosen then).
  final Collection? collection;

  @override
  Widget build(BuildContext context) {
    final col = collection;
    final collectionEnv = col == null ? null : state.envName(col.path);
    final globalEnv = state.globalEnvName();
    final collectionGroup = col == null
        ? null
        : EnvGroup(
            title: 'Collection',
            noneLabel: 'No environment',
            options: col.environments.map((e) => e.name).toList(),
            selected: collectionEnv,
            onSelect: (v) => state.setEnv(col.path, v),
          );
    final globalGroup = EnvGroup(
      title: 'Global',
      noneLabel: 'No global',
      options: state.globalEnvs.map((e) => e.name).toList(),
      selected: globalEnv,
      onSelect: state.setGlobalEnv,
    );
    return _EnvChip(
      label: envSummary(collectionEnv, globalEnv),
      active: collectionEnv != null || globalEnv != null,
      width: collectionGroup == null ? 200 : 400,
      popover: (close) => _ColumnsPopover(
        groups: [?collectionGroup, globalGroup],
        onManage: () {
          close();
          state.modal = col == null
              ? const ModalEnvs()
              : ModalEnvs(collection: col.path);
        },
        close: close,
      ),
    );
  }
}

/// Text for the closed chip: "dev + shared (global)", "dev" or "shared (global)".
String envSummary(String? collectionEnv, String? globalEnv) {
  if (collectionEnv != null && globalEnv != null) {
    return '$collectionEnv + $globalEnv (global)';
  }
  if (collectionEnv != null) return collectionEnv;
  if (globalEnv != null) return '$globalEnv (global)';
  return 'No environment';
}

/// Rectangular chip that shows the active environments and opens [popover] below itself.
class _EnvChip extends StatelessWidget {
  const _EnvChip({
    required this.label,
    required this.active,
    required this.width,
    required this.popover,
  });

  final String label;

  /// Whether any environment is selected (the label is green then, muted otherwise).
  final bool active;
  final double width;
  final Widget Function(VoidCallback close) popover;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Builder(
      builder: (anchorCtx) => Clickable(
        onClick: () => showAnchoredPopup<void>(
          anchorCtx,
          anchor: anchorRectOf(anchorCtx),
          width: width,
          builder: (ctx, close) => popover(() => close(null)),
        ),
        cursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: CONTROL_H,
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(5),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: p.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Flexible(
                child: T(
                  label,
                  color: active ? p.ok : p.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Ico(Ic.dropDown, tint: p.muted, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable row with a tick on the active entry.
class _EnvRow extends StatelessWidget {
  const _EnvRow({
    required this.text,
    required this.selected,
    required this.onTap,
    this.dim = false,
  });

  final String text;
  final bool selected;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      onTap: onTap,
      indicate: true,
      builder: (ctx, hov) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          spacing: 8,
          children: [
            SizedBox(
              width: 14,
              child: selected ? Ico(Ic.check, tint: p.accent, size: 14) : null,
            ),
            Flexible(
              child: T(
                text,
                color: dim ? p.muted : p.text,
                weight: selected ? FontWeight.w600 : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageFooter extends StatelessWidget {
  const _ManageFooter({required this.onManage});
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: p.border),
        HoverBuilder(
          cursor: SystemMouseCursors.click,
          onTap: onManage,
          indicate: true,
          builder: (ctx, hov) => Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Row(
              spacing: 8,
              children: [
                Ico(Ic.environments, tint: p.muted, size: 15),
                T('Manage environments…', color: p.muted, size: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
    child: T(
      text.toUpperCase(),
      color: context.pal.muted,
      size: 10,
      weight: FontWeight.w600,
    ),
  );
}

/// Popover with the groups side by side so both selections are visible at once.
class _ColumnsPopover extends StatelessWidget {
  const _ColumnsPopover({
    required this.groups,
    required this.onManage,
    required this.close,
  });

  final List<EnvGroup> groups;
  final VoidCallback onManage;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) Container(width: 1, color: p.border),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GroupTitle(groups[i].title),
                      _EnvRow(
                        text: groups[i].noneLabel,
                        dim: true,
                        selected: groups[i].selected == null,
                        onTap: () {
                          groups[i].onSelect(null);
                          close();
                        },
                      ),
                      for (final o in groups[i].options)
                        _EnvRow(
                          text: o,
                          selected: groups[i].selected == o,
                          onTap: () {
                            groups[i].onSelect(o);
                            close();
                          },
                        ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        _ManageFooter(onManage: onManage),
      ],
    );
  }
}
