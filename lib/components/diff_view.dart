import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:open_rest/components/text.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/diff.dart';

/// Unified line diff with context collapsing.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.old, required this.new_});

  final String old;

  final String new_;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final style = TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: 13,
      height: 19 / 13,
      leadingDistribution: TextLeadingDistribution.even,
      letterSpacing: bodyLetterSpacing,
      color: p.text,
      decoration: TextDecoration.none,
    );
    final diff = Diff.lines(old.split('\n'), new_.split('\n'));
    final box = BoxDecoration(
      color: p.field,
      borderRadius: BorderRadius.circular(5),
    );
    // Border is painted over the content so it doesn't change the layout.
    final fg = BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: p.border, width: 1),
    );
    if (diff == null) {
      return Container(
        decoration: box,
        foregroundDecoration: fg,
        padding: const EdgeInsets.all(12),
        alignment: Alignment.topLeft,
        child: T('Responses are too large to diff.', color: p.muted),
      );
    }
    final added = diff.where((l) => l.op == '+').length;
    final removed = diff.where((l) => l.op == '-').length;
    if (added + removed == 0) {
      return Container(
        decoration: box,
        foregroundDecoration: fg,
        padding: const EdgeInsets.all(12),
        alignment: Alignment.topLeft,
        child: T('✓ Responses are identical', color: p.ok),
      );
    }
    final keep = List<bool>.filled(diff.length, false);
    for (var i = 0; i < diff.length; i++) {
      if (diff[i].op != ' ') {
        for (
          var k = math.max(0, i - 3);
          k <= math.min(diff.length - 1, i + 3);
          k++
        ) {
          keep[k] = true;
        }
      }
    }
    final rows = <DiffLine?>[];
    var gap = false;
    for (var i = 0; i < diff.length; i++) {
      if (keep[i]) {
        rows.add(diff[i]);
        gap = false;
      } else if (!gap) {
        rows.add(null);
        gap = true;
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: box,
      foregroundDecoration: fg,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: rows.length + 1,
        itemBuilder: (context, idx) {
          if (idx == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: T('+$added  −$removed', color: p.muted, size: 11),
            );
          }
          final l = rows[idx - 1];
          if (l == null) {
            return Padding(
              padding: const EdgeInsets.only(left: 10),
              child: T('⋯', color: p.muted, mono: true),
            );
          }
          final bg = l.op == '+'
              ? p.ok.withValues(alpha: 0.16)
              : (l.op == '-'
                    ? p.err.withValues(alpha: 0.16)
                    : const Color(0x00000000));
          final opColor = l.op == '+' ? p.ok : (l.op == '-' ? p.err : p.muted);
          return Container(
            color: bg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(l.op, style: style.copyWith(color: opColor)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(l.text, style: style),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
