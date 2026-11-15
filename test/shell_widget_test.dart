import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/features/shell/app.dart';
import 'package:open_rest/theme/theme.dart';

import 'helpers.dart';

Widget host(AppState s) => MaterialApp(
  theme: OpenRestTheme.data(true),
  builder: (c, child) => AppScope(
    state: s,
    child: OpenRestTheme(dark: true, child: child!),
  ),
  home: Material(child: OpenRestApp(state: s)),
);

void main() {
  testWidgets('the shell renders and every dialog opens without errors', (
    t,
  ) async {
    useTempHome();
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    final s = AppState();
    await t.pumpWidget(host(s));
    await t.pump();
    expect(
      find.text(
        'Open-source API client — collections are plain files on disk.',
      ),
      findsOneWidget,
    );
    for (final m in <Modal>[
      const ModalOnboarding(),
      const ModalPalette(),
      const ModalSettings(),
      const ModalAbout(),
      const ModalDeveloper(),
      const ModalCookies(),
      const ModalNewCollection(),
      const ModalOpenCollection(),
      const ModalImport(),
      const ModalEnvs(),
    ]) {
      s.modal = m;
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(errors(t), isEmpty, reason: '$m');
    }
    s.modal = null;
    await t.pump();
  });
}

final List<String> _errors = [];

/// Collects everything except RenderFlex overflows (the test font is far wider than the real one).
void captureErrors() {
  _errors.clear();
  FlutterError.onError = (d) {
    if (!d.toString().contains('overflowed')) _errors.add(d.toString());
  };
}

List<String> errors(WidgetTester t) {
  t.takeException();
  return List.of(_errors);
}
