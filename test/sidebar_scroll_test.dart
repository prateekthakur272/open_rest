import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Material, MaterialApp;
import 'package:open_rest/components/text.dart';
import 'package:open_rest/features/sidebar/tree.dart';
import 'package:open_rest/theme/theme.dart';

/// A scrollable list of real sidebar rows that records the drag callbacks.
class _Harness {
  final starts = <int>[];
  final moves = <double>[];
  final ends = <int>[];
  final controller = ScrollController();

  Widget build() => MaterialApp(
    theme: OpenRestTheme.data(true),
    home: Material(
      child: OpenRestTheme(
        dark: true,
        child: SizedBox(
          width: 300,
          height: 300,
          child: ListView.builder(
            controller: controller,
            itemCount: 40,
            itemExtent: 30,
            itemBuilder: (context, i) => TreeRow(
              key: ValueKey('row-$i'),
              rowKey: 'r:$i',
              depth: 0,
              selected: false,
              onClick: () {},
              items: const [],
              cursor: false,
              drag: DragCtx(
                onStart: () => starts.add(i),
                onMove: moves.add,
                onEnd: () => ends.add(i),
                mode: null,
                dragging: false,
              ),
              content: (_) => [T('row $i')],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'trackpad scrolling over a row scrolls the list and never starts a drag',
    (t) async {
      final h = _Harness();
      await t.pumpWidget(h.build());
      final at = t.getCenter(find.text('row 3'));

      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      await t.sendEventToBinding(pad.panZoomStart(at));
      for (var i = 1; i <= 6; i++) {
        await t.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(0, -40.0 * i)),
        );
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.sendEventToBinding(pad.panZoomEnd());
      await t.pumpAndSettle();

      expect(
        h.controller.offset,
        greaterThan(0),
        reason: 'the list should have scrolled',
      );
      expect(
        h.starts,
        isEmpty,
        reason: 'a scroll must not start dragging a row',
      );
      expect(h.moves, isEmpty);
    },
  );

  testWidgets('a diagonal trackpad scroll does not drag a row either', (
    t,
  ) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    final at = t.getCenter(find.text('row 5'));
    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    await t.sendEventToBinding(pad.panZoomStart(at));
    for (var i = 1; i <= 6; i++) {
      await t.sendEventToBinding(
        pad.panZoomUpdate(at, pan: Offset(30.0 * i, -30.0 * i)),
      );
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.sendEventToBinding(pad.panZoomEnd());
    await t.pumpAndSettle();
    expect(h.starts, isEmpty);
  });

  testWidgets('dragging a row with the mouse still starts a drag', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    final mouse = await t.startGesture(
      t.getCenter(find.text('row 3')),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 20));
    await t.pump();
    await mouse.moveBy(const Offset(0, 20));
    await t.pump();
    await mouse.up();
    await t.pump();
    expect(h.starts, [3]);
    expect(h.moves, isNotEmpty);
    expect(h.ends, [3]);
  });
}
