import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/utils/json.dart';

/// Mutable view of the request that scripts can read/modify via `req`.
class ReqView {
  String name;
  String url;
  String method;
  Map<String, String> headers;
  String body;
  int timeout;
  String authMode;

  ReqView(
    this.name,
    this.url,
    this.method,
    this.headers,
    this.body,
    this.timeout,
    this.authMode,
  );
}

/// Bridge object behind the JavaScript `__host` calls. Only primitive/JSON-string values cross the boundary.
/// The prelude reaches it through the `openrest` message channel (see [handle]).
class ScriptHost {
  final Map<String, dynamic> runtime;
  final Map<String, String> envVars;
  final Map<String, String> collVars;
  final Map<String, String> processEnv;
  final String envNameValue;
  final String collName;
  final String workDir;
  final String Function(String) interpolator;

  ReqView? req;
  String resultJson = 'null';
  final List<TestResult> tests = [];
  final List<String> logs = [];
  String? next;
  bool skipped = false;
  bool stopped = false;
  bool envChanged = false;
  String? lastError;

  ScriptHost(
    this.runtime,
    this.envVars,
    this.collVars,
    this.processEnv,
    String envName,
    this.collName,
    this.workDir,
    this.interpolator,
  ) : envNameValue = envName;

  String reqJson() {
    final r = req;
    if (r == null) return '{}';
    return Json.stringify({
      'name': r.name,
      'url': r.url,
      'method': r.method,
      'headers': r.headers,
      'body': r.body,
      'timeout': r.timeout,
      'authMode': r.authMode,
    });
  }

  void applyReq(String json) {
    final r = req;
    if (r == null) return;
    final m = Json.obj(Json.parse(json));
    if (m == null) return;
    r.url = m['url'] is String ? m['url'] as String : r.url;
    r.method = m['method'] is String ? m['method'] as String : r.method;
    r.body = Json.str(m['body']) ?? '';
    r.timeout = m['timeout'] is num ? (m['timeout'] as num).toInt() : r.timeout;
    final h = Json.obj(m['headers']);
    if (h != null) r.headers = {for (final e in h.entries) e.key: _s(e.value)};
  }

  static String _s(dynamic v) =>
      v == null ? 'null' : (v is String ? v : v.toString());

  String resJson() => resultJson;
  String? getVar(String n) =>
      runtime.containsKey(n) ? Json.stringify(runtime[n]) : null;
  void setVar(String n, String? json) {
    runtime[n] = json == null ? null : Json.tryParse(json);
  }

  void deleteVar(String n) => runtime.remove(n);
  void deleteAllVars() => runtime.clear();
  String? getEnvVar(String n) =>
      envVars[n] == null ? null : Json.quote(envVars[n]!);
  void setEnvVar(String n, String? json) {
    envVars[n] = json == null ? '' : (Json.str(Json.tryParse(json)) ?? '');
    envChanged = true;
  }

  String? getCollVar(String n) =>
      collVars[n] == null ? null : Json.quote(collVars[n]!);
  String? getProcessEnv(String n) => processEnv[n] ?? Platform.environment[n];
  String envName() => envNameValue;
  String collectionName() => collName;
  String cwd() => workDir;
  String interpolate(String s) => interpolator(s);
  void nextReq(String? n) => next = n;
  void skip() => skipped = true;
  void stop() => stopped = true;
  void log(String level, String msg) =>
      logs.add(level == 'log' ? msg : '[$level] $msg');
  void testResult(String name, bool pass, String msg) =>
      tests.add(TestResult(name: name, passed: pass, message: msg));
  String btoa(String s) => base64.encode(latin1.encode(s));
  String atob(String s) => latin1.decode(base64.decode(s));
  void error(String msg) => lastError = msg;

  /// Dispatches a call coming from the prelude: `[name, ...args]`.
  dynamic handle(dynamic message) {
    final a = message as List;
    final n = a[0] as String;
    String? s(int i) => a.length > i && a[i] != null ? a[i].toString() : null;
    switch (n) {
      case 'reqJson':
        return reqJson();
      case 'applyReq':
        applyReq(s(1) ?? '{}');
        return null;
      case 'resJson':
        return resJson();
      case 'getVar':
        return getVar(s(1)!);
      case 'setVar':
        setVar(s(1)!, s(2));
        return null;
      case 'deleteVar':
        deleteVar(s(1)!);
        return null;
      case 'deleteAllVars':
        deleteAllVars();
        return null;
      case 'getEnvVar':
        return getEnvVar(s(1)!);
      case 'setEnvVar':
        setEnvVar(s(1)!, s(2));
        return null;
      case 'getCollVar':
        return getCollVar(s(1)!);
      case 'getProcessEnv':
        return getProcessEnv(s(1)!);
      case 'envName':
        return envName();
      case 'collectionName':
        return collectionName();
      case 'cwd':
        return cwd();
      case 'interpolate':
        return interpolate(s(1) ?? '');
      case 'nextReq':
        nextReq(s(1));
        return null;
      case 'skip':
        skip();
        return null;
      case 'stop':
        stop();
        return null;
      case 'log':
        log(s(1) ?? 'log', s(2) ?? '');
        return null;
      case 'testResult':
        testResult(s(1) ?? '', a[2] == true, s(3) ?? '');
        return null;
      case 'btoa':
        return btoa(s(1) ?? '');
      case 'atob':
        return atob(s(1) ?? '');
      case 'error':
        error(s(1) ?? '');
        return null;
    }
    return null;
  }
}

/// JavaScript runtime that runs request scripts, tests and expressions.
class ScriptEngine {
  final ScriptHost host;
  late final JavascriptRuntime _rt;
  static String? _prelude;

  /// Tests (and anything without an asset bundle) can point this at a prelude file.
  static String preludePath = 'assets/prelude.js';

  ScriptEngine._(this.host);

  /// Creates the JS runtime and loads the prelude (async because the prelude is a Flutter asset).
  static Future<ScriptEngine> create(ScriptHost host) async {
    final e = ScriptEngine._(host);
    _prelude ??= await _loadPrelude();
    e._rt = getJavascriptRuntime(xhr: false);
    e._rt.onMessage('openrest', host.handle);
    final r = e._rt.evaluate(_prelude!);
    if (r.isError) throw StateError('prelude failed: ${r.stringResult}');
    return e;
  }

  static Future<String> _loadPrelude() async {
    try {
      return await rootBundle.loadString('assets/prelude.js');
    } catch (_) {
      return File(preludePath).readAsString();
    }
  }

  void setRequest(ReqView v) {
    host.req = v;
    _rt.evaluate('__loadReq()');
  }

  void setResponse(HttpResult? r) {
    host.resultJson = (r == null || r.error != null)
        ? 'null'
        : Json.stringify({
            'status': r.status,
            'statusText': r.statusText,
            'headers': [
              for (final h in r.headers) [h.$1, h.$2],
            ],
            'body': r.text,
            'time': r.timeMs,
            'size': r.size,
            'url': r.finalUrl,
          });
    _rt.evaluate('__loadRes()');
  }

  /// Runs a user script (promises and `await bru.sleep()` are driven to completion). Returns an error message on failure, null otherwise.
  Future<String?> run(String code, {bool syncRequest = false}) async {
    if (code.trim().isEmpty) return null;
    host.lastError = null;
    _rt.evaluate('globalThis.__runDone = false;');
    final r = _rt.evaluate(
      "(async function(){ try {\n$code\n} catch(e) { const m = String(e), st = e && e.stack ? String(e.stack) : ''; __hostError(st.indexOf(m) >= 0 ? st : (st ? m + '\\n' + st : m)); } finally { __runDone = true; } })();",
    );
    if (r.isError) {
      _rt.evaluate('globalThis.__runDone = true;');
      return r.stringResult.isEmpty ? 'Script error' : r.stringResult;
    }
    await _pump();
    if (syncRequest) _rt.evaluate('__saveReq()');
    return host.lastError;
  }

  /// Drains promise jobs; waits for `bru.sleep` timers; stops when everything settled or nothing can progress.
  Future<void> _pump() async {
    var idle = 0;
    for (var guard = 0; guard < 100000; guard++) {
      _rt.executePendingJob();
      final st = double.tryParse(_rt.evaluate('__state()').stringResult) ?? -2;
      if (st == -2) return;
      if (st < 0) {
        if (++idle > 2) return;
        continue;
      }
      idle = 0;
      if (st > 0) await Future<void>.delayed(Duration(milliseconds: st.ceil()));
      _rt.evaluate('__wakeDue()');
    }
  }

  (bool, String) assertOne(String expr, String spec) {
    try {
      final r = _rt.evaluate(
        '__assert(${jsonEncode(expr)}, ${jsonEncode(spec)})',
      );
      if (r.isError) return (false, r.stringResult);
      final m = Json.obj(Json.parse(r.stringResult))!;
      return (m['pass'] == true, m['msg'] is String ? m['msg'] as String : '');
    } catch (e) {
      return (false, e.toString());
    }
  }

  /// Evaluate a JS expression (used by post-response vars). Returns the result as a string, or null.
  String? evalExpr(String expr) {
    try {
      final r = _rt.evaluate('__evalExpr(${jsonEncode(expr)})');
      if (r.isError) return null;
      final s = r.stringResult;
      if (s == 'null' || s == 'undefined') return null;
      return Json.str(Json.tryParse(s));
    } catch (_) {
      return null;
    }
  }

  void close() {
    try {
      _rt.dispose();
    } catch (_) {}
  }
}
