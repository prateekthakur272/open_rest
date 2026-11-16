// ignore_for_file: constant_identifier_names
import 'package:open_rest/components/modifiers.dart';

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/context_menu.dart';
import 'package:open_rest/components/editing.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/inline_rename.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/response_controls.dart';
import 'package:open_rest/components/tables.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/features/request/graphql_pane.dart';
import 'package:open_rest/features/request/tls_editor.dart';
import 'package:open_rest/features/response/response_pane.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/xml.dart';
import 'package:path/path.dart' as p;

/// Editor tabs of a WebSocket request: the handshake request, no body or scripts.
const List<String> WS_TABS = [
  'Message',
  'Params',
  'Headers',
  'Auth',
  'Protocols',
  'Docs',
  'Settings',
];

const List<String> REQ_TABS = [
  'Params',
  'Body',
  'Headers',
  'Auth',
  'Vars',
  'Script',
  'Assert',
  'Tests',
  'Docs',
  'Settings',
];

List<KV> syncPathParams(String url, List<KV> old) {
  final qi = url.indexOf('?');
  final base = qi < 0 ? url : url.substring(0, qi);
  final names = <String>[];
  for (final m in RegExp(r'(?<=/):([A-Za-z_][\w-]*)').allMatches(base)) {
    final n = m.group(1)!;
    if (!names.contains(n)) names.add(n);
  }
  return [
    for (final n in names)
      () {
        for (final k in old) {
          if (k.name == n) return k;
        }
        return KV(name: n);
      }(),
  ];
}

/// The editor tab of a request: title bar, URL bar, request / response split.
class RequestView extends StatelessWidget {
  const RequestView({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, tab]),
    builder: (context, _) {
      final known = {
        ...state.knownVars(tab),
        ...state.runtime(tab.collectionPath).keys,
      };
      final info = {
        for (final e in state.varInfo(tab).entries)
          e.key: VarInfo(e.value.$1, e.value.$2),
      };
      return LocalVars(
        value: known,
        child: LocalVarInfo(
          value: info,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RequestTitleBar(
                key: ValueKey('title-${tab.id}'),
                state: state,
                tab: tab,
              ),
              _UrlBar(state: state, tab: tab),
              _ResolvedBar(state: state, tab: tab, known: known),
              Expanded(
                child: SplitPane(
                  vertical: state.settings.verticalLayout,
                  fraction: state.splitFraction,
                  onFraction: (f) => state.splitFraction = f,
                  first: RequestPane(state: state, tab: tab),
                  second: ResponsePane(state: state, tab: tab),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ResolvedBar extends StatelessWidget {
  const _ResolvedBar({
    required this.state,
    required this.tab,
    required this.known,
  });
  final AppState state;
  final RequestTab tab;
  final Set<String> known;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = tab.draft;
    final text =
        [
          r.url,
          r.headers
              .where((it) => it.enabled)
              .map((it) => '${it.name} ${it.value}')
              .join(' '),
          r.bodyJson,
          r.bodyText,
          r.bodyXml,
          r.bodyGraphql,
        ].join(' ') +
        r.formUrlEncoded
            .where((it) => it.enabled)
            .map((it) => it.value)
            .join(' ');
    final undefined = Variables.names(text)
        .toSet()
        .where(
          (n) =>
              !known.contains(n) &&
              !n.startsWith(r'$') &&
              !n.startsWith('process.env.') &&
              !WorkflowRunner.isStepRef(n),
        )
        .toList();
    final hasVars = r.url.contains('{{') || r.url.contains('/:');
    if (!hasVars && undefined.isEmpty) return const SizedBox.shrink();
    final resolved = hasVars ? state.resolveUrl(tab) : null;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
      child: Row(
        spacing: 10,
        children: [
          if (resolved != null && resolved != r.url) ...[
            T('→', color: pal.muted, size: 12),
            Flexible(
              child: Clickable(
                onClick: () {
                  Platform.copy(resolved);
                  state.showToast('Resolved URL copied');
                },
                child: T(
                  resolved,
                  color: pal.muted,
                  size: 12,
                  mono: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          if (undefined.isNotEmpty)
            Chip(
              'undefined: ${undefined.take(4).join(', ')}${undefined.length > 4 ? ' +${undefined.length - 4}' : ''}',
              color: pal.err,
            ),
        ],
      ),
    );
  }
}

/// Breadcrumb + inline-rename title of a request tab.
class RequestTitleBar extends StatefulWidget {
  const RequestTitleBar({super.key, required this.state, required this.tab});
  final AppState state;
  final RequestTab tab;

  @override
  State<RequestTitleBar> createState() => RequestTitleBarState();
}

class RequestTitleBarState extends State<RequestTitleBar> {
  bool renaming = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final state = widget.state, tab = widget.tab;
    final col = state.collection(tab.collectionPath);
    final crumbs = <String>[
      if (col != null) col.name,
      ...?col?.ancestorFolders(tab.filePath).map((f) => f.name),
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 10, top: 8),
      child: Row(
        spacing: 6,
        children: [
          for (final c in crumbs) ...[
            T(c, color: pal.muted, size: 12, maxLines: 1),
            T('/', color: pal.muted.withValues(alpha: 0.6), size: 12),
          ],
          if (renaming)
            SizedBox(
              width: 240,
              child: InlineRename(
                initial: tab.draft.name,
                onDone: (n) {
                  setState(() => renaming = false);
                  final node = col?.findRequest(tab.filePath);
                  if (n != null &&
                      n != tab.draft.name &&
                      col != null &&
                      node != null) {
                    state.renameNode(col.path, node, n);
                  }
                },
              ),
            )
          else
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Clickable(
                  onClick: () => setState(() => renaming = true),
                  cursor: SystemMouseCursors.text,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Flexible(
                          child: T(
                            tab.draft.name,
                            size: 14,
                            weight: FontWeight.w600,
                            maxLines: 1,
                          ),
                        ),
                        if (tab.dirty)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: pal.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (renaming) const Spacer(),
          IconBtn(icon: Ic.copy, onClick: () => state.copyCurl(tab)),
          IconBtn(
            icon: Ic.code,
            onClick: () => state.modal = ModalCodegen(tabId: tab.id),
          ),
          IconBtn(
            icon: state.settings.verticalLayout ? Ic.splitV : Ic.splitH,
            onClick: () => state.toggleLayout(),
          ),
          Btn(
            label: 'Save',
            onClick: () => state.save(tab),
            enabled: tab.dirty,
            icon: Ic.save,
          ),
        ],
      ),
    );
  }
}

class _UrlBar extends StatelessWidget {
  const _UrlBar({required this.state, required this.tab});
  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = tab.draft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // The border is painted only, so it takes no layout space.
      child: Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: pal.field,
          borderRadius: BorderRadius.circular(8),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: pal.border, width: 1),
        ),
        child: Row(
          spacing: 4,
          children: [
            Dropdown(
              selected: r.method,
              options: HTTP_METHODS,
              onSelect: (m) =>
                  state.update(tab, (it) => it.copyWith(method: m)),
              color: methodColor(r.method, pal),
              weight: FontWeight.w700,
              optionColor: (o) => methodColor(o, pal),
              bordered: false,
            ),
            Container(width: 1, height: 20, color: pal.border),
            Expanded(
              child: Field(
                value: r.url,
                onChange: (u) {
                  if (u.trimLeft().startsWith('curl ')) {
                    final parsed = Importers.parseCurl(u);
                    if (parsed != null) {
                      state.update(
                        tab,
                        (it) => parsed.copyWith(
                          name: it.name,
                          seq: it.seq,
                          pathParams: syncPathParams(parsed.url, const []),
                        ),
                      );
                      return;
                    }
                  }
                  state.update(
                    tab,
                    (it) => it.copyWith(
                      url: u,
                      params: UrlSync.paramsFromUrl(u, it.params),
                      pathParams: syncPathParams(u, it.pathParams),
                    ),
                  );
                },
                placeholder: 'Enter URL or paste a cURL command',
                mono: true,
                bordered: false,
                onEnter: () => state.send(tab),
                focusRequester: state.urlFocus,
              ),
            ),
            if (tab.sending)
              Btn(
                label: 'Cancel',
                onClick: () => state.cancel(tab),
                danger: true,
                icon: Ic.stop,
              )
            else
              Btn(
                label: 'Send',
                onClick: () => state.send(tab),
                primary: true,
                icon: Ic.send,
              ),
          ],
        ),
      ),
    );
  }
}

/// Request editor tabs (Params / Body / Headers / ...).
class RequestPane extends StatelessWidget {
  const RequestPane({
    super.key,
    required this.state,
    required this.tab,
    this.tabs = REQ_TABS,
    this.custom = const {},
  });

  final AppState state;
  final RequestTab tab;

  /// The editor tabs to offer; a WebSocket request uses [WS_TABS].
  final List<String> tabs;

  /// Content of tabs that are not built in (keyed by tab name), e.g. the WebSocket message editor.
  final Map<String, Widget> custom;

  String? _badge(ApiRequest r, String t) {
    String? n(int v) => v > 0 ? '$v' : null;
    switch (t) {
      case 'Params':
        return n(r.params.where((it) => it.enabled).length);
      case 'Headers':
        return n(r.headers.where((it) => it.enabled).length);
      case 'Body':
        return r.bodyMode != BodyMode.None ? '●' : null;
      case 'Auth':
        return r.auth.mode != AuthMode.None && r.auth.mode != AuthMode.Inherit
            ? '●'
            : null;
      case 'Vars':
        return n(r.preVars.length + r.postVars.length);
      case 'Script':
        return r.preScript.trim().isNotEmpty || r.postScript.trim().isNotEmpty
            ? '●'
            : null;
      case 'Assert':
        return n(r.assertions.where((it) => it.enabled).length);
      case 'Tests':
        return r.tests.trim().isNotEmpty ? '●' : null;
      case 'Docs':
        return r.docs.trim().isNotEmpty ? '●' : null;
      case 'Protocols':
        return r.wsProtocols.trim().isNotEmpty ? '●' : null;
      case 'Message':
        return r.wsMessage.trim().isNotEmpty ? '●' : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = tab.draft;
    final pal = context.pal;
    void upd(ApiRequest Function(ApiRequest) f) => state.update(tab, f);
    // A tab name this editor does not offer (e.g. restored from another request type) falls back to the first.
    final cur = tabs.contains(tab.reqTab) ? tab.reqTab : tabs.first;
    Widget content;
    switch (cur) {
      case 'Params':
        content = ScrollBox(
          content: [
            KVTable(
              items: r.params,
              onChange: (np) => upd(
                (it) => it.copyWith(
                  params: np,
                  url: UrlSync.urlWithParams(it.url, np),
                ),
              ),
              title: 'Query Parameters',
              encodeTools: true,
            ),
            if (r.pathParams.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    const SectionLabel('PATH PARAMETERS'),
                    T(
                      'from  :name  segments in the URL',
                      color: pal.muted,
                      size: 11,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < r.pathParams.length; i++)
                        Row(
                          spacing: 6,
                          children: [
                            Expanded(
                              flex: 10,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 22),
                                child: T(
                                  ':${r.pathParams[i].name}',
                                  mono: true,
                                  color: pal.accent,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 14,
                              child: Field(
                                value: r.pathParams[i].value,
                                onChange: (v) => upd(
                                  (it) => it.copyWith(
                                    pathParams: [
                                      ...it.pathParams,
                                    ]..[i] = r.pathParams[i].copyWith(value: v),
                                  ),
                                ),
                                placeholder: 'Value',
                                mono: true,
                              ),
                            ),
                            const SizedBox(width: 24),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      case 'Body':
        content = _BodyPane(state: state, tab: tab);
      case 'Headers':
        content = ScrollBox(
          content: [
            KVTable(
              items: r.headers,
              onChange: (h) => upd((it) => it.copyWith(headers: h)),
              keyHint: 'Header',
              valueHint: 'Value',
              title: 'Request Headers',
              keySuggestions: HEADER_NAMES,
              keyHints: (n) => HEADER_HINTS[n],
              valueSuggestions: (n) =>
                  HEADER_VALUES[n.toLowerCase()] ?? const [],
            ),
            _InheritedHeaders(state: state, tab: tab),
          ],
        );
      case 'Auth':
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: AuthEditor(
                auth: r.auth,
                onChange: (a) => upd((it) => it.copyWith(auth: a)),
                modes: AuthMode.values,
                inheritInfo: _inheritedAuthInfo(state, tab),
              ),
            ),
          ],
        );
      case 'Vars':
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tabs(
                items: const ['Pre Request', 'Post Response'],
                selected: tab.varsTab,
                onSelect: (v) => tab.varsTab = v,
              ),
            ),
            if (tab.varsTab == 'Pre Request') ...[
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: T(
                  'Variables set before the request runs. Use them as {{name}}.',
                  color: pal.muted,
                  size: 12,
                ),
              ),
              Expanded(
                child: ScrollBox(
                  content: [
                    KVTable(
                      items: r.preVars,
                      onChange: (v) => upd((it) => it.copyWith(preVars: v)),
                      keyHint: 'Name',
                      valueHint: 'Value',
                      title: 'Pre-request Variables',
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: T(
                  'Set variables from the response using an expression, e.g. res.body.token',
                  color: pal.muted,
                  size: 12,
                ),
              ),
              Expanded(
                child: ScrollBox(
                  content: [
                    KVTable(
                      items: r.postVars,
                      onChange: (v) => upd((it) => it.copyWith(postVars: v)),
                      keyHint: 'Name',
                      valueHint: 'Expression  (res.body.id)',
                      title: 'Post-response Variables',
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      case 'Script':
        final pre = tab.scriptTab == 'Pre Request';
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tabs(
                items: const ['Pre Request', 'Post Response'],
                selected: tab.scriptTab,
                onSelect: (v) => tab.scriptTab = v,
              ),
            ),
            _SnippetBar(
              items: pre ? Snippets.pre : Snippets.post,
              onInsert: (code) => upd(
                (it) => pre
                    ? it.copyWith(preScript: _append(it.preScript, code))
                    : it.copyWith(postScript: _append(it.postScript, code)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: pre
                    ? CodeEditor(
                        key: const ValueKey('pre-script'),
                        value: r.preScript,
                        onChange: (v) => upd((it) => it.copyWith(preScript: v)),
                        lang: 'js',
                        placeholder: "// req.setHeader('X-Time', Date.now());\n// bru.setVar('token', 'abc');",
                      )
                    : CodeEditor(
                        key: const ValueKey('post-script'),
                        value: r.postScript,
                        onChange: (v) =>
                            upd((it) => it.copyWith(postScript: v)),
                        lang: 'js',
                        placeholder: "// bru.setVar('token', res.body.token);\n// console.log(res.status);",
                      ),
              ),
            ),
          ],
        );
      case 'Assert':
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, right: 12),
              child: T(
                "Declarative checks, e.g.  res.status  eq 200   •   res.body.name  isString   •   res.headers['content-type']  contains json",
                color: pal.muted,
                size: 12,
              ),
            ),
            Expanded(
              child: ScrollBox(
                content: [
                  KVTable(
                    items: r.assertions,
                    onChange: (a) => upd((it) => it.copyWith(assertions: a)),
                    keyHint: 'Expression',
                    valueHint: 'Operator and value',
                    title: 'Assertions',
                  ),
                ],
              ),
            ),
          ],
        );
      case 'Tests':
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SnippetBar(
              items: Snippets.tests,
              onInsert: (code) =>
                  upd((it) => it.copyWith(tests: _append(it.tests, code))),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: CodeEditor(
                  value: r.tests,
                  onChange: (v) => upd((it) => it.copyWith(tests: v)),
                  lang: 'js',
                  placeholder: "test('status is 200', () => {\n  expect(res.status).to.equal(200);\n});",
                ),
              ),
            ),
          ],
        );
      case 'Docs':
        content = Padding(
          padding: const EdgeInsets.all(10),
          child: CodeEditor(
            value: r.docs,
            onChange: (v) => upd((it) => it.copyWith(docs: v)),
            lang: 'text',
            placeholder: 'Document this request…',
          ),
        );
      case 'Protocols':
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    const SectionLabel('SUBPROTOCOLS'),
                    Field(
                      key: const ValueKey('ws-protocols'),
                      value: r.wsProtocols,
                      onChange: (v) => upd((it) => it.copyWith(wsProtocols: v)),
                      placeholder: 'graphql-transport-ws, mqtt',
                      mono: true,
                    ),
                    T(
                      'Comma-separated list sent in Sec-WebSocket-Protocol; the server picks one.',
                      color: pal.muted,
                      size: 11,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 'Settings':
        content = ScrollBox(
          content: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  LabeledCheck(
                    label:
                        'Encode URL (escape unsafe characters before sending)',
                    checked: r.encodeUrl,
                    onChange: (v) => upd((it) => it.copyWith(encodeUrl: v)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      const T('Timeout (ms, 0 = use global)'),
                      SizedBox(
                        width: 100,
                        child: Field(
                          value: r.timeoutMs.toString(),
                          onChange: (v) {
                            final digits = v
                                .split('')
                                .where(
                                  (c) =>
                                      c.codeUnitAt(0) >= 48 &&
                                      c.codeUnitAt(0) <= 57,
                                )
                                .join();
                            final cut = digits.length > 7
                                ? digits.substring(0, 7)
                                : digits;
                            upd(
                              (it) => it.copyWith(
                                timeoutMs: int.tryParse(cut) ?? 0,
                              ),
                            );
                          },
                          highlightVars: false,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      const T(
                        'Client certificate',
                        size: 13,
                        weight: FontWeight.w600,
                      ),
                      TlsEditor(
                        config: r.tls,
                        onChange: (t) => upd((it) => it.copyWith(tls: t)),
                        inheritLabel: 'Inherit from folder / collection',
                        baseDir: state.collection(tab.collectionPath)?.path,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      default:
        content = custom[cur] ?? const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Tabs(
            items: tabs,
            selected: cur,
            onSelect: (v) => tab.reqTab = v,
            badge: (t) => _badge(r, t),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _BodyPane extends StatelessWidget {
  const _BodyPane({required this.state, required this.tab});
  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) {
    final r = tab.draft;
    final pal = context.pal;
    void upd(ApiRequest Function(ApiRequest) f) => state.update(tab, f);
    final String? autoCt = switch (r.bodyMode) {
      BodyMode.Json || BodyMode.Graphql => 'application/json',
      BodyMode.Text => 'text/plain',
      BodyMode.Xml => 'application/xml',
      BodyMode.Form => 'application/x-www-form-urlencoded',
      BodyMode.Multipart => 'multipart/form-data',
      BodyMode.File => 'application/octet-stream',
      BodyMode.None => null,
    };
    final ctOverride = r.headers.any(
      (it) => it.enabled && it.name.toLowerCase() == 'content-type',
    );
    (String, int)? jsonErr;
    if (r.bodyMode == BodyMode.Json && r.bodyJson.trim().isNotEmpty) {
      try {
        Json.parse(r.bodyJson.replaceAll(RegExp(r'\{\{[^}]*\}\}'), '0'));
      } on JsonException catch (e) {
        final pos =
            int.tryParse(
              RegExp(r'position (\d+)').firstMatch(e.message)?.group(1) ?? '',
            ) ??
            0;
        final (ln, col) = lineCol(r.bodyJson, pos);
        final at = e.message.indexOf(' at position');
        jsonErr = (
          '${at < 0 ? e.message : e.message.substring(0, at)} — line $ln, col $col',
          ln,
        );
      } catch (e) {
        jsonErr = (e.toString(), -1);
      }
    }
    final String? current = switch (r.bodyMode) {
      BodyMode.Json => r.bodyJson,
      BodyMode.Text => r.bodyText,
      BodyMode.Xml => r.bodyXml,
      BodyMode.Graphql => r.bodyGraphql,
      _ => null,
    };

    Widget body;
    switch (r.bodyMode) {
      case BodyMode.None:
        body = Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: pal.border, width: 1),
          ),
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Ico(Ic.code, tint: pal.muted.withValues(alpha: 0.5), size: 40),
                const SizedBox(height: 8),
                const T('This request has no body', weight: FontWeight.w600),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: T(
                    'Pick a type above, or start with a template',
                    color: pal.muted,
                    size: 12,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Btn(
                      label: 'JSON',
                      onClick: () => upd(
                        (it) => it.copyWith(
                          bodyMode: BodyMode.Json,
                          bodyJson: it.bodyJson.trim().isEmpty
                              ? '{\n  \n}'
                              : it.bodyJson,
                        ),
                      ),
                      icon: Ic.fmtJson,
                    ),
                    Btn(
                      label: 'Form',
                      onClick: () =>
                          upd((it) => it.copyWith(bodyMode: BodyMode.Form)),
                      icon: Ic.text,
                    ),
                    Btn(
                      label: 'Text',
                      onClick: () =>
                          upd((it) => it.copyWith(bodyMode: BodyMode.Text)),
                      icon: Ic.fmtRaw,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      case BodyMode.Json:
        body = CodeEditor(
          value: r.bodyJson,
          onChange: (v) => upd((it) => it.copyWith(bodyJson: v)),
          lang: 'json',
          placeholder: '{\n  "key": "value"\n}',
          showStatus: true,
          scrollbar: true,
          errorLine: jsonErr?.$2 ?? -1,
        );
      case BodyMode.Text:
        body = CodeEditor(
          value: r.bodyText,
          onChange: (v) => upd((it) => it.copyWith(bodyText: v)),
          lang: 'text',
          showStatus: true,
          scrollbar: true,
        );
      case BodyMode.Xml:
        body = CodeEditor(
          value: r.bodyXml,
          onChange: (v) => upd((it) => it.copyWith(bodyXml: v)),
          lang: 'xml',
          placeholder: '<root></root>',
          showStatus: true,
          scrollbar: true,
        );
      case BodyMode.Graphql:
        body = GraphqlBody(state: state, tab: tab);
      case BodyMode.Form:
        body = ScrollBox(
          content: [
            KVTable(
              items: r.formUrlEncoded,
              onChange: (v) => upd((it) => it.copyWith(formUrlEncoded: v)),
              title: 'Form Fields',
              encodeTools: true,
            ),
          ],
        );
      case BodyMode.Multipart:
        body = ScrollBox(
          content: [
            KVTable(
              items: r.multipart,
              onChange: (v) => upd((it) => it.copyWith(multipart: v)),
              allowFile: true,
              onPickFile: (_, set) async {
                final f = await Platform.pickFile('Choose file');
                if (f != null) set(f);
              },
              title: 'Form Data',
            ),
          ],
        );
      case BodyMode.File:
        File? f;
        try {
          final x = File(r.bodyFile);
          if (r.bodyFile.isNotEmpty && x.existsSync()) f = x;
        } catch (_) {}
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Field(
                      value: r.bodyFile,
                      onChange: (v) => upd((it) => it.copyWith(bodyFile: v)),
                      placeholder: 'Path to file',
                      mono: true,
                    ),
                  ),
                  Btn(
                    label: 'Browse…',
                    icon: Ic.folder,
                    onClick: () async {
                      final x = await Platform.pickFile('Choose file');
                      if (x != null) upd((it) => it.copyWith(bodyFile: x));
                    },
                  ),
                ],
              ),
            ),
            if (f != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Ico(Ic.fileGeneric, tint: pal.accent, size: 16),
                  () {
                    final len = f!.lengthSync();
                    final sz = len < 1048576
                        ? '${(len / 1024.0).toStringAsFixed(1)} KB'
                        : '${(len / 1048576.0).toStringAsFixed(2)} MB';
                    return T(
                      '${p.basename(f.path)}  ·  $sz',
                      color: pal.muted,
                      size: 12,
                    );
                  }(),
                ],
              )
            else if (r.bodyFile.trim().isNotEmpty)
              T('File not found', color: pal.err, size: 12),
          ],
        );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              OptionMenu(
                selected: r.bodyMode.name,
                groups: BODY_MENU,
                onSelect: (id) => upd(
                  (it) => it.copyWith(bodyMode: BodyMode.values.byName(id)),
                ),
              ),
              if (r.bodyMode != BodyMode.None) ...[
                if (r.bodyMode == BodyMode.Json && r.bodyJson.trim().isNotEmpty)
                  if (jsonErr != null) ...[
                    Ico(Ic.cancel, tint: pal.err, size: 15),
                    Flexible(
                      child: T(
                        'Invalid JSON: ${jsonErr.$1}',
                        color: pal.err,
                        size: 12,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    Ico(Ic.checkCircle, tint: pal.ok, size: 15),
                    T('Valid JSON', color: pal.ok, size: 12),
                  ],
                if (autoCt != null)
                  Flexible(
                    child: T(
                      ctOverride
                          ? 'Content-Type taken from Headers'
                          : 'Content-Type: $autoCt (auto)',
                      color: pal.muted,
                      size: 11,
                      mono: true,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const Spacer(),
                if (current != null) ...[
                  if (r.bodyMode == BodyMode.Json || r.bodyMode == BodyMode.Xml)
                    IconBtn(
                      icon: Ic.edit,
                      onClick: () {
                        if (r.bodyMode == BodyMode.Json) {
                          final v = Json.prettyText(r.bodyJson);
                          if (v != null) {
                            upd((it) => it.copyWith(bodyJson: v));
                          } else {
                            state.showToast('Body is not valid JSON');
                          }
                        } else {
                          String x;
                          try {
                            x = prettyXml(r.bodyXml);
                          } catch (_) {
                            x = r.bodyXml;
                          }
                          upd((it) => it.copyWith(bodyXml: x));
                        }
                      },
                    ),
                  if (r.bodyMode == BodyMode.Json)
                    IconBtn(
                      icon: Ic.collapseAll,
                      onClick: () {
                        if (Json.isValid(r.bodyJson)) {
                          upd(
                            (it) => it.copyWith(
                              bodyJson: Json.stringify(Json.parse(r.bodyJson)),
                            ),
                          );
                        } else {
                          state.showToast(
                            'Minify needs valid JSON without {{variables}}',
                          );
                        }
                      },
                    ),
                  IconBtn(
                    icon: Ic.copy,
                    onClick: () {
                      Platform.copy(current);
                      state.showToast('Body copied');
                    },
                  ),
                ],
              ],
            ],
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

IconData _authIcon(AuthMode m) {
  switch (m) {
    case AuthMode.None:
      return Ic.noBody;
    case AuthMode.Inherit:
      return Ic.link;
    case AuthMode.Basic:
      return Ic.person;
    case AuthMode.Bearer:
      return Ic.key;
    case AuthMode.ApiKey:
      return Ic.key;
    case AuthMode.Digest:
      return Ic.fingerprint;
    case AuthMode.OAuth2:
      return Ic.shield;
  }
}

/// Section header with an icon tile; optionally collapsible.
class _AuthSection extends StatefulWidget {
  const _AuthSection({
    required this.icon,
    required this.title,
    this.collapsible = false,
    this.initiallyOpen = true,
    required this.children,
  });
  final IconData icon;
  final String title;
  final bool collapsible;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<_AuthSection> createState() => _AuthSectionState();
}

class _AuthSectionState extends State<_AuthSection> {
  late bool open = widget.initiallyOpen || !widget.collapsible;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final header = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pal.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Ico(widget.icon, tint: pal.accent, size: 13),
        ),
        T(widget.title, size: 13, weight: FontWeight.w600),
        if (widget.collapsible) Chevron(open: open, color: pal.muted),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: widget.collapsible
              ? Clickable(
                  onClick: () => setState(() => open = !open),
                  cursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(8),
                  child: header,
                )
              : header,
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

class _AuthRow extends StatelessWidget {
  const _AuthRow(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 120, child: T(label, color: context.pal.muted, size: 12)),
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child,
          ),
        ),
      ),
    ],
  );
}

class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.value,
    required this.onChange,
    this.placeholder = '',
  });
  final String value;
  final ValueChanged<String> onChange;
  final String placeholder;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool show = false;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Field(
        value: widget.value,
        onChange: widget.onChange,
        placeholder: widget.placeholder,
        mono: true,
        password: !show,
      ),
      Positioned.fill(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: IconBtn(
              icon: show ? Ic.eye : Ic.eyeOff,
              onClick: () => setState(() => show = !show),
              color: context.pal.muted,
            ),
          ),
        ),
      ),
    ],
  );
}

/// Editor for request authentication settings.
class AuthEditor extends StatelessWidget {
  const AuthEditor({
    super.key,
    required this.auth,
    required this.onChange,
    required this.modes,
    this.inheritLabel = 'Inherit',
    this.inheritInfo,
    this.padding = EdgeInsets.zero,
  });

  final Auth auth;
  final ValueChanged<Auth> onChange;
  final List<AuthMode> modes;
  final String inheritLabel;
  final String? inheritInfo;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    String label(AuthMode m) => m == AuthMode.Inherit ? inheritLabel : m.label;
    final simple = modes
        .where((it) => it == AuthMode.None || it == AuthMode.Inherit)
        .toList();
    final real = modes
        .where((it) => it != AuthMode.None && it != AuthMode.Inherit)
        .toList();
    final groups = [simple, real]
        .where((g) => g.isNotEmpty)
        .map(
          (g) => [for (final m in g) MenuOpt(m.name, label(m), _authIcon(m))],
        )
        .toList();
    Widget fld(String v, ValueChanged<String> f, [String ph = '']) =>
        Field(value: v, onChange: f, placeholder: ph, mono: true);
    final List<Widget> body;
    switch (auth.mode) {
      case AuthMode.None:
        body = [
          const _InfoCard(
            icon: Ic.noBody,
            title: 'No authentication',
            text: 'This request is sent without any credentials.',
          ),
        ];
      case AuthMode.Inherit:
        body = [
          _InfoCard(
            icon: Ic.link,
            title: 'Inherited',
            text: inheritInfo ?? 'Uses the authentication configured on the parent folder or collection.',
          ),
        ];
      case AuthMode.Basic:
      case AuthMode.Digest:
        body = [
          _AuthSection(
            icon: Ic.settings,
            title: 'Configuration',
            children: [
              _AuthRow(
                'Username',
                fld(auth.username, (v) => onChange(auth.copyWith(username: v))),
              ),
              _AuthRow(
                'Password',
                _SecretField(
                  value: auth.password,
                  onChange: (v) => onChange(auth.copyWith(password: v)),
                ),
              ),
              if (auth.mode == AuthMode.Digest)
                T(
                  "The nonce is obtained from the server's 401 challenge automatically.",
                  color: pal.muted,
                  size: 12,
                ),
            ],
          ),
        ];
      case AuthMode.Bearer:
        body = [
          _AuthSection(
            icon: Ic.settings,
            title: 'Configuration',
            children: [
              _AuthRow(
                'Token',
                _SecretField(
                  value: auth.token,
                  onChange: (v) => onChange(auth.copyWith(token: v)),
                  placeholder: '{{token}}',
                ),
              ),
              T(
                'Sent as  Authorization: Bearer <token>',
                color: pal.muted,
                size: 12,
                mono: true,
              ),
            ],
          ),
        ];
      case AuthMode.ApiKey:
        body = [
          _AuthSection(
            icon: Ic.settings,
            title: 'Configuration',
            children: [
              _AuthRow(
                'Key',
                fld(
                  auth.keyName,
                  (v) => onChange(auth.copyWith(keyName: v)),
                  'X-API-Key',
                ),
              ),
              _AuthRow(
                'Value',
                _SecretField(
                  value: auth.keyValue,
                  onChange: (v) => onChange(auth.copyWith(keyValue: v)),
                ),
              ),
              _AuthRow(
                'Add to',
                Dropdown(
                  selected: auth.placement == 'queryparams'
                      ? 'Query Params'
                      : 'Header',
                  options: const ['Header', 'Query Params'],
                  onSelect: (v) => onChange(
                    auth.copyWith(
                      placement: v == 'Header' ? 'header' : 'queryparams',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ];
      case AuthMode.OAuth2:
        body = [
          _AuthSection(
            icon: Ic.settings,
            title: 'Configuration',
            children: [
              _AuthRow(
                'Grant type',
                Dropdown(
                  selected: auth.grantType,
                  options: const ['client_credentials', 'password'],
                  onSelect: (v) => onChange(auth.copyWith(grantType: v)),
                ),
              ),
              _AuthRow(
                'Access token URL',
                fld(
                  auth.tokenUrl,
                  (v) => onChange(auth.copyWith(tokenUrl: v)),
                  'https://auth.example.com/oauth/token',
                ),
              ),
              _AuthRow(
                'Client ID',
                fld(auth.clientId, (v) => onChange(auth.copyWith(clientId: v))),
              ),
              _AuthRow(
                'Client secret',
                _SecretField(
                  value: auth.clientSecret,
                  onChange: (v) => onChange(auth.copyWith(clientSecret: v)),
                ),
              ),
              if (auth.grantType == 'password') ...[
                _AuthRow(
                  'Username',
                  fld(
                    auth.username,
                    (v) => onChange(auth.copyWith(username: v)),
                  ),
                ),
                _AuthRow(
                  'Password',
                  _SecretField(
                    value: auth.password,
                    onChange: (v) => onChange(auth.copyWith(password: v)),
                  ),
                ),
              ],
            ],
          ),
          _AuthSection(
            icon: Ic.tune,
            title: 'Advanced',
            collapsible: true,
            initiallyOpen: auth.scope.trim().isNotEmpty,
            children: [
              _AuthRow(
                'Scope',
                fld(
                  auth.scope,
                  (v) => onChange(auth.copyWith(scope: v)),
                  'read write',
                ),
              ),
              T(
                'The access token is fetched automatically and cached for this session.',
                color: pal.muted,
                size: 12,
              ),
            ],
          ),
        ];
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OptionMenu(
              selected: auth.mode.name,
              groups: groups,
              onSelect: (id) =>
                  onChange(auth.copyWith(mode: AuthMode.values.byName(id))),
              width: 190,
            ),
          ),
          ...body,
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: pal.field,
        borderRadius: BorderRadius.circular(8),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.border, width: 1),
      ),
      child: Row(
        spacing: 10,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pal.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Ico(icon, tint: pal.accent, size: 14),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(title, size: 13, weight: FontWeight.w600),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: T(text, color: pal.muted, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const List<List<MenuOpt>> BODY_MENU = [
  [MenuOpt('None', 'No Body', Ic.noBody)],
  [
    MenuOpt('Json', 'JSON', Ic.fmtJson),
    MenuOpt('Xml', 'XML', Ic.fmtXml),
    MenuOpt('Text', 'Text', Ic.fmtRaw),
    MenuOpt('Graphql', 'GraphQL', Ic.graph),
  ],
  [
    MenuOpt('Form', 'Form URL Encoded', Ic.formBody),
    MenuOpt('Multipart', 'Multipart Form', Ic.attach),
  ],
  [MenuOpt('File', 'Binary File', Ic.fileGeneric)],
];

const Map<BodyMode, String> BODY_SHORT = {
  BodyMode.None: 'None',
  BodyMode.Json: 'JSON',
  BodyMode.Text: 'Text',
  BodyMode.Xml: 'XML',
  BodyMode.Form: 'Form',
  BodyMode.Multipart: 'Multipart',
  BodyMode.Graphql: 'GraphQL',
  BodyMode.File: 'Binary',
};

const List<String> HEADER_NAMES = [
  'Accept',
  'Accept-Encoding',
  'Accept-Language',
  'Authorization',
  'Cache-Control',
  'Connection',
  'Content-Type',
  'Cookie',
  'DNT',
  'Host',
  'If-Modified-Since',
  'If-None-Match',
  'Origin',
  'Pragma',
  'Range',
  'Referer',
  'User-Agent',
  'X-API-Key',
  'X-Correlation-Id',
  'X-Forwarded-For',
  'X-Request-Id',
  'X-Requested-With',
];

const Map<String, String> HEADER_HINTS = {
  'Accept': 'Media types the client accepts',
  'Accept-Encoding': 'Compression the client supports',
  'Accept-Language': 'Preferred natural languages',
  'Authorization': 'Credentials for authenticating',
  'Cache-Control': 'Caching directives',
  'Connection': 'Connection management',
  'Content-Type': 'Media type of the request body',
  'Cookie': 'Cookies sent to the server',
  'DNT': 'Do Not Track preference',
  'Host': 'Target host and port',
  'If-Modified-Since': 'Conditional request by date',
  'If-None-Match': 'Conditional request by ETag',
  'Origin': 'Origin of the request (CORS)',
  'Pragma': 'Legacy cache directive',
  'Range': 'Request part of a resource',
  'Referer': 'URL of the referring page',
  'User-Agent': 'Client software identification',
  'X-API-Key': 'API key credential',
  'X-Correlation-Id': 'Trace id across services',
  'X-Forwarded-For': 'Original client IP via proxy',
  'X-Request-Id': 'Unique request id',
  'X-Requested-With': 'Marks AJAX requests',
};

const Map<String, List<String>> HEADER_VALUES = {
  'content-type': [
    'application/json',
    'application/x-www-form-urlencoded',
    'multipart/form-data',
    'application/xml',
    'text/plain',
    'text/html',
    'application/octet-stream',
  ],
  'accept': [
    'application/json',
    '*/*',
    'text/html',
    'application/xml',
    'text/plain',
  ],
  'authorization': ['Bearer ', 'Basic '],
  'cache-control': ['no-cache', 'no-store', 'max-age=0', 'max-age=3600'],
  'accept-encoding': ['gzip, deflate, br', 'gzip', 'identity'],
  'connection': ['keep-alive', 'close'],
  'x-requested-with': ['XMLHttpRequest'],
};

String _inheritedAuthInfo(AppState state, RequestTab tab) {
  final col = state.collection(tab.collectionPath);
  if (col == null) return 'Inherits from the parent folder or collection.';
  for (final f in col.ancestorFolders(tab.filePath).reversed) {
    final m = f.config.auth.mode;
    if (m != AuthMode.None && m != AuthMode.Inherit) {
      return 'Inherited from folder “${f.name}”: ${m.label}';
    }
  }
  final m = col.config.auth.mode;
  return m == AuthMode.None || m == AuthMode.Inherit
      ? 'Inherited: no authentication is configured on the folder or collection.'
      : 'Inherited from collection “${col.name}”: ${m.label}';
}

class _InheritedHeaders extends StatelessWidget {
  const _InheritedHeaders({required this.state, required this.tab});
  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) {
    final col = state.collection(tab.collectionPath);
    if (col == null) return const SizedBox.shrink();
    final rows = [
      ...col.config.headers
          .where((it) => it.enabled)
          .map((it) => TRow(it.name, it.value, 'collection')),
      for (final f in col.ancestorFolders(tab.filePath))
        ...f.config.headers
            .where((it) => it.enabled)
            .map((it) => TRow(it.name, it.value, f.name)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 12),
      child: ReadOnlyTable(
        rows: rows,
        keyHint: 'Header',
        valueHint: 'Value',
        noteHint: 'From',
        title: 'Inherited Headers',
        onCopy: (v) {
          Platform.copy(v);
          state.showToast('Copied');
        },
      ),
    );
  }
}

String _append(String existing, String code) =>
    existing.trim().isEmpty ? code : '${existing.trimRight()}\n\n$code';

/// Script snippets that can be inserted into the script editors.
class Snippets {
  Snippets._();
  static const List<(String, String)> pre = [
    ('Set header', "req.setHeader('X-Request-Id', Date.now().toString());"),
    ('Set variable', "bru.setVar('name', 'value');"),
    (
      'Bearer from variable',
      "req.setHeader('Authorization', 'Bearer ' + bru.getVar('token'));",
    ),
    (
      'Random id',
      "bru.setVar('rid', Math.random().toString(36).slice(2, 10));",
    ),
    (
      'Modify JSON body',
      'const body = req.getBody();\nbody.timestamp = new Date().toISOString();\nreq.setBody(body);',
    ),
    ('Wait', 'await bru.sleep(500);'),
  ];
  static const List<(String, String)> post = [
    ('Save token from response', "bru.setVar('token', res.body.token);"),
    ('Save environment variable', "bru.setEnvVar('userId', res.body.id);"),
    ('Log response', 'console.log(res.status, res.body);'),
    ('Run next request by name', "bru.setNextRequest('Request name');"),
    ('Stop collection run', 'bru.runner.stopExecution();'),
  ];
  static const List<(String, String)> tests = [
    (
      'Status is 200',
      "test('status is 200', () => {\n  expect(res.status).to.equal(200);\n});",
    ),
    (
      'Response time under 500ms',
      "test('fast response', () => {\n  expect(res.responseTime).to.be.below(500);\n});",
    ),
    (
      'Body has property',
      "test('has id', () => {\n  expect(res.body).to.have.property('id');\n});",
    ),
    (
      'Content-Type is JSON',
      "test('content type is json', () => {\n  expect(res.getHeader('content-type')).to.include('application/json');\n});",
    ),
    (
      'Array is not empty',
      "test('returns items', () => {\n  expect(res.body).to.be.an('array');\n  expect(res.body.length).to.be.above(0);\n});",
    ),
    (
      'Field types',
      "test('field types', () => {\n  expect(res.body.id).to.be.a('number');\n  expect(res.body.name).to.be.a('string');\n});",
    ),
  ];
}

class _SnippetBar extends StatefulWidget {
  const _SnippetBar({required this.items, required this.onInsert});
  final List<(String, String)> items;
  final ValueChanged<String> onInsert;

  @override
  State<_SnippetBar> createState() => _SnippetBarState();
}

class _SnippetBarState extends State<_SnippetBar> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10, top: 6, right: 10),
    child: Row(
      spacing: 8,
      children: [
        Stack(
          children: [
            Btn(
              label: 'Snippets',
              onClick: () => setState(() => open = true),
              icon: Ic.code,
            ),
            ContextMenu(
              open: open,
              onDismiss: () {
                if (mounted) setState(() => open = false);
              },
              items: [
                for (final (label, code) in widget.items)
                  MenuItem(label, action: () => widget.onInsert(code)),
              ],
            ),
          ],
        ),
        T(
          'bru · req · res · expect · test() · console',
          color: context.pal.muted,
          size: 11,
          mono: true,
        ),
      ],
    ),
  );
}
