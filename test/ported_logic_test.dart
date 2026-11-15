import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/json.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

// Logic tests for tree operations, onboarding, preferences, environments, tables and URL codec.
void main() {
  setUp(useTempHome);

  group('TreeOpsTest', () {
    (AppState, String, String) setup() {
      AppStore.saveState(const SavedState(collections: [], envs: {}));
      final dir = Collections.create(tempDir('tree'), 'T');
      final f = Collections.createFolder(dir, 'Sub');
      for (final n in ['A', 'B', 'C']) {
        Collections.createRequest(dir, ApiRequest(name: n, url: 'http://x/$n'));
      }
      Collections.createRequest(
        f,
        const ApiRequest(name: 'Inner', url: 'http://x/i'),
      );
      final st = AppState();
      st.openCollection(dir);
      return (st, dir, f);
    }

    List<String> order(AppState st, String dir) => st
        .collection(dir)!
        .children
        .whereType<RequestNode>()
        .map((e) => e.name)
        .toList();
    RequestNode req(AppState st, String dir, String n) =>
        st.collection(dir)!.allRequests().firstWhere((e) => e.name == n);

    test('reorder', () {
      final (st, dir, _) = setup();
      expect(order(st, dir), ['A', 'B', 'C']);
      st.dropRequest(dir, req(st, dir, 'C'), req(st, dir, 'A'), false);
      expect(order(st, dir), ['C', 'A', 'B']);
      st.dropRequest(dir, req(st, dir, 'C'), req(st, dir, 'B'), true);
      expect(order(st, dir), ['A', 'B', 'C']);
    });

    test('moveIntoFolderAndOut', () {
      final (st, dir, f) = setup();
      st.moveNode(dir, req(st, dir, 'A').path, f);
      expect(order(st, dir), ['B', 'C']);
      expect(
        st
            .collection(dir)!
            .children
            .whereType<FolderNode>()
            .first
            .children
            .map((e) => e.name)
            .toSet(),
        {'A', 'Inner'},
      );
      st.dropRequest(dir, req(st, dir, 'Inner'), req(st, dir, 'B'), true);
      expect(order(st, dir), ['B', 'Inner', 'C']);
    });

    test('inlineRenameKeepsTabs', () {
      final (st, dir, _) = setup();
      final node = req(st, dir, 'B');
      st.openRequest(dir, node);
      st.renameNode(dir, node, 'Bee');
      expect(st.activeTab!.draft.name, 'Bee');
      expect(p.basename(st.activeTab!.filePath).startsWith('Bee'), isTrue);
      expect(st.activeTab!.dirty, isFalse);
      expect(
        st.collection(dir)!.allRequests().any((e) => e.name == 'Bee'),
        isTrue,
      );
    });

    test('cannotMoveFolderIntoItself', () {
      final (st, dir, f) = setup();
      st.moveNode(dir, f, f);
      expect(Directory(f).existsSync(), isTrue);
    });
  });

  group('Onboarding / Preferences logic', () {
    test('firstRunIsDetectedAndClearedOnceSettingsAreSaved', () {
      expect(AppStore.isFirstRun(), isTrue);
      AppStore.saveSettings(const AppSettings());
      expect(AppStore.isFirstRun(), isFalse);
    });

    test('finishOnboarding saves settings and opens next modal', () {
      final st = AppState();
      expect(AppStore.isFirstRun(), isTrue);
      st.finishOnboarding();
      expect(AppStore.isFirstRun(), isFalse);
      expect(st.modal, isNull);
    });

    test(
      'preferences are applied and saved as you go; reset restores defaults',
      () {
        final st = AppState();
        expect(st.settings.autoSave, isFalse);
        st.updateSettings(st.settings.copyWith(autoSave: true));
        expect(AppStore.loadSettings().autoSave, isTrue);
        st.updateSettings(st.settings.copyWith(fontSize: 14));
        expect(st.settings.fontSize, 14);
        st.updateSettings(st.settings.copyWith(proxyEnabled: true));
        st.updateSettings(const AppSettings());
        expect(st.settings, const AppSettings());
        expect(AppStore.loadSettings(), const AppSettings());
      },
    );

    test('systemThemeFollowsTheOperatingSystemAndOldFilesMigrate', () {
      expect(ThemeMode.System.isDark(true), isTrue);
      expect(ThemeMode.System.isDark(false), isFalse);
      expect(ThemeMode.Light.isDark(true), isFalse);
      expect(ThemeMode.Dark.isDark(false), isTrue);
      expect(const AppSettings().theme, ThemeMode.System);
      final file = File(p.join(AppStore.dir, 'settings.json'));
      file.writeAsStringSync('{"dark": false, "fontSize": 14}');
      expect(AppStore.loadSettings().theme, ThemeMode.Light);
      file.writeAsStringSync('{"dark": true}');
      expect(AppStore.loadSettings().theme, ThemeMode.Dark);
      file.writeAsStringSync('{"theme": "system", "dark": true}');
      expect(AppStore.loadSettings().theme, ThemeMode.System);
      file.writeAsStringSync('{"theme": "bogus"}');
      expect(AppStore.loadSettings().theme, ThemeMode.System);
      AppStore.saveSettings(const AppSettings(theme: ThemeMode.System));
      expect(file.readAsStringSync().contains('"theme": "system"'), isTrue);
    });

    test('zoom clamps and toasts', () {
      final st = AppState();
      st.zoom(1);
      expect(st.settings.fontSize, 14);
      expect(st.toast, 'Zoom 107%');
      st.zoom(-1);
      st.zoom(-1);
      expect(st.settings.fontSize, 12);
      st.zoom(0);
      expect(st.settings.fontSize, 13);
      for (var i = 0; i < 20; i++) {
        st.zoom(1);
      }
      expect(st.settings.fontSize, 20);
    });
  });

  group('TableTest (model part) / persistence', () {
    test('state persisted: tabs, active tab, sidebar, split, env', () {
      final dir = Collections.create(tempDir('st'), 'S');
      Collections.createRequest(
        dir,
        const ApiRequest(name: 'R', url: 'http://x'),
      );
      final st = AppState();
      st.openCollection(dir);
      st.openRequest(dir, st.collection(dir)!.allRequests().first);
      st.sidebarWidth = 0.3;
      st.splitFraction = 0.6;
      st.sidebarVisible = false;
      st.persist();
      final saved = AppStore.loadState();
      expect(saved.collections, [dir]);
      expect(saved.tabs.length, 1);
      expect(saved.activeTab, saved.tabs.first);
      expect(saved.sidebarVisible, isFalse);
      final st2 = AppState();
      expect(st2.tabs.length, 1);
      expect(st2.activeTab, isNotNull);
      expect(st2.sidebarWidth, closeTo(0.3, 1e-6));
      expect(st2.splitFraction, closeTo(0.6, 1e-6));
      expect(st2.sidebarVisible, isFalse);
    });

    test(
      'the sidebar tree remembers which collections and folders were open',
      () {
        final dir = Collections.create(tempDir('ex'), 'E');
        final sub = Collections.createFolder(dir, 'Sub');
        final st = AppState();
        st.openCollection(dir);
        st.expanded[sub] = true;
        st.expanded[dir] = false;
        st.persist();
        final st2 = AppState();
        expect(st2.expanded[sub], isTrue);
        expect(st2.expanded[dir] ?? false, isFalse);
      },
    );

    test('closeTab picks the neighbour and dirty tabs ask first', () {
      final dir = Collections.create(tempDir('ct'), 'C');
      for (final n in ['A', 'B', 'C']) {
        Collections.createRequest(dir, ApiRequest(name: n, url: 'http://x/$n'));
      }
      final st = AppState();
      st.openCollection(dir);
      for (final r in st.collection(dir)!.allRequests()) {
        st.openRequest(dir, r);
      }
      st.activeTabId = st.tabs[1].id;
      st.update(st.tabs[1], (r) => r.copyWith(url: 'http://changed'));
      st.closeTab(st.tabs[1].id);
      expect(st.modal, isA<ModalConfirm>());
      expect(st.tabs.length, 3);
      st.closeTab(st.tabs[1].id, true);
      expect(st.tabs.length, 2);
      expect(st.activeTab!.draft.name, 'C');
    });
  });

  group('EnvironmentTest', () {
    Execution execution(Environment? global, Environment? env) {
      final dir = Collections.create(tempDir('or-env'), 'C');
      Collections.createRequest(
        dir,
        const ApiRequest(
          name: 'R',
          url: 'http://localhost:1/{{host}}/{{only_global}}',
        ),
      );
      if (env != null) Collections.saveEnvironment(dir, env);
      final col = Collections.load(dir);
      return Execution(
        RunCtx(col, env?.name, {}, const AppSettings(), global),
        col.allRequests()[0],
      );
    }

    test('globalIsFallback', () {
      final x = execution(
        const Environment(
          name: 'G',
          vars: [
            KV(name: 'host', value: 'global-host'),
            KV(name: 'only_global', value: 'g'),
          ],
        ),
        null,
      );
      expect(x.lookup('host'), 'global-host');
      expect(x.lookup('only_global'), 'g');
    });

    test('collectionEnvOverridesGlobal', () {
      final x = execution(
        const Environment(
          name: 'G',
          vars: [
            KV(name: 'host', value: 'global-host'),
            KV(name: 'only_global', value: 'g'),
          ],
        ),
        const Environment(
          name: 'Dev',
          vars: [KV(name: 'host', value: 'dev-host')],
        ),
      );
      expect(x.lookup('host'), 'dev-host');
      expect(x.lookup('only_global'), 'g');
    });

    test('disabledGlobalVarsIgnored', () {
      final x = execution(
        const Environment(
          name: 'G',
          vars: [KV(name: 'host', value: 'h', enabled: false)],
        ),
        null,
      );
      expect(x.lookup('host'), isNull);
    });
  });

  test('json numbers', () {
    expect(Json.str(1.0), '1');
    expect(Json.stringify({'a': 1.5, 'b': 2}), '{"a":1.5,"b":2}');
  });
}
