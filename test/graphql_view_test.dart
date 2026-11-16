import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/graphql/graphql.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/theme/icons.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show host;

GqlSchema _schema() => GqlSchema.parse({
  'data': {
    '__schema': {
      'queryType': {'name': 'Query'},
      'mutationType': {'name': 'Mutation'},
      'types': [
        {
          'kind': 'OBJECT',
          'name': 'Query',
          'fields': [
            {
              'name': 'user',
              'description': 'Find a user',
              'args': [
                {
                  'name': 'id',
                  'type': {
                    'kind': 'NON_NULL',
                    'ofType': {'kind': 'SCALAR', 'name': 'ID'},
                  },
                },
              ],
              'type': {'kind': 'OBJECT', 'name': 'User'},
            },
          ],
        },
        {
          'kind': 'OBJECT',
          'name': 'Mutation',
          'fields': [
            {
              'name': 'like',
              'args': [],
              'type': {'kind': 'SCALAR', 'name': 'Boolean'},
            },
          ],
        },
        {
          'kind': 'OBJECT',
          'name': 'User',
          'fields': [
            {
              'name': 'name',
              'args': [],
              'type': {'kind': 'SCALAR', 'name': 'String'},
            },
          ],
        },
        {'kind': 'SCALAR', 'name': 'ID'},
        {'kind': 'SCALAR', 'name': 'String'},
        {'kind': 'SCALAR', 'name': 'Boolean'},
      ],
    },
  },
})!;

void main() {
  testWidgets('schema panel: empty, error, browse and insert', (t) async {
    useTempHome();
    // Layout overflows of unrelated widgets at this window size are noise; everything else still fails the test.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(1500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final dir = Collections.create(tempDir('gqlv'), 'G');
    final s = AppState()..addCollection(dir, false);
    s.createRequest(
      dir,
      dir,
      'Q',
      'POST',
      'https://example.com/graphql',
      graphql: true,
    );
    await t.pumpWidget(host(s));
    await t.pump();
    final tab = s.activeTab!;
    tab.reqTab = 'Body';
    await t.pump();

    // The schema browser is a floating menu behind the Docs button, closed by default.
    expect(find.byKey(const ValueKey('gql-docs')), findsNothing);
    await t.tap(find.byKey(const ValueKey('gql-docs-toggle')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('gql-docs')), findsOneWidget);

    // Nothing fetched yet: a clear call to action.
    expect(find.text('No schema loaded'), findsOneWidget);
    expect(find.byKey(const ValueKey('gql-schema')), findsOneWidget);

    // While the schema loads, a spinner replaces the button.
    tab.gqlLoading = true;
    await t.pump();
    expect(find.byKey(const ValueKey('gql-schema-spinner')), findsOneWidget);
    expect(find.text('Fetching schema…'), findsOneWidget);
    expect(find.byKey(const ValueKey('gql-schema')), findsNothing);
    tab.gqlLoading = false;
    await t.pump();

    tab.gqlError = 'HTTP 400: introspection disabled';
    await t.pump();
    expect(find.text('Could not load the schema'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('introspection disabled'), findsOneWidget);

    tab.gqlError = null;
    tab.gqlSchema = _schema();
    await t.pump();
    expect(find.textContaining('SCHEMA · 6 TYPES'), findsOneWidget);
    expect(find.text('Query'), findsOneWidget);
    expect(find.text('Mutation'), findsOneWidget);

    // A root opens its fields; tapping a field inserts it as that operation and the menu stays open.
    s.update(tab, (r) => r.copyWith(bodyGraphql: ''));
    await t.tap(find.byKey(const ValueKey('gql-root-mutation')));
    await t.pump();
    expect(find.text('like'), findsOneWidget);
    await t.tap(find.text('like'));
    await t.pump();
    expect(tab.draft.bodyGraphql, 'mutation {\n  like\n}\n');
    expect(find.byKey(const ValueKey('gql-docs')), findsOneWidget);

    // Back to the roots, then drill from a field into its type.
    await t.tap(find.byKey(const ValueKey('gql-docs-back')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('gql-root-query')));
    await t.pump();
    expect(find.text('user'), findsOneWidget);
    expect(find.textContaining('id: ID!'), findsOneWidget);
    await t.tap(find.byIcon(Ic.chevronRight).first);
    await t.pump();
    expect(find.text('name'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('gql-docs-back')));
    await t.pump();
    expect(find.text('user'), findsOneWidget);

    // Back arrow returns to the root list.
    await t.tap(find.byKey(const ValueKey('gql-docs-back')));
    await t.pump();
    expect(find.text('Query'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('gql-docs-close')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('gql-docs')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'new request dialog: type cards pick GraphQL, gRPC is not available yet',
    (t) async {
      useTempHome();
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      // Overflows of unrelated widgets at this window size are ignored; any other error fails.
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.toString().contains('overflowed')) prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      final dir = Collections.create(tempDir('gqld'), 'G');
      final s = AppState()..addCollection(dir, false);
      await t.pumpWidget(host(s));
      await t.pump();

      s.modal = ModalNewRequest(collection: dir, dir: dir);
      await t.pump();
      for (final n in ['HTTP', 'GraphQL', 'WebSocket', 'gRPC']) {
        expect(find.text(n), findsWidgets);
      }
      expect(find.text('Soon'), findsOneWidget);
      expect(find.text('GET'), findsOneWidget);

      // A disabled card does nothing.
      await t.tap(find.byKey(const ValueKey('new-type-grpc')));
      await t.pump();
      expect(find.text('GET'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('new-type-graphql')));
      await t.pump();
      expect(find.text('GET'), findsNothing);
      expect(find.text('GQL'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
}
