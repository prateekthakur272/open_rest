import 'dart:convert';
import 'dart:io';

import 'package:open_rest/core/codegen/code_gen.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/bru.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as p;

/// One export target.
class ExportFormat {
  final String id;
  final String label;
  final String ext;
  final String hint;
  const ExportFormat(this.id, this.label, this.ext, this.hint);

  bool get isDirectory => ext.isEmpty;
}

/// Exports a collection to other tools' formats.
class Exporters {
  Exporters._();

  static const List<ExportFormat> formats = [
    ExportFormat(
      'bundle',
      'OpenRest Bundle (single YAML file)',
      '.openrest.yaml',
      'Whole collection and environments in one shareable file. Re-importable.',
    ),
    ExportFormat(
      'postman',
      'Postman Collection v2.1',
      '.postman_collection.json',
      'Folders, requests, bodies, auth and collection variables.',
    ),
    ExportFormat(
      'bruno',
      'Bruno Collection (folder of .bru files)',
      '',
      'Creates a Bruno collection folder inside the chosen directory.',
    ),
    ExportFormat(
      'openapi-yaml',
      'OpenAPI 3.0 / Swagger (YAML)',
      '.openapi.yaml',
      'Paths, parameters, request bodies and security schemes.',
    ),
    ExportFormat(
      'openapi-json',
      'OpenAPI 3.0 / Swagger (JSON)',
      '.openapi.json',
      'Same as above, as JSON (loads in Swagger UI / Editor).',
    ),
    ExportFormat(
      'insomnia',
      'Insomnia v4',
      '.insomnia.json',
      'Requests, folders and environments.',
    ),
    ExportFormat(
      'http',
      'HTTP file (.http)',
      '.http',
      'For VS Code REST Client and JetBrains HTTP Client.',
    ),
    ExportFormat(
      'curl',
      'Shell script of cURL commands',
      '.sh',
      'One curl command per request.',
    ),
  ];

  /// Returns the path that was written.
  static String export(String format, Collection c, String dest) {
    switch (format) {
      case 'bundle':
        File(dest).writeAsStringSync(Yml.dump(_bundle(c)));
        return dest;
      case 'postman':
        File(dest).writeAsStringSync(Importers.exportPostman(c));
        return dest;
      case 'bruno':
        return _bruno(c, dest);
      case 'openapi-yaml':
        File(dest).writeAsStringSync(Yml.dump(_openApi(c)));
        return dest;
      case 'openapi-json':
        File(dest).writeAsStringSync(Json.stringify(_openApi(c), pretty: true));
        return dest;
      case 'insomnia':
        File(dest)
            .writeAsStringSync(Json.stringify(_insomnia(c), pretty: true));
        return dest;
      case 'http':
        File(dest).writeAsStringSync(_httpFile(c));
        return dest;
      case 'curl':
        File(dest).writeAsStringSync(_curlScript(c));
        return dest;
      default:
        throw StateError('Unknown export format: $format');
    }
  }

  static Map<String, dynamic> _nodeMap(Node n) {
    if (n is FolderNode) {
      final m = Map<String, dynamic>.of(
        OrYaml.configToMap(n.config.copyWith(name: n.name), true),
      );
      m['items'] = n.children.map(_nodeMap).toList();
      return m;
    }
    return OrYaml.requestToMap((n as RequestNode).request);
  }

  static Map<String, dynamic> _bundle(Collection c) {
    final m = <String, dynamic>{'openrest': OrYaml.VERSION};
    m.addAll(OrYaml.configToMap(c.config.copyWith(name: c.name), false));
    m['items'] = c.children.map(_nodeMap).toList();
    if (c.environments.isNotEmpty) {
      m['environments'] = c.environments.map(OrYaml.envToMap).toList();
    }
    return m;
  }

  static String _bruno(Collection c, String destParent) {
    var root = p.join(destParent, Collections.sanitize(c.name));
    var i = 1;
    while (FileSystemEntity.typeSync(root) != FileSystemEntityType.notFound) {
      root = p.join(destParent, '${Collections.sanitize(c.name)} (${i++})');
    }
    Directory(root).createSync(recursive: true);
    File(p.join(root, 'bruno.json')).writeAsStringSync(
      Json.stringify({
        'version': '1',
        'name': c.name,
        'type': 'collection',
        'ignore': ['node_modules', '.git'],
      }, pretty: true),
    );
    final cfg = Bru.serializeConfig(c.config, false);
    if (cfg.trim().isNotEmpty) {
      File(p.join(root, 'collection.bru')).writeAsStringSync(cfg);
    }
    void walk(List<Node> nodes, String dir) {
      for (var i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        if (n is FolderNode) {
          final d = p.join(dir, Collections.sanitize(n.name));
          Directory(d).createSync(recursive: true);
          File(p.join(d, 'folder.bru')).writeAsStringSync(
            Bru.serializeConfig(
              n.config.copyWith(name: n.name, seq: i + 1),
              true,
            ),
          );
          walk(n.children, d);
        } else if (n is RequestNode) {
          File(Collections.uniqueFile(dir, n.name, '.bru')).writeAsStringSync(
            Bru.serializeRequest(
              n.request.copyWith(seq: i + 1, params: n.request.params),
            ),
          );
        }
      }
    }

    walk(c.children, root);
    if (c.environments.isNotEmpty) {
      final ed = p.join(root, 'environments');
      Directory(ed).createSync(recursive: true);
      for (final e in c.environments) {
        File(p.join(ed, '${Collections.sanitize(e.name)}.bru'))
            .writeAsStringSync(Bru.serializeEnv(e));
      }
    }
    return root;
  }

  static PreparedRequest _raw(ApiRequest r) {
    final h = [
      for (final k in r.headers.where(
        (k) => k.enabled && k.name.trim().isNotEmpty,
      ))
        (k.name, k.value),
    ];
    var url = r.url;
    for (final pp in r.pathParams.where(
      (k) => k.enabled && k.value.trim().isNotEmpty,
    )) {
      url = url.replaceAll(':${pp.name}', pp.value);
    }
    final a = r.auth;
    switch (a.mode) {
      case AuthMode.Bearer:
        h.add(('Authorization', 'Bearer ${a.token}'));
      case AuthMode.Basic:
        h.add((
          'Authorization',
          'Basic ${base64.encode(utf8.encode('${a.username}:${a.password}'))}',
        ));
      case AuthMode.ApiKey:
        if (a.placement == 'queryparams') {
          url += '${url.contains('?') ? '&' : '?'}${a.keyName}=${a.keyValue}';
        } else {
          h.add((a.keyName, a.keyValue));
        }
      default:
        break;
    }
    final Body body;
    switch (r.bodyMode) {
      case BodyMode.None:
        body = const BodyNone();
      case BodyMode.Json:
        body = BodyRaw(text: r.bodyJson, contentType: 'application/json');
      case BodyMode.Text:
        body = BodyRaw(text: r.bodyText, contentType: 'text/plain');
      case BodyMode.Xml:
        body = BodyRaw(text: r.bodyXml, contentType: 'application/xml');
      case BodyMode.Graphql:
        body = BodyRaw(
          text: Json.stringify({
            'query': r.bodyGraphql,
            'variables':
                Json.tryParse(r.bodyGraphqlVars) ?? <String, dynamic>{},
          }),
          contentType: 'application/json',
        );
      case BodyMode.Form:
        body = BodyForm(
          fields: [
            for (final k in r.formUrlEncoded.where((k) => k.enabled))
              (k.name, k.value),
          ],
        );
      case BodyMode.Multipart:
        body = BodyMultipart(
          parts: [
            for (final k in r.multipart.where((k) => k.enabled))
              Part(
                name: k.name,
                value: k.value,
                isFile: k.isFile,
                contentType: k.contentType,
              ),
          ],
        );
      case BodyMode.File:
        body = BodyFileBody(path: r.bodyFile);
    }
    return PreparedRequest(method: r.method, url: url, headers: h, body: body);
  }

  static List<(String, RequestNode)> _flat(
    List<Node> nodes, [
    String prefix = '',
  ]) => [
    for (final n in nodes)
      if (n is RequestNode)
        (prefix, n)
      else
        ..._flat(
          (n as FolderNode).children,
          prefix.isEmpty ? n.name : '$prefix / ${n.name}',
        ),
  ];

  static List<KV> _baseVars(Collection c) => [
    ...c.config.preVars.where((k) => k.enabled),
    ...(c.environments.isEmpty ? const <KV>[] : c.environments.first.vars),
  ];

  static String _curlScript(Collection c) {
    final sb = StringBuffer();
    sb.write('#!/usr/bin/env bash\n# ${c.name} — exported from OpenRest\n');
    for (final k in _baseVars(c)) {
      sb.write(
        "${k.name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}='${k.value.replaceAll("'", "'\\''")}'\n",
      );
    }
    sb.write('\n');
    for (final (folder, n) in _flat(c.children)) {
      sb.write('# ${folder.isEmpty ? '' : '$folder / '}${n.name}\n');
      sb.write(CodeGen.generate('cURL', _raw(n.request)));
      sb.write('\n\n');
    }
    return sb.toString();
  }

  static String _httpFile(Collection c) {
    final sb = StringBuffer();
    for (final k in _baseVars(c)) {
      sb.write('@${k.name} = ${k.value}\n');
    }
    if (sb.isNotEmpty) sb.write('\n');
    for (final (folder, n) in _flat(c.children)) {
      final pr = _raw(n.request);
      sb.write('### ${folder.isEmpty ? '' : '$folder / '}${n.name}\n');
      sb.write('# @name ${n.name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}\n');
      sb.write('${pr.method} ${pr.url}\n');
      final hs = List<(String, String)>.of(pr.headers);
      final b = pr.body;
      if (b is BodyRaw) {
        if (!hs.any((x) => x.$1.toLowerCase() == 'content-type')) {
          hs.add(('Content-Type', b.contentType));
        }
      } else if (b is BodyForm) {
        hs.add(('Content-Type', 'application/x-www-form-urlencoded'));
      }
      for (final x in hs) {
        sb.write('${x.$1}: ${x.$2}\n');
      }
      if (b is BodyRaw) {
        sb.write('\n${b.text}\n');
      } else if (b is BodyForm) {
        sb.write('\n${HttpExecutor.formEncode(b.fields)}\n');
      } else if (b is BodyFileBody) {
        sb.write('\n< ${b.path}\n');
      } else if (b is BodyMultipart) {
        const bd = '----OpenRestBoundary';
        hs.removeWhere((x) => x.$1.toLowerCase() == 'content-type');
        sb.write('Content-Type: multipart/form-data; boundary=$bd\n\n');
        for (final pt in b.parts) {
          sb.write('--$bd\n');
          if (pt.isFile) {
            final i = pt.value.lastIndexOf('/');
            sb.write(
              'Content-Disposition: form-data; name="${pt.name}"; filename="${i < 0 ? pt.value : pt.value.substring(i + 1)}"\n\n< ${pt.value}\n',
            );
          } else {
            sb.write(
              'Content-Disposition: form-data; name="${pt.name}"\n\n${pt.value}\n',
            );
          }
        }
        sb.write('--$bd--\n');
      }
      sb.write('\n');
    }
    return sb.toString();
  }

  static Map<String, dynamic> _insomnia(Collection c) {
    final res = <Map<String, dynamic>>[];
    var n = 0;
    const ws = 'wrk_1';
    res.add({
      '_id': ws,
      '_type': 'workspace',
      'name': c.name,
      'description': c.config.docs,
      'scope': 'collection',
    });
    void walk(List<Node> nodes, String parent) {
      for (final node in nodes) {
        if (node is FolderNode) {
          final id = 'fld_${++n}';
          res.add({
            '_id': id,
            '_type': 'request_group',
            'parentId': parent,
            'name': node.name,
          });
          walk(node.children, id);
        } else if (node is RequestNode) {
          final r = node.request;
          Map<String, dynamic> body;
          switch (r.bodyMode) {
            case BodyMode.Json:
              body = {'mimeType': 'application/json', 'text': r.bodyJson};
            case BodyMode.Text:
              body = {'mimeType': 'text/plain', 'text': r.bodyText};
            case BodyMode.Xml:
              body = {'mimeType': 'application/xml', 'text': r.bodyXml};
            case BodyMode.Graphql:
              body = {
                'mimeType': 'application/graphql',
                'text': Json.stringify({
                  'query': r.bodyGraphql,
                  'variables':
                      Json.tryParse(r.bodyGraphqlVars) ?? <String, dynamic>{},
                }),
              };
            case BodyMode.Form:
              body = {
                'mimeType': 'application/x-www-form-urlencoded',
                'params': [
                  for (final k in r.formUrlEncoded)
                    {'name': k.name, 'value': k.value, 'disabled': !k.enabled},
                ],
              };
            case BodyMode.Multipart:
              body = {
                'mimeType': 'multipart/form-data',
                'params': [
                  for (final k in r.multipart)
                    {
                      'name': k.name,
                      'value': k.isFile ? '' : k.value,
                      'type': k.isFile ? 'file' : 'text',
                      'fileName': k.isFile ? k.value : '',
                      'disabled': !k.enabled,
                    },
                ],
              };
            default:
              body = <String, dynamic>{};
          }
          Map<String, dynamic> auth;
          switch (r.auth.mode) {
            case AuthMode.Bearer:
              auth = {'type': 'bearer', 'token': r.auth.token};
            case AuthMode.Basic:
              auth = {
                'type': 'basic',
                'username': r.auth.username,
                'password': r.auth.password,
              };
            default:
              auth = <String, dynamic>{};
          }
          final qi = r.url.indexOf('?');
          res.add({
            '_id': 'req_${++n}',
            '_type': 'request',
            'parentId': parent,
            'name': r.name,
            'method': r.method,
            'url': qi < 0 ? r.url : r.url.substring(0, qi),
            'parameters': [
              for (final k in r.params)
                {'name': k.name, 'value': k.value, 'disabled': !k.enabled},
            ],
            'headers': [
              for (final k in r.headers)
                {'name': k.name, 'value': k.value, 'disabled': !k.enabled},
            ],
            'body': body,
            'authentication': auth,
            'description': r.docs,
          });
        }
      }
    }

    walk(c.children, ws);
    const baseId = 'env_base';
    res.add({
      '_id': baseId,
      '_type': 'environment',
      'parentId': ws,
      'name': 'Base Environment',
      'data': {
        for (final k in c.config.preVars.where((k) => k.enabled))
          k.name: k.value,
      },
    });
    for (final e in c.environments) {
      res.add({
        '_id': 'env_${++n}',
        '_type': 'environment',
        'parentId': baseId,
        'name': e.name,
        'data': {
          for (final k in e.vars.where((k) => k.enabled)) k.name: k.value,
        },
      });
    }
    return {
      '_type': 'export',
      '__export_format': 4,
      '__export_source': 'openrest',
      'resources': res,
    };
  }

  static Map<String, dynamic> _schemaOf(dynamic v) {
    if (v is Map) {
      return {
        'type': 'object',
        'properties': {
          for (final e in v.entries) e.key.toString(): _schemaOf(e.value),
        },
      };
    }
    if (v is List) {
      return {'type': 'array', 'items': _schemaOf(v.isEmpty ? null : v.first)};
    }
    if (v is int) return {'type': 'integer'};
    if (v is num) return {'type': 'number'};
    if (v is bool) return {'type': 'boolean'};
    return {'type': 'string'};
  }

  static Map<String, dynamic> _openApi(Collection c) {
    final vars = <String, String>{
      for (final k in [
        ...c.config.preVars.where((k) => k.enabled),
        ...(c.environments.isEmpty
            ? const <KV>[]
            : c.environments.first.vars.where((k) => k.enabled)),
      ])
        k.name: k.value,
    };
    final paths = <String, Map<String, dynamic>>{};
    final schemes = <String, dynamic>{};
    String? server;
    final urlRe = RegExp(
      r'^(https?://[^/]+|\{\{[^}]+\}\})(/.*)?$',
      dotAll: true,
    );
    final leadRe = RegExp(r'^\{\{([^}]+)\}\}(/.*)?$', dotAll: true);
    for (final (folder, node) in _flat(c.children)) {
      final r = node.request;
      final qi = r.url.indexOf('?');
      final rawUrl = qi < 0 ? r.url : r.url.substring(0, qi);
      final lead = leadRe.firstMatch(rawUrl);
      String? base;
      String path;
      if (lead != null && vars.containsKey(lead.group(1))) {
        base = Variables.interpolate(
          vars[lead.group(1)]!,
          (k) => vars[k],
        ).replaceFirst(RegExp(r'/+$'), '');
        final g2 = lead.group(2) ?? '';
        path = g2.isEmpty ? '/' : g2;
      } else {
        final url = Variables.interpolate(rawUrl, (k) => vars[k]);
        final mm = urlRe.firstMatch(url);
        base = mm?.group(1);
        if (mm != null) {
          final g2 = mm.group(2) ?? '';
          path = g2.isEmpty ? '/' : g2;
        } else {
          path = url.startsWith('/') ? url : '/$url';
        }
      }
      if (server == null && base != null) server = base;
      path = path
          .replaceAllMapped(
            RegExp(r'(?<=/):([A-Za-z_][\w-]*)'),
            (m) => '{${m.group(1)}}',
          )
          .replaceAllMapped(
            RegExp(r'\{\{([^}]+)\}\}'),
            (m) => '{${m.group(1)}}',
          );
      final params = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final m in RegExp(r'\{([^}/]+)\}').allMatches(path)) {
        final pn = m.group(1)!;
        if (!seen.add(pn)) continue;
        String? ex;
        for (final k in r.pathParams) {
          if (k.name == pn) {
            ex = k.value;
            break;
          }
        }
        params.add(
          Yml.m([
            ('name', pn),
            ('in', 'path'),
            ('required', true),
            ('schema', {'type': 'string'}),
            ('example', ex),
          ]),
        );
      }
      for (final k in r.params.where(
        (k) => k.enabled && k.name.trim().isNotEmpty,
      )) {
        params.add(
          Yml.m([
            ('name', k.name),
            ('in', 'query'),
            ('required', false),
            ('schema', {'type': 'string'}),
            ('example', k.value),
          ]),
        );
      }
      for (final k in r.headers.where(
        (k) =>
            k.enabled &&
            !const {
              'content-type',
              'accept',
              'authorization',
            }.contains(k.name.toLowerCase()),
      )) {
        params.add(
          Yml.m([
            ('name', k.name),
            ('in', 'header'),
            ('schema', {'type': 'string'}),
            ('example', k.value),
          ]),
        );
      }
      Map<String, dynamic>? bodyContent;
      switch (r.bodyMode) {
        case BodyMode.Json:
          final ex = Json.tryParse(r.bodyJson);
          bodyContent = {
            'application/json': Yml.m([
              ('schema', ex != null ? _schemaOf(ex) : {'type': 'object'}),
              ('example', ex ?? (r.bodyJson.isEmpty ? null : r.bodyJson)),
            ]),
          };
        case BodyMode.Text:
          bodyContent = {
            'text/plain': {
              'schema': {'type': 'string'},
              'example': r.bodyText,
            },
          };
        case BodyMode.Xml:
          bodyContent = {
            'application/xml': {
              'schema': {'type': 'string'},
              'example': r.bodyXml,
            },
          };
        case BodyMode.Graphql:
          bodyContent = {
            'application/json': {
              'schema': _schemaOf({
                'query': '',
                'variables': <String, dynamic>{},
              }),
              'example': {
                'query': r.bodyGraphql,
                'variables':
                    Json.tryParse(r.bodyGraphqlVars) ?? <String, dynamic>{},
              },
            },
          };
        case BodyMode.Form:
          bodyContent = {
            'application/x-www-form-urlencoded': {
              'schema': {
                'type': 'object',
                'properties': {
                  for (final k in r.formUrlEncoded.where((k) => k.enabled))
                    k.name: {'type': 'string', 'example': k.value},
                },
              },
            },
          };
        case BodyMode.Multipart:
          bodyContent = {
            'multipart/form-data': {
              'schema': {
                'type': 'object',
                'properties': {
                  for (final k in r.multipart.where((k) => k.enabled))
                    k.name: k.isFile
                        ? {'type': 'string', 'format': 'binary'}
                        : {'type': 'string', 'example': k.value},
                },
              },
            },
          };
        case BodyMode.File:
          bodyContent = {
            'application/octet-stream': {
              'schema': {'type': 'string', 'format': 'binary'},
            },
          };
        case BodyMode.None:
          bodyContent = null;
      }
      final auth = r.auth.mode == AuthMode.Inherit ? c.config.auth : r.auth;
      List<Map<String, dynamic>>? sec;
      switch (auth.mode) {
        case AuthMode.Bearer:
          schemes['bearerAuth'] = {'type': 'http', 'scheme': 'bearer'};
          sec = [
            {'bearerAuth': <String>[]},
          ];
        case AuthMode.Basic:
          schemes['basicAuth'] = {'type': 'http', 'scheme': 'basic'};
          sec = [
            {'basicAuth': <String>[]},
          ];
        case AuthMode.Digest:
          schemes['digestAuth'] = {'type': 'http', 'scheme': 'digest'};
          sec = [
            {'digestAuth': <String>[]},
          ];
        case AuthMode.ApiKey:
          schemes['apiKeyAuth'] = {
            'type': 'apiKey',
            'in': auth.placement == 'queryparams' ? 'query' : 'header',
            'name': auth.keyName,
          };
          sec = [
            {'apiKeyAuth': <String>[]},
          ];
        default:
          sec = null;
      }
      final op = Yml.m([
        ('tags', folder.isEmpty ? null : [folder]),
        ('summary', r.name),
        ('description', r.docs),
        ('parameters', params),
        ('requestBody', bodyContent == null ? null : {'content': bodyContent}),
        (
          'responses',
          {
            '200': {'description': 'Successful response'},
          },
        ),
        ('security', sec),
      ]);
      (paths[path] ??= <String, dynamic>{})[r.method.toLowerCase()] = op;
    }
    return Yml.m([
      ('openapi', '3.0.3'),
      (
        'info',
        Yml.m([
          ('title', c.name),
          ('description', c.config.docs),
          ('version', '1.0.0'),
        ]),
      ),
      (
        'servers',
        server == null
            ? null
            : [
                {'url': server},
              ],
      ),
      ('paths', paths),
      ('components', Yml.m([('securitySchemes', schemes)])),
    ]);
  }
}
