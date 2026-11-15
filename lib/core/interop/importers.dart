import 'dart:io';

import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/interop/open_collection_importer.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/bru.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as p;

String _ts(dynamic v) => '$v';
String _tsOr(dynamic v, [String d = '']) => v == null ? d : v.toString();
bool _isWs(String c) => RegExp(r'\s').hasMatch(c);

/// Writes imported nodes into a new collection directory.
class ImportWriter {
  final String root;
  ImportWriter(this.root);

  String folder(
    String parent,
    String name,
    int seq, [
    NodeConfig cfg = const NodeConfig(),
  ]) {
    var d = p.join(parent, Collections.sanitize(name));
    var n = 1;
    while (FileSystemEntity.typeSync(d) != FileSystemEntityType.notFound) {
      d = p.join(parent, '${Collections.sanitize(name)} (${n++})');
    }
    Directory(d).createSync(recursive: true);
    Collections.saveFolderConfig(d, cfg.copyWith(name: name, seq: seq));
    return d;
  }

  void request(String dir, ApiRequest r, int seq) {
    Collections.writeRequest(
      Collections.uniqueFile(dir, r.name),
      r.copyWith(
        seq: seq,
        params: r.params.isEmpty
            ? UrlSync.paramsFromUrl(r.url, const [])
            : r.params,
      ),
    );
  }
}

/// Imports cURL, Postman, Insomnia, OpenAPI, Bruno and OpenRest files into collections.
class Importers {
  Importers._();

  static List<String> tokenize(String cmd) {
    final out = <String>[];
    final s = cmd.replaceAll('\\\r\n', ' ').replaceAll('\\\n', ' ');
    final cur = StringBuffer();
    var inTok = false;
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == "'") {
        inTok = true;
        i++;
        while (i < s.length && s[i] != "'") {
          cur.write(s[i++]);
        }
      } else if (c == '"') {
        inTok = true;
        i++;
        while (i < s.length && s[i] != '"') {
          if (s[i] == '\\' && i + 1 < s.length && '"\\\$`'.contains(s[i + 1])) {
            cur.write(s[i + 1]);
            i += 2;
          } else {
            cur.write(s[i++]);
          }
        }
      } else if (c == r'$' && i + 1 < s.length && s[i + 1] == "'") {
        inTok = true;
        i += 2;
        while (i < s.length && s[i] != "'") {
          if (s[i] == '\\' && i + 1 < s.length) {
            i++;
            switch (s[i]) {
              case 'n':
                cur.write('\n');
              case 't':
                cur.write('\t');
              case 'r':
                cur.write('\r');
              default:
                cur.write(s[i]);
            }
            i++;
          } else {
            cur.write(s[i++]);
          }
        }
      } else if (c == '\\' && i + 1 < s.length) {
        inTok = true;
        cur.write(s[++i]);
      } else if (_isWs(c)) {
        if (inTok) {
          out.add(cur.toString());
          cur.clear();
          inTok = false;
        }
      } else {
        inTok = true;
        cur.write(c);
      }
      i++;
    }
    if (inTok) out.add(cur.toString());
    return out;
  }

  static String _after(String s, String d) {
    final i = s.indexOf(d);
    return i < 0 ? '' : s.substring(i + d.length);
  }

  static String _before(String s, String d) {
    final i = s.indexOf(d);
    return i < 0 ? s : s.substring(0, i);
  }

  static String _javaDecode(String s) => Uri.decodeQueryComponent(s);

  static ApiRequest? parseCurl(String cmd) {
    final t = tokenize(cmd.trim());
    if (t.isEmpty || t[0] != 'curl') return null;
    String? method;
    var url = '';
    final headers = <KV>[];
    final data = <String>[];
    final forms = <KV>[];
    var auth = const Auth(mode: AuthMode.Inherit);
    var getMode = false;
    var i = 1;
    String next() {
      i++;
      return i >= 0 && i < t.length ? t[i] : '';
    }

    while (i < t.length) {
      final a = t[i];
      if (a == '-X' || a == '--request') {
        method = next().toUpperCase();
      } else if (a == '-H' || a == '--header') {
        final h = next();
        final idx = h.indexOf(':');
        if (idx > 0) {
          headers.add(
            KV(
              name: h.substring(0, idx).trim(),
              value: h.substring(idx + 1).trim(),
            ),
          );
        }
      } else if (const {
        '-d',
        '--data',
        '--data-raw',
        '--data-binary',
        '--data-ascii',
        '--data-urlencode',
      }.contains(a)) {
        data.add(next());
      } else if (a == '-F' || a == '--form') {
        final f = next();
        final idx = f.indexOf('=');
        if (idx > 0) {
          final v = f.substring(idx + 1);
          forms.add(
            v.startsWith('@')
                ? KV(
                    name: f.substring(0, idx),
                    value: v.substring(1),
                    isFile: true,
                  )
                : KV(name: f.substring(0, idx), value: v),
          );
        }
      } else if (a == '-u' || a == '--user') {
        final u = next();
        auth = Auth(
          mode: AuthMode.Basic,
          username: _before(u, ':'),
          password: _after(u, ':'),
        );
      } else if (a == '-b' || a == '--cookie') {
        headers.add(KV(name: 'Cookie', value: next()));
      } else if (a == '-A' || a == '--user-agent') {
        headers.add(KV(name: 'User-Agent', value: next()));
      } else if (a == '-e' || a == '--referer') {
        headers.add(KV(name: 'Referer', value: next()));
      } else if (a == '--url') {
        url = next();
      } else if (a == '-G' || a == '--get') {
        getMode = true;
      } else if (const {
        '-o',
        '--output',
        '-m',
        '--max-time',
        '--connect-timeout',
        '-x',
        '--proxy',
        '--retry',
        '-w',
        '--write-out',
        '-c',
        '--cookie-jar',
        '--cacert',
        '--cert',
        '--key',
      }.contains(a)) {
        next();
      } else if (a.startsWith('-')) {
        // ignored flag
      } else if (url.isEmpty) {
        url = a;
      }
      i++;
    }
    if (url.isEmpty) return null;
    String ct = '';
    for (final h in headers) {
      if (h.name.toLowerCase() == 'content-type') {
        ct = h.value.toLowerCase();
        break;
      }
    }
    var r = ApiRequest(name: _curlName(url), auth: auth);
    final joined = data.join('&');
    if (forms.isNotEmpty) {
      r = r.copyWith(bodyMode: BodyMode.Multipart, multipart: forms);
    } else if (data.isNotEmpty && !getMode) {
      final jt = joined.trim();
      if (ct.contains('json') || jt.startsWith('{') || jt.startsWith('[')) {
        r = r.copyWith(
          bodyMode: BodyMode.Json,
          bodyJson: Json.prettyText(joined) ?? joined,
        );
      } else if (ct.contains('x-www-form-urlencoded') || ct.isEmpty) {
        r = r.copyWith(
          bodyMode: BodyMode.Form,
          formUrlEncoded: joined
              .split('&')
              .where((s) => s.isNotEmpty)
              .map(
                (s) => KV(
                  name: _javaDecode(_before(s, '=')),
                  value: _javaDecode(_after(s, '=')),
                ),
              )
              .toList(),
        );
      } else if (ct.contains('xml')) {
        r = r.copyWith(bodyMode: BodyMode.Xml, bodyXml: joined);
      } else {
        r = r.copyWith(bodyMode: BodyMode.Text, bodyText: joined);
      }
    }
    if (getMode && data.isNotEmpty) {
      url += (url.contains('?') ? '&' : '?') + joined;
    }
    final finalMethod =
        method ??
        ((forms.isNotEmpty || (data.isNotEmpty && !getMode)) ? 'POST' : 'GET');
    final hs = headers
        .where(
          (h) =>
              !(h.name.toLowerCase() == 'content-type' &&
                  r.bodyMode == BodyMode.Multipart),
        )
        .toList();
    return r.copyWith(
      method: finalMethod,
      url: url,
      headers: hs,
      params: UrlSync.paramsFromUrl(url, const []),
    );
  }

  /// Name from the last path segment of the URL, else the host, else "Imported".
  static String _curlName(String url) {
    if (RegExp(r'[\s{}|\\^`"<>]').hasMatch(url)) return 'Imported';
    try {
      final u = Uri.parse(url);
      var path = u.path.replaceFirst(RegExp(r'/+$'), '');
      final i = path.lastIndexOf('/');
      path = i < 0 ? path : path.substring(i + 1);
      if (path.isNotEmpty) return path;
      return u.host.isEmpty ? 'Imported' : u.host;
    } catch (_) {
      return 'Imported';
    }
  }

  static String newCollectionDir(String parent, String name) {
    var n = 0;
    while (true) {
      final nm = n == 0 ? name : '$name ($n)';
      final d = p.join(parent, Collections.sanitize(nm));
      if (FileSystemEntity.typeSync(d) == FileSystemEntityType.notFound) {
        return Collections.create(parent, nm);
      }
      n++;
    }
  }

  static String _translatePm(String src) => src
      .replaceAll('pm.environment.set(', 'bru.setEnvVar(')
      .replaceAll('pm.environment.get(', 'bru.getEnvVar(')
      .replaceAll('pm.variables.set(', 'bru.setVar(')
      .replaceAll('pm.variables.get(', 'bru.getVar(')
      .replaceAll('pm.collectionVariables.set(', 'bru.setVar(')
      .replaceAll('pm.collectionVariables.get(', 'bru.getVar(')
      .replaceAll('pm.globals.set(', 'bru.setVar(')
      .replaceAll('pm.globals.get(', 'bru.getVar(')
      .replaceAll('pm.test(', 'test(')
      .replaceAll('pm.expect(', 'expect(')
      .replaceAll('pm.response.json()', 'res.getBody()')
      .replaceAll('pm.response.code', 'res.status')
      .replaceAll('pm.response.status', 'res.statusText')
      .replaceAll('pm.response.responseTime', 'res.responseTime')
      .replaceAll('pm.response.text()', 'JSON.stringify(res.getBody())')
      .replaceAll('pm.request.url', 'req.getUrl()');

  static (String, String) _pmScripts(List<dynamic>? events) {
    var pre = '';
    var test = '';
    if (events != null) {
      for (final e0 in events) {
        final e = Json.obj(e0);
        if (e == null) continue;
        final exec = Json.arr(Json.obj(e['script'])?['exec']);
        final code = exec?.map((x) => x.toString()).join('\n') ?? '';
        if (e['listen'] == 'prerequest') {
          pre = _translatePm(code);
        } else if (e['listen'] == 'test') {
          test = _translatePm(code);
        }
      }
    }
    return (pre, test);
  }

  static List<KV> _pmKvs(dynamic l, [String keyName = 'key']) {
    final a = Json.arr(l);
    if (a == null) return const [];
    return [
      for (final x in a)
        if (Json.obj(x) != null)
          KV(
            name: _tsOr(Json.obj(x)![keyName]),
            value: _tsOr(Json.obj(x)!['value']),
            enabled: Json.obj(x)!['disabled'] != true,
          ),
    ];
  }

  static Auth? _pmAuth(Map<String, dynamic>? a) {
    if (a == null) return null;
    final type = a['type'];
    if (type is! String) return null;
    final m = <String, String>{};
    for (final x in Json.arr(a[type]) ?? const []) {
      final o = Json.obj(x);
      if (o != null) m[_ts(o['key'])] = _tsOr(o['value']);
    }
    switch (type) {
      case 'bearer':
        return Auth(mode: AuthMode.Bearer, token: m['token'] ?? '');
      case 'basic':
        return Auth(
          mode: AuthMode.Basic,
          username: m['username'] ?? '',
          password: m['password'] ?? '',
        );
      case 'digest':
        return Auth(
          mode: AuthMode.Digest,
          username: m['username'] ?? '',
          password: m['password'] ?? '',
        );
      case 'apikey':
        return Auth(
          mode: AuthMode.ApiKey,
          keyName: m['key'] ?? '',
          keyValue: m['value'] ?? '',
          placement: m['in'] == 'query' ? 'queryparams' : 'header',
        );
      case 'noauth':
        return const Auth(mode: AuthMode.None);
      case 'oauth2':
        return Auth(
          mode: AuthMode.OAuth2,
          grantType: 'client_credentials',
          tokenUrl: m['accessTokenUrl'] ?? '',
          clientId: m['clientId'] ?? '',
          clientSecret: m['clientSecret'] ?? '',
          scope: m['scope'] ?? '',
        );
      default:
        return null;
    }
  }

  static ApiRequest _pmRequest(Map<String, dynamic> item) {
    final reqAny = item['request'];
    final name = _tsOr(item['name'], 'Request');
    if (reqAny is String) return ApiRequest(name: name, url: reqAny);
    final rq = Json.obj(reqAny);
    if (rq == null) return ApiRequest(name: name);
    final urlAny = rq['url'];
    final url = urlAny is String
        ? urlAny
        : (urlAny is Map ? _tsOr(urlAny['raw']) : '');
    var r = ApiRequest(
      name: name,
      method: (rq['method'] is String ? rq['method'] as String : 'GET')
          .toUpperCase(),
      url: url,
      headers: _pmKvs(rq['header']),
      auth: _pmAuth(Json.obj(rq['auth'])) ?? const Auth(mode: AuthMode.Inherit),
    );
    final u = Json.obj(urlAny);
    if (u != null) {
      r = r.copyWith(
        params: _pmKvs(u['query']),
        pathParams: _pmKvs(u['variable']),
      );
    }
    final body = Json.obj(rq['body']);
    if (body != null) {
      switch (body['mode']) {
        case 'raw':
          final raw = _tsOr(body['raw']);
          final lang = Json.obj(
            Json.obj(body['options'])?['raw'],
          )?['language']?.toString();
          if (lang == 'json' ||
              r.headers.any(
                (h) =>
                    h.name.toLowerCase() == 'content-type' &&
                    h.value.contains('json'),
              ) ||
              raw.trim().startsWith('{')) {
            r = r.copyWith(bodyMode: BodyMode.Json, bodyJson: raw);
          } else if (lang == 'xml') {
            r = r.copyWith(bodyMode: BodyMode.Xml, bodyXml: raw);
          } else {
            r = r.copyWith(bodyMode: BodyMode.Text, bodyText: raw);
          }
        case 'urlencoded':
          r = r.copyWith(
            bodyMode: BodyMode.Form,
            formUrlEncoded: _pmKvs(body['urlencoded']),
          );
        case 'formdata':
          r = r.copyWith(
            bodyMode: BodyMode.Multipart,
            multipart: [
              for (final x in Json.arr(body['formdata']) ?? const [])
                if (Json.obj(x) != null)
                  if (Json.obj(x)!['type'] == 'file')
                    KV(
                      name: _ts(Json.obj(x)!['key']),
                      value: _tsOr(Json.obj(x)!['src']),
                      enabled: Json.obj(x)!['disabled'] != true,
                      isFile: true,
                    )
                  else
                    KV(
                      name: _ts(Json.obj(x)!['key']),
                      value: _tsOr(Json.obj(x)!['value']),
                      enabled: Json.obj(x)!['disabled'] != true,
                    ),
            ],
          );
        case 'graphql':
          final g = Json.obj(body['graphql']);
          r = r.copyWith(
            bodyMode: BodyMode.Graphql,
            bodyGraphql: _tsOr(g?['query']),
            bodyGraphqlVars: _tsOr(g?['variables']),
          );
        case 'file':
          r = r.copyWith(
            bodyMode: BodyMode.File,
            bodyFile: _tsOr(Json.obj(body['file'])?['src']),
          );
      }
    }
    final (pre, test) = _pmScripts(Json.arr(item['event']));
    final d = rq['description'];
    return r.copyWith(
      preScript: pre,
      tests: test,
      docs: d == null ? '' : (d is Map ? _tsOr(d['content']) : d.toString()),
    );
  }

  static String importPostman(String text, String parent) {
    final root =
        Json.obj(Json.parse(text)) ??
        (throw StateError('Invalid Postman file'));
    final info =
        Json.obj(root['info']) ??
        (throw StateError("Not a Postman collection (missing 'info')"));
    final name = _tsOr(info['name'], 'Postman Collection');
    final dir = newCollectionDir(parent, name);
    final w = ImportWriter(dir);
    final (pre, test) = _pmScripts(Json.arr(root['event']));
    final cfg = NodeConfig(
      name: name,
      auth: _pmAuth(Json.obj(root['auth'])) ?? const Auth(mode: AuthMode.None),
      preVars: _pmKvs(root['variable']),
      preScript: pre,
      tests: test,
      docs: info['description'] is String ? info['description'] as String : '',
    );
    Collections.saveCollectionConfig(dir, cfg);
    void walk(List<dynamic>? items, String into) {
      var seq = 1;
      for (final x in items ?? const []) {
        final it0 = Json.obj(x);
        if (it0 == null) continue;
        if (it0.containsKey('item')) {
          final (fp, ft) = _pmScripts(Json.arr(it0['event']));
          final fcfg = NodeConfig(
            auth:
                _pmAuth(Json.obj(it0['auth'])) ??
                const Auth(mode: AuthMode.None),
            preScript: fp,
            tests: ft,
          );
          final d = w.folder(into, _tsOr(it0['name'], 'Folder'), seq++, fcfg);
          walk(Json.arr(it0['item']), d);
        } else {
          w.request(into, _pmRequest(it0), seq++);
        }
      }
    }

    walk(Json.arr(root['item']), dir);
    return dir;
  }

  static Environment? importPostmanEnv(String text) {
    final m = Json.obj(Json.tryParse(text));
    if (m == null) return null;
    final vals = Json.arr(m['values']);
    if (vals == null) return null;
    return Environment(
      name: _tsOr(m['name'], 'Imported'),
      vars: [
        for (final x in vals)
          if (Json.obj(x) != null)
            KV(
              name: _ts(Json.obj(x)!['key']),
              value: _tsOr(Json.obj(x)!['value']),
              enabled: Json.obj(x)!['enabled'] != false,
            ),
      ],
    );
  }

  static String importInsomnia(String text, String parent) {
    final root =
        Json.obj(Json.parse(text)) ??
        (throw StateError('Invalid Insomnia export'));
    final resList =
        Json.arr(root['resources']) ??
        (throw StateError('Not an Insomnia export'));
    final res = [
      for (final x in resList)
        if (Json.obj(x) != null) Json.obj(x)!,
    ];
    Map<String, dynamic>? ws;
    for (final r in res) {
      if (r['_type'] == 'workspace') {
        ws = r;
        break;
      }
    }
    final name = _tsOr(ws?['name'], 'Insomnia Import');
    final dir = newCollectionDir(parent, name);
    final w = ImportWriter(dir);
    List<Map<String, dynamic>> children(String? pid) =>
        res.where((r) => r['parentId'] == pid).toList();
    void walk(String? pid, String into) {
      var seq = 1;
      for (final r in children(pid)) {
        switch (r['_type']) {
          case 'request_group':
            walk(
              _ts(r['_id']),
              w.folder(into, _tsOr(r['name'], 'Folder'), seq++),
            );
          case 'request':
            final body = Json.obj(r['body']);
            final mime = _tsOr(body?['mimeType']);
            final txt = _tsOr(body?['text']);
            var rq = ApiRequest(
              name: _tsOr(r['name'], 'Request'),
              method: _tsOr(r['method'], 'GET').toUpperCase(),
              url: _tsOr(r['url']),
              headers: [
                for (final x in Json.arr(r['headers']) ?? const [])
                  if (Json.obj(x) != null)
                    KV(
                      name: _ts(Json.obj(x)!['name']),
                      value: _tsOr(Json.obj(x)!['value']),
                      enabled: Json.obj(x)!['disabled'] != true,
                    ),
              ],
              docs: _tsOr(r['description']),
            );
            if (mime.contains('json')) {
              rq = rq.copyWith(bodyMode: BodyMode.Json, bodyJson: txt);
            } else if (mime.contains('x-www-form-urlencoded')) {
              rq = rq.copyWith(
                bodyMode: BodyMode.Form,
                formUrlEncoded: _pmKvs(body?['params'], 'name'),
              );
            } else if (mime.contains('multipart')) {
              rq = rq.copyWith(
                bodyMode: BodyMode.Multipart,
                multipart: _pmKvs(body?['params'], 'name'),
              );
            } else if (mime.contains('xml')) {
              rq = rq.copyWith(bodyMode: BodyMode.Xml, bodyXml: txt);
            } else if (mime.contains('graphql')) {
              rq = rq.copyWith(
                bodyMode: BodyMode.Graphql,
                bodyGraphql:
                    Json.obj(Json.tryParse(txt))?['query']?.toString() ?? txt,
              );
            } else if (txt.isNotEmpty) {
              rq = rq.copyWith(bodyMode: BodyMode.Text, bodyText: txt);
            }
            final au = Json.obj(r['authentication']);
            if (au?['type'] == 'bearer') {
              rq = rq.copyWith(
                auth: Auth(mode: AuthMode.Bearer, token: _tsOr(au!['token'])),
              );
            } else if (au?['type'] == 'basic') {
              rq = rq.copyWith(
                auth: Auth(
                  mode: AuthMode.Basic,
                  username: _tsOr(au!['username']),
                  password: _tsOr(au['password']),
                ),
              );
            }
            w.request(into, rq, seq++);
        }
      }
    }

    walk(ws?['_id']?.toString(), dir);
    for (final e in res.where(
      (r) => r['_type'] == 'environment' && Json.obj(r['data']) != null,
    )) {
      final vars = [
        for (final en in Json.obj(e['data'])!.entries)
          KV(name: en.key, value: Json.str(en.value) ?? ''),
      ];
      if (vars.isNotEmpty) {
        Collections.saveEnvironment(
          dir,
          Environment(name: _tsOr(e['name'], 'Environment'), vars: vars),
        );
      }
    }
    return dir;
  }

  static dynamic _deref(String ref, Map<String, dynamic> root) {
    dynamic cur = root;
    for (final s in (ref.startsWith('#/') ? ref.substring(2) : ref).split(
      '/',
    )) {
      cur = Json.obj(cur)?[s];
    }
    return cur;
  }

  static dynamic _example(
    Map<String, dynamic>? schema,
    Map<String, dynamic> root, [
    int depth = 0,
  ]) {
    if (schema == null) return null;
    if (depth > 5) return null;
    final ref = schema[r'$ref']?.toString();
    if (ref != null) {
      return _example(Json.obj(_deref(ref, root)), root, depth + 1);
    }
    if (schema.containsKey('example')) return schema['example'];
    if (schema.containsKey('default')) return schema['default'];
    final en = Json.arr(schema['enum']);
    if (en != null && en.isNotEmpty && en.first != null) return en.first;
    final allOf = Json.arr(schema['allOf']);
    if (allOf != null) {
      final acc = <String, dynamic>{};
      for (final s in allOf) {
        final e = _example(Json.obj(s), root, depth + 1);
        if (e is Map) {
          e.forEach((k, v) => acc[k.toString()] = v);
        }
      }
      return acc;
    }
    final oneOf = Json.arr(schema['oneOf'] ?? schema['anyOf']);
    if (oneOf != null && oneOf.isNotEmpty && oneOf.first != null) {
      return _example(Json.obj(oneOf.first), root, depth + 1);
    }
    final type = schema['type'];
    switch (type) {
      case 'object':
      case null:
        final props = Json.obj(schema['properties']);
        if (props != null) {
          final m = <String, dynamic>{};
          props.forEach(
            (k, v) => m[k] = _example(Json.obj(v), root, depth + 1),
          );
          return m;
        }
        return type == null ? null : <String, dynamic>{};
      case 'array':
        return [_example(Json.obj(schema['items']), root, depth + 1)];
      case 'integer':
        return 0;
      case 'number':
        return 0.0;
      case 'boolean':
        return true;
      default:
        switch (schema['format']) {
          case 'date-time':
            return '2024-01-01T00:00:00Z';
          case 'date':
            return '2024-01-01';
          case 'email':
            return 'user@example.com';
          case 'uuid':
            return '00000000-0000-0000-0000-000000000000';
          default:
            return 'string';
        }
    }
  }

  static String importOpenApi(String text, String parent) {
    final root =
        Json.obj(Json.tryParse(text)) ??
        Json.obj(Yml.tryParse(text)) ??
        (throw StateError(
          'Not a valid OpenAPI / Swagger document (JSON or YAML)',
        ));
    final info = Json.obj(root['info']);
    final name = _tsOr(info?['title'], 'OpenAPI Import');
    final dir = newCollectionDir(parent, name);
    final w = ImportWriter(dir);
    String base;
    final servers = Json.arr(root['servers']);
    if (servers != null &&
        servers.isNotEmpty &&
        servers.first != null &&
        Json.obj(servers.first)?['url'] != null) {
      base = Json.obj(servers.first)!['url'].toString();
    } else if (root['host'] != null) {
      final sc = Json.arr(root['schemes']);
      base =
          '${sc != null && sc.isNotEmpty ? sc.first.toString() : 'https'}://${root['host']}${_tsOr(root['basePath'])}';
    } else {
      base = 'http://localhost';
    }
    Collections.saveEnvironment(
      dir,
      Environment(
        name: 'Default',
        vars: [
          KV(name: 'baseUrl', value: base.replaceFirst(RegExp(r'/+$'), '')),
        ],
      ),
    );
    final paths =
        Json.obj(root['paths']) ?? (throw StateError("No 'paths' found"));
    final folders = <String, String>{};
    var seq = 1;
    const order = [
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'head',
      'options',
      'trace',
    ];
    for (final entry in paths.entries) {
      final path = entry.key;
      final item = Json.obj(entry.value);
      if (item == null) continue;
      final common = [
        for (final x in Json.arr(item['parameters']) ?? const [])
          if (Json.obj(x) != null) Json.obj(x)!,
      ];
      for (final mth in order) {
        final op = Json.obj(item[mth]);
        if (op == null) continue;
        final tags = Json.arr(op['tags']);
        final tag = tags != null && tags.isNotEmpty
            ? tags.first?.toString()
            : null;
        final String into;
        if (tag == null) {
          into = dir;
        } else {
          into = folders[tag] ??= w.folder(dir, tag, folders.length + 1);
        }
        final opParams = [
          for (final x in Json.arr(op['parameters']) ?? const [])
            if (Json.obj(x) != null) Json.obj(x)!,
        ];
        final params = [...common, ...opParams].map((pm) {
          if (pm.containsKey(r'$ref')) {
            return Json.obj(_deref(pm[r'$ref'].toString(), root)) ?? pm;
          }
          return pm;
        }).toList();
        List<KV> kv(String where) => [
          for (final pm in params.where((x) => x['in'] == where))
            KV(
              name: _ts(pm['name']),
              value: Json.str(_example(Json.obj(pm['schema']), root)) ?? '',
              enabled: pm['required'] == true,
            ),
        ];
        final summary = op['summary']?.toString();
        var r = ApiRequest(
          name: (summary != null && summary.trim().isNotEmpty)
              ? summary
              : (op['operationId']?.toString() ?? '${mth.toUpperCase()} $path'),
          method: mth.toUpperCase(),
          url:
              '{{baseUrl}}${path.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) => ':${m.group(1)}')}',
          params: kv('query'),
          pathParams: kv('path').map((k) => k.copyWith(enabled: true)).toList(),
          headers: kv('header'),
          docs: _tsOr(op['description']),
        );
        final rb = Json.obj(op['requestBody']);
        final content = Json.obj(rb?['content']);
        if (content != null) {
          MapEntry<String, dynamic>? pick;
          for (final e in content.entries) {
            if (e.key.contains('json')) {
              pick = e;
              break;
            }
          }
          pick ??= content.entries.first;
          final ct = pick.key;
          final ex = _example(Json.obj(Json.obj(pick.value)?['schema']), root);
          if (ct.contains('json')) {
            r = r.copyWith(
              bodyMode: BodyMode.Json,
              bodyJson: Json.stringify(ex, pretty: true),
            );
          } else if (ct.contains('x-www-form-urlencoded')) {
            r = r.copyWith(
              bodyMode: BodyMode.Form,
              formUrlEncoded: ex is Map
                  ? [
                      for (final e in ex.entries)
                        KV(
                          name: e.key.toString(),
                          value: Json.str(e.value) ?? '',
                        ),
                    ]
                  : const [],
            );
          } else if (ct.contains('multipart')) {
            r = r.copyWith(
              bodyMode: BodyMode.Multipart,
              multipart: ex is Map
                  ? [
                      for (final e in ex.entries)
                        KV(
                          name: e.key.toString(),
                          value: Json.str(e.value) ?? '',
                        ),
                    ]
                  : const [],
            );
          } else if (ct.contains('xml')) {
            r = r.copyWith(bodyMode: BodyMode.Xml);
          } else {
            r = r.copyWith(
              bodyMode: BodyMode.Text,
              bodyText: Json.str(ex) ?? '',
            );
          }
        }
        w.request(into, r, seq++);
      }
    }
    return dir;
  }

  static String importBruno(String src, String parent) {
    if (OpenCollectionImporter.isOpenCollection(src)) {
      return OpenCollectionImporter.import(
        src,
        parent,
      ); // the newer YAML layout
    }
    Map<String, dynamic>? meta;
    try {
      meta = Json.obj(
        Json.parse(File(p.join(src, 'bruno.json')).readAsStringSync()),
      );
    } catch (_) {
      meta = null;
    }
    final name = meta?['name'] is String
        ? meta!['name'] as String
        : p.basename(src);
    final dir = newCollectionDir(parent, name);
    final w = ImportWriter(dir);
    final cf = p.join(src, 'collection.bru');
    Collections.saveCollectionConfig(
      dir,
      (File(cf).existsSync()
              ? Bru.parseConfig(File(cf).readAsStringSync(), fallbackName: name)
              : const NodeConfig())
          .copyWith(name: name),
    );
    void walk(String from, String into) {
      final entries = Directory(from).listSync(followLinks: false).toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      var fseq = 1;
      for (final e in entries) {
        final en = p.basename(e.path);
        if (en.startsWith('.')) continue;
        final isDir = FileSystemEntity.isDirectorySync(e.path);
        if (isDir) {
          if (en == 'node_modules' || (en == 'environments' && from == src)) {
            continue;
          }
          final fb = p.join(e.path, 'folder.bru');
          final cfg = File(fb).existsSync()
              ? Bru.parseConfig(File(fb).readAsStringSync(), fallbackName: en)
              : NodeConfig(name: en);
          walk(
            e.path,
            w.folder(
              into,
              cfg.name.isEmpty ? en : cfg.name,
              (cfg.seq == 2147483647 || cfg.seq == 0) ? fseq++ : cfg.seq,
              cfg,
            ),
          );
        } else if (p.extension(e.path) == '.bru' &&
            en != 'collection.bru' &&
            en != 'folder.bru') {
          ApiRequest? r;
          try {
            r = Bru.parseRequest(
              File(e.path).readAsStringSync(),
              fallbackName: p.basenameWithoutExtension(e.path),
            );
          } catch (_) {
            r = null;
          }
          if (r != null) w.request(into, r, r.seq);
        }
      }
    }

    walk(src, dir);
    final envDir = p.join(src, 'environments');
    if (Directory(envDir).existsSync()) {
      final files =
          Directory(envDir)
              .listSync()
              .whereType<File>()
              .where((f) => p.extension(f.path) == '.bru')
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        Collections.saveEnvironment(
          dir,
          Bru.parseEnv(
            f.readAsStringSync(),
            p.basenameWithoutExtension(f.path),
          ),
        );
      }
    }
    return dir;
  }

  static String importBundle(String text, String parent) {
    final root = Yml.parse(text);
    if (root is! Map) throw StateError('Not an OpenRest bundle');
    if (!root.containsKey('openrest')) {
      throw ArgumentError("Not an OpenRest bundle (missing 'openrest' key)");
    }
    final cfg = OrYaml.mapToConfig(root, fallbackName: 'Imported');
    final dir = newCollectionDir(parent, cfg.name);
    final w = ImportWriter(dir);
    Collections.saveCollectionConfig(dir, cfg);
    void walk(dynamic items, String into) {
      var seq = 1;
      if (items is! List) return;
      for (final m in items) {
        if (m is! Map) continue;
        if (m.containsKey('items')) {
          final c = OrYaml.mapToConfig(m);
          walk(
            m['items'],
            w.folder(
              into,
              c.name.isEmpty ? 'Folder' : c.name,
              seq++,
              OrYaml.mapToConfig(m),
            ),
          );
        } else {
          w.request(into, OrYaml.mapToRequest(m), seq++);
        }
      }
    }

    walk(root['items'], dir);
    final envs = root['environments'];
    if (envs is List) {
      for (final m in envs) {
        if (m is Map) {
          Collections.saveEnvironment(
            dir,
            OrYaml.mapToEnv(m, _tsOr(m['name'], 'Environment')),
          );
        }
      }
    }
    return dir;
  }

  static String exportPostman(Collection c) {
    List<Map<String, dynamic>> kvs(List<KV> l) => [
      for (final k in l)
        {'key': k.name, 'value': k.value, 'disabled': !k.enabled},
    ];
    Map<String, dynamic> item(Node n) {
      if (n is FolderNode) {
        return {'name': n.name, 'item': n.children.map(item).toList()};
      }
      final r = (n as RequestNode).request;
      Map<String, dynamic>? body;
      switch (r.bodyMode) {
        case BodyMode.Json:
          body = {
            'mode': 'raw',
            'raw': r.bodyJson,
            'options': {
              'raw': {'language': 'json'},
            },
          };
        case BodyMode.Text:
          body = {'mode': 'raw', 'raw': r.bodyText};
        case BodyMode.Xml:
          body = {
            'mode': 'raw',
            'raw': r.bodyXml,
            'options': {
              'raw': {'language': 'xml'},
            },
          };
        case BodyMode.Form:
          body = {'mode': 'urlencoded', 'urlencoded': kvs(r.formUrlEncoded)};
        case BodyMode.Multipart:
          body = {
            'mode': 'formdata',
            'formdata': [
              for (final k in r.multipart)
                {
                  'key': k.name,
                  'value': k.value,
                  'type': k.isFile ? 'file' : 'text',
                  'disabled': !k.enabled,
                },
            ],
          };
        case BodyMode.Graphql:
          body = {
            'mode': 'graphql',
            'graphql': {'query': r.bodyGraphql, 'variables': r.bodyGraphqlVars},
          };
        default:
          body = null;
      }
      final req = <String, dynamic>{
        'method': r.method,
        'header': kvs(r.headers),
        'url': {'raw': r.url},
      };
      if (body != null) req['body'] = body;
      switch (r.auth.mode) {
        case AuthMode.Bearer:
          req['auth'] = {
            'type': 'bearer',
            'bearer': [
              {'key': 'token', 'value': r.auth.token, 'type': 'string'},
            ],
          };
        case AuthMode.Basic:
          req['auth'] = {
            'type': 'basic',
            'basic': [
              {'key': 'username', 'value': r.auth.username},
              {'key': 'password', 'value': r.auth.password},
            ],
          };
        default:
          break;
      }
      return {'name': r.name, 'request': req};
    }

    final root = <String, dynamic>{
      'info': {
        'name': c.name,
        'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': c.children.map(item).toList(),
      'variable': [
        for (final k in c.config.preVars) {'key': k.name, 'value': k.value},
      ],
    };
    return Json.stringify(root, pretty: true);
  }
}

/// Keeps the URL query string and the params table in sync, like Bruno does.
class UrlSync {
  UrlSync._();

  static String _dec(String s) {
    try {
      return Uri.decodeQueryComponent(s);
    } catch (_) {
      return s;
    }
  }

  static List<KV> paramsFromUrl(String url, List<KV> old) {
    final q = url.indexOf('?');
    final parsed = q < 0
        ? <KV>[]
        : url.substring(q + 1).split('&').where((s) => s.isNotEmpty).map((s) {
            final k = _before(s, '=');
            final v = _after(s, '=');
            // keep {{var}} readable; decode other escapes
            return KV(
              name: k.contains('{{') ? k : _dec(k),
              value: v.contains('{{') ? v : _dec(v),
            );
          }).toList();
    return [...parsed, ...old.where((k) => !k.enabled)];
  }

  static String _before(String s, String d) {
    final i = s.indexOf(d);
    return i < 0 ? s : s.substring(0, i);
  }

  static String _after(String s, String d) {
    final i = s.indexOf(d);
    return i < 0 ? '' : s.substring(i + d.length);
  }

  static String urlWithParams(String url, List<KV> params) {
    final base = _before(url, '?');
    final q = params
        .where((k) => k.enabled && k.name.isNotEmpty)
        .map((k) => '${_enc(k.name)}=${_enc(k.value)}')
        .join('&');
    return q.isEmpty ? base : '$base?$q';
  }

  static String _enc(String s) =>
      s.contains('{{') ? s : HttpExecutor.urlEncode(s);
}
