// ignore_for_file: constant_identifier_names, non_constant_identifier_names, deprecated_member_use
import 'package:open_rest/utils/app_config.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

enum _Step {
  Welcome('Welcome'),
  Look('Make it yours'),
  Tips('Quick tour'),
  Start('Get started');

  const _Step(this.title);
  final String title;
}

/// First-run walkthrough: welcome, look and feel, a few tips, then how to start. Skipping or closing it counts as finished.
class OnboardingDialog extends StatefulWidget {
  const OnboardingDialog({super.key, required this.state});
  final AppState state;

  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final steps = _Step.values;
    final step = steps[index];
    final last = index == steps.length - 1;
    return ModalBox(
      title: 'Welcome to ${AppConfig.NAME}',
      onClose: () => state.finishOnboarding(),
      width: 640,
      height: 520,
      actions: [
        if (!last) Btn(label: 'Skip', onClick: () => state.finishOnboarding()),
        Expanded(
          child: Center(
            child: _Dots(current: index, count: steps.length),
          ),
        ),
        if (index > 0)
          Btn(label: 'Back', onClick: () => setState(() => index--)),
        if (!last)
          Btn(
            label: 'Next',
            onClick: () => setState(() => index++),
            primary: true,
          )
        else
          Btn(
            label: 'Start with an empty workspace',
            onClick: () => state.finishOnboarding(),
          ),
      ],
      content: [
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: switch (step) {
                _Step.Welcome => const _Welcome(),
                _Step.Look => _Look(state: state),
                _Step.Tips => const _Tips(),
                _Step.Start => _Start(state: state),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.current, required this.count});
  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == current ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == current ? p.accent : p.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.sub);
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      T(title, size: 20, weight: FontWeight.w700),
      T(sub, color: context.pal.muted),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final rows = <(IconData, String)>[
      (
        Ic.folder,
        'Requests are plain YAML files in folders you choose. Keep them in git.',
      ),
      (
        Ic.import,
        'Bring your work from Postman, Insomnia, Bruno, OpenAPI or cURL.',
      ),
      (
        Ic.workflow,
        'Chain requests into workflows with loops, conditions and passed-on values.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 10,
      children: [
        Ico(Ic.logo, tint: p.accent, size: 64),
        T(AppConfig.NAME, size: 28, weight: FontWeight.w700),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DefaultTextStyle.merge(
            textWidthBasis: TextWidthBasis.longestLine,
            child: T(AppConfig.TAGLINE, color: p.muted, size: 14),
          ),
        ),
        const SizedBox(height: 10),
        for (final r in rows)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Row(
              spacing: 12,
              children: [
                Ico(r.$1, tint: p.accent, size: 20),
                Expanded(child: T(r.$2)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Look extends StatelessWidget {
  const _Look({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        const _Heading(
          'Make it yours',
          'You can change all of this later in Preferences.',
        ),
        const SectionLabel('THEME'),
        Row(
          spacing: 8,
          children: [
            for (final m in ThemeMode.values)
              Pill(
                label: m.label,
                selected: s.theme == m,
                onClick: () => state.updateSettings(s.copyWith(theme: m)),
              ),
          ],
        ),
        const SectionLabel('LAYOUT'),
        Row(
          spacing: 8,
          children: [
            Pill(
              label: 'Request above response',
              selected: s.verticalLayout,
              onClick: () =>
                  state.updateSettings(s.copyWith(verticalLayout: true)),
            ),
            Pill(
              label: 'Side by side',
              selected: !s.verticalLayout,
              onClick: () =>
                  state.updateSettings(s.copyWith(verticalLayout: false)),
            ),
          ],
        ),
        const SectionLabel('TEXT SIZE'),
        Row(
          spacing: 8,
          children: [
            Btn(label: '−', onClick: () => state.zoom(-1)),
            T('${s.fontSize * 100 ~/ 13}%', mono: true),
            Btn(label: '+', onClick: () => state.zoom(1)),
          ],
        ),
      ],
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cmd = Platform.isMac ? '⌘' : 'Ctrl+';
    final tips = <(String, String)>[
      ('${cmd}K', 'Command palette: search every request and run any command.'),
      (
        '$cmd${Platform.isMac ? '↵' : 'Enter'}',
        'Send the request you are editing.',
      ),
      (
        '{{name}}',
        'Use an environment or collection variable in a URL, header or body.',
      ),
      ('${cmd}S', 'Save the current request or workflow.'),
      ('Help ▸ Shortcuts', 'See every keyboard shortcut.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        const _Heading(
          'A quick tour',
          'The few things worth knowing on day one.',
        ),
        for (final t in tips)
          Row(
            spacing: 14,
            children: [
              SizedBox(
                width: 130,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    // Borders are painted over the content so they take no layout space.
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: p.border, width: 1),
                    ),
                    child: T(t.$1, mono: true, size: 12),
                  ),
                ),
              ),
              Expanded(child: T(t.$2)),
            ],
          ),
      ],
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 14,
    children: [
      const _Heading(
        'Get started',
        'Pick how you want to begin. You can do the others any time from the sidebar.',
      ),
      _StartCard(
        icon: Ic.add,
        title: 'Create a collection',
        sub: 'A new folder for your requests.',
        onClick: () => state.finishOnboarding(const ModalNewCollection()),
      ),
      _StartCard(
        icon: Ic.folderOpen,
        title: 'Open a folder',
        sub: 'Use a collection you already have on disk.',
        onClick: () => state.finishOnboarding(const ModalOpenCollection()),
      ),
      _StartCard(
        icon: Ic.import,
        title: 'Import',
        sub: 'Postman, Insomnia, Bruno, OpenAPI or a cURL command.',
        onClick: () => state.finishOnboarding(const ModalImport()),
      ),
    ],
  );
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onClick,
  });
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Clickable(
      onClick: onClick,
      cursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border, width: 1),
        ),
        child: Row(
          spacing: 14,
          children: [
            Ico(icon, tint: p.accent, size: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(title, weight: FontWeight.w600),
                  T(sub, color: p.muted, size: 12),
                ],
              ),
            ),
            T('›', color: p.muted, size: 18),
          ],
        ),
      ),
    );
  }
}
