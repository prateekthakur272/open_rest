import 'dart:convert';

import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';

/// Outcome of one finished runner item.
enum RunStatus { passed, failed, skipped }

/// Which results the list shows.
enum ResultFilter { all, failed, passed, skipped }

/// Classifies a finished item: skipped, failed (error, transport error or failing test) or passed.
RunStatus statusOf(RunnerItem it) {
  final r = it.result;
  if (r.skipped) return RunStatus.skipped;
  if (r.error != null ||
      r.response?.error != null ||
      r.tests.any((t) => !t.passed)) {
    return RunStatus.failed;
  }
  return RunStatus.passed;
}

/// The response when the request actually got one.
HttpResult? responseOf(RunnerItem it) {
  final resp = it.result.response;
  return resp != null && resp.error == null ? resp : null;
}

/// Aggregate numbers of a run.
class RunSummary {
  const RunSummary({
    this.passed = 0,
    this.failed = 0,
    this.skipped = 0,
    this.totalMs = 0,
    this.responses = 0,
    this.testsPassed = 0,
    this.testsTotal = 0,
  });

  final int passed;
  final int failed;
  final int skipped;

  /// Sum of response times.
  final int totalMs;

  /// Number of items that produced a response (the divisor for [avgMs]).
  final int responses;
  final int testsPassed;
  final int testsTotal;

  int get total => passed + failed + skipped;
  int get avgMs => responses == 0 ? 0 : (totalMs / responses).round();
}

/// Computes the [RunSummary] of [items].
RunSummary summarize(Iterable<RunnerItem> items) {
  var passed = 0, failed = 0, skipped = 0;
  var ms = 0, responses = 0, tp = 0, tt = 0;
  for (final it in items) {
    switch (statusOf(it)) {
      case RunStatus.passed:
        passed++;
      case RunStatus.failed:
        failed++;
      case RunStatus.skipped:
        skipped++;
    }
    final resp = responseOf(it);
    if (resp != null) {
      ms += resp.timeMs;
      responses++;
    }
    tt += it.result.tests.length;
    tp += it.result.tests.where((t) => t.passed).length;
  }
  return RunSummary(
    passed: passed,
    failed: failed,
    skipped: skipped,
    totalMs: ms,
    responses: responses,
    testsPassed: tp,
    testsTotal: tt,
  );
}

/// Whether [s] belongs to [f].
bool matchesFilter(ResultFilter f, RunStatus s) => switch (f) {
  ResultFilter.all => true,
  ResultFilter.failed => s == RunStatus.failed,
  ResultFilter.passed => s == RunStatus.passed,
  ResultFilter.skipped => s == RunStatus.skipped,
};

/// Indices into [items] that match [f], in run order.
List<int> filterIndices(List<RunnerItem> items, ResultFilter f) => [
  for (var i = 0; i < items.length; i++)
    if (matchesFilter(f, statusOf(items[i]))) i,
];

/// Results of one iteration.
class IterationGroup {
  const IterationGroup(this.iteration, this.indices, this.summary);

  final int iteration;

  /// Indices into the item list.
  final List<int> indices;

  /// Summary of the items in this group.
  final RunSummary summary;
}

/// Groups [indices] of [items] by iteration, ordered by iteration number.
List<IterationGroup> groupByIteration(
  List<RunnerItem> items,
  List<int> indices,
) {
  final by = <int, List<int>>{};
  for (final i in indices) {
    by.putIfAbsent(items[i].iteration, () => []).add(i);
  }
  final keys = by.keys.toList()..sort();
  return [
    for (final k in keys)
      IterationGroup(k, by[k]!, summarize(by[k]!.map((i) => items[i]))),
  ];
}

/// Latest status of every request path that has run.
Map<String, RunStatus> lastStatuses(List<RunnerItem> items) => {
  for (final it in items) it.node.path: statusOf(it),
};

/// Requests whose latest run failed, in the order they first ran.
List<RequestNode> failedRequests(List<RunnerItem> items) {
  final last = lastStatuses(items);
  final seen = <String>{};
  return [
    for (final it in items)
      if (last[it.node.path] == RunStatus.failed && seen.add(it.node.path))
        it.node,
  ];
}

/// Folder of [path] relative to [base] (a collection or folder path), using `/`; empty at the top level.
String folderPath(String path, String base) {
  var p = path.replaceAll('\\', '/');
  final b = base.replaceAll('\\', '/');
  if (p.startsWith('$b/')) p = p.substring(b.length + 1);
  final i = p.lastIndexOf('/');
  return i < 0 ? '' : p.substring(0, i);
}

/// `850 ms`, `1.2 s`, `2m 05s`.
String formatDuration(int ms) {
  if (ms < 1000) return '$ms ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} s';
  final s = (ms / 1000).round();
  return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
}

/// Method and URL of an item, preferring what was actually sent.
(String, String) requestLine(RunnerItem it) {
  final req = it.result.request;
  return (
    req?.method ?? it.node.request.method,
    req?.url ?? it.node.request.url,
  );
}

String _statusText(RunnerItem it) {
  final resp = responseOf(it);
  return resp == null ? '-' : '${resp.status}';
}

/// Plain-text report of a run.
String reportText({
  required String title,
  required List<RunnerItem> items,
  required int elapsedMs,
}) {
  final s = summarize(items);
  final b = StringBuffer()
    ..writeln('Run: $title')
    ..writeln(
      'Requests: ${s.total}  Passed: ${s.passed}  Failed: ${s.failed}  Skipped: ${s.skipped}',
    )
    ..writeln('Tests: ${s.testsPassed}/${s.testsTotal} passed')
    ..writeln('Time: ${formatDuration(elapsedMs)}  Avg response: ${s.avgMs} ms')
    ..writeln();
  for (final it in items) {
    final st = statusOf(it);
    final (method, url) = requestLine(it);
    final resp = responseOf(it);
    final tag = switch (st) {
      RunStatus.passed => 'PASS',
      RunStatus.failed => 'FAIL',
      RunStatus.skipped => 'SKIP',
    };
    final tests = it.result.tests;
    b.write(
      '[$tag] ${it.node.name}  $method $url  ${_statusText(it)}  ${resp?.timeMs ?? 0} ms',
    );
    if (tests.isNotEmpty) {
      b.write('  tests ${tests.where((t) => t.passed).length}/${tests.length}');
    }
    b.writeln();
    if (it.result.error != null) b.writeln('    error: ${it.result.error}');
    if (resp == null && it.result.response?.error != null) {
      b.writeln('    error: ${it.result.response!.error}');
    }
    for (final t in tests.where((t) => !t.passed)) {
      b.writeln(
        '    failed: ${t.name}${t.message.isEmpty ? '' : ' - ${t.message}'}',
      );
    }
  }
  return b.toString().trimRight();
}

/// JSON export of a run: name, method, url, status, time and tests per item.
String resultsJson(String title, List<RunnerItem> items) {
  final s = summarize(items);
  final data = {
    'run': title,
    'summary': {
      'total': s.total,
      'passed': s.passed,
      'failed': s.failed,
      'skipped': s.skipped,
      'testsPassed': s.testsPassed,
      'testsTotal': s.testsTotal,
      'totalResponseMs': s.totalMs,
    },
    'results': [
      for (final it in items)
        {
          'name': it.node.name,
          'iteration': it.iteration + 1,
          'method': requestLine(it).$1,
          'url': requestLine(it).$2,
          'result': statusOf(it).name,
          'status': responseOf(it)?.status,
          'timeMs': responseOf(it)?.timeMs,
          'error': it.result.error ?? it.result.response?.error,
          'tests': [
            for (final t in it.result.tests)
              {'name': t.name, 'passed': t.passed, 'message': t.message},
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Applied settings as a short line, e.g. `2 iterations · 100 ms delay · stop on failure`; `Defaults` when none differ.
String settingsSummary({
  required int iterations,
  required int delayMs,
  required bool stopOnFail,
}) {
  final parts = [
    if (iterations != 1) '$iterations iterations',
    if (delayMs > 0) '$delayMs ms delay',
    if (stopOnFail) 'stop on failure',
  ];
  return parts.isEmpty ? 'Defaults' : parts.join(' · ');
}
