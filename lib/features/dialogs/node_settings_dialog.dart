import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/features/dialogs/node_settings_controller.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/features/dialogs/node_settings_view.dart';
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
  late final NodeSettingsController _ctl = NodeSettingsController(
    widget.state,
    widget.m.collection,
    widget.m.node,
  );

  /// Confirmation shown over the dialog (inside it, so the draft survives).
  bool _asking = false;

  AppState get state => widget.state;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _setAsking(bool v) => setState(() => _asking = v);

  void _close() {
    if (_asking) return _setAsking(false);
    if (_ctl.dirty) return _setAsking(true);
    state.modal = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final hw = HardwareKeyboard.instance;
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyS &&
        (hw.isMetaPressed || hw.isControlPressed)) {
      if (!_asking) _ctl.save();
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
    final isCol = _ctl.isCollection;
    final kind = isCol ? 'collection' : 'folder';
    return Focus(
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: _ctl,
        builder: (context, _) {
          final dirty = _ctl.dirty;
          return Stack(
            fit: StackFit.expand,
            children: [
              ModalBox(
                title: isCol
                    ? 'Collection Settings — ${col.name}'
                    : 'Folder Settings — ${findFolder(col.children, widget.m.node)?.name ?? ''}',
                onClose: _close,
                width: 900,
                height: 620,
                actions: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: dirty ? _unsaved(p) : null,
                    ),
                  ),
                  Btn(label: 'Revert', onClick: _ctl.revert, enabled: dirty),
                  Btn(label: 'Close', onClick: _close),
                  Btn(
                    label: 'Save',
                    onClick: _ctl.save,
                    primary: true,
                    enabled: dirty,
                  ),
                ],
                content: [
                  Expanded(
                    child: NodeSettingsView(state: state, controller: _ctl),
                  ),
                ],
              ),
              if (_asking)
                ModalBox(
                  title: 'Unsaved changes',
                  onClose: () => _setAsking(false),
                  width: 420,
                  actions: [
                    Btn(label: 'Cancel', onClick: () => _setAsking(false)),
                    Btn(
                      label: 'Discard',
                      onClick: () => state.modal = null,
                      danger: true,
                    ),
                    Btn(
                      label: 'Save',
                      onClick: () {
                        _ctl.save();
                        state.modal = null;
                      },
                      primary: true,
                    ),
                  ],
                  content: [T('This $kind has unsaved settings changes.')],
                ),
            ],
          );
        },
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
}
