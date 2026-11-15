import 'package:open_rest/core/model/model.dart';

/// Editable copy of an environment, kept while the user switches between environments.
class EnvDraft {
  const EnvDraft({
    required this.name,
    this.vars = const [],
    this.secrets = const {},
  });

  factory EnvDraft.of(Environment e) =>
      EnvDraft(name: e.name, vars: e.vars, secrets: e.secrets);

  final String name;
  final List<KV> vars;
  final Set<String> secrets;

  EnvDraft copyWith({String? name, List<KV>? vars, Set<String>? secrets}) =>
      EnvDraft(
        name: name ?? this.name,
        vars: vars ?? this.vars,
        secrets: secrets ?? this.secrets,
      );

  /// The environment this draft saves as: trimmed name, no unnamed variables, secrets only for existing names.
  Environment toEnvironment() {
    final kept = vars.where((v) => v.name.trim().isNotEmpty).toList();
    final names = kept.map((v) => v.name).toSet();
    return Environment(
      name: name.trim(),
      vars: kept,
      secrets: secrets.where(names.contains).toSet(),
    );
  }

  /// Whether saving this draft would change [saved].
  bool differsFrom(Environment saved) =>
      toEnvironment() != EnvDraft.of(saved).toEnvironment();
}

/// Why [name] cannot be used for an environment, or null when it is fine.
/// [self] is the environment being renamed (it may keep its own name).
String? validateEnvName(
  String name,
  Iterable<String> existing, {
  String? self,
}) {
  final n = name.trim();
  if (n.isEmpty) return 'Name is required';
  if (n.contains('/') || n.contains(r'\')) {
    return r'Name cannot contain / or \';
  }
  if (n == '.' || n == '..') return 'Name is not valid';
  final lower = n.toLowerCase();
  for (final e in existing) {
    if (e != self && e.toLowerCase() == lower) {
      return 'An environment with this name already exists';
    }
  }
  return null;
}

/// [base], or [base] with a numeric suffix when taken.
String uniqueEnvName(String base, Iterable<String> existing) {
  final taken = existing.map((e) => e.toLowerCase()).toSet();
  var n = base;
  var i = 2;
  while (taken.contains(n.toLowerCase())) {
    n = '$base ${i++}';
  }
  return n;
}

/// Variable names used more than once (ignoring empty names).
Set<String> duplicateVarNames(List<KV> vars) {
  final seen = <String>{};
  final dup = <String>{};
  for (final v in vars) {
    final n = v.name.trim();
    if (n.isEmpty) continue;
    if (!seen.add(n)) dup.add(n);
  }
  return dup;
}

/// One `KEY=value` line per variable.
String serializeBulk(List<KV> vars) =>
    vars.map((v) => '${v.name}=${v.value}').join('\n');

/// Parses `KEY=value` lines. Blank lines and `#` comments are skipped; a line without `=` is a name with an empty value.
List<KV> parseBulk(String text) {
  final out = <KV>[];
  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = line.indexOf('=');
    out.add(
      i < 0
          ? KV(name: t)
          : KV(name: line.substring(0, i).trim(), value: line.substring(i + 1)),
    );
  }
  return out;
}

/// Secret flags that still apply to [vars] by name.
Set<String> secretsFor(Set<String> secrets, List<KV> vars) {
  final names = vars.map((v) => v.name).toSet();
  return secrets.where(names.contains).toSet();
}
