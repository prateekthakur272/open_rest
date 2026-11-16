import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/core/script/script.dart';
import 'package:open_rest/utils/json.dart';

class RunCtx {
  final Collection collection;
  final String? envName;
  final Map<String, dynamic> runtime;
  final AppSettings settings;
  final Environment? globalEnv;

  /// Resolves `s1.body.id`-style references to earlier workflow steps (null outside workflows).
  final String? Function(String)? refs;

  /// Resolves a single-brace `{name}` / `{name.field}` to a value a workflow step passed on; null = not one of those, leave the text alone.
  final String? Function(String)? flow;

  RunCtx(
    this.collection,
    this.envName,
    this.runtime,
    this.settings, [
    this.globalEnv,
    this.refs,
    this.flow,
  ]);
}

/// Caches OAuth tokens until they expire.
class OAuthCache {
  OAuthCache._();
  static final Map<String, String> tokens = {};
}

/// Resolves variables, inherited config, auth and scripts for one request and executes it.
class Execution {
  final RunCtx rc;
  final RequestNode node;

  late final Collection col = rc.collection;
  late final List<FolderNode> folders = col.ancestorFolders(node.path);
  late final List<NodeConfig> chain = [
    col.config,
    ...folders.map((f) => f.config),
  ];
  late final ApiRequest req = node.request;
  late final Environment? env = _findEnv();
  late final Map<String, String> envVars = _initEnvVars();

  /// Global environment variables: the lowest-precedence layer, shared by every collection.
  late final Map<String, String> globalVars = {
    for (final k in (rc.globalEnv?.vars ?? const <KV>[]).where(
      (k) => k.enabled,
    ))
      k.name: k.value,
  };
  late final Map<String, String> collVars = {
    for (final k in col.config.preVars.where((k) => k.enabled)) k.name: k.value,
  };
  late final Map<String, String> folderVars = () {
    final acc = <String, String>{};
    for (final f in folders) {
      for (final k in f.config.preVars.where((k) => k.enabled)) {
        acc[k.name] = k.value;
      }
    }
    return acc;
  }();
  late final Map<String, String> reqVars = {
    for (final k in req.preVars.where((k) => k.enabled)) k.name: k.value,
  };

  Execution(this.rc, this.node);

  Environment? _findEnv() {
    for (final e in col.environments) {
      if (e.name == rc.envName) return e;
    }
    return null;
  }

  Map<String, String> _initEnvVars() {
    final m = <String, String>{};
    for (final k in (env?.vars ?? const <KV>[]).where((k) => k.enabled)) {
      m[k.name] = k.value;
    }
    final o = EnvOverrides.get(col.path, rc.envName ?? '');
    if (o != null) m.addAll(o);
    return m;
  }

  String _str(dynamic v) =>
      v == null ? '' : (v is String ? v : Json.stringify(v));

  String? lookup(String n) {
    if (rc.refs != null && WorkflowRunner.isStepRef(n)) return rc.refs!(n);
    if (n.startsWith('process.env.')) {
      final k = n.substring('process.env.'.length);
      return col.dotEnv[k] ?? Platform.environment[k];
    }
    if (rc.runtime.containsKey(n)) return _str(rc.runtime[n]);
    // `item.id` / `order.items[0].sku`: read into a structured variable (loop item, JSON set by a workflow)
    if (n.contains('.')) {
      final root = n.substring(0, n.indexOf('.'));
      final v = rc.runtime[root];
      if (v is Map || v is List) {
        return _str(JsonPath.query(v, n.substring(n.indexOf('.') + 1)));
      }
    }
    return reqVars[n] ??
        folderVars[n] ??
        envVars[n] ??
        collVars[n] ??
        globalVars[n];
  }

  static final RegExp _flowRe = RegExp(
    r'(?<!\{)\{([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_\[\]-]+)*)\}',
  );

  /// `{name}` first (only for names a workflow passed on, so JSON and other braces are never touched), then `{{variables}}`.
  String interp(String s) {
    final f = rc.flow;
    final a = (f != null && s.contains('{'))
        ? s.replaceAllMapped(_flowRe, (m) => f(m.group(1)!) ?? m.group(0)!)
        : s;
    return Variables.interpolate(a, lookup);
  }

  Map<String, String> _mergedHeaders() {
    final m = <String, String>{};
    void put(List<KV> kvs) {
      for (final kv in kvs.where(
        (k) => k.enabled && k.name.trim().isNotEmpty,
      )) {
        String? old;
        for (final k in m.keys) {
          if (k.toLowerCase() == kv.name.toLowerCase()) {
            old = k;
            break;
          }
        }
        if (old != null) m.remove(old);
        m[kv.name] = kv.value;
      }
    }

    for (final c in chain) {
      put(c.headers);
    }
    put(req.headers);
    return m;
  }

  Auth effectiveAuth() {
    if (req.auth.mode != AuthMode.Inherit) return req.auth;
    for (final f in folders.reversed) {
      if (f.config.auth.mode != AuthMode.None &&
          f.config.auth.mode != AuthMode.Inherit) {
        return f.config.auth;
      }
    }
    return col.config.auth.mode != AuthMode.Inherit
        ? col.config.auth
        : const Auth(mode: AuthMode.None);
  }

  /// Client certificate for this request: the request, then the nearest folder, then the collection.
  /// `none` stops the walk. Variables are expanded and relative paths resolve against the collection directory.
  TlsConfig? effectiveTls() {
    TlsConfig? pick() {
      if (req.tls.mode != TlsMode.inherit) return req.tls;
      for (final f in folders.reversed) {
        if (f.config.tls.mode != TlsMode.inherit) return f.config.tls;
      }
      return col.config.tls;
    }

    final t = pick();
    if (t == null || t.mode != TlsMode.custom) return null;
    String path(String s) {
      final v = interp(s).trim();
      if (v.isEmpty) return '';
      return File(v).isAbsolute ? v : '${col.path}${Platform.pathSeparator}$v';
    }

    return t.copyWith(
      pfxPath: path(t.pfxPath),
      certPath: path(t.certPath),
      keyPath: path(t.keyPath),
      caPath: path(t.caPath),
      passphrase: interp(t.passphrase),
    );
  }

  ReqView initialView() {
    final body = switch (req.bodyMode) {
      BodyMode.Json => req.bodyJson,
      BodyMode.Text => req.bodyText,
      BodyMode.Xml => req.bodyXml,
      BodyMode.Graphql => req.bodyGraphql,
      _ => '',
    };
    return ReqView(
      req.name,
      req.url,
      req.method,
      _mergedHeaders(),
      body,
      req.timeoutMs,
      effectiveAuth().mode.bru,
    );
  }

  String _encodeUrl(String u) {
    final sb = StringBuffer();
    const special = ' "<>\\^`{|}';
    for (final rune in u.runes) {
      final ch = String.fromCharCode(rune);
      if (rune > 126 || special.contains(ch)) {
        for (final b in utf8.encode(ch)) {
          sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  String buildUrl(String raw) {
    var u = interp(raw.trim());
    // path params  /users/:id
    final q = u.indexOf('?');
    var base = q >= 0 ? u.substring(0, q) : u;
    final rest = q >= 0 ? u.substring(q) : '';
    for (final pp in req.pathParams.where((k) => k.enabled)) {
      final v = interp(pp.value);
      base = base.replaceAll(
        RegExp('(?<=/):${RegExp.escape(pp.name)}(?![\\w-])'),
        v,
      );
    }
    u = base + rest;
    if (!u.contains('?')) {
      final ps = req.params
          .where((k) => k.enabled && k.name.trim().isNotEmpty)
          .toList();
      if (ps.isNotEmpty) {
        u +=
            '?${ps.map((k) => '${HttpExecutor.urlEncode(interp(k.name))}=${HttpExecutor.urlEncode(interp(k.value))}').join('&')}';
      }
    }
    if (!u.toLowerCase().startsWith('http://') &&
        !u.toLowerCase().startsWith('https://') &&
        u.trim().isNotEmpty &&
        !u.contains('://')) {
      u = 'http://$u';
    }
    return req.encodeUrl ? _encodeUrl(u) : u;
  }

  Body _buildBody(ReqView view) {
    switch (req.bodyMode) {
      case BodyMode.None:
        return const BodyNone();
      case BodyMode.Json:
        return BodyRaw(
          text: interp(view.body),
          contentType: 'application/json',
        );
      case BodyMode.Text:
        return BodyRaw(text: interp(view.body), contentType: 'text/plain');
      case BodyMode.Xml:
        return BodyRaw(text: interp(view.body), contentType: 'application/xml');
      case BodyMode.Graphql:
        final vs = interp(req.bodyGraphqlVars);
        final vars = vs.trim().isNotEmpty ? Json.tryParse(vs) : null;
        final op = interp(req.operationName).trim();
        return BodyRaw(
          text: Json.stringify({
            'query': interp(view.body),
            if (op.isNotEmpty) 'operationName': op,
            'variables': vars ?? <String, dynamic>{},
          }),
          contentType: 'application/json',
        );
      case BodyMode.Form:
        return BodyForm(
          fields: [
            for (final k in req.formUrlEncoded.where(
              (k) => k.enabled && k.name.trim().isNotEmpty,
            ))
              (interp(k.name), interp(k.value)),
          ],
        );
      case BodyMode.Multipart:
        return BodyMultipart(
          parts: [
            for (final k in req.multipart.where(
              (k) => k.enabled && k.name.trim().isNotEmpty,
            ))
              Part(
                name: interp(k.name),
                value: interp(k.value),
                isFile: k.isFile,
                contentType: k.contentType,
              ),
          ],
        );
      case BodyMode.File:
        return BodyFileBody(path: interp(req.bodyFile));
    }
  }

  /// Build the final request: interpolate everything and apply auth.
  Future<PreparedRequest> prepare([ReqView? v]) async {
    final view = v ?? initialView();
    var url = buildUrl(view.url);
    final headers = <String, String>{};
    view.headers.forEach((k, val) => headers[interp(k)] = interp(val));
    final a = effectiveAuth();
    switch (a.mode) {
      case AuthMode.Basic:
        headers['Authorization'] =
            'Basic ${base64.encode(utf8.encode('${interp(a.username)}:${interp(a.password)}'))}';
      case AuthMode.Bearer:
        headers['Authorization'] = 'Bearer ${interp(a.token)}';
      case AuthMode.ApiKey:
        if (a.placement == 'queryparams') {
          url +=
              '${url.contains('?') ? '&' : '?'}${HttpExecutor.urlEncode(interp(a.keyName))}=${HttpExecutor.urlEncode(interp(a.keyValue))}';
        } else {
          headers[interp(a.keyName)] = interp(a.keyValue);
        }
      case AuthMode.OAuth2:
        final t = await _fetchOAuthToken(a);
        if (t != null) headers['Authorization'] = 'Bearer $t';
      default:
        break;
    }
    final body = _buildBody(view);
    return PreparedRequest(
      method: view.method.toUpperCase(),
      url: url,
      headers: [for (final e in headers.entries) (e.key, e.value)],
      body: body,
      timeoutMs: view.timeout,
      tls: effectiveTls(),
    );
  }

  Future<String?> _fetchOAuthToken(Auth a) async {
    final key = [
      a.grantType,
      interp(a.tokenUrl),
      interp(a.clientId),
      interp(a.scope),
      interp(a.username),
    ].join('|');
    final cached = OAuthCache.tokens[key];
    if (cached != null) return cached;
    final fields = <(String, String)>[
      ('grant_type', a.grantType),
      ('client_id', interp(a.clientId)),
      ('client_secret', interp(a.clientSecret)),
    ];
    if (a.scope.trim().isNotEmpty) fields.add(('scope', interp(a.scope)));
    if (a.grantType == 'password') {
      fields.add(('username', interp(a.username)));
      fields.add(('password', interp(a.password)));
    }
    final res = await HttpExecutor.execute(
      PreparedRequest(
        method: 'POST',
        url: interp(a.tokenUrl),
        headers: [('Accept', 'application/json')],
        body: BodyForm(fields: fields),
        tls: effectiveTls(),
      ),
      rc.settings,
    );
    final t = Json.obj(Json.tryParse(res.text))?['access_token'];
    final tok = t is String ? t : null;
    if (tok != null) OAuthCache.tokens[key] = tok;
    return tok;
  }

  PreparedRequest _digest(PreparedRequest p, Auth a, String challenge) {
    String md5(String s) => crypto.md5.convert(utf8.encode(s)).toString();
    final di = challenge.indexOf('Digest');
    final after = di < 0 ? '' : challenge.substring(di + 'Digest'.length);
    final params = <String, String>{};
    for (final m in RegExp(
      r'(\w+)=(?:"([^"]*)"|([^,\s]*))',
    ).allMatches(after)) {
      final g2 = m.group(2) ?? '';
      params[m.group(1)!] = g2.isEmpty ? (m.group(3) ?? '') : g2;
    }
    final parsed = Uri.parse(p.url);
    final uri =
        (parsed.path.isEmpty ? '/' : parsed.path) +
        (parsed.hasQuery ? '?${parsed.query}' : '');
    final user = interp(a.username);
    final pass = interp(a.password);
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'] ?? '';
    String? qop;
    final qs = params['qop'];
    if (qs != null) {
      for (final s in qs.split(',').map((e) => e.trim())) {
        if (s == 'auth') {
          qop = s;
          break;
        }
      }
    }
    final ha1 = md5('$user:$realm:$pass');
    final ha2 = md5('${p.method}:$uri');
    const nc = '00000001';
    final rnd = Random.secure();
    final cnonce = List.generate(
      8,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final response = qop != null
        ? md5('$ha1:$nonce:$nc:$cnonce:$qop:$ha2')
        : md5('$ha1:$nonce:$ha2');
    final sb = StringBuffer(
      'Digest username="$user", realm="$realm", nonce="$nonce", uri="$uri", algorithm=MD5, response="$response"',
    );
    if (qop != null) sb.write(', qop=$qop, nc=$nc, cnonce="$cnonce"');
    if (params['opaque'] != null) sb.write(', opaque="${params['opaque']}"');
    return p.copyWith(
      headers: [
        ...p.headers.where((h) => h.$1.toLowerCase() != 'authorization'),
        ('Authorization', sb.toString()),
      ],
    );
  }

  Future<HttpResult> _send(PreparedRequest p) async {
    var res = await HttpExecutor.execute(p, rc.settings);
    final a = effectiveAuth();
    if (a.mode == AuthMode.Digest && res.status == 401) {
      String? ch;
      for (final h in res.headers) {
        if (h.$1.toLowerCase() == 'www-authenticate' &&
            h.$2.toLowerCase().startsWith('digest')) {
          ch = h.$2;
          break;
        }
      }
      if (ch != null) {
        res = await HttpExecutor.execute(_digest(p, a, ch), rc.settings);
      }
    }
    return res;
  }

  Future<ExecResult> run() async {
    final hasLogic =
        [
          req.preScript,
          req.postScript,
          req.tests,
        ].any((s) => s.trim().isNotEmpty) ||
        chain.any(
          (c) =>
              c.preScript.trim().isNotEmpty ||
              c.postScript.trim().isNotEmpty ||
              c.tests.trim().isNotEmpty ||
              c.postVars.isNotEmpty,
        ) ||
        req.assertions.isNotEmpty ||
        req.postVars.isNotEmpty;
    final host = ScriptHost(
      rc.runtime,
      envVars,
      {...collVars, ...folderVars},
      col.dotEnv,
      rc.envName ?? '',
      col.name,
      col.path,
      interp,
    );
    ScriptEngine? engine;
    final tests = <TestResult>[];
    void scriptErr(String where, String? e) {
      if (e != null) {
        tests.add(
          TestResult(
            name: '$where script error',
            passed: false,
            message: e,
            kind: 'script',
          ),
        );
      }
    }

    try {
      engine = hasLogic ? await ScriptEngine.create(host) : null;
      final view = initialView();
      engine?.setRequest(view);
      // pre-request: collection -> folders -> request
      final pre = [...chain.map((c) => c.preScript), req.preScript];
      for (var i = 0; i < pre.length; i++) {
        final e = engine == null
            ? null
            : await engine.run(pre[i], syncRequest: true);
        scriptErr(
          i == 0
              ? 'Collection pre-request'
              : (i == chain.length ? 'Pre-request' : 'Folder pre-request'),
          e,
        );
      }
      if (host.skipped) {
        return ExecResult(
          skipped: true,
          logs: host.logs,
          tests: tests,
          nextRequest: host.next,
          stop: host.stopped,
        );
      }
      final prepared = await prepare(host.req ?? view);
      final res = await _send(prepared);
      if (res.error != null) {
        return ExecResult(
          request: prepared,
          response: res,
          tests: tests,
          logs: host.logs,
          error: res.error,
          nextRequest: host.next,
          stop: host.stopped,
        );
      }
      if (engine != null) {
        engine.setResponse(res);
        // post-response vars
        for (final kv in [
          ...chain.expand((c) => c.postVars),
          ...req.postVars,
        ].where((k) => k.enabled && k.name.trim().isNotEmpty)) {
          final v = engine.evalExpr(interp(kv.value));
          if (v != null) rc.runtime[kv.name] = v;
        }
        // post-response scripts: request -> folders(reverse) -> collection
        for (final code in [
          req.postScript,
          ...chain.reversed.map((c) => c.postScript),
        ]) {
          scriptErr('Post-response', await engine.run(code));
        }
        // declarative assertions
        for (final kv in req.assertions.where(
          (k) => k.enabled && k.name.trim().isNotEmpty,
        )) {
          final (ok, msg) = engine.assertOne(kv.name, kv.value);
          tests.add(
            TestResult(
              name: '${kv.name}: ${kv.value}',
              passed: ok,
              message: msg,
              kind: 'assert',
            ),
          );
        }
        // tests
        for (final code in [...chain.map((c) => c.tests), req.tests]) {
          scriptErr('Tests', await engine.run(code));
        }
        tests.addAll(host.tests);
      }
      return ExecResult(
        request: prepared,
        response: res,
        tests: tests,
        logs: host.logs,
        nextRequest: host.next,
        stop: host.stopped,
      );
    } catch (e) {
      return ExecResult(error: e.toString(), tests: tests, logs: host.logs);
    } finally {
      engine?.close();
      // persist script-modified env vars back (in memory only)
      if (host.envChanged) {
        EnvOverrides.set(col.path, rc.envName ?? '', envVars);
      }
    }
  }
}

/// Env var changes made by scripts (bru.setEnvVar) live for the session.
class EnvOverrides {
  EnvOverrides._();
  static final Map<String, Map<String, String>> _map = {};
  static void set(String col, String env, Map<String, String> vars) =>
      _map['$col|$env'] = Map.of(vars);
  static Map<String, String>? get(String col, String env) => _map['$col|$env'];
}

/// One finished request of [Runner.runAll].
class RunnerItem {
  final RequestNode node;
  final ExecResult result;

  /// Zero-based iteration this request ran in.
  final int iteration;
  const RunnerItem(this.node, this.result, {this.iteration = 0});
}

/// Runs several requests in sequence.
class Runner {
  Runner._();

  static List<RequestNode> flatten(List<Node> nodes) => [
    for (final n in nodes)
      if (n is RequestNode)
        // WebSocket requests are connections, not exchanges: the runner skips them.
        ...(n.request.kind == RequestKind.http ? [n] : const <RequestNode>[])
      else
        ...flatten((n as FolderNode).children),
  ];

  /// Runs requests sequentially; honours bru.runner.skipRequest / stopExecution / setNextRequest.
  /// Returns true when the run was halted (cancelled, stop requested, or stopped on failure).
  static Future<bool> runAll(
    RunCtx rc,
    List<RequestNode> requests,
    bool stopOnFailure,
    int delayMs,
    bool Function() cancelled,
    void Function(RequestNode) onStart,
    void Function(RunnerItem) onResult,
  ) async {
    var i = 0;
    var guard = 0;
    while (i < requests.length && guard++ < requests.length * 20 + 20) {
      if (cancelled()) return true;
      final node = requests[i];
      onStart(node);
      final r = await Execution(rc, node).run();
      onResult(RunnerItem(node, r));
      final failed = r.error != null || r.tests.any((t) => !t.passed);
      if (r.stop || (stopOnFailure && failed)) return true;
      if (r.nextRequest != null) {
        final idx = requests.indexWhere((q) => q.name == r.nextRequest);
        i = idx >= 0 ? idx : requests.length;
      } else {
        i = i + 1;
      }
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
    return false;
  }
}
