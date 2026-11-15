import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/features/runner/runner_logic.dart';

RunnerItem item(
  String name, {
  int status = 200,
  int ms = 10,
  List<TestResult> tests = const [],
  String? error,
  bool skipped = false,
  int iteration = 0,
  String path = '',
}) => RunnerItem(
  RequestNode(
    path: path.isEmpty ? '/c/$name.bru' : path,
    name: name,
    request: ApiRequest(name: name, url: 'http://x/$name'),
  ),
  ExecResult(
    response: skipped || error != null
        ? null
        : HttpResult(status: status, timeMs: ms, body: Uint8List(4)),
    tests: tests,
    error: error,
    skipped: skipped,
  ),
  iteration: iteration,
);

const pass = TestResult(name: 'ok', passed: true);
const fail = TestResult(name: 'bad', passed: false, message: 'nope');

void main() {
  final items = [
    item('a', tests: [pass, pass]),
    item('b', ms: 30, tests: [pass, fail]),
    item('c', error: 'boom'),
    item('d', skipped: true),
    item('a', iteration: 1, tests: [pass]),
  ];

  test('status classification', () {
    expect(items.map(statusOf), [
      RunStatus.passed,
      RunStatus.failed,
      RunStatus.failed,
      RunStatus.skipped,
      RunStatus.passed,
    ]);
  });

  test('summary counts, timing and tests', () {
    final s = summarize(items);
    expect((s.passed, s.failed, s.skipped, s.total), (2, 2, 1, 5));
    expect(s.totalMs, 50);
    expect(s.avgMs, 17);
    expect((s.testsPassed, s.testsTotal), (4, 5));
    expect(summarize(const []).avgMs, 0);
  });

  test('filters keep original indices', () {
    expect(filterIndices(items, ResultFilter.all), [0, 1, 2, 3, 4]);
    expect(filterIndices(items, ResultFilter.failed), [1, 2]);
    expect(filterIndices(items, ResultFilter.passed), [0, 4]);
    expect(filterIndices(items, ResultFilter.skipped), [3]);
  });

  test('grouping by iteration', () {
    final g = groupByIteration(items, [0, 1, 2, 3, 4]);
    expect(g.map((e) => e.iteration), [0, 1]);
    expect(g[0].indices, [0, 1, 2, 3]);
    expect(g[0].summary.failed, 2);
    expect(g[1].summary.passed, 1);
    expect(groupByIteration(items, [1, 4]).map((e) => e.indices), [
      [1],
      [4],
    ]);
  });

  test('last status and failed requests use the latest run', () {
    final again = [...items, item('b', iteration: 1)];
    expect(failedRequests(items).map((n) => n.name), ['b', 'c']);
    expect(failedRequests(again).map((n) => n.name), ['c']);
    expect(lastStatuses(again)['/c/b.bru'], RunStatus.passed);
  });

  test('folder path is relative to the base', () {
    expect(folderPath('/c/api/users/get.bru', '/c'), 'api/users');
    expect(folderPath('/c/get.bru', '/c'), '');
    expect(folderPath('/c/api/users/get.bru', '/c/api'), 'users');
    expect(folderPath(r'C:\c\api\get.bru', r'C:\c'), 'api');
  });

  test('duration formatting', () {
    expect(formatDuration(850), '850 ms');
    expect(formatDuration(1234), '1.2 s');
    expect(formatDuration(125000), '2m 05s');
  });

  test('report text lists failures', () {
    final t = reportText(title: 'API', items: items, elapsedMs: 1500);
    expect(t, contains('Run: API'));
    expect(t, contains('Passed: 2  Failed: 2  Skipped: 1'));
    expect(t, contains('Tests: 4/5 passed'));
    expect(t, contains('[FAIL] b'));
    expect(t, contains('failed: bad - nope'));
    expect(t, contains('error: boom'));
    expect(t, contains('[SKIP] d'));
  });

  test('json export', () {
    final j = jsonDecode(resultsJson('API', items)) as Map<String, dynamic>;
    final rs = j['results'] as List;
    expect(rs.length, 5);
    expect(rs[1]['name'], 'b');
    expect(rs[1]['result'], 'failed');
    expect(rs[1]['status'], 200);
    expect(rs[1]['tests'][1]['passed'], false);
    expect(rs[2]['error'], 'boom');
    expect(j['summary']['failed'], 2);
  });

  test('settings summary lists only non-default values', () {
    expect(
      settingsSummary(iterations: 2, delayMs: 100, stopOnFail: true),
      '2 iterations · 100 ms delay · stop on failure',
    );
    expect(
      settingsSummary(iterations: 1, delayMs: 0, stopOnFail: false),
      'Defaults',
    );
  });

  test('min, max and stat captions', () {
    final s = summarize(items);
    expect((s.minMs, s.maxMs), (10, 30));
    expect(passPercent(s), 40);
    expect(passedCaption(s), '40% of 5');
    expect(failedCaption(s), '2 need attention');
    expect(skippedCaption(s), 'not run');
    expect(avgCaption(s), 'min 10 ms · max 30 ms');
    expect(testsValue(s), '4/5');
    expect(testsCaption(s), '5 assertions');
    const none = RunSummary();
    expect(passedCaption(none), '—');
    expect(failedCaption(none), 'none');
    expect(skippedCaption(none), 'none');
    expect(avgCaption(none), '—');
    expect(testsValue(none), '—');
    expect(testsCaption(none), 'no tests');
  });
}
