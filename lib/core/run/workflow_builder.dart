// ignore_for_file: constant_identifier_names

import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/utils/json.dart';

String _take(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// One selectable value of a finished step's response, for the "pick a value" list.
class ResponseField {
  final String label;
  final SourceKind kind;
  final String path;
  final String preview;
  const ResponseField({
    required this.label,
    required this.kind,
    required this.path,
    required this.preview,
  });

  @override
  bool operator ==(Object other) =>
      other is ResponseField &&
      other.label == label &&
      other.kind == kind &&
      other.path == path &&
      other.preview == preview;
  @override
  int get hashCode => Object.hash(label, kind, path, preview);
}

/// Values that can be picked from a step response.
class ResponseFields {
  ResponseFields._();
  static const int _max = 120;

  /// Status, time, headers and every leaf of a JSON body (first few items of arrays). Empty when the step produced no response.
  static List<ResponseField> of(ExecResult? res) {
    final r = res?.response;
    if (r == null || r.error != null) return const [];
    final out = <ResponseField>[];
    final root = Json.tryParse(r.text);
    final structured = root is Map || root is List;
    // what people reach for first: the full body, then single fields of it
    out.add(
      ResponseField(
        label: structured ? 'Full body' : 'Full body (text)',
        kind: SourceKind.Body,
        path: '',
        preview: _take(r.text, 70).replaceAll('\n', ' '),
      ),
    );
    void walk(dynamic v, String path, int depth) {
      if (out.length >= _max || depth > 7) return;
      if (v is Map) {
        v.forEach(
          (k, c) =>
              walk(c, path.isEmpty ? k.toString() : '$path.$k', depth + 1),
        );
      } else if (v is List) {
        if (path.isNotEmpty) {
          out.add(
            ResponseField(
              label: 'body.$path  (list)',
              kind: SourceKind.Field,
              path: path,
              preview: '${v.length} item${v.length == 1 ? '' : 's'}',
            ),
          );
        }
        var i = 0;
        for (final c in v.take(3)) {
          walk(c, '$path[$i]', depth + 1);
          i++;
        }
      } else if (path.isNotEmpty) {
        out.add(
          ResponseField(
            label: 'body.$path',
            kind: SourceKind.Field,
            path: path,
            preview: _take(Json.str(v) ?? 'null', 70),
          ),
        );
      }
    }

    if (structured) walk(root, '', 0);
    out.add(
      ResponseField(
        label: 'Status code',
        kind: SourceKind.Status,
        path: '',
        preview: r.status.toString(),
      ),
    );
    for (final h in r.headers.take(15)) {
      out.add(
        ResponseField(
          label: 'header ${h.$1}',
          kind: SourceKind.Header,
          path: h.$1,
          preview: _take(h.$2, 70),
        ),
      );
    }
    out.add(
      ResponseField(
        label: 'Response time (ms)',
        kind: SourceKind.Time,
        path: '',
        preview: r.timeMs.toString(),
      ),
    );
    out.add(
      const ResponseField(
        label: 'Whole response (status, headers, body)',
        kind: SourceKind.Response,
        path: '',
        preview: '',
      ),
    );
    return out;
  }
}

/// A place in a request that can be filled from an earlier step.
class Slot {
  final InputTarget target;
  final String name;
  final String current;
  const Slot({required this.target, required this.name, required this.current});

  String get label => Slots.label(target, name);

  @override
  bool operator ==(Object other) =>
      other is Slot &&
      other.target == target &&
      other.name == name &&
      other.current == current;
  @override
  int get hashCode => Object.hash(target, name, current);
}

/// Places in a request that a value can be written to.
class Slots {
  Slots._();

  static String label(InputTarget target, String name) {
    switch (target) {
      case InputTarget.PathParam:
        return 'URL path · :$name';
      case InputTarget.Query:
        return 'Query · $name';
      case InputTarget.Header:
        return 'Header · $name';
      case InputTarget.Body:
        return 'Body · $name';
      case InputTarget.BodyRaw:
        return 'Body · whole body';
      case InputTarget.Bearer:
        return 'Auth · bearer token';
      case InputTarget.Url:
        return 'Request · URL';
      case InputTarget.Method:
        return 'Request · method';
      case InputTarget.PathAppend:
        return 'URL path · add at the end';
      case InputTarget.Variable:
        return 'Variable · {{$name}}';
    }
  }

  static String _after(String s, String d, [String missing = '']) {
    final i = s.indexOf(d);
    return i < 0 ? missing : s.substring(i + d.length);
  }

  static String _before(String s, String d) {
    final i = s.indexOf(d);
    return i < 0 ? s : s.substring(0, i);
  }

  /// Every fillable place of [req]: path params, query, headers, JSON body fields and the auth token.
  static List<Slot> of(ApiRequest req) {
    final out = <Slot>[];
    final pathNames = <String>[];
    for (final m in RegExp(
      r'(?<=/):([A-Za-z_][\w-]*)',
    ).allMatches(_before(req.url, '?'))) {
      if (!pathNames.contains(m.group(1)!)) pathNames.add(m.group(1)!);
    }
    for (final n in pathNames) {
      String v = '';
      for (final pp in req.pathParams) {
        if (pp.name == n) {
          v = pp.value;
          break;
        }
      }
      out.add(Slot(target: InputTarget.PathParam, name: n, current: v));
    }
    final inline = _after(req.url, '?')
        .split('&')
        .where((s) => s.isNotEmpty)
        .map((s) => (_before(s, '='), _after(s, '=')))
        .toList();
    final seen = <String>{};
    for (final (k, v) in [
      ...inline,
      ...req.params
          .where((k) => k.enabled && k.name.trim().isNotEmpty)
          .map((k) => (k.name, k.value)),
    ]) {
      if (seen.add(k)) {
        out.add(Slot(target: InputTarget.Query, name: k, current: v));
      }
    }
    for (final h in req.headers.where(
      (h) => h.enabled && h.name.trim().isNotEmpty,
    )) {
      out.add(Slot(target: InputTarget.Header, name: h.name, current: h.value));
    }
    if (req.bodyMode == BodyMode.Json) {
      final root = Json.tryParse(req.bodyJson);
      var n = 0;
      void walk(dynamic v, String path, int depth) {
        if (n >= 30 || depth > 6) return;
        if (v is Map) {
          v.forEach(
            (k, c) =>
                walk(c, path.isEmpty ? k.toString() : '$path.$k', depth + 1),
          );
        } else if (v is List) {
          var i = 0;
          for (final c in v.take(3)) {
            walk(c, '$path[$i]', depth + 1);
            i++;
          }
        } else if (path.isNotEmpty) {
          n++;
          out.add(
            Slot(
              target: InputTarget.Body,
              name: path,
              current: Json.str(v) ?? 'null',
            ),
          );
        }
      }

      if (root is Map || root is List) walk(root, '', 0);
    }
    out.add(
      Slot(
        target: InputTarget.Bearer,
        name: '',
        current: req.auth.mode == AuthMode.Bearer ? req.auth.token : '',
      ),
    );
    return out;
  }

  static final RegExp _token = RegExp(
    r'\{\{\s*(s\d+)\.([a-z]+)(?:\.([^{}]*?))?\s*\}\}',
  );

  /// Shows `{{s1.body.data.id}}` as `[Create user › data.id]` so users never see ids or braces.
  static String friendly(
    String value,
    List<WorkflowStep> steps,
    String Function(WorkflowStep) nameOf,
  ) => value.replaceAllMapped(_token, (m) {
    WorkflowStep? st;
    for (final s in steps) {
      if (s.id == m.group(1)) {
        st = s;
        break;
      }
    }
    final who = st != null ? nameOf(st) : m.group(1)!;
    final path = m.group(3) ?? '';
    final what = switch (m.group(2)!) {
      'out' => path,
      'body' => path.isEmpty ? 'whole body' : path,
      'status' => 'status code',
      'header' => 'header $path',
      'time' => 'response time',
      'response' => 'whole response',
      final o => o,
    };
    return '[$who › $what]';
  });

  static bool hasReference(String value) => _token.hasMatch(value);

  static final RegExp _plain = RegExp(
    r'\{\{\s*([A-Za-z_][A-Za-z0-9_]*)((?:\.[^{}\s]*)?)\s*\}\}',
  );

  /// Like [friendly], and also names a plain `{{token}}` / `{{user.id}}` after the step that passes `token` / `user` on.
  static String friendlyAll(
    String value,
    List<WorkflowStep> steps,
    String Function(WorkflowStep) nameOf,
  ) => friendly(value, steps, nameOf).replaceAllMapped(_plain, (m) {
    WorkflowStep? owner;
    for (final s in steps) {
      if (s.kind == StepKind.Request &&
          s.outputs.any((o) => o.name.trim() == m.group(1))) {
        owner = s;
      }
    }
    return owner == null
        ? m.group(0)!
        : '[${nameOf(owner)} › ${m.group(1)}${m.group(2)}]';
  });
}

/// Something a step's request still needs a value for.
class StepNeed {
  final InputTarget target;
  final String name;
  const StepNeed({required this.target, required this.name});

  String get label => target == InputTarget.PathParam ? '/:$name' : '{{$name}}';

  @override
  bool operator ==(Object other) =>
      other is StepNeed && other.target == target && other.name == name;
  @override
  int get hashCode => Object.hash(target, name);
}

class StepNeeds {
  StepNeeds._();
  static final RegExp _pathParam = RegExp(r'(?<=/):([A-Za-z_][\w-]*)');

  /// Unfilled path parameters (`/users/:id`) and `{{variables}}` the request uses that nothing defines yet.
  /// [known] are variable names already available (collection, environment, runtime, loops, Set blocks).
  static List<StepNeed> of(
    ApiRequest req,
    List<StepInput> inputs,
    Set<String> known,
  ) {
    final out = <StepNeed>[];
    final filled = inputs.where((i) => i.value.trim().isNotEmpty).toList();
    final qi = req.url.indexOf('?');
    final base = qi < 0 ? req.url : req.url.substring(0, qi);
    final names = <String>[];
    for (final m in _pathParam.allMatches(base)) {
      if (!names.contains(m.group(1)!)) names.add(m.group(1)!);
    }
    for (final n in names) {
      final set =
          req.pathParams.any((k) => k.name == n && k.value.trim().isNotEmpty) ||
          filled.any(
            (i) => i.target == InputTarget.PathParam && i.name.trim() == n,
          ) ||
          filled.any((i) => i.target == InputTarget.Url);
      if (!set) out.add(StepNeed(target: InputTarget.PathParam, name: n));
    }
    final sb = StringBuffer();
    sb.write('${req.url}\n');
    for (final h in req.headers.where((h) => h.enabled)) {
      sb.write('${h.name} ${h.value}\n');
    }
    for (final k in req.params.where((k) => k.enabled)) {
      sb.write('${k.value}\n');
    }
    sb.write(req.bodyJson);
    sb.write(req.bodyText);
    sb.write(req.bodyXml);
    sb.write(req.auth.token);
    sb.write(req.auth.username);
    sb.write(req.auth.password);
    final vars = <String>[];
    for (final n in Variables.names(sb.toString())) {
      if (!vars.contains(n)) vars.add(n);
    }
    for (final n in vars) {
      final root = n.contains('.') ? n.substring(0, n.indexOf('.')) : n;
      if (!WorkflowRunner.isStepRef(n) &&
          !n.startsWith(r'$') &&
          !n.startsWith('process.env.') &&
          !known.contains(n) &&
          !known.contains(root) &&
          !inputs.any(
            (i) => i.target == InputTarget.Variable && i.name.trim() == n,
          ) &&
          !n.contains(' ')) {
        out.add(StepNeed(target: InputTarget.Variable, name: n));
      }
    }
    return out;
  }
}
