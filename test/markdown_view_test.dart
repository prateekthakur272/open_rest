import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/components/markdown_view.dart';

void main() {
  test('blocks: headings, paragraphs, rules and code fences', () {
    final b = parseMarkdownBlocks(
      '# Title\n\nline one\nline two\n\n---\n\n```json\n{"a": 1}\n```\n### Sub',
    );
    expect(b.length, 5);
    expect((b[0] as MdHeading).level, 1);
    expect((b[0] as MdHeading).text, 'Title');
    expect((b[1] as MdParagraph).text, 'line one line two');
    expect(b[2], isA<MdRule>());
    expect((b[3] as MdCode).lang, 'json');
    expect((b[3] as MdCode).code, '{"a": 1}');
    expect((b[4] as MdHeading).level, 3);
  });

  test('blocks: lists, quotes and tables', () {
    final b = parseMarkdownBlocks(
      '- a\n- b\n  more\n\n1. x\n2. y\n\n> quoted\n> text\n\n'
      '| k | v |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |',
    );
    final l1 = b[0] as MdList;
    expect(l1.ordered, isFalse);
    expect(l1.items, ['a', 'b more']);
    expect((b[1] as MdList).ordered, isTrue);
    expect((b[2] as MdQuote).text, 'quoted text');
    final t = b[3] as MdTable;
    expect(t.header, ['k', 'v']);
    expect(t.rows, [
      ['1', '2'],
      ['3', '4'],
    ]);
  });

  test('an unclosed fence runs to the end and empty input is empty', () {
    expect((parseMarkdownBlocks('```\nx\ny')[0] as MdCode).code, 'x\ny');
    expect(parseMarkdownBlocks(''), isEmpty);
  });

  test('inline: bold, italic, code and links', () {
    expect(parseMarkdownInline('a **b** *c* `d` e'), const [
      MdSpan('a '),
      MdSpan('b', bold: true),
      MdSpan(' '),
      MdSpan('c', italic: true),
      MdSpan(' '),
      MdSpan('d', code: true),
      MdSpan(' e'),
    ]);
    expect(
      parseMarkdownInline('[site](https://x.io) and https://y.io.'),
      const [
        MdSpan('site', link: 'https://x.io'),
        MdSpan(' and '),
        MdSpan('https://y.io', link: 'https://y.io'),
        MdSpan('.'),
      ],
    );
  });

  test('inline: markers inside words and unmatched markers stay literal', () {
    expect(parseMarkdownInline('snake_case_name'), const [
      MdSpan('snake_case_name'),
    ]);
    expect(parseMarkdownInline('2 * 3'), const [MdSpan('2 * 3')]);
    expect(parseMarkdownInline(r'\*not\*'), const [MdSpan('*not*')]);
  });
}
