// ignore_for_file: constant_identifier_names
import 'dart:convert';

import 'package:open_rest/core/model/model.dart';
import 'package:yaml/yaml.dart';

/// Thin YAML wrapper: parse to plain maps/lists, dump with readable block style (multi-line strings as `|`).
///
/// The dumper emits block style, indent 2, sequences not indented under their key,
/// unicode allowed, no line splitting, so output stays stable.
class Yml {
  Yml._();

  static dynamic parse(String text) => _plain(loadYaml(text));

  static dynamic tryParse(String text) {
    try {
      return parse(text);
    } catch (_) {
      return null;
    }
  }

  static String dump(dynamic v) {
    final e = _Emitter();
    return e.dump(v);
  }

  /// Map builder that drops null / empty values so files stay tidy.
  static Map<String, dynamic> m(List<(String, Object?)> p) {
    final out = <String, dynamic>{};
    for (final (k, v) in p) {
      final empty =
          v == null ||
          (v is String && v.isEmpty) ||
          (v is List && v.isEmpty) ||
          (v is Map && v.isEmpty);
      if (!empty) out[k] = v;
    }
    return out;
  }

  static dynamic _plain(dynamic v) {
    if (v is YamlMap) {
      final out = <dynamic, dynamic>{};
      for (final e in v.entries) {
        out[_plain(e.key)] = _plain(e.value);
      }
      return out;
    }
    if (v is YamlList) return [for (final x in v) _plain(x)];
    return v;
  }
}

// Emitter

class _Analysis {
  bool empty = false;
  bool multiline = false;
  bool allowFlowPlain = true;
  bool allowBlockPlain = true;
  bool allowSingleQuoted = true;
  bool allowDoubleQuoted = true;
  bool allowBlock = true;
}

bool _isBreak(int c) =>
    c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029;
bool _isBlankOrBreak(int c) => c == 0x20 || c == 0x09 || _isBreak(c) || c == 0;

final RegExp _boolRe = RegExp(
  r'^(?:yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF)$',
);
final RegExp _floatRe = RegExp(
  r'^(?:[-+]?(?:\.[0-9]+|[0-9_]+(?:\.[0-9_]*)?)(?:[eE][-+]?[0-9]+)?|[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$',
);
final RegExp _intRe = RegExp(
  r'^(?:[-+]?0b[0-1_]+|[-+]?0[0-7_]+|[-+]?(?:0|[1-9][0-9_]*)|[-+]?0x[0-9a-fA-F_]+|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$',
);
final RegExp _nullRe = RegExp(r'^(?:~|null|Null|NULL)$');
final RegExp _tsRe = RegExp(
  r'^(?:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]?-[0-9][0-9]?(?:[Tt]|[ \t]+)[0-9][0-9]?:[0-9][0-9]:[0-9][0-9](?:\.[0-9]*)?(?:[ \t]*(?:Z|[-+][0-9][0-9]?(?::[0-9][0-9])?))?)$',
);

/// True when a plain scalar with this text would be read back as something other than a string.
bool _implicitNonString(String s) {
  if (s.isEmpty) return true; // null
  final c = s[0];
  if ('yYnNtTfFoO'.contains(c) && _boolRe.hasMatch(s)) return true;
  if ('-+0123456789.'.contains(c)) {
    if (_floatRe.hasMatch(s)) return true;
    if (_intRe.hasMatch(s)) return true;
  }
  if ('~nN'.contains(c) && _nullRe.hasMatch(s)) return true;
  if (c == '<' && s == '<<') return true;
  if ('0123456789'.contains(c) && _tsRe.hasMatch(s)) return true;
  return false;
}

_Analysis _analyze(String scalar) {
  final a = _Analysis();
  if (scalar.isEmpty) {
    a
      ..empty = true
      ..allowFlowPlain = false
      ..allowBlockPlain = true
      ..allowSingleQuoted = true
      ..allowDoubleQuoted = true
      ..allowBlock = false;
    return a;
  }
  final cps = scalar.runes.toList();
  final len = cps.length;
  var blockIndicators = false;
  var flowIndicators = false;
  var lineBreaks = false;
  var specialCharacters = false;
  var leadingSpace = false;
  var leadingBreak = false;
  var trailingSpace = false;
  var trailingBreak = false;
  var breakSpace = false;
  var spaceBreak = false;
  var previousSpace = false;
  var previousBreak = false;
  if (scalar.startsWith('---') || scalar.startsWith('...')) {
    blockIndicators = true;
    flowIndicators = true;
  }
  var preceededByWhitespace = true;
  var followedByWhitespace = len == 1 || _isBlankOrBreak(cps[1]);
  for (var index = 0; index < len; index++) {
    final c = cps[index];
    if (index == 0) {
      if ('#,[]{}&*!|>\'"%@`'.runes.contains(c)) {
        flowIndicators = true;
        blockIndicators = true;
      }
      if (c == 0x3F || c == 0x3A) {
        flowIndicators = true;
        if (followedByWhitespace) blockIndicators = true;
      }
      if (c == 0x2D && followedByWhitespace) {
        flowIndicators = true;
        blockIndicators = true;
      }
    } else {
      if (',?[]{}'.runes.contains(c)) flowIndicators = true;
      if (c == 0x3A) {
        flowIndicators = true;
        if (followedByWhitespace) blockIndicators = true;
      }
      if (c == 0x23 && preceededByWhitespace) {
        flowIndicators = true;
        blockIndicators = true;
      }
    }
    final isLb = _isBreak(c);
    if (isLb) lineBreaks = true;
    if (!(c == 0x0A || (c >= 0x20 && c <= 0x7E))) {
      final unicode =
          c == 0x85 ||
          (c >= 0xA0 && c <= 0xD7FF) ||
          (c >= 0xE000 && c <= 0xFFFD) ||
          (c >= 0x10000 && c <= 0x10FFFF);
      if (!unicode) specialCharacters = true;
    }
    if (c == 0x20) {
      if (index == 0) leadingSpace = true;
      if (index == len - 1) trailingSpace = true;
      if (previousBreak) breakSpace = true;
      previousSpace = true;
      previousBreak = false;
    } else if (isLb) {
      if (index == 0) leadingBreak = true;
      if (index == len - 1) trailingBreak = true;
      if (previousSpace) spaceBreak = true;
      previousSpace = false;
      previousBreak = true;
    } else {
      previousSpace = false;
      previousBreak = false;
    }
    preceededByWhitespace = _isBlankOrBreak(c);
    followedByWhitespace = index + 2 >= len || _isBlankOrBreak(cps[index + 2]);
  }
  a.multiline = lineBreaks;
  if (leadingSpace || leadingBreak || trailingSpace || trailingBreak) {
    a.allowFlowPlain = false;
    a.allowBlockPlain = false;
  }
  if (trailingSpace) a.allowBlock = false;
  if (breakSpace) {
    a.allowFlowPlain = false;
    a.allowBlockPlain = false;
    a.allowSingleQuoted = false;
  }
  if (spaceBreak || specialCharacters) {
    a.allowFlowPlain = false;
    a.allowBlockPlain = false;
    a.allowSingleQuoted = false;
    a.allowBlock = false;
  }
  if (lineBreaks) a.allowFlowPlain = false;
  if (flowIndicators) a.allowFlowPlain = false;
  if (blockIndicators) a.allowBlockPlain = false;
  return a;
}

const Map<int, String> _escapes = {
  0x00: '0',
  0x07: 'a',
  0x08: 'b',
  0x09: 't',
  0x0A: 'n',
  0x0B: 'v',
  0x0C: 'f',
  0x0D: 'r',
  0x1B: 'e',
  0x22: '"',
  0x5C: '\\',
  0x85: 'N',
  0xA0: '_',
  0x2028: 'L',
  0x2029: 'P',
};

bool _printable(int c) =>
    (c >= 0x20 && c <= 0x7E) ||
    c == 0x09 ||
    c == 0x0A ||
    c == 0x0D ||
    c == 0x85 ||
    (c >= 0xA0 && c <= 0xD7FF) ||
    (c >= 0xE000 && c <= 0xFFFD) ||
    (c >= 0x10000 && c <= 0x10FFFF);

String _doubleQuoted(String text) {
  final sb = StringBuffer('"');
  for (final ch in text.runes) {
    if (ch == 0x22 ||
        ch == 0x5C ||
        ch == 0x85 ||
        ch == 0x2028 ||
        ch == 0x2029 ||
        ch == 0xFEFF ||
        !(ch >= 0x20 && ch <= 0x7E)) {
      final r = _escapes[ch];
      if (r != null) {
        sb.write('\\$r');
      } else if (!_printable(ch)) {
        if (ch <= 0xFF) {
          sb.write('\\x${ch.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        } else if (ch <= 0xFFFF) {
          sb.write('\\u${ch.toRadixString(16).toUpperCase().padLeft(4, '0')}');
        } else {
          sb.write('\\U${ch.toRadixString(16).toUpperCase().padLeft(8, '0')}');
        }
      } else {
        sb.writeCharCode(ch);
      }
    } else {
      sb.writeCharCode(ch);
    }
  }
  sb.write('"');
  return sb.toString();
}

class _Emitter {
  final StringBuffer sb = StringBuffer();

  String dump(dynamic v) {
    if (v is Map && v.isNotEmpty) {
      _map(v, 0, false);
    } else if (v is List && v.isNotEmpty) {
      _seq(v, 0, false);
    } else if (v is Map) {
      sb.write('{}\n');
    } else if (v is List) {
      sb.write('[]\n');
    } else {
      sb.write(_scalar(v, 0, false));
    }
    return sb.toString();
  }

  void _map(Map m, int indent, bool inlineFirst) {
    var idx = 0;
    for (final e in m.entries) {
      if (!(idx == 0 && inlineFirst)) sb.write(' ' * indent);
      idx++;
      sb.write(_scalar(e.key, indent + 2, true, key: true));
      sb.write(':');
      final v = e.value;
      if (v is Map) {
        if (v.isEmpty) {
          sb.write(' {}\n');
        } else {
          sb.write('\n');
          _map(v, indent + 2, false);
        }
      } else if (v is List) {
        if (v.isEmpty) {
          sb.write(' []\n');
        } else {
          sb.write('\n');
          _seq(v, indent, false); // indentless sequence under a mapping key
        }
      } else {
        sb.write(' ');
        sb.write(_scalar(v, indent + 2, false));
      }
    }
  }

  void _seq(List l, int indent, bool inlineFirst) {
    var idx = 0;
    for (final v in l) {
      if (!(idx == 0 && inlineFirst)) sb.write(' ' * indent);
      idx++;
      sb.write('-');
      if (v is Map) {
        if (v.isEmpty) {
          sb.write(' {}\n');
        } else {
          sb.write(' ');
          _map(v, indent + 2, true);
        }
      } else if (v is List) {
        if (v.isEmpty) {
          sb.write(' []\n');
        } else {
          sb.write(' ');
          _seq(v, indent + 2, true);
        }
      } else {
        sb.write(' ');
        sb.write(_scalar(v, indent + 2, false));
      }
    }
  }

  /// Text of a scalar. Always ends with a newline unless [key] is true.
  String _scalar(
    dynamic v,
    int contentIndent,
    bool simpleKey, {
    bool key = false,
  }) {
    String text;
    if (v == null) {
      text = 'null';
    } else if (v is bool || v is int) {
      text = v.toString();
    } else if (v is double) {
      text = v.isNaN
          ? '.nan'
          : (v.isInfinite ? (v < 0 ? '-.inf' : '.inf') : v.toString());
    } else {
      return _string(v.toString(), contentIndent, key);
    }
    return key ? text : '$text\n';
  }

  String _string(String s, int contentIndent, bool key) {
    // Strings with non-printable characters are dumped as !!binary (base64 of the UTF-8 bytes).
    if (s.runes.any((c) => !_printable(c))) {
      final b64 = base64.encode(utf8.encode(s));
      return key
          ? '!!binary "$b64"'
          : '!!binary |-\n${' ' * contentIndent}$b64\n';
    }
    // Strings containing \n, U+0085, U+2028 or U+2029 are emitted as literal blocks.
    final wantLiteral = !key && RegExp('\n|\u0085|\u2028|\u2029').hasMatch(s);
    final an = _analyze(s);
    String? out;
    if (!wantLiteral && !_implicitNonString(s)) {
      final plainOk =
          !(key && (an.empty || an.multiline)) && an.allowBlockPlain;
      if (plainOk && !an.multiline) out = s;
    }
    if (out == null && wantLiteral && an.allowBlock) {
      return _literal(s, contentIndent);
    }
    if (out == null &&
        !wantLiteral &&
        an.allowSingleQuoted &&
        !(key && an.multiline) &&
        !an.multiline) {
      out = "'${s.replaceAll("'", "''")}'";
    }
    // empty strings: single quoted
    out ??= an.empty ? "''" : _doubleQuoted(s);
    return key ? out : '$out\n';
  }

  String _literal(String text, int indent) {
    final out = StringBuffer();
    final hints = StringBuffer();
    final first = text.codeUnitAt(0);
    if (first == 0x20 || _isBreak(first)) hints.write('2');
    final last = text.codeUnitAt(text.length - 1);
    if (!_isBreak(last)) {
      hints.write('-');
    } else if (text.length == 1 || _isBreak(text.codeUnitAt(text.length - 2))) {
      hints.write('+');
    }
    out.write('|$hints\n');
    var breaks = true;
    var start = 0;
    var end = 0;
    final len = text.length;
    while (end <= len) {
      final ch = end < len ? text.codeUnitAt(end) : -1;
      if (breaks) {
        if (ch == -1 || !_isBreak(ch)) {
          for (final b in text.substring(start, end).codeUnits) {
            out.write(b == 0x0A ? '\n' : String.fromCharCode(b));
          }
          if (ch != -1) out.write(' ' * indent);
          start = end;
        }
      } else {
        if (ch == -1 || _isBreak(ch)) {
          out.write(text.substring(start, end));
          if (ch == -1) out.write('\n');
          start = end;
        }
      }
      if (ch != -1) breaks = _isBreak(ch);
      end++;
    }
    return out.toString();
  }
}

/// Mapping between OpenRest's model and the OpenRest YAML file format.
class OrYaml {
  OrYaml._();

  static const String ROOT_FILE = 'openrest.yaml';
  static const String FOLDER_FILE = 'folder.yaml';
  static const int VERSION = 1;

  static String _s(dynamic v) => v == null ? '' : v.toString();
  static Map? _map(dynamic v) => v is Map ? v : null;
  static String _orElse(String s, String d) => s.isEmpty ? d : s;

  static List<Map<String, dynamic>> kvOut(List<KV> l) => l
      .map(
        (it) => Yml.m([
          ('name', it.name),
          ('value', it.value),
          ('enabled', it.enabled ? null : false),
          ('file', it.isFile ? true : null),
          ('contentType', it.contentType),
        ]),
      )
      .toList();

  static List<KV> kvIn(dynamic v) {
    if (v is List) {
      final out = <KV>[];
      for (final e in v) {
        final m = _map(e);
        if (m != null) {
          out.add(
            KV(
              name: _s(m['name']),
              value: _s(m['value']),
              enabled: m['enabled'] != false,
              isFile: m['file'] == true,
              contentType: _s(m['contentType']),
            ),
          );
        }
      }
      return out;
    }
    if (v is Map) {
      return [
        for (final e in v.entries)
          KV(name: e.key.toString(), value: _s(e.value)),
      ];
    }
    return [];
  }

  static Map<String, dynamic>? _authOut(Auth a, AuthMode omit) {
    if (a.mode == omit) return null;
    switch (a.mode) {
      case AuthMode.None:
      case AuthMode.Inherit:
        return Yml.m([('type', a.mode.bru)]);
      case AuthMode.Basic:
      case AuthMode.Digest:
        return Yml.m([
          ('type', a.mode.bru),
          ('username', a.username),
          ('password', a.password),
        ]);
      case AuthMode.Bearer:
        return Yml.m([('type', 'bearer'), ('token', a.token)]);
      case AuthMode.ApiKey:
        return Yml.m([
          ('type', 'apikey'),
          ('key', a.keyName),
          ('value', a.keyValue),
          ('placement', a.placement),
        ]);
      case AuthMode.OAuth2:
        return Yml.m([
          ('type', 'oauth2'),
          ('grantType', a.grantType),
          ('tokenUrl', a.tokenUrl),
          ('clientId', a.clientId),
          ('clientSecret', a.clientSecret),
          ('scope', a.scope),
          ('username', a.username),
          ('password', a.password),
        ]);
    }
  }

  static Auth _authIn(dynamic v, AuthMode def) {
    final m = _map(v);
    if (m == null) return Auth(mode: def);
    return Auth(
      mode: AuthMode.fromBru(_orElse(_s(m['type']), def.bru)),
      username: _s(m['username']),
      password: _s(m['password']),
      token: _s(m['token']),
      keyName: _s(m['key']),
      keyValue: _s(m['value']),
      placement: _orElse(_s(m['placement']), 'header'),
      grantType: _orElse(_s(m['grantType']), 'client_credentials'),
      tokenUrl: _s(m['tokenUrl']),
      clientId: _s(m['clientId']),
      clientSecret: _s(m['clientSecret']),
      scope: _s(m['scope']),
    );
  }

  static Map<String, dynamic> _tlsOut(TlsConfig t) {
    if (t.mode == TlsMode.inherit) return {};
    return Yml.m([
      ('mode', t.mode.name),
      ('format', t.mode == TlsMode.custom ? t.format.name : null),
      ('pfx', t.pfxPath),
      ('cert', t.certPath),
      ('key', t.keyPath),
      ('ca', t.caPath),
      ('passphrase', t.passphrase),
    ]);
  }

  static TlsConfig _tlsIn(dynamic v) {
    final m = _map(v);
    if (m == null) return const TlsConfig();
    final mode = switch (_s(m['mode']).toLowerCase()) {
      'none' => TlsMode.none,
      'custom' => TlsMode.custom,
      _ => TlsMode.inherit,
    };
    return TlsConfig(
      mode: mode,
      format: _s(m['format']).toLowerCase() == 'pem'
          ? TlsFormat.pem
          : TlsFormat.pfx,
      pfxPath: _s(m['pfx']),
      certPath: _s(m['cert']),
      keyPath: _s(m['key']),
      caPath: _s(m['ca']),
      passphrase: _s(m['passphrase']),
    );
  }

  static String _txt(dynamic v) => _s(v).trimRight();

  static Map<String, dynamic> requestToMap(ApiRequest r) {
    final hasBody =
        r.bodyMode != BodyMode.None ||
        [
          r.bodyJson,
          r.bodyText,
          r.bodyXml,
          r.bodyGraphql,
          r.bodyGraphqlVars,
          r.bodyFile,
        ].any((it) => it.isNotEmpty) ||
        r.formUrlEncoded.isNotEmpty ||
        r.multipart.isNotEmpty;
    return Yml.m([
      ('name', r.name),
      ('seq', r.seq),
      ('method', r.method),
      ('url', r.url),
      (
        'params',
        Yml.m([('query', kvOut(r.params)), ('path', kvOut(r.pathParams))]),
      ),
      ('headers', kvOut(r.headers)),
      (
        'body',
        !hasBody
            ? null
            : Yml.m([
                ('type', r.bodyMode.bru),
                ('json', r.bodyJson),
                ('text', r.bodyText),
                ('xml', r.bodyXml),
                ('graphql', r.bodyGraphql),
                ('graphqlVariables', r.bodyGraphqlVars),
                ('form', kvOut(r.formUrlEncoded)),
                ('multipart', kvOut(r.multipart)),
                ('file', r.bodyFile),
              ]),
      ),
      ('auth', _authOut(r.auth, AuthMode.Inherit)),
      ('vars', Yml.m([('pre', kvOut(r.preVars)), ('post', kvOut(r.postVars))])),
      ('assertions', kvOut(r.assertions)),
      ('scripts', Yml.m([('pre', r.preScript), ('post', r.postScript)])),
      ('tests', r.tests),
      ('docs', r.docs),
      (
        'settings',
        Yml.m([
          ('encodeUrl', r.encodeUrl ? null : false),
          ('timeout', r.timeoutMs > 0 ? r.timeoutMs : null),
          ('tls', _tlsOut(r.tls)),
        ]),
      ),
    ]);
  }

  static ApiRequest mapToRequest(Map m, {String fallbackName = 'Request'}) {
    final params = _map(m['params']);
    final body = _map(m['body']);
    final vars = _map(m['vars']);
    final scripts = _map(m['scripts']);
    final st = _map(m['settings']);
    final seq = m['seq'];
    final timeout = st?['timeout'];
    return ApiRequest(
      name: _orElse(_s(m['name']), fallbackName),
      seq: seq is num ? seq.toInt() : 1,
      method: _orElse(_s(m['method']), 'GET').toUpperCase(),
      url: _s(m['url']),
      params: kvIn(params?['query']),
      pathParams: kvIn(params?['path']),
      headers: kvIn(m['headers']),
      bodyMode: BodyMode.fromBru(_orElse(_s(body?['type']), 'none')),
      bodyJson: _txt(body?['json']),
      bodyText: _txt(body?['text']),
      bodyXml: _txt(body?['xml']),
      bodyGraphql: _txt(body?['graphql']),
      bodyGraphqlVars: _txt(body?['graphqlVariables']),
      bodyFile: _s(body?['file']),
      formUrlEncoded: kvIn(body?['form']),
      multipart: kvIn(body?['multipart']),
      auth: _authIn(m['auth'], AuthMode.Inherit),
      preVars: kvIn(vars?['pre']),
      postVars: kvIn(vars?['post']),
      assertions: kvIn(m['assertions']),
      preScript: _txt(scripts?['pre']),
      postScript: _txt(scripts?['post']),
      tests: _txt(m['tests']),
      docs: _txt(m['docs']),
      encodeUrl: st?['encodeUrl'] != false,
      timeoutMs: timeout is num ? timeout.toInt() : 0,
      tls: _tlsIn(st?['tls']),
    );
  }

  static Map<String, dynamic> configToMap(NodeConfig c, bool folder) => Yml.m([
    ('name', c.name),
    ('seq', folder ? c.seq : null),
    ('headers', kvOut(c.headers)),
    ('auth', _authOut(c.auth, AuthMode.None)),
    ('vars', Yml.m([('pre', kvOut(c.preVars)), ('post', kvOut(c.postVars))])),
    ('scripts', Yml.m([('pre', c.preScript), ('post', c.postScript)])),
    ('tests', c.tests),
    ('docs', c.docs),
    ('tls', _tlsOut(c.tls)),
  ]);

  static const int _intMax = 2147483647;

  static NodeConfig mapToConfig(Map m, {String fallbackName = ''}) {
    final vars = _map(m['vars']);
    final scripts = _map(m['scripts']);
    final seq = m['seq'];
    return NodeConfig(
      name: _orElse(_s(m['name']), fallbackName),
      seq: seq is num ? seq.toInt() : _intMax,
      headers: kvIn(m['headers']),
      auth: _authIn(m['auth'], AuthMode.None),
      preVars: kvIn(vars?['pre']),
      postVars: kvIn(vars?['post']),
      preScript: _txt(scripts?['pre']),
      postScript: _txt(scripts?['post']),
      tests: _txt(m['tests']),
      docs: _txt(m['docs']),
      tls: _tlsIn(m['tls']),
    );
  }

  static Map<String, dynamic> envToMap(Environment e) => Yml.m([
    ('name', e.name),
    (
      'variables',
      e.vars.map((it) {
        final secret = e.secrets.contains(it.name);
        return Yml.m([
          ('name', it.name),
          ('value', secret ? null : it.value),
          ('enabled', it.enabled ? null : false),
          ('secret', secret ? true : null),
        ]);
      }).toList(),
    ),
  ]);

  static Environment mapToEnv(Map m, String name) {
    final raw = m['variables'];
    final list = <Map>[];
    if (raw is List) {
      for (final x in raw) {
        final mm = _map(x);
        if (mm != null) list.add(mm);
      }
    }
    return Environment(
      name: name,
      vars: list
          .map(
            (it) => KV(
              name: _s(it['name']),
              value: _s(it['value']),
              enabled: it['enabled'] != false,
            ),
          )
          .toList(),
      secrets: list
          .where((it) => it['secret'] == true)
          .map((it) => _s(it['name']))
          .toSet(),
    );
  }

  static String requestText(ApiRequest r) => Yml.dump(requestToMap(r));

  static ApiRequest? parseRequest(
    String text, {
    String fallbackName = 'Request',
  }) {
    final m = Yml.parse(text);
    if (m is Map && (m.containsKey('url') || m.containsKey('method'))) {
      return mapToRequest(m, fallbackName: fallbackName);
    }
    return null;
  }
}
