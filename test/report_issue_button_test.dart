import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/utils/app_config.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show host;

/// A browser that only records what it was asked to open.
class _FakeBrowser extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final opened = <String>[];

  // Links are not used here.
  @override
  get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

void main() {
  testWidgets(
    'the report-an-issue button sits next to the GitHub button and opens a new issue',
    (t) async {
      useTempHome();
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.toString().contains('overflowed')) prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      final real = UrlLauncherPlatform.instance;
      final browser = _FakeBrowser();
      UrlLauncherPlatform.instance = browser;
      addTearDown(() => UrlLauncherPlatform.instance = real);
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final s = AppState();
      await t.pumpWidget(host(s));
      await t.pump();

      final report = find.byKey(const ValueKey('report-issue'));
      final github = find.byWidgetPredicate(
        (w) => w is Ico && w.icon == Ic.gitHub,
      );
      expect(report, findsOneWidget);
      expect(github, findsOneWidget);

      // Right after the GitHub icon, on the same line.
      expect(t.getTopLeft(report).dx, greaterThan(t.getTopLeft(github).dx));
      expect(t.getCenter(report).dy, closeTo(t.getCenter(github).dy, 2));
      expect(t.getTopLeft(report).dx - t.getTopRight(github).dx, lessThan(40));

      await t.tap(report);
      await t.pump();
      expect(browser.opened, hasLength(1));
      final u = Uri.parse(browser.opened.single);
      expect('${u.scheme}://${u.host}${u.path}', AppConfig.ISSUES_URL);
      expect(u.queryParameters['body'], contains('**What happened?**'));

      // The GitHub button still opens the developer dialog, not the browser.
      await t.tap(github);
      await t.pump();
      expect(s.modal, isA<ModalDeveloper>());
      expect(browser.opened, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
}
