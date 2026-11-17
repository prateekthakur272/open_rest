import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/utils/paths.dart';

/// `~/OpenRest`: where new collections are created by default.
String get defaultDir => Paths.defaultCollectionsDir;

/// Dialog that asks for a single text value.
class PromptDialog extends StatefulWidget {
  const PromptDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalPrompt m;

  @override
  State<PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<PromptDialog> {
  late String v = widget.m.initial;
  final FocusNode fr = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fr.requestFocus();
    });
  }

  @override
  void dispose() {
    fr.dispose();
    super.dispose();
  }

  void ok() {
    if (v.trim().isNotEmpty) {
      widget.state.modal = null;
      widget.m.onOk(v.trim());
    }
  }

  @override
  Widget build(BuildContext context) => ModalBox(
    title: widget.m.title,
    onClose: () => widget.state.modal = null,
    width: 420,
    actions: [
      Btn(label: 'Cancel', onClick: () => widget.state.modal = null),
      Btn(
        label: widget.m.confirm,
        onClick: ok,
        primary: true,
        enabled: v.trim().isNotEmpty,
      ),
    ],
    content: [
      SectionLabel(widget.m.label.toUpperCase()),
      SizedBox(
        width: double.infinity,
        child: Field(
          value: v,
          onChange: (t) => setState(() => v = t),
          onEnter: ok,
          focusRequester: fr,
          highlightVars: false,
        ),
      ),
    ],
  );
}
