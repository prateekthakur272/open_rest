import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/shell/menus.dart';
import 'package:open_rest/features/shell/window_chrome.dart';

import 'helpers.dart';

List<MenuItemSpec> flat(List<MenuEntry> m) => [
  for (final e in m)
    if (e is MenuItemSpec) e else if (e is SubMenuSpec) ...flat(e.items),
];

extension on List<MenuSpec> {
  MenuItemSpec item(String label) =>
      expand((m) => flat(m.items)).firstWhere((i) => i.label == label);
  MenuSpec menu(String name) => firstWhere((m) => m.label == name);
  List<String> labels() =>
      expand((m) => flat(m.items)).map((i) => i.label).toList();
}

void expectAct(SingleActivator a, SingleActivator b) {
  expect(
    [a.trigger, a.control, a.meta, a.shift, a.alt],
    [b.trigger, b.control, b.meta, b.shift, b.alt],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dragging an edge resizes the window and never below the minimum', () {
    const b = Bounds(100, 100, 1000, 700);
    expect(
      resizeBounds(ResizeEdge.E, b, 150, 99, 760, 480),
      const Bounds(100, 100, 1150, 700),
    );
    expect(
      resizeBounds(ResizeEdge.S, b, 80, -60, 760, 480),
      const Bounds(100, 100, 1000, 640),
    );
    expect(
      resizeBounds(ResizeEdge.W, b, -40, 0, 760, 480),
      const Bounds(60, 100, 1040, 700),
    );
    expect(
      resizeBounds(ResizeEdge.N, b, 0, 30, 760, 480),
      const Bounds(100, 130, 1000, 670),
    );
    expect(
      resizeBounds(ResizeEdge.NW, b, -40, 30, 760, 480),
      const Bounds(60, 130, 1040, 670),
    );
    expect(
      resizeBounds(ResizeEdge.SE, b, 200, 100, 760, 480),
      const Bounds(100, 100, 1200, 800),
    );
    expect(
      resizeBounds(ResizeEdge.W, b, 900, 0, 760, 480),
      const Bounds(340, 100, 760, 700),
    );
    expect(
      resizeBounds(ResizeEdge.N, b, 0, 900, 760, 480),
      const Bounds(100, 320, 1000, 480),
    );
    expect(resizeBounds(ResizeEdge.E, b, -900, 0, 760, 480).w, 760);
  });

  test('mac and windows get their own menus', () {
    useTempHome();
    final s = AppState();
    final mac = AppMenus.build(s, isMac: true);
    final win = AppMenus.build(s, isMac: false);
    expect(mac.map((m) => m.label), [
      'File',
      'View',
      'Request',
      'Workflow',
      'Window',
      'Help',
    ]);
    expect(win.map((m) => m.label), mac.map((m) => m.label));
    expect(
      mac.labels().contains('Preferences…') ||
          mac.labels().contains('Exit') ||
          mac.labels().contains('About OpenRest'),
      isFalse,
    );
    expect(
      win.labels().contains('Preferences…') &&
          win.labels().contains('Exit') &&
          win.labels().contains('About OpenRest'),
      isTrue,
    );
    expect(flat(win.menu('File').items).last.label, 'Exit');
    expect(flat(win.menu('Help').items).last.label, 'About OpenRest');
    final newRequest = mac.item('New Request').shortcut!;
    expect(newRequest.key, LogicalKeyboardKey.keyN);
    expectAct(
      newRequest.toActivator(true),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
    );
    expectAct(
      newRequest.toActivator(false),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true),
    );
    expectAct(
      mac.item('Save All').shortcut!.toActivator(true),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
    );
    expectAct(
      mac.item('Next Tab').shortcut!.toActivator(true),
      const SingleActivator(LogicalKeyboardKey.tab, control: true),
    );
    expect(mac.item('Minimize').shortcut, isNotNull);
    expect(win.item('Minimize').shortcut, isNull);
    expect(mac.item('Save All').shortcut!.label(true), '⇧⌘S');
    expect(win.item('Save All').shortcut!.label(false), 'Ctrl+Shift+S');
    for (final menus in [mac, win]) {
      final keys = menus
          .expand((m) => flat(m.items))
          .map((i) => i.shortcut)
          .whereType<Shortcut>()
          .map((k) => k.label(false))
          .toList();
      expect(keys.length, keys.toSet().length, reason: 'duplicate shortcuts');
    }
    s.dispose();
  });

  test(
    'items are enabled only when they can do something; actions drive the app',
    () {
      useTempHome();
      final s = AppState();
      var empty = AppMenus.build(s, isMac: false);
      expect(empty.item('New Request').enabled, isTrue);
      for (final l in [
        'New Folder',
        'New Workflow',
        'Export Collection…',
        'Save',
        'Save All',
        'Close Tab',
        'Send',
        'Cancel Request',
        'Copy as cURL',
        'Generate Code…',
        'Run',
        'Stop',
        'Add Step…',
        'Variables…',
        'Next Tab',
      ]) {
        expect(
          empty.item(l).enabled,
          isFalse,
          reason: '$l should be disabled with nothing open',
        );
      }
      AppMenus.build(s, isMac: true).item('Import…').action();
      expect(s.modal, const ModalImport());
      AppMenus.build(s, isMac: true).item('Command Palette…').action();
      expect(s.modal, const ModalPalette());
      AppMenus.build(s, isMac: true).item('Command Palette…').action();
      expect(s.modal, isNull);
      AppMenus.build(s, isMac: true).item('Cookies…').action();
      expect(s.modal, const ModalCookies());
      s.modal = null;
      expect(s.settings.theme, ThemeMode.System);
      expect(AppMenus.build(s, isMac: true).item('System').checked, isTrue);
      AppMenus.build(s, isMac: true).item('Dark').action();
      expect(s.settings.theme, ThemeMode.Dark);
      expect(AppMenus.build(s, isMac: true).item('Dark').checked, isTrue);
      AppMenus.build(s, isMac: true).item('Show Sidebar').action();
      expect(s.sidebarVisible, isFalse);
      final size = s.settings.fontSize;
      AppMenus.build(s, isMac: true).item('Zoom In').action();
      expect(s.settings.fontSize, size + 1);
      AppMenus.build(s, isMac: true).item('Actual Size').action();
      expect(s.settings.fontSize, 13);
      AppMenus.build(s, isMac: true).item('Keyboard Shortcuts').action();
      expect(s.modal, const ModalSettings());
      expect(s.prefsSection, 'Shortcuts');
      var quit = 0;
      final win = AppMenus.build(s, isMac: false, quit: () => quit++);
      win.item('Preferences…').action();
      expect(s.modal, const ModalSettings());
      win.item('About OpenRest').action();
      expect(s.modal, const ModalAbout());
      win.item('Exit').action();
      expect(quit, 1);
      s.dispose();
    },
  );

  test('app info is filled in by the app module', () {
    final before = AppInfo.meta;
    try {
      expect(AppInfo.NAME, 'OpenRest');
      expect(AppInfo.VERSION, 'dev');
      AppInfo.meta = const AppMetadata(
        name: 'Demo',
        bundleId: 'x.y',
        version: '2.3.4',
        vendor: 'V',
      );
      expect(AppInfo.NAME, 'Demo');
      expect(AppInfo.BUNDLE_ID, 'x.y');
      expect(AppInfo.VERSION, '2.3.4');
      expect(AppInfo.VENDOR, 'V');
    } finally {
      AppInfo.meta = before;
    }
  });
}
