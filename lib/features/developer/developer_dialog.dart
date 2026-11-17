import 'package:flutter/widgets.dart';
import 'package:open_rest/utils/app_config.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Who made OpenRest, and where to find the developer and the project on GitHub.
class DeveloperDialog extends StatelessWidget {
  const DeveloperDialog({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ModalBox(
      title: 'Developer',
      onClose: () => state.modal = null,
      width: 560,
      actions: [
        Btn(label: 'Close', onClick: () => state.modal = null, primary: true),
      ],
      content: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            spacing: 14,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.field,
                ),
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.border, width: 1),
                ),
                child: Ico(Ic.gitHub, tint: p.text, size: 32),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(AppConfig.VENDOR, size: 18, weight: FontWeight.w700),
                  T('Developer of ${AppConfig.NAME}', color: p.muted),
                ],
              ),
            ],
          ),
        ),
        if (AppConfig.DEVELOPER_URL.trim().isNotEmpty)
          _LinkRow(label: 'Profile', url: AppConfig.DEVELOPER_URL),
        if (AppConfig.HOMEPAGE.trim().isNotEmpty)
          _LinkRow(label: 'Project repository', url: AppConfig.HOMEPAGE),
        if (AppConfig.MORE_APPS_URL.trim().isNotEmpty)
          _LinkRow(label: 'Explore more apps', url: AppConfig.MORE_APPS_URL),
        T(
          '${AppConfig.NAME} is built in the open. Bug reports, ideas and pull requests are welcome on GitHub.',
          color: p.muted,
          size: 12,
        ),
      ],
    );
  }
}

class _LinkRow extends StatefulWidget {
  const _LinkRow({required this.label, required this.url});
  final String label;
  final String url;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool copied = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          SectionLabel(widget.label.toUpperCase()),
          Container(
            padding: const EdgeInsets.only(
              left: 10,
              top: 4,
              bottom: 4,
              right: 4,
            ),
            decoration: BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(6),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: p.border, width: 1),
            ),
            child: Row(
              spacing: 6,
              children: [
                Expanded(child: T(widget.url, mono: true, size: 12)),
                Btn(
                  label: copied ? 'Copied' : 'Copy',
                  onClick: () {
                    Platform.copy(widget.url);
                    setState(() => copied = true);
                  },
                ),
                Btn(
                  label: 'Open',
                  onClick: () => Platform.openUrl(widget.url),
                  primary: true,
                  icon: Ic.open,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
