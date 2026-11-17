import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app keeps its own files in the data folder (`~/.openrest`): settings.json, state.json, prefs.json ...
/// Nothing may use the platform's preference store (shared_preferences), so everything stays in one place.
void main() {
  test('shared_preferences is not a dependency', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('shared_preferences')),
    );
  });

  test('no source file uses shared_preferences', () {
    final offenders = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            (f.readAsStringSync().contains('shared_preferences') ||
                f.readAsStringSync().contains('SharedPreferences')))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
