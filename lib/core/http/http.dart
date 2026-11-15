import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:open_rest/core/model/model.dart';
import 'package:path/path.dart' as p;

/// Variable interpolation and URL encoding helpers.
class Variables {
  Variables._();

  static final RegExp _re = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');
  static final Random _rnd = Random();

  static String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static T _pick<T>(List<T> l) => l[_rnd.nextInt(l.length)];

  static String? dynamic(String name) {
    switch (name) {
      case r'$guid':
      case r'$randomUUID':
        return _uuid();
      case r'$timestamp':
        return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      case r'$isoTimestamp':
        return DateTime.now().toUtc().toIso8601String();
      case r'$randomInt':
        return _rnd.nextInt(1000).toString();
      case r'$randomBoolean':
        return _rnd.nextBool().toString();
      case r'$randomEmail':
        return 'user${_rnd.nextInt(100000)}@example.com';
      case r'$randomFirstName':
        return _pick(['Ava', 'Liam', 'Noah', 'Mia', 'Zoe', 'Ethan']);
      case r'$randomLastName':
        return _pick(['Smith', 'Jones', 'Brown', 'Lee', 'Khan', 'Patel']);
    }
    return null;
  }

  static String interpolate(String text, String? Function(String) lookup) {
    var cur = text;
    for (var i = 0; i < 4; i++) {
      if (!cur.contains('{{')) return cur;
      final next = cur.replaceAllMapped(_re, (m) {
        final n = m.group(1)!;
        return lookup(n) ?? dynamic(n) ?? m.group(0)!;
      });
      if (next == cur) return cur;
      cur = next;
    }
    return cur;
  }

  static List<String> names(String text) =>
      _re.allMatches(text).map((m) => m.group(1)!).toList();
}

/// A cookie held by the session jar (shown in the Cookies dialog).
class StoredCookie {
  final String name;
  String value;
  final String? domain;
  final String? path;
  final bool secure;
  final bool isHttpOnly;
  final bool hostOnly;
  final DateTime? expires;

  StoredCookie(
    this.name,
    this.value,
    this.domain,
    this.path,
    this.secure,
    this.isHttpOnly,
    this.hostOnly,
    this.expires,
  );
}

/// In-memory cookie store that accepts every cookie.
class CookieJar {
  final List<StoredCookie> cookies = [];

  void removeAll() => cookies.clear();

  /// Removes one stored cookie (matched by identity).
  void removeCookie(StoredCookie c) => cookies.remove(c);

  /// Removes every cookie stored for [domain].
  void removeDomain(String domain) =>
      cookies.removeWhere((c) => (c.domain ?? '') == domain);

  void store(Uri uri, List<String> setCookieValues) {
    for (final raw in setCookieValues) {
      try {
        final c = Cookie.fromSetCookieValue(raw);
        final host = uri.host.toLowerCase();
        final hostOnly = c.domain == null;
        final domain = (c.domain ?? host).toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        var path = c.path;
        if (path == null || !path.startsWith('/')) {
          final up = uri.path;
          final i = up.lastIndexOf('/');
          path = (i <= 0) ? '/' : up.substring(0, i);
        }
        cookies.removeWhere(
          (x) => x.name == c.name && x.domain == domain && x.path == path,
        );
        final expired =
            (c.maxAge != null && c.maxAge! <= 0) ||
            (c.expires != null && c.expires!.isBefore(DateTime.now()));
        if (expired) continue;
        DateTime? exp = c.expires;
        if (c.maxAge != null) {
          exp = DateTime.now().add(Duration(seconds: c.maxAge!));
        }
        cookies.add(
          StoredCookie(
            c.name,
            c.value,
            domain,
            path,
            c.secure,
            c.httpOnly,
            hostOnly,
            exp,
          ),
        );
      } catch (_) {}
    }
  }

  String? headerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final now = DateTime.now();
    cookies.removeWhere((c) => c.expires != null && c.expires!.isBefore(now));
    final out = <String>[];
    for (final c in cookies) {
      final d = c.domain ?? '';
      final domOk = c.hostOnly
          ? host == d
          : (host == d || host.endsWith('.$d'));
      if (!domOk) continue;
      final cp = c.path ?? '/';
      final pathOk =
          path == cp ||
          (path.startsWith(cp) && (cp.endsWith('/') || path[cp.length] == '/'));
      if (!pathOk) continue;
      if (c.secure && uri.scheme != 'https') continue;
      out.add('${c.name}=${c.value}');
    }
    return out.isEmpty ? null : out.join('; ');
  }
}

/// Sends HTTP requests and follows redirects.
class HttpExecutor {
  HttpExecutor._();

  static final CookieJar cookies = CookieJar();

  static String? _cachedKey;
  static HttpClient? _cachedClient;

  static HttpClient _client(AppSettings s) {
    final key =
        '${s.followRedirects}|${s.sslVerify}|${s.proxyEnabled}|${s.proxyHost}|${s.proxyPort}';
    if (_cachedKey == key && _cachedClient != null) return _cachedClient!;
    _cachedClient?.close();
    final c = HttpClient()
      ..autoUncompress = false
      ..userAgent = null
      ..connectionTimeout = const Duration(seconds: 30);
    if (!s.sslVerify) c.badCertificateCallback = (cert, host, port) => true;
    if (s.proxyEnabled && s.proxyHost.trim().isNotEmpty) {
      final proxy = 'PROXY ${s.proxyHost}:${s.proxyPort}';
      c.findProxy = (uri) => proxy;
    } else {
      c.findProxy = (uri) => 'DIRECT';
    }
    _cachedKey = key;
    _cachedClient = c;
    return c;
  }

  static const String _unreserved =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_';

  /// URL-encodes as UTF-8: space becomes '+'.
  static String _javaEncode(String s) {
    final sb = StringBuffer();
    for (final b in utf8.encode(s)) {
      final ch = String.fromCharCode(b);
      if (b < 128 && _unreserved.contains(ch)) {
        sb.write(ch);
      } else if (b == 0x20) {
        sb.write('+');
      } else {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return sb.toString();
  }

  static String urlEncode(String s) => _javaEncode(s).replaceAll('+', '%20');

  static String formEncode(List<(String, String)> fields) =>
      fields.map((f) => '${_javaEncode(f.$1)}=${_javaEncode(f.$2)}').join('&');

  static const Map<String, String> _mime = {
    'txt': 'text/plain',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'csv': 'text/csv',
    'xml': 'application/xml',
    'json': 'application/json',
    'js': 'text/javascript',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'yaml': 'application/yaml',
    'yml': 'application/yaml',
    'md': 'text/markdown',
  };

  static String? _probeContentType(String path) {
    final e = p.extension(path).toLowerCase().replaceFirst('.', '');
    return _mime[e];
  }

  /// Builds the request body bytes (null = no body) and adjusts [headers] (Content-Type).
  static Future<Uint8List?> buildBody(
    Body body,
    List<(String, String)> headers,
  ) async {
    bool hasCt() => headers.any((h) => h.$1.toLowerCase() == 'content-type');
    void setCt(String ct) {
      if (!hasCt()) headers.add(('Content-Type', ct));
    }

    switch (body) {
      case BodyNone():
        return null;
      case BodyRaw():
        if (body.contentType.isNotEmpty) setCt(body.contentType);
        return Uint8List.fromList(utf8.encode(body.text));
      case BodyForm():
        setCt('application/x-www-form-urlencoded');
        return Uint8List.fromList(utf8.encode(formEncode(body.fields)));
      case BodyFileBody():
        setCt('application/octet-stream');
        return await File(body.path).readAsBytes();
      case BodyMultipart():
        final boundary = '----OpenRestBoundary${_hex(16)}';
        headers.removeWhere((h) => h.$1.toLowerCase() == 'content-type');
        headers.add((
          'Content-Type',
          'multipart/form-data; boundary=$boundary',
        ));
        final out = BytesBuilder();
        void w(String s) => out.add(utf8.encode(s));
        for (final part in body.parts) {
          w('--$boundary\r\n');
          if (part.isFile) {
            final fileName = p.basename(part.value);
            w(
              'Content-Disposition: form-data; name="${part.name}"; filename="$fileName"\r\n',
            );
            w(
              'Content-Type: ${part.contentType.isEmpty ? (_probeContentType(part.value) ?? 'application/octet-stream') : part.contentType}\r\n\r\n',
            );
            out.add(await File(part.value).readAsBytes());
          } else {
            w('Content-Disposition: form-data; name="${part.name}"\r\n');
            if (part.contentType.isNotEmpty) {
              w('Content-Type: ${part.contentType}\r\n');
            }
            w('\r\n');
            w(part.value);
          }
          w('\r\n');
        }
        w('--$boundary--\r\n');
        return out.toBytes();
    }
  }

  static String _hex(int bytes) {
    final r = Random.secure();
    return List.generate(
      bytes,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<HttpResult> execute(
    PreparedRequest req,
    AppSettings settings,
  ) async {
    final sw = Stopwatch()..start();
    int elapsed() => sw.elapsedMilliseconds;
    try {
      final headers = List<(String, String)>.of(req.headers);
      final payload = await buildBody(req.body, headers);
      Uri uri;
      try {
        uri = Uri.parse(req.url.trim());
      } catch (e) {
        return HttpResult(
          error: 'Invalid URL: ${e is FormatException ? e.message : e}',
          timeMs: elapsed(),
        );
      }
      if (uri.scheme.isEmpty || uri.host.isEmpty) {
        return HttpResult(
          error: 'Invalid URL: scheme and host are required (e.g. https://example.com)',
          timeMs: elapsed(),
        );
      }
      final timeout = req.timeoutMs > 0 ? req.timeoutMs : settings.timeoutMs;
      final future = _send(req, settings, uri, headers, payload, sw);
      final res = timeout > 0
          ? await future.timeout(Duration(milliseconds: timeout))
          : await future;
      return res;
    } on TimeoutException {
      return HttpResult(error: 'Request timed out', timeMs: elapsed());
    } on SocketException catch (e) {
      return HttpResult(
        error: 'Could not connect: ${e.osError?.message ?? e.message}',
        timeMs: elapsed(),
      );
    } on FileSystemException catch (e) {
      // Missing-file and access-denied errors carry only the path as message.
      final code = e.osError?.errorCode;
      final t = code == 2
          ? 'NoSuchFileException'
          : (code == 13 ? 'AccessDeniedException' : 'FileSystemException');
      return HttpResult(error: '$t: ${e.path ?? e.message}', timeMs: elapsed());
    } on HttpException catch (e) {
      return HttpResult(
        error: 'HttpException: ${e.message}',
        timeMs: elapsed(),
      );
    } catch (e) {
      final t = e.runtimeType.toString();
      final msg = e is FormatException
          ? e.message
          : (e is Error || e is Exception
                ? e.toString().replaceFirst(
                    RegExp(r'^[A-Za-z]+(Exception|Error): '),
                    '',
                  )
                : e.toString());
      return HttpResult(error: '$t: $msg', timeMs: elapsed());
    }
  }

  static Future<HttpResult> _send(
    PreparedRequest req,
    AppSettings settings,
    Uri uri0,
    List<(String, String)> headers0,
    Uint8List? payload0,
    Stopwatch sw,
  ) async {
    final client = _client(settings);
    var method = req.method.toUpperCase();
    var uri = uri0;
    var headers = headers0;
    var payload = req.body is BodyNone ? null : payload0;
    final maxHops = settings.maxRedirects > 0 ? settings.maxRedirects : 10;
    for (var hop = 0; ; hop++) {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      request.persistentConnection = true;
      final names = headers.map((h) => h.$1.toLowerCase()).toSet();
      for (final (k, v) in headers) {
        if (k.trim().isEmpty || k.toLowerCase() == 'content-length') continue;
        try {
          request.headers.add(k, v, preserveHeaderCase: true);
        } catch (_) {}
      }
      if (!names.contains('user-agent')) {
        request.headers.set('User-Agent', settings.userAgent);
      }
      if (!names.contains('accept')) request.headers.set('Accept', '*/*');
      if (!names.contains('accept-encoding')) {
        request.headers.set('Accept-Encoding', 'gzip, deflate');
      }
      final jar = cookies.headerFor(uri);
      if (jar != null) {
        final existing = request.headers.value('cookie');
        request.headers.set(
          'Cookie',
          existing == null ? jar : '$existing; $jar',
        );
      }
      if (payload != null) {
        request.contentLength = payload.length;
        request.add(payload);
      }
      final response = await request.close();
      final setCookies = response.headers['set-cookie'];
      if (setCookies != null) cookies.store(uri, setCookies);
      final bb = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bb.add(chunk);
      }
      final code = response.statusCode;
      final location = response.headers.value('location');
      if (settings.followRedirects &&
          hop < maxHops &&
          location != null &&
          const [301, 302, 303, 307, 308].contains(code)) {
        Uri next;
        try {
          next = uri.resolve(location);
        } catch (_) {
          next = uri;
        }
        // https -> http redirects are not followed
        if (!(uri.scheme == 'https' && next.scheme == 'http')) {
          final toGet = code == 303
              ? method != 'HEAD'
              : ((code == 301 || code == 302) && method == 'POST');
          if (toGet) {
            method = 'GET';
            payload = null;
            headers = headers.where((h) {
              final k = h.$1.toLowerCase();
              return k != 'content-type' && k != 'content-length';
            }).toList();
          }
          uri = next;
          continue;
        }
      }
      var data = bb.takeBytes();
      final enc = (response.headers.value('content-encoding') ?? '')
          .toLowerCase();
      try {
        if (enc.contains('gzip')) {
          data = Uint8List.fromList(gzip.decode(data));
        } else if (enc.contains('deflate')) {
          try {
            data = Uint8List.fromList(zlib.decode(data));
          } catch (_) {
            data = Uint8List.fromList(ZLibCodec(raw: true).decode(data));
          }
        }
      } catch (_) {}
      final hs = <(String, String)>[];
      response.headers.forEach((k, vs) {
        for (final v in vs) {
          hs.add((k, v));
        }
      });
      return HttpResult(
        status: code,
        statusText: statusText(code),
        headers: hs,
        body: data,
        timeMs: sw.elapsedMilliseconds,
        finalUrl: uri.toString(),
      );
    }
  }

  static String statusText(int code) {
    switch (code) {
      case 100:
        return 'Continue';
      case 101:
        return 'Switching Protocols';
      case 200:
        return 'OK';
      case 201:
        return 'Created';
      case 202:
        return 'Accepted';
      case 203:
        return 'Non-Authoritative Information';
      case 204:
        return 'No Content';
      case 205:
        return 'Reset Content';
      case 206:
        return 'Partial Content';
      case 300:
        return 'Multiple Choices';
      case 301:
        return 'Moved Permanently';
      case 302:
        return 'Found';
      case 303:
        return 'See Other';
      case 304:
        return 'Not Modified';
      case 307:
        return 'Temporary Redirect';
      case 308:
        return 'Permanent Redirect';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 402:
        return 'Payment Required';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 405:
        return 'Method Not Allowed';
      case 406:
        return 'Not Acceptable';
      case 408:
        return 'Request Timeout';
      case 409:
        return 'Conflict';
      case 410:
        return 'Gone';
      case 413:
        return 'Payload Too Large';
      case 415:
        return 'Unsupported Media Type';
      case 418:
        return "I'm a teapot";
      case 422:
        return 'Unprocessable Entity';
      case 429:
        return 'Too Many Requests';
      case 500:
        return 'Internal Server Error';
      case 501:
        return 'Not Implemented';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      case 504:
        return 'Gateway Timeout';
      default:
        return '';
    }
  }
}
