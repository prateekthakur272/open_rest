import 'package:open_rest/core/model/model.dart';

/// Reader / writer for Bruno's `.bru` file format, so collections are plain git-friendly files on disk.
class BruBlock {
  final String name;
  final List<String> lines;
  final bool isList;
  const BruBlock(this.name, this.lines, this.isList);
}

class Bru {
  Bru._();

  static final RegExp _headerRe = RegExp(r'^([\w:\-]+)\s*([{\[])\s*$');
  static const Set<String> _methods = {
    'get',
    'post',
    'put',
    'patch',
    'delete',
    'head',
    'options',
    'trace',
    'connect',
  };
  static final RegExp _fileRe = RegExp(
    r'^@file\((.*?)\)(?:\s*@contentType\((.*)\))?$',
  );

  static List<BruBlock> blocks(String text) {
    final out = <BruBlock>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var i = 0;
    while (i < lines.length) {
      final m = _headerRe.firstMatch(lines[i]);
      if (m != null) {
        final close = m.group(2) == '{' ? '}' : ']';
        final body = <String>[];
        i++;
        while (i < lines.length && lines[i].trimRight() != close) {
          body.add(lines[i]);
          i++;
        }
        out.add(BruBlock(m.group(1)!, body, close == ']'));
      }
      i++;
    }
    return out;
  }

  static List<KV> _dict(BruBlock b) {
    final out = <KV>[];
    for (final raw in b.lines) {
      final l = raw.trim();
      if (l.isEmpty) continue;
      final idx = l.indexOf(':');
      if (idx < 0) continue;
      var k = l.substring(0, idx).trim();
      final enabled = !k.startsWith('~');
      if (k.startsWith('~')) k = k.substring(1);
      var v = l.substring(idx + 1).trim();
      var isFile = false;
      var ct = '';
      final fm = _fileRe.firstMatch(v);
      if (fm != null) {
        isFile = true;
        v = fm.group(1) ?? '';
        ct = fm.group(2) ?? '';
      }
      out.add(
        KV(
          name: k,
          value: v,
          enabled: enabled,
          isFile: isFile,
          contentType: ct,
        ),
      );
    }
    return out;
  }

  static Map<String, String> _plain(BruBlock b) {
    final m = <String, String>{};
    for (final kv in _dict(b)) {
      m[kv.name] = kv.value;
    }
    return m;
  }

  static String _text(BruBlock b) => b.lines
      .map((it) => it.startsWith('  ') ? it.substring(2) : it.trimLeft())
      .join('\n')
      .trimRight();

  static Auth _authFrom(List<BruBlock> blocks, String? modeStr) {
    var a = Auth(mode: AuthMode.fromBru(modeStr ?? 'none'));
    for (final b in blocks.where((it) => it.name.startsWith('auth:'))) {
      final m = _plain(b);
      switch (b.name.substring('auth:'.length)) {
        case 'basic':
        case 'digest':
          a = a.copyWith(
            username: m['username'] ?? '',
            password: m['password'] ?? '',
          );
        case 'bearer':
          a = a.copyWith(token: m['token'] ?? '');
        case 'apikey':
          a = a.copyWith(
            keyName: m['key'] ?? '',
            keyValue: m['value'] ?? '',
            placement: m['placement'] ?? 'header',
          );
        case 'oauth2':
          a = a.copyWith(
            grantType: m['grant_type'] ?? 'client_credentials',
            tokenUrl: m['access_token_url'] ?? '',
            clientId: m['client_id'] ?? '',
            clientSecret: m['client_secret'] ?? '',
            scope: m['scope'] ?? '',
            username: m['username'] ?? '',
            password: m['password'] ?? '',
          );
      }
    }
    return a;
  }

  static bool? _boolStrict(String? s) =>
      s == 'true' ? true : (s == 'false' ? false : null);

  static ApiRequest parseRequest(
    String src, {
    String fallbackName = 'Request',
  }) {
    var r = ApiRequest(
      name: fallbackName,
      auth: const Auth(mode: AuthMode.None),
    );
    final bl = blocks(src);
    String? authMode;
    for (final b in bl) {
      final n = b.name;
      if (n == 'meta') {
        final m = _plain(b);
        r = r.copyWith(
          name: m['name'] ?? fallbackName,
          seq: int.tryParse(m['seq'] ?? '') ?? 1,
        );
      } else if (_methods.contains(n)) {
        final m = _plain(b);
        r = r.copyWith(
          method: n.toUpperCase(),
          url: m['url'] ?? '',
          bodyMode: BodyMode.fromBru(m['body'] ?? 'none'),
        );
        authMode = m['auth'];
      } else if (n == 'params:query') {
        r = r.copyWith(params: _dict(b));
      } else if (n == 'params:path') {
        r = r.copyWith(pathParams: _dict(b));
      } else if (n == 'headers') {
        r = r.copyWith(headers: _dict(b));
      } else if (n == 'body:json') {
        r = r.copyWith(bodyJson: _text(b));
      } else if (n == 'body:text') {
        r = r.copyWith(bodyText: _text(b));
      } else if (n == 'body:xml') {
        r = r.copyWith(bodyXml: _text(b));
      } else if (n == 'body:graphql') {
        r = r.copyWith(bodyGraphql: _text(b));
      } else if (n == 'body:graphql:vars') {
        r = r.copyWith(bodyGraphqlVars: _text(b));
      } else if (n == 'body:form-urlencoded') {
        r = r.copyWith(formUrlEncoded: _dict(b));
      } else if (n == 'body:multipart-form') {
        r = r.copyWith(multipart: _dict(b));
      } else if (n == 'body:file') {
        final en = _dict(b).where((it) => it.enabled);
        r = r.copyWith(bodyFile: en.isEmpty ? '' : en.first.value);
      } else if (n == 'vars:pre-request') {
        r = r.copyWith(preVars: _dict(b));
      } else if (n == 'vars:post-response') {
        r = r.copyWith(postVars: _dict(b));
      } else if (n == 'assert') {
        r = r.copyWith(assertions: _dict(b));
      } else if (n == 'script:pre-request') {
        r = r.copyWith(preScript: _text(b));
      } else if (n == 'script:post-response') {
        r = r.copyWith(postScript: _text(b));
      } else if (n == 'tests') {
        r = r.copyWith(tests: _text(b));
      } else if (n == 'docs') {
        r = r.copyWith(docs: _text(b));
      } else if (n == 'settings') {
        final m = _plain(b);
        r = r.copyWith(
          encodeUrl: _boolStrict(m['encodeUrl']) ?? true,
          timeoutMs: int.tryParse(m['timeout'] ?? '') ?? 0,
        );
      }
    }
    return r.copyWith(auth: _authFrom(bl, authMode));
  }

  static NodeConfig parseConfig(String src, {String fallbackName = ''}) {
    var c = NodeConfig(name: fallbackName);
    final bl = blocks(src);
    String? authMode;
    for (final b in bl) {
      switch (b.name) {
        case 'meta':
          final m = _plain(b);
          c = c.copyWith(
            name: m['name'] ?? fallbackName,
            seq: int.tryParse(m['seq'] ?? '') ?? 1,
          );
        case 'headers':
          c = c.copyWith(headers: _dict(b));
        case 'auth':
          authMode = _plain(b)['mode'];
        case 'vars:pre-request':
          c = c.copyWith(preVars: _dict(b));
        case 'vars:post-response':
          c = c.copyWith(postVars: _dict(b));
        case 'script:pre-request':
          c = c.copyWith(preScript: _text(b));
        case 'script:post-response':
          c = c.copyWith(postScript: _text(b));
        case 'tests':
          c = c.copyWith(tests: _text(b));
        case 'docs':
          c = c.copyWith(docs: _text(b));
      }
    }
    return c.copyWith(auth: _authFrom(bl, authMode));
  }

  static Environment parseEnv(String src, String name) {
    final bl = blocks(src);
    final vb = bl.where((it) => it.name == 'vars' && !it.isList);
    final vars = vb.isEmpty ? <KV>[] : _dict(vb.first);
    final sb = bl.where((it) => it.name == 'vars:secret');
    final secrets = sb.isEmpty
        ? <String>{}
        : sb.first.lines
              .map((it) => _trimComma(it.trim()).trim())
              .where((it) => it.isNotEmpty)
              .toSet();
    return Environment(name: name, vars: vars, secrets: secrets);
  }

  static String _trimComma(String s) {
    var e = s.length;
    while (e > 0 && s[e - 1] == ',') {
      e--;
    }
    return s.substring(0, e);
  }

  static void _dictBlock(StringBuffer sb, String name, List<KV> items) {
    if (items.isEmpty) return;
    sb.write('$name {\n');
    for (final kv in items) {
      sb.write('  ');
      sb.write(kv.enabled ? '' : '~');
      sb.write(kv.name);
      sb.write(': ');
      if (kv.isFile) {
        sb.write('@file(${kv.value})');
        if (kv.contentType.isNotEmpty) {
          sb.write(' @contentType(${kv.contentType})');
        }
      } else {
        sb.write(kv.value.replaceAll('\n', ' '));
      }
      sb.write('\n');
    }
    sb.write('}\n\n');
  }

  static bool _isBlank(String s) => s.trim().isEmpty;

  static void _textBlock(StringBuffer sb, String name, String body) {
    if (_isBlank(body)) return;
    sb.write('$name {\n');
    for (final l in body.replaceAll('\r\n', '\n').split('\n')) {
      sb.write('  $l\n');
    }
    sb.write('}\n\n');
  }

  static void _authBlocks(StringBuffer sb, Auth a) {
    switch (a.mode) {
      case AuthMode.Basic:
        _dictBlock(sb, 'auth:basic', [
          KV(name: 'username', value: a.username),
          KV(name: 'password', value: a.password),
        ]);
      case AuthMode.Digest:
        _dictBlock(sb, 'auth:digest', [
          KV(name: 'username', value: a.username),
          KV(name: 'password', value: a.password),
        ]);
      case AuthMode.Bearer:
        _dictBlock(sb, 'auth:bearer', [KV(name: 'token', value: a.token)]);
      case AuthMode.ApiKey:
        _dictBlock(sb, 'auth:apikey', [
          KV(name: 'key', value: a.keyName),
          KV(name: 'value', value: a.keyValue),
          KV(name: 'placement', value: a.placement),
        ]);
      case AuthMode.OAuth2:
        _dictBlock(sb, 'auth:oauth2', [
          KV(name: 'grant_type', value: a.grantType),
          KV(name: 'access_token_url', value: a.tokenUrl),
          KV(name: 'client_id', value: a.clientId),
          KV(name: 'client_secret', value: a.clientSecret),
          KV(name: 'scope', value: a.scope),
          KV(name: 'username', value: a.username),
          KV(name: 'password', value: a.password),
        ]);
      default:
        break;
    }
  }

  static String serializeRequest(ApiRequest r) {
    final sb = StringBuffer();
    _dictBlock(sb, 'meta', [
      KV(name: 'name', value: r.name),
      const KV(name: 'type', value: 'http'),
      KV(name: 'seq', value: r.seq.toString()),
    ]);
    _dictBlock(sb, r.method.toLowerCase(), [
      KV(name: 'url', value: r.url),
      KV(name: 'body', value: r.bodyMode.bru),
      KV(name: 'auth', value: r.auth.mode.bru),
    ]);
    _dictBlock(sb, 'params:query', r.params);
    _dictBlock(sb, 'params:path', r.pathParams);
    _dictBlock(sb, 'headers', r.headers);
    _authBlocks(sb, r.auth);
    _textBlock(sb, 'body:json', r.bodyJson);
    _textBlock(sb, 'body:text', r.bodyText);
    _textBlock(sb, 'body:xml', r.bodyXml);
    _textBlock(sb, 'body:graphql', r.bodyGraphql);
    _textBlock(sb, 'body:graphql:vars', r.bodyGraphqlVars);
    _dictBlock(sb, 'body:form-urlencoded', r.formUrlEncoded);
    _dictBlock(sb, 'body:multipart-form', r.multipart);
    if (!_isBlank(r.bodyFile)) {
      _dictBlock(sb, 'body:file', [
        KV(name: 'file', value: r.bodyFile, isFile: true),
      ]);
    }
    _dictBlock(sb, 'vars:pre-request', r.preVars);
    _dictBlock(sb, 'vars:post-response', r.postVars);
    _dictBlock(sb, 'assert', r.assertions);
    _textBlock(sb, 'script:pre-request', r.preScript);
    _textBlock(sb, 'script:post-response', r.postScript);
    _textBlock(sb, 'tests', r.tests);
    _textBlock(sb, 'docs', r.docs);
    _dictBlock(sb, 'settings', [
      KV(name: 'encodeUrl', value: r.encodeUrl.toString()),
      if (r.timeoutMs > 0) KV(name: 'timeout', value: r.timeoutMs.toString()),
    ]);
    return '${sb.toString().trimRight()}\n';
  }

  static String serializeConfig(NodeConfig c, bool withMeta) {
    final sb = StringBuffer();
    if (withMeta) {
      _dictBlock(sb, 'meta', [
        KV(name: 'name', value: c.name),
        KV(name: 'seq', value: c.seq.toString()),
      ]);
    }
    _dictBlock(sb, 'headers', c.headers);
    if (c.auth.mode != AuthMode.None) {
      _dictBlock(sb, 'auth', [KV(name: 'mode', value: c.auth.mode.bru)]);
    }
    _authBlocks(sb, c.auth);
    _dictBlock(sb, 'vars:pre-request', c.preVars);
    _dictBlock(sb, 'vars:post-response', c.postVars);
    _textBlock(sb, 'script:pre-request', c.preScript);
    _textBlock(sb, 'script:post-response', c.postScript);
    _textBlock(sb, 'tests', c.tests);
    _textBlock(sb, 'docs', c.docs);
    final t = sb.toString().trimRight();
    return t.isEmpty ? '' : '$t\n';
  }

  static String serializeEnv(Environment e) {
    final sb = StringBuffer();
    _dictBlock(
      sb,
      'vars',
      e.vars.where((it) => !e.secrets.contains(it.name)).toList(),
    );
    if (e.secrets.isNotEmpty) {
      sb.write('vars:secret [\n');
      sb.write(e.secrets.map((it) => '  $it').join(',\n'));
      sb.write('\n]\n\n');
    }
    final t = sb.toString().trimRight();
    return t.isEmpty ? 'vars {\n}\n' : '$t\n';
  }
}
