// ignore_for_file: constant_identifier_names, non_constant_identifier_names, deprecated_member_use
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// What the app module knows about the app, like Android's `applicationId` and `versionName`.
class AppMetadata {
  const AppMetadata({
    this.name = 'OpenRest',
    this.bundleId = '',
    this.version = 'dev',
    this.vendor = '',
    this.description = '',
    this.homepage = '',
    this.developerUrl = '',
  });

  final String name;
  final String bundleId;
  final String version;
  final String vendor;
  final String description;
  final String homepage;
  final String developerUrl;
}

/// Application name, version and credits shown in the About dialog.
class AppInfo {
  AppInfo._();

  /// Set once at startup by the app module. The defaults are what tests and previews see.
  static AppMetadata meta = const AppMetadata();

  static String get NAME => meta.name;
  static String get BUNDLE_ID => meta.bundleId;
  static String get VERSION => meta.version;
  static String get VENDOR => meta.vendor;
  static String get DESCRIPTION => meta.description;
  static String get HOMEPAGE => meta.homepage;
  static String get DEVELOPER_URL => meta.developerUrl;
  static const String TAGLINE =
      'An open, file-based API client — requests, environments and workflows that live in plain folders.';
}

/// A keyboard shortcut. [primary] is ⌘ on a Mac and Ctrl elsewhere; [control] is the literal Control key (used for tab switching).
class Shortcut {
  const Shortcut(
    this.key, {
    this.primary = true,
    this.shift = false,
    this.control = false,
  });

  final LogicalKeyboardKey key;
  final bool primary;
  final bool shift;
  final bool control;

  SingleActivator toActivator(bool isMac) => SingleActivator(
    key,
    control: control || (primary && !isMac),
    meta: primary && isMac,
    shift: shift,
  );

  /// As shown in a menu: ⌘⇧S on a Mac, Ctrl+Shift+S elsewhere.
  String label(bool isMac) {
    String k;
    if (key == LogicalKeyboardKey.enter) {
      k = isMac ? '↵' : 'Enter';
    } else if (key == LogicalKeyboardKey.comma) {
      k = ',';
    } else if (key == LogicalKeyboardKey.equal) {
      k = isMac ? '+' : '=';
    } else if (key == LogicalKeyboardKey.minus) {
      k = '−';
    } else if (key == LogicalKeyboardKey.digit0) {
      k = '0';
    } else if (key == LogicalKeyboardKey.tab) {
      k = isMac ? '⇥' : 'Tab';
    } else {
      final l = key.keyLabel;
      k = (l.length == 1 && RegExp(r'[A-Za-z]').hasMatch(l))
          ? l.toUpperCase()
          : '?';
    }
    if (isMac) {
      return (control ? '⌃' : '') +
          (shift ? '⇧' : '') +
          (primary ? '⌘' : '') +
          k;
    }
    return [if (primary || control) 'Ctrl', if (shift) 'Shift', k].join('+');
  }
}

/// Entry of a title-bar menu.
sealed class MenuEntry {
  const MenuEntry();
}

/// Horizontal divider between menu entries.
class MenuSeparator extends MenuEntry {
  const MenuSeparator();
}

/// [checked] != null makes it a check item.
class MenuItemSpec extends MenuEntry {
  const MenuItemSpec(
    this.label, {
    this.shortcut,
    this.enabled = true,
    this.checked,
    required this.action,
  });

  final String label;
  final Shortcut? shortcut;
  final bool enabled;
  final bool? checked;
  final VoidCallback action;
}

/// Menu entry that opens a nested menu.
class SubMenuSpec extends MenuEntry {
  const SubMenuSpec(this.label, this.items, {this.enabled = true});

  final String label;
  final List<MenuEntry> items;
  final bool enabled;
}

/// Title and entries of one top-level menu.
class MenuSpec {
  const MenuSpec(this.label, this.items);

  final String label;
  final List<MenuEntry> items;
}

/// The application menu bar as plain data, so it can be tested and rendered by the platform's menu bar.
///
/// macOS: About, Preferences and Quit live in the application menu (see `buildMacMenus` in main), so they are left out here.
/// Windows / Linux: Preferences and Exit are in File, About is in Help; shortcuts use Ctrl instead of ⌘.
class AppMenus {
  AppMenus._();

  static List<MenuSpec> build(
    AppState state, {
    required bool isMac,
    VoidCallback? quit,
    VoidCallback? minimize,
  }) {
    final quit_ = quit ?? () {};
    final minimize_ = minimize ?? () {};
    Shortcut key(LogicalKeyboardKey k, {bool shift = false}) =>
        Shortcut(k, shift: shift);
    MenuItemSpec item(
      String label,
      VoidCallback action, {
      Shortcut? shortcut,
      bool enabled = true,
    }) => MenuItemSpec(
      label,
      shortcut: shortcut,
      enabled: enabled,
      action: action,
    );
    MenuItemSpec check(
      String label,
      bool checked,
      VoidCallback action, {
      Shortcut? shortcut,
      bool enabled = true,
    }) => MenuItemSpec(
      label,
      shortcut: shortcut,
      enabled: enabled,
      checked: checked,
      action: action,
    );

    final col = state.currentCollection;
    final tab = state.activeTab;
    final request = (tab != null && tab.isRequest) ? tab : null;
    final wf = tab?.workflow;
    final anyDirty = state.tabs.any((t) => t.dirty);
    final s = state.settings;

    final file = MenuSpec('File', [
      item('New Request', () {
        if (col != null) {
          state.modal = ModalNewRequest(collection: col.path, dir: col.path);
        } else {
          state.modal = const ModalNewCollection();
        }
      }, shortcut: key(LogicalKeyboardKey.keyN)),
      item('New Folder', () {
        if (col != null) state.promptNewFolder(col.path, col.path);
      }, enabled: col != null),
      item('New Workflow', () {
        if (col != null) state.promptNewWorkflow(col.path);
      }, enabled: col != null),
      item('New Collection…', () => state.modal = const ModalNewCollection()),
      const MenuSeparator(),
      item('Open Collection…', () => state.modal = const ModalOpenCollection()),
      item('Import…', () => state.modal = const ModalImport()),
      item('Export Collection…', () {
        if (col != null) state.modal = ModalExport(collection: col.path);
      }, enabled: col != null),
      const MenuSeparator(),
      item(
        'Save',
        () {
          if (tab != null) state.save(tab);
        },
        shortcut: key(LogicalKeyboardKey.keyS),
        enabled: tab != null && tab.dirty,
      ),
      item(
        'Save All',
        () => state.saveAll(),
        shortcut: key(LogicalKeyboardKey.keyS, shift: true),
        enabled: anyDirty,
      ),
      const MenuSeparator(),
      item(
        'Close Tab',
        () {
          if (tab != null) state.closeTab(tab.id);
        },
        shortcut: key(LogicalKeyboardKey.keyW),
        enabled: tab != null,
      ),
      item('Close Other Tabs', () {
        if (tab != null) state.closeOthers(tab.id);
      }, enabled: state.tabs.length > 1),
      item(
        'Close All Saved Tabs',
        () => state.closeAll(),
        enabled: state.tabs.any((t) => !t.dirty),
      ),
      if (!isMac) ...[
        const MenuSeparator(),
        item(
          'Preferences…',
          () => state.modal = const ModalSettings(),
          shortcut: key(LogicalKeyboardKey.comma),
        ),
        const MenuSeparator(),
        item('Exit', quit_, shortcut: key(LogicalKeyboardKey.keyQ)),
      ],
    ]);

    final view = MenuSpec('View', [
      item(
        'Command Palette…',
        () => state.modal = state.modal is ModalPalette
            ? null
            : const ModalPalette(),
        shortcut: key(LogicalKeyboardKey.keyK),
      ),
      const MenuSeparator(),
      check(
        'Show Sidebar',
        state.sidebarVisible,
        () => state.sidebarVisible = !state.sidebarVisible,
        shortcut: key(LogicalKeyboardKey.keyB),
      ),
      check(
        'Stack Request Above Response',
        s.verticalLayout,
        () => state.toggleLayout(),
        shortcut: key(LogicalKeyboardKey.keyL, shift: true),
      ),
      SubMenuSpec('Theme', [
        for (final m in ThemeMode.values)
          check(
            m.label,
            s.theme == m,
            () => state.updateSettings(s.copyWith(theme: m)),
          ),
      ]),
      const MenuSeparator(),
      item(
        'Zoom In',
        () => state.zoom(1),
        shortcut: key(LogicalKeyboardKey.equal),
        enabled: s.fontSize < 20,
      ),
      item(
        'Zoom Out',
        () => state.zoom(-1),
        shortcut: key(LogicalKeyboardKey.minus),
        enabled: s.fontSize > 10,
      ),
      item(
        'Actual Size',
        () => state.zoom(0),
        shortcut: key(LogicalKeyboardKey.digit0),
        enabled: s.fontSize != 13,
      ),
      const MenuSeparator(),
      item('Cookies…', () => state.modal = const ModalCookies()),
      item('Variables…', () {
        if (col != null) state.modal = ModalVars(collection: col.path);
      }, enabled: col != null),
    ]);

    final envs = col?.environments ?? const <Environment>[];
    final activeEnv = col != null ? state.envName(col.path) : null;
    final requestMenu = MenuSpec('Request', [
      item(
        'Send',
        () {
          if (request != null) state.send(request);
        },
        shortcut: key(LogicalKeyboardKey.enter),
        enabled: request != null && !request.sending,
      ),
      item('Cancel Request', () {
        if (request != null) state.cancel(request);
      }, enabled: request?.sending == true),
      const MenuSeparator(),
      item(
        'Focus URL Bar',
        () => state.urlFocus.requestFocus(),
        shortcut: key(LogicalKeyboardKey.keyL),
        enabled: request != null,
      ),
      item(
        'Copy as cURL',
        () {
          if (request != null) state.copyCurl(request);
        },
        shortcut: key(LogicalKeyboardKey.keyC, shift: true),
        enabled: request != null,
      ),
      item('Generate Code…', () {
        if (request != null) state.modal = ModalCodegen(tabId: request.id);
      }, enabled: request != null),
      const MenuSeparator(),
      SubMenuSpec('Environment', [
        check('No Environment', activeEnv == null, () {
          if (col != null) state.setEnv(col.path, null);
        }),
        for (final e in envs)
          check(e.name, activeEnv == e.name, () {
            if (col != null) state.setEnv(col.path, e.name);
          }),
        const MenuSeparator(),
        item('Manage Environments…', () {
          if (col != null) state.modal = ModalEnvs(collection: col.path);
        }, enabled: col != null),
      ], enabled: col != null),
      SubMenuSpec('Global Environment', [
        check(
          'None',
          state.globalEnvName() == null,
          () => state.setGlobalEnv(null),
        ),
        for (final e in state.globalEnvs)
          check(
            e.name,
            state.globalEnvName() == e.name,
            () => state.setGlobalEnv(e.name),
          ),
        const MenuSeparator(),
        item(
          'Manage Global Environments…',
          () => state.modal = const ModalEnvs(),
        ),
      ]),
      const MenuSeparator(),
      item('Run Collection…', () {
        if (col != null) state.openRunner(col.path, null);
      }, enabled: col != null),
    ]);

    final workflow = MenuSpec('Workflow', [
      item('New Workflow', () {
        if (col != null) state.promptNewWorkflow(col.path);
      }, enabled: col != null),
      const MenuSeparator(),
      item('Run', () {
        if (tab != null) state.runWorkflow(tab);
      }, enabled: wf != null && !wf.running),
      item('Stop', () => wf?.cancelled = true, enabled: wf?.running == true),
      item('Add Step…', () {
        if (tab != null) state.modal = ModalAddStep(tabId: tab.id);
      }, enabled: wf != null),
      const MenuSeparator(),
      item('Save Workflow', () {
        if (tab != null) state.saveWorkflow(tab);
      }, enabled: wf != null && wf.dirty),
      check('Show Run Log', wf?.logExpanded == true, () {
        if (wf != null) wf.logExpanded = !wf.logExpanded;
      }, enabled: wf != null),
    ]);

    final window = MenuSpec('Window', [
      item(
        'Minimize',
        minimize_,
        shortcut: isMac ? key(LogicalKeyboardKey.keyM) : null,
      ),
      const MenuSeparator(),
      item(
        'Next Tab',
        () => state.nextTab(1),
        shortcut: const Shortcut(
          LogicalKeyboardKey.tab,
          primary: false,
          control: true,
        ),
        enabled: state.tabs.length > 1,
      ),
      item(
        'Previous Tab',
        () => state.nextTab(-1),
        shortcut: const Shortcut(
          LogicalKeyboardKey.tab,
          primary: false,
          control: true,
          shift: true,
        ),
        enabled: state.tabs.length > 1,
      ),
    ]);

    final help = MenuSpec('Help', [
      item('Welcome Tour', () => state.modal = const ModalOnboarding()),
      item('Keyboard Shortcuts', () {
        state.prefsSection = 'Shortcuts';
        state.modal = const ModalSettings();
      }),
      item('Developer…', () => state.modal = const ModalDeveloper()),
      item('Show Data Folder', () => Platform.reveal(AppStore.dir)),
      if (!isMac) ...[
        const MenuSeparator(),
        item('About ${AppInfo.NAME}', () => state.modal = const ModalAbout()),
      ],
    ]);

    return [file, view, requestMenu, workflow, window, help];
  }
}

/// Dialog with application information.
class AboutDialog extends StatelessWidget {
  const AboutDialog({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ModalBox(
      title: 'About ${AppInfo.NAME}',
      onClose: () => state.modal = null,
      width: 440,
      actions: [
        Btn(label: 'Close', onClick: () => state.modal = null, primary: true),
      ],
      content: [
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 6,
              children: [
                Ico(Ic.logo, tint: p.accent, size: 56),
                T(AppInfo.NAME, size: 22, weight: FontWeight.w700),
                T('Version ${AppInfo.VERSION}', color: p.muted, size: 12),
                if (AppInfo.VENDOR.trim().isNotEmpty)
                  T('by ${AppInfo.VENDOR}', color: p.muted, size: 12),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DefaultTextStyle.merge(
                    textWidthBasis: TextWidthBasis.longestLine,
                    child: T(AppInfo.TAGLINE, color: p.muted, size: 12),
                  ),
                ),
                const SizedBox(height: 6),
                DefaultTextStyle.merge(
                  textWidthBasis: TextWidthBasis.longestLine,
                  child: T(
                    'Your data stays on this computer, in ${AppStore.dir}',
                    color: p.muted,
                    size: 11,
                    mono: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
