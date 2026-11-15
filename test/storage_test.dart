import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';

void main() {
  setUpAll(() {
    AppStore.homeOverride = Directory.systemTemp.createTempSync('or-home').path;
  });

  test('envStoreRoundTripRenameDelete', () {
    final dir =
        '${Directory.systemTemp.createTempSync('or-genv').path}/environments';
    final scope = Directory.systemTemp.createTempSync('scope').path;
    EnvStore.save(
      dir,
      scope,
      const Environment(
        name: 'Prod/EU',
        vars: [KV(name: 'a', value: '1')],
      ),
    );
    expect(EnvStore.load(dir, scope).map((e) => e.name).toList(), ['Prod/EU']);
    EnvStore.save(
      dir,
      scope,
      const Environment(
        name: 'Prod EU',
        vars: [KV(name: 'a', value: '1')],
      ),
      'Prod/EU',
    );
    expect(EnvStore.load(dir, scope).map((e) => e.name).toList(), ['Prod EU']);
    EnvStore.save(dir, scope, const Environment(name: 'Other'));
    expect(
      () => EnvStore.save(
        dir,
        scope,
        const Environment(name: 'Other'),
        'Prod EU',
      ),
      throwsArgumentError,
    );
    EnvStore.delete(dir, scope, 'Prod EU');
    expect(EnvStore.load(dir, scope).map((e) => e.name).toList(), ['Other']);
  });

  test('secrets stay out of yaml', () {
    final dir =
        '${Directory.systemTemp.createTempSync('or-sec').path}/environments';
    EnvStore.save(
      dir,
      EnvStore.GLOBAL_SCOPE,
      const Environment(
        name: 'S',
        vars: [KV(name: 'tok', value: 'sss')],
        secrets: {'tok'},
      ),
    );
    expect(File('$dir/S.yaml').readAsStringSync().contains('sss'), isFalse);
    expect(
      EnvStore.load(dir, EnvStore.GLOBAL_SCOPE).single.vars.single.value,
      'sss',
    );
  });

  test('settings and state defaults / round trip', () {
    expect(AppStore.loadSettings(), const AppSettings());
    AppStore.saveSettings(
      const AppSettings(theme: ThemeMode.Dark, fontSize: 15),
    );
    expect(AppStore.loadSettings().theme, ThemeMode.Dark);
    expect(AppStore.loadSettings().fontSize, 15);
    AppStore.saveState(
      const SavedState(
        collections: ['/a'],
        envs: {'/a': 'Dev'},
        tabs: ['/a/x.yaml'],
      ),
    );
    final s = AppStore.loadState();
    expect(s.collections, ['/a']);
    expect(s.envs, {'/a': 'Dev'});
    expect(s.sidebarWidth, closeTo(0.22, 1e-6));
  });

  test('collection create / request / reorder', () {
    final tmp = Directory.systemTemp.createTempSync('tree').path;
    final dir = Collections.create(tmp, 'T');
    final f = Collections.createFolder(dir, 'Sub');
    for (final n in ['A', 'B', 'C']) {
      Collections.createRequest(dir, ApiRequest(name: n, url: 'http://x/$n'));
    }
    Collections.createRequest(
      f,
      const ApiRequest(name: 'Inner', url: 'http://x/i'),
    );
    final col = Collections.load(dir);
    expect(col.children.whereType<RequestNode>().map((e) => e.name).toList(), [
      'A',
      'B',
      'C',
    ]);
    expect(col.allRequests().length, 4);
    Collections.reorder(col.children, 0, 1);
    final col2 = Collections.load(dir);
    expect(col2.children.whereType<RequestNode>().map((e) => e.name).toList(), [
      'B',
      'A',
      'C',
    ]);
    expect(() => Collections.move(f, f), throwsArgumentError);
  });
}
