import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/features/shell/app.dart';
import 'package:open_rest/features/shell/window_chrome.dart';
import 'package:open_rest/theme/theme.dart';

import 'helpers.dart';

/// Counts what the title bar asked the window to do.
class _Window {
  int drags = 0;
  int toggles = 0;
  int menus = 0;

  WindowChrome chrome({required bool isMac, bool maximized = false}) =>
      WindowChrome.desktop(
        isMac: isMac,
        maximized: maximized,
        onMinimize: () {},
        onToggleMaximize: () => toggles++,
        onClose: () {},
        onDragStart: () => drags++,
        onContextMenu: () => menus++,
      );
}

Widget _host(AppState s, WindowChrome chrome) => MaterialApp(
  theme: OpenRestTheme.data(true),
  builder: (c, child) => AppScope(
    state: s,
    child: OpenRestTheme(dark: true, child: child!),
  ),
  home: Material(
    child: OpenRestApp(state: s, chrome: chrome),
  ),
);

void main() {
  group('title bar gestures in isolation', () {
    Widget bar(_Window w, {Widget? inside}) => MaterialApp(
      theme: OpenRestTheme.data(true),
      home: Material(
        child: OpenRestTheme(
          dark: true,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 30,
              child: TitleBarDrag(
                onDragStart: () => w.drags++,
                onContextMenu: () => w.menus++,
                child: Stack(
                  children: [
                    const SizedBox.expand(),
                    if (inside != null) Positioned(left: 4, child: inside),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('dragging with the mouse starts a window drag', (t) async {
      final w = _Window();
      await t.pumpWidget(bar(w));
      final g = await t.startGesture(
        t.getCenter(find.byType(TitleBarDrag)),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(40, 0));
      await t.pump();
      await g.up();
      expect(w.drags, 1);
    });

    testWidgets('a trackpad swipe over the bar does not move the window', (
      t,
    ) async {
      final w = _Window();
      await t.pumpWidget(bar(w));
      final at = t.getCenter(find.byType(TitleBarDrag));
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      await t.sendEventToBinding(pad.panZoomStart(at));
      for (var i = 1; i <= 5; i++) {
        await t.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(30.0 * i, 0)),
        );
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.sendEventToBinding(pad.panZoomEnd());
      await t.pump();
      expect(w.drags, 0);
    });

    testWidgets('a right click opens the window menu', (t) async {
      final w = _Window();
      await t.pumpWidget(bar(w));
      await t.tap(
        find.byType(TitleBarDrag),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      expect(w.menus, 1);
      expect(w.drags, 0);
    });

    testWidgets('a control inside the bar still gets its own click', (t) async {
      final w = _Window();
      var clicked = 0;
      await t.pumpWidget(
        bar(
          w,
          inside: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => clicked++,
            child: const SizedBox(width: 60, height: 30),
          ),
        ),
      );
      await t.tapAt(
        t.getTopLeft(find.byType(TitleBarDrag)) + const Offset(20, 15),
      );
      await t.pump();
      expect(clicked, 1);
      expect(w.drags, 0);
    });
  });

  group('WindowChrome.desktop', () {
    testWidgets('has the same gestures on macOS and elsewhere', (t) async {
      for (final isMac in [true, false]) {
        final w = _Window();
        final c = w.chrome(isMac: isMac);
        expect(c.onDoubleClick, isNotNull, reason: 'isMac=$isMac');
        c.onDoubleClick!();
        expect(w.toggles, 1);
        await t.pumpWidget(
          MaterialApp(home: Material(child: c.dragArea(const SizedBox()))),
        );
        expect(
          find.byType(TitleBarDrag),
          findsOneWidget,
          reason: 'isMac=$isMac',
        );
      }
    });

    test('macOS keeps its traffic lights; the others draw their own buttons and menus', () {
      final mac = _Window().chrome(isMac: true);
      expect(mac.leftInset, 72);
      expect(mac.controls, isNull);
      expect(mac.inlineMenus, isFalse);
      final other = _Window().chrome(isMac: false);
      expect(other.leftInset, 0);
      expect(other.controls, isA<WindowControls>());
      expect(other.inlineMenus, isTrue);
    });
  });

  for (final isMac in [true, false]) {
    testWidgets(
      'the real title bar (isMac=$isMac): drag, double click and right click',
      (t) async {
        useTempHome();
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          if (!d.toString().contains('overflowed')) prev?.call(d);
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = const Size(1400, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        final w = _Window();
        final s = AppState();
        await t.pumpWidget(_host(s, w.chrome(isMac: isMac)));
        await t.pump();

        // A point in the title bar that holds no control: just right of the window title.
        final bar = find.byType(TitleBarDrag);
        expect(bar, findsOneWidget);
        final box = t.getRect(bar);
        final spot = Offset(box.center.dx, box.top + 8);

        // double click -> maximize / zoom / restore
        await t.tapAt(spot, kind: PointerDeviceKind.mouse);
        await t.pump(const Duration(milliseconds: 60));
        await t.tapAt(spot, kind: PointerDeviceKind.mouse);
        await t.pump(const Duration(milliseconds: 400));
        expect(w.toggles, 1, reason: 'double click');
        expect(w.drags, 0);

        // drag -> move the window
        final g = await t.startGesture(spot, kind: PointerDeviceKind.mouse);
        await g.moveBy(const Offset(50, 0));
        await t.pump();
        await g.up();
        await t.pump(const Duration(milliseconds: 400));
        expect(w.drags, 1, reason: 'drag');

        // right click -> window menu
        await t.tapAt(
          spot,
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await t.pump();
        expect(w.menus, 1, reason: 'right click');
        expect(t.takeException(), isNull);
      },
    );
  }
}
