import 'package:flutter/services.dart';

bool _isLetterOrDigit(String? c) =>
    c != null &&
    c.isNotEmpty &&
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);
bool _isWhitespace(String c) => c.trim().isEmpty;

/// Editor niceties applied when exactly one character was typed or deleted:
/// auto-closing brackets/quotes, typing over a closer, smart indentation on Enter, paired backspace.
TextEditingValue smartEdit(
  TextEditingValue old,
  TextEditingValue neu,
  String lang,
) {
  if (lang == 'text') return neu;
  final o = old.text;
  final n = neu.text;
  if (!old.selection.isCollapsed ||
      !neu.selection.isCollapsed ||
      !old.selection.isValid ||
      !neu.selection.isValid) {
    return neu;
  }
  final oldPos = old.selection.start;
  final code = lang == 'json' || lang == 'js';
  const closers = {'{': '}', '[': ']', '(': ')', '"': '"'};

  TextEditingValue v(String t, int caret) => TextEditingValue(
    text: t,
    selection: TextSelection.collapsed(offset: caret),
  );

  // Typed one character.
  if (n.length == o.length + 1 &&
      neu.selection.start == oldPos + 1 &&
      n.substring(0, oldPos) == o.substring(0, oldPos)) {
    final ch = n[oldPos];
    final String? next = oldPos < o.length ? o[oldPos] : null;
    if (code && '}])"'.contains(ch) && next == ch) {
      return v(o, oldPos + 1);
    }
    if (ch == '\n') {
      final lineStart = oldPos == 0 ? 0 : o.lastIndexOf('\n', oldPos - 1) + 1;
      final before = o.substring(lineStart, oldPos);
      var k = 0;
      while (k < before.length && (before[k] == ' ' || before[k] == '\t')) {
        k++;
      }
      final indent = before.substring(0, k);
      final tr = before.trimRight();
      final last = tr.isEmpty ? null : tr[tr.length - 1];
      final opens = last != null && (last == '{' || last == '[' || last == '(');
      final inner = '\n$indent${opens ? "  " : ""}';
      if (opens && next != null && '}])'.contains(next)) {
        return v(
          '${o.substring(0, oldPos)}$inner\n$indent${o.substring(oldPos)}',
          oldPos + inner.length,
        );
      }
      return v(
        '${o.substring(0, oldPos)}$inner${o.substring(oldPos)}',
        oldPos + inner.length,
      );
    }
    if (code) {
      final closer = closers[ch];
      if (closer != null) {
        if (ch == '"') {
          final String? prev = oldPos >= 1 ? o[oldPos - 1] : null;
          if (_isLetterOrDigit(prev) ||
              prev == '\\' ||
              _isLetterOrDigit(next)) {
            return neu;
          }
        }
        if (next == null || _isWhitespace(next) || '}]),:'.contains(next)) {
          return v(
            '${n.substring(0, oldPos + 1)}$closer${n.substring(oldPos + 1)}',
            oldPos + 1,
          );
        }
      }
    }
  }
  // Deleted one character: remove the matching closer of an empty pair.
  if (code &&
      n.length == o.length - 1 &&
      neu.selection.start == oldPos - 1 &&
      oldPos >= 1 &&
      oldPos < o.length) {
    final deleted = o[oldPos - 1];
    if (closers[deleted] == o[oldPos]) {
      return v(
        '${n.substring(0, oldPos - 1)}${n.substring(oldPos)}',
        oldPos - 1,
      );
    }
  }
  return neu;
}

/// 1-based line and column of [pos] in [text].
(int, int) lineCol(String text, int pos) {
  final p = pos.clamp(0, text.length);
  var line = 1;
  var last = -1;
  for (var i = 0; i < p; i++) {
    if (text.codeUnitAt(i) == 10) {
      line++;
      last = i;
    }
  }
  return (line, p - last);
}
