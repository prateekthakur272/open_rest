import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/app_metadata.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'helpers.dart';

void _version(String v) => PackageInfo.setMockInitialValues(
  appName: 'OpenRest',
  packageName: 'dev.prateekthakur.openrest',
  version: v,
  buildNumber: '1',
  buildSignature: '',
);

void _saveSettings(Map<String, dynamic> json) =>
    File('${AppStore.dir}/settings.json').writeAsStringSync(jsonEncode(json));

void main() {
  setUp(() {
    AppMetadata.reset();
    useTempHome();
  });

  test('the default User-Agent follows the app version', () async {
    expect(const AppSettings().userAgent, '');
    expect(const AppSettings().effectiveUserAgent, 'OpenRest/dev');
    _version('2.1.0');
    await AppMetadata.load();
    expect(AppSettings.defaultUserAgent, 'OpenRest/2.1.0');
    expect(const AppSettings().effectiveUserAgent, 'OpenRest/2.1.0');
  });

  test('a custom User-Agent wins; blank counts as unset', () {
    expect(
      const AppSettings(userAgent: ' Acme/9 ').effectiveUserAgent,
      'Acme/9',
    );
    expect(
      const AppSettings(userAgent: '   ').effectiveUserAgent,
      AppSettings.defaultUserAgent,
    );
  });

  test('the User-Agent saved by older versions is read back as unset', () {
    _saveSettings({'userAgent': AppSettings.legacyUserAgent});
    expect(AppStore.loadSettings().userAgent, '');
    _saveSettings({'userAgent': 'Acme/9'});
    expect(AppStore.loadSettings().userAgent, 'Acme/9');
    _saveSettings({'timeoutMs': 5});
    expect(AppStore.loadSettings().userAgent, '');
  });

  test('a custom value survives a save and load; the default stays empty', () {
    AppStore.saveSettings(const AppSettings(userAgent: 'Acme/9'));
    expect(AppStore.loadSettings().userAgent, 'Acme/9');
    AppStore.saveSettings(const AppSettings());
    expect(AppStore.loadSettings().userAgent, '');
  });

  test('requests send the effective User-Agent', () async {
    _version('2.1.0');
    await AppMetadata.load();
    final seen = <String?>[];
    final srv = await startServer((r) async {
      seen.add(r.headers.value('user-agent'));
      await respond(r, '{}');
    });
    addTearDown(() => srv.close(force: true));
    PreparedRequest req() => PreparedRequest(
      method: 'GET',
      url: 'http://127.0.0.1:${srv.port}/',
      headers: const [],
      body: const BodyNone(),
      timeoutMs: 0,
    );
    await HttpExecutor.execute(req(), const AppSettings());
    await HttpExecutor.execute(req(), const AppSettings(userAgent: 'Acme/9'));
    expect(seen, ['OpenRest/2.1.0', 'Acme/9']);
  });
}
