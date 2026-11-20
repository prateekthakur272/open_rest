import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';

/// Generates code snippets for a request in many languages.
class CodeGen {
  CodeGen._();

  static const List<String> languages = [
    'cURL',
    'JavaScript (fetch)',
    'JavaScript (axios)',
    'Node.js (http)',
    'Python (requests)',
    'Java (HttpClient)',
    'Kotlin (OkHttp)',
    'Go (net/http)',
    'PHP (cURL)',
    'C# (HttpClient)',
    'Ruby (Net::HTTP)',
    'Swift (URLSession)',
    'Rust (reqwest)',
    'Dart (http)',
    'PowerShell',
    'HTTPie',
    'wget',
  ];

  /// Syntax-highlighter language id for a generator name.
  static String langId(String name) {
    if (name.startsWith('JavaScript') || name.startsWith('Node')) return 'js';
    if (name.startsWith('Python')) return 'py';
    if (name.startsWith('Java ') || name.startsWith('Java(')) return 'java';
    if (name.startsWith('Kotlin')) return 'kt';
    if (name.startsWith('Go')) return 'go';
    if (name.startsWith('PHP')) return 'php';
    if (name.startsWith('C#')) return 'cs';
    if (name.startsWith('Ruby')) return 'rb';
    if (name.startsWith('Swift')) return 'swift';
    if (name.startsWith('Rust')) return 'rs';
    if (name.startsWith('Dart')) return 'dart';
    if (name.startsWith('PowerShell')) return 'ps';
    return 'sh';
  }

  static String _q(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t')}"';
  static String _sh(String s) => "'${s.replaceAll("'", "'\\''")}'";

  static List<(String, String)> _headersWithCt(PreparedRequest r) {
    final h = List<(String, String)>.of(r.headers);
    bool has() => h.any((x) => x.$1.toLowerCase() == 'content-type');
    final b = r.body;
    if (b is BodyRaw) {
      if (!has() && b.contentType.isNotEmpty) {
        h.add(('Content-Type', b.contentType));
      }
    } else if (b is BodyForm) {
      if (!has()) h.add(('Content-Type', 'application/x-www-form-urlencoded'));
    }
    return h;
  }

  static String? _rawBody(PreparedRequest r) {
    final b = r.body;
    if (b is BodyRaw) return b.text;
    if (b is BodyForm) return HttpExecutor.formEncode(b.fields);
    return null;
  }

  static String _ctOf(List<(String, String)> h, String dflt) {
    for (final x in h) {
      if (x.$1.toLowerCase() == 'content-type') return x.$2;
    }
    return dflt;
  }

  static String _dollar(String s) => s.replaceAll(r'$', r'\$');

  /// cURL command that opens a WebSocket (curl 7.86+ speaks `ws://` and `wss://`).
  ///
  /// The sub-[protocols] go in the `Sec-WebSocket-Protocol` header and the optional [message] is sent after the
  /// handshake; `--no-buffer` prints incoming frames as they arrive.
  static String curlWebSocket(
    PreparedRequest r, {
    List<String> protocols = const [],
    String message = '',
  }) {
    final sb = StringBuffer('curl --no-buffer ${_sh(r.url)}');
    final h = r.headers
        .where((x) => x.$1.toLowerCase() != 'sec-websocket-protocol')
        .toList();
    if (protocols.isNotEmpty) {
      h.add(('Sec-WebSocket-Protocol', protocols.join(', ')));
    }
    for (final x in h) {
      sb.write(' \\\n  -H ${_sh('${x.$1}: ${x.$2}')}');
    }
    final tls = r.tls;
    if (tls != null && tls.mode == TlsMode.custom) {
      final pfx = tls.format == TlsFormat.pfx;
      if (pfx && tls.pfxPath.isNotEmpty) {
        sb.write(' \\\n  --cert ${_sh(tls.pfxPath)} --cert-type P12');
      } else if (!pfx && tls.certPath.isNotEmpty) {
        sb.write(' \\\n  --cert ${_sh(tls.certPath)}');
        if (tls.keyPath.isNotEmpty) sb.write(' --key ${_sh(tls.keyPath)}');
      }
      if (tls.caPath.isNotEmpty) {
        sb.write(' \\\n  --cacert ${_sh(tls.caPath)}');
      }
    }
    if (message.isNotEmpty) sb.write(' \\\n  --data-raw ${_sh(message)}');
    return sb.toString();
  }

  static String generate(String lang, PreparedRequest r) {
    final h = _headersWithCt(r);
    final body = _rawBody(r);
    final rb = r.body;
    final mp = rb is BodyMultipart ? rb.parts : null;
    final file = rb is BodyFileBody ? rb.path : null;
    final m = r.method;
    final sb = StringBuffer();
    String hdrs(String Function((String, String)) f, String sep) =>
        h.map(f).join(sep);
    switch (lang) {
      case 'cURL':
        sb.write('curl');
        if (m != 'GET') sb.write(' -X $m');
        sb.write(' ');
        sb.write(_sh(r.url));
        for (final x in h) {
          sb.write(' \\\n  -H ');
          sb.write(_sh('${x.$1}: ${x.$2}'));
        }
        final tls = r.tls;
        if (tls != null && tls.mode == TlsMode.custom) {
          final pfx = tls.format == TlsFormat.pfx;
          final hasPass = tls.passphrase.isNotEmpty;
          if (pfx && tls.pfxPath.isNotEmpty) {
            sb.write(' \\\n  --cert ');
            sb.write(
              _sh(hasPass ? '${tls.pfxPath}:<passphrase>' : tls.pfxPath),
            );
            sb.write(' --cert-type P12');
          } else if (!pfx && tls.certPath.isNotEmpty) {
            sb.write(' \\\n  --cert ${_sh(tls.certPath)}');
            if (tls.keyPath.isNotEmpty) sb.write(' --key ${_sh(tls.keyPath)}');
            if (hasPass) sb.write(" --pass '<passphrase>'");
          }
          if (tls.caPath.isNotEmpty) {
            sb.write(' \\\n  --cacert ${_sh(tls.caPath)}');
          }
        }
        if (body != null) {
          sb.write(' \\\n  --data-raw ');
          sb.write(_sh(body));
        }
        if (mp != null) {
          for (final x in mp) {
            sb.write(' \\\n  -F ');
            sb.write(
              _sh(x.isFile ? '${x.name}=@${x.value}' : '${x.name}=${x.value}'),
            );
          }
        }
        if (file != null) {
          sb.write(' \\\n  --data-binary ');
          sb.write(_sh('@$file'));
        }
      case 'wget':
        sb.write('wget --no-check-certificate --quiet \\\n  --method $m \\\n');
        for (final x in h) {
          sb.write('  --header ');
          sb.write(_sh('${x.$1}: ${x.$2}'));
          sb.write(' \\\n');
        }
        if (body != null) {
          sb.write('  --body-data ');
          sb.write(_sh(body));
          sb.write(' \\\n');
        }
        sb.write('  ');
        sb.write(_sh(r.url));
      case 'HTTPie':
        sb.write('http ');
        if (body != null && r.body is BodyRaw) {
          sb.write('--raw ');
          sb.write(_sh(body));
          sb.write(' ');
        }
        sb.write('$m ');
        sb.write(_sh(r.url));
        for (final x in h) {
          sb.write(' \\\n  ');
          sb.write(_sh('${x.$1}:${x.$2}'));
        }
      case 'JavaScript (fetch)':
        sb.write('const options = {\n  method: ${_q(m)},\n');
        if (h.isNotEmpty) {
          sb.write('  headers: {\n');
          sb.write(hdrs((x) => '    ${_q(x.$1)}: ${_q(x.$2)}', ',\n'));
          sb.write('\n  },\n');
        }
        if (body != null) sb.write('  body: ${_q(body)},\n');
        if (mp != null) {
          sb.write('  body: (() => {\n    const f = new FormData();\n');
          for (final x in mp) {
            sb.write(
              x.isFile
                  ? '    f.append(${_q(x.name)}, /* file: ${x.value} */ new Blob([]));\n'
                  : '    f.append(${_q(x.name)}, ${_q(x.value)});\n',
            );
          }
          sb.write('    return f;\n  })(),\n');
        }
        sb.write(
          '};\n\nfetch(${_q(r.url)}, options)\n  .then((res) => res.text())\n  .then((data) => console.log(data))\n  .catch((err) => console.error(err));',
        );
      case 'JavaScript (axios)':
        sb.write(
          "const axios = require('axios');\n\nconst config = {\n  method: ${_q(m.toLowerCase())},\n  url: ${_q(r.url)},\n",
        );
        if (h.isNotEmpty) {
          sb.write('  headers: {\n');
          sb.write(hdrs((x) => '    ${_q(x.$1)}: ${_q(x.$2)}', ',\n'));
          sb.write('\n  },\n');
        }
        if (body != null) sb.write('  data: ${_q(body)},\n');
        sb.write(
          '};\n\naxios(config)\n  .then((response) => console.log(response.data))\n  .catch((error) => console.error(error));',
        );
      case 'Node.js (http)':
        // URLs with spaces or these characters are not parsed (no host, path "/").
        final u = RegExp(r'[ "<>\\^`{|}]').hasMatch(r.url)
            ? null
            : Uri.tryParse(r.url);
        final https = u?.scheme == 'https';
        final mod = https ? 'https' : 'http';
        sb.write("const $mod = require('$mod');\n\n");
        sb.write(
          'const options = {\n  method: ${_q(m)},\n  hostname: ${_q(u?.host ?? '')},\n',
        );
        if (u != null && u.hasPort && u.port > 0) {
          sb.write('  port: ${u.port},\n');
        }
        sb.write(
          '  path: ${_q((u == null || u.path.isEmpty ? '/' : u.path) + (u != null && u.hasQuery ? '?${u.query}' : ''))},\n',
        );
        sb.write('  headers: {\n');
        sb.write(hdrs((x) => '    ${_q(x.$1)}: ${_q(x.$2)}', ',\n'));
        sb.write('\n  },\n};\n\n');
        sb.write(
          "const req = $mod.request(options, (res) => {\n  const chunks = [];\n  res.on('data', (c) => chunks.push(c));\n  res.on('end', () => console.log(Buffer.concat(chunks).toString()));\n});\n\n",
        );
        if (body != null) sb.write('req.write(${_q(body)});\n');
        sb.write('req.end();');
      case 'Python (requests)':
        sb.write('import requests\n\nurl = ${_q(r.url)}\n');
        if (h.isNotEmpty) {
          sb.write('headers = {\n');
          sb.write(hdrs((x) => '    ${_q(x.$1)}: ${_q(x.$2)}', ',\n'));
          sb.write(',\n}\n');
        } else {
          sb.write('headers = {}\n');
        }
        if (body != null) sb.write('payload = ${_q(body)}\n');
        if (mp != null) {
          sb.write('files = [\n');
          sb.write(
            mp
                .where((x) => x.isFile)
                .map((x) => "    (${_q(x.name)}, open(${_q(x.value)}, 'rb'))")
                .join(',\n'),
          );
          sb.write('\n]\n');
          sb.write('data = {\n');
          sb.write(
            mp
                .where((x) => !x.isFile)
                .map((x) => '    ${_q(x.name)}: ${_q(x.value)}')
                .join(',\n'),
          );
          sb.write('\n}\n');
        }
        sb.write(
          '\nresponse = requests.request(${_q(m)}, url, headers=headers',
        );
        if (body != null) sb.write(', data=payload');
        if (mp != null) sb.write(', data=data, files=files');
        if (file != null) sb.write(", data=open(${_q(file)}, 'rb')");
        sb.write(')\nprint(response.text)');
      case 'Java (HttpClient)':
        sb.write(
          'import java.net.URI;\nimport java.net.http.*;\n\nHttpClient client = HttpClient.newHttpClient();\nHttpRequest request = HttpRequest.newBuilder()\n    .uri(URI.create(${_q(r.url)}))\n',
        );
        for (final x in h) {
          sb.write('    .header(${_q(x.$1)}, ${_q(x.$2)})\n');
        }
        sb.write(
          '    .method(${_q(m)}, ${body != null ? 'HttpRequest.BodyPublishers.ofString(${_q(body)})' : 'HttpRequest.BodyPublishers.noBody()'})\n    .build();\n',
        );
        sb.write(
          'HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());\nSystem.out.println(response.body());',
        );
      case 'Kotlin (OkHttp)':
        sb.write(
          'import okhttp3.*\nimport okhttp3.MediaType.Companion.toMediaType\nimport okhttp3.RequestBody.Companion.toRequestBody\n\nval client = OkHttpClient()\n',
        );
        final ct = _ctOf(h, 'text/plain');
        sb.write('val request = Request.Builder()\n    .url(${_q(r.url)})\n');
        for (final x in h) {
          sb.write('    .addHeader(${_q(x.$1)}, ${_q(x.$2)})\n');
        }
        sb.write(
          '    .method(${_q(m)}, ${body != null ? '${_q(body)}.toRequestBody(${_q(ct)}.toMediaType())' : (const ['POST', 'PUT', 'PATCH'].contains(m) ? '"".toRequestBody(null)' : 'null')})\n    .build()\n',
        );
        sb.write(
          'client.newCall(request).execute().use { println(it.body?.string()) }',
        );
      case 'Go (net/http)':
        sb.write(
          'package main\n\nimport (\n\t"fmt"\n\t"io"\n\t"net/http"\n${body != null ? '\t"strings"\n' : ''})\n\nfunc main() {\n',
        );
        sb.write('\tclient := &http.Client{}\n');
        if (body != null) {
          sb.write(
            '\tpayload := strings.NewReader(${_q(body)})\n\treq, err := http.NewRequest(${_q(m)}, ${_q(r.url)}, payload)\n',
          );
        } else {
          sb.write(
            '\treq, err := http.NewRequest(${_q(m)}, ${_q(r.url)}, nil)\n',
          );
        }
        sb.write('\tif err != nil {\n\t\tpanic(err)\n\t}\n');
        for (final x in h) {
          sb.write('\treq.Header.Add(${_q(x.$1)}, ${_q(x.$2)})\n');
        }
        sb.write(
          '\tres, err := client.Do(req)\n\tif err != nil {\n\t\tpanic(err)\n\t}\n\tdefer res.Body.Close()\n\tb, _ := io.ReadAll(res.Body)\n\tfmt.Println(string(b))\n}',
        );
      case 'PHP (cURL)':
        sb.write(
          '<?php\n\n\$curl = curl_init();\ncurl_setopt_array(\$curl, [\n  CURLOPT_URL => ${_dollar(_q(r.url))},\n  CURLOPT_RETURNTRANSFER => true,\n  CURLOPT_CUSTOMREQUEST => ${_q(m)},\n',
        );
        if (body != null) {
          sb.write('  CURLOPT_POSTFIELDS => ${_dollar(_q(body))},\n');
        }
        if (h.isNotEmpty) {
          sb.write('  CURLOPT_HTTPHEADER => [\n');
          sb.write(
            hdrs((x) => '    ${_dollar(_q('${x.$1}: ${x.$2}'))}', ',\n'),
          );
          sb.write('\n  ],\n');
        }
        sb.write(
          ']);\n\$response = curl_exec(\$curl);\ncurl_close(\$curl);\necho \$response;',
        );
      case 'C# (HttpClient)':
        sb.write(
          'using System.Net.Http;\n\nvar client = new HttpClient();\nvar request = new HttpRequestMessage(new HttpMethod(${_q(m)}), ${_q(r.url)});\n',
        );
        for (final x in h.where((x) => x.$1.toLowerCase() != 'content-type')) {
          sb.write(
            'request.Headers.TryAddWithoutValidation(${_q(x.$1)}, ${_q(x.$2)});\n',
          );
        }
        if (body != null) {
          final ct = _ctOf(h, 'text/plain');
          sb.write(
            'request.Content = new StringContent(${_q(body)}, System.Text.Encoding.UTF8, ${_q(ct)});\n',
          );
        }
        sb.write(
          'var response = await client.SendAsync(request);\nresponse.EnsureSuccessStatusCode();\nConsole.WriteLine(await response.Content.ReadAsStringAsync());',
        );
      case 'Ruby (Net::HTTP)':
        sb.write(
          "require 'uri'\nrequire 'net/http'\n\nurl = URI(${_q(r.url)})\nhttp = Net::HTTP.new(url.host, url.port)\nhttp.use_ssl = url.scheme == 'https'\n\n",
        );
        final lm = m.toLowerCase();
        sb.write(
          'request = Net::HTTP::${lm.isEmpty ? lm : lm[0].toUpperCase() + lm.substring(1)}.new(url)\n',
        );
        for (final x in h) {
          sb.write('request[${_q(x.$1)}] = ${_q(x.$2)}\n');
        }
        if (body != null) sb.write('request.body = ${_q(body)}\n');
        sb.write('\nresponse = http.request(request)\nputs response.read_body');
      case 'Swift (URLSession)':
        sb.write(
          'import Foundation\n\nvar request = URLRequest(url: URL(string: ${_q(r.url)})!)\nrequest.httpMethod = ${_q(m)}\n',
        );
        for (final x in h) {
          sb.write(
            'request.addValue(${_q(x.$2)}, forHTTPHeaderField: ${_q(x.$1)})\n',
          );
        }
        if (body != null) {
          sb.write('request.httpBody = ${_q(body)}.data(using: .utf8)\n');
        }
        sb.write(
          '\nlet task = URLSession.shared.dataTask(with: request) { data, response, error in\n    if let data = data { print(String(data: data, encoding: .utf8)!) }\n}\ntask.resume()',
        );
      case 'Rust (reqwest)':
        sb.write(
          'let client = reqwest::Client::new();\nlet res = client\n    .request(reqwest::Method::from_bytes(b${_q(m)}).unwrap(), ${_q(r.url)})\n',
        );
        for (final x in h) {
          sb.write('    .header(${_q(x.$1)}, ${_q(x.$2)})\n');
        }
        if (body != null) sb.write('    .body(${_q(body)})\n');
        sb.write(
          '    .send()\n    .await?;\nprintln!("{}", res.text().await?);',
        );
      case 'Dart (http)':
        sb.write(
          "import 'package:http/http.dart' as http;\n\nvoid main() async {\n  final request = http.Request(${_q(m)}, Uri.parse(${_q(r.url)}));\n",
        );
        if (h.isNotEmpty) {
          sb.write('  request.headers.addAll({\n');
          sb.write(hdrs((x) => '    ${_q(x.$1)}: ${_q(x.$2)}', ',\n'));
          sb.write('\n  });\n');
        }
        if (body != null) sb.write('  request.body = ${_q(body)};\n');
        sb.write(
          '  final response = await request.send();\n  print(await response.stream.bytesToString());\n}',
        );
      case 'PowerShell':
        sb.write('\$headers = @{\n');
        sb.write(hdrs((x) => '  ${_q(x.$1)} = ${_q(x.$2)}', '\n'));
        sb.write('\n}\n');
        if (body != null) sb.write('\$body = ${_q(body)}\n');
        sb.write(
          '\$response = Invoke-RestMethod -Uri ${_q(r.url)} -Method $m -Headers \$headers',
        );
        if (body != null) sb.write(' -Body \$body');
      default:
        return '// Unsupported language: $lang';
    }
    return sb.toString();
  }
}
