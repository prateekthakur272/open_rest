import 'dart:convert';
import 'dart:io';

import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';

/// Where an automatically added header comes from, shown next to it.
abstract final class HeaderSource {
  static const String auth = 'Auth';
  static const String body = 'Body';
  static const String client = 'Client';
  static const String cookies = 'Cookie jar';
  static const String websocket = 'WebSocket';
}

/// A header that is sent although it is not one of the request's own (or inherited) headers.
class GeneratedHeader {
  const GeneratedHeader(this.name, this.value, this.source);
  final String name;
  final String value;
  final String source;

  @override
  String toString() => '$name: $value ($source)';
}

/// Shown instead of a value that only exists once the request is actually sent.
const String calculatedWhenSent = '<calculated when sent>';

/// The headers the app's HTTP client (or WebSocket handshake) adds on its own, in the order they are listed.
///
/// [present] holds the lower-case names of the headers the request already has (its own, inherited and
/// auth ones): a header the user set is never replaced, so it is not listed again. Nothing is sent or read
/// from the network; values that only exist at send time say so.
List<GeneratedHeader> clientHeaders({
  required Uri? uri,
  required Body body,
  required Set<String> present,
  required AppSettings settings,
  String? cookie,
  bool websocket = false,
  List<String> protocols = const [],
}) {
  final out = <GeneratedHeader>[];
  void add(String name, String value, String source) {
    if (!present.contains(name.toLowerCase())) {
      out.add(GeneratedHeader(name, value, source));
    }
  }

  if (uri != null && uri.host.isNotEmpty) {
    final defaultPort = switch (uri.scheme) {
      'https' || 'wss' => 443,
      _ => 80,
    };
    add(
      'Host',
      uri.hasPort && uri.port != defaultPort
          ? '${uri.host}:${uri.port}'
          : uri.host,
      HeaderSource.client,
    );
  }
  add('User-Agent', settings.effectiveUserAgent, HeaderSource.client);

  if (websocket) {
    add('Upgrade', 'websocket', HeaderSource.websocket);
    add('Connection', 'Upgrade', HeaderSource.websocket);
    add('Sec-WebSocket-Version', '13', HeaderSource.websocket);
    add(
      'Sec-WebSocket-Key',
      '<random, generated when sent>',
      HeaderSource.websocket,
    );
    if (protocols.isNotEmpty) {
      add(
        'Sec-WebSocket-Protocol',
        protocols.join(', '),
        HeaderSource.websocket,
      );
    }
  } else {
    add('Accept', '*/*', HeaderSource.client);
    add('Accept-Encoding', 'gzip, deflate', HeaderSource.client);
  }

  if (cookie != null && cookie.isNotEmpty) {
    add('Cookie', cookie, HeaderSource.cookies);
  }

  if (!websocket) {
    switch (body) {
      case BodyNone():
        break;
      case BodyRaw():
        if (body.contentType.isNotEmpty) {
          add('Content-Type', body.contentType, HeaderSource.body);
        }
        add(
          'Content-Length',
          '${utf8.encode(body.text).length}',
          HeaderSource.body,
        );
      case BodyForm():
        add(
          'Content-Type',
          'application/x-www-form-urlencoded',
          HeaderSource.body,
        );
        add(
          'Content-Length',
          '${utf8.encode(HttpExecutor.formEncode(body.fields)).length}',
          HeaderSource.body,
        );
      case BodyFileBody():
        add('Content-Type', 'application/octet-stream', HeaderSource.body);
        var size = calculatedWhenSent;
        try {
          size = '${File(body.path).lengthSync()}';
        } catch (_) {}
        add('Content-Length', size, HeaderSource.body);
      case BodyMultipart():
        add(
          'Content-Type',
          'multipart/form-data; boundary=<generated when sent>',
          HeaderSource.body,
        );
        add('Content-Length', calculatedWhenSent, HeaderSource.body);
    }
  }
  return out;
}
