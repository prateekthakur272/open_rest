import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:open_rest/components/modifiers.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/theme/theme.dart';

/// Dialog for managing environments and their variables.
class EnvsDialog extends StatefulWidget {
  const EnvsDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalEnvs m;

  @override
  State<EnvsDialog> createState() => _EnvsDialogState();
}

class _EnvsDialogState extends State<EnvsDialog> {
  String? selName;
  String name = '';
  List<KV> vars = const [];
  Set<String> secrets = const {};

  AppState get state => widget.state;
  Collection? get col => widget.m.collection == null
      ? null
      : state.collection(widget.m.collection!);
  List<Environment> get envs =>
      col == null ? state.globalEnvs : col!.environments;
  String? get activeName =>
      col == null ? state.globalEnvName() : state.envName(col!.path);
  Environment? get env {
    for (final e in envs) {
      if (e.name == selName) return e;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _reset(activeName ?? (envs.isEmpty ? null : envs.first.name));
  }

  @override
  void didUpdateWidget(EnvsDialog old) {
    super.didUpdateWidget(old);
    if (old.m.collection != widget.m.collection) {
      _reset(activeName ?? (envs.isEmpty ? null : envs.first.name));
    }
  }

  /// `remember(selName, m.collection)`: choosing another environment reloads the editable copy.
  void _reset(String? sel) {
    selName = sel;
    final e = env;
    name = e?.name ?? '';
    vars = e?.vars ?? const [];
    secrets = e?.secrets ?? const {};
  }

  void activateEnv(String? n) =>
      col == null ? state.setGlobalEnv(n) : state.setEnv(col!.path, n);
  void save(Environment e, String? old) => col == null
      ? state.saveGlobalEnvironment(e, old)
      : state.saveEnvironment(col!.path, e, old);
  void delete(String n) => col == null
      ? state.deleteGlobalEnvironment(n)
      : state.deleteEnvironment(col!.path, n);
  String uniqueName(String base) {
    var n = base;
    var i = 2;
    while (envs.any((e) => e.name == n)) {
      n = '$base ${i++}';
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (widget.m.collection != null && col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final isGlobal = col == null;
    final active = activeName;
    final e = env;
    final changed =
        e != null &&
        (name.trim() != e.name ||
            !listEquals(
              vars.where((v) => v.name.trim().isNotEmpty).toList(),
              e.vars,
            ) ||
            !setEquals(
              secrets.where((s) => vars.any((v) => v.name == s)).toSet(),
              e.secrets,
            ));

    return ModalBox(
      title: col == null
          ? 'Environments — Global'
          : 'Environments — ${col!.name}',
      onClose: () => state.modal = null,
      width: 860,
      height: 560,
      actions: [
        Btn(label: 'Close', onClick: () => state.modal = null),
        if (e != null)
          Btn(
            label: 'Save',
            onClick: () {
              save(
                Environment(
                  name: name.trim(),
                  vars: vars.where((v) => v.name.trim().isNotEmpty).toList(),
                  secrets: secrets
                      .where((s) => vars.any((v) => v.name == s))
                      .toSet(),
                ),
                e.name,
              );
              if (selName != name.trim()) {
                setState(() => _reset(name.trim()));
              }
              state.showToast('Environment saved');
            },
            primary: true,
          ),
      ],
      content: [
        Builder(
          builder: (context) {
            final current = state.currentCollection;
            return Row(
              spacing: 8,
              children: [
                Btn(
                  label: 'Global',
                  onClick: () => state.modal = const ModalEnvs(),
                  primary: isGlobal,
                ),
                if (current != null)
                  Btn(
                    label: 'Collection: ${current.name}',
                    onClick: () =>
                        state.modal = ModalEnvs(collection: current.path),
                    primary: !isGlobal,
                  ),
                Expanded(
                  child: T(
                    isGlobal
                        ? 'Shared by every collection. Lowest precedence — collection, folder and request variables override them.'
                        : 'Only for this collection. Overrides global environment variables with the same name.',
                    color: p.muted,
                    size: 12,
                  ),
                ),
              ],
            );
          },
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final en in envs)
                              Clickable(
                                onClick: () => setState(() => _reset(en.name)),
                                cursor: SystemMouseCursors.basic,
                                child: Container(
                                  color: en.name == selName
                                      ? p.selected
                                      : const Color(0x00000000),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: T(
                                          en.name,
                                          weight: en.name == active
                                              ? FontWeight.w700
                                              : null,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (en.name == active)
                                        T('●', color: p.ok, size: 10),
                                    ],
                                  ),
                                ),
                              ),
                            if (envs.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: T(
                                  'No ${isGlobal ? 'global ' : ''}environments yet.',
                                  color: p.muted,
                                  size: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Btn(
                      label: '+ New Environment',
                      onClick: () {
                        final n = uniqueName('New Environment');
                        save(Environment(name: n), null);
                        setState(() => _reset(n));
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: e == null
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: T(
                          'No environment selected. Create one to define variables like {{baseUrl}}.',
                          color: p.muted,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          Row(
                            spacing: 8,
                            children: [
                              Expanded(
                                child: Field(
                                  value: name,
                                  onChange: (v) => setState(() => name = v),
                                  placeholder: 'Environment name',
                                  highlightVars: false,
                                ),
                              ),
                              if (e.name == active)
                                Btn(
                                  label: 'Deactivate',
                                  onClick: () => activateEnv(null),
                                )
                              else
                                Btn(
                                  label: 'Activate',
                                  onClick: () => activateEnv(e.name),
                                ),
                              Btn(
                                label: 'Clone',
                                onClick: () {
                                  final n = uniqueName('${e.name} copy');
                                  save(e.copyWith(name: n), null);
                                  setState(() => _reset(n));
                                },
                              ),
                              Btn(
                                label: 'Delete',
                                onClick: () {
                                  String? next;
                                  for (final x in envs) {
                                    if (x.name != e.name) {
                                      next = x.name;
                                      break;
                                    }
                                  }
                                  delete(e.name);
                                  setState(() => _reset(next));
                                },
                                danger: true,
                              ),
                            ],
                          ),
                          if (changed)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: T(
                                'Unsaved changes',
                                color: p.accent,
                                size: 11,
                              ),
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: KVTable(
                                items: vars,
                                onChange: (v) => setState(() => vars = v),
                                keyHint: 'Variable',
                                valueHint: 'Value',
                                extra: (ctx, _, kv) => Row(
                                  spacing: 4,
                                  children: [
                                    Check(
                                      checked:
                                          secrets.contains(kv.name) &&
                                          kv.name.trim().isNotEmpty,
                                      onChange: (on) => setState(
                                        () => secrets = on
                                            ? {...secrets, kv.name}
                                            : (Set.of(secrets)
                                                ..remove(kv.name)),
                                      ),
                                    ),
                                    T('secret', size: 11, color: p.muted),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        T(
          '${isGlobal ? 'Global environments are stored in ~/.openrest/environments. ' : ''}'
          'Secret values are kept out of the YAML file (stored in ~/.openrest). Use {{name}} anywhere: URL, headers, body, auth.',
          color: p.muted,
          size: 12,
        ),
      ],
    );
  }
}

/// Dialog listing variables available to the current request.
class VarsDialog extends StatelessWidget {
  const VarsDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalVars m;

  Widget _row(Pal p, String k, String v, {Color? keyColor}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 200,
        child: T(k, mono: true, color: keyColor ?? p.syntaxKey),
      ),
      Expanded(child: T(v, mono: true)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = state.collection(m.collection);
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
    final rtKeys = rt.keys.toList()..sort();
    return ModalBox(
      title: 'Variables — ${col.name}',
      onClose: () => state.modal = null,
      width: 640,
      height: 520,
      actions: [
        Btn(
          label: 'Clear Runtime Variables',
          onClick: () => rt.clear(),
          danger: true,
        ),
        Btn(label: 'Close', onClick: () => state.modal = null, primary: true),
      ],
      content: [
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  const SectionLabel(
                    'RUNTIME (set by scripts / post-response vars)',
                  ),
                  if (rt.isEmpty) T('none', color: p.muted),
                  for (final k in rtKeys) _row(p, k, Json.str(rt[k]) ?? 'null'),
                  const SizedBox(height: 8),
                  SectionLabel('GLOBAL ENVIRONMENT: ${genv?.name ?? 'None'}'),
                  if (genv != null)
                    for (final v in genv.vars)
                      _row(
                        p,
                        v.name,
                        genv.secrets.contains(v.name) ? '••••••' : v.value,
                      ),
                  const SizedBox(height: 8),
                  SectionLabel('ENVIRONMENT: ${envN ?? 'No Environment'}'),
                  if (env != null)
                    for (final v in env.vars)
                      _row(
                        p,
                        v.name,
                        env.secrets.contains(v.name) ? '••••••' : v.value,
                      ),
                  const SizedBox(height: 8),
                  const SectionLabel('COLLECTION'),
                  for (final v in col.config.preVars) _row(p, v.name, v.value),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
