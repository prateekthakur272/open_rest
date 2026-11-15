import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/storage/storage.dart';

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
}
