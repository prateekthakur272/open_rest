import 'package:flutter/widgets.dart' show FlutterError, Size, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

void main() {
  testWidgets('collection settings TLS page switches to a custom certificate', (
    t,
  ) async {
    useTempHome();
    final oldOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldOnError);
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final dir = Collections.create(tempDir('tlsdlg'), 'Secure');
    final s = AppState()..addCollection(dir, false);
    await t.pumpWidget(host(s));
    await t.pump();

    s.modal = ModalNodeSettings(collection: dir, node: dir);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    await t.tap(find.byKey(const ValueKey('nav-tls')));
    await t.pump();
    expect(find.text('PFX / PKCS#12'), findsOneWidget);
    expect(find.text('PEM'), findsOneWidget);
    expect(find.text('Passphrase'), findsNothing);

    await t.tap(find.text('PFX / PKCS#12'));
    await t.pump();
    expect(find.text('PFX file'), findsOneWidget);
    expect(find.text('CA bundle'), findsOneWidget);
    expect(find.text('Passphrase'), findsOneWidget);
    expect(find.text('Browse'), findsNWidgets(2));

    await t.tap(find.text('PEM'));
    await t.pump();
    expect(find.text('Certificate'), findsOneWidget);
    expect(find.text('Private key'), findsOneWidget);
    expect(find.text('PFX file'), findsNothing);

    await t.tap(find.text('Save'));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    final saved = s.collection(dir)!.config.tls;
    expect(saved.mode, TlsMode.custom);
    expect(saved.format, TlsFormat.pem);
    expect(errors(t), isEmpty);
  });
}
