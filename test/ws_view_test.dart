import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/features/request/request_pane.dart' show RequestPane;
import 'package:open_rest/features/dialogs/collection_dialogs.dart'
    show NewRequestDialog;

import 'helpers.dart';
import 'shell_widget_test.dart' show host;

void main() {
  testWidgets('websocket tab renders and the dialog creates one', (t) async {
    useTempHome();
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(1500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final dir = Collections.create(tempDir('wsv'), 'W');
    final s = AppState()..addCollection(dir, false);
    await t.pumpWidget(host(s));
    await t.pump();

    s.modal = ModalNewRequest(collection: dir, dir: dir, ws: true);
    await t.pump();
    expect(find.text('Soon'), findsOneWidget);
    expect(find.text('WS'), findsWidgets);
    expect(find.text('GET'), findsNothing);
    await t.enterText(
      find
          .descendant(
            of: find.byType(NewRequestDialog),
            matching: find.byType(EditableText),
          )
          .first,
      'Echo',
    );
    await t.pump();
    await t.tap(find.text('Create'));
    await t.pump();

    final tab = s.activeTab!;
    expect(tab.ws, isNotNull);
    expect(find.byKey(const ValueKey('ws-connect')), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('ws-composer')), findsOneWidget);
    // Filters and Clear sit at the right end of the status row, after the status text.
    final status = t.getTopRight(find.byKey(const ValueKey('ws-status'))).dx;
    final all = t.getTopLeft(find.byKey(const ValueKey('ws-filter-All'))).dx;
    final clear = t.getTopRight(find.byKey(const ValueKey('ws-clear'))).dx;
    expect(all, greaterThan(status));
    expect(clear, closeTo(1500, 30));

    // The message editor is the first tab of the request pane, not part of the log panel.
    expect(tab.reqTab, 'Message');
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('ws-composer')),
        matching: find.byType(RequestPane),
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Params'));
    await t.pump();
    expect(find.byKey(const ValueKey('ws-composer')), findsNothing);
    await t.tap(find.text('Message'));
    await t.pump();
    expect(find.byKey(const ValueKey('ws-composer')), findsOneWidget);

    // Sending needs a connection.
    final send = find.byKey(const ValueKey('ws-send'));
    expect(send, findsOneWidget);
    expect(t.takeException(), isNull);

    // Log entries show in the list and filters narrow them.
    tab.ws!.messages
      ..add(WsMessage(WsDir.sent, text: '{"a":1}'))
      ..add(WsMessage(WsDir.received, text: 'pong'));
    await t.pump();
    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('{"a":1}'), findsOneWidget);
    expect(find.text('pong'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ws-filter-Received')));
    await t.pump();
    expect(find.text('{"a":1}'), findsNothing);
    expect(find.text('pong'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ws-clear')));
    await t.pump();
    expect(find.text('pong'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
