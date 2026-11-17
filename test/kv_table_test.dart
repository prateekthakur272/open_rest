import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Material, MaterialApp;
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// A multipart-style table whose file dialog "returns" [picked]; the rows after every change are kept in [rows].
Widget _table(
  List<KV> rows,
  List<String> picked,
  void Function(List<KV>) onChange,
) => MaterialApp(
  theme: OpenRestTheme.data(true),
  home: Material(
    child: OpenRestTheme(
      dark: true,
      child: SizedBox(
        width: 900,
        height: 500,
        child: KVTable(
          items: rows,
          onChange: onChange,
          allowFile: true,
          onPickFiles: () async => picked,
        ),
      ),
    ),
  ),
);

void main() {
  const row = KV(name: 'files', isFile: true, contentType: 'image/png');

  testWidgets(
    'several picked files become one row each, with the same field name',
    (t) async {
      var rows = <KV>[
        const KV(name: 'title', value: 'hello'),
        row,
        const KV(name: 'after', value: 'x'),
      ];
      late void Function(void Function()) rebuild;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _table(rows, ['/a/one.png', '/a/two.png', '/a/three.png'], (
              v,
            ) {
              rebuild(() => rows = v);
            });
          },
        ),
      );
      await t.pump();

      await t.tap(find.byIcon(Ic.folder));
      await t.pump();

      expect(rows.map((r) => r.name).toList(), [
        'title',
        'files',
        'files',
        'files',
        'after',
      ]);
      expect(rows.map((r) => r.value).toList(), [
        'hello',
        '/a/one.png',
        '/a/two.png',
        '/a/three.png',
        'x',
      ]);
      // The extra rows are file rows too and keep the content type.
      for (final r in rows.sublist(1, 4)) {
        expect(r.isFile, isTrue);
        expect(r.contentType, 'image/png');
        expect(r.enabled, isTrue);
      }
    },
  );

  testWidgets('one file fills the row and adds nothing', (t) async {
    var rows = <KV>[row];
    late void Function(void Function()) rebuild;
    await t.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return _table(rows, ['/a/one.png'], (v) => rebuild(() => rows = v));
        },
      ),
    );
    await t.pump();
    await t.tap(find.byIcon(Ic.folder));
    await t.pump();
    expect(rows.length, 1);
    expect(rows.single.value, '/a/one.png');
  });

  testWidgets('cancelling the dialog changes nothing', (t) async {
    var calls = 0;
    await t.pumpWidget(_table([row], const [], (_) => calls++));
    await t.pump();
    await t.tap(find.byIcon(Ic.folder));
    await t.pump();
    expect(calls, 0);
  });

  group('file name display', () {
    const path = '/Users/me/Documents/photos/photo.png';

    Widget table(List<KV> rows) => _table(rows, const [], (_) {});

    testWidgets('shows only the file name', (t) async {
      await t.pumpWidget(table([row.copyWith(value: path)]));
      await t.pump();
      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text(path), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('hovering reveals the full path', (t) async {
      await t.pumpWidget(table([row.copyWith(value: path)]));
      await t.pump();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      expect(find.text(path), findsNothing);
      await mouse.moveTo(t.getCenter(find.text('photo.png')));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(path), findsOneWidget);
      await mouse.moveTo(const Offset(5, 5));
      await t.pump(const Duration(seconds: 2));
      expect(find.text(path), findsNothing);
    });

    testWidgets('clicking the name edits the full path', (t) async {
      var rows = [row.copyWith(value: path)];
      late void Function(void Function()) rebuild;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _table(rows, const [], (v) => rebuild(() => rows = v));
          },
        ),
      );
      await t.pump();
      await t.tap(find.text('photo.png'));
      await t.pump();
      await t.pump();
      expect(find.text(path), findsOneWidget);
      await t.enterText(find.text(path), '/other/doc.pdf');
      await t.pump();
      expect(rows.single.value, '/other/doc.pdf');
      // Leaving the field shows the new name again.
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump();
      expect(find.text('doc.pdf'), findsOneWidget);
    });

    testWidgets('an empty value is an editable field with a placeholder', (
      t,
    ) async {
      await t.pumpWidget(table([row]));
      await t.pump();
      expect(find.text('File path'), findsOneWidget);
      expect(find.byType(EditableText), findsWidgets);
    });

    testWidgets('a path with a variable shows its last part', (t) async {
      await t.pumpWidget(table([row.copyWith(value: '{{assets}}/logo.svg')]));
      await t.pump();
      expect(find.text('logo.svg'), findsOneWidget);
      expect(find.text('{{assets}}/logo.svg'), findsNothing);
    });
  });
}
