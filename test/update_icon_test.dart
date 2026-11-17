import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/theme/icons.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show host;

void main() {
  testWidgets('the status-bar update icon follows availableUpdate', (t) async {
    useTempHome();
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

    final icon = find.byWidgetPredicate(
      (w) => w is Ico && w.icon == Ic.download,
    );
    final github = find.byWidgetPredicate(
      (w) => w is Ico && w.icon == Ic.gitHub,
    );
    expect(icon, findsNothing);

    s.availableUpdate = '2.2.0';
    await t.pump();
    expect(icon, findsOneWidget);
    // Between the settings button and the GitHub button, on the same line.
    expect(t.getTopLeft(icon).dx, lessThan(t.getTopLeft(github).dx));
    expect(t.getCenter(icon).dy, closeTo(t.getCenter(github).dy, 2));

    // Clicking it opens the update dialog for that version.
    await t.tap(icon);
    await t.pump();
    expect(s.modal, ModalUpdateAvailable(version: '2.2.0'));

    // The icon goes when the update is cleared (for example after "Download").
    s.modal = null;
    s.availableUpdate = null;
    await t.pump();
    expect(icon, findsNothing);
    expect(t.takeException(), isNull);
  });
}
