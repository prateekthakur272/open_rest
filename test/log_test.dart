import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/logging/log.dart';

void main() {
  String tmp() => '${Directory.systemTemp.createTempSync('log').path}/log.txt';

  test('writesLevelTagMessageAndStackTrace', () {
    final file = tmp();
    Log.writeTo(file);
    Log.warning(
      'storage',
      'Cannot read settings.json',
      StateError('boom'),
      StackTrace.current,
    );
    final text = File(file).readAsStringSync();
    expect(text, contains('WARNING [storage] Cannot read settings.json'));
    expect(text, contains('StateError: boom'));
  });

  test('belowMinimumLevelIsSkipped', () {
    final file = tmp();
    Log.writeTo(file);
    Log.debug('x', 'hidden');
    expect(
      File(file).existsSync() &&
          File(file).readAsStringSync().contains('hidden'),
      isFalse,
    );
    expect(Log.minimumLevel, LogLevel.INFO);
  });

  test('orElseReturnsFallbackAndLogs', () {
    final file = tmp();
    Log.writeTo(file);
    final v = Log.orElse<int>(
      't',
      'Cannot parse',
      -1,
      () => throw StateError('bad'),
    );
    expect(v, -1);
    expect(File(file).readAsStringSync(), contains('Cannot parse: bad'));
  });
}
