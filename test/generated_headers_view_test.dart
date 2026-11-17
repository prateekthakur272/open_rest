import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show host;

const _autoNames = [
  'Authorization',
  'Host',
  'User-Agent',
  'Accept',
  'Accept-Encoding',
  'Content-Type',
  'Content-Length',
];

Finder get _eye => find.byKey(const ValueKey('toggle-auto-rows'));

void main() {
  late AppState s;
  late RequestTab tab;

  Future<void> open(WidgetTester t) async {
    useTempHome();
    // Layout overflows of unrelated widgets at this window size are ignored; any other error fails.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(1500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final dir = Collections.create(tempDir('ghv'), 'G');
    s = AppState()..addCollection(dir, false);
    s.createRequest(dir, dir, 'R', 'POST', 'http://example.test:9000/x');
    tab = s.activeTab!;
    s.update(
      tab,
      (r) => r.copyWith(
        bodyMode: BodyMode.Json,
        bodyJson: '{}',
        auth: const Auth(mode: AuthMode.Bearer, token: 'abc'),
        headers: const [KV(name: 'X-Mine', value: 'mine-value')],
      ),
    );
    await t.pumpWidget(host(s));
    await t.pump();
    tab.reqTab = 'Headers';
    await t.pump();
  }

  testWidgets('the generated headers are rows of the same headers table', (
    t,
  ) async {
    await open(t);

    // One table: the request's own header and the generated ones are all inside the same KVTable.
    final table = find.byType(KVTable);
    expect(table, findsOneWidget);
    for (final name in ['X-Mine', ..._autoNames]) {
      expect(
        find.descendant(of: table, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    expect(find.text('AUTO-GENERATED'), findsOneWidget);
    expect(find.text('Bearer abc'), findsOneWidget);
    expect(find.text('example.test:9000'), findsOneWidget);
    // Generated rows come after the editable ones.
    expect(
      t.getTopLeft(find.text('Authorization')).dy,
      greaterThan(t.getTopLeft(find.text('X-Mine')).dy),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'the eye button sits before the headers count and hides and shows them',
    (t) async {
      await open(t);
      final badge = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_CountBadge',
      );
      expect(badge, findsOneWidget);
      expect(_eye, findsOneWidget);
      expect(t.getTopLeft(_eye).dx, lessThan(t.getTopLeft(badge).dx));
      expect(
        t.getTopLeft(find.text('REQUEST HEADERS')).dx,
        lessThan(t.getTopLeft(_eye).dx),
      );

      await t.tap(_eye);
      await t.pump();
      for (final name in _autoNames) {
        expect(find.text(name), findsNothing, reason: 'hidden: $name');
      }
      expect(find.text('AUTO-GENERATED'), findsNothing);
      expect(find.text('X-Mine'), findsOneWidget);
      expect(
        _eye,
        findsOneWidget,
        reason: 'the button stays so they can be shown again',
      );

      await t.tap(_eye);
      await t.pump();
      for (final name in _autoNames) {
        expect(find.text(name), findsOneWidget, reason: 'shown again: $name');
      }
    },
  );

  testWidgets('the choice is remembered', (t) async {
    await open(t);
    expect(AppStore.loadSettings().showAutoHeaders, isTrue);
    await t.tap(_eye);
    await t.pump();
    expect(s.settings.showAutoHeaders, isFalse);
    expect(AppStore.loadSettings().showAutoHeaders, isFalse);
    expect(AppSettings().showAutoHeaders, isTrue, reason: 'on by default');
  });

  testWidgets(
    'setting a header of the same name moves it out of the generated rows',
    (t) async {
      await open(t);
      s.update(
        tab,
        (r) => r.copyWith(
          headers: const [KV(name: 'User-Agent', value: 'Mine/1')],
        ),
      );
      await t.pump();
      expect(find.text('User-Agent'), findsOneWidget);
      expect(find.text('Mine/1'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('generated rows are laid out like the editable rows', (t) async {
    await open(t);
    final own = find.byKey(const ValueKey(0));
    final auto = find.byKey(const ValueKey('auto-Authorization'));
    expect(own, findsOneWidget);
    expect(auto, findsOneWidget);
    // Same row height.
    expect(t.getSize(auto).height, t.getSize(own).height);
    // Key and value text start in the same place as in the editable row above.
    expect(
      t.getTopLeft(find.text('Authorization')).dx,
      closeTo(t.getTopLeft(find.text('X-Mine')).dx, 1),
    );
    expect(
      t.getTopLeft(find.text('Bearer abc')).dx,
      closeTo(t.getTopLeft(find.text('mine-value')).dx, 1),
    );
    // Same font size and family as the editable row's text.
    final mine = t.widget<EditableText>(find.text('X-Mine')).style;
    final generated = t.widget<Text>(find.text('Authorization')).style!;
    expect(generated.fontSize, mine.fontSize);
    expect(generated.fontFamily, mine.fontFamily);
    expect(generated.color, mine.color);
    // Same columns: every generated row's value starts where the others do.
    final x = t.getTopLeft(find.text('Bearer abc')).dx;
    for (final v in ['*/*', 'gzip, deflate', 'example.test:9000']) {
      expect(t.getTopLeft(find.text(v)).dx, closeTo(x, 1), reason: v);
    }
  });

  testWidgets('the source chip is small and its text is not cut off', (
    t,
  ) async {
    await open(t);
    for (final name in ['Authorization', 'Host', 'Content-Type']) {
      final chip = find.byKey(ValueKey('auto-source-$name'));
      expect(chip, findsOneWidget, reason: name);
      expect(t.widget<Text>(chip).style!.fontSize, lessThan(10));
      // The text's line box fits inside the chip (inside its 1px border), so nothing is clipped.
      final box = find
          .ancestor(of: chip, matching: find.byType(Container))
          .first;
      expect(t.getSize(box).height, lessThanOrEqualTo(16));
      expect(
        t.getSize(chip).height,
        lessThanOrEqualTo(t.getSize(box).height - 2),
        reason: '$name chip text must fit inside the chip',
      );
      expect(t.getRect(chip).top, greaterThanOrEqualTo(t.getRect(box).top));
      expect(t.getRect(chip).bottom, lessThanOrEqualTo(t.getRect(box).bottom));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('there is no separate generated-headers table any more', (
    t,
  ) async {
    await open(t);
    expect(find.text('AUTO-GENERATED HEADERS'), findsNothing);
    expect(find.byType(ReadOnlyTable), findsNothing);
  });
}
