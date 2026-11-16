// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:open_rest/core/run/workflow_model.dart';

const Object _unset = Object();

/// A name/value pair that can be switched off.
class KV {
  final String name;
  final String value;
  final bool enabled;
  final bool isFile;
  final String contentType;

  const KV({
    this.name = '',
    this.value = '',
    this.enabled = true,
    this.isFile = false,
    this.contentType = '',
  });

  KV copyWith({
    String? name,
    String? value,
    bool? enabled,
    bool? isFile,
    String? contentType,
  }) => KV(
    name: name ?? this.name,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
    isFile: isFile ?? this.isFile,
    contentType: contentType ?? this.contentType,
  );

  @override
  bool operator ==(Object other) =>
      other is KV &&
      other.name == name &&
      other.value == value &&
      other.enabled == enabled &&
      other.isFile == isFile &&
      other.contentType == contentType;

  @override
  int get hashCode => Object.hash(name, value, enabled, isFile, contentType);

  @override
  String toString() =>
      'KV(name=$name, value=$value, enabled=$enabled, isFile=$isFile, contentType=$contentType)';
}

/// How the request body is entered.
enum BodyMode {
  None('No Body', 'none'),
  Json('JSON', 'json'),
  Text('Text', 'text'),
  Xml('XML', 'xml'),
  Form('Form URL Encoded', 'formUrlEncoded'),
  Multipart('Multipart Form', 'multipartForm'),
  Graphql('GraphQL', 'graphql'),
  File('File / Binary', 'file');

  final String label;
  final String bru;
  const BodyMode(this.label, this.bru);

  static BodyMode fromBru(String s) {
    for (final e in BodyMode.values) {
      if (e.bru.toLowerCase() == s.toLowerCase()) return e;
    }
    return BodyMode.None;
  }
}

/// Authentication scheme of a request.
enum AuthMode {
  None('No Auth', 'none'),
  Inherit('Inherit', 'inherit'),
  Basic('Basic Auth', 'basic'),
  Bearer('Bearer Token', 'bearer'),
  ApiKey('API Key', 'apikey'),
  Digest('Digest Auth', 'digest'),
  OAuth2('OAuth 2.0', 'oauth2');

  final String label;
  final String bru;
  const AuthMode(this.label, this.bru);

  static AuthMode fromBru(String s) {
    for (final e in AuthMode.values) {
      if (e.bru.toLowerCase() == s.toLowerCase()) return e;
    }
    return AuthMode.None;
  }
}

/// Authentication settings.
class Auth {
  final AuthMode mode;
  final String username;
  final String password;
  final String token;
  final String keyName;
  final String keyValue;
  final String placement; // header | queryparams
  final String grantType; // client_credentials | password
  final String tokenUrl;
  final String clientId;
  final String clientSecret;
  final String scope;

  const Auth({
    this.mode = AuthMode.None,
    this.username = '',
    this.password = '',
    this.token = '',
    this.keyName = '',
    this.keyValue = '',
    this.placement = 'header',
    this.grantType = 'client_credentials',
    this.tokenUrl = '',
    this.clientId = '',
    this.clientSecret = '',
    this.scope = '',
  });

  Auth copyWith({
    AuthMode? mode,
    String? username,
    String? password,
    String? token,
    String? keyName,
    String? keyValue,
    String? placement,
    String? grantType,
    String? tokenUrl,
    String? clientId,
    String? clientSecret,
    String? scope,
  }) => Auth(
    mode: mode ?? this.mode,
    username: username ?? this.username,
    password: password ?? this.password,
    token: token ?? this.token,
    keyName: keyName ?? this.keyName,
    keyValue: keyValue ?? this.keyValue,
    placement: placement ?? this.placement,
    grantType: grantType ?? this.grantType,
    tokenUrl: tokenUrl ?? this.tokenUrl,
    clientId: clientId ?? this.clientId,
    clientSecret: clientSecret ?? this.clientSecret,
    scope: scope ?? this.scope,
  );

  @override
  bool operator ==(Object other) =>
      other is Auth &&
      other.mode == mode &&
      other.username == username &&
      other.password == password &&
      other.token == token &&
      other.keyName == keyName &&
      other.keyValue == keyValue &&
      other.placement == placement &&
      other.grantType == grantType &&
      other.tokenUrl == tokenUrl &&
      other.clientId == clientId &&
      other.clientSecret == clientSecret &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(
    mode,
    username,
    password,
    token,
    keyName,
    keyValue,
    placement,
    grantType,
    tokenUrl,
    clientId,
    clientSecret,
    scope,
  );
}

/// Where a client certificate setting comes from.
enum TlsMode { inherit, none, custom }

/// File format of a client certificate.
enum TlsFormat { pfx, pem }

/// TLS client certificate settings. Only file paths are stored.
class TlsConfig {
  final TlsMode mode;
  final TlsFormat format;
  final String pfxPath;
  final String certPath;
  final String keyPath;
  final String caPath;
  final String passphrase;

  const TlsConfig({
    this.mode = TlsMode.inherit,
    this.format = TlsFormat.pfx,
    this.pfxPath = '',
    this.certPath = '',
    this.keyPath = '',
    this.caPath = '',
    this.passphrase = '',
  });

  TlsConfig copyWith({
    TlsMode? mode,
    TlsFormat? format,
    String? pfxPath,
    String? certPath,
    String? keyPath,
    String? caPath,
    String? passphrase,
  }) => TlsConfig(
    mode: mode ?? this.mode,
    format: format ?? this.format,
    pfxPath: pfxPath ?? this.pfxPath,
    certPath: certPath ?? this.certPath,
    keyPath: keyPath ?? this.keyPath,
    caPath: caPath ?? this.caPath,
    passphrase: passphrase ?? this.passphrase,
  );

  @override
  bool operator ==(Object other) =>
      other is TlsConfig &&
      other.mode == mode &&
      other.format == format &&
      other.pfxPath == pfxPath &&
      other.certPath == certPath &&
      other.keyPath == keyPath &&
      other.caPath == caPath &&
      other.passphrase == passphrase;

  @override
  int get hashCode =>
      Object.hash(mode, format, pfxPath, certPath, keyPath, caPath, passphrase);
}

const HTTP_METHODS = [
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
  'TRACE',
];

/// A saved request.
class ApiRequest {
  final String name;
  final int seq;
  final String method;
  final String url;
  final List<KV> params;
  final List<KV> pathParams;
  final List<KV> headers;
  final BodyMode bodyMode;
  final String bodyJson;
  final String bodyText;
  final String bodyXml;
  final String bodyGraphql;
  final String bodyGraphqlVars;
  final String operationName;
  final String bodyFile;
  final List<KV> formUrlEncoded;
  final List<KV> multipart;
  final Auth auth;
  final List<KV> preVars;
  final List<KV> postVars;
  final List<KV> assertions;
  final String preScript;
  final String postScript;
  final String tests;
  final String docs;
  final bool encodeUrl;
  final int timeoutMs;
  final TlsConfig tls;

  const ApiRequest({
    this.name = 'New Request',
    this.seq = 1,
    this.method = 'GET',
    this.url = '',
    this.params = const [],
    this.pathParams = const [],
    this.headers = const [],
    this.bodyMode = BodyMode.None,
    this.bodyJson = '',
    this.bodyText = '',
    this.bodyXml = '',
    this.bodyGraphql = '',
    this.bodyGraphqlVars = '',
    this.operationName = '',
    this.bodyFile = '',
    this.formUrlEncoded = const [],
    this.multipart = const [],
    this.auth = const Auth(mode: AuthMode.Inherit),
    this.preVars = const [],
    this.postVars = const [],
    this.assertions = const [],
    this.preScript = '',
    this.postScript = '',
    this.tests = '',
    this.docs = '',
    this.encodeUrl = true,
    this.timeoutMs = 0,
    this.tls = const TlsConfig(),
  });

  /// Label shown in lists and tabs: `GQL` for GraphQL bodies, otherwise the HTTP method.
  String get displayMethod => bodyMode == BodyMode.Graphql ? 'GQL' : method;

  ApiRequest copyWith({
    String? name,
    int? seq,
    String? method,
    String? url,
    List<KV>? params,
    List<KV>? pathParams,
    List<KV>? headers,
    BodyMode? bodyMode,
    String? bodyJson,
    String? bodyText,
    String? bodyXml,
    String? bodyGraphql,
    String? bodyGraphqlVars,
    String? operationName,
    String? bodyFile,
    List<KV>? formUrlEncoded,
    List<KV>? multipart,
    Auth? auth,
    List<KV>? preVars,
    List<KV>? postVars,
    List<KV>? assertions,
    String? preScript,
    String? postScript,
    String? tests,
    String? docs,
    bool? encodeUrl,
    int? timeoutMs,
    TlsConfig? tls,
  }) => ApiRequest(
    name: name ?? this.name,
    seq: seq ?? this.seq,
    method: method ?? this.method,
    url: url ?? this.url,
    params: params ?? this.params,
    pathParams: pathParams ?? this.pathParams,
    headers: headers ?? this.headers,
    bodyMode: bodyMode ?? this.bodyMode,
    bodyJson: bodyJson ?? this.bodyJson,
    bodyText: bodyText ?? this.bodyText,
    bodyXml: bodyXml ?? this.bodyXml,
    bodyGraphql: bodyGraphql ?? this.bodyGraphql,
    bodyGraphqlVars: bodyGraphqlVars ?? this.bodyGraphqlVars,
    operationName: operationName ?? this.operationName,
    bodyFile: bodyFile ?? this.bodyFile,
    formUrlEncoded: formUrlEncoded ?? this.formUrlEncoded,
    multipart: multipart ?? this.multipart,
    auth: auth ?? this.auth,
    preVars: preVars ?? this.preVars,
    postVars: postVars ?? this.postVars,
    assertions: assertions ?? this.assertions,
    preScript: preScript ?? this.preScript,
    postScript: postScript ?? this.postScript,
    tests: tests ?? this.tests,
    docs: docs ?? this.docs,
    encodeUrl: encodeUrl ?? this.encodeUrl,
    timeoutMs: timeoutMs ?? this.timeoutMs,
    tls: tls ?? this.tls,
  );

  @override
  bool operator ==(Object other) =>
      other is ApiRequest &&
      other.name == name &&
      other.seq == seq &&
      other.method == method &&
      other.url == url &&
      listEquals(other.params, params) &&
      listEquals(other.pathParams, pathParams) &&
      listEquals(other.headers, headers) &&
      other.bodyMode == bodyMode &&
      other.bodyJson == bodyJson &&
      other.bodyText == bodyText &&
      other.bodyXml == bodyXml &&
      other.bodyGraphql == bodyGraphql &&
      other.bodyGraphqlVars == bodyGraphqlVars &&
      other.operationName == operationName &&
      other.bodyFile == bodyFile &&
      listEquals(other.formUrlEncoded, formUrlEncoded) &&
      listEquals(other.multipart, multipart) &&
      other.auth == auth &&
      listEquals(other.preVars, preVars) &&
      listEquals(other.postVars, postVars) &&
      listEquals(other.assertions, assertions) &&
      other.preScript == preScript &&
      other.postScript == postScript &&
      other.tests == tests &&
      other.docs == docs &&
      other.encodeUrl == encodeUrl &&
      other.timeoutMs == timeoutMs &&
      other.tls == tls;

  @override
  int get hashCode => Object.hashAll([
    name,
    seq,
    method,
    url,
    Object.hashAll(params),
    Object.hashAll(pathParams),
    Object.hashAll(headers),
    bodyMode,
    bodyJson,
    bodyText,
    bodyXml,
    bodyGraphql,
    bodyGraphqlVars,
    operationName,
    bodyFile,
    Object.hashAll(formUrlEncoded),
    Object.hashAll(multipart),
    auth,
    Object.hashAll(preVars),
    Object.hashAll(postVars),
    Object.hashAll(assertions),
    preScript,
    postScript,
    tests,
    docs,
    encodeUrl,
    timeoutMs,
    tls,
  ]);
}

/// Settings shared by a whole collection (collection config) or a folder (folder.yaml).
class NodeConfig {
  final String name;
  final int seq;
  final List<KV> headers;
  final Auth auth;
  final List<KV> preVars;
  final List<KV> postVars;
  final String preScript;
  final String postScript;
  final String tests;
  final String docs;
  final TlsConfig tls;

  const NodeConfig({
    this.name = '',
    this.seq = 1,
    this.headers = const [],
    this.auth = const Auth(mode: AuthMode.None),
    this.preVars = const [],
    this.postVars = const [],
    this.preScript = '',
    this.postScript = '',
    this.tests = '',
    this.docs = '',
    this.tls = const TlsConfig(),
  });

  NodeConfig copyWith({
    String? name,
    int? seq,
    List<KV>? headers,
    Auth? auth,
    List<KV>? preVars,
    List<KV>? postVars,
    String? preScript,
    String? postScript,
    String? tests,
    String? docs,
    TlsConfig? tls,
  }) => NodeConfig(
    name: name ?? this.name,
    seq: seq ?? this.seq,
    headers: headers ?? this.headers,
    auth: auth ?? this.auth,
    preVars: preVars ?? this.preVars,
    postVars: postVars ?? this.postVars,
    preScript: preScript ?? this.preScript,
    postScript: postScript ?? this.postScript,
    tests: tests ?? this.tests,
    docs: docs ?? this.docs,
    tls: tls ?? this.tls,
  );

  @override
  bool operator ==(Object other) =>
      other is NodeConfig &&
      other.name == name &&
      other.seq == seq &&
      listEquals(other.headers, headers) &&
      other.auth == auth &&
      listEquals(other.preVars, preVars) &&
      listEquals(other.postVars, postVars) &&
      other.preScript == preScript &&
      other.postScript == postScript &&
      other.tests == tests &&
      other.docs == docs &&
      other.tls == tls;

  @override
  int get hashCode => Object.hash(
    name,
    seq,
    Object.hashAll(headers),
    auth,
    Object.hashAll(preVars),
    Object.hashAll(postVars),
    preScript,
    postScript,
    tests,
    docs,
    tls,
  );
}

/// A named set of variables.
class Environment {
  final String name;
  final List<KV> vars;
  final Set<String> secrets;

  const Environment({
    required this.name,
    this.vars = const [],
    this.secrets = const {},
  });

  Environment copyWith({String? name, List<KV>? vars, Set<String>? secrets}) =>
      Environment(
        name: name ?? this.name,
        vars: vars ?? this.vars,
        secrets: secrets ?? this.secrets,
      );

  @override
  bool operator ==(Object other) =>
      other is Environment &&
      other.name == name &&
      listEquals(other.vars, vars) &&
      setEquals(other.secrets, secrets);

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(vars), Object.hashAllUnordered(secrets));
}

sealed class Node {
  const Node();

  /// Absolute file-system path (file for requests, directory for folders).
  String get path;
  String get name;
}

class FolderNode extends Node {
  @override
  final String path;
  @override
  final String name;
  final NodeConfig config;
  final List<Node> children;

  const FolderNode({
    required this.path,
    required this.name,
    required this.config,
    required this.children,
  });

  FolderNode copyWith({
    String? path,
    String? name,
    NodeConfig? config,
    List<Node>? children,
  }) => FolderNode(
    path: path ?? this.path,
    name: name ?? this.name,
    config: config ?? this.config,
    children: children ?? this.children,
  );

  @override
  bool operator ==(Object other) =>
      other is FolderNode &&
      other.path == path &&
      other.name == name &&
      other.config == config &&
      listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(path, name, config, Object.hashAll(children));
}

class RequestNode extends Node {
  @override
  final String path;
  @override
  final String name;
  final ApiRequest request;

  const RequestNode({
    required this.path,
    required this.name,
    required this.request,
  });

  RequestNode copyWith({String? path, String? name, ApiRequest? request}) =>
      RequestNode(
        path: path ?? this.path,
        name: name ?? this.name,
        request: request ?? this.request,
      );

  @override
  bool operator ==(Object other) =>
      other is RequestNode &&
      other.path == path &&
      other.name == name &&
      other.request == request;

  @override
  int get hashCode => Object.hash(path, name, request);
}

/// An opened collection with its node tree.
class Collection {
  final String path;
  final String name;
  final NodeConfig config;
  final List<Node> children;
  final List<Environment> environments;
  final Map<String, String> dotEnv;
  final List<Workflow> workflows;

  const Collection({
    required this.path,
    required this.name,
    required this.config,
    required this.children,
    required this.environments,
    this.dotEnv = const {},
    this.workflows = const [],
  });

  Collection copyWith({
    String? path,
    String? name,
    NodeConfig? config,
    List<Node>? children,
    List<Environment>? environments,
    Map<String, String>? dotEnv,
    List<Workflow>? workflows,
  }) => Collection(
    path: path ?? this.path,
    name: name ?? this.name,
    config: config ?? this.config,
    children: children ?? this.children,
    environments: environments ?? this.environments,
    dotEnv: dotEnv ?? this.dotEnv,
    workflows: workflows ?? this.workflows,
  );

  @override
  bool operator ==(Object other) =>
      other is Collection &&
      other.path == path &&
      other.name == name &&
      other.config == config &&
      listEquals(other.children, children) &&
      listEquals(other.environments, environments) &&
      mapEquals(other.dotEnv, dotEnv) &&
      listEquals(other.workflows, workflows);

  @override
  int get hashCode => Object.hash(
    path,
    name,
    config,
    Object.hashAll(children),
    Object.hashAll(environments),
    Object.hashAll(workflows),
  );

  List<RequestNode> allRequests() {
    List<RequestNode> walk(List<Node> n) => [
      for (final x in n)
        if (x is RequestNode) x else ...walk((x as FolderNode).children),
    ];
    return walk(children);
  }

  RequestNode? findRequest(String path) {
    for (final r in allRequests()) {
      if (r.path == path) return r;
    }
    return null;
  }

  /// Folder configs from the collection root down to (not including) the node at [target].
  List<FolderNode> ancestorFolders(String target) {
    final out = <FolderNode>[];
    bool walk(List<Node> list) {
      for (final n in list) {
        if (n.path == target) return true;
        if (n is FolderNode) {
          out.add(n);
          if (walk(n.children)) return true;
          out.removeLast();
        }
      }
      return false;
    }

    walk(children);
    return out;
  }
}

/// Request body variants: [BodyNone] / [BodyRaw] / [BodyForm] / [BodyMultipart] / [BodyFileBody].
sealed class Body {
  const Body();
  static const Body none = BodyNone();
}

class BodyNone extends Body {
  const BodyNone();
  @override
  bool operator ==(Object other) => other is BodyNone;
  @override
  int get hashCode => 0;
}

class BodyRaw extends Body {
  final String text;
  final String contentType;
  const BodyRaw({required this.text, required this.contentType});
  @override
  bool operator ==(Object other) =>
      other is BodyRaw &&
      other.text == text &&
      other.contentType == contentType;
  @override
  int get hashCode => Object.hash(text, contentType);
}

class BodyForm extends Body {
  final List<(String, String)> fields;
  const BodyForm({required this.fields});
  @override
  bool operator ==(Object other) =>
      other is BodyForm && listEquals(other.fields, fields);
  @override
  int get hashCode => Object.hashAll(fields);
}

class BodyMultipart extends Body {
  final List<Part> parts;
  const BodyMultipart({required this.parts});
  @override
  bool operator ==(Object other) =>
      other is BodyMultipart && listEquals(other.parts, parts);
  @override
  int get hashCode => Object.hashAll(parts);
}

class BodyFileBody extends Body {
  final String path;
  const BodyFileBody({required this.path});
  @override
  bool operator ==(Object other) => other is BodyFileBody && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

class Part {
  final String name;
  final String value;
  final bool isFile;
  final String contentType;
  const Part({
    required this.name,
    required this.value,
    required this.isFile,
    this.contentType = '',
  });

  Part copyWith({
    String? name,
    String? value,
    bool? isFile,
    String? contentType,
  }) => Part(
    name: name ?? this.name,
    value: value ?? this.value,
    isFile: isFile ?? this.isFile,
    contentType: contentType ?? this.contentType,
  );

  @override
  bool operator ==(Object other) =>
      other is Part &&
      other.name == name &&
      other.value == value &&
      other.isFile == isFile &&
      other.contentType == contentType;
  @override
  int get hashCode => Object.hash(name, value, isFile, contentType);
}

/// A request with every variable and auth applied.
class PreparedRequest {
  final String method;
  final String url;
  final List<(String, String)> headers;
  final Body body;
  final int timeoutMs;

  /// Resolved client certificate, null when none applies.
  final TlsConfig? tls;

  const PreparedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    this.timeoutMs = 0,
    this.tls,
  });

  PreparedRequest copyWith({
    String? method,
    String? url,
    List<(String, String)>? headers,
    Body? body,
    int? timeoutMs,
    Object? tls = _unset,
  }) => PreparedRequest(
    method: method ?? this.method,
    url: url ?? this.url,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    timeoutMs: timeoutMs ?? this.timeoutMs,
    tls: identical(tls, _unset) ? this.tls : tls as TlsConfig?,
  );

  @override
  bool operator ==(Object other) =>
      other is PreparedRequest &&
      other.method == method &&
      other.url == url &&
      listEquals(other.headers, headers) &&
      other.body == body &&
      other.timeoutMs == timeoutMs &&
      other.tls == tls;
  @override
  int get hashCode =>
      Object.hash(method, url, Object.hashAll(headers), body, timeoutMs, tls);
}

/// Outcome of an HTTP call.
class HttpResult {
  final int status;
  final String statusText;
  final List<(String, String)> headers;
  final Uint8List body;
  final int timeMs;
  final String finalUrl;
  final String? error;

  HttpResult({
    this.status = 0,
    this.statusText = '',
    this.headers = const [],
    Uint8List? body,
    this.timeMs = 0,
    this.finalUrl = '',
    this.error,
  }) : body = body ?? Uint8List(0);

  String get contentType {
    for (final h in headers) {
      if (h.$1.toLowerCase() == 'content-type') return h.$2;
    }
    return '';
  }

  String get text => _decode();
  int get size => body.length;

  String _decode() {
    final cs = RegExp(
      r'charset=([\w-]+)',
      caseSensitive: false,
    ).firstMatch(contentType)?.group(1)?.toLowerCase();
    try {
      if (cs == null || cs == 'utf-8' || cs == 'utf8') {
        return utf8.decode(body, allowMalformed: true);
      }
      if (cs == 'iso-8859-1' || cs == 'latin1' || cs == 'latin-1') {
        return latin1.decode(body);
      }
      if (cs == 'us-ascii' || cs == 'ascii') {
        return ascii.decode(body, allowInvalid: true);
      }
      return utf8.decode(body, allowMalformed: true);
    } catch (_) {
      return utf8.decode(body, allowMalformed: true);
    }
  }

  HttpResult copyWith({
    int? status,
    String? statusText,
    List<(String, String)>? headers,
    Uint8List? body,
    int? timeMs,
    String? finalUrl,
    Object? error = _unset,
  }) => HttpResult(
    status: status ?? this.status,
    statusText: statusText ?? this.statusText,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    timeMs: timeMs ?? this.timeMs,
    finalUrl: finalUrl ?? this.finalUrl,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  // Identity equality.
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => identityHashCode(this);
}

/// Outcome of one test or assertion.
class TestResult {
  final String name;
  final bool passed;
  final String message;
  final String kind;
  const TestResult({
    required this.name,
    required this.passed,
    this.message = '',
    this.kind = 'test',
  });

  TestResult copyWith({
    String? name,
    bool? passed,
    String? message,
    String? kind,
  }) => TestResult(
    name: name ?? this.name,
    passed: passed ?? this.passed,
    message: message ?? this.message,
    kind: kind ?? this.kind,
  );

  @override
  bool operator ==(Object other) =>
      other is TestResult &&
      other.name == name &&
      other.passed == passed &&
      other.message == message &&
      other.kind == kind;
  @override
  int get hashCode => Object.hash(name, passed, message, kind);
  @override
  String toString() =>
      'TestResult(name=$name, passed=$passed, message=$message, kind=$kind)';
}

/// Everything a request run produced.
class ExecResult {
  final PreparedRequest? request;
  final HttpResult? response;
  final List<TestResult> tests;
  final List<String> logs;
  final String? error;
  final bool skipped;
  final bool stop;
  final String? nextRequest;

  const ExecResult({
    this.request,
    this.response,
    this.tests = const [],
    this.logs = const [],
    this.error,
    this.skipped = false,
    this.stop = false,
    this.nextRequest,
  });

  ExecResult copyWith({
    Object? request = _unset,
    Object? response = _unset,
    List<TestResult>? tests,
    List<String>? logs,
    Object? error = _unset,
    bool? skipped,
    bool? stop,
    Object? nextRequest = _unset,
  }) => ExecResult(
    request: identical(request, _unset)
        ? this.request
        : request as PreparedRequest?,
    response: identical(response, _unset)
        ? this.response
        : response as HttpResult?,
    tests: tests ?? this.tests,
    logs: logs ?? this.logs,
    error: identical(error, _unset) ? this.error : error as String?,
    skipped: skipped ?? this.skipped,
    stop: stop ?? this.stop,
    nextRequest: identical(nextRequest, _unset)
        ? this.nextRequest
        : nextRequest as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ExecResult &&
      other.request == request &&
      other.response == response &&
      listEquals(other.tests, tests) &&
      listEquals(other.logs, logs) &&
      other.error == error &&
      other.skipped == skipped &&
      other.stop == stop &&
      other.nextRequest == nextRequest;
  @override
  int get hashCode => Object.hash(
    request,
    response,
    Object.hashAll(tests),
    Object.hashAll(logs),
    error,
    skipped,
    stop,
    nextRequest,
  );
}

/// How the app picks its colours: follow the operating system, or always light / dark.
/// NOTE: clashes with Flutter's `ThemeMode`; import with `hide ThemeMode` from material_ui where both are needed.
enum ThemeMode {
  System('system', 'System'),
  Light('light', 'Light'),
  Dark('dark', 'Dark');

  final String id;
  final String label;
  const ThemeMode(this.id, this.label);

  bool isDark(bool systemIsDark) => switch (this) {
    ThemeMode.System => systemIsDark,
    ThemeMode.Light => false,
    ThemeMode.Dark => true,
  };

  static ThemeMode? of(String? id) {
    for (final e in ThemeMode.values) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// User preferences saved between sessions.
class AppSettings {
  final ThemeMode theme;
  final int timeoutMs;
  final bool followRedirects;
  final int maxRedirects;
  final bool sslVerify;
  final bool proxyEnabled;
  final String proxyHost;
  final int proxyPort;
  final String userAgent;
  final bool verticalLayout;
  final int fontSize;
  final bool autoSave;

  const AppSettings({
    this.theme = ThemeMode.System,
    this.timeoutMs = 30000,
    this.followRedirects = true,
    this.maxRedirects = 10,
    this.sslVerify = true,
    this.proxyEnabled = false,
    this.proxyHost = '',
    this.proxyPort = 8080,
    this.userAgent = 'OpenRest/1.0',
    this.verticalLayout = true,
    this.fontSize = 13,
    this.autoSave = false,
  });

  AppSettings copyWith({
    ThemeMode? theme,
    int? timeoutMs,
    bool? followRedirects,
    int? maxRedirects,
    bool? sslVerify,
    bool? proxyEnabled,
    String? proxyHost,
    int? proxyPort,
    String? userAgent,
    bool? verticalLayout,
    int? fontSize,
    bool? autoSave,
  }) => AppSettings(
    theme: theme ?? this.theme,
    timeoutMs: timeoutMs ?? this.timeoutMs,
    followRedirects: followRedirects ?? this.followRedirects,
    maxRedirects: maxRedirects ?? this.maxRedirects,
    sslVerify: sslVerify ?? this.sslVerify,
    proxyEnabled: proxyEnabled ?? this.proxyEnabled,
    proxyHost: proxyHost ?? this.proxyHost,
    proxyPort: proxyPort ?? this.proxyPort,
    userAgent: userAgent ?? this.userAgent,
    verticalLayout: verticalLayout ?? this.verticalLayout,
    fontSize: fontSize ?? this.fontSize,
    autoSave: autoSave ?? this.autoSave,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.timeoutMs == timeoutMs &&
      other.followRedirects == followRedirects &&
      other.maxRedirects == maxRedirects &&
      other.sslVerify == sslVerify &&
      other.proxyEnabled == proxyEnabled &&
      other.proxyHost == proxyHost &&
      other.proxyPort == proxyPort &&
      other.userAgent == userAgent &&
      other.verticalLayout == verticalLayout &&
      other.fontSize == fontSize &&
      other.autoSave == autoSave;

  @override
  int get hashCode => Object.hash(
    theme,
    timeoutMs,
    followRedirects,
    maxRedirects,
    sslVerify,
    proxyEnabled,
    proxyHost,
    proxyPort,
    userAgent,
    verticalLayout,
    fontSize,
    autoSave,
  );
}
