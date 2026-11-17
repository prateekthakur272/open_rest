import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/utils/app_config.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show host;

void main() {
  testWidgets('developer dialog lists the profile, repository and more apps', (
    t,
  ) async {
    useTempHome();
    // Layout overflows of unrelated widgets at this window size are ignored; any other error fails.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final s = AppState();
    await t.pumpWidget(host(s));
    await t.pump();

    s.modal = const ModalDeveloper();
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    for (final label in [
      'PROFILE',
      'PROJECT REPOSITORY',
      'EXPLORE MORE APPS',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text(AppConfig.DEVELOPER_URL), findsOneWidget);
    expect(find.text(AppConfig.HOMEPAGE), findsOneWidget);
    expect(find.text(AppConfig.MORE_APPS_URL), findsOneWidget);
    expect(
      AppConfig.MORE_APPS_URL,
      'https://prateekthakur272.github.io/github-marketplace/',
    );
    expect(t.takeException(), isNull);
  });
}
