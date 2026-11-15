import 'package:flutter/widgets.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/env_logic.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Detail pane of the environments dialog: name, actions and the variable editor (table or bulk text).
class EnvEditor extends StatefulWidget {
  const EnvEditor({
    super.key,
    required this.draft,
    required this.dirty,
    required this.nameError,
    required this.active,
    required this.onChange,
    required this.onActivate,
    required this.onDuplicate,
    required this.onDelete,
    required this.onSave,
    required this.onRevert,
  });

  final EnvDraft draft;
  final bool dirty;
  final String? nameError;
  final bool active;
  final ValueChanged<EnvDraft> onChange;
  final VoidCallback onActivate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onRevert;

  @override
  State<EnvEditor> createState() => EnvEditorState();
}

class EnvEditorState extends State<EnvEditor> {
  String filter = '';
  bool bulk = false;
  String bulkText = '';
  final Set<int> revealed = {};

  EnvDraft get draft => widget.draft;

  /// Applies pending bulk text to the draft so nothing typed there is lost.
  void flushBulk() {
    if (!bulk) return;
    if (bulkText != serializeBulk(draft.vars)) {
      final vars = parseBulk(bulkText);
      widget.onChange(
        draft.copyWith(vars: vars, secrets: secretsFor(draft.secrets, vars)),
      );
    }
    setState(() {
      bulk = false;
      revealed.clear();
    });
  }

  /// Leaves bulk mode without applying its text.
  void discardBulk() {
    if (!bulk) return;
    setState(() {
      bulk = false;
      revealed.clear();
    });
  }

  void _toggleBulk() {
    if (bulk) {
      flushBulk();
    } else {
      setState(() {
        bulkText = serializeBulk(draft.vars);
        bulk = true;
      });
    }
  }

  void _setVar(int i, KV kv) {
    final vars = List<KV>.of(draft.vars)..[i] = kv;
    var secrets = draft.secrets;
    final old = draft.vars[i].name;
    if (old != kv.name && secrets.contains(old)) {
      secrets = Set.of(secrets)..remove(old);
      if (kv.name.trim().isNotEmpty) secrets.add(kv.name);
    }
    widget.onChange(draft.copyWith(vars: vars, secrets: secrets));
  }

  void _removeVar(int i) {
    final vars = List<KV>.of(draft.vars)..removeAt(i);
    revealed.clear();
    widget.onChange(
      draft.copyWith(vars: vars, secrets: secretsFor(draft.secrets, vars)),
    );
  }

  void _toggleSecret(int i, bool on) {
    final n = draft.vars[i].name;
    if (n.trim().isEmpty) return;
    widget.onChange(
      draft.copyWith(
        secrets: on
            ? {...draft.secrets, n}
            : (Set.of(draft.secrets)..remove(n)),
      ),
    );
  }

  bool _matches(KV v) {
    final q = filter.trim().toLowerCase();
    return q.isEmpty ||
        v.name.toLowerCase().contains(q) ||
        v.value.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final n = draft.vars.length;
    final shown = [
      for (var i = 0; i < n; i++)
        if (_matches(draft.vars[i])) i,
    ];
    final filtering = filter.trim().isNotEmpty && !bulk;
    final countText = filtering
        ? '${shown.length} of $n variables'
        : '$n variable${n == 1 ? '' : 's'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Field(
              value: draft.name,
              onChange: (v) => widget.onChange(draft.copyWith(name: v)),
              placeholder: 'Environment name',
              highlightVars: false,
            ),
            if (widget.nameError != null)
              T(widget.nameError!, color: p.accent, size: 11),
          ],
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Btn(
                    label: widget.active ? 'Deactivate' : 'Activate',
                    onClick: widget.onActivate,
                  ),
                  Btn(label: 'Duplicate', onClick: widget.onDuplicate),
                  Btn(label: 'Delete', onClick: widget.onDelete, danger: true),
                ],
              ),
            ),
            Btn(
              label: 'Revert',
              onClick: widget.onRevert,
              enabled: widget.dirty,
            ),
            Btn(
              label: 'Save',
              onClick: widget.onSave,
              primary: true,
              enabled: widget.dirty && widget.nameError == null,
            ),
          ],
        ),
        Row(
          spacing: 10,
          children: [
            if (!bulk)
              SizedBox(
                width: 220,
                child: Field(
                  value: filter,
                  onChange: (v) => setState(() => filter = v),
                  placeholder: 'Filter by name or value',
                  highlightVars: false,
                ),
              ),
            T(countText, color: p.muted, size: 12),
            const Spacer(),
            Btn(
              label: 'Bulk edit',
              onClick: _toggleBulk,
              primary: bulk,
              icon: Ic.edit,
            ),
          ],
        ),
        Expanded(child: bulk ? _bulkView(p) : _table(p, shown, n)),
      ],
    );
  }

  Widget _bulkView(Pal p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Expanded(
        child: AreaField(
          value: bulkText,
          onChange: (v) => setState(() => bulkText = v),
          placeholder: 'BASE_URL=https://api.example.com',
          expands: true,
        ),
      ),
      Row(
        spacing: 8,
        children: [
          Expanded(
            child: T(
              'One KEY=value per line. Lines starting with # are ignored. Secret flags are kept by name.',
              color: p.muted,
              size: 11,
            ),
          ),
          Btn(label: 'Cancel', onClick: discardBulk),
          Btn(label: 'Apply', onClick: flushBulk, primary: true),
        ],
      ),
    ],
  );

  Widget _table(Pal p, List<int> shown, int total) {
    final dups = duplicateVarNames(draft.vars);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: T(
                'No variables yet. Add one to use it as {{name}} in requests.',
                color: p.muted,
                size: 12,
              ),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: T('No variable matches the filter.', color: p.muted),
            )
          else
            Row(
              spacing: 6,
              children: [
                Expanded(
                  flex: 2,
                  child: T('VARIABLE', color: p.muted, size: 11),
                ),
                Expanded(flex: 3, child: T('VALUE', color: p.muted, size: 11)),
                const SizedBox(width: 26),
                SizedBox(
                  width: 70,
                  child: T('SECRET', color: p.muted, size: 11),
                ),
                const SizedBox(width: 26),
              ],
            ),
          for (final i in shown) _row(p, i, dups),
          Align(
            alignment: Alignment.centerLeft,
            child: Btn(
              label: 'Add variable',
              icon: Ic.add,
              onClick: () => widget.onChange(
                draft.copyWith(vars: [...draft.vars, const KV()]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Pal p, int i, Set<String> dups) {
    final kv = draft.vars[i];
    final name = kv.name.trim();
    final secret = name.isNotEmpty && draft.secrets.contains(kv.name);
    final masked = secret && !revealed.contains(i);
    final warn = name.isEmpty
        ? 'Empty name: this variable is dropped when saved'
        : dups.contains(name)
        ? 'Duplicate name'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Row(
          spacing: 6,
          children: [
            Expanded(
              flex: 2,
              child: Field(
                key: ValueKey('name$i'),
                value: kv.name,
                onChange: (v) => _setVar(i, kv.copyWith(name: v)),
                placeholder: 'Variable',
                mono: true,
                highlightVars: false,
              ),
            ),
            Expanded(
              flex: 3,
              child: Field(
                key: ValueKey('value$i'),
                value: kv.value,
                onChange: (v) => _setVar(i, kv.copyWith(value: v)),
                placeholder: 'Value',
                mono: !masked,
                password: masked,
                highlightVars: false,
              ),
            ),
            SizedBox(
              width: 26,
              child: secret
                  ? IconBtn(
                      icon: masked ? Ic.eye : Ic.eyeOff,
                      onClick: () => setState(
                        () => masked ? revealed.add(i) : revealed.remove(i),
                      ),
                    )
                  : null,
            ),
            SizedBox(
              width: 70,
              child: Row(
                spacing: 6,
                children: [
                  Check(
                    checked: secret,
                    onChange: (on) => _toggleSecret(i, on),
                  ),
                  T('secret', size: 11, color: p.muted),
                ],
              ),
            ),
            IconBtn(icon: Ic.delete, onClick: () => _removeVar(i)),
          ],
        ),
        if (warn != null) T(warn, color: p.accent, size: 11),
      ],
    );
  }
}
