import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/shell/app.dart';
import 'package:open_rest/theme/theme.dart';

import 'helpers.dart';

Widget _themed(Widget child) => MaterialApp(
  theme: OpenRestTheme.data(true),
  home: Material(child: OpenRestTheme(dark: true, child: child)),
);

bool _resizeCursor(Widget w) =>
    w is MouseRegion &&
    (w.cursor == SystemMouseCursors.resizeLeftRight ||
        w.cursor == SystemMouseCursors.resizeUpDown);

/// A two-finger trackpad swipe starting on [at]: what scrolling looks like to Flutter.
Future<void> _trackpadSwipe(WidgetTester t, Offset at, Offset total) async {
  final pad = TestPointer(1, PointerDeviceKind.trackpad);
  await t.sendEventToBinding(pad.panZoomStart(at));
  for (var i = 1; i <= 8; i++) {
    await t.sendEventToBinding(pad.panZoomUpdate(at, pan: total * (i / 8)));
    await t.pump(const Duration(milliseconds: 16));
  }
  await t.sendEventToBinding(pad.panZoomEnd());
  await t.pump();
}

Future<void> _mouseDrag(WidgetTester t, Offset at, Offset by) async {
  final g = await t.startGesture(at, kind: PointerDeviceKind.mouse);
  await g.moveBy(by / 2);
  await t.pump();
  await g.moveBy(by / 2);
  await t.pump();
  await g.up();
  await t.pump();
}

void main() {
  for (final vertical in [true, false]) {
    group('split pane (${vertical ? 'stacked' : 'side by side'})', () {
      Widget pane(List<double> fractions) => _themed(
        SizedBox(
          width: 600,
          height: 400,
          child: SplitPane(
            vertical: vertical,
            fraction: 0.5,
            onFraction: fractions.add,
            first: const SizedBox.expand(),
            second: const SizedBox.expand(),
          ),
        ),
      );
      Finder handle() => find.descendant(
        of: find.byType(SplitPane),
        matching: find.byWidgetPredicate(_resizeCursor),
      );

      testWidgets('scrolling over the divider does not resize it', (t) async {
        final fractions = <double>[];
        await t.pumpWidget(pane(fractions));
        await _trackpadSwipe(
          t,
          t.getCenter(handle()),
          vertical ? const Offset(0, 80) : const Offset(80, 0),
        );
        expect(fractions, isEmpty);
      });

      testWidgets('dragging the divider with the mouse still resizes', (
        t,
      ) async {
        final fractions = <double>[];
        await t.pumpWidget(pane(fractions));
        await _mouseDrag(
          t,
          t.getCenter(handle()),
          vertical ? const Offset(0, 40) : const Offset(40, 0),
        );
        expect(fractions, isNotEmpty);
      });
    });
  }

  group('sidebar divider', () {
    Future<(AppState, Offset)> shell(WidgetTester t) async {
      useTempHome();
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.toString().contains('overflowed')) prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final s = AppState();
      await t.pumpWidget(
        MaterialApp(
          theme: OpenRestTheme.data(true),
          builder: (c, child) => AppScope(
            state: s,
            child: OpenRestTheme(dark: true, child: child!),
          ),
          home: Material(child: OpenRestApp(state: s)),
        ),
      );
      await t.pump();
      // The first resize cursor in the tree is the sidebar's divider.
      final divider = find.byWidgetPredicate(_resizeCursor).first;
      return (s, t.getCenter(divider));
    }

    testWidgets('scrolling over it does not resize the sidebar', (t) async {
      final (s, at) = await shell(t);
      final before = s.sidebarWidth;
      await _trackpadSwipe(t, at, const Offset(120, 0));
      expect(s.sidebarWidth, before);
    });

    testWidgets('dragging it with the mouse resizes the sidebar', (t) async {
      final (s, at) = await shell(t);
      final before = s.sidebarWidth;
      await _mouseDrag(t, at, const Offset(60, 0));
      expect(s.sidebarWidth, greaterThan(before));
    });
  });

  group('table column divider', () {
    Widget table() => _themed(
      SizedBox(
        width: 800,
        height: 300,
        child: KVTable(
          items: const [KV(name: 'a', value: 'b')],
          onChange: (_) {},
        ),
      ),
    );

    testWidgets('scrolling over it does not move the columns', (t) async {
      await t.pumpWidget(table());
      final value = find.text('VALUE');
      final before = t.getTopLeft(value);
      final handle = find.byWidgetPredicate(_resizeCursor).first;
      await _trackpadSwipe(t, t.getCenter(handle), const Offset(100, 0));
      expect(t.getTopLeft(value), before);
    });

    testWidgets('dragging it with the mouse moves the columns', (t) async {
      await t.pumpWidget(table());
      final value = find.text('VALUE');
      final before = t.getTopLeft(value);
      final handle = find.byWidgetPredicate(_resizeCursor).first;
      await _mouseDrag(t, t.getCenter(handle), const Offset(80, 0));
      expect(t.getTopLeft(value).dx, isNot(before.dx));
    });
  });
}
