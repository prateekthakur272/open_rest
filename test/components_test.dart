import 'package:flutter/widgets.dart' show TextSpan, Color;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/components/syntax_highlight.dart';
import 'package:open_rest/components/editing.dart';
import 'package:open_rest/theme/theme.dart';

void main() {
  TextEditingValue tv(String s, [int? at]) => TextEditingValue(
    text: s,
    selection: TextSelection.collapsed(offset: at ?? s.length),
  );
  TextEditingValue type(
    TextEditingValue old,
    String c, [
    String lang = 'json',
  ]) {
    final p = old.selection.start;
    return smartEdit(
      old,
      TextEditingValue(
        text: old.text.substring(0, p) + c + old.text.substring(p),
        selection: TextSelection.collapsed(offset: p + 1),
      ),
      lang,
    );
  }

  TextEditingValue backspace(TextEditingValue old, [String lang = 'json']) {
    final p = old.selection.start;
    return smartEdit(
      old,
      TextEditingValue(
        text: old.text.replaceRange(p - 1, p, ''),
        selection: TextSelection.collapsed(offset: p - 1),
      ),
      lang,
    );
  }

  group('editing', () {
    test('autoCloseBrace', () {
      final r = type(tv(''), '{');
      expect(r.text, '{}');
      expect(r.selection.start, 1);
    });
    test('autoCloseQuoteAndTypeOver', () {
      var r = type(tv('{"a": ', 6), '"');
      expect(r.text.substring(0, 8), '{"a": ""');
      r = type(r, 'x');
      r = type(r, '"');
      expect(r.text.substring(0, 9), '{"a": "x"');
      expect(r.selection.start, 9);
    });
    test(
      'noAutoCloseBeforeWord',
      () => expect(type(tv('a', 0), '{').text, '{a'),
    );
    test('enterIndentsInsideBraces', () {
      final r = smartEdit(tv('{}', 1), tv('{\n}', 2), 'json');
      expect(r.text, '{\n  \n}');
      expect(r.selection.start, 4);
    });
    test(
      'enterKeepsIndent',
      () => expect(
        smartEdit(tv('  a', 3), tv('  a\n', 4), 'json').text,
        '  a\n  ',
      ),
    );
    test('pairedBackspace', () => expect(backspace(tv('{}', 1)).text, ''));
    test(
      'plainTextUntouched',
      () => expect(type(tv(''), '{', 'text').text, '{'),
    );
    test('lineColumn', () {
      expect(lineCol('ab\ncd', 0), (1, 1));
      expect(lineCol('ab\ncd', 4), (2, 2));
    });
  });

  group('highlight', () {
    const p = DarkPal;
    List<(String, Color?)> colors(String code, String lang) {
      final out = <(String, Color?)>[];
      for (final s in highlight(code, lang, p).children ?? const []) {
        final t = s as TextSpan;
        out.add((t.text ?? '', t.style?.color));
      }
      return out;
    }

    test('python', () {
      final c = colors(
        'import requests\nurl = "https://x.io" # note\nn = 5',
        'py',
      );
      expect(c.contains(('import', p.syntaxKeyword)), isTrue);
      expect(c.contains(('"https://x.io"', p.syntaxString)), isTrue);
      expect(c.contains(('# note', p.syntaxComment)), isTrue);
      expect(c.contains(('5', p.syntaxNumber)), isTrue);
    });
    test('shell', () {
      final c = colors(
        "curl -X POST 'https://x.io/a#b' \\\n  -H 'A: b' # c",
        'sh',
      );
      expect(c.contains(('curl', p.syntaxKeyword)), isTrue);
      expect(c.contains(('-X', p.syntaxKey)), isTrue);
      expect(c.contains(("'https://x.io/a#b'", p.syntaxString)), isTrue);
      expect(c.contains(('# c', p.syntaxComment)), isTrue);
    });
    test('blockCommentAndTypes', () {
      final c = colors('/* hi */ val x: String = "a"', 'kt');
      expect(c.contains(('/* hi */', p.syntaxComment)), isTrue);
      expect(c.contains(('val', p.syntaxKeyword)), isTrue);
      expect(c.contains(('String', p.syntaxKey)), isTrue);
    });
  });
}
