import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:open_rest/app/modal.dart';
import 'package:open_rest/app/sessions.dart';
import 'package:open_rest/core/codegen/code_gen.dart';
import 'package:open_rest/core/graphql/graphql.dart';
import 'package:open_rest/core/http/generated_headers.dart';
import 'package:open_rest/core/logging/log.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/core/ws/ws_client.dart';
import 'package:open_rest/features/dialogs/node_settings_controller.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/utils/json.dart';
import 'package:path/path.dart' as p;

import 'package:open_rest/app/app_state_workflows.dart';

export 'package:open_rest/app/app_state_environments.dart';
export 'package:open_rest/app/app_state_sidebar.dart';
export 'package:open_rest/app/app_state_transfer.dart';
export 'package:open_rest/app/app_state_workflows.dart';
export 'package:open_rest/app/modal.dart';
export 'package:open_rest/app/sessions.dart';

const Set<String> _sidebarTabs = {'Collections', 'History'};

/// Success value or failure.
class Result<R> {
  const Result._(this.value, this.error, this.isSuccess);
  factory Result.success(R v) => Result._(v, null, true);
  factory Result.failure(Object e) => Result._(null, e, false);

  final R? value;
  final Object? error;
  final bool isSuccess;
  bool get isFailure => !isSuccess;

  R? getOrNull() => value;
  Object? exceptionOrNull() => error;
  X fold<X>(X Function(R) onSuccess, X Function(Object) onFailure) =>
      isSuccess ? onSuccess(value as R) : onFailure(error!);
}

class _Require implements Exception {
  _Require(this.message);
  final String message;
  @override
  String toString() => message;
}

void require(bool ok, String Function() msg) {
  if (!ok) throw _Require(msg());
}

/// The human-readable message of a thrown error .
String errorText(Object e) {
  if (e is ArgumentError) return e.message?.toString() ?? e.toString();
  if (e is StateError) return e.message;
  if (e is FormatException) return e.message;
  if (e is FileSystemException) {
    return e.message.isNotEmpty
        ? '${e.message}${e.path != null ? ": ${e.path}" : ""}'
        : e.toString();
  }
  var s = e.toString();
  for (final pre in const [
    'Exception: ',
    'Bad state: ',
    'Invalid argument(s): ',
    'Invalid argument: ',
  ]) {
    if (s.startsWith(pre)) {
      s = s.substring(pre.length);
      break;
    }
  }
  return s;
}

T? firstMatch<T>(Iterable<T> it, bool Function(T) test) {
  for (final x in it) {
    if (test(x)) return x;
  }
  return null;
}

/// True when `path` equals `dir` or is inside it.
bool isUnder(String path, String dir) => path == dir || p.isWithin(dir, path);

/// The single source of truth for the UI. Every field notifies listeners when set.
class AppState extends ChangeNotifier {
  AppState() {
    titleMenu.addListener(notifyListeners);
    _loadInitial();
  }

  final TitleMenuState titleMenu = TitleMenuState();

  AppSettings _settings = AppStore.loadSettings();
  AppSettings get settings => _settings;
  set settings(AppSettings v) {
    _settings = v;
    notifyListeners();
  }

  List<Collection> _collections = const [];
  List<Collection> get collections => _collections;
  set collections(List<Collection> v) {
    _collections = v;
    notifyListeners();
  }

  late final StateList<RequestTab> tabs = StateList<RequestTab>(
    notifyListeners,
  );

  int? _activeTabId;
  int? get activeTabId => _activeTabId;
  set activeTabId(int? v) {
    _activeTabId = v;
    notifyListeners();
  }

  late final StateMap<String, String> activeEnv = StateMap<String, String>(
    notifyListeners,
  );

  /// Global environments are shared by every collection; one can be active at a time.
  List<Environment> _globalEnvs = const [];
  List<Environment> get globalEnvs => _globalEnvs;
  set globalEnvs(List<Environment> v) {
    _globalEnvs = v;
    notifyListeners();
  }

  String? _activeGlobalEnv;
  String? get activeGlobalEnv => _activeGlobalEnv;
  set activeGlobalEnv(String? v) {
    _activeGlobalEnv = v;
    notifyListeners();
  }

  final Map<String, StateMap<String, dynamic>> _runtimes = {};

  Modal? _modal;
  Modal? get modal => _modal;
  set modal(Modal? v) {
    _modal = v;
    notifyListeners();
  }

  String? _toast;
  String? get toast => _toast;
  set toast(String? v) {
    _toast = v;
    notifyListeners();
  }

  late final StateMap<String, bool> expanded = StateMap<String, bool>(
    notifyListeners,
  );

  String? _selectedCollection;
  String? get selectedCollection => _selectedCollection;
  set selectedCollection(String? v) {
    _selectedCollection = v;
    notifyListeners();
  }

  String _sidebarFilter = '';
  String get sidebarFilter => _sidebarFilter;
  set sidebarFilter(String v) {
    _sidebarFilter = v;
    notifyListeners();
  }

  double _sidebarWidth = 0.22;
  double get sidebarWidth => _sidebarWidth;
  set sidebarWidth(double v) {
    _sidebarWidth = v;
    notifyListeners();
  }

  double _splitFraction = 0.45;
  double get splitFraction => _splitFraction;
  set splitFraction(double v) {
    _splitFraction = v;
    notifyListeners();
  }

  late final StateList<HistoryEntry> history = StateList<HistoryEntry>(
    notifyListeners,
  );

  String _sidebarTab = 'Collections';
  String get sidebarTab => _sidebarTab;
  set sidebarTab(String v) {
    _sidebarTab = v;
    notifyListeners();
  }

  String? _renaming;
  String? get renaming => _renaming;
  set renaming(String? v) {
    _renaming = v;
    notifyListeners();
  }

  String? _cursor;
  String? get cursor => _cursor;
  set cursor(String? v) {
    _cursor = v;
    notifyListeners();
  }

  bool _cursorVisible = false;
  bool get cursorVisible => _cursorVisible;
  set cursorVisible(bool v) {
    _cursorVisible = v;
    notifyListeners();
  }

  bool _sidebarVisible = true;
  bool get sidebarVisible => _sidebarVisible;
  set sidebarVisible(bool v) {
    _sidebarVisible = v;
    notifyListeners();
  }

  /// Which section Preferences should open on (set by menu items such as Help > Keyboard Shortcuts).
  String? _prefsSection;
  String? get prefsSection => _prefsSection;
  set prefsSection(String? v) {
    _prefsSection = v;
    notifyListeners();
  }

  final FocusNode urlFocus = FocusNode();
  int nextId = 1;
  Timer? _toastTimer;

  void _loadInitial() {
    final saved = AppStore.loadState();
    for (final c in saved.collections.where(Collections.isCollection)) {
      Log.orElse(
        'app',
        'Cannot open saved collection $c',
        null,
        () => addCollection(c, false),
      );
    }
    saved.envs.forEach((k, v) => activeEnv[k] = v);
    globalEnvs = AppStore.loadGlobalEnvs();
    activeGlobalEnv = saved.globalEnv;
    sidebarWidth = saved.sidebarWidth.clamp(0.12, 0.45).toDouble();
    splitFraction = saved.splitFraction.clamp(0.12, 0.88).toDouble();
    sidebarVisible = saved.sidebarVisible;
    _restoreSidebar(saved);
    for (final k in saved.tabs) {
      Log.orElse('app', 'Cannot restore tab $k', null, () => _restoreTab(k));
    }
    for (final t in tabs) {
      final ui = saved.tabState[tabKey(t)];
      if (ui != null) _applyTabUi(t, ui);
    }
    final a = saved.activeTab;
    if (a != null) {
      final t = firstMatch(tabs, (t) => tabKey(t) == a);
      if (t != null) activeTabId = t.id;
    }
  }

  /// The UI state worth keeping across launches: which sub-tab / page each tab shows.
  Map<String, String> _tabUi(RequestTab t) {
    if (t.collection != null) return {'page': t.collection!.page.name};
    if (t.runner != null || t.workflow != null) return const {};
    return {
      'req': t.reqTab,
      'res': t.resTab,
      'script': t.scriptTab,
      'vars': t.varsTab,
    };
  }

  void _applyTabUi(RequestTab t, Map<String, String> ui) {
    final page = ui['page'];
    if (t.collection != null && page != null) {
      for (final s in NodeSection.values) {
        if (s.name == page) t.collection!.page = s;
      }
    }
    if (t.isRequest) {
      if (ui['req'] != null) t.reqTab = ui['req']!;
      if (ui['res'] != null) t.resTab = ui['res']!;
      if (ui['script'] != null) t.scriptTab = ui['script']!;
      if (ui['vars'] != null) t.varsTab = ui['vars']!;
    }
  }

  static const _collectionTab = 'collection:';
  static const _runnerTab = 'runner:';
  static const _workflowTab = 'workflow:';

  /// Stable identity of a tab across launches: a request's file path, or a typed key for the other kinds.
  String tabKey(RequestTab t) {
    if (t.collection != null) return '$_collectionTab${t.collectionPath}';
    if (t.runner != null) {
      return '$_runnerTab${t.collectionPath}\n${t.runner!.folder ?? ''}';
    }
    if (t.workflow != null) {
      return '$_workflowTab${t.collectionPath}\n${t.workflow!.saved.name}';
    }
    return t.filePath;
  }

  void _restoreTab(String k) {
    (String, String) split(String v) {
      final i = v.indexOf('\n');
      return i < 0 ? (v, '') : (v.substring(0, i), v.substring(i + 1));
    }

    if (k.startsWith(_collectionTab)) {
      openCollectionTab(k.substring(_collectionTab.length));
    } else if (k.startsWith(_runnerTab)) {
      final (col, folder) = split(k.substring(_runnerTab.length));
      openRunner(col, folder.isEmpty ? null : folder);
    } else if (k.startsWith(_workflowTab)) {
      final (col, name) = split(k.substring(_workflowTab.length));
      openWorkflow(col, name);
    } else {
      final c = firstMatch(collections, (c) => isUnder(k, c.path));
      final r = c?.findRequest(k);
      if (c != null && r != null) openRequest(c.path, r);
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    urlFocus.dispose();
    super.dispose();
  }

  RequestTab? get activeTab => firstMatch(tabs, (t) => t.id == activeTabId);

  Collection? get currentCollection {
    final t = activeTab;
    if (t != null) {
      final c = collection(t.collectionPath);
      if (c != null) return c;
    }
    final s = selectedCollection;
    if (s != null) {
      final c = collection(s);
      if (c != null) return c;
    }
    return collections.isEmpty ? null : collections.first;
  }

  Collection? collection(String path) =>
      firstMatch(collections, (c) => c.path == path);

  StateMap<String, dynamic> runtime(String col) => _runtimes.putIfAbsent(
    col,
    () => StateMap<String, dynamic>(notifyListeners),
  );

  /// The active global environment, or null when none is selected (or the selection no longer exists).
  Environment? globalEnv() =>
      firstMatch(globalEnvs, (e) => e.name == activeGlobalEnv);
  String? globalEnvName() => globalEnv()?.name;

  RunCtx runCtx(Collection col) =>
      RunCtx(col, envName(col.path), runtime(col.path), settings, globalEnv());

  String? envName(String col) {
    final n = activeEnv[col];
    if (n == null) return null;
    return collection(col)?.environments.any((e) => e.name == n) == true
        ? n
        : null;
  }

  void showToast(String msg) {
    toast = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 3500), () => toast = null);
  }

  void guard(void Function() block) {
    try {
      block();
    } catch (e, st) {
      Log.warning('app', 'Operation failed: ${errorText(e)}', e, st);
      showToast(errorText(e));
    }
  }

  /// Re-applies the side pane: its tab, which folders were open and the selected collection (entries for paths that no longer exist are dropped).
  void _restoreSidebar(SavedState saved) {
    final tab = saved.sidebarTab;
    if (tab != null && _sidebarTabs.contains(tab)) sidebarTab = tab;
    final open = saved.expandedFolders;
    if (open != null) {
      expanded.clear();
      for (final path in open) {
        if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
          expanded[path] = true;
        }
      }
    }
    final sel = saved.selectedCollection;
    if (sel != null && collections.any((c) => c.path == sel)) {
      selectedCollection = sel;
    }
  }

  /// Everything the side pane shows or the layout remembers; a change to any of it is saved shortly after.
  List<Object?> layoutSnapshot() => [
    sidebarWidth,
    splitFraction,
    sidebarVisible,
    sidebarTab,
    selectedCollection,
    {
      for (final e in expanded.entries)
        if (e.value) e.key,
    },
    // Open tabs (in order) and the active one.
    tabs.map(tabKey).join('\u0001'),
    activeTab == null ? null : tabKey(activeTab!),
    // Which sub-tab / page each open tab shows.
    tabs.map((t) => _tabUi(t).values.join('|')).join('\u0001'),
  ];

  void persist() {
    AppStore.saveState(
      SavedState(
        collections: collections.map((c) => c.path).toList(),
        envs: Map<String, String>.from(activeEnv),
        tabs: tabs.map(tabKey).toList(),
        activeTab: activeTab == null ? null : tabKey(activeTab!),
        sidebarWidth: sidebarWidth,
        splitFraction: splitFraction,
        sidebarVisible: sidebarVisible,
        globalEnv: activeGlobalEnv,
        sidebarTab: sidebarTab,
        expandedFolders: [
          for (final e in expanded.entries)
            if (e.value) e.key,
        ],
        selectedCollection: selectedCollection,
        tabState: {
          for (final t in tabs)
            if (_tabUi(t).isNotEmpty) tabKey(t): _tabUi(t),
        },
      ),
    );
  }

  /// The headers sent for [tab]'s request besides the ones written on it (auth, body type, User-Agent, cookies ...).
  /// Empty when the collection is gone or the request cannot be resolved.
  List<GeneratedHeader> generatedHeadersFor(RequestTab tab) {
    final col = collection(tab.collectionPath);
    if (col == null) return const [];
    try {
      return Execution(
        runCtx(col),
        RequestNode(
          path: tab.filePath,
          name: tab.draft.name,
          request: tab.draft,
        ),
      ).generatedHeaders(settings);
    } catch (_) {
      return const [];
    }
  }

  void updateSettings(AppSettings s) {
    settings = s;
    AppStore.saveSettings(s);
  }

  /// Closes the first-run walkthrough, remembers that it was seen (the settings file now exists) and optionally opens what the user picked next.
  void finishOnboarding([Modal? next]) {
    AppStore.saveSettings(settings);
    modal = next;
  }

  RequestTab newTab(
    String col,
    String file,
    ApiRequest req, {
    RunnerSession? runner,
    WorkflowSession? workflow,
    CollectionSession? collection,
  }) {
    final t = RequestTab(
      id: nextId++,
      collectionPath: col,
      filePath: file,
      req: req,
      runner: runner,
      workflow: workflow,
      collection: collection,
      ws:
          runner == null &&
              workflow == null &&
              collection == null &&
              req.kind == RequestKind.ws
          ? WebSocketSession()
          : null,
    );
    // A GraphQL request is all about its query: open on the Body tab instead of Params.
    if (t.isRequest && req.bodyMode == BodyMode.Graphql) t.reqTab = 'Body';
    // A WebSocket request opens on its message editor.
    if (t.ws != null) t.reqTab = 'Message';
    t.onChange = notifyListeners;
    return t;
  }

  void addCollection(String path, [bool persist = true]) {
    if (collections.any((c) => c.path == path)) {
      showToast('Collection already open');
      return;
    }
    collections = [...collections, Collections.load(path)];
    expanded[path] = true;
    selectedCollection = path;
    if (persist) this.persist();
  }

  void openCollection(String path) => guard(() {
    require(
      Collections.isCollection(path),
      () => 'Not a collection (no openrest.yaml found in ${p.basename(path)})',
    );
    addCollection(path);
  });

  void createCollection(String parent, String name) => guard(() {
    require(name.trim().isNotEmpty, () => 'Name required');
    final dir = Collections.create(parent, name);
    addCollection(dir);
  });

  void closeCollection(String path) {
    for (final t in tabs.where((t) => t.collectionPath == path)) {
      t.release();
    }
    tabs.removeWhere((t) => t.collectionPath == path);
    if (activeTab == null) activeTabId = tabs.isEmpty ? null : tabs.last.id;
    collections = collections.where((c) => c.path != path).toList();
    persist();
  }

  void reload(String path) {
    final i = collections.indexWhere((c) => c.path == path);
    if (i >= 0) {
      final c = Collections.load(path);
      collections = List<Collection>.of(collections)..[i] = c;
      for (final t in tabs) {
        final cs = t.collection;
        if (cs != null && t.collectionPath == path) {
          cs.name = c.name;
          cs.controller.rebase();
        }
      }
    }
  }

  void reloadAll() {
    for (final path in collections.map((c) => c.path).toList()) {
      Log.orElse(
        'app',
        'Cannot reload collection $path',
        null,
        () => reload(path),
      );
    }
  }

  void openRequest(String col, RequestNode node) {
    final ex = firstMatch(tabs, (t) => t.filePath == node.path);
    if (ex != null) {
      activeTabId = ex.id;
      return;
    }
    final t = newTab(col, node.path, node.request);
    tabs.add(t);
    activeTabId = t.id;
    selectedCollection = col;
    persist();
  }

  /// The open collection tab of [path], if any.
  RequestTab? collectionTab(String path) =>
      firstMatch(tabs, (t) => t.collection != null && t.collectionPath == path);

  /// Opens (or focuses) the overview / settings tab of a collection, optionally on [page].
  void openCollectionTab(String path, {NodeSection? page}) {
    final c = collection(path);
    if (c == null) return;
    final ex = collectionTab(path);
    if (ex != null) {
      if (page != null) ex.collection!.page = page;
      activeTabId = ex.id;
      selectedCollection = path;
      return;
    }
    final t = newTab(
      path,
      path,
      ApiRequest(name: c.name),
      collection: CollectionSession(
        NodeSettingsController(this, path, path),
        c.name,
        page ?? NodeSection.general,
      ),
    );
    tabs.add(t);
    activeTabId = t.id;
    selectedCollection = path;
  }

  /// Runner nodes for a collection (folder == null) or one folder, in tree order.
  List<RequestNode> runnerRequests(Collection col, String? folder) {
    FolderNode? find(List<Node> nodes) {
      for (final n in nodes) {
        if (n is FolderNode) {
          final r = n.path == folder ? n : find(n.children);
          if (r != null) return r;
        }
      }
      return null;
    }

    return folder == null
        ? Runner.flatten(col.children)
        : Runner.flatten(find(col.children)?.children ?? const []);
  }

  void openRunner(String col, String? folder) {
    final c = collection(col);
    if (c == null) return;
    final ex = firstMatch(
      tabs,
      (t) =>
          t.runner != null &&
          t.collectionPath == col &&
          t.runner!.folder == folder,
    );
    if (ex != null) {
      activeTabId = ex.id;
      return;
    }
    final label = folder == null ? c.name : p.basename(folder);
    final t = newTab(
      col,
      folder ?? col,
      ApiRequest(name: 'Runner: $label'),
      runner: RunnerSession(folder, runnerRequests(c, folder)),
    );
    tabs.add(t);
    activeTabId = t.id;
    selectedCollection = col;
  }

  void closeTab(int id, [bool force = false]) {
    final t = firstMatch(tabs, (t) => t.id == id);
    if (t == null) return;
    t.runner?.cancelled = true;
    t.workflow?.cancelled = true;
    if (t.dirty && !force) {
      modal = ModalConfirm(
        title: 'Unsaved changes',
        message: '"${t.title}" has unsaved changes.',
        confirm: 'Discard',
        onOk: () => closeTab(id, true),
      );
      return;
    }
    t.release();
    final idx = tabs.indexOf(t);
    tabs.remove(t);
    if (activeTabId == id) {
      final ni = math.min(idx, tabs.length - 1);
      activeTabId = (ni >= 0 && ni < tabs.length) ? tabs[ni].id : null;
    }
    persist();
  }

  void update(RequestTab tab, ApiRequest Function(ApiRequest) f) {
    tab.draft = f(tab.draft);
  }

  void save(RequestTab tab) => guard(() {
    if (tab.workflow != null) {
      saveWorkflow(tab);
      return;
    }
    if (tab.collection != null) {
      tab.collection!.controller.save();
      return;
    }
    if (tab.runner != null) return;
    Collections.saveRequest(tab.filePath, tab.draft);
    tab.saved = tab.draft;
    reload(tab.collectionPath);
  });

  void saveAll() {
    for (final t in tabs.where((t) => t.dirty).toList()) {
      save(t);
    }
  }

  /// Opens the WebSocket of [tab] with its resolved URL, headers and auth.
  Future<void> connectWs(RequestTab tab) async {
    final ws = tab.ws;
    final col = collection(tab.collectionPath);
    if (ws == null || col == null || ws.status != WsStatus.disconnected) return;
    if (settings.autoSave && tab.dirty) save(tab);
    final d = tab.draft;
    WsTarget target;
    try {
      final ex = Execution(
        runCtx(col),
        RequestNode(
          path: tab.filePath,
          name: d.name,
          request: d.copyWith(method: 'GET', bodyMode: BodyMode.None),
        ),
      );
      final prepared = await ex.prepare();
      target = WsTarget(
        url: prepared.url,
        headers: prepared.headers,
        protocols: parseProtocols(ex.interp(d.wsProtocols)),
        tls: prepared.tls,
        timeoutMs: prepared.timeoutMs,
      );
    } on FormatException {
      ws.fail('Invalid URL: use ws://host/path or wss://host/path');
      return;
    } catch (e) {
      ws.fail(errorText(e));
      return;
    }
    await ws.connect(target, settings);
  }

  /// Sends the composer message of [tab] over its open connection.
  bool sendWs(RequestTab tab) {
    final ws = tab.ws;
    final col = collection(tab.collectionPath);
    if (ws == null || col == null || !ws.isOpen) return false;
    final d = tab.draft;
    final text = Execution(
      runCtx(col),
      RequestNode(path: tab.filePath, name: d.name, request: d),
    ).interp(d.wsMessage);
    if (text.isEmpty) return false;
    return ws.send(text);
  }

  Future<void> send(RequestTab tab) async {
    if (tab.ws != null) {
      // Enter in the URL bar / the send shortcut: connect, or send when already connected.
      if (tab.ws!.isOpen) {
        sendWs(tab);
      } else {
        await connectWs(tab);
      }
      return;
    }
    if (tab.sending || !tab.isRequest) return;
    final col = collection(tab.collectionPath);
    if (col == null) return;
    if (settings.autoSave && tab.dirty) save(tab);
    tab.sending = true;
    tab.result = null;
    tab.resTab = 'Response';
    final gen = ++tab.sendGen;
    final node = RequestNode(
      path: tab.filePath,
      name: tab.draft.name,
      request: tab.draft,
    );
    final rc = runCtx(col);
    ExecResult r;
    try {
      r = await Execution(rc, node).run();
    } catch (e) {
      r = ExecResult(error: errorText(e));
    }
    if (tab.sendGen == gen) {
      tab.push(r);
      tab.sending = false;
      history.insert(
        0,
        HistoryEntry(
          time: DateTime.now().millisecondsSinceEpoch,
          collection: col.path,
          file: tab.filePath,
          name: tab.draft.name,
          method: tab.draft.method,
          url: r.request?.url ?? tab.draft.url,
          status: r.response?.status ?? 0,
          timeMs: r.response?.timeMs ?? 0,
          error: r.error ?? r.response?.error,
          result: r,
        ),
      );
      while (history.length > 200) {
        history.removeAt(history.length - 1);
      }
    }
  }

  /// Fetches the GraphQL schema of [tab]'s endpoint with an introspection query (same auth, headers and variables as the request).
  Future<void> fetchGraphqlSchema(RequestTab tab) async {
    final col = collection(tab.collectionPath);
    if (col == null || tab.gqlLoading) return;
    tab.gqlLoading = true;
    tab.gqlError = null;
    final d = tab.draft;
    final probe = d.copyWith(
      method: 'POST',
      bodyMode: BodyMode.Graphql,
      bodyGraphql: introspectionQuery,
      bodyGraphqlVars: '',
      operationName: 'IntrospectionQuery',
      preScript: '',
      postScript: '',
      tests: '',
      assertions: const [],
      postVars: const [],
    );
    try {
      final r = await Execution(
        runCtx(col),
        RequestNode(path: tab.filePath, name: d.name, request: probe),
      ).run();
      final res = r.response;
      if (r.error != null || res == null) {
        tab.gqlError = r.error ?? 'No response';
      } else {
        final body = Json.tryParse(res.text);
        final schema = GqlSchema.parse(body);
        if (schema != null) {
          tab.gqlSchema = schema;
        } else {
          final errs = graphqlErrors(body);
          tab.gqlError = errs.isNotEmpty
              ? errs.first
              : 'HTTP ${res.status}: not a GraphQL schema response (introspection may be disabled)';
        }
      }
    } catch (e) {
      tab.gqlError = errorText(e);
    } finally {
      tab.gqlLoading = false;
    }
  }

  void cancel(RequestTab tab) {
    tab.cancelJob();
    tab.sending = false;
    tab.push(const ExecResult(error: 'Request cancelled'));
  }

  /// Build the prepared request for code generation without running scripts.
  Future<Result<PreparedRequest>> prepareFor(RequestTab tab) async {
    try {
      require(tab.isRequest, () => 'Not a request tab');
      final col = collection(tab.collectionPath);
      if (col == null) throw StateError('Collection not found');
      final rc = runCtx(col);
      return Result.success(
        await Execution(
          rc,
          RequestNode(
            path: tab.filePath,
            name: tab.draft.name,
            request: tab.draft,
          ),
        ).prepare(),
      );
    } catch (e) {
      return Result.failure(e);
    }
  }

  /// name -> (value, source) for the autocomplete menu; later puts win, matching variable precedence.
  Map<String, (String, String)> varInfo(RequestTab? tab) {
    final col =
        (tab != null ? collection(tab.collectionPath) : null) ??
        currentCollection;
    if (col == null) return const {};
    final out = <String, (String, String)>{};
    final g = globalEnv();
    if (g != null) {
      for (final v in g.vars.where((v) => v.enabled)) {
        out[v.name] = (
          g.secrets.contains(v.name) ? '••••••' : v.value,
          'global',
        );
      }
    }
    for (final v in col.config.preVars.where((v) => v.enabled)) {
      out[v.name] = (v.value, 'collection');
    }
    final en = envName(col.path);
    if (en != null) {
      final e = firstMatch(col.environments, (e) => e.name == en);
      if (e != null) {
        for (final v in e.vars.where((v) => v.enabled)) {
          out[v.name] = (
            e.secrets.contains(v.name) ? '••••••' : v.value,
            'env',
          );
        }
      }
    }
    if (tab != null) {
      for (final f in col.ancestorFolders(tab.filePath)) {
        for (final v in f.config.preVars.where((v) => v.enabled)) {
          out[v.name] = (v.value, 'folder');
        }
      }
      for (final v in tab.draft.preVars.where((v) => v.enabled)) {
        out[v.name] = (v.value, 'request');
      }
      for (final v in tab.draft.pathParams) {
        out[v.name] = (v.value, 'path');
      }
    }
    runtime(col.path).forEach((k, v) {
      out[k] = (v is String ? v : Json.stringify(v), 'runtime');
    });
    return out;
  }

  Set<String> knownVars(RequestTab? tab) {
    final col =
        (tab != null ? collection(tab.collectionPath) : null) ??
        currentCollection;
    if (col == null) return const {};
    final out = <String>{};
    final g = globalEnv();
    if (g != null) {
      for (final v in g.vars) {
        out.add(v.name);
      }
    }
    final en = envName(col.path);
    if (en != null) {
      final e = firstMatch(col.environments, (e) => e.name == en);
      if (e != null) {
        for (final v in e.vars) {
          out.add(v.name);
        }
      }
    }
    for (final v in col.config.preVars) {
      out.add(v.name);
    }
    if (tab != null) {
      for (final f in col.ancestorFolders(tab.filePath)) {
        for (final v in f.config.preVars) {
          out.add(v.name);
        }
      }
      for (final v in tab.draft.preVars) {
        out.add(v.name);
      }
      for (final v in tab.draft.pathParams) {
        out.add(v.name);
      }
    }
    out.addAll(runtime(col.path).keys);
    return out;
  }

  void nextTab(int delta) {
    if (tabs.isEmpty) return;
    final i = math.max(0, tabs.indexWhere((t) => t.id == activeTabId));
    activeTabId = tabs[(i + delta + tabs.length) % tabs.length].id;
  }

  void moveTab(int from, int to) {
    if (from < 0 ||
        from >= tabs.length ||
        to < 0 ||
        to >= tabs.length ||
        from == to) {
      return;
    }
    tabs.insert(to, tabs.removeAt(from));
    persist();
  }

  void gotoTab(int index) {
    if (index >= 0 && index < tabs.length) activeTabId = tabs[index].id;
  }

  void closeOthers(int id) {
    for (final t in tabs.where((t) => t.id != id && !t.dirty).toList()) {
      closeTab(t.id, true);
    }
  }

  void closeAll() {
    for (final t in tabs.toList().where((t) => !t.dirty)) {
      closeTab(t.id, true);
    }
  }

  Future<void> copyCurl(RequestTab tab) async {
    final r = await prepareFor(tab);
    r.fold(
      (pr) {
        Platform.copy(CodeGen.generate('cURL', pr));
        showToast('Copied as cURL');
      },
      (e) => showToast(
        errorText(e).isEmpty ? 'Could not build request' : errorText(e),
      ),
    );
  }

  void collapseAll() {
    expanded.clear();
  }

  void expandAll() {
    void walk(List<Node> nodes) {
      for (final n in nodes) {
        if (n is FolderNode) {
          expanded[n.path] = true;
          walk(n.children);
        }
      }
    }

    for (final c in collections) {
      expanded[c.path] = true;
      walk(c.children);
    }
  }

  void openHistory(HistoryEntry e) {
    final req = collection(e.collection)?.findRequest(e.file);
    if (req == null) {
      showToast('Request no longer exists');
      return;
    }
    openRequest(e.collection, req);
    final t = activeTab;
    if (t != null) {
      t.push(e.result);
      t.resTab = 'Response';
    }
  }

  void zoom(int delta) {
    final n = delta == 0 ? 13 : (settings.fontSize + delta).clamp(10, 20);
    updateSettings(settings.copyWith(fontSize: n));
    showToast('Zoom ${n * 100 ~/ 13}%');
  }

  String? resolveUrl(RequestTab tab) {
    try {
      final col = collection(tab.collectionPath);
      if (col == null) return null;
      return Execution(
        runCtx(col),
        RequestNode(
          path: tab.filePath,
          name: tab.draft.name,
          request: tab.draft,
        ),
      ).buildUrl(tab.draft.url);
    } catch (_) {
      return null;
    }
  }

  void toggleLayout() => updateSettings(
    settings.copyWith(verticalLayout: !settings.verticalLayout),
  );
}

/// Provides the [AppState] to the tree; `AppScope.of(context)` subscribes to every change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'No AppScope above this context');
    return s!.notifier!;
  }

  /// The state without subscribing to changes.
  static AppState read(BuildContext context) {
    final s = context.getInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'No AppScope above this context');
    return s!.notifier!;
  }

  static AppState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
}
