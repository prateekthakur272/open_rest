import 'package:flutter/widgets.dart'
    show EditableText, FlutterError, Size, Text, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

void main() {
  group('section badges', () {
    const empty = NodeConfig();
    String? b(NodeSection s, NodeConfig c) => sectionBadge(s, c);

    test('nothing configured shows no badge', () {
      for (final s in NodeSection.values) {
        expect(b(s, empty), isNull, reason: s.name);
      }
    });

    test('headers and variables count only enabled named rows', () {
      final c = empty.copyWith(
        headers: const [
          KV(name: 'A', value: '1'),
          KV(name: 'B', enabled: false),
          KV(name: ' '),
          KV(name: 'C'),
        ],
        preVars: const [KV(name: 'x')],
        postVars: const [
          KV(name: 'y'),
          KV(name: 'z'),
        ],
      );
      expect(b(NodeSection.headers, c), '2');
      expect(b(NodeSection.variables, c), '3');
    });

    test('auth names the mode and treats none / inherit as unset', () {
      Auth a(AuthMode m) => Auth(mode: m);
      expect(
        b(NodeSection.auth, empty.copyWith(auth: a(AuthMode.Bearer))),
        'Bearer',
      );
      expect(
        b(NodeSection.auth, empty.copyWith(auth: a(AuthMode.OAuth2))),
        'OAuth2',
      );
      expect(
        b(NodeSection.auth, empty.copyWith(auth: a(AuthMode.Inherit))),
        isNull,
      );
    });

    test('scripts, tests and docs show a dot when not blank', () {
      expect(b(NodeSection.scripts, empty.copyWith(postScript: 'x')), dotBadge);
      expect(b(NodeSection.scripts, empty.copyWith(preScript: '  \n')), isNull);
      expect(b(NodeSection.tests, empty.copyWith(tests: 't')), dotBadge);
      expect(b(NodeSection.docs, empty.copyWith(docs: 'd')), dotBadge);
    });

    test('tls shows the certificate format or None', () {
      TlsConfig t(TlsMode m, [TlsFormat f = TlsFormat.pfx]) =>
          TlsConfig(mode: m, format: f);
      expect(b(NodeSection.tls, empty.copyWith(tls: t(TlsMode.none))), 'None');
      expect(b(NodeSection.tls, empty.copyWith(tls: t(TlsMode.custom))), 'PFX');
      expect(
        b(
          NodeSection.tls,
          empty.copyWith(tls: t(TlsMode.custom, TlsFormat.pem)),
        ),
        'PEM',
      );
    });
  });

  test('dirty check compares the draft with the saved config', () {
    const saved = NodeConfig(
      headers: [KV(name: 'A', value: '1')],
    );
    expect(nodeConfigDirty(saved, saved.copyWith()), isFalse);
    expect(nodeConfigDirty(saved, saved.copyWith(docs: 'x')), isTrue);
    expect(
      nodeConfigDirty(saved, saved.copyWith(headers: const [KV(name: 'A')])),
      isTrue,
    );
  });

  test('stats count nested requests and folders', () {
    const cfg = NodeConfig();
    RequestNode r(String n) =>
        RequestNode(path: n, name: n, request: ApiRequest());
    final nodes = <Node>[
      r('a'),
      FolderNode(
        path: 'f',
        name: 'f',
        config: cfg,
        children: [
          r('b'),
          FolderNode(path: 'g', name: 'g', config: cfg, children: [r('c')]),
        ],
      ),
    ];
    expect(nodeStats(nodes), const NodeStats(requests: 3, folders: 2));
    expect(findFolder(nodes, 'g')?.name, 'g');
    expect(findFolder(nodes, 'zzz'), isNull);
    expect(countLabel(1, 'folder'), '1 folder');
    expect(countLabel(2, 'folder'), '2 folders');
  });

  testWidgets('settings dialog navigates, tracks edits and guards closing', (
    t,
  ) async {
    useTempHome();
    final oldOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldOnError);
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final dir = Collections.create(tempDir('nodeset'), 'Shop');
    Collections.saveCollectionConfig(
      dir,
      const NodeConfig(
        headers: [KV(name: 'X-A', value: '1')],
      ),
    );
    final s = AppState()..addCollection(dir, false);
    await t.pumpWidget(host(s));
    await t.pump();

    s.modal = ModalNodeSettings(collection: dir, node: dir);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    expect(find.text('Collection Settings — Shop'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-headers')), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);

    for (final sec in NodeSection.values) {
      await t.tap(find.byKey(ValueKey('nav-${sec.name}')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('nav-general')));
    await t.pump();
    expect(find.text('Copy path'), findsOneWidget);
    expect(
      find.text('0 requests  ·  0 folders  ·  0 workflows'),
      findsOneWidget,
    );

    await t.tap(find.byKey(const ValueKey('nav-headers')));
    await t.pump();
    expect(find.text('1'), findsWidgets);
    await t.enterText(find.byType(EditableText).first, 'X-B');
    await t.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('badge-headers'))).data,
      '2',
    );

    // Closing asks first; Cancel keeps the draft.
    await t.tap(find.text('Close'));
    await t.pump();
    expect(
      find.text('This collection has unsaved settings changes.'),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(s.modal, isA<ModalNodeSettings>());
    expect(find.text('Unsaved changes'), findsOneWidget);

    // Revert restores the saved state.
    await t.tap(find.text('Revert'));
    await t.pump();
    expect(find.text('Unsaved changes'), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('badge-headers'))).data,
      '1',
    );

    // Save keeps the dialog open and clears the indicator.
    await t.enterText(find.byType(EditableText).first, 'X-B');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    expect(s.collection(dir)!.config.headers.length, 2);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(s.modal, isA<ModalNodeSettings>());

    // Edit again, then Discard closes without saving.
    await t.enterText(find.byType(EditableText).first, 'X-C');
    await t.pump();
    await t.tap(find.text('Close'));
    await t.pump();
    await t.tap(find.text('Discard'));
    await t.pump();
    expect(s.modal, isNull);
    expect(s.collection(dir)!.config.headers.length, 2);
    expect(errors(t), isEmpty);
  });
}
