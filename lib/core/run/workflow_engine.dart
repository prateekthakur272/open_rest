import 'dart:math' as math;

import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/utils/json.dart';

enum _Flow { next, breakLoop, stopAll }

String _take(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Truncates to int; NaN becomes 0 and out-of-range values saturate.
int _toLong(double d) {
  if (d.isNaN) return 0;
  if (d.isInfinite) return d > 0 ? 9223372036854775807 : -9223372036854775808;
  return d.toInt();
}

int _coerce(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Splits on '.' into at most 3 parts.
List<String> _split3(String s) {
  final out = <String>[];
  var rest = s;
  while (out.length < 2) {
    final i = rest.indexOf('.');
    if (i < 0) break;
    out.add(rest.substring(0, i));
    rest = rest.substring(i + 1);
  }
  out.add(rest);
  return out;
}

/// Executes a workflow block by block.
class WorkflowRunner {
  WorkflowRunner._();

  static bool isStepRef(String name) =>
      RegExp(r'^s\d+\.').hasMatch(name.trim());

  /// Dot/bracket path into parsed JSON; tolerates a leading `res.body.`, `body.` or `$.`.
  static String? field(String text, String path) {
    final root = Json.tryParse(text);
    if (root == null) return null;
    var p = path.trim();
    if (p.startsWith('res.body.')) p = p.substring('res.body.'.length);
    if (p.startsWith('body.')) p = p.substring('body.'.length);
    final v = JsonPath.query(root, p);
    return v == null ? null : asString(v);
  }

  static String asString(dynamic v) {
    if (v == null) return '';
    if (v is String || v is num || v is bool) {
      return Json.str(v) ?? v.toString();
    }
    return Json.stringify(v);
  }

  /// Resolves `s1.body.data.id`-style references against finished steps.
  /// Returns the value and an optional warning (value is "" when something is missing).
  static (String, String?) resolve(String name, ExecResult? src) {
    final parts = _split3(name.trim());
    final id = parts[0];
    final what = parts.length > 1 ? parts[1] : '';
    final path = parts.length > 2 ? parts[2] : '';
    final r = src?.response;
    if (r == null) return ('', '{{$name}}: step $id has no response');
    switch (what) {
      case 'body':
        if (path.isEmpty) return (r.text, null);
        final f = field(r.text, path);
        return (
          f ?? '',
          f == null ? "{{$name}}: '$path' not found in response body" : null,
        );
      case 'status':
        return (r.status.toString(), null);
      case 'time':
        return (r.timeMs.toString(), null);
      case 'header':
        String? h;
        for (final x in r.headers) {
          if (x.$1.toLowerCase() == path.trim().toLowerCase()) {
            h = x.$2;
            break;
          }
        }
        return (
          h ?? '',
          h == null ? "{{$name}}: header '$path' not found" : null,
        );
      case 'response':
        final hs = <String, dynamic>{};
        for (final x in r.headers) {
          hs[x.$1] = x.$2;
        }
        return (
          Json.stringify({
            'status': r.status,
            'statusText': r.statusText,
            'timeMs': r.timeMs,
            'headers': hs,
            'body': Json.tryParse(r.text) ?? r.text,
          }),
          null,
        );
      default:
        return (
          '',
          "{{$name}}: unknown reference '$what' (use body, status, header, time or response)",
        );
    }
  }

  static List<KV> _upsert(
    List<KV> list,
    String key,
    String value, [
    bool ci = false,
  ]) {
    final i = list.indexWhere(
      (k) => ci ? k.name.toLowerCase() == key.toLowerCase() : k.name == key,
    );
    if (i >= 0) {
      final l = List<KV>.of(list);
      l[i] = l[i].copyWith(value: value, enabled: true);
      return l;
    }
    return [...list, KV(name: key, value: value)];
  }

  static dynamic _setPath(dynamic cur, List<String> tokens, dynamic v) {
    if (tokens.isEmpty) return v;
    final k = tokens[0];
    final idx = int.tryParse(k);
    if (idx != null && (cur is List || cur == null)) {
      final l = List<dynamic>.of(cur is List ? cur : const []);
      while (l.length <= idx) {
        l.add(null);
      }
      l[idx] = _setPath(l[idx], tokens.sublist(1), v);
      return l;
    }
    final m = <String, dynamic>{};
    if (cur is Map) {
      cur.forEach((kk, vv) => m[kk.toString()] = vv);
    }
    m[k] = _setPath(m[k], tokens.sublist(1), v);
    return m;
  }

  /// Applies one customisation to [req]. Returns the changed request, or the same request with a warning when it can't be applied.
  static (ApiRequest, String?) apply(
    ApiRequest req,
    StepInput inp,
    String value,
  ) {
    switch (inp.target) {
      case InputTarget.Variable:
        return (req, null);
      case InputTarget.PathParam:
        return (
          req.copyWith(
            pathParams: _upsert(req.pathParams, inp.name.trim(), value),
          ),
          null,
        );
      case InputTarget.Url:
        return (req.copyWith(url: value), null);
      case InputTarget.Method:
        final m = value.trim().toUpperCase();
        return (req.copyWith(method: m.isEmpty ? req.method : m), null);
      case InputTarget.Query:
        final key = inp.name.trim();
        final q = req.url.indexOf('?');
        if (q < 0) {
          return (req.copyWith(params: _upsert(req.params, key, value)), null);
        }
        // the URL already carries a query string (the params table is ignored then), so edit it in place
        final pair =
            '${HttpExecutor.urlEncode(key)}=${HttpExecutor.urlEncode(value)}';
        final parts = req.url
            .substring(q + 1)
            .split('&')
            .where((s) => s.isNotEmpty)
            .toList();
        String nameOf(String s) {
          final i = s.indexOf('=');
          return i < 0 ? s : s.substring(0, i);
        }

        final at = parts.indexWhere(
          (s) => nameOf(s) == key || nameOf(s) == HttpExecutor.urlEncode(key),
        );
        if (at >= 0) {
          parts[at] = pair;
        } else {
          parts.add(pair);
        }
        return (
          req.copyWith(url: '${req.url.substring(0, q)}?${parts.join('&')}'),
          null,
        );
      case InputTarget.Header:
        return (
          req.copyWith(
            headers: _upsert(req.headers, inp.name.trim(), value, true),
          ),
          null,
        );
      case InputTarget.Bearer:
        return (
          req.copyWith(
            auth: req.auth.copyWith(mode: AuthMode.Bearer, token: value),
          ),
          null,
        );
      case InputTarget.PathAppend:
        final q = req.url.indexOf('?');
        var base = q >= 0 ? req.url.substring(0, q) : req.url;
        base = base.replaceFirst(RegExp(r'/+$'), '');
        final tail = value.replaceFirst(RegExp(r'^/+'), '');
        return (
          req.copyWith(url: '$base/$tail${q >= 0 ? req.url.substring(q) : ''}'),
          null,
        );
      case InputTarget.BodyRaw:
        final r = switch (req.bodyMode) {
          BodyMode.Text => req.copyWith(bodyText: value),
          BodyMode.Xml => req.copyWith(bodyXml: value),
          BodyMode.Graphql => req.copyWith(bodyGraphql: value),
          _ => req.copyWith(bodyMode: BodyMode.Json, bodyJson: value),
        };
        return (r, null);
      case InputTarget.Body:
        final usable =
            req.bodyMode == BodyMode.Json || req.bodyMode == BodyMode.None;
        if (!usable) {
          return (
            req,
            "body field '${inp.name}': the request body is not JSON",
          );
        }
        final existing = req.bodyJson.trim().isNotEmpty
            ? Json.tryParse(req.bodyJson)
            : null;
        if (req.bodyJson.trim().isNotEmpty && existing == null) {
          return (
            req,
            "body field '${inp.name}': the request's JSON body is not valid JSON",
          );
        }
        final typed =
            (value.trim().isNotEmpty ? Json.tryParse(value) : null) ?? value;
        final tokens = JsonPathTokens.split(inp.name);
        return (
          req.copyWith(
            bodyMode: BodyMode.Json,
            bodyJson: Json.stringify(
              _setPath(existing, tokens, typed),
              pretty: true,
            ),
          ),
          null,
        );
    }
  }

  static double? _num(String s) => double.tryParse(s.trim());

  static bool test(String l, CondOp op, String r) {
    final a = _num(l);
    final b = _num(r);
    final numeric = a != null && b != null;
    bool isEmpty() =>
        l.trim().isEmpty || const {'[]', '{}', 'null'}.contains(l.trim());
    switch (op) {
      case CondOp.Eq:
        return numeric ? a == b : l.trim() == r.trim();
      case CondOp.Ne:
        return numeric ? a != b : l.trim() != r.trim();
      case CondOp.Contains:
        return l.toLowerCase().contains(r.toLowerCase());
      case CondOp.NotContains:
        return !l.toLowerCase().contains(r.toLowerCase());
      case CondOp.StartsWith:
        return l.toLowerCase().startsWith(r.toLowerCase());
      case CondOp.Gt:
        return numeric ? a > b : l.compareTo(r) > 0;
      case CondOp.Gte:
        return numeric ? a >= b : l.compareTo(r) >= 0;
      case CondOp.Lt:
        return numeric ? a < b : l.compareTo(r) < 0;
      case CondOp.Lte:
        return numeric ? a <= b : l.compareTo(r) <= 0;
      case CondOp.Empty:
        return isEmpty();
      case CondOp.NotEmpty:
        return !isEmpty();
      case CondOp.Matches:
        try {
          return RegExp(r).hasMatch(l);
        } catch (_) {
          return false;
        }
    }
  }

  static String _short(String s, [int n = 40]) {
    final t = s.replaceAll('\n', ' ');
    return t.length > n ? '${_take(t, n)}…' : t;
  }

  static List<dynamic>? _items(String text) {
    final v = Json.tryParse(text.trim());
    if (v is List) return v;
    if (v is Map) return v.values.toList();
    return null;
  }

  static dynamic _number(double d) =>
      (d % 1.0 == 0.0 && d.abs() < 1e15) ? d.toInt() : d;

  /// Runs the workflow's blocks in order. Responses of finished requests are reachable as `{{sN.…}}`; loops and
  /// Set blocks create variables (`{{item.id}}`, `{{count}}`). Everything happens on a private copy of the
  /// collection's runtime variables.
  ///
  /// [stopAfter] ends the run once that block has finished (the "run to here" button).
  static Future<void> run(
    RunCtx rc,
    Workflow wf,
    bool Function() cancelled,
    void Function(WorkflowStep) onStart,
    void Function(StepRun) onStep, [
    void Function(RunEvent)? onEvent,
    String? stopAfter,
  ]) async {
    onEvent ??= (_) {};
    final emit = onEvent;
    final col = rc.collection;
    final runtime = Map<String, dynamic>.of(rc.runtime);
    final results = <String, ExecResult?>{};

    /// step id → output name → value, as defined on each request step.
    final outputs = <String, Map<String, String>>{};
    final ids = wf.steps.walk().map((s) => s.id).toSet();
    var notes = <String>[];
    var iteration = 0;
    var executed = 0;
    String? refs(String name) {
      final id = name.contains('.')
          ? name.substring(0, name.indexOf('.'))
          : name;
      if (!ids.contains(id)) {
        notes.add("{{$name}}: there is no step '$id'");
        return '';
      }
      if (!results.containsKey(id)) {
        notes.add('{{$name}}: that step has not run yet');
        return '';
      }
      final parts = _split3(name);
      if (parts.length > 1 && parts[1] == 'out') {
        final out = parts.length > 2 ? parts[2] : '';
        final v = outputs[id]?[out];
        if (v != null) return v;
        notes.add(
          "{{$name}}: step '$id' does not pass on an output called '$out'",
        );
        return '';
      }
      final (v, w) = resolve(name, results[id]);
      if (w != null) notes.add(w);
      return v;
    }

    /// Names that hold workflow data (passed-on values, loop and Set variables): the ones `{name}` may refer to.
    final flowNames = <String>{};
    String? flowFn(String n) {
      final root = n.contains('.') ? n.substring(0, n.indexOf('.')) : n;
      if (!flowNames.contains(root)) return null;
      if (!n.contains('.')) return asString(runtime[root]);
      return asString(
        JsonPath.query(runtime[root], n.substring(n.indexOf('.') + 1)),
      );
    }

    final ctx = RunCtx(
      col,
      rc.envName,
      runtime,
      rc.settings,
      rc.globalEnv,
      refs,
      flowFn,
    );
    final resolver = Execution(
      ctx,
      RequestNode(
        path: col.path,
        name: 'workflow',
        request: const ApiRequest(),
      ),
    );
    String text(String t) => resolver.interp(t);

    final started = DateTime.now().millisecondsSinceEpoch;
    void event(
      WorkflowStep st,
      int depth,
      String msg, {
      bool ok = true,
      int? status,
      int? ms,
      String? label,
      bool sub = false,
      List<(String, String)> fields = const [],
    }) {
      emit(
        RunEvent(
          stepId: st.id,
          depth: depth,
          kind: st.kind,
          text: msg,
          ok: ok,
          at: DateTime.now().millisecondsSinceEpoch - started,
          status: status,
          ms: ms,
          label: label,
          sub: sub,
          fields: fields,
        ),
      );
    }

    String label(WorkflowStep st, String fallback) =>
        st.title.trim().isEmpty ? fallback : st.title;

    (bool, String) check(List<Condition> conds, bool all) {
      if (conds.isEmpty) return (false, 'no conditions');
      final parts = conds.map((c) {
        final l = text(c.left);
        final r = c.op.needsRight ? text(c.right) : '';
        return (
          test(l, c.op, r),
          '${_short(l)} ${c.op.label}${c.op.needsRight ? ' ${_short(r)}' : ''}',
        );
      }).toList();
      final ok = all ? parts.every((x) => x.$1) : parts.any((x) => x.$1);
      return (ok, parts.map((x) => x.$2).join(all ? ' and ' : ' or '));
    }

    late Future<_Flow> Function(List<WorkflowStep>, int) execList;

    Future<_Flow> execRequest(WorkflowStep st, int depth) async {
      final node = col.requestByRef(st.request);
      if (node == null) {
        final msg =
            "Request '${st.request}' no longer exists in this collection";
        onStep(
          StepRun(
            step: st,
            node: null,
            result: null,
            notes: [msg],
            depth: depth,
            iteration: iteration,
          ),
        );
        event(st, depth, msg, ok: false);
        return (wf.stopOnFail && !st.continueOnFail)
            ? _Flow.stopAll
            : _Flow.next;
      }
      var req = node.request;
      final shown = <(String, String)>[];
      final sorted = List<StepInput>.of(st.inputs)
        ..sort(
          (a, b) => (a.target == InputTarget.BodyRaw ? 0 : 1).compareTo(
            b.target == InputTarget.BodyRaw ? 0 : 1,
          ),
        );
      for (final inp in sorted) {
        if (inp.value.trim().isEmpty) continue;
        if (inp.target.needsKey && inp.name.trim().isEmpty) {
          notes.add('${inp.target.label}: name is empty');
          continue;
        }
        final value = text(
          inp.value,
        ); // step references, loop / Set variables and {{vars}}
        if (inp.target == InputTarget.Variable) {
          runtime[inp.name.trim()] = value;
          flowNames.add(inp.name.trim());
        } else {
          final (r, w) = apply(req, inp, value);
          if (w != null) notes.add(w);
          req = r;
        }
        shown.add((
          inp.target.needsKey
              ? '${inp.target.label} ${inp.name.trim()}'
              : inp.target.label,
          value,
        ));
      }
      ExecResult res;
      try {
        res = await Execution(ctx, node.copyWith(request: req)).run();
      } catch (e) {
        res = ExecResult(error: e.toString());
      }
      results[st.id] = res;
      // what this step passes on to the steps after it
      final passed = <String, String>{};
      for (final o in st.outputs) {
        if (o.name.trim().isEmpty) continue;
        final (v, warn) = resolve(o.reference(st.id), res);
        passed[o.name.trim()] = v;
        if (warn != null && res.response?.error == null && res.error == null) {
          final i = warn.indexOf(': ');
          notes.add(
            "output '${o.name}': ${i < 0 ? warn : warn.substring(i + 2)}",
          );
        }
      }
      outputs[st.id] = passed;
      // ...and plain variables: {{token}}, or {{user.id}} when the value is JSON
      flowNames.addAll(passed.keys);
      passed.forEach((k, v) {
        final t = v.trim();
        runtime[k] = (t.startsWith('{') || t.startsWith('['))
            ? (Json.tryParse(t) ?? v)
            : v;
      });
      final distinctNotes = notes.toSet().toList();
      final runRec = StepRun(
        step: st,
        node: node,
        result: res,
        inputs: shown,
        notes: distinctNotes,
        depth: depth,
        iteration: iteration,
      );
      onStep(runRec);
      final r = res.response;
      final okResp = (r != null && r.error == null) ? r : null;
      event(
        st,
        depth,
        '${label(st, node.name)} · ${okResp != null ? '${okResp.status} · ${okResp.timeMs} ms' : (res.error ?? r?.error ?? 'failed')}'
        '${res.tests.any((t) => !t.passed) ? ' · ${res.tests.where((t) => !t.passed).length} test(s) failed' : ''}',
        ok: !runRec.failed,
        status: okResp?.status,
        ms: okResp?.timeMs,
        label: label(st, node.name),
      );
      if (passed.isNotEmpty) {
        event(
          st,
          depth,
          'passes on ${passed.entries.map((e) => '${e.key} = ${_short(e.value.replaceAll('\n', ' '), 40)}').join(', ')}',
          sub: true,
          fields: [for (final e in passed.entries) (e.key, e.value)],
        );
      }
      return (res.stop ||
              (wf.stopOnFail && !st.continueOnFail && runRec.failed))
          ? _Flow.stopAll
          : _Flow.next;
    }

    Future<_Flow> execIf(WorkflowStep st, int depth) async {
      final (yes, why) = check(st.conditions, st.matchAll);
      event(st, depth, '${label(st, 'If')}: $why → ${yes ? 'then' : 'else'}');
      for (final n in notes.toSet()) {
        event(st, depth, '⚠ $n', ok: false);
      }
      return execList(yes ? st.children : st.otherwise, depth + 1);
    }

    Future<_Flow> runBody(WorkflowStep st, int depth, int index) {
      final iv = st.indexVar.trim().isEmpty ? 'index' : st.indexVar.trim();
      runtime[iv] = index;
      flowNames.add(iv);
      iteration = index + 1;
      return execList(st.children, depth + 1);
    }

    Future<_Flow> execLoop(WorkflowStep st, int depth) async {
      final cap = _coerce(st.maxIterations, 1, 1000);
      final saved = iteration;
      var flow = _Flow.next;
      switch (st.loop) {
        case LoopMode.ForEach:
          final raw = text(st.list);
          final all = _items(raw);
          for (final n in notes.toSet()) {
            event(st, depth, '⚠ $n', ok: false);
          }
          if (all == null) {
            event(
              st,
              depth,
              '${label(st, 'Loop')}: “${_short(raw)}” is not a list — nothing to repeat',
              ok: false,
            );
            return _Flow.next;
          }
          event(
            st,
            depth,
            '${label(st, 'Loop')}: for each of ${all.length} item${all.length == 1 ? '' : 's'}${all.length > cap ? ' (limited to $cap)' : ''}',
          );
          var i = 0;
          for (final it in all.take(cap)) {
            if (cancelled()) {
              flow = _Flow.stopAll;
              break;
            }
            final iv = st.itemVar.trim().isEmpty ? 'item' : st.itemVar.trim();
            runtime[iv] = it;
            flowNames.add(iv);
            flow = await runBody(st, depth, i);
            if (flow != _Flow.next) break;
            i++;
          }
        case LoopMode.Repeat:
          final n = _coerce(
            _toLong(double.tryParse(text(st.count).trim()) ?? 0.0),
            0,
            cap,
          );
          event(
            st,
            depth,
            '${label(st, 'Loop')}: repeat $n time${n == 1 ? '' : 's'}',
          );
          for (var i = 0; i < n; i++) {
            if (cancelled()) {
              flow = _Flow.stopAll;
              break;
            }
            flow = await runBody(st, depth, i);
            if (flow != _Flow.next) break;
          }
        case LoopMode.While:
          event(
            st,
            depth,
            '${label(st, 'Loop')}: repeat while the condition holds (at most $cap times)',
          );
          var i = 0;
          while (i < cap) {
            if (cancelled()) {
              flow = _Flow.stopAll;
              break;
            }
            final iv = st.indexVar.trim().isEmpty
                ? 'index'
                : st.indexVar.trim();
            runtime[iv] = i;
            flowNames.add(iv);
            if (!check(st.conditions, st.matchAll).$1) break;
            flow = await runBody(st, depth, i);
            if (flow != _Flow.next) break;
            i++;
          }
          if (i >= cap) {
            event(
              st,
              depth,
              'Stopped after $cap rounds (the limit)',
              ok: false,
            );
          }
      }
      iteration = saved;
      return flow == _Flow.breakLoop ? _Flow.next : flow;
    }

    Future<_Flow> execSet(WorkflowStep st, int depth) async {
      final name = st.varName.trim();
      if (name.isEmpty) {
        event(
          st,
          depth,
          '${label(st, 'Set variable')}: no variable name',
          ok: false,
        );
        return _Flow.next;
      }
      final raw = st.setOp.needsList ? text(st.list) : text(st.value);
      final all = st.setOp.needsList ? _items(raw) : null;
      if (st.setOp.needsList && all == null) {
        flowNames.add(name);
        final numeric = st.setOp == SetOp.Count || st.setOp == SetOp.Sum;
        runtime[name] = numeric ? 0 : '';
        event(
          st,
          depth,
          '$name = ${numeric ? 0 : '(empty)'}  (“${_short(raw)}” is not a list)',
          ok: false,
        );
        return _Flow.next;
      }
      dynamic v;
      switch (st.setOp) {
        case SetOp.Value:
          final t = raw.trim();
          v = (t.startsWith('[') || t.startsWith('{'))
              ? (Json.tryParse(t) ?? raw)
              : raw;
        case SetOp.Count:
          v = all!.length;
        case SetOp.Sum:
          var sum = 0.0;
          for (final itm in all!) {
            sum +=
                _num(
                  asString(
                    st.path.trim().isEmpty ? itm : JsonPath.query(itm, st.path),
                  ),
                ) ??
                0.0;
          }
          v = _number(sum);
        case SetOp.First:
          v = all!.isEmpty ? '' : (all.first ?? '');
        case SetOp.Last:
          v = all!.isEmpty ? '' : (all.last ?? '');
      }
      runtime[name] = v;
      flowNames.add(name);
      event(
        st,
        depth,
        '${label(st, 'Set')}: $name = ${_short(asString(v), 80)}',
      );
      return _Flow.next;
    }

    Future<_Flow> execStep(WorkflowStep st, int depth) async {
      if (++executed > 2000) {
        event(
          st,
          depth,
          'Stopped: more than 2000 blocks ran (safety limit)',
          ok: false,
        );
        return _Flow.stopAll;
      }
      notes = <String>[];
      onStart(st);
      _Flow flow;
      switch (st.kind) {
        case StepKind.Request:
          flow = await execRequest(st, depth);
        case StepKind.If:
          flow = await execIf(st, depth);
        case StepKind.Loop:
          flow = await execLoop(st, depth);
        case StepKind.Set:
          flow = await execSet(st, depth);
        case StepKind.Wait:
          final ms = _coerce(
            _toLong(double.tryParse(text(st.value).trim()) ?? 0.0),
            0,
            60000,
          );
          event(st, depth, '${label(st, 'Wait')}: $ms ms');
          var left = ms;
          while (left > 0 && !cancelled()) {
            await Future<void>.delayed(
              Duration(milliseconds: math.min(left, 50)),
            );
            left -= 50;
          }
          flow = _Flow.next;
        case StepKind.Stop:
          final m = text(st.value);
          final msg = m.trim().isEmpty ? (st.stopFail ? 'failed' : 'done') : m;
          event(
            st,
            depth,
            '${label(st, 'Stop')}: ${st.stopScope.label.toLowerCase()} — $msg',
            ok: !st.stopFail,
          );
          flow = st.stopScope == StopScope.Loop
              ? _Flow.breakLoop
              : _Flow.stopAll;
      }
      if (stopAfter != null && st.id == stopAfter) return _Flow.stopAll;
      return flow;
    }

    execList = (list, depth) async {
      var flow = _Flow.next;
      for (final st in list) {
        if (cancelled()) {
          flow = _Flow.stopAll;
          break;
        }
        if (!st.enabled) continue;
        flow = await execStep(st, depth);
        if (flow != _Flow.next) break;
      }
      return flow;
    };
    await execList(wf.steps, 0);
  }
}

/// Splits `a.b[0].c` into path tokens.
class JsonPathTokens {
  JsonPathTokens._();
  static final RegExp _re = RegExp(
    r'''\.?([^.\[\]]+)|\[(\d+|"[^"]*"|'[^']*')\]''',
  );

  static List<String> split(String path) {
    var p = path.trim();
    if (p.startsWith(r'$')) p = p.substring(1);
    return _re.allMatches(p).map((m) {
      var s = (m.group(1) ?? '').isEmpty ? (m.group(2) ?? '') : m.group(1)!;
      s = s.replaceAll(RegExp('^["\']+|["\']+\$'), '');
      return s;
    }).toList();
  }
}
