import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/method_pill.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/format.dart';

/// The "History" tab of the sidebar: lays out in the remaining height of the sidebar column.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 6, bottom: 6),
            child: Row(
              children: [
                const Expanded(child: SectionLabel('RECENT REQUESTS')),
                if (state.history.isNotEmpty)
                  IconBtn(
                    icon: Ic.delete,
                    onClick: () => state.history.clear(),
                    size: 16,
                  ),
              ],
            ),
          ),
          Container(height: 1, color: p.border),
          if (state.history.isEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Ico(
                      Ic.history,
                      tint: p.muted.withValues(alpha: 0.5),
                      size: 44,
                    ),
                    const SizedBox(height: 10),
                    const T('Nothing sent yet', weight: FontWeight.w600),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: DefaultTextStyle.merge(
                        textWidthBasis: TextWidthBasis.longestLine,
                        child: T(
                          'Requests you send show up here with their full response.',
                          color: p.muted,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  for (final e in state.history.toList())
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HoverBuilder(
                          indicate: true,
                          cursor: SystemMouseCursors.click,
                          onTap: () => state.openHistory(e),
                          builder: (ctx, hov) => Container(
                            color: hov ? p.hover : const Color(0x00000000),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 3,
                              children: [
                                Row(
                                  spacing: 8,
                                  children: [
                                    MethodPill(e.method),
                                    Expanded(
                                      child: T(
                                        e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (e.status == 0
                                                    ? p.err
                                                    : statusColor(e.status, p))
                                                .withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: T(
                                        e.status == 0
                                            ? 'ERR'
                                            : e.status.toString(),
                                        color: e.status == 0
                                            ? p.err
                                            : statusColor(e.status, p),
                                        size: 10,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  spacing: 8,
                                  children: [
                                    Expanded(
                                      child: T(
                                        e.url,
                                        color: p.muted,
                                        size: 11,
                                        mono: true,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    T(
                                      '${e.timeMs}ms · ${timeAgo(e.time)}',
                                      color: p.muted,
                                      size: 10,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          height: 1,
                          color: p.border.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
