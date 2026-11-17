import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/utils/update_checker.dart';

import 'helpers.dart';

void main() {
  test('live: real GitHub, as the app calls it', () async {
    useTempHome();
    final older = await UpdateChecker.check('2.0.0');
    // ignore: avoid_print
    print('running 2.0.0 -> hasUpdate=${older.hasUpdate} version=${older.version} failed=${older.failed} error=${older.error}');
    final same = await UpdateChecker.check('2.1.0');
    // ignore: avoid_print
    print('running 2.1.0 -> hasUpdate=${same.hasUpdate} failed=${same.failed}');
  });
}
