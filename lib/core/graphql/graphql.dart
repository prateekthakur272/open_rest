/// GraphQL helpers: operation parsing, query formatting, introspection and schema model.
library;

/// One operation of a GraphQL document.
class GqlOperation {
  const GqlOperation(this.type, this.name);

  /// `query`, `mutation` or `subscription`.
  final String type;

  /// Null for an anonymous operation.
  final String? name;

  String get label => name ?? '($type)';
}

/// Replaces comments and string contents with spaces so structure scans ignore them (length is kept).
String _blank(String q) {
  final sb = StringBuffer();
  var i = 0;
  while (i < q.length) {
    final c = q[i];
    if (c == '#') {
      while (i < q.length && q[i] != '\n') {
        sb.write(' ');
        i++;
      }
    } else if (q.startsWith('"""', i)) {
      sb.write('   ');
      i += 3;
      while (i < q.length && !q.startsWith('"""', i)) {
        sb.write(q[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < q.length) {
        sb.write('   ');
        i += 3;
      }
    } else if (c == '"') {
      sb.write('"');
      i++;
      while (i < q.length && q[i] != '"' && q[i] != '\n') {
        if (q[i] == r'\' && i + 1 < q.length) {
          sb.write('  ');
          i += 2;
        } else {
          sb.write(' ');
          i++;
        }
      }
      if (i < q.length && q[i] == '"') {
        sb.write('"');
        i++;
      }
    } else {
      sb.write(c);
      i++;
    }
  }
  return sb.toString();
}

/// Index just past the `}` matching the `{` at [open] (end of [src] when unbalanced).
int _skipBlock(String src, int open) {
  var d = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') d++;
    if (src[i] == '}' && --d == 0) return i + 1;
  }
  return src.length;
}

/// Index of the first `{` at or after [from] that is outside parentheses (-1 when none).
int _selectionStart(String src, int from) {
  var d = 0;
  for (var i = from; i < src.length; i++) {
    final c = src[i];
    if (c == '(') d++;
    if (c == ')') d--;
    if (c == '{' && d <= 0) return i;
  }
  return -1;
}

/// Operations declared at the top level of [query] (anonymous `{ ... }` shorthand counts as a query).
List<GqlOperation> parseOperations(String query) {
  final src = _blank(query);
  final out = <GqlOperation>[];
  final word = RegExp(r'[A-Za-z_]\w*');
  var i = 0;
  while (i < src.length) {
    if (src[i] == '{') {
      out.add(const GqlOperation('query', null));
      i = _skipBlock(src, i);
      continue;
    }
    final m = word.matchAsPrefix(src, i);
    if (m == null) {
      i++;
      continue;
    }
    final kw = m.group(0)!;
    i = m.end;
    if (kw == 'query' || kw == 'mutation' || kw == 'subscription') {
      final name = RegExp(r'\s*([A-Za-z_]\w*)').matchAsPrefix(src, i);
      out.add(GqlOperation(kw, name?.group(1)));
      final open = _selectionStart(src, i);
      i = open < 0 ? src.length : _skipBlock(src, open);
    } else if (kw == 'fragment' || kw == 'type' || kw == 'input') {
      final open = _selectionStart(src, i);
      i = open < 0 ? src.length : _skipBlock(src, open);
    }
  }
  return out;
}

/// Re-indents [query] by its brace and parenthesis nesting (two spaces) and trims blank-line runs.
String prettifyQuery(String query) {
  final lines = query.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  var depth = 0;
  var blank = 0;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      if (++blank == 1 && out.isNotEmpty) out.add('');
      continue;
    }
    blank = 0;
    final s = _blank(line);
    final leadClose = RegExp(r'^[}\])]+').stringMatch(s)?.length ?? 0;
    final open = RegExp(r'[{(\[]').allMatches(s).length;
    final close = RegExp(r'[})\]]').allMatches(s).length;
    final indent = (depth - leadClose).clamp(0, 1 << 20);
    out.add('${'  ' * indent}$line');
    depth = (depth + open - close).clamp(0, 1 << 20);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

/// The standard introspection query.
const String introspectionQuery = r'''
query IntrospectionQuery {
  __schema {
    queryType { name }
    mutationType { name }
    subscriptionType { name }
    types {
      kind name description
      fields(includeDeprecated: true) {
        name description
        args { name description type { ...TypeRef } defaultValue }
        type { ...TypeRef }
        isDeprecated
      }
      inputFields { name description type { ...TypeRef } defaultValue }
      enumValues(includeDeprecated: true) { name description isDeprecated }
    }
  }
}
fragment TypeRef on __Type {
  kind name
  ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }
}
''';

class GqlArg {
  const GqlArg(this.name, this.type, {this.description = ''});
  final String name;

  /// Rendered type, e.g. `[String!]!`.
  final String type;
  final String description;

  bool get required => type.endsWith('!');
}

class GqlField {
  const GqlField(
    this.name,
    this.type,
    this.typeName, {
    this.args = const [],
    this.description = '',
    this.deprecated = false,
  });
  final String name;
  final String type;

  /// Named type with list / non-null wrappers removed.
  final String typeName;
  final List<GqlArg> args;
  final String description;
  final bool deprecated;
}

class GqlType {
  const GqlType(
    this.name,
    this.kind, {
    this.description = '',
    this.fields = const [],
    this.inputFields = const [],
    this.enumValues = const [],
  });
  final String name;

  /// `OBJECT`, `INTERFACE`, `INPUT_OBJECT`, `ENUM`, `SCALAR`, `UNION`.
  final String kind;
  final String description;
  final List<GqlField> fields;
  final List<GqlArg> inputFields;
  final List<String> enumValues;

  bool get isLeaf => kind == 'SCALAR' || kind == 'ENUM';
}

/// A parsed introspection result.
class GqlSchema {
  const GqlSchema(this.types, this.query, this.mutation, this.subscription);

  final Map<String, GqlType> types;
  final String? query;
  final String? mutation;
  final String? subscription;

  GqlType? get queryType => query == null ? null : types[query];
  GqlType? get mutationType => mutation == null ? null : types[mutation];
  GqlType? get subscriptionType =>
      subscription == null ? null : types[subscription];

  /// User-facing types (introspection types hidden), sorted by name.
  List<GqlType> get visibleTypes =>
      types.values.where((t) => !t.name.startsWith('__')).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  static String _ref(dynamic t) {
    if (t is! Map) return '';
    switch (t['kind']) {
      case 'NON_NULL':
        return '${_ref(t['ofType'])}!';
      case 'LIST':
        return '[${_ref(t['ofType'])}]';
      default:
        return '${t['name'] ?? ''}';
    }
  }

  static String _named(dynamic t) {
    var cur = t;
    while (cur is Map && cur['name'] == null && cur['ofType'] != null) {
      cur = cur['ofType'];
    }
    return cur is Map ? '${cur['name'] ?? ''}' : '';
  }

  static List<GqlArg> _args(dynamic v) => [
    if (v is List)
      for (final a in v.whereType<Map>())
        GqlArg(
          '${a['name']}',
          _ref(a['type']),
          description: '${a['description'] ?? ''}',
        ),
  ];

  /// Parses a response body (`{data: {__schema: ...}}` or the bare `__schema` map); null when it is not a schema.
  static GqlSchema? parse(dynamic json) {
    dynamic s = json;
    if (s is Map && s['data'] is Map) s = s['data'];
    if (s is Map && s['__schema'] is Map) s = s['__schema'];
    if (s is! Map || s['types'] is! List) return null;
    final types = <String, GqlType>{};
    for (final t in (s['types'] as List).whereType<Map>()) {
      final name = '${t['name'] ?? ''}';
      if (name.isEmpty) continue;
      types[name] = GqlType(
        name,
        '${t['kind']}',
        description: '${t['description'] ?? ''}',
        fields: [
          if (t['fields'] is List)
            for (final f in (t['fields'] as List).whereType<Map>())
              GqlField(
                '${f['name']}',
                _ref(f['type']),
                _named(f['type']),
                args: _args(f['args']),
                description: '${f['description'] ?? ''}',
                deprecated: f['isDeprecated'] == true,
              ),
        ],
        inputFields: _args(t['inputFields']),
        enumValues: [
          if (t['enumValues'] is List)
            for (final e in (t['enumValues'] as List).whereType<Map>())
              '${e['name']}',
        ],
      );
    }
    String? root(String k) => s[k] is Map ? s[k]['name'] as String? : null;
    return GqlSchema(
      types,
      root('queryType'),
      root('mutationType'),
      root('subscriptionType'),
    );
  }

  /// Text to insert for [f]: its name, required arguments and, for object types, a few leaf fields.
  String skeleton(GqlField f, {String indent = ''}) {
    final req = f.args.where((a) => a.required).toList();
    final args = req.isEmpty
        ? ''
        : '(${req.map((a) => '${a.name}: \$${a.name}').join(', ')})';
    final t = types[f.typeName];
    if (t == null || t.isLeaf || t.fields.isEmpty) return '${f.name}$args';
    final leaves = t.fields
        .where((c) => (types[c.typeName]?.isLeaf ?? false) && c.args.isEmpty)
        .take(3)
        .map((c) => c.name)
        .toList();
    final inner = leaves.isEmpty ? ['__typename'] : leaves;
    return '${f.name}$args {\n${inner.map((n) => '$indent  $n').join('\n')}\n$indent}';
  }
}

/// The `errors` array of a GraphQL response body, as readable one-line messages (empty when none).
List<String> graphqlErrors(dynamic body) {
  if (body is! Map || body['errors'] is! List) return const [];
  return [
    for (final e in (body['errors'] as List))
      if (e is Map)
        () {
          final loc = e['locations'];
          final at = loc is List && loc.isNotEmpty && loc.first is Map
              ? ' (line ${loc.first['line']}, col ${loc.first['column']})'
              : '';
          final path = e['path'] is List && (e['path'] as List).isNotEmpty
              ? ' at ${(e['path'] as List).join('.')}'
              : '';
          return '${e['message'] ?? 'Unknown error'}$at$path';
        }()
      else
        '$e',
  ];
}

/// Adds [snippet] (one field selection, possibly multi-line) to [query].
///
/// An empty query becomes `<root> { snippet }`; otherwise the snippet is appended to the last top-level
/// selection set. [root] is `query`, `mutation` or `subscription`.
String insertField(String query, String snippet, {String root = 'query'}) {
  String indent(String s) => s.split('\n').map((l) => '  $l').join('\n');
  if (query.trim().isEmpty) return '$root {\n${indent(snippet)}\n}\n';
  final blank = _blank(query);
  final close = blank.lastIndexOf('}');
  if (close < 0) return '$query\n$root {\n${indent(snippet)}\n}\n';
  final head = query.substring(0, close).trimRight();
  return '$head\n${indent(snippet)}\n${query.substring(close)}';
}
