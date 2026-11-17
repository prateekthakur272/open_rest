import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/utils/app_metadata.dart';
import 'package:package_info_plus/package_info_plus.dart';

void _platform(
  String version,
  String build, {
  String package = 'dev.prateekthakur.openrest',
}) => PackageInfo.setMockInitialValues(
  appName: 'OpenRest',
  packageName: package,
  version: version,
  buildNumber: build,
  buildSignature: '',
);

void main() {
  setUp(AppMetadata.reset);

  test('is "dev" until the version has been loaded', () {
    expect(AppMetadata.version, AppMetadata.unknown);
    expect(AppMetadata.build, '');
    expect(AppMetadata.full, 'dev');
  });

  test('reads the version and build number from the platform', () async {
    _platform('2.1.0', '1');
    await AppMetadata.load();
    expect(AppMetadata.version, '2.1.0');
    expect(AppMetadata.build, '1');
    expect(AppMetadata.full, '2.1.0+1');
  });

  test('a missing build number leaves just the version', () async {
    _platform('2.1.0', '');
    await AppMetadata.load();
    expect(AppMetadata.full, '2.1.0');
  });

  test('a blank version keeps the fallback', () async {
    _platform('  ', '7');
    await AppMetadata.load();
    expect(AppMetadata.version, AppMetadata.unknown);
  });

  test('reset forgets what was loaded', () async {
    _platform('3.0.0', '9');
    await AppMetadata.load();
    AppMetadata.reset();
    expect(AppMetadata.full, 'dev');
  });

  group('bundle id', () {
    test('is the constant until the metadata has been loaded', () {
      expect(AppMetadata.bundleId, AppMetadata.fallbackBundleId);
    });

    test('uses the id the platform reports (macOS)', () async {
      _platform('2.1.0', '1', package: 'com.example.other');
      await AppMetadata.load();
      expect(AppMetadata.bundleId, 'com.example.other');
    });

    test(
      'falls back when the platform gives a plain name (Windows, Linux)',
      () async {
        for (final name in ['OpenRest', 'open_rest', '', '  ']) {
          AppMetadata.reset();
          _platform('2.1.0', '1', package: name);
          await AppMetadata.load();
          expect(
            AppMetadata.bundleId,
            AppMetadata.fallbackBundleId,
            reason: '"$name"',
          );
        }
      },
    );

    test('reset goes back to the constant', () async {
      _platform('2.1.0', '1', package: 'com.example.other');
      await AppMetadata.load();
      AppMetadata.reset();
      expect(AppMetadata.bundleId, AppMetadata.fallbackBundleId);
    });
  });
}
