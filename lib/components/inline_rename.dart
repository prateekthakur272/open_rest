import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/components/field.dart';

class InlineRename extends StatefulWidget {
  const InlineRename({super.key, required this.initial, required this.onDone});

  final String initial;
  final void Function(String?) onDone;

  @override
  State<InlineRename> createState() => _InlineRenameState();
}

class _InlineRenameState extends State<InlineRename> {
  late String v = widget.initial;
  bool gotFocus = false;
  final FocusNode fr = FocusNode();

  @override
  void initState() {
    super.initState();
    fr.addListener(() {
      if (fr.hasFocus) {
        gotFocus = true;
      } else if (gotFocus) {
        widget.onDone(null);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fr.requestFocus();
    });
  }

  @override
  void dispose() {
    fr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (n, e) {
      if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
        widget.onDone(null);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Field(
      value: v,
      onChange: (t) => setState(() => v = t),
      onEnter: () {
        final t = v.trim();
        widget.onDone(t.isNotEmpty ? t : null);
      },
      focusRequester: fr,
      highlightVars: false,
    ),
  );
}
