import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

void main() {
  test('methodCounts groups requests by method, common ones first', () {
    RequestNode r(String m) => RequestNode(
      path: 'p$m${m.hashCode}',
      name: m,
      request: ApiRequest(name: m, method: m),
    );
    final out = methodCounts([
      r('POST'),
      r('GET'),
      FolderNode(
        path: 'f',
        name: 'f',
        config: const NodeConfig(),
        children: [r('GET'), r('ZED')],
      ),
    ]);
    expect(out.map((e) => '${e.key}${e.value}').toList(), [
      'GET2',
      'POST1',
      'ZED1',
    ]);
  });

  testWidgets('collection tab: overview, docs edit / preview, dirty and save', (
    t,
  ) async {
    useTempHome();
    captureErrors();
    t.view.physicalSize = const Size(1360, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final dir = Collections.create(tempDir('coltab'), 'Shop');
    Collections.saveCollectionConfig(
      dir,
      const NodeConfig(name: 'Shop', docs: '# Welcome\n\nUse **bold** care.'),
    );
    final s = AppState()..addCollection(dir, false);
    await t.pumpWidget(host(s));
    await t.pump();

    s.openCollectionTab(dir);
    s.openCollectionTab(dir);
    await t.pump();
    expect(s.tabs.length, 1);
    expect(s.activeTab!.collection, isNotNull);
    expect(s.activeTab!.title, 'Shop');
    expect(s.activeTab!.dirty, isFalse);

    expect(t.widget<T>(find.byKey(const ValueKey('stat-requests'))).text, '0');
    expect(
      t.widget<T>(find.byKey(const ValueKey('stat-environments'))).text,
      '0',
    );
    // The overview starts right under the page tabs instead of floating in the middle of the page.
    final tabsBottom = t.getBottomLeft(find.text('Overview').first).dy;
    final cardsTop = t
        .getTopLeft(find.byKey(const ValueKey('stat-requests')))
        .dy;
    expect(cardsTop - tabsBottom, lessThan(100));
    expect(find.text('Active environment'), findsOneWidget);
    // Rendered markdown, not the raw source.
    expect(find.textContaining('Welcome'), findsOneWidget);
    expect(find.textContaining('# Welcome'), findsNothing);

    await t.tap(find.byKey(const ValueKey('docs-edit')));
    await t.pump();
    expect(find.textContaining('# Welcome'), findsWidgets);
    s.activeTab!.collection!.controller.update(
      s.activeTab!.collection!.controller.config.copyWith(docs: '# Changed'),
    );
    await t.pump();
    expect(s.activeTab!.dirty, isTrue);
    expect(find.byKey(const ValueKey('collection-unsaved')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('docs-preview')));
    await t.pump();
    expect(find.text('Changed'), findsOneWidget);

    // Revert drops the edit; closing a dirty tab asks first.
    s.activeTab!.collection!.controller.update(
      s.activeTab!.collection!.controller.config.copyWith(docs: '# Saved'),
    );
    await t.pump();
    s.closeTab(s.activeTab!.id);
    await t.pump();
    expect(s.modal, isA<ModalConfirm>());
    s.modal = null;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.text('Save'));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    expect(s.collection(dir)!.config.docs, '# Saved');
    expect(s.activeTab!.dirty, isFalse);
    expect(find.byKey(const ValueKey('collection-unsaved')), findsNothing);

    // Pages switch without losing the tab; the dialog-free settings still edit.
    await t.tap(find.text('Headers'));
    await t.pump();
    expect(s.activeTab!.collection!.page, NodeSection.headers);

    s.closeTab(s.activeTab!.id);
    expect(s.tabs, isEmpty);
    expect(errors(t), isEmpty);
  });
}
