import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/env_editor.dart';
import 'package:open_rest/features/dialogs/env_logic.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// A confirmation shown over the dialog (kept inside it so drafts survive).
class _Ask {
  const _Ask(this.title, this.message, this.buttons);
  final String title;
  final String message;
  final List<Btn> buttons;
}

/// Dialog for creating and managing environments and their variables.
class EnvsDialog extends StatefulWidget {
  const EnvsDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalEnvs m;

  @override
  State<EnvsDialog> createState() => _EnvsDialogState();
}

class _EnvsDialogState extends State<EnvsDialog> {
  static const _global = 'Global';

  /// Unsaved edits per scope (collection path, null for global) and saved environment name.
  final Map<String?, Map<String, EnvDraft>> _drafts = {};
  final Map<String?, String?> _sel = {};
  final GlobalKey<EnvEditorState> _editor = GlobalKey();
  final FocusNode _newFocus = FocusNode();
  String? _lastCol;
  bool _creating = false;
  bool _tried = false;
  bool _copy = false;
  String _newName = '';
  _Ask? _ask;

  AppState get state => widget.state;
  String? get _key => widget.m.collection;

  @override
  void initState() {
    super.initState();
    _lastCol = _key;
  }

  @override
  void didUpdateWidget(EnvsDialog old) {
    super.didUpdateWidget(old);
    if (old.m.collection != widget.m.collection) {
      _creating = false;
      _newName = '';
      _ask = null;
      _lastCol ??= widget.m.collection;
      if (widget.m.collection != null) _lastCol = widget.m.collection;
    }
  }

  @override
  void dispose() {
    _newFocus.dispose();
    super.dispose();
  }

  List<Environment> _envsIn(String? key) => key == null
      ? state.globalEnvs
      : (state.collection(key)?.environments ?? const []);
  List<Environment> get _envs => _envsIn(_key);
  String? _activeIn(String? key) =>
      key == null ? state.globalEnvName() : state.envName(key);

  Environment? _find(String? key, String? name) {
    for (final e in _envsIn(key)) {
      if (e.name == name) return e;
    }
    return null;
  }

  Environment? get _env {
    final s = _sel[_key];
    final chosen = _find(_key, s);
    if (chosen != null) return chosen;
    final act = _find(_key, _activeIn(_key));
    return act ?? (_envs.isEmpty ? null : _envs.first);
  }

  EnvDraft _draftOf(Environment e) => _drafts[_key]?[e.name] ?? EnvDraft.of(e);

  bool _isDirty(String? key, Environment e) {
    final d = _drafts[key]?[e.name];
    return d != null && d.differsFrom(e);
  }

  /// Dirty drafts as (scope, saved environment) pairs.
  List<(String?, Environment)> _dirty([String? only, bool all = true]) => [
    for (final key in _drafts.keys)
      if (all || key == only)
        for (final e in _envsIn(key))
          if (_isDirty(key, e)) (key, e),
  ];

  void _flush() => _editor.currentState?.flushBulk();

  void _saveIn(String? key, Environment env, String? old) => key == null
      ? state.saveGlobalEnvironment(env, old)
      : state.saveEnvironment(key, env, old);

  void _select(String name) {
    _flush();
    setState(() {
      _sel[_key] = name;
      _creating = false;
    });
  }

  void _setDraft(Environment e, EnvDraft d) =>
      setState(() => (_drafts[_key] ??= {})[e.name] = d);

  void _save() {
    if (_ask != null) return;
    _flush();
    final e = _env;
    if (e == null) return;
    final d = _draftOf(e);
    if (!d.differsFrom(e)) return;
    final err = validateEnvName(d.name, _envs.map((x) => x.name), self: e.name);
    if (err != null) {
      state.showToast(err);
      return;
    }
    final out = d.toEnvironment();
    _saveIn(_key, out, e.name);
    setState(() {
      _drafts[_key]?.remove(e.name);
      _sel[_key] = out.name;
    });
    state.showToast('Environment saved');
  }

  void _revert(Environment e) {
    _editor.currentState?.discardBulk();
    setState(() => _drafts[_key]?.remove(e.name));
  }

  void _activate(Environment e, bool on) {
    final n = on ? e.name : null;
    _key == null ? state.setGlobalEnv(n) : state.setEnv(_key!, n);
    setState(() {});
  }

  void _duplicate(Environment e) {
    _flush();
    final out = _draftOf(e)
        .copyWith(
          name: uniqueEnvName('${e.name} copy', _envs.map((x) => x.name)),
        )
        .toEnvironment();
    _saveIn(_key, out, null);
    setState(() => _sel[_key] = out.name);
  }

  void _confirmDelete(Environment e) => setState(
    () => _ask = _Ask(
      'Delete environment',
      'Delete "${e.name}"? This removes its file and cannot be undone.'
          '${_isDirty(_key, e) ? ' Its unsaved changes will be lost too.' : ''}',
      [
        Btn(label: 'Cancel', onClick: _dismiss),
        Btn(label: 'Delete', onClick: () => _delete(e), primary: true),
      ],
    ),
  );

  void _delete(Environment e) {
    final names = _envs.map((x) => x.name).toList();
    final wasSel = _env?.name == e.name;
    final i = names.indexOf(e.name);
    String? next;
    if (names.length > 1) next = names[i + 1 < names.length ? i + 1 : i - 1];
    _key == null
        ? state.deleteGlobalEnvironment(e.name)
        : state.deleteEnvironment(_key!, e.name);
    setState(() {
      _ask = null;
      _drafts[_key]?.remove(e.name);
      if (wasSel) _sel[_key] = next;
    });
  }

  void _dismiss() => setState(() => _ask = null);

  void _startCreate() {
    setState(() {
      _creating = true;
      _tried = false;
      _copy = false;
      _newName = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _newFocus.requestFocus();
    });
  }

  void _cancelCreate() => setState(() => _creating = false);

  String? get _newError => (_newName.isEmpty && !_tried)
      ? null
      : validateEnvName(_newName, _envs.map((x) => x.name));

  void _create() {
    _flush();
    setState(() => _tried = true);
    if (validateEnvName(_newName, _envs.map((x) => x.name)) != null) return;
    final src = _copy ? _env : null;
    final base = src == null ? const EnvDraft(name: '') : _draftOf(src);
    final out = base.copyWith(name: _newName).toEnvironment();
    _saveIn(_key, out, null);
    setState(() {
      _creating = false;
      _sel[_key] = out.name;
    });
  }

  void _close() {
    if (_ask != null) return _dismiss();
    _flush();
    final dirty = _dirty();
    if (dirty.isEmpty) {
      state.modal = null;
      return;
    }
    setState(
      () => _ask = _Ask(
        'Unsaved changes',
        '${dirty.length} environment${dirty.length == 1 ? ' has' : 's have'} '
            'unsaved changes: ${dirty.map((d) => d.$2.name).join(', ')}.',
        [
          Btn(label: 'Cancel', onClick: _dismiss),
          Btn(
            label: 'Discard',
            onClick: () => state.modal = null,
            danger: true,
          ),
          Btn(label: 'Save all', onClick: _saveAll, primary: true),
        ],
      ),
    );
  }

  void _saveAll() {
    final dirty = _dirty();
    for (final (key, e) in dirty) {
      final d = _drafts[key]![e.name]!;
      final err = validateEnvName(
        d.name,
        _envsIn(key).map((x) => x.name),
        self: e.name,
      );
      if (err != null) {
        setState(() {
          _ask = null;
          if (key == _key) _sel[key] = e.name;
        });
        state.showToast('"${e.name}": $err');
        return;
      }
    }
    for (final (key, e) in dirty) {
      _saveIn(key, _drafts[key]![e.name]!.toEnvironment(), e.name);
    }
    state.modal = null;
    state.showToast('Environments saved');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final hw = HardwareKeyboard.instance;
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyS &&
        (hw.isMetaPressed || hw.isControlPressed)) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _switchScope(String tab, String? colPath) {
    _flush();
    state.modal = tab == _global
        ? const ModalEnvs()
        : ModalEnvs(collection: colPath);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final key = _key;
    final col = key == null ? null : state.collection(key);
    if (key != null && col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final colPath = key ?? _lastCol ?? state.currentCollection?.path;
    final colName = colPath == null ? null : state.collection(colPath)?.name;
    final tabs = [_global, if (colName != null) 'Collection: $colName'];
    final env = _env;
    final ask = _ask;
    return Focus(
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBox(
            title: 'Environments',
            onClose: _close,
            width: 900,
            height: 600,
            actions: [Btn(label: 'Close', onClick: _close)],
            content: [
              SizedBox(
                width: double.infinity,
                child: Tabs(
                  items: tabs,
                  selected: key == null ? _global : tabs.last,
                  onSelect: (t) => _switchScope(t, colPath),
                  badge: (t) =>
                      _dirty(t == _global ? null : colPath, false).isEmpty
                      ? null
                      : '●',
                ),
              ),
              T(
                key == null
                    ? 'Shared by every collection. Lowest precedence: collection, folder and request variables override them.'
                    : 'Only for this collection. Overrides global environment variables with the same name.',
                color: p.muted,
                size: 12,
              ),
              Expanded(
                child: env == null
                    ? _empty(p)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 14,
                        children: [
                          SizedBox(width: 250, child: _list(p, env)),
                          Expanded(child: _detail(env)),
                        ],
                      ),
              ),
              T(
                '${key == null ? 'Global environments are stored in ~/.openrest/environments. ' : ''}'
                'Secret values are kept out of the YAML file (stored in ~/.openrest). Use {{name}} anywhere: URL, headers, body, auth.',
                color: p.muted,
                size: 12,
              ),
            ],
          ),
          if (ask != null)
            ModalBox(
              title: ask.title,
              onClose: _dismiss,
              width: 420,
              actions: ask.buttons,
              content: [T(ask.message)],
            ),
        ],
      ),
    );
  }

  Widget _detail(Environment env) {
    final d = _draftOf(env);
    return EnvEditor(
      key: ValueKey('$_key/${env.name}'),
      draft: d,
      dirty: d.differsFrom(env),
      nameError: validateEnvName(
        d.name,
        _envs.map((x) => x.name),
        self: env.name,
      ),
      active: _activeIn(_key) == env.name,
      onChange: (v) => _setDraft(env, v),
      onActivate: () => _activate(env, _activeIn(_key) != env.name),
      onDuplicate: () => _duplicate(env),
      onDelete: () => _confirmDelete(env),
      onSave: _save,
      onRevert: () => _revert(env),
    );
  }

  Widget _empty(Pal p) => Center(
    child: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Ico(Ic.environments, tint: p.muted, size: 36),
          T('No environments yet', size: 15, weight: FontWeight.w600),
          T(
            'An environment is a named set of variables, like {{baseUrl}}, that you can switch between.',
            color: p.muted,
            size: 12,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          if (_creating)
            _newForm(p)
          else
            Btn(
              label: 'Create your first environment',
              onClick: _startCreate,
              primary: true,
            ),
        ],
      ),
    ),
  );

  Widget _list(Pal p, Environment sel) {
    final active = _activeIn(_key);
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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in _envs)
                    _row(
                      p,
                      e,
                      selected: e.name == sel.name,
                      active: e.name == active,
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            foregroundDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: _creating
                ? _newForm(p, sel: sel)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Btn(
                      label: '+ New environment',
                      onClick: _startCreate,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    Pal p,
    Environment e, {
    required bool selected,
    required bool active,
  }) {
    final dirty = _isDirty(_key, e);
    final count = _draftOf(e).toEnvironment().vars.length;
    return Clickable(
      onClick: () => _select(e.name),
      child: HoverBuilder(
        builder: (ctx, hov) => Container(
          color: selected ? p.selected : const Color(0x00000000),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            spacing: 6,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T(
                      e.name,
                      weight: selected ? FontWeight.w600 : null,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    T(
                      '$count variable${count == 1 ? '' : 's'}',
                      color: p.muted,
                      size: 11,
                    ),
                  ],
                ),
              ),
              if (dirty)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: p.ok.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: T(
                    'active',
                    color: p.ok,
                    size: 11,
                    weight: FontWeight.w600,
                  ),
                ),
              SizedBox(
                width: 26,
                child: hov || selected
                    ? IconBtn(
                        key: ValueKey('del-${e.name}'),
                        icon: Ic.delete,
                        color: p.err,
                        onClick: () => _confirmDelete(e),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _newForm(Pal p, {Environment? sel}) {
    final err = _newError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (n, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.escape) {
              _cancelCreate();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Field(
            value: _newName,
            onChange: (v) => setState(() => _newName = v),
            placeholder: 'Environment name',
            highlightVars: false,
            focusRequester: _newFocus,
            onEnter: _create,
          ),
        ),
        if (err != null) T(err, color: p.accent, size: 11),
        if (sel != null)
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: _choice(p, 'Start empty', !_copy, () {
                  setState(() => _copy = false);
                }),
              ),
              Expanded(
                child: _choice(p, 'Copy from ${sel.name}', _copy, () {
                  setState(() => _copy = true);
                }),
              ),
            ],
          ),
        Row(
          spacing: 6,
          children: [
            Expanded(
              child: T('Enter creates, Esc cancels', color: p.muted, size: 11),
            ),
            if (sel != null) IconBtn(icon: Ic.close, onClick: _cancelCreate),
          ],
        ),
      ],
    );
  }

  Widget _choice(Pal p, String label, bool on, VoidCallback onTap) => Clickable(
    onClick: onTap,
    borderRadius: BorderRadius.circular(5),
    child: Container(
      height: 26,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: on ? p.selected : const Color(0x00000000),
        borderRadius: BorderRadius.circular(5),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: on ? p.accent : p.border),
      ),
      child: T(
        label,
        size: 12,
        color: on ? p.text : p.muted,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
