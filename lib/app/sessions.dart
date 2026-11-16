import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect, VoidCallback;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:open_rest/core/graphql/graphql.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/ws/ws_client.dart';
import 'package:open_rest/features/dialogs/node_settings_controller.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/features/runner/runner_logic.dart' show ResultFilter;

/// A list that notifies on every mutation.
class StateList<E> extends ListBase<E> {
  StateList(this._notify, [Iterable<E> initial = const []])
    : _l = List<E>.of(initial);

  final List<E> _l;
  final VoidCallback _notify;

  @override
  int get length => _l.length;
  @override
  set length(int n) {
    _l.length = n;
    _notify();
  }

  @override
  E operator [](int index) => _l[index];
  @override
  void operator []=(int index, E element) {
    _l[index] = element;
    _notify();
  }

  @override
  void add(E element) {
    _l.add(element);
    _notify();
  }

  @override
  void addAll(Iterable<E> iterable) {
    _l.addAll(iterable);
    _notify();
  }

  @override
  void insert(int index, E element) {
    _l.insert(index, element);
    _notify();
  }

  @override
  E removeAt(int index) {
    final r = _l.removeAt(index);
    _notify();
    return r;
  }

  @override
  E removeLast() {
    final r = _l.removeLast();
    _notify();
    return r;
  }

  @override
  bool remove(Object? element) {
    final r = _l.remove(element);
    if (r) _notify();
    return r;
  }

  @override
  void removeWhere(bool Function(E) test) {
    final n = _l.length;
    _l.removeWhere(test);
    if (_l.length != n) _notify();
  }

  @override
  void clear() {
    if (_l.isEmpty) return;
    _l.clear();
    _notify();
  }
}

/// An insertion-ordered map that notifies on every mutation.
class StateMap<K, V> extends MapBase<K, V> {
  StateMap(this._notify);

  final Map<K, V> _m = <K, V>{};
  final VoidCallback _notify;

  @override
  V? operator [](Object? key) => _m[key];
  @override
  void operator []=(K key, V value) {
    _m[key] = value;
    _notify();
  }

  @override
  void clear() {
    if (_m.isEmpty) return;
    _m.clear();
    _notify();
  }

  @override
  Iterable<K> get keys => _m.keys;
  @override
  V? remove(Object? key) {
    final had = _m.containsKey(key);
    final r = _m.remove(key);
    if (had) _notify();
    return r;
  }

  @override
  bool containsKey(Object? key) => _m.containsKey(key);
  @override
  int get length => _m.length;
}

/// Base for the session/tab objects: notifies its own listeners and the owning [AppState] (via [onChange]).
class SessionNotifier extends ChangeNotifier {
  VoidCallback? onChange;

  /// Notifies listeners and the owning state that something changed.
  void changed() {
    notifyListeners();
    onChange?.call();
  }
}

/// One past response kept in a tab's history.
class HistoryEntry {
  const HistoryEntry({
    required this.time,
    required this.collection,
    required this.file,
    required this.name,
    required this.method,
    required this.url,
    required this.status,
    required this.timeMs,
    required this.error,
    required this.result,
  });

  final int time;
  final String collection;
  final String file;
  final String name;
  final String method;
  final String url;
  final int status;
  final int timeMs;
  final String? error;
  final ExecResult result;
}

/// Editable state of a Runner tab; lives on the tab so it survives switching between tabs.
class RunnerSession extends SessionNotifier {
  RunnerSession(this.folder, List<RequestNode> requests) {
    order = StateList<RequestNode>(changed, requests);
    selected = StateMap<String, bool>(changed);
    results = StateList<RunnerItem>(changed);
    collapsed = StateMap<int, bool>(changed);
    for (final r in requests) {
      selected._m[r.path] = true;
    }
  }

  final String? folder;
  late final StateList<RequestNode> order;
  late final StateMap<String, bool> selected;
  late final StateList<RunnerItem> results;

  /// Iteration groups collapsed in the results list.
  late final StateMap<int, bool> collapsed;

  bool _running = false;
  String _current = '';
  bool _stopOnFail = false;
  String _delay = '';
  String _iterations = '1';
  bool _cancelled = false;
  int? _expanded;
  bool _settingsOpen = false;
  ResultFilter _filter = ResultFilter.all;
  int _planned = 0;
  DateTime? _startedAt;
  DateTime? _finishedAt;

  /// Which results the list shows.
  ResultFilter get filter => _filter;
  set filter(ResultFilter v) {
    _filter = v;
    changed();
  }

  /// Number of requests the current run expects to execute.
  int get planned => _planned;
  set planned(int v) {
    _planned = v;
    changed();
  }

  DateTime? get startedAt => _startedAt;
  set startedAt(DateTime? v) {
    _startedAt = v;
    changed();
  }

  DateTime? get finishedAt => _finishedAt;
  set finishedAt(DateTime? v) {
    _finishedAt = v;
    changed();
  }

  /// Whether the settings section is expanded.
  bool get settingsOpen => _settingsOpen;
  set settingsOpen(bool v) {
    _settingsOpen = v;
    changed();
  }

  bool get running => _running;
  set running(bool v) {
    _running = v;
    changed();
  }

  String get current => _current;
  set current(String v) {
    _current = v;
    changed();
  }

  bool get stopOnFail => _stopOnFail;
  set stopOnFail(bool v) {
    _stopOnFail = v;
    changed();
  }

  String get delay => _delay;
  set delay(String v) {
    _delay = v;
    changed();
  }

  String get iterations => _iterations;
  set iterations(String v) {
    _iterations = v;
    changed();
  }

  bool get cancelled => _cancelled;
  set cancelled(bool v) {
    _cancelled = v;
    changed();
  }

  int? get expanded => _expanded;
  set expanded(int? v) {
    _expanded = v;
    changed();
  }

  List<RequestNode> get chosen =>
      order.where((it) => selected[it.path] == true).toList();
  int get iters => (int.tryParse(_iterations) ?? 1).clamp(1, 100);

  void resetOrder(List<RequestNode> requests) {
    order.clear();
    order.addAll(requests);
    for (final r in requests) {
      selected[r.path] = true;
    }
  }
}

/// Editable state + last run of a workflow tab.
class WorkflowSession extends SessionNotifier {
  WorkflowSession(Workflow initial) : _draft = initial, _saved = initial {
    runs = StateMap<String, StepRun>(changed);
    counts = StateMap<String, int>(changed);
    history = StateMap<String, List<StepRun>>(changed);
    events = StateList<RunEvent>(changed);
    logOpen = StateMap<int, bool>(changed);
  }

  Workflow _draft;
  Workflow _saved;
  Workflow get draft => _draft;
  set draft(Workflow v) {
    _draft = v;
    changed();
  }

  Workflow get saved => _saved;
  set saved(Workflow v) {
    _saved = v;
    changed();
  }

  /// Last execution of each request block (a block in a loop runs many times; [counts] says how many).
  late final StateMap<String, StepRun> runs;
  late final StateMap<String, int> counts;

  /// Every execution of a request block in the last run, oldest first (a loop runs its blocks many times).
  late final StateMap<String, List<StepRun>> history;

  /// Everything that happened in the last run, in order, for the run log.
  late final StateList<RunEvent> events;

  bool _running = false;
  String? _current;
  bool _cancelled = false;
  bool _logProblemsOnly = false;
  bool _logExpanded = false;
  double _logHeight = 280;
  String? _expanded;
  String? _selected;

  bool get running => _running;
  set running(bool v) {
    _running = v;
    changed();
  }

  String? get current => _current;
  set current(String? v) {
    _current = v;
    changed();
  }

  bool get cancelled => _cancelled;
  set cancelled(bool v) {
    _cancelled = v;
    changed();
  }

  /// Run log: show only the entries that went wrong.
  bool get logProblemsOnly => _logProblemsOnly;
  set logProblemsOnly(bool v) {
    _logProblemsOnly = v;
    changed();
  }

  /// The run log is a bottom-docked panel: expanded or just its header bar, and how tall it is (dp).
  bool get logExpanded => _logExpanded;
  set logExpanded(bool v) {
    _logExpanded = v;
    changed();
  }

  double get logHeight => _logHeight;
  set logHeight(double v) {
    _logHeight = v;
    changed();
  }

  /// Run log entries (by position) that are expanded to show details.
  late final StateMap<int, bool> logOpen;

  String? get expanded => _expanded;
  set expanded(String? v) {
    _expanded = v;
    changed();
  }

  /// The block whose configuration is open in the side pane (null = the first one).
  String? get selected => _selected;
  set selected(String? v) {
    _selected = v;
    changed();
  }

  bool get dirty => draft != saved;
  void update(Workflow Function(Workflow) f) {
    draft = f(draft);
  }

  void updateStep(String id, WorkflowStep Function(WorkflowStep) f) =>
      update((w) => w.copyWith(steps: w.steps.mapStep(id, f)));
}

/// Editable state of a collection tab: the settings draft, the page shown and the docs mode.
class CollectionSession extends SessionNotifier {
  CollectionSession(this.controller, this._name, NodeSection page) {
    controller.section = page;
    controller.addListener(changed);
  }

  final NodeSettingsController controller;
  String _name;
  bool _editingDocs = false;
  bool _previewingDocs = false;

  String get name => _name;
  set name(String v) {
    if (v == _name) return;
    _name = v;
    changed();
  }

  /// Page shown; [NodeSection.general] is the overview.
  NodeSection get page => controller.section;
  set page(NodeSection v) => controller.section = v;

  /// Whether the documentation block shows its editor instead of the rendered text.
  bool get editingDocs => _editingDocs;
  set editingDocs(bool v) {
    if (v == _editingDocs) return;
    _editingDocs = v;
    if (!v) _previewingDocs = false;
    changed();
  }

  /// Whether edit mode currently shows the rendered draft instead of the editor.
  bool get previewingDocs => _previewingDocs;
  set previewingDocs(bool v) {
    if (v == _previewingDocs) return;
    _previewingDocs = v;
    changed();
  }

  bool get dirty => controller.dirty;
}

/// Direction of a WebSocket log entry; `info` entries are connection events (opened, closed, errors).
enum WsDir { sent, received, info }

/// One entry of a WebSocket message log.
class WsMessage {
  WsMessage(this.dir, {this.text = '', this.bytes, this.error = false})
    : time = DateTime.now();

  final WsDir dir;
  final DateTime time;

  /// Text of a text message, or the description of an info entry.
  final String text;

  /// Payload of a binary message.
  final Uint8List? bytes;

  /// An info entry that reports a failure.
  final bool error;

  bool get isBinary => bytes != null;
  int get size => bytes?.length ?? utf8.encode(text).length;

  /// Hex dump of the first bytes of a binary message.
  String get hex {
    final b = bytes;
    if (b == null) return '';
    final n = b.length < 256 ? b.length : 256;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(b[i].toRadixString(16).padLeft(2, '0'));
      sb.write(i % 16 == 15 ? '\n' : ' ');
    }
    if (b.length > n) sb.write('…');
    return sb.toString().trimRight();
  }
}

enum WsStatus { disconnected, connecting, open, closing }

/// A WebSocket connection of a request tab: its state and the message log.
class WebSocketSession extends SessionNotifier {
  WebSocketSession() {
    messages = StateList<WsMessage>(changed);
  }

  /// Most entries kept in the log; the oldest are dropped beyond this.
  static const int maxMessages = 2000;

  late final StateList<WsMessage> messages;
  WsStatus _status = WsStatus.disconnected;
  String? _protocol;
  DateTime? _openedAt;
  String _filter = 'All';
  WsConnection? _conn;
  StreamSubscription<dynamic>? _sub;

  /// Bumped on every connect / disconnect so events of a stale connection are ignored.
  int _gen = 0;

  WsStatus get status => _status;
  bool get isOpen => _status == WsStatus.open;
  bool get busy =>
      _status == WsStatus.connecting || _status == WsStatus.closing;
  String? get protocol => _protocol;
  DateTime? get openedAt => _openedAt;

  /// Which log entries show: `All`, `Sent` or `Received`.
  String get filter => _filter;
  set filter(String v) {
    _filter = v;
    changed();
  }

  int get sentCount => messages.where((m) => m.dir == WsDir.sent).length;
  int get receivedCount =>
      messages.where((m) => m.dir == WsDir.received).length;

  void _setStatus(WsStatus v) {
    _status = v;
    changed();
  }

  void _log(WsMessage m) {
    messages.add(m);
    while (messages.length > maxMessages) {
      messages.removeAt(0);
    }
  }

  /// Opens the connection; logs the outcome. Does nothing when already connected or connecting.
  Future<void> connect(WsTarget target, AppSettings settings) async {
    if (_status != WsStatus.disconnected) return;
    final gen = ++_gen;
    _setStatus(WsStatus.connecting);
    _log(WsMessage(WsDir.info, text: 'Connecting to ${toWsUrl(target.url)}…'));
    try {
      final c = await WsConnection.connect(target, settings);
      if (gen != _gen) {
        unawaited(c.close(1001));
        return;
      }
      _conn = c;
      _protocol = c.protocol;
      _openedAt = DateTime.now();
      _log(
        WsMessage(
          WsDir.info,
          text: c.protocol == null || c.protocol!.isEmpty
              ? 'Connected'
              : 'Connected (subprotocol ${c.protocol})',
        ),
      );
      _sub = c.messages.listen(
        (d) {
          if (gen != _gen) return;
          _log(
            d is String
                ? WsMessage(WsDir.received, text: d)
                : WsMessage(
                    WsDir.received,
                    bytes: d is Uint8List
                        ? d
                        : Uint8List.fromList(d as List<int>),
                  ),
          );
        },
        onError: (Object e) {
          if (gen != _gen) return;
          _log(WsMessage(WsDir.info, text: '$e', error: true));
        },
        onDone: () {
          if (gen != _gen) return;
          final code = c.closeCode, reason = c.closeReason;
          _log(
            WsMessage(
              WsDir.info,
              text: code == null
                  ? 'Connection closed'
                  : 'Closed with code $code${reason == null || reason.isEmpty ? '' : ' ($reason)'}',
              error: code != null && code != 1000 && code != 1001,
            ),
          );
          _drop();
        },
      );
      _setStatus(WsStatus.open);
    } on WsConnectException catch (e) {
      if (gen != _gen) return;
      _log(WsMessage(WsDir.info, text: e.message, error: true));
      _drop();
    } catch (e) {
      if (gen != _gen) return;
      _log(WsMessage(WsDir.info, text: '$e', error: true));
      _drop();
    }
  }

  void _drop() {
    _sub?.cancel();
    _sub = null;
    _conn = null;
    _protocol = null;
    _openedAt = null;
    _setStatus(WsStatus.disconnected);
  }

  /// Sends a text message; false when not connected.
  bool send(String text) {
    final c = _conn;
    if (c == null || _status != WsStatus.open) return false;
    try {
      c.sendText(text);
    } catch (e) {
      _log(WsMessage(WsDir.info, text: 'Send failed: $e', error: true));
      return false;
    }
    _log(WsMessage(WsDir.sent, text: text));
    return true;
  }

  /// Closes the connection normally; safe to call when not connected.
  Future<void> disconnect() async {
    final c = _conn;
    if (c == null) {
      // Abandon a connect that is still in flight.
      if (_status == WsStatus.connecting) {
        _gen++;
        _log(WsMessage(WsDir.info, text: 'Cancelled'));
        _drop();
      }
      return;
    }
    final gen = _gen;
    _setStatus(WsStatus.closing);
    try {
      await c.close();
    } catch (_) {}
    if (gen != _gen) return;
    _gen++;
    _log(WsMessage(WsDir.info, text: 'Disconnected'));
    _drop();
  }

  /// Logs a failure that happened before a connection could be attempted.
  void fail(String message) =>
      _log(WsMessage(WsDir.info, text: message, error: true));

  void clear() => messages.clear();

  @override
  void dispose() {
    _gen++;
    final c = _conn;
    _conn = null;
    // Close with a code and let the stream finish on its own: cancelling the subscription would drop the socket
    // before the close frame is sent. Its events are ignored because the generation moved on.
    if (c != null) unawaited(c.close(1001).catchError((_) {}));
    _sub = null;
    super.dispose();
  }
}

/// Editable state of a request tab.
class RequestTab extends SessionNotifier {
  RequestTab({
    required this.id,
    required this.collectionPath,
    required this._filePath,
    required ApiRequest req,
    this.runner,
    this.workflow,
    this.collection,
    this.ws,
  }) : _draft = req,
       _saved = req {
    responses = StateList<ExecResult>(changed);
    runner?.onChange = changed;
    workflow?.onChange = changed;
    collection?.onChange = changed;
    ws?.onChange = changed;
  }

  final int id;
  final String collectionPath;
  final RunnerSession? runner;
  final WorkflowSession? workflow;
  final CollectionSession? collection;

  /// The WebSocket connection of a WebSocket request (null for HTTP requests).
  final WebSocketSession? ws;

  bool get isRequest =>
      runner == null && workflow == null && collection == null;
  String get title => collection?.name ?? workflow?.draft.name ?? draft.name;

  String _filePath;
  ApiRequest _draft;
  ApiRequest _saved;
  ExecResult? _result;
  bool _sending = false;
  String _reqTab = 'Params';
  String _resTab = 'Response';
  String _resView = 'Auto';
  bool? _resPreview;
  String _filter = '';
  String _scriptTab = 'Pre Request';
  String _varsTab = 'Pre Request';
  int _viewing = 0;
  bool _diff = false;
  String _find = '';

  // GraphQL: the introspected schema (session only) and the docs panel state.
  GqlSchema? _gqlSchema;
  bool _gqlLoading = false;
  String? _gqlError;

  /// Bumped to abandon an in-flight send: a finished send applies only if its generation is still current.
  int sendGen = 0;

  GqlSchema? get gqlSchema => _gqlSchema;
  set gqlSchema(GqlSchema? v) {
    _gqlSchema = v;
    changed();
  }

  bool get gqlLoading => _gqlLoading;
  set gqlLoading(bool v) {
    _gqlLoading = v;
    changed();
  }

  String? get gqlError => _gqlError;
  set gqlError(String? v) {
    _gqlError = v;
    changed();
  }

  String get filePath => _filePath;
  set filePath(String v) {
    _filePath = v;
    changed();
  }

  ApiRequest get draft => _draft;
  set draft(ApiRequest v) {
    _draft = v;
    changed();
  }

  ApiRequest get saved => _saved;
  set saved(ApiRequest v) {
    _saved = v;
    changed();
  }

  ExecResult? get result => _result;
  set result(ExecResult? v) {
    _result = v;
    changed();
  }

  bool get sending => _sending;
  set sending(bool v) {
    _sending = v;
    changed();
  }

  String get reqTab => _reqTab;
  set reqTab(String v) {
    _reqTab = v;
    changed();
  }

  String get resTab => _resTab;
  set resTab(String v) {
    _resTab = v;
    changed();
  }

  String get resView => _resView;
  set resView(String v) {
    _resView = v;
    changed();
  }

  bool? get resPreview => _resPreview;
  set resPreview(bool? v) {
    _resPreview = v;
    changed();
  }

  String get filter => _filter;
  set filter(String v) {
    _filter = v;
    changed();
  }

  String get scriptTab => _scriptTab;
  set scriptTab(String v) {
    _scriptTab = v;
    changed();
  }

  String get varsTab => _varsTab;
  set varsTab(String v) {
    _varsTab = v;
    changed();
  }

  late final StateList<ExecResult> responses;
  int get viewing => _viewing;
  set viewing(int v) {
    _viewing = v;
    changed();
  }

  bool get diff => _diff;
  set diff(bool v) {
    _diff = v;
    changed();
  }

  String get find => _find;
  set find(String v) {
    _find = v;
    changed();
  }

  /// Abandons the in-flight send.
  void cancelJob() {
    sendGen++;
  }

  /// Frees what the tab holds (in-flight send, open connection); call when it is closed.
  void release() {
    cancelJob();
    ws?.dispose();
  }

  void push(ExecResult r) {
    responses.insert(0, r);
    while (responses.length > 10) {
      responses.removeAt(responses.length - 1);
    }
    viewing = 0;
    result = r;
  }

  bool get dirty => collection?.dirty ?? workflow?.dirty ?? draft != saved;
}

/// Which menu of the in-window menu bar is open, and where things are on screen (so a click elsewhere can close it).
class TitleMenuState extends ChangeNotifier {
  String? _open;
  String? get open => _open;
  set open(String? v) {
    _open = v;
    notifyListeners();
  }

  final Map<String, Rect> anchors = {};
  Rect? panel;
  void close() {
    open = null;
  }
}
