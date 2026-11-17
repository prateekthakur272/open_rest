import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/storage/storage.dart';

import 'helpers.dart';

void main() {
  setUp(useTempHome);

  File prefsFile() => File('${AppStore.dir}/prefs.json');

  test('a flag that was never set is null, and reading creates no file', () {
    expect(AppStore.flag('x'), isNull);
    expect(AppStore.flagString('x'), isNull);
    expect(prefsFile().existsSync(), isFalse);
  });

  test(
    'flags are kept in prefs.json in the data folder and survive a restart',
    () {
      AppStore.setFlag('dismissedUpdateVersion', '2.2.0');
      AppStore.setFlag('seenTip', true);
      expect(prefsFile().existsSync(), isTrue);
      expect(jsonDecode(prefsFile().readAsStringSync()), {
        'dismissedUpdateVersion': '2.2.0',
        'seenTip': true,
      });
      // A fresh read goes to the file: nothing is held in memory.
      expect(AppStore.flagString('dismissedUpdateVersion'), '2.2.0');
      expect(AppStore.flag('seenTip'), true);
      expect(AppStore.flagString('seenTip'), isNull, reason: 'not a string');
    },
  );

  test('setting one flag keeps the others; null removes only that one', () {
    AppStore.setFlag('a', '1');
    AppStore.setFlag('b', '2');
    AppStore.setFlag('a', null);
    expect(AppStore.flag('a'), isNull);
    expect(AppStore.flagString('b'), '2');
    AppStore.setFlag('a', 'again');
    expect(AppStore.flagString('a'), 'again');
  });

  test('removing a flag that does not exist creates nothing', () {
    AppStore.setFlag('nope', null);
    expect(prefsFile().existsSync(), isFalse);
  });

  test('a damaged flags file is treated as empty and then replaced', () {
    prefsFile().writeAsStringSync('{ not json');
    expect(AppStore.flag('a'), isNull);
    AppStore.setFlag('a', '1');
    expect(AppStore.flagString('a'), '1');
    prefsFile().writeAsStringSync('[1, 2, 3]');
    expect(AppStore.flag('a'), isNull);
  });

  test('flags do not touch settings or state', () {
    AppStore.setFlag('a', '1');
    final files = Directory(AppStore.dir)
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .toList();
    expect(files, ['prefs.json']);
  });
}
