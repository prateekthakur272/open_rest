import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

String _decodeEntities(String s) {
  const named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'copy': '©',
    'reg': '®',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'laquo': '«',
    'raquo': '»',
    'bull': '•',
  };
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[A-Za-z]+);'), (m) {
    final e = m.group(1)!;
    if (e.startsWith('#x')) {
      return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 63);
    }
    if (e.startsWith('#')) {
      return String.fromCharCode(int.tryParse(e.substring(1)) ?? 63);
    }
    return named[e] ?? m.group(0)!;
  });
}

/// A deliberately simple HTML renderer (headings, paragraphs, lists, links, emphasis, code, rules; no scripts or layout CSS).
List<Widget> renderHtml(String html) {
  var h = html;
  h = h.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  h = h.replaceAll(
    RegExp(r'<(script|style|head)[\s\S]*?</\1\s*>', caseSensitive: false),
    '',
  );
  final blocks = <Widget>[];
  var spans = <InlineSpan>[];
  var bold = 0, italic = 0, code = 0, link = 0, pre = 0, list = 0;
  double size = 14;
  double marginTop = 0;
  final listStack = <int?>[];
  FontWeight? headWeight;
  const black = Color(0xFF111111);

  void flush() {
    final nonEmpty = spans.any(
      (s) => s is TextSpan && (s.text ?? '').trim().isNotEmpty,
    );
    if (nonEmpty) {
      blocks.add(
        Padding(
          padding: EdgeInsets.only(
            top: marginTop,
            bottom: 6,
            left: list * 20.0,
          ),
          child: Text.rich(
            TextSpan(children: spans),
            style: const TextStyle(
              color: black,
              fontSize: 14,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      );
    }
    spans = [];
    marginTop = 0;
  }

  TextStyle style() => TextStyle(
    color: link > 0 ? const Color(0xFF1A5FB4) : black,
    fontSize: size,
    height: 1.4,
    fontWeight: (bold > 0 || headWeight != null) ? FontWeight.w700 : null,
    fontStyle: italic > 0 ? FontStyle.italic : null,
    fontFamily: (code > 0 || pre > 0) ? monoFamily : null,
    fontFamilyFallback: (code > 0 || pre > 0) ? monoFallback : null,
    backgroundColor: code > 0 && pre == 0 ? const Color(0x14000000) : null,
    decoration: link > 0 ? TextDecoration.underline : TextDecoration.none,
  );

  final tok = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)|<');
  for (final m in tok.allMatches(h)) {
    final text = m.group(4);
    if (text != null) {
      var t = _decodeEntities(text);
      if (pre == 0) t = t.replaceAll(RegExp(r'\s+'), ' ');
      if (spans.isEmpty && pre == 0) t = t.trimLeft();
      if (t.isNotEmpty) spans.add(TextSpan(text: t, style: style()));
      continue;
    }
    if (m.group(2) == null) continue;
    final close = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();
    switch (tag) {
      case 'b':
      case 'strong':
        bold += close ? -1 : 1;
        break;
      case 'i':
      case 'em':
        italic += close ? -1 : 1;
        break;
      case 'code':
      case 'kbd':
      case 'tt':
        code += close ? -1 : 1;
        break;
      case 'a':
        link += close ? -1 : 1;
        break;
      case 'br':
        spans.add(const TextSpan(text: '\n'));
        break;
      case 'hr':
        flush();
        blocks.add(
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 8),
            color: const Color(0x33000000),
          ),
        );
        break;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        flush();
        if (close) {
          size = 14;
          headWeight = null;
        } else {
          const sizes = {
            'h1': 28.0,
            'h2': 22.0,
            'h3': 18.0,
            'h4': 16.0,
            'h5': 14.0,
            'h6': 12.0,
          };
          size = sizes[tag]!;
          headWeight = FontWeight.w700;
          marginTop = 8;
        }
        break;
      case 'pre':
        flush();
        pre += close ? -1 : 1;
        break;
      case 'ul':
      case 'ol':
        flush();
        if (close) {
          if (listStack.isNotEmpty) listStack.removeLast();
          list = math.max(0, list - 1);
        } else {
          listStack.add(tag == 'ol' ? 0 : null);
          list++;
        }
        break;
      case 'li':
        flush();
        if (!close) {
          final n = listStack.isNotEmpty ? listStack.last : null;
          if (n != null) {
            listStack[listStack.length - 1] = n + 1;
            spans.add(TextSpan(text: '${n + 1}. ', style: style()));
          } else {
            spans.add(TextSpan(text: '• ', style: style()));
          }
        }
        break;
      case 'p':
      case 'div':
      case 'table':
      case 'tr':
      case 'section':
      case 'article':
      case 'header':
      case 'footer':
      case 'blockquote':
      case 'form':
      case 'body':
      case 'html':
        flush();
        break;
      case 'td':
      case 'th':
        if (!close && spans.isNotEmpty) spans.add(const TextSpan(text: '    '));
        break;
    }
  }
  flush();
  return blocks;
}

/// Simplified HTML renderer used for the preview (no full HTML/CSS engine).
class HtmlPreview extends StatelessWidget {
  const HtmlPreview({super.key, required this.html, required this.bytes});

  final String html;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final blocks = renderHtml(
      html.length > 2000000 ? html.substring(0, 2000000) : html,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(5),
      ),
      // Border is painted over the content so it doesn't change the layout.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: blocks,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Btn(
                label: 'Open in browser',
                onClick: () =>
                    Platform.openBytes(bytes, '.html', browser: true),
                icon: Ic.open,
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF000000).withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const T(
                'Simplified render (HTML 3.2 / basic CSS, no scripts)',
                color: Color(0xFFFFFFFF),
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
