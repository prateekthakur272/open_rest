import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/graphql/graphql.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/yml.dart';

import 'helpers.dart';

void main() {
  group('parseOperations', () {
    test('named, anonymous and mixed documents', () {
      const q = '''
# query Commented { x }
query Users(\$id: ID!) @dir(a: "}") { user(id: \$id) { name } }
mutation { like }
subscription OnNew { posted { id } }
fragment F on User { id }
''';
      final ops = parseOperations(q);
      expect(ops.map((o) => '${o.type}:${o.name}').toList(), [
        'query:Users',
        'mutation:null',
        'subscription:OnNew',
      ]);
    });

    test('shorthand query and empty text', () {
      expect(parseOperations('{ a { b } }').single.type, 'query');
      expect(parseOperations('{ a { b } }').single.name, isNull);
      expect(parseOperations('   '), isEmpty);
    });
  });

  test('prettifyQuery re-indents and collapses blank lines', () {
    final out = prettifyQuery('query A {\nuser(id: "{") {\n\n\n  name\n}\n}\n');
    expect(out, 'query A {\n  user(id: "{") {\n\n    name\n  }\n}');
  });

  group('schema', () {
    final json = {
      'data': {
        '__schema': {
          'queryType': {'name': 'Query'},
          'mutationType': null,
          'subscriptionType': null,
          'types': [
            {
              'kind': 'OBJECT',
              'name': 'Query',
              'fields': [
                {
                  'name': 'user',
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
              'name': 'User',
              'fields': [
                {
                  'name': 'id',
                  'args': [],
                  'type': {'kind': 'SCALAR', 'name': 'ID'},
                },
                {
                  'name': 'tags',
                  'args': [],
                  'type': {
                    'kind': 'LIST',
                    'ofType': {'kind': 'SCALAR', 'name': 'String'},
                  },
                },
              ],
            },
            {'kind': 'SCALAR', 'name': 'ID'},
            {'kind': 'SCALAR', 'name': 'String'},
            {'kind': 'OBJECT', 'name': '__Schema', 'fields': []},
          ],
        },
      },
    };

    test('parse builds types, args and skeletons', () {
      final s = GqlSchema.parse(json)!;
      expect(s.queryType!.fields.single.args.single.type, 'ID!');
      expect(s.queryType!.fields.single.args.single.required, isTrue);
      expect(s.types['User']!.fields[1].type, '[String]');
      expect(s.visibleTypes.map((t) => t.name), isNot(contains('__Schema')));
      expect(
        s.skeleton(s.queryType!.fields.single),
        'user(id: \$id) {\n  id\n  tags\n}',
      );
    });

    test('parse rejects non-schema bodies', () {
      expect(
        GqlSchema.parse({
          'data': {'x': 1},
        }),
        isNull,
      );
      expect(GqlSchema.parse('nope'), isNull);
    });
  });

  test('insertField starts a query or appends to the last selection set', () {
    expect(insertField('', 'a'), 'query {\n  a\n}\n');
    expect(
      insertField('query Q {\n  a\n}\n', 'b {\n  c\n}'),
      'query Q {\n  a\n  b {\n    c\n  }\n}\n',
    );
    expect(
      insertField('# only a comment', 'x', root: 'mutation'),
      '# only a comment\nmutation {\n  x\n}\n',
    );
  });

  test('graphqlErrors formats messages with location and path', () {
    expect(
      graphqlErrors({
        'errors': [
          {
            'message': 'Bad',
            'locations': [
              {'line': 2, 'column': 5},
            ],
            'path': ['user', 0, 'name'],
          },
          {'message': 'Plain'},
        ],
      }),
      ['Bad (line 2, col 5) at user.0.name', 'Plain'],
    );
    expect(graphqlErrors({'data': {}}), isEmpty);
    expect(graphqlErrors([1]), isEmpty);
  });

  test('operation name persists in yaml and old files still load', () {
    const r = ApiRequest(
      method: 'POST',
      bodyMode: BodyMode.Graphql,
      bodyGraphql: 'query A { a } query B { b }',
      operationName: 'B',
    );
    final back = OrYaml.parseRequest(OrYaml.requestText(r));
    expect(back!.operationName, 'B');
    final old = OrYaml.parseRequest(
      OrYaml.requestText(r.copyWith(operationName: '')),
    );
    expect(old!.operationName, '');
  });

  test('GraphQL tabs open on Body, HTTP tabs on Params', () {
    useTempHome();
    final dir = Collections.create(tempDir('gqlt'), 'G');
    final s = AppState();
    final gql = s.newTab(
      dir,
      'a',
      const ApiRequest(bodyMode: BodyMode.Graphql),
    );
    final http = s.newTab(dir, 'b', const ApiRequest());
    expect(gql.reqTab, 'Body');
    expect(http.reqTab, 'Params');
  });

  group('with a server', () {
    setUp(useTempHome);

    test('create, send operationName and fetch the schema', () async {
      final bodies = <Map<String, dynamic>>[];
      final srv = await startServer((req) async {
        final b = jsonDecode(
          await utf8.decoder.bind(req).join(),
        ) as Map<String, dynamic>;
        bodies.add(b);
        if (b['operationName'] == 'IntrospectionQuery') {
          await respond(
            req,
            jsonEncode({
              'data': {
                '__schema': {
                  'queryType': {'name': 'Query'},
                  'types': [
                    {
                      'kind': 'OBJECT',
                      'name': 'Query',
                      'fields': [
                        {
                          'name': 'hello',
                          'args': [],
                          'type': {'kind': 'SCALAR', 'name': 'String'},
                        },
                      ],
                    },
                    {'kind': 'SCALAR', 'name': 'String'},
                  ],
                },
              },
            }),
          );
        } else {
          await respond(
            req,
            jsonEncode({
              'data': null,
              'errors': [
                {'message': 'boom'},
              ],
            }),
          );
        }
      });
      addTearDown(() => srv.close(force: true));
      final url = 'http://127.0.0.1:${srv.port}/graphql';
      final dir = Collections.create(tempDir('gql'), 'G');
      final s = AppState()..addCollection(dir, false);
      s.createRequest(dir, dir, 'Q', 'GET', url, graphql: true);
      final tab = s.activeTab!;
      expect(tab.draft.method, 'POST');
      expect(tab.draft.bodyMode, BodyMode.Graphql);
      expect(tab.draft.displayMethod, 'GQL');
      expect(tab.reqTab, 'Body');

      s.update(
        tab,
        (r) => r.copyWith(
          bodyGraphql: 'query A { a } query B { b }',
          operationName: 'B',
          bodyGraphqlVars: '{"x":1}',
        ),
      );
      await s.send(tab);
      final sent = bodies.single;
      expect(sent['operationName'], 'B');
      expect(sent['variables'], {'x': 1});
      expect(graphqlErrors(jsonDecode(tab.result!.response!.text)), ['boom']);

      await s.fetchGraphqlSchema(tab);
      expect(tab.gqlError, isNull);
      expect(tab.gqlSchema!.queryType!.fields.single.name, 'hello');
      // The probe must not touch the draft.
      expect(tab.draft.bodyGraphql, 'query A { a } query B { b }');
      expect(bodies.last['operationName'], 'IntrospectionQuery');
    });
  });
}
