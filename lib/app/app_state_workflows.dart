import 'dart:io';

import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/runner.dart';
import 'package:open_rest/core/run/workflow_model.dart';
import 'package:open_rest/core/run/workflow_run_models.dart';
import 'package:open_rest/core/run/workflow_storage.dart';
import 'package:open_rest/core/run/workflow_tree.dart';
import 'package:open_rest/core/run/workflow_engine.dart';
import 'package:open_rest/core/storage/storage.dart';

// Workflow tabs: creating, editing, running and saving workflows. Extensions of [AppState] so that class stays the single owner of state.

extension AppStateWorkflows on AppState {
  RequestTab? workflowTab(String col, String name) => firstMatch(
    tabs,
    (t) =>
        t.workflow != null &&
        t.collectionPath == col &&
        t.workflow!.saved.name == name,
  );

  void openWorkflow(String col, String name) {
    final ex = workflowTab(col, name);
    if (ex != null) {
      activeTabId = ex.id;
      return;
    }
    final c = collection(col);
    final wf = c == null
        ? null
        : firstMatch(c.workflows, (w) => w.name == name);
    if (wf == null) return;
    final t = newTab(
      col,
      WorkflowStore.file(col, name),
      ApiRequest(name: name),
      workflow: WorkflowSession(wf),
    );
    tabs.add(t);
    activeTabId = t.id;
    selectedCollection = col;
  }

  void promptNewWorkflow(String col) {
    modal = ModalPrompt(
      title: 'New Workflow',
      initial: '',
      label: 'Workflow name',
      confirm: 'Create',
      onOk: (n) => guard(() {
        final name = n.trim();
        require(name.isNotEmpty, () => 'Name required');
        require(
          !File(WorkflowStore.file(col, name)).existsSync(),
          () => "A workflow named '$name' already exists",
        );
        WorkflowStore.save(col, Workflow(name: name));
        reload(col);
        expanded[col] = true;
        openWorkflow(col, name);
      }),
    );
  }

  void saveWorkflow(RequestTab tab) => guard(() {
    final ws = tab.workflow;
    if (ws == null) return;
    final w = ws.draft.copyWith(name: ws.draft.name.trim());
    require(w.name.isNotEmpty, () => 'Workflow name required');
    WorkflowStore.save(tab.collectionPath, w, ws.saved.name);
    ws.draft = w;
    ws.saved = w;
    tab.filePath = WorkflowStore.file(tab.collectionPath, w.name);
    reload(tab.collectionPath);
  });

  void promptRenameWorkflow(String col, String name) {
    modal = ModalPrompt(
      title: 'Rename Workflow',
      initial: name,
      label: 'Workflow name',
      confirm: 'Rename',
      onOk: (n) => guard(() {
        final neu = n.trim();
        require(neu.isNotEmpty, () => 'Name required');
        final c = collection(col);
        final wf = c == null
            ? null
            : firstMatch(c.workflows, (w) => w.name == name);
        if (wf == null) return;
        WorkflowStore.save(col, wf.copyWith(name: neu), name);
        final t = workflowTab(col, name);
        if (t != null) {
          final s = t.workflow!;
          s.draft = s.draft.copyWith(name: neu);
          s.saved = s.saved.copyWith(name: neu);
          t.filePath = WorkflowStore.file(col, neu);
        }
        reload(col);
      }),
    );
  }

  void cloneWorkflow(String col, String name) => guard(() {
    final c = collection(col);
    final wf = c == null
        ? null
        : firstMatch(c.workflows, (w) => w.name == name);
    if (wf == null) return;
    var n = '$name copy';
    var i = 2;
    while (File(WorkflowStore.file(col, n)).existsSync()) {
      n = '$name copy ${i++}';
    }
    WorkflowStore.save(col, wf.copyWith(name: n));
    reload(col);
    openWorkflow(col, n);
  });

  void promptDeleteWorkflow(String col, String name) {
    modal = ModalConfirm(
      title: 'Delete workflow',
      message:
          'Permanently delete workflow "$name"? The requests it uses are not deleted.',
      confirm: 'Delete',
      onOk: () => guard(() {
        final t = workflowTab(col, name);
        if (t != null) closeTab(t.id, true);
        WorkflowStore.delete(col, name);
        reload(col);
      }),
    );
  }

  void _addBlock(
    RequestTab tab,
    String? parent,
    int branch,
    WorkflowStep Function(String) make,
  ) {
    final ws = tab.workflow;
    if (ws == null) return;
    final id = newStepId(ws.draft.steps);
    ws.update(
      (w) => w.copyWith(steps: w.steps.addStep(parent, branch, make(id))),
    );
    ws.selected = id;
  }

  /// Adds an existing request of the collection at the end of a branch (top level when [parent] is null).
  void addWorkflowStep(
    RequestTab tab,
    RequestNode request, {
    String? parent,
    int branch = 0,
  }) {
    final col = collection(tab.collectionPath);
    if (col == null) return;
    _addBlock(
      tab,
      parent,
      branch,
      (id) => WorkflowStep(id: id, request: col.requestRef(request)),
    );
  }

  /// Creates a brand-new request in the collection root and adds it as a step.
  void addNewWorkflowStep(
    RequestTab tab,
    String name,
    String method,
    String url, {
    String? parent,
    int branch = 0,
  }) => guard(() {
    require(name.trim().isNotEmpty, () => 'Request name required');
    final col = tab.collectionPath;
    final file = Collections.createRequest(
      col,
      ApiRequest(name: name.trim(), method: method, url: url.trim()),
    );
    reload(col);
    final r = collection(col)?.findRequest(file);
    if (r != null) addWorkflowStep(tab, r, parent: parent, branch: branch);
  });

  /// Adds a logic block (if/else, loop, set variable, wait, stop) with sensible starting values.
  void addWorkflowLogic(
    RequestTab tab,
    StepKind kind, {
    String? parent,
    int branch = 0,
    LoopMode loop = LoopMode.ForEach,
    SetOp setOp = SetOp.Value,
  }) {
    _addBlock(tab, parent, branch, (id) {
      switch (kind) {
        case StepKind.If:
          return WorkflowStep(
            id: id,
            kind: kind,
            conditions: const [Condition()],
          );
        case StepKind.Loop:
          return WorkflowStep(
            id: id,
            kind: kind,
            loop: loop,
            conditions: loop == LoopMode.While ? const [Condition()] : const [],
            count: loop == LoopMode.Repeat ? '3' : '',
          );
        case StepKind.Set:
          String vn;
          switch (setOp) {
            case SetOp.Count:
              vn = 'count';
              break;
            case SetOp.Sum:
              vn = 'total';
              break;
            case SetOp.First:
              vn = 'first';
              break;
            case SetOp.Last:
              vn = 'last';
              break;
            default:
              vn = '';
          }
          return WorkflowStep(id: id, kind: kind, setOp: setOp, varName: vn);
        case StepKind.Wait:
          return WorkflowStep(id: id, kind: kind, value: '1000');
        default:
          return WorkflowStep(id: id, kind: kind);
      }
    });
  }

  void removeWorkflowStep(RequestTab tab, String id) {
    final ws = tab.workflow;
    if (ws == null) return;
    // references to the removed block are left in place; the next run flags them
    final st = ws.draft.steps.findStep(id);
    final gone = st != null
        ? [
            st,
            ...st.children.walk(),
            ...st.otherwise.walk(),
          ].map((s) => s.id).toList()
        : [id];
    ws.update((w) => w.copyWith(steps: w.steps.removeStep(id)));
    for (final g in gone) {
      ws.runs.remove(g);
      ws.counts.remove(g);
      ws.history.remove(g);
    }
    if (ws.selected != null && gone.contains(ws.selected)) ws.selected = null;
  }

  void moveWorkflowStep(RequestTab tab, String id, int delta) {
    final ws = tab.workflow;
    if (ws == null) return;
    ws.update((w) => w.copyWith(steps: w.steps.moveStep(id, delta)));
  }

  /// Runs the workflow; with [upTo] it ends once that block has run (handy while building).
  Future<void> runWorkflow(RequestTab tab, [String? upTo]) async {
    final ws = tab.workflow;
    if (ws == null) return;
    if (ws.running) return;
    final col = collection(tab.collectionPath);
    if (col == null) return;
    if (settings.autoSave && ws.dirty) saveWorkflow(tab);
    ws.runs.clear();
    ws.counts.clear();
    ws.history.clear();
    ws.events.clear();
    ws.logOpen.clear();
    ws.cancelled = false;
    ws.running = true;
    ws.expanded = null;
    final rc = runCtx(col);
    final wf = ws.draft;
    try {
      await WorkflowRunner.run(
        rc,
        wf,
        () => ws.cancelled,
        (s) => ws.current = s.id,
        (r) {
          ws.runs[r.step.id] = r;
          ws.counts[r.step.id] = (ws.counts[r.step.id] ?? 0) + 1;
          final h = [...(ws.history[r.step.id] ?? const <StepRun>[]), r];
          ws.history[r.step.id] = h.length > 100
              ? h.sublist(h.length - 100)
              : h;
        },
        (e) => ws.events.add(e),
        upTo,
      );
    } catch (e) {
      showToast(errorText(e));
    } finally {
      ws.running = false;
      ws.current = null;
    }
  }

  Future<void> startRunner(RequestTab tab) async {
    final rs = tab.runner;
    if (rs == null) return;
    if (rs.running) return;
    final col = collection(tab.collectionPath);
    if (col == null) return;
    rs.results.clear();
    rs.cancelled = false;
    rs.running = true;
    rs.expanded = null;
    final rc = runCtx(col);
    final queue = <RequestNode>[
      for (var i = 0; i < rs.iters; i++) ...rs.chosen,
    ];
    final delay = int.tryParse(rs.delay) ?? 0;
    final stop = rs.stopOnFail;
    try {
      await Runner.runAll(
        rc,
        queue,
        stop,
        delay,
        () => rs.cancelled,
        (n) => rs.current = n.name,
        (it) => rs.results.add(it),
      );
    } finally {
      rs.running = false;
      rs.current = '';
    }
  }
}
