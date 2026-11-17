import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/paths.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  test('folder and file names are derived from the app name', () {
    expect(p.basename(Paths.dataDir), '.openrest');
    expect(p.basename(Paths.logFile()), 'openrest.log');
    expect(p.basename(Paths.defaultCollectionsDir), 'OpenRest');
    expect(Paths.logFile('/x/y'), p.join('/x/y', 'openrest.log'));
  });

  test('everything hangs off the same home folder', () {
    expect(p.dirname(Paths.dataDir), Paths.home);
    expect(p.dirname(Paths.defaultCollectionsDir), Paths.home);
    if (!Platform.isWindows && Platform.environment['HOME'] != null) {
      expect(Paths.home, Platform.environment['HOME']);
    }
  });

  test(
    'temp files are unique, keep the extension and sit in the temp folder',
    () {
      final a = Paths.tempFile('.png');
      final b = Paths.tempFile('.png');
      expect(p.extension(a), '.png');
      expect(p.basename(a), startsWith('openrest-'));
      expect(p.dirname(a), Directory.systemTemp.path);
      expect(a, isNot(b));
    },
  );

  test(
    'the store uses the override when set and the data folder otherwise',
    () {
      useTempHome();
      final overridden = AppStore.dir;
      expect(overridden, AppStore.homeOverride);
      expect(File(Paths.logFile(overridden)).parent.path, overridden);
      AppStore.homeOverride = null;
      addTearDown(() => AppStore.homeOverride = null);
    },
  );
}
