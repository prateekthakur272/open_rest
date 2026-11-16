import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';

import 'helpers.dart';

void main() {
  setUp(useTempHome);

  test('sidePaneSurvivesRestart', () {
    AppStore.saveState(const SavedState(collections: [], envs: {}));
    final col = Collections.create(tempDir('sp'), 'C');
    final folder = Collections.createFolder(col, 'Users');
    final first = AppState();
    first.openCollection(col);
    first.expanded.clear();
    first.expanded[col] = true;
    first.expanded[folder] = true;
    first.sidebarTab = 'History';
    first.sidebarWidth = 0.3;
    first.sidebarVisible = false;
    first.persist();

    final second = AppState();
    expect(second.sidebarTab, 'History');
    expect(second.sidebarWidth, closeTo(0.3, 1e-6));
    expect(second.sidebarVisible, isFalse);
    expect(second.selectedCollection, col);
    expect(second.expanded[folder], true);
  });

  test('layoutSnapshotChangesWithTheSidePane', () {
    final s = AppState();
    final before = s.layoutSnapshot();
    s.sidebarWidth = 0.4;
    expect(listEquals(before, s.layoutSnapshot()), isFalse);
  });

  test('openTabsSurviveRestart', () {
    AppStore.saveState(const SavedState(collections: [], envs: {}));
    final col = Collections.create(tempDir('tabs'), 'C');
    final first = AppState();
    first.openCollection(col);
    first.openCollectionTab(col);
    first.openRunner(col, null);
    final keys = first.tabs.map(first.tabKey).toList();
    first.activeTabId = first.tabs.first.id;
    first.persist();

    final second = AppState();
    expect(second.tabs.map(second.tabKey).toList(), keys);
    expect(second.tabs.length, 2);
    expect(second.tabs.first.collection, isNotNull);
    expect(second.tabs.last.runner, isNotNull);
    expect(second.activeTab?.collection, isNotNull);
  });

  test('tabUiStateSurvivesRestart', () {
    AppStore.saveState(const SavedState(collections: [], envs: {}));
    final col = Collections.create(tempDir('tabui'), 'C');
    final first = AppState();
    first.openCollection(col);
    first.createRequest(col, col, 'R', 'GET', 'http://x.test');
    final req = first.activeTab!;
    req.reqTab = 'Headers';
    req.resTab = 'Timeline';
    first.openCollectionTab(col, page: NodeSection.headers);
    first.persist();

    final second = AppState();
    final r = second.tabs.firstWhere((t) => t.isRequest);
    expect(r.reqTab, 'Headers');
    expect(r.resTab, 'Timeline');
    expect(
      second.tabs.firstWhere((t) => t.collection != null).collection!.page,
      NodeSection.headers,
    );
    // Untouched tabs keep their defaults.
    expect(r.scriptTab, 'Pre Request');
  });

  test('layoutSnapshotChangesWithTheSubTab', () {
    final s = AppState();
    final col = Collections.create(tempDir('tabsnap'), 'C');
    s.openCollection(col);
    s.createRequest(col, col, 'R', 'GET', 'http://x.test');
    final before = s.layoutSnapshot();
    s.activeTab!.reqTab = 'Headers';
    expect(listEquals(before, s.layoutSnapshot()), isFalse);
  });
}
