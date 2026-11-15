import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/env_logic.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

Finder _field(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

void main() {
  group('bulk text', () {
    test('parses KEY=value lines, skipping blanks and comments', () {
      final v = parseBulk('# c\n\nA=1\r\nB = x=y \nC\n  # indented\n');
      expect(v.map((e) => e.name), ['A', 'B', 'C']);
      expect(v.map((e) => e.value), ['1', ' x=y ', '']);
    });

    test('round-trips variables', () {
      const vars = [
        KV(name: 'url', value: 'https://a/b?x=1&y=2'),
        KV(name: 'empty'),
        KV(name: 'sp', value: '  padded '),
      ];
      expect(parseBulk(serializeBulk(vars)), vars);
    });

    test('secret flags follow names', () {
      final vars = parseBulk('a=1\nb=2');
      expect(secretsFor({'a', 'gone'}, vars), {'a'});
    });
  });

  group('names', () {
    test('validation', () {
      expect(validateEnvName('', []), isNotNull);
      expect(validateEnvName('  ', []), isNotNull);
      expect(validateEnvName('a/b', []), isNotNull);
      expect(validateEnvName(r'a\b', []), isNotNull);
      expect(validateEnvName('..', []), isNotNull);
      expect(validateEnvName('dev', ['Dev']), isNotNull);
      expect(validateEnvName('dev', ['dev'], self: 'dev'), isNull);
      expect(validateEnvName(' prod ', ['dev']), isNull);
    });

    test('unique suffix and duplicate variables', () {
      expect(uniqueEnvName('x copy', ['x copy', 'x copy 2']), 'x copy 3');
      expect(
        duplicateVarNames(const [
          KV(name: 'a'),
          KV(name: 'a'),
          KV(),
          KV(),
          KV(name: 'b'),
        ]),
        {'a'},
      );
    });

    test('drafts compare against the saved environment', () {
      const e = Environment(
        name: 'dev',
        vars: [KV(name: 'a', value: '1')],
        secrets: {'a'},
      );
      expect(EnvDraft.of(e).differsFrom(e), isFalse);
      expect(
        EnvDraft.of(e).copyWith(vars: [...e.vars, const KV()]).differsFrom(e),
        isFalse,
      );
      expect(EnvDraft.of(e).copyWith(name: 'dev2').differsFrom(e), isTrue);
      expect(EnvDraft.of(e).copyWith(secrets: {}).differsFrom(e), isTrue);
    });
  });

  testWidgets('create, edit, switch with draft, delete', (t) async {
    useTempHome();
    final orig = FlutterError.onError;
    captureErrors();
    try {
      t.view.physicalSize = const Size(1360, 860);
      t.view.devicePixelRatio = 1;
      final s = AppState();
      await t.pumpWidget(host(s));
      await t.pump();
      s.modal = const ModalEnvs();
      await t.pump(const Duration(milliseconds: 200));

      expect(find.text('Create your first environment'), findsOneWidget);
      await t.tap(find.text('Create your first environment'));
      await t.pump();
      await t.enterText(_field('Environment name').first, 'dev');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(s.globalEnvs.map((e) => e.name), ['dev']);

      // second environment through the list footer
      await t.tap(find.text('+ New environment'));
      await t.pump();
      await t.enterText(_field('Environment name').first, 'prod');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(s.globalEnvs.map((e) => e.name), ['dev', 'prod']);

      // edit prod: add a variable
      await t.tap(find.text('Add variable'));
      await t.pump();
      await t.enterText(_field('Variable'), 'host');
      await t.pump();
      await t.enterText(_field('Value'), 'example.com');
      await t.pump();
      expect(find.text('1 variable'), findsWidgets);
      expect(s.globalEnvs.last.vars, isEmpty);

      // switch to dev and back: the draft is kept
      await t.tap(find.text('dev').first);
      await t.pump();
      await t.tap(find.text('prod').first);
      await t.pump();
      expect(_field('Variable'), findsOneWidget);
      expect(
        (t.widget<TextField>(_field('Variable')).controller!.text),
        'host',
      );

      // closing asks about the draft; Cancel keeps the dialog
      await t.tap(find.text('Close'));
      await t.pump();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pump();
      expect(s.modal, isA<ModalEnvs>());

      await t.tap(find.text('Save'));
      await t.pump();
      expect(s.globalEnvs.last.vars.single.name, 'host');

      // delete needs confirmation
      await t.tap(find.text('Delete'));
      await t.pump();
      expect(s.globalEnvs.length, 2);
      await t.tap(find.text('Delete').last);
      await t.pump();
      expect(s.globalEnvs.map((e) => e.name), ['dev']);

      await t.tap(find.text('Close'));
      await t.pump();
      expect(s.modal, isNull);
      await t.pump(const Duration(seconds: 5));
      expect(errors(t), isEmpty);
    } finally {
      FlutterError.onError = orig;
    }
  });

  testWidgets('row delete button asks first and removes the environment', (
    t,
  ) async {
    useTempHome();
    final orig = FlutterError.onError;
    captureErrors();
    try {
      t.view.physicalSize = const Size(1360, 860);
      t.view.devicePixelRatio = 1;
      final s = AppState();
      s.saveGlobalEnvironment(const Environment(name: 'a'), null);
      s.saveGlobalEnvironment(const Environment(name: 'b'), null);
      s.saveGlobalEnvironment(const Environment(name: 'c'), null);
      await t.pumpWidget(host(s));
      await t.pump();
      s.modal = const ModalEnvs();
      await t.pump(const Duration(milliseconds: 200));

      // 'a' is selected so it shows the button; 'c' only on hover
      expect(find.byKey(const ValueKey('del-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('del-c')), findsNothing);
      final g = await t.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      await g.moveTo(t.getCenter(find.text('c').first));
      await t.pump();
      expect(find.byKey(const ValueKey('del-c')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('del-c')));
      await t.pump();
      expect(find.textContaining('Delete "c"?'), findsOneWidget);
      expect(s.globalEnvs.length, 3);
      await t.tap(find.text('Delete').last);
      await t.pump();
      expect(s.globalEnvs.map((e) => e.name), ['a', 'b']);
      // the selection stayed on 'a'
      expect(
        t.widget<TextField>(_field('Environment name').first).controller!.text,
        'a',
      );

      // deleting the selected row selects the next one
      await t.tap(find.byKey(const ValueKey('del-a')));
      await t.pump();
      await t.tap(find.text('Delete').last);
      await t.pump();
      expect(s.globalEnvs.map((e) => e.name), ['b']);
      expect(
        t.widget<TextField>(_field('Environment name').first).controller!.text,
        'b',
      );
      await t.pump(const Duration(seconds: 5));
      expect(errors(t), isEmpty);
    } finally {
      FlutterError.onError = orig;
    }
  });
}
