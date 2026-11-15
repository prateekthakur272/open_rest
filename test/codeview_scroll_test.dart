import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_rest/components/code_view.dart';
import 'package:open_rest/theme/theme.dart';

void main() {
  testWidgets('CodeView extent stays stable while scrolling wrapped lines', (
    tester,
  ) async {
    final lines = <String>[];
    for (var i = 0; i < 3000; i++) {
      lines.add(
        i % 7 == 0
            ? List.filled(40 + i % 300, 'abcdefghij').join()
            : (i % 3 == 0
                  ? '<div class="x">item $i</div> ' * (1 + i % 9)
                  : 'short line $i'),
      );
    }
    final text = lines.join('\n');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpWidget(
      MaterialApp(
        theme: OpenRestTheme.data(true),
        home: PalScope(
          pal: DarkPal,
          child: Material(
            child: SizedBox(
              width: 900,
              height: 700,
              child: CodeView(text: text, lang: 'html'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final sc = tester.state<State>(find.byType(CodeView));
    final pos = (tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller)!;
    final start = pos.position.maxScrollExtent;
    final seen = <double>[];
    for (final f in [0.1, 0.5, 0.9, 0.3, 1.0, 0.0, 0.7]) {
      pos.jumpTo(pos.position.maxScrollExtent * f);
      await tester.pump();
      seen.add(pos.position.maxScrollExtent);
    }
    // ignore: avoid_print
    print('start=$start seen=$seen sc=$sc');
    for (final s in seen) {
      expect(s, closeTo(start, 0.5));
    }
    expect(tester.takeException(), isNull);
  });
}
