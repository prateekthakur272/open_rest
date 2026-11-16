import 'dart:collection';
import 'dart:ui' show Rect, VoidCallback;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:open_rest/core/graphql/graphql.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
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
  }) : _draft = req,
       _saved = req {
    responses = StateList<ExecResult>(changed);
    runner?.onChange = changed;
    workflow?.onChange = changed;
    collection?.onChange = changed;
  }

  final int id;
  final String collectionPath;
  final RunnerSession? runner;
  final WorkflowSession? workflow;
  final CollectionSession? collection;

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
