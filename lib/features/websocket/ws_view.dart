import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/segmented.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/interop/importers.dart' show UrlSync;
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/request/request_pane.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/json.dart';

/// The editor tab of a WebSocket request: title, URL bar with connect, handshake settings and the live message log.
class WebSocketView extends StatelessWidget {
  const WebSocketView({super.key, required this.state, required this.tab});

  final AppState state;
  final RequestTab tab;

  @override
  Widget build(BuildContext context) {
    final ws = tab.ws;
    if (ws == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([state, tab, ws]),
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
                _WsUrlBar(state: state, tab: tab, ws: ws),
                Expanded(
                  child: SplitPane(
                    vertical: state.settings.verticalLayout,
                    fraction: state.splitFraction,
                    onFraction: (f) => state.splitFraction = f,
                    first: RequestPane(
                      state: state,
                      tab: tab,
                      tabs: WS_TABS,
                      custom: {
                        'Message': WsComposer(
                          state: state,
                          tab: tab,
                          ws: ws,
                          r: tab.draft,
                        ),
                      },
                    ),
                    second: _WsMessages(state: state, tab: tab, ws: ws),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WsUrlBar extends StatelessWidget {
  const _WsUrlBar({required this.state, required this.tab, required this.ws});

  final AppState state;
  final RequestTab tab;
  final WebSocketSession ws;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = tab.draft;
    final Widget action = switch (ws.status) {
      WsStatus.disconnected => Btn(
        key: const ValueKey('ws-connect'),
        label: 'Connect',
        primary: true,
        onClick: () => state.connectWs(tab),
      ),
      WsStatus.connecting => Btn(
        key: const ValueKey('ws-cancel'),
        label: 'Cancel',
        danger: true,
        onClick: ws.disconnect,
      ),
      WsStatus.open || WsStatus.closing => Btn(
        key: const ValueKey('ws-disconnect'),
        label: 'Disconnect',
        danger: true,
        enabled: ws.status == WsStatus.open,
        onClick: ws.disconnect,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: T(
                'WS',
                color: methodColor('WS', pal),
                weight: FontWeight.w700,
              ),
            ),
            Container(width: 1, height: 20, color: pal.border),
            Expanded(
              child: Field(
                key: const ValueKey('ws-url'),
                value: r.url,
                onChange: (u) => state.update(
                  tab,
                  (it) => it.copyWith(
                    url: u,
                    params: UrlSync.paramsFromUrl(u, it.params),
                  ),
                ),
                placeholder: 'wss://echo.websocket.events',
                mono: true,
                bordered: false,
                onEnter: () => state.send(tab),
                focusRequester: state.urlFocus,
              ),
            ),
            action,
          ],
        ),
      ),
    );
  }
}

String _clock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

/// Right-hand side: status and filters, the message log and the composer.
class _WsMessages extends StatelessWidget {
  const _WsMessages({required this.state, required this.tab, required this.ws});

  final AppState state;
  final RequestTab tab;
  final WebSocketSession ws;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final (String label, Color color) = switch (ws.status) {
      WsStatus.open => (
        ws.protocol == null || ws.protocol!.isEmpty
            ? 'Connected'
            : 'Connected · ${ws.protocol}',
        pal.ok,
      ),
      WsStatus.connecting => ('Connecting…', pal.accent),
      WsStatus.closing => ('Closing…', pal.warn),
      WsStatus.disconnected => ('Disconnected', pal.muted),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            spacing: 8,
            children: [
              // Status and counts take the left side and shrink first, so the controls stay at the right end.
              Expanded(
                child: Row(
                  spacing: 8,
                  children: [
                    if (ws.status == WsStatus.connecting)
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          color: pal.accent,
                          strokeWidth: 1.5,
                        ),
                      )
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Flexible(
                      child: T(
                        label,
                        key: const ValueKey('ws-status'),
                        color: color,
                        weight: FontWeight.w600,
                        size: 12,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    T(
                      '↑ ${ws.sentCount}   ↓ ${ws.receivedCount}',
                      color: pal.muted,
                      size: 11,
                      mono: true,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                ),
              ),
              Segmented(
                options: const ['All', 'Sent', 'Received'],
                selected: ws.filter,
                onSelect: (f) => ws.filter = f,
                itemKey: (o) => ValueKey('ws-filter-$o'),
              ),
              Btn(
                key: const ValueKey('ws-clear'),
                label: 'Clear',
                enabled: ws.messages.isNotEmpty,
                onClick: ws.clear,
              ),
            ],
          ),
        ),
        Container(height: 1, color: pal.border),
        Expanded(
          child: _WsLog(ws: ws, state: state),
        ),
      ],
    );
  }
}

/// The scrolling message log; sticks to the bottom while the user has not scrolled up.
class _WsLog extends StatefulWidget {
  const _WsLog({required this.ws, required this.state});

  final WebSocketSession ws;
  final AppState state;

  @override
  State<_WsLog> createState() => _WsLogState();
}

class _WsLogState extends State<_WsLog> {
  final ScrollController _c = ScrollController();
  final Set<WsMessage> _open = {};
  int _last = 0;
  bool _stick = true;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_c.hasClients) return;
      _stick = _c.position.pixels >= _c.position.maxScrollExtent - 40;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _shown(WsMessage m) => switch (widget.ws.filter) {
    'Sent' => m.dir == WsDir.sent || m.dir == WsDir.info,
    'Received' => m.dir == WsDir.received || m.dir == WsDir.info,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final all = [...widget.ws.messages.where(_shown)];
    if (all.length != _last) {
      _last = all.length;
      if (_stick) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_c.hasClients) _c.jumpTo(_c.position.maxScrollExtent);
        });
      }
    }
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              T('No messages yet', weight: FontWeight.w600, size: 13),
              T(
                widget.ws.isOpen
                    ? 'Type a message below and press Send.'
                    : 'Connect to start sending and receiving messages.',
                color: pal.muted,
                size: 12,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('ws-log'),
      controller: _c,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: all.length,
      itemBuilder: (context, i) {
        final m = all[i];
        return _LogRow(
          m: m,
          open: _open.contains(m),
          onToggle: () => setState(() {
            if (!_open.remove(m)) _open.add(m);
          }),
          state: widget.state,
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.m,
    required this.open,
    required this.onToggle,
    required this.state,
  });

  final WsMessage m;
  final bool open;
  final VoidCallback onToggle;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (m.dir == WsDir.info) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Row(
          spacing: 8,
          children: [
            T(_clock(m.time), color: pal.muted, size: 11, mono: true),
            Expanded(
              child: T(
                m.text,
                color: m.error ? pal.err : pal.muted,
                size: 12,
                softWrap: true,
              ),
            ),
          ],
        ),
      );
    }
    final sent = m.dir == WsDir.sent;
    final color = sent ? pal.accent : pal.ok;
    final preview = m.isBinary
        ? 'binary · ${m.size} bytes'
        : m.text.replaceAll(RegExp(r'\s+'), ' ');
    final body = m.isBinary ? m.hex : (Json.prettyText(m.text) ?? m.text);
    return Clickable(
      onClick: onToggle,
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            Row(
              spacing: 8,
              children: [
                T(
                  sent ? '↑' : '↓',
                  color: color,
                  weight: FontWeight.w700,
                  mono: true,
                ),
                T(_clock(m.time), color: pal.muted, size: 11, mono: true),
                Expanded(
                  child: T(
                    preview,
                    mono: true,
                    size: 12,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                T('${m.size} B', color: pal.muted, size: 11, mono: true),
              ],
            ),
            if (open)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: pal.field,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: pal.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Expanded(
                      child: T(body, mono: true, size: 12, softWrap: true),
                    ),
                    Clickable(
                      onClick: () {
                        Platform.copy(m.isBinary ? m.hex : m.text);
                        state.showToast('Copied');
                      },
                      cursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Ico(Ic.copy, tint: pal.muted, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Message editor with saved messages and the Send button; the Message tab of the request pane.
class WsComposer extends StatelessWidget {
  const WsComposer({
    super.key,
    required this.state,
    required this.tab,
    required this.ws,
    required this.r,
  });

  final AppState state;
  final RequestTab tab;
  final WebSocketSession ws;
  final ApiRequest r;

  String _name(String text) {
    final one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return one.length > 28 ? '${one.substring(0, 28)}…' : one;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    void upd(ApiRequest Function(ApiRequest) f) => state.update(tab, f);
    final canSave =
        r.wsMessage.trim().isNotEmpty &&
        !r.wsMessages.any((k) => k.value == r.wsMessage);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          if (r.wsMessages.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (i, k) in r.wsMessages.indexed)
                  Container(
                    key: ValueKey('ws-saved-$i'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: pal.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Clickable(
                          onClick: () =>
                              upd((it) => it.copyWith(wsMessage: k.value)),
                          cursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
                            child: T(k.name, size: 11, mono: true),
                          ),
                        ),
                        Clickable(
                          onClick: () => upd(
                            (it) => it.copyWith(
                              wsMessages: [...it.wsMessages]..removeAt(i),
                            ),
                          ),
                          cursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(2, 3, 8, 3),
                            child: Ico(Ic.close, tint: pal.muted, size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          Expanded(
            child: CodeEditor(
              key: const ValueKey('ws-composer'),
              value: r.wsMessage,
              onChange: (v) => upd((it) => it.copyWith(wsMessage: v)),
              lang: 'json',
              placeholder: 'Message to send (supports {{variables}})',
              scrollbar: true,
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Btn(
                key: const ValueKey('ws-save-message'),
                label: 'Save message',
                enabled: canSave,
                onClick: () => upd(
                  (it) => it.copyWith(
                    wsMessages: [
                      ...it.wsMessages,
                      KV(name: _name(it.wsMessage), value: it.wsMessage),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Btn(
                key: const ValueKey('ws-send'),
                label: 'Send',
                primary: true,
                icon: Ic.send,
                enabled: ws.isOpen && r.wsMessage.isNotEmpty,
                onClick: () => state.sendWs(tab),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
