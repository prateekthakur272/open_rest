import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/features/dialogs/vars_dialog.dart';
import 'package:open_rest/features/dialogs/vars_logic.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

final _dialogFields = find.descendant(
  of: find.byType(VarsDialog),
  matching: find.byType(TextField),
);

void main() {
  const env = Environment(
    name: 'dev',
    vars: [
      KV(name: 'host', value: 'dev.local'),
      KV(name: 'token', value: 's3cret'),
      KV(name: 'off', value: 'x', enabled: false),
    ],
    secrets: {'token'},
  );
  const glob = Environment(
    name: 'shared',
    vars: [
      KV(name: 'host', value: 'global.local'),
      KV(name: 'zone', value: 'eu'),
    ],
  );

  group('collectVars', () {
    final groups = collectVars(
      runtime: {'host': 'rt.local', 'count': 3},
      env: env,
      collectionVars: const [
        KV(name: 'host', value: 'coll.local'),
        KV(name: 'base', value: '/api'),
        KV(name: 'dup', value: 'a'),
        KV(name: 'dup', value: 'b'),
      ],
      global: glob,
    );
    VarGroup g(String n) => groups.firstWhere((x) => x.name == n);

    test('sorted by name, disabled skipped', () {
      expect(groups.map((x) => x.name), [
        'base',
        'count',
        'dup',
        'host',
        'token',
        'zone',
      ]);
    });

    test('precedence is runtime, environment, collection, global', () {
      final h = g('host');
      expect(h.entries.map((e) => e.source), [
        VarSource.runtime,
        VarSource.environment,
        VarSource.collection,
        VarSource.global,
      ]);
      expect(h.winner.value, 'rt.local');
      expect(h.overridden.map((e) => e.label), [
        'Environment: dev',
        'Collection',
        'Global: shared',
      ]);
    });

    test('values, secrets and duplicates', () {
      expect(g('count').winner.value, '3');
      expect(g('token').winner.secret, isTrue);
      expect(g('dup').entries.single.value, 'b');
      expect(g('zone').winner.label, 'Global: shared');
    });

    test('environment overrides replace and add values', () {
      final o = collectVars(
        env: env,
        envOverrides: {'host': 'new', 'extra': '1'},
      );
      expect(o.firstWhere((x) => x.name == 'host').winner.value, 'new');
      expect(o.any((x) => x.name == 'extra'), isTrue);
    });

    test('empty input gives no groups', () => expect(collectVars(), isEmpty));
  });

  group('filterVars', () {
    final groups = collectVars(env: env, global: glob);
    test('matches names and values, case-insensitive', () {
      expect(filterVars(groups, 'HOS').map((g) => g.name), ['host']);
      expect(filterVars(groups, 'eu').map((g) => g.name), ['zone']);
      expect(filterVars(groups, '  '), groups);
    });
    test('does not match secret values', () {
      expect(filterVars(groups, 's3cret'), isEmpty);
    });
    test('count label', () {
      expect(varCountLabel(1), '1 variable');
      expect(varCountLabel(4), '4 variables');
    });
  });

  test('runtime text round-trips types', () {
    expect(runtimeText(null), '');
    expect(runtimeText({'a': 1}), '{"a":1}');
    expect(parseRuntimeText('5', 3), 5);
    expect(parseRuntimeText('5', 'x'), '5');
    expect(parseRuntimeText('nope{', 3), 'nope{');
  });

  testWidgets('variables dialog inspects, filters and edits runtime values', (
    t,
  ) async {
    useTempHome();
    final oldOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldOnError);
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    final s = AppState();
    final dir = Collections.create(tempDir('vars'), 'V');
    s.openCollection(dir);
    await t.pumpWidget(host(s));
    await t.pump();
    final col = s.collections.first;
    s.modal = ModalVars(collection: col.path);
    await t.pump();
    expect(find.textContaining('No variables yet.'), findsWidgets);
    expect(find.text('Open environments'), findsOneWidget);

    s.runtime(col.path)['host'] = 'rt.local';
    s.runtime(col.path)['n'] = 1;
    await t.pump();
    expect(find.text('2 variables'), findsOneWidget);
    expect(find.text('rt.local'), findsOneWidget);
    expect(find.text('Runtime'), findsWidgets);

    // Hover reveals the row actions; edit the value in place.
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('rt.local')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('edit-Runtime|host')));
    await t.pump();
    await t.enterText(_dialogFields.last, 'changed');
    await t.tap(find.byKey(const ValueKey('edit-save')));
    await t.pump();
    expect(s.runtime(col.path)['host'], 'changed');

    // Filtering narrows the list.
    await t.enterText(_dialogFields.first, 'chang');
    await t.pump();
    expect(find.text('1 variable'), findsOneWidget);

    await mouse.moveTo(t.getCenter(find.text('changed')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('delete-Runtime|host')));
    await t.pump();
    expect(s.runtime(col.path).containsKey('host'), isFalse);
    final errs = errors(t);
    s.modal = null;
    expect(errs, isEmpty);
    await t.pump();
  });

  testWidgets('shadowed values collapse under the winner; secrets reveal', (
    t,
  ) async {
    useTempHome();
    final oldOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldOnError);
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    final s = AppState();
    s.openCollection(Collections.create(tempDir('vars2'), 'V'));
    final col = s.collections.first;
    s.saveEnvironment(col.path, env, null);
    s.setEnv(col.path, 'dev');
    s.saveGlobalEnvironment(glob, null);
    s.setGlobalEnv('shared');
    await t.pumpWidget(host(s));
    await t.pump();
    s.modal = ModalVars(collection: col.path);
    await t.pump();
    expect(find.text('dev.local'), findsOneWidget);
    expect(find.text('global.local'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('chevron-host')));
    await t.pump();
    expect(find.text('global.local'), findsOneWidget);
    expect(find.text('overridden by Environment: dev'), findsOneWidget);

    expect(find.text('s3cret'), findsNothing);
    expect(find.text('\u2022\u2022\u2022\u2022\u2022\u2022'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('reveal-Environment: dev|token')));
    await t.pump();
    expect(find.text('s3cret'), findsOneWidget);
    final errs = errors(t);
    s.modal = null;
    expect(errs, isEmpty);
  });
}
