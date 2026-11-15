import 'dart:ui' show Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/storage/storage.dart';

import 'package:open_rest/theme/icons.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

void main() {
  testWidgets('runner shows summary, grouped results and expands a row', (
    t,
  ) async {
    useTempHome();
    captureErrors();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = AppState();
    final dir = Collections.create(tempDir('runner'), 'Demo');
    s.openCollection(dir);
    final col = s.collections.first;
    s.createRequest(col.path, col.path, 'Alpha', 'GET', 'http://x/a');
    s.createRequest(col.path, col.path, 'Beta', 'POST', 'http://x/b');
    s.openRunner(col.path, null);
    await t.pumpWidget(host(s));
    await t.pump();
    final tab = s.activeTab!;
    final rs = tab.runner!;
    expect(find.text('REQUESTS'), findsOneWidget);
    expect(find.text('Run 2 Requests'), findsOneWidget);
    expect(find.text('No results yet'), findsOneWidget);

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Defaults'), findsOneWidget);
    expect(find.text('Iterations'), findsNothing);
    await t.tap(find.text('SETTINGS'));
    await t.pumpAndSettle();
    expect(rs.settingsOpen, isTrue);
    expect(find.text('Defaults'), findsNothing);
    expect(find.text('Iterations'), findsOneWidget);
    expect(find.text('Delay (ms)'), findsOneWidget);
    expect(find.text('Stop on failure'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsNothing);
    await t.tap(find.text('SETTINGS'));
    await t.pumpAndSettle();
    expect(find.text('Defaults'), findsOneWidget);
    await t.tap(find.text('SETTINGS'));
    await t.pumpAndSettle();
    rs.iterations = '3';
    await t.pump();
    await t.tap(find.text('Reset to defaults'));
    await t.pump();
    expect(rs.iterations, '1');
    expect(find.text('Reset to defaults'), findsNothing);

    final nodes = rs.order.toList();
    ExecResult ok(int ms) => ExecResult(
      response: HttpResult(status: 200, timeMs: ms, body: Uint8List(2048)),
      tests: const [TestResult(name: 'status', passed: true)],
    );
    rs.iterations = '2';
    rs.planned = 4;
    rs.startedAt = DateTime.now();
    for (var i = 0; i < 2; i++) {
      rs.results.add(RunnerItem(nodes[0], ok(20), iteration: i));
      rs.results.add(
        RunnerItem(
          nodes[1],
          ExecResult(
            response: HttpResult(status: 500, timeMs: 40),
            tests: const [
              TestResult(name: 'is ok', passed: false, message: 'got 500'),
            ],
          ),
          iteration: i,
        ),
      );
    }
    rs.finishedAt = DateTime.now();
    await t.pump();

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Iteration 1'), findsOneWidget);
    expect(find.text('Iteration 2'), findsOneWidget);
    expect(find.text('Failed 2'), findsOneWidget);
    expect(find.text('Re-run failed (2)'), findsNothing); // one node, deduped
    expect(find.text('Re-run failed (1)'), findsOneWidget);
    expect(find.text('Copy summary'), findsOneWidget);
    expect(find.text('2.0 KB'), findsWidgets);

    await t.tap(find.text('Failed 2'));
    await t.pump();
    expect(find.text('Alpha'), findsWidgets); // still in the request list
    await t.tap(find.text('Beta').last);
    await t.pump();
    expect(find.text('FAILED TESTS'), findsOneWidget);
    expect(find.text('got 500'), findsOneWidget);

    await t.tap(find.text('Iteration 1'));
    await t.pump();
    expect(find.text('Iteration 2'), findsOneWidget);
    // Status icons in the request list share one column.
    final xs = {
      for (final ic in [Ic.checkCircle, Ic.cancel])
        for (final e in find.byIcon(ic).evaluate())
          if (t.getCenter(find.byElementPredicate((x) => x == e)).dx < 560)
            t.getCenter(find.byElementPredicate((x) => x == e)).dx,
    };
    expect(xs.length, 1);
    expect(errors, isEmpty);
  });

  testWidgets('empty selection disables Run and says why', (t) async {
    useTempHome();
    captureErrors();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = AppState();
    s.openCollection(Collections.create(tempDir('runner_empty'), 'Empty'));
    final col = s.collections.first;
    s.openRunner(col.path, null);
    await t.pumpWidget(host(s));
    await t.pump();
    expect(find.text('No requests in this collection'), findsOneWidget);
    expect(find.text('Select at least one request to run'), findsOneWidget);
    expect(errors, isEmpty);
  });
}
