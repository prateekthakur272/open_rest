import 'dart:convert';
import 'dart:io';

import 'package:open_rest/core/storage/storage.dart';

/// Points the app data dir at a fresh temp directory.
void useTempHome() {
  AppStore.homeOverride = Directory.systemTemp.createTempSync('orh').path;
}

String tempDir(String prefix) =>
    Directory.systemTemp.createTempSync(prefix).path;

/// Starts a local HTTP server on a free port. [handler] writes the response (and must close it).
Future<HttpServer> startServer(
  Future<void> Function(HttpRequest req) handler,
) async {
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  srv.listen((r) async {
    try {
      await handler(r);
    } catch (_) {
      try {
        await r.response.close();
      } catch (_) {}
    }
  });
  return srv;
}

Future<void> respond(
  HttpRequest r,
  String body, {
  String contentType = 'application/json',
  int status = 200,
  Map<String, String> headers = const {},
}) async {
  final b = utf8.encode(body);
  r.response.statusCode = status;
  r.response.headers.set('Content-Type', contentType);
  headers.forEach((k, v) => r.response.headers.add(k, v));
  r.response.contentLength = b.length;
  r.response.add(b);
  await r.response.close();
}
