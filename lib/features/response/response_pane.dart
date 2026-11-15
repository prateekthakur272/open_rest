// ignore_for_file: non_constant_identifier_names
// ignore_for_file: constant_identifier_names
import 'package:open_rest/components/modifiers.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_view.dart';
import 'package:open_rest/components/diff_view.dart';
import 'package:open_rest/components/syntax_highlight.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/html_preview.dart';
import 'package:open_rest/components/json_tree.dart';
import 'package:open_rest/components/media_preview.dart';
import 'package:open_rest/components/response_controls.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/components/test_results.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/format.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/xml.dart';
import 'package:path/path.dart' as p;

String? _hintFor(String msg) {
  final m = msg.toLowerCase();
  bool c(String s) => m.contains(s.toLowerCase());
  if (c('Could not connect') || c('Connection refused')) {
    return 'Is the server running? Check the host and port, and that the environment is the one you expect.';
  }
  if (c('timed out')) {
    return "The server did not answer in time. Raise the timeout in Preferences or in this request's Settings tab.";
  }
  if (c('PKIX') || c('SSLHandshake') || c('certificate')) {
    return "Self-signed or untrusted certificate? Turn off 'Verify SSL certificates' in Preferences.";
  }
  if (c('Invalid URL')) {
    return 'A URL needs a scheme and host, e.g. https://api.example.com/users. Unresolved {{variables}} also cause this.';
  }
  if (c('UnknownHost') || c('nodename')) {
    return 'The host name could not be resolved. Check for typos, VPN or proxy settings.';
  }
  return null;
}

/// The response half of the request editor.
class ResponsePane extends StatelessWidget {
  const ResponsePane({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final result = tab.viewing >= 0 && tab.viewing < tab.responses.length
        ? tab.responses[tab.viewing]
        : tab.result;
    if (tab.sending) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: pal.accent,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 10),
            T('Sending request…', color: pal.muted),
            const SizedBox(height: 10),
            Btn(
              label: 'Cancel',
              onClick: () => state.cancel(tab),
              danger: true,
              icon: Ic.stop,
            ),
          ],
        ),
      );
    }
    if (result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            T('Response', size: 16, weight: FontWeight.w600, color: pal.muted),
            const SizedBox(height: 6),
            T(
              'Press Send or ⌘/Ctrl + Enter to execute the request',
              color: pal.muted,
              size: 12,
            ),
          ],
        ),
      );
    }
    final resp = result.response;
    if (resp == null || resp.error != null || result.error != null) {
      final msg = result.error ?? resp?.error ?? 'Request did not run';
      final hint = _hintFor(msg);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Chip(result.skipped ? 'SKIPPED' : 'ERROR', color: pal.err),
            T(msg, color: pal.err, mono: true),
            if (hint != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Ico(Ic.bulb, tint: pal.accent, size: 16),
                  Expanded(child: T(hint, color: pal.muted, size: 12)),
                ],
              ),
            if (result.tests.isNotEmpty) TestsList(tests: result.tests),
            if (result.logs.isNotEmpty)
              T(result.logs.join('\n'), mono: true, color: pal.muted),
          ],
        ),
      );
    }
    return _ResponseBody(state: state, tab: tab, result: result, res: resp);
  }
}

class _ResponseBody extends StatelessWidget {
  const _ResponseBody({
    required this.state,
    required this.tab,
    required this.result,
    required this.res,
  });
  final AppState state;
  final RequestTab tab;
  final ExecResult result;
  final HttpResult res;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final passed = result.tests.where((t) => t.passed).length;
    const tabs = [
      'Response',
      'Headers',
      'Cookies',
      'Timeline',
      'Tests',
      'Console',
    ];
    final rs = tab.responses;
    HttpResult? older;
    if (tab.viewing + 1 < rs.length && tab.viewing + 1 >= 0) {
      final o = rs[tab.viewing + 1].response;
      if (o != null && o.error == null) older = o;
    }
    Widget content;
    switch (tab.resTab) {
      case 'Response':
        content = tab.diff && older != null
            ? DiffView(old: _bodyForDiff(older), new_: _bodyForDiff(res))
            : _BodyView(state: state, tab: tab, res: res);
      case 'Headers':
        final sorted = [...res.headers]
          ..sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: ReadOnlyTable(
                rows: [for (final h in sorted) TRow(h.$1, h.$2)],
                keyHint: 'Header',
                valueHint: 'Value',
                title: 'Response Headers',
                onCopy: (v) {
                  Platform.copy(v);
                  state.showToast('Copied');
                },
              ),
            ),
          ],
        );
      case 'Cookies':
        final cookies = res.headers
            .where((h) => h.$1.toLowerCase() == 'set-cookie')
            .map((h) => h.$2)
            .toList();
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  if (cookies.isEmpty)
                    T(
                      'No cookies were set by this response.',
                      color: pal.muted,
                    ),
                  for (final c in cookies)
                    () {
                      final parts = c.split(';').map((s) => s.trim()).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          T(parts.first, mono: true, weight: FontWeight.w600),
                          T(
                            parts.skip(1).join('  •  '),
                            mono: true,
                            color: pal.muted,
                            size: 12,
                          ),
                        ],
                      );
                    }(),
                ],
              ),
            ),
          ],
        );
      case 'Timeline':
        final rq = result.request;
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  if (rq != null) ...[
                    T(
                      '${rq.method} ${rq.url}',
                      mono: true,
                      weight: FontWeight.w600,
                    ),
                    for (final h in rq.headers)
                      T('${h.$1}: ${h.$2}', mono: true, color: pal.muted),
                    ...switch (rq.body) {
                      BodyRaw b => [
                        const SizedBox(height: 4),
                        T(b.text, mono: true),
                      ],
                      BodyForm b => [
                        T(HttpExecutor.formEncode(b.fields), mono: true),
                      ],
                      BodyMultipart b => [
                        for (final it in b.parts)
                          T(
                            '${it.name} = ${it.isFile ? "@" : ""}${it.value}',
                            mono: true,
                          ),
                      ],
                      BodyFileBody b => [T('<file: ${b.path}>', mono: true)],
                      BodyNone() => const <Widget>[],
                    },
                    const SizedBox(height: 8),
                    T(
                      '← ${res.status} ${res.statusText}  (${res.timeMs} ms)',
                      mono: true,
                      color: statusColor(res.status, pal),
                      weight: FontWeight.w600,
                    ),
                    if (res.finalUrl != rq.url)
                      T(
                        'Final URL: ${res.finalUrl}',
                        mono: true,
                        color: pal.muted,
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      case 'Tests':
        content = ScrollBox(
          content: [
            if (result.tests.isEmpty)
              Padding(
                padding: const EdgeInsets.all(6),
                child: T('No tests or assertions ran.', color: pal.muted),
              )
            else
              TestsList(tests: result.tests),
          ],
        );
      case 'Console':
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: result.logs.isEmpty
                  ? T(
                      'Nothing logged. Use console.log() in scripts.',
                      color: pal.muted,
                    )
                  : T(result.logs.join('\n'), mono: true),
            ),
          ],
        );
      default:
        content = const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            spacing: 10,
            children: [
              Chip(
                '${res.status} ${res.statusText}'.trim(),
                color: statusColor(res.status, pal),
              ),
              T('${res.timeMs} ms', color: pal.muted, size: 12),
              T(formatSize(res.size), color: pal.muted, size: 12),
              if (result.tests.isNotEmpty)
                Clickable(
                  onClick: () => tab.resTab = 'Tests',
                  cursor: SystemMouseCursors.click,
                  child: Chip(
                    '$passed/${result.tests.length} tests',
                    color: passed == result.tests.length ? pal.ok : pal.err,
                  ),
                ),
              const Spacer(),
              if (rs.length > 1)
                Builder(
                  builder: (context) {
                    final labels = [
                      for (var i = 0; i < rs.length; i++)
                        '${i == 0 ? "Latest" : "#$i"}  ${rs[i].response != null && rs[i].response!.error == null ? "${rs[i].response!.status}" : "ERR"} · ${rs[i].response?.timeMs ?? 0}ms',
                    ];
                    return Dropdown(
                      selected: labels[tab.viewing.clamp(0, labels.length - 1)],
                      options: labels,
                      onSelect: (l) => tab.viewing = labels.indexOf(l),
                    );
                  },
                ),
              if (older != null)
                Btn(
                  label: tab.diff ? 'Hide Diff' : 'Diff',
                  onClick: () => tab.diff = !tab.diff,
                  icon: Ic.compare,
                ),
              Btn(
                label: 'Copy',
                onClick: () {
                  Platform.copy(res.text);
                  state.showToast('Response copied');
                },
                icon: Ic.copy,
              ),
              Btn(
                label: 'Save',
                icon: Ic.download,
                onClick: () async {
                  final f = await Platform.saveFile(
                    'Save response',
                    'response${_extFor(res.contentType)}',
                  );
                  if (f != null) {
                    try {
                      await File(f).writeAsBytes(res.body);
                      state.showToast('Saved ${p.basename(f)}');
                    } catch (_) {}
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Tabs(
            items: tabs,
            selected: tab.resTab,
            onSelect: (v) => tab.resTab = v,
            badge: (t) {
              switch (t) {
                case 'Headers':
                  return '${res.headers.length}';
                case 'Tests':
                  return result.tests.isNotEmpty
                      ? '$passed/${result.tests.length}'
                      : null;
                case 'Console':
                  return result.logs.isNotEmpty
                      ? '${result.logs.length}'
                      : null;
                default:
                  return null;
              }
            },
          ),
        ),
        Expanded(
          child: Padding(padding: const EdgeInsets.all(8), child: content),
        ),
      ],
    );
  }
}

/// Content types that are text. Anything else with a content type (zip, octet-stream, fonts, ...) is treated as a file.
final RegExp TEXT_TYPE = RegExp(
  'text/|json|xml|html|javascript|ecmascript|yaml|x-www-form-urlencoded|graphql|csv|svg|markdown|x-sh|x-httpd',
);

String _extFor(String ct) {
  if (ct.contains('json')) return '.json';
  if (ct.contains('html')) return '.html';
  if (ct.contains('xml')) return '.xml';
  if (ct.contains('png')) return '.png';
  if (ct.contains('jpeg')) return '.jpg';
  if (ct.contains('pdf')) return '.pdf';
  if (ct.contains('text')) return '.txt';
  return '.bin';
}

String _bodyForDiff(HttpResult r) {
  final t = r.text;
  final s = t.length > 300000 ? t.substring(0, 300000) : t;
  return Json.prettyText(s) ?? s;
}

class _BodyView extends StatefulWidget {
  const _BodyView({required this.state, required this.tab, required this.res});
  final AppState state;
  final RequestTab tab;
  final HttpResult res;

  @override
  State<_BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<_BodyView> {
  int expandSignal = 0;
  int cur = 0;
  String? _lastShown;
  String? _lastFind;

  @override
  void didUpdateWidget(_BodyView old) {
    super.didUpdateWidget(old);
    if (!identical(old.res, widget.res)) expandSignal = 0;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final state = widget.state, tab = widget.tab, res = widget.res;
    final ct = res.contentType.toLowerCase();
    final isImage = ct.startsWith('image/') && !ct.contains('svg');
    final isDoc =
        ct.contains('pdf') ||
        ct.startsWith('audio/') ||
        ct.startsWith('video/');
    // Non-text types (zip, octet-stream, fonts) or content with NUL bytes count as files.
    final isTextType = ct.isEmpty || TEXT_TYPE.hasMatch(ct);
    final head = res.body.length > 2000 ? res.body.sublist(0, 2000) : res.body;
    final isBinary = !isImage && !isDoc && (!isTextType || head.contains(0));
    final isMedia = isDoc || isBinary;
    final text = (isImage || isMedia) ? '' : res.text;
    final trimmed = text.trimLeft();
    dynamic parsed;
    if (text.length < 8000000 &&
        (ct.contains('json') ||
            trimmed.startsWith('{') ||
            trimmed.startsWith('['))) {
      parsed = Json.tryParse(text);
    }
    final isJson = parsed != null;
    final isXml =
        !isJson && (ct.contains('xml') || trimmed.startsWith('<?xml'));
    final lt = trimmed.length > 200
        ? trimmed.substring(0, 200).toLowerCase()
        : trimmed.toLowerCase();
    final isHtml =
        ct.contains('html') ||
        (!isJson &&
            !isXml &&
            (lt.startsWith('<!doctype html') || lt.startsWith('<html')));
    final isJs = ct.contains('javascript') || ct.contains('ecmascript');

    // Files offer Raw, Hex and Base64; text adds its own format.
    final List<String> textFormats = isImage || isMedia
        ? const []
        : isJson
        ? const ['JSON']
        : isHtml
        ? const ['HTML']
        : isXml
        ? const ['XML']
        : isJs
        ? const ['JavaScript']
        : const [];
    const rawFormats = BINARY_FORMATS;
    final allFormats = [...textFormats, ...rawFormats];
    final detected = isImage || isMedia
        ? 'Hex'
        : (textFormats.isNotEmpty ? textFormats.first : 'Raw');
    final fmt = allFormats.contains(tab.resView) ? tab.resView : detected;
    final previewable =
        isImage ||
        isMedia ||
        (fmt == 'JSON' && isJson) ||
        (fmt == 'HTML' && isHtml);
    final preview = previewable && (tab.resPreview ?? (isImage || isMedia));
    final jsonMode = fmt == 'JSON' && isJson;
    final dynamic filtered = !isJson
        ? null
        : (tab.filter.trim().isEmpty
              ? parsed
              : JsonPath.query(parsed, tab.filter));
    String shown;
    switch (fmt) {
      case 'JSON':
        if (isJson) {
          if (filtered is String && tab.filter.trim().isNotEmpty) {
            shown = filtered;
          } else if (text.length > 3000000 && tab.filter.trim().isEmpty) {
            shown = text;
          } else {
            shown = Json.stringify(filtered, pretty: true);
          }
        } else {
          shown = text;
        }
      case 'XML':
        if (isXml || text.trimLeft().startsWith('<')) {
          try {
            shown = prettyXml(text);
          } catch (_) {
            shown = text;
          }
        } else {
          shown = text;
        }
      case 'Hex':
        shown = hexDump(res.body);
      case 'Base64':
        shown = base64Wrapped(
          res.body.length > 2000000
              ? Uint8List.sublistView(res.body, 0, 2000000)
              : res.body,
        );
      default:
        shown = text.isEmpty && res.size > 0
            ? (res.text.length > 2000000
                  ? res.text.substring(0, 2000000)
                  : res.text)
            : text;
    }
    final lang = switch (fmt) {
      'JSON' => isJson ? 'json' : 'text',
      'HTML' || 'XML' => 'xml',
      'JavaScript' => 'js',
      _ => 'text',
    };
    final textual = !preview;
    final matches = <int>[];
    if (tab.find.trim().isNotEmpty && textual) {
      final q = tab.find.toLowerCase();
      final lines = codeLines(shown);
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains(q)) matches.add(i);
      }
    }
    if (_lastShown != shown || _lastFind != tab.find) {
      cur = 0;
      _lastShown = shown;
      _lastFind = tab.find;
    }
    if (cur >= matches.length) cur = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          spacing: 8,
          children: [
            FormatMenu(
              current: fmt,
              onFormat: (f) {
                tab.resView = f;
                if (BINARY_FORMATS.contains(f)) tab.resPreview = false;
              },
              textFormats: textFormats,
              rawFormats: rawFormats,
            ),
            PreviewToggle(
              on: preview,
              enabled: previewable,
              onChange: (v) => tab.resPreview = v,
            ),
            if (jsonMode && !isMedia)
              Expanded(
                child: Field(
                  value: tab.filter,
                  onChange: (v) => tab.filter = v,
                  placeholder: 'Filter  e.g.  \$.data.items[0].name',
                  mono: true,
                  highlightVars: false,
                ),
              )
            else
              const Spacer(),
            if (preview && jsonMode) ...[
              IconBtn(
                icon: Ic.expandAll,
                onClick: () => setState(
                  () => expandSignal = expandSignal > 0 ? expandSignal + 1 : 1,
                ),
              ),
              IconBtn(
                icon: Ic.collapseAll,
                onClick: () => setState(
                  () => expandSignal = expandSignal < 0 ? expandSignal - 1 : -1,
                ),
              ),
            ],
            if (textual) ...[
              SizedBox(
                width: 150,
                child: Field(
                  value: tab.find,
                  onChange: (v) => tab.find = v,
                  placeholder: 'Find…',
                  highlightVars: false,
                  onEnter: () {
                    if (matches.isNotEmpty) {
                      setState(() => cur = (cur + 1) % matches.length);
                    }
                  },
                ),
              ),
              if (tab.find.trim().isNotEmpty) ...[
                T(
                  matches.isEmpty ? '0' : '${cur + 1}/${matches.length}',
                  color: matches.isEmpty ? pal.err : pal.muted,
                  size: 11,
                ),
                IconBtn(
                  icon: Ic.up,
                  onClick: () {
                    if (matches.isNotEmpty) {
                      setState(
                        () => cur = (cur - 1 + matches.length) % matches.length,
                      );
                    }
                  },
                ),
                IconBtn(
                  icon: Ic.down,
                  onClick: () {
                    if (matches.isNotEmpty) {
                      setState(() => cur = (cur + 1) % matches.length);
                    }
                  },
                ),
              ],
            ],
          ],
        ),
        if (res.size == 0)
          T('(empty response body)', color: pal.muted)
        else
          Expanded(
            child: preview && isImage
                ? ImagePreview(res: res)
                : preview && isMedia
                ? MediaPreview(res: res)
                : preview && fmt == 'HTML'
                ? HtmlPreview(html: text, bytes: res.body)
                : preview && jsonMode
                ? JsonTree(
                    root: filtered,
                    expandSignal: expandSignal,
                    onCopy: (v, msg) {
                      Platform.copy(v);
                      state.showToast(msg);
                    },
                  )
                : CodeView(
                    text: shown,
                    lang: lang,
                    query: tab.find,
                    focusLine: cur < matches.length ? matches[cur] : -1,
                  ),
          ),
      ],
    );
  }
}
