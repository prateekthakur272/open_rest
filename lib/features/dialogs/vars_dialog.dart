import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/features/dialogs/vars_logic.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

const _nameW = 190.0;
const _sourceW = 190.0;
const _actionsW = 108.0;
const _maskedText = '••••••';

/// Above this many runtime variables, clearing them asks for confirmation.
const _confirmClearOver = 3;

/// Inspector of every variable that applies to a collection, with where each value comes from.
class VarsDialog extends StatefulWidget {
  const VarsDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalVars m;

  @override
  State<VarsDialog> createState() => _VarsDialogState();
}

class _VarsDialogState extends State<VarsDialog> {
  final FocusNode _editFocus = FocusNode();
  final FocusNode _newNameFocus = FocusNode();
  String _query = '';
  final Set<String> _revealed = {};
  final Set<String> _expanded = {};
  String? _editing;
  String _editText = '';
  bool _adding = false;
  bool _confirmClear = false;
  String _newName = '';
  String _newValue = '';

  AppState get state => widget.state;

  @override
  void dispose() {
    _editFocus.dispose();
    _newNameFocus.dispose();
    super.dispose();
  }

  void _close() {
    if (_confirmClear) return setState(() => _confirmClear = false);
    state.modal = null;
  }

  void _copy(String text, String what) {
    Platform.copy(text);
    state.showToast('Copied $what');
  }

  void _startEdit(String name, StateMap<String, dynamic> rt) {
    setState(() {
      _editing = name;
      _editText = runtimeText(rt[name]);
      _adding = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  void _saveEdit(StateMap<String, dynamic> rt) {
    final n = _editing;
    if (n == null) return;
    rt[n] = parseRuntimeText(_editText, rt[n]);
    setState(() => _editing = null);
  }

  void _startAdd() {
    setState(() {
      _adding = true;
      _editing = null;
      _newName = '';
      _newValue = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _newNameFocus.requestFocus();
    });
  }

  void _commitAdd(StateMap<String, dynamic> rt) {
    final n = _newName.trim();
    if (n.isEmpty) {
      state.showToast('Enter a variable name');
      return;
    }
    rt[n] = _newValue;
    setState(() => _adding = false);
  }

  void _clear(StateMap<String, dynamic> rt) {
    if (rt.length > _confirmClearOver && !_confirmClear) {
      setState(() => _confirmClear = true);
      return;
    }
    rt.clear();
    setState(() {
      _confirmClear = false;
      _editing = null;
    });
  }

  Widget _escapeScope({required VoidCallback onEsc, required Widget child}) =>
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (n, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            onEsc();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = state.collection(widget.m.collection);
    if (col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final rt = state.runtime(col.path);
    final envN = state.envName(col.path);
    Environment? env;
    for (final e in col.environments) {
      if (e.name == envN) env = e;
    }
    final genv = state.globalEnv();
    final all = collectVars(
      runtime: rt,
      env: env,
      envOverrides: envN == null ? null : EnvOverrides.get(col.path, envN),
      collectionVars: col.config.preVars,
      global: genv,
    );
    final groups = filterVars(all, _query);
    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBox(
          title: 'Variables',
          onClose: _close,
          width: 860,
          height: 560,
          actions: [
            Btn(
              label: 'Clear runtime variables',
              onClick: () => _clear(rt),
              danger: true,
              enabled: rt.isNotEmpty,
            ),
            const Spacer(),
            Btn(label: 'Close', onClick: _close, primary: true),
          ],
          content: [
            _header(p, col.name, envN, genv?.name),
            _toolbar(p, groups.length, rt),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: all.isEmpty && !_adding
                    ? _empty(p, col.path)
                    : _table(p, groups, rt, all.isEmpty),
              ),
            ),
            T(
              'Folder and request variables are resolved per request. Precedence: runtime, request, folder, environment, collection, global.',
              color: p.muted,
              size: 12,
            ),
          ],
        ),
        if (_confirmClear)
          ModalBox(
            title: 'Clear runtime variables',
            onClose: _close,
            width: 420,
            actions: [
              Btn(label: 'Cancel', onClick: _close),
              Btn(
                label: 'Clear ${rt.length} variables',
                onClick: () => _clear(rt),
                danger: true,
              ),
            ],
            content: [
              T(
                'Remove all ${rt.length} runtime variables of "${col.name}"? Scripts can set them again on the next run.',
              ),
            ],
          ),
      ],
    );
  }

  Widget _header(Pal p, String colName, String? env, String? genv) => Row(
    spacing: 8,
    children: [
      Flexible(
        child: T(
          colName,
          size: 14,
          weight: FontWeight.w600,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      _tag(
        p,
        env == null ? 'No environment' : 'Env: $env',
        _color(p, VarSource.environment),
        dim: env == null,
      ),
      _tag(
        p,
        genv == null ? 'No global environment' : 'Global: $genv',
        _color(p, VarSource.global),
        dim: genv == null,
      ),
    ],
  );

  Widget _toolbar(Pal p, int count, StateMap<String, dynamic> rt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Row(
        spacing: 10,
        children: [
          Expanded(
            child: Field(
              value: _query,
              onChange: (v) => setState(() => _query = v),
              placeholder: 'Filter by name or value',
              highlightVars: false,
            ),
          ),
          T(varCountLabel(count), color: p.muted, size: 12),
          Btn(
            label: 'Add runtime variable',
            icon: Ic.add,
            onClick: _adding
                ? () => setState(() => _adding = false)
                : _startAdd,
          ),
        ],
      ),
      if (_adding) _addRow(p, rt),
    ],
  );

  Widget _addRow(Pal p, StateMap<String, dynamic> rt) => _escapeScope(
    onEsc: () => setState(() => _adding = false),
    child: Row(
      spacing: 8,
      children: [
        SizedBox(
          width: _nameW,
          child: Field(
            value: _newName,
            onChange: (v) => _newName = v,
            placeholder: 'name',
            mono: true,
            highlightVars: false,
            focusRequester: _newNameFocus,
            onEnter: () => _commitAdd(rt),
          ),
        ),
        Expanded(
          child: Field(
            value: _newValue,
            onChange: (v) => _newValue = v,
            placeholder: 'value',
            mono: true,
            highlightVars: false,
            onEnter: () => _commitAdd(rt),
          ),
        ),
        Btn(label: 'Add', onClick: () => _commitAdd(rt), primary: true),
        IconBtn(icon: Ic.close, onClick: () => setState(() => _adding = false)),
      ],
    ),
  );

  Widget _empty(Pal p, String path) => Center(
    child: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Ico(Ic.variables, tint: p.muted, size: 36),
          T('No variables yet', size: 15, weight: FontWeight.w600),
          T(
            'No variables yet. Define some in an environment or with bru.setVar in a script.',
            color: p.muted,
            size: 12,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Btn(
            label: 'Open environments',
            icon: Ic.environments,
            onClick: () => state.modal = ModalEnvs(collection: path),
            primary: true,
          ),
        ],
      ),
    ),
  );

  Widget _table(
    Pal p,
    List<VarGroup> groups,
    StateMap<String, dynamic> rt,
    bool none,
  ) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            foregroundDecoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                const SizedBox(width: _nameW, child: SectionLabel('NAME')),
                const Expanded(child: SectionLabel('VALUE')),
                const SizedBox(width: _sourceW, child: SectionLabel('SOURCE')),
                const SizedBox(width: _actionsW),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: T(
                      none ? 'No variables' : 'No variables match "$_query"',
                      color: p.muted,
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final g in groups) ...[
                          _row(p, g.winner, rt, group: g),
                          if (_expanded.contains(g.name))
                            for (final e in g.overridden)
                              _row(p, e, rt, shadowedBy: g.winner),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _color(Pal p, VarSource s) => switch (s) {
    VarSource.runtime => p.accent,
    VarSource.environment => p.ok,
    VarSource.collection => p.syntaxKeyword,
    VarSource.global => p.muted,
  };

  Widget _tag(Pal p, String text, Color c, {bool dim = false}) {
    final col = dim ? c.withValues(alpha: 0.6) : c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: T(
        text,
        color: col,
        size: 11,
        weight: FontWeight.w600,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _row(
    Pal p,
    VarEntry e,
    StateMap<String, dynamic> rt, {
    VarGroup? group,
    VarEntry? shadowedBy,
  }) {
    final dim = shadowedBy != null;
    final isRuntime = e.source == VarSource.runtime;
    final rk = '${e.label}|${e.name}';
    final editing = isRuntime && _editing == e.name;
    final shown = !e.secret || _revealed.contains(rk);
    final over = group?.overridden.length ?? 0;
    final open = group != null && _expanded.contains(group.name);
    final textColor = dim ? p.muted.withValues(alpha: 0.7) : p.text;
    return HoverBuilder(
      builder: (ctx, hov) => Container(
        key: ValueKey('var-$rk'),
        constraints: const BoxConstraints(minHeight: 34),
        padding: EdgeInsets.only(
          left: dim ? 26 : 10,
          right: 10,
          top: 4,
          bottom: 4,
        ),
        color: hov && !dim ? p.hover : const Color(0x00000000),
        foregroundDecoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _nameW - (dim ? 16 : 0),
              child: Row(
                spacing: 4,
                children: [
                  if (over > 0)
                    IconBtn(
                      key: ValueKey('chevron-${e.name}'),
                      icon: open ? Ic.up : Ic.dropDown,
                      onClick: () => setState(
                        () => open
                            ? _expanded.remove(e.name)
                            : _expanded.add(e.name),
                      ),
                    ),
                  Expanded(
                    child: T(
                      e.name,
                      mono: true,
                      color: dim ? textColor : p.syntaxKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: editing
                  ? _editField(rt)
                  : Row(
                      spacing: 4,
                      children: [
                        Flexible(
                          child: T(
                            shown ? e.value : _maskedText,
                            mono: true,
                            color: textColor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (e.secret)
                          IconBtn(
                            key: ValueKey('reveal-$rk'),
                            icon: shown ? Ic.eyeOff : Ic.eye,
                            onClick: () => setState(
                              () => shown
                                  ? _revealed.remove(rk)
                                  : _revealed.add(rk),
                            ),
                          ),
                      ],
                    ),
            ),
            SizedBox(
              width: _sourceW,
              child: Align(
                alignment: Alignment.centerLeft,
                child: dim
                    ? T(
                        'overridden by ${shadowedBy.label}',
                        color: p.muted.withValues(alpha: 0.7),
                        size: 11,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Row(
                        spacing: 6,
                        children: [
                          Flexible(
                            child: _tag(p, e.label, _color(p, e.source)),
                          ),
                          if (over > 0) T('+$over', color: p.muted, size: 11),
                        ],
                      ),
              ),
            ),
            SizedBox(
              width: _actionsW,
              child: editing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconBtn(
                          key: const ValueKey('edit-save'),
                          icon: Ic.check,
                          color: p.ok,
                          onClick: () => _saveEdit(rt),
                        ),
                        IconBtn(
                          icon: Ic.close,
                          onClick: () => setState(() => _editing = null),
                        ),
                      ],
                    )
                  : hov
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconBtn(
                          key: ValueKey('copy-value-$rk'),
                          icon: Ic.copy,
                          onClick: () => _copy(e.value, 'value of ${e.name}'),
                        ),
                        IconBtn(
                          key: ValueKey('copy-ref-$rk'),
                          icon: Ic.code,
                          onClick: () =>
                              _copy('{{${e.name}}}', '{{${e.name}}}'),
                        ),
                        if (isRuntime && !dim) ...[
                          IconBtn(
                            key: ValueKey('edit-$rk'),
                            icon: Ic.edit,
                            onClick: () => _startEdit(e.name, rt),
                          ),
                          IconBtn(
                            key: ValueKey('delete-$rk'),
                            icon: Ic.delete,
                            color: p.err,
                            onClick: () => rt.remove(e.name),
                          ),
                        ],
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(StateMap<String, dynamic> rt) => _escapeScope(
    onEsc: () => setState(() => _editing = null),
    child: Field(
      value: _editText,
      onChange: (v) => _editText = v,
      mono: true,
      highlightVars: false,
      focusRequester: _editFocus,
      onEnter: () => _saveEdit(rt),
    ),
  );
}
