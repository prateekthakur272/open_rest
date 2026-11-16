import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';

/// Everything needed to open a WebSocket, already resolved (variables, auth, inherited headers).
class WsTarget {
  const WsTarget({
    required this.url,
    this.headers = const [],
    this.protocols = const [],
    this.tls,
    this.timeoutMs = 0,
  });

  /// `ws://` or `wss://` (an `http(s)://` URL is converted).
  final String url;
  final List<(String, String)> headers;
  final List<String> protocols;
  final TlsConfig? tls;
  final int timeoutMs;
}

/// A connect failure with a message fit to show.
class WsConnectException implements Exception {
  const WsConnectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Subprotocols from a comma / space separated field.
List<String> parseProtocols(String text) => [
  for (final p in text.split(RegExp(r'[,\s]+')))
    if (p.trim().isNotEmpty) p.trim(),
];

/// `http(s)` -> `ws(s)`; other schemes are left alone.
String toWsUrl(String url) {
  final u = url.trim();
  if (u.startsWith('https://')) return 'wss://${u.substring(8)}';
  if (u.startsWith('http://')) return 'ws://${u.substring(7)}';
  return u;
}

/// One open WebSocket connection.
class WsConnection {
  WsConnection._(this._socket);

  final WebSocket _socket;

  /// Subprotocol the server picked, if any.
  String? get protocol => _socket.protocol;

  /// Text messages arrive as `String`, binary ones as `Uint8List`.
  Stream<dynamic> get messages => _socket;

  int? get closeCode => _socket.closeCode;
  String? get closeReason => _socket.closeReason;

  void sendText(String text) => _socket.add(text);
  void sendBytes(Uint8List bytes) => _socket.add(bytes);

  Future<void> close([int code = 1000, String? reason]) =>
      _socket.close(code, reason);

  /// Opens a connection through the app's pooled client, so TLS, proxy and certificate settings apply.
  static Future<WsConnection> connect(WsTarget t, AppSettings settings) async {
    final url = toWsUrl(t.url);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'ws' || uri.scheme == 'wss') ||
        uri.host.isEmpty) {
      throw const WsConnectException(
        'Invalid URL: use ws://host/path or wss://host/path',
      );
    }
    final headers = <String, String>{};
    for (final (k, v) in t.headers) {
      final name = k.trim();
      if (name.isEmpty) continue;
      // Handshake headers are owned by the WebSocket implementation.
      final l = name.toLowerCase();
      if (const {
        'upgrade',
        'connection',
        'sec-websocket-key',
        'sec-websocket-version',
        'host',
      }.contains(l)) {
        continue;
      }
      headers[name] = v;
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'cookie')) {
      final jar = HttpExecutor.cookies.headerFor(
        uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
      );
      if (jar != null) headers['Cookie'] = jar;
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] = settings.userAgent;
    }
    final timeout = t.timeoutMs > 0 ? t.timeoutMs : settings.timeoutMs;
    try {
      var future = WebSocket.connect(
        url,
        headers: headers,
        protocols: t.protocols.isEmpty ? null : t.protocols,
        customClient: HttpExecutor.clientFor(settings, t.tls),
      );
      if (timeout > 0) {
        future = future.timeout(Duration(milliseconds: timeout));
      }
      return WsConnection._(await future);
    } on FormatException {
      throw const WsConnectException(
        'Invalid URL: use ws://host/path or wss://host/path',
      );
    } on TimeoutException {
      throw const WsConnectException('Connection timed out');
    } on WebSocketException catch (e) {
      throw WsConnectException(_clean(e.message));
    } on SocketException catch (e) {
      throw WsConnectException(
        'Could not connect: ${e.osError?.message ?? e.message}',
      );
    } on HandshakeException catch (e) {
      throw WsConnectException('TLS handshake failed: ${_clean(e.message)}');
    } on HttpException catch (e) {
      throw WsConnectException(_clean(e.message));
    }
  }

  static String _clean(String m) => m.isEmpty ? 'Connection failed' : m;
}
