import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/utils/json.dart';

/// Where a variable value comes from, listed from highest to lowest precedence.
enum VarSource { runtime, environment, collection, global }

/// One definition of a variable in one source.
class VarEntry {
  const VarEntry({
    required this.name,
    required this.value,
    required this.source,
    required this.label,
    this.secret = false,
  });

  final String name;
  final String value;
  final VarSource source;

  /// Display name of the source, e.g. `Environment: dev`.
  final String label;
  final bool secret;
}

/// All definitions of one variable name; the first entry is the one that wins.
class VarGroup {
  const VarGroup(this.name, this.entries);

  final String name;
  final List<VarEntry> entries;

  VarEntry get winner => entries.first;
  List<VarEntry> get overridden => entries.sublist(1);
}

/// Text form of a runtime value, the way it is substituted into requests.
String runtimeText(dynamic v) =>
    v == null ? '' : (v is String ? v : Json.stringify(v));

/// Parses text typed for a runtime variable that currently holds [old]; strings stay strings.
dynamic parseRuntimeText(String text, dynamic old) =>
    old is String || old == null ? text : (Json.tryParse(text) ?? text);

/// Collects the variables of one collection from every source a request resolves, grouped by name.
///
/// Precedence: runtime, environment (with script overrides), collection, global environment.
/// Disabled variables are skipped. Groups are sorted by name.
List<VarGroup> collectVars({
  Map<String, dynamic> runtime = const {},
  Environment? env,
  Map<String, String>? envOverrides,
  List<KV> collectionVars = const [],
  Environment? global,
}) {
  final byName = <String, List<VarEntry>>{};
  void add(VarEntry e) => (byName[e.name] ??= []).add(e);

  for (final k in runtime.keys) {
    add(
      VarEntry(
        name: k,
        value: runtimeText(runtime[k]),
        source: VarSource.runtime,
        label: 'Runtime',
      ),
    );
  }
  if (env != null) {
    final vals = <String, String>{
      for (final v in env.vars.where((v) => v.enabled)) v.name: v.value,
      ...?envOverrides,
    };
    vals.forEach((k, v) {
      add(
        VarEntry(
          name: k,
          value: v,
          source: VarSource.environment,
          label: 'Environment: ${env.name}',
          secret: env.secrets.contains(k),
        ),
      );
    });
  }
  for (final v in collectionVars.where((v) => v.enabled)) {
    if (v.name.isEmpty) continue;
    final list = byName[v.name] ??= [];
    list.removeWhere((e) => e.source == VarSource.collection);
    list.add(
      VarEntry(
        name: v.name,
        value: v.value,
        source: VarSource.collection,
        label: 'Collection',
      ),
    );
  }
  if (global != null) {
    final g = <String, String>{
      for (final v in global.vars.where((v) => v.enabled)) v.name: v.value,
    };
    g.forEach((k, v) {
      add(
        VarEntry(
          name: k,
          value: v,
          source: VarSource.global,
          label: 'Global: ${global.name}',
          secret: global.secrets.contains(k),
        ),
      );
    });
  }
  final out = [
    for (final e in byName.entries)
      if (e.key.isNotEmpty && e.value.isNotEmpty)
        VarGroup(
          e.key,
          e.value.toList()
            ..sort((a, b) => a.source.index.compareTo(b.source.index)),
        ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// Groups whose name, or any non-secret value, contains [query] (case-insensitive).
List<VarGroup> filterVars(List<VarGroup> groups, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return groups;
  return [
    for (final g in groups)
      if (g.name.toLowerCase().contains(q) ||
          g.entries.any((e) => !e.secret && e.value.toLowerCase().contains(q)))
        g,
  ];
}

/// `1 variable` / `N variables`.
String varCountLabel(int n) => '$n variable${n == 1 ? '' : 's'}';
