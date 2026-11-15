import 'package:flutter/widgets.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

class TestsList extends StatelessWidget {
  const TestsList({super.key, required this.tests});

  final List<TestResult> tests;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          for (final t in tests)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Ico(
                  t.passed ? Ic.checkCircle : Ic.cancel,
                  tint: t.passed ? p.ok : p.err,
                  size: 16,
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      T(t.name, mono: true),
                      if (!t.passed && t.message.trim().isNotEmpty)
                        T(t.message, color: p.err, mono: true, size: 12),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
