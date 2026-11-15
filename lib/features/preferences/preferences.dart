// ignore_for_file: constant_identifier_names, non_constant_identifier_names, deprecated_member_use
import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/theme.dart';

enum _Section {
  General('General', 'How OpenRest behaves day to day.'),
  Appearance('Appearance', 'Theme, size and layout.'),
  Requests('Requests', 'Defaults applied to every request you send.'),
  Network('Network', 'Certificates and cookies.'),
  Proxy('Proxy', 'Send requests through an HTTP proxy.'),
  Shortcuts(
    'Shortcuts',
    'Keyboard shortcuts. Use Ctrl instead of ⌘ on Windows and Linux.',
  ),
  Data('Data', 'Where OpenRest keeps your files.');

  const _Section(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// One setting: what it is, a line of explanation, and the control that changes it.
class _Pref {
  const _Pref(
    this.section,
    this.title,
    this.control, {
    this.desc = '',
    this.descColor,
  });
  final _Section section;
  final String title;
  final String desc;
  final Color? descColor;
  final Widget control;
}

class _BorderThenFill extends CustomPainter {
  _BorderThenFill({
    required this.border,
    required this.fill,
    required this.radius,
  });
  final Color border;
  final Color fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(
      r.deflate(0.5),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(r, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_BorderThenFill o) =>
      o.border != border || o.fill != fill || o.radius != radius;
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChange});
  final bool on;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Clickable(
      onClick: () => onChange(!on),
      cursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? p.accent : p.border,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onSelect,
  });
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      // Borders are painted over the content so they take no layout space.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final o in options)
            Clickable(
              onClick: () => onSelect(o),
              cursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: o == selected ? p.accent : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: T(
                  o,
                  color: o == selected ? const Color(0xFF000000) : p.text,
                  size: 12,
                  weight: o == selected ? FontWeight.w600 : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.value,
    required this.onChange,
    this.suffix = '',
    this.width = 100,
  });
  final int value;
  final String suffix;
  final double width;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      SizedBox(
        width: width,
        child: Field(
          value: value.toString(),
          onChange: (v) {
            final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
            onChange(
              int.tryParse(
                    digits.length > 7 ? digits.substring(0, 7) : digits,
                  ) ??
                  0,
            );
          },
          highlightVars: false,
        ),
      ),
      if (suffix.isNotEmpty) T(suffix, color: context.pal.muted, size: 12),
    ],
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onClick,
  });
  final String label;
  final bool selected;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HoverBuilder(
      indicate: true,
      borderRadius: BorderRadius.circular(7),
      cursor: SystemMouseCursors.click,
      onTap: onClick,
      builder: (ctx, hov) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? p.accent.withValues(alpha: 0.16)
              : (hov ? p.hover : const Color(0x00000000)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: T(
          label,
          color: selected ? p.accent : p.text,
          weight: selected ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

/// App-level preferences: sections on the left, settings with a line of explanation each on the right, and a search across all of them.
class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({super.key, required this.state});
  final AppState state;

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late _Section section;
  String query = '';
  bool confirmReset = false;

  @override
  void initState() {
    super.initState();
    section = _Section.values.firstWhere(
      (s) => s.label == widget.state.prefsSection,
      orElse: () => _Section.General,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.state.prefsSection = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final state = widget.state;
    final s = state.settings;
    void set(AppSettings n) => state.updateSettings(n);

    final prefs = <_Pref>[
      _Pref(
        _Section.General,
        'Save automatically',
        _Toggle(
          on: s.autoSave,
          onChange: (v) => set(s.copyWith(autoSave: v)),
        ),
        desc: 'Saves a request, or a workflow, just before it is sent or run.',
      ),
      _Pref(
        _Section.Appearance,
        'Theme',
        _Segmented(
          options: [for (final m in ThemeMode.values) m.label],
          selected: s.theme.label,
          onSelect: (l) => set(
            s.copyWith(theme: ThemeMode.values.firstWhere((m) => m.label == l)),
          ),
        ),
        desc: s.theme == ThemeMode.System
            ? "Follows your operating system's light / dark setting (currently ${p.dark ? 'dark' : 'light'})."
            : 'Light or dark interface, or follow the operating system.',
      ),
      _Pref(
        _Section.Appearance,
        'Interface size',
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Btn(
              label: '−',
              onClick: () =>
                  set(s.copyWith(fontSize: (s.fontSize - 1).clamp(10, 20))),
              enabled: s.fontSize > 10,
            ),
            SizedBox(
              width: 48,
              child: T(
                '${s.fontSize * 100 ~/ 13}%',
                mono: true,
                weight: FontWeight.w600,
              ),
            ),
            Btn(
              label: '+',
              onClick: () =>
                  set(s.copyWith(fontSize: (s.fontSize + 1).clamp(10, 20))),
              enabled: s.fontSize < 20,
            ),
            if (s.fontSize != 13)
              Clickable(
                onClick: () => set(s.copyWith(fontSize: 13)),
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: T('Reset', color: p.accent, size: 12),
                ),
              ),
          ],
        ),
        desc: 'Scales text and controls (also ⌘+ and ⌘−).',
      ),
      _Pref(
        _Section.Appearance,
        'Request layout',
        _Segmented(
          options: const ['Stacked', 'Side by side'],
          selected: s.verticalLayout ? 'Stacked' : 'Side by side',
          onSelect: (v) => set(s.copyWith(verticalLayout: v == 'Stacked')),
        ),
        desc: 'Show the response below the request, or beside it.',
      ),
      _Pref(
        _Section.Requests,
        'Timeout',
        _NumberField(
          value: s.timeoutMs,
          suffix: 'ms',
          onChange: (v) => set(s.copyWith(timeoutMs: v)),
        ),
        desc: 'How long to wait for a response. 0 means no limit.',
      ),
      _Pref(
        _Section.Requests,
        'Follow redirects',
        _Toggle(
          on: s.followRedirects,
          onChange: (v) => set(s.copyWith(followRedirects: v)),
        ),
        desc: 'Automatically follow 3xx responses to the new location.',
      ),
      if (s.followRedirects)
        _Pref(
          _Section.Requests,
          'Maximum redirects',
          _NumberField(
            value: s.maxRedirects,
            suffix: 'hops',
            width: 80,
            onChange: (v) => set(s.copyWith(maxRedirects: v > 50 ? 50 : v)),
          ),
          desc: 'Stop after this many hops, to avoid redirect loops.',
        ),
      _Pref(
        _Section.Requests,
        'User-Agent',
        SizedBox(
          width: 260,
          child: Field(
            value: s.userAgent,
            onChange: (v) => set(s.copyWith(userAgent: v)),
            highlightVars: false,
          ),
        ),
        desc: 'Sent with every request unless the request sets its own.',
      ),
      _Pref(
        _Section.Network,
        'Verify SSL certificates',
        _Toggle(
          on: s.sslVerify,
          onChange: (v) => set(s.copyWith(sslVerify: v)),
        ),
        desc: s.sslVerify
            ? 'Reject servers whose certificate cannot be verified.'
            : 'Off: connections are not verified. Use only for servers you trust, such as local development.',
        descColor: s.sslVerify ? null : p.err,
      ),
      _Pref(
        _Section.Network,
        'Cookies',
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Btn(
              label: 'Manage…',
              onClick: () => state.modal = const ModalCookies(),
            ),
            Btn(
              label: 'Clear all',
              onClick: () {
                HttpExecutor.cookies.removeAll();
                state.showToast('Cookies cleared');
              },
            ),
          ],
        ),
        desc: 'Cookies are kept for this session and sent back to the sites that set them.',
      ),
      _Pref(
        _Section.Proxy,
        'Use an HTTP proxy',
        _Toggle(
          on: s.proxyEnabled,
          onChange: (v) => set(s.copyWith(proxyEnabled: v)),
        ),
        desc: 'Route every request through the proxy below.',
      ),
      if (s.proxyEnabled) ...[
        _Pref(
          _Section.Proxy,
          'Proxy host',
          SizedBox(
            width: 260,
            child: Field(
              value: s.proxyHost,
              onChange: (v) => set(s.copyWith(proxyHost: v)),
              placeholder: 'proxy.example.com',
              highlightVars: false,
            ),
          ),
          desc: 'Host name or address of the proxy.',
        ),
        _Pref(
          _Section.Proxy,
          'Proxy port',
          _NumberField(
            value: s.proxyPort,
            width: 90,
            onChange: (v) => set(s.copyWith(proxyPort: v > 65535 ? 65535 : v)),
          ),
        ),
      ],
      for (final (what, keys) in const <(String, String)>[
        ('Command palette', '⌘K'),
        ('Send request', '⌘↵'),
        ('Save', '⌘S'),
        ('Save all', '⌘⇧S'),
        ('Close tab', '⌘W'),
        ('New request', '⌘N'),
        ('Show / hide sidebar', '⌘B'),
        ('Focus the URL bar', '⌘L'),
        ('Switch request layout', '⌘⇧L'),
        ('Copy as cURL', '⌘⇧C'),
        ('Previous / next tab', '⌘⇧[  ⌘⇧]'),
        ('Zoom in / out / reset', '⌘+  ⌘−  ⌘0'),
        ('Preferences', '⌘,'),
      ])
        _Pref(
          _Section.Shortcuts,
          what,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: BorderRadius.circular(5),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: p.border, width: 1),
            ),
            child: T(keys, mono: true, size: 12),
          ),
        ),
      _Pref(
        _Section.Data,
        'Storage location',
        Btn(
          label: Platform.revealLabel,
          onClick: () => Platform.reveal(AppStore.dir),
        ),
        desc: AppStore.dir,
      ),
      _Pref(
        _Section.Data,
        'Reset preferences',
        !confirmReset
            ? Btn(
                label: 'Reset…',
                onClick: () => setState(() => confirmReset = true),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  T('Are you sure?', color: p.err, size: 12),
                  Btn(
                    label: 'Cancel',
                    onClick: () => setState(() => confirmReset = false),
                  ),
                  Btn(
                    label: 'Reset',
                    onClick: () {
                      set(const AppSettings());
                      setState(() => confirmReset = false);
                      state.showToast('Preferences reset to defaults');
                    },
                    danger: true,
                  ),
                ],
              ),
        desc: 'Restore every setting to its default. Your collections and environments are not touched.',
      ),
    ];

    final q = query.trim();
    final searching = q.isNotEmpty;
    final ql = q.toLowerCase();
    final shown = searching
        ? prefs
              .where(
                (x) =>
                    x.title.toLowerCase().contains(ql) ||
                    x.desc.toLowerCase().contains(ql) ||
                    x.section.label.toLowerCase().contains(ql),
              )
              .toList()
        : prefs.where((x) => x.section == section).toList();
    final groups = <_Section, List<_Pref>>{};
    for (final x in shown) {
      groups.putIfAbsent(x.section, () => []).add(x);
    }

    return ModalBox(
      title: 'Preferences',
      onClose: () => state.modal = null,
      width: 900,
      height: 620,
      actions: [
        Expanded(
          child: T(
            'Changes are saved as you make them.',
            color: p.muted,
            size: 12,
          ),
        ),
        Btn(label: 'Done', onClick: () => state.modal = null, primary: true),
      ],
      content: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 18,
            children: [
              SizedBox(
                width: 190,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    Field(
                      value: query,
                      onChange: (v) => setState(() => query = v),
                      placeholder: 'Search settings',
                      highlightVars: false,
                    ),
                    const SizedBox(height: 6),
                    for (final sec in _Section.values)
                      _NavItem(
                        label: sec.label,
                        selected: !searching && sec == section,
                        onClick: () => setState(() {
                          query = '';
                          section = sec;
                        }),
                      ),
                  ],
                ),
              ),
              Container(width: 1, color: p.border),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 14,
                    children: [
                      if (!searching)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            T(section.label, size: 18, weight: FontWeight.w700),
                            T(section.blurb, color: p.muted, size: 12),
                          ],
                        )
                      else
                        T(
                          shown.isEmpty
                              ? 'No settings match “$q”.'
                              : '${shown.length} setting${shown.length == 1 ? '' : 's'} matching “$q”',
                          color: p.muted,
                          size: 13,
                        ),
                      for (final e in groups.entries) ...[
                        if (searching) SectionLabel(e.key.label.toUpperCase()),
                        // The fill paints over the 1px border, which therefore stays visible.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CustomPaint(
                            painter: _BorderThenFill(
                              border: p.border,
                              fill: p.field.withValues(alpha: 0.5),
                              radius: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < e.value.length; i++) ...[
                                  if (i > 0)
                                    Container(height: 1, color: p.border),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      spacing: 16,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            spacing: 2,
                                            children: [
                                              T(
                                                e.value[i].title,
                                                weight: FontWeight.w600,
                                              ),
                                              if (e.value[i].desc
                                                  .trim()
                                                  .isNotEmpty)
                                                T(
                                                  e.value[i].desc,
                                                  color:
                                                      e.value[i].descColor ??
                                                      p.muted,
                                                  size: 12,
                                                  mono:
                                                      e.key == _Section.Data &&
                                                      e.value[i].title ==
                                                          'Storage location',
                                                ),
                                            ],
                                          ),
                                        ),
                                        e.value[i].control,
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
