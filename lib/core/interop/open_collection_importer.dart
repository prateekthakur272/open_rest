import 'dart:io';

import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as p;

/// Imports a Bruno collection saved in the newer YAML "OpenCollection" layout: an `opencollection.yml` at the root,
/// one `.yml` file per request, `folder.yml` per folder and an `environments` folder of `.yml` files.
/// The reader is lenient: it understands the field names Bruno writes and ignores what it does not know.
class OpenCollectionImporter {
  OpenCollectionImporter._();

  static const Set<String> _reserved = {
    'opencollection.yml',
    'opencollection.yaml',
    'folder.yml',
    'folder.yaml',
  };

  static bool isOpenCollection(String dir) =>
      Directory(dir).existsSync() &&
      (File(p.join(dir, 'opencollection.yml')).existsSync() ||
          File(p.join(dir, 'opencollection.yaml')).existsSync());

  static String import(String src, String parent) {
    final rootFile = [
      'opencollection.yml',
      'opencollection.yaml',
    ].map((f) => p.join(src, f)).firstWhere((f) => File(f).existsSync());
    final root =
        _readMap(rootFile) ??
        (throw StateError('opencollection.yml is not valid YAML'));
    final nm = _str(_map(root['info'])?['name']);
    final name = nm.trim().isEmpty ? p.basename(src) : nm;
    final ignore = <String>{
      ...(_list(_map(_map(root['extensions'])?['bruno'])?['ignore']) ??
              const [])
          .map(_str),
      'node_modules',
      '.git',
      'environments',
    };
    final dir = Importers.newCollectionDir(parent, name);
    final w = ImportWriter(dir);
    Collections.saveCollectionConfig(dir, _nodeConfig(root, name));

    void walk(String from, String into) {
      var folderSeq = 1;
      final entries = Directory(from).listSync(followLinks: false).toList()
        ..sort(
          (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );
      for (final e in entries) {
        final en = p.basename(e.path);
        final isDir = FileSystemEntity.isDirectorySync(e.path);
        if (en.startsWith('.') || (ignore.contains(en) && isDir)) continue;
        if (isDir) {
          String? fmPath;
          for (final f in ['folder.yml', 'folder.yaml']) {
            if (File(p.join(e.path, f)).existsSync()) {
              fmPath = p.join(e.path, f);
              break;
            }
          }
          final fm = fmPath == null ? null : _readMap(fmPath);
          final cfg = _nodeConfig(fm ?? const <String, dynamic>{}, en);
          walk(
            e.path,
            w.folder(
              into,
              cfg.name.trim().isEmpty ? en : cfg.name,
              (cfg.seq <= 0 || cfg.seq == 2147483647) ? folderSeq++ : cfg.seq,
              cfg,
            ),
          );
        } else {
          final ext = p.extension(en);
          if ((ext == '.yml' || ext == '.yaml') && !_reserved.contains(en)) {
            final m = _readMap(e.path);
            if (m == null) continue;
            if (m['http'] == null && m['info'] == null) continue;
            ApiRequest? r;
            try {
              r = request(m, p.basenameWithoutExtension(en));
            } catch (_) {
              r = null;
            }
            if (r != null) w.request(into, r, r.seq);
          }
        }
      }
    }

    walk(src, dir);

    final envDir = p.join(src, 'environments');
    if (Directory(envDir).existsSync()) {
      final files = Directory(envDir).listSync().whereType<File>().where((f) {
        final e = p.extension(f.path);
        return e == '.yml' || e == '.yaml';
      }).toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final m = _readMap(f.path);
        if (m != null) {
          final n = _str(m['name']);
          Collections.saveEnvironment(
            dir,
            OrYaml.mapToEnv(
              m,
              n.trim().isEmpty ? p.basenameWithoutExtension(f.path) : n,
            ),
          );
        }
      }
    }
    return dir;
  }

  static ApiRequest request(Map m, String fallbackName) {
    final info = _map(m['info']);
    final http = _map(m['http']) ?? const <String, dynamic>{};
    final settings = _map(m['settings']);
    final body = _map(http['body']);
    final type = _str(body?['type']).toLowerCase();
    final data = body?['data'];
    final mode = switch (type) {
      'json' => BodyMode.Json,
      'text' => BodyMode.Text,
      'xml' => BodyMode.Xml,
      'form-urlencoded' ||
      'formurlencoded' ||
      'form_urlencoded' => BodyMode.Form,
      'multipart-form' ||
      'multipartform' ||
      'multipart_form' ||
      'multipart' => BodyMode.Multipart,
      'graphql' => BodyMode.Graphql,
      'file' => BodyMode.File,
      _ => BodyMode.None,
    };
    final params = [
      for (final x in _list(http['params']) ?? const [])
        if (_map(x) != null) _map(x)!,
    ];
    final gql = _map(data);
    final (pre, post, tests) = _scripts(m);
    final url = _str(http['url'])
        .split(RegExp(r'\r\n|\n|\r'))
        .map((l) => l.trim())
        .join(); // long URLs are wrapped over several lines in the file
    final nm = _str(info?['name']);
    final mth = _str(http['method']);
    return ApiRequest(
      name: nm.trim().isEmpty ? fallbackName : nm,
      seq: info?['seq'] is num ? (info!['seq'] as num).toInt() : 1,
      method: (mth.trim().isEmpty ? 'GET' : mth).toUpperCase(),
      url: url,
      params: params
          .where((x) => _str(x['type']).toLowerCase() != 'path')
          .map(_kv)
          .toList(),
      pathParams: params
          .where((x) => _str(x['type']).toLowerCase() == 'path')
          .map(_kv)
          .toList(),
      headers: [
        for (final x in _list(http['headers']) ?? const [])
          if (_map(x) != null) _kv(_map(x)!),
      ],
      bodyMode: mode,
      bodyJson: mode == BodyMode.Json ? _str(data) : '',
      bodyText: mode == BodyMode.Text ? _str(data) : '',
      bodyXml: mode == BodyMode.Xml ? _str(data) : '',
      bodyGraphql: mode == BodyMode.Graphql ? _str(gql?['query'] ?? data) : '',
      bodyGraphqlVars: mode == BodyMode.Graphql ? _str(gql?['variables']) : '',
      bodyFile: mode == BodyMode.File ? _str(_map(data)?['path'] ?? data) : '',
      formUrlEncoded: mode == BodyMode.Form
          ? [
              for (final x in _list(data) ?? const [])
                if (_map(x) != null) _kv(_map(x)!),
            ]
          : const [],
      multipart: mode == BodyMode.Multipart
          ? [
              for (final x in _list(data) ?? const [])
                if (_map(x) != null)
                  _kv(_map(x)!).copyWith(
                    isFile: _str(_map(x)!['type']).toLowerCase() == 'file',
                    contentType: _str(_map(x)!['contentType']),
                  ),
            ]
          : const [],
      auth: _auth(http['auth'], true),
      preVars: _vars(m, 'pre'),
      postVars: _vars(m, 'post'),
      assertions: _assertions(m),
      preScript: pre,
      postScript: post,
      tests: tests,
      docs: _docs(m['docs']),
      encodeUrl: settings?['encodeUrl'] is bool
          ? settings!['encodeUrl'] as bool
          : true,
      timeoutMs: settings?['timeout'] is num
          ? (settings!['timeout'] as num).toInt()
          : 0,
    );
  }

  static NodeConfig _nodeConfig(Map m, String fallbackName) {
    final info = _map(m['info']);
    // defaults may sit under `request:` (collection / folder) or `http:`, depending on the version that wrote the file
    final d =
        _map(m['request']) ?? _map(m['http']) ?? const <String, dynamic>{};
    final Map rt = m['runtime'] != null
        ? m
        : <String, dynamic>{'runtime': d['runtime'] ?? d};
    final (pre, post, tests) = _scripts(rt);
    final nm = _str(info?['name']);
    return NodeConfig(
      name: nm.trim().isEmpty ? fallbackName : nm,
      seq: info?['seq'] is num ? (info!['seq'] as num).toInt() : 2147483647,
      headers: [
        for (final x in _list(d['headers']) ?? const [])
          if (_map(x) != null) _kv(_map(x)!),
      ],
      auth: _auth(d['auth'], false),
      preVars: _vars(rt, 'pre'),
      postVars: _vars(rt, 'post'),
      preScript: pre,
      postScript: post,
      tests: tests,
      docs: _docs(m['docs']),
    );
  }

  static Auth _auth(dynamic v, bool inherit) {
    if (v == null) {
      return Auth(mode: inherit ? AuthMode.Inherit : AuthMode.None);
    }
    if (v is String) {
      switch (v.toLowerCase()) {
        case 'inherit':
          return const Auth(mode: AuthMode.Inherit);
        default:
          return const Auth(mode: AuthMode.None);
      }
    }
    final a = _map(v);
    if (a == null) return const Auth(mode: AuthMode.None);
    switch (_str(a['type']).toLowerCase()) {
      case 'inherit':
        return const Auth(mode: AuthMode.Inherit);
      case 'bearer':
        return Auth(mode: AuthMode.Bearer, token: _str(a['token']));
      case 'basic':
        return Auth(
          mode: AuthMode.Basic,
          username: _str(a['username']),
          password: _str(a['password']),
        );
      case 'digest':
        return Auth(
          mode: AuthMode.Digest,
          username: _str(a['username']),
          password: _str(a['password']),
        );
      case 'apikey':
      case 'api-key':
      case 'api_key':
        return Auth(
          mode: AuthMode.ApiKey,
          keyName: _str(a['key']),
          keyValue: _str(a['value']),
          placement: _str(a['placement']).toLowerCase().startsWith('query')
              ? 'queryparams'
              : 'header',
        );
      case 'oauth2':
        var g = _str(a['flow'] ?? a['grant_type'] ?? a['grantType']);
        if (g.trim().isEmpty) g = 'client_credentials';
        g = g.replaceAll('-', '_');
        return Auth(
          mode: AuthMode.OAuth2,
          grantType: g.contains('password') ? 'password' : 'client_credentials',
          tokenUrl: _str(
            a['access_token_url'] ?? a['accessTokenUrl'] ?? a['tokenUrl'],
          ),
          clientId: _str(a['client_id'] ?? a['clientId']),
          clientSecret: _str(a['client_secret'] ?? a['clientSecret']),
          scope: _str(a['scope']),
          username: _str(a['username']),
          password: _str(a['password']),
        );
      default:
        return const Auth(mode: AuthMode.None);
    }
  }

  /// `runtime.scripts` is a list of `{type, code}`; older files used a map keyed by the same names.
  static (String, String, String) _scripts(Map m) {
    final rt = _map(m['runtime']) ?? m;
    var pre = '';
    var post = '';
    var tests = '';
    void put(String type, String code) {
      switch (type.toLowerCase().replaceAll('_', '-')) {
        case 'before-request' || 'pre-request' || 'pre':
          pre = code;
        case 'after-response' || 'post-response' || 'post':
          post = code;
        case 'tests' || 'test':
          tests = code;
      }
    }

    final s = rt['scripts'];
    if (s is List) {
      for (final x in s) {
        final o = _map(x);
        if (o != null) put(_str(o['type']), _str(o['code'] ?? o['script']));
      }
    } else if (s is Map) {
      s.forEach((k, v) => put(_str(k), v is Map ? _str(v['code']) : _str(v)));
    }
    return (pre, post, tests);
  }

  static List<KV> _vars(Map m, String which) {
    final rt = _map(m['runtime']) ?? m;
    final v = rt['vars'];
    final want = which == 'pre'
        ? const {'pre-request', 'pre', 'before-request', 'request'}
        : const {'post-response', 'post', 'after-response', 'response'};
    if (v is List) {
      return [
        for (final x in v)
          if (_map(x) != null &&
              want.contains(
                _orDefault(
                  _str(_map(x)!['type'] ?? _map(x)!['when']).toLowerCase(),
                  'pre-request',
                ),
              ))
            _kv(_map(x)!),
      ];
    }
    if (v is Map) {
      dynamic found;
      for (final e in v.entries) {
        if (want.contains(_str(e.key).toLowerCase())) {
          found = e.value;
          break;
        }
      }
      return [
        for (final x in _list(found) ?? const [])
          if (_map(x) != null) _kv(_map(x)!),
      ];
    }
    return const [];
  }

  static String _orDefault(String s, String d) => s.trim().isEmpty ? d : s;

  static List<KV> _assertions(Map m) {
    final rt = _map(m['runtime']) ?? m;
    return [
      for (final x in _list(rt['assertions']) ?? const [])
        if (_map(x) != null)
          () {
            final a = _map(x)!;
            final expr = _str(a['expression'] ?? a['name']);
            final op = _str(a['operator']);
            final value = _str(a['value']);
            return KV(
              name: expr,
              value: op.trim().isEmpty ? value : '$op $value'.trim(),
              enabled: a['disabled'] != true && a['enabled'] != false,
            );
          }(),
    ];
  }

  static String _docs(dynamic v) => v is Map ? _str(v['content']) : _str(v);

  static KV _kv(Map m) => KV(
    name: _str(m['name']),
    value: _str(m['value']),
    enabled: m['disabled'] != true && m['enabled'] != false,
  );

  static Map? _readMap(String path) {
    try {
      final v = Yml.parse(File(path).readAsStringSync());
      return v is Map ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Map? _map(dynamic v) => v is Map ? v : null;
  static List? _list(dynamic v) => v is List ? v : null;
  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map || v is List) return Json.stringify(v);
    return v.toString();
  }
}
