import 'dart:math' as math;

import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:path/path.dart' as p;

// Sidebar operations: creating, renaming, moving, cloning and deleting requests and folders. Extensions of [AppState] so that class stays the single owner of state.

extension AppStateSidebar on AppState {
  void _remapTabs(String old, String neu) {
    for (final t in tabs.toList()) {
      if (isUnder(t.filePath, old)) {
        t.filePath = p.normalize(
          p.join(neu, p.relative(t.filePath, from: old)),
        );
      }
    }
  }

  void _dropTabs(String under) {
    final gone = tabs.where((t) => isUnder(t.filePath, under)).toList();
    for (final t in gone) {
      t.cancelJob();
    }
    tabs.removeWhere(gone.contains);
    if (activeTab == null) activeTabId = tabs.isEmpty ? null : tabs.last.id;
  }

  void createRequest(
    String col,
    String dir,
    String name,
    String method,
    String url, {
    bool graphql = false,
  }) => guard(() {
    require(name.trim().isNotEmpty, () => 'Name required');
    final r = ApiRequest(
      name: name.trim(),
      method: graphql ? 'POST' : method,
      url: url.trim(),
      params: UrlSync.paramsFromUrl(url.trim(), const []),
      bodyMode: graphql ? BodyMode.Graphql : BodyMode.None,
      bodyGraphql: graphql ? 'query {\n  __typename\n}\n' : '',
    );
    final f = Collections.createRequest(dir, r);
    reload(col);
    expanded[dir] = true;
    final n = collection(col)?.findRequest(f);
    if (n != null) openRequest(col, n);
  });

  void createRequestFromCurl(String col, String dir, String curl) => guard(() {
    final r = Importers.parseCurl(curl);
    if (r == null) throw StateError('Could not parse cURL command');
    final f = Collections.createRequest(dir, r);
    reload(col);
    expanded[dir] = true;
    final n = collection(col)?.findRequest(f);
    if (n != null) openRequest(col, n);
  });

  void promptNewFolder(String col, String dir) {
    modal = ModalPrompt(
      title: 'New Folder',
      initial: '',
      label: 'Folder name',
      confirm: 'Create',
      onOk: (n) => guard(() {
        Collections.createFolder(dir, n);
        reload(col);
        expanded[dir] = true;
      }),
    );
  }

  void promptRename(String col, Node? node) {
    if (node == null) {
      final c = collection(col);
      if (c == null) return;
      modal = ModalPrompt(
        title: 'Rename Collection',
        initial: c.name,
        label: 'Collection name',
        confirm: 'Rename',
        onOk: (n) => guard(() {
          Collections.renameCollection(col, n);
          reload(col);
        }),
      );
      return;
    }
    renaming = node.path;
  }

  void renameNode(String col, Node node, String newName) => guard(() {
    require(newName.trim().isNotEmpty, () => 'Name required');
    final neu = node is FolderNode
        ? Collections.renameFolder(node.path, newName)
        : Collections.renameRequest(node.path, newName);
    _remapTabs(node.path, neu);
    if (node is RequestNode) {
      final t = firstMatch(tabs, (t) => t.filePath == neu);
      if (t != null) {
        t.draft = t.draft.copyWith(name: newName);
        t.saved = t.saved.copyWith(name: newName);
      }
    }
    reload(col);
  });

  void moveNode(String col, String src, String destDir) => guard(() {
    if (p.dirname(src) == destDir) return;
    final neu = Collections.move(src, destDir);
    _remapTabs(src, neu);
    expanded[destDir] = true;
    reload(col);
    showToast('Moved ${p.basename(src)} → ${p.basename(destDir)}');
  });

  /// Drop a request next to [target] (before / after), moving it into target's folder if needed.
  void dropRequest(
    String col,
    RequestNode src,
    RequestNode target,
    bool after,
  ) => guard(() {
    final destDir = p.dirname(target.path);
    var srcPath = src.path;
    if (p.dirname(src.path) != destDir) {
      srcPath = Collections.move(src.path, destDir);
      _remapTabs(src.path, srcPath);
    }
    final withSeq = <(String, int)>[];
    for (final f in Collections.requestFiles(destDir)) {
      final r = Collections.readRequest(f);
      if (r != null) withSeq.add((f, r.seq));
    }
    withSeq.sort((a, b) => a.$2.compareTo(b.$2));
    final files = withSeq.map((e) => e.$1).toList();
    files.remove(srcPath);
    final ti = math.max(0, files.indexOf(target.path));
    files.insert(after ? ti + 1 : ti, srcPath);
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final r = Collections.readRequest(f);
      if (r != null) Collections.saveRequest(f, r.copyWith(seq: i + 1));
      final t = firstMatch(tabs, (t) => t.filePath == f);
      if (t != null) {
        t.draft = t.draft.copyWith(seq: i + 1);
        t.saved = t.saved.copyWith(seq: i + 1);
      }
    }
    reload(col);
  });

  void promptClone(String col, Node node) {
    modal = ModalPrompt(
      title: 'Clone',
      initial: '${node.name} copy',
      label: 'Name',
      confirm: 'Clone',
      onOk: (n) => guard(() {
        if (node is FolderNode) {
          Collections.cloneFolder(node.path, n);
        } else {
          Collections.clone(node.path, n);
        }
        reload(col);
      }),
    );
  }

  void promptDelete(String col, Node node) {
    modal = ModalConfirm(
      title: 'Delete ${node is FolderNode ? "folder" : "request"}',
      message: 'Permanently delete "${node.name}" from disk?',
      confirm: 'Delete',
      onOk: () => guard(() {
        _dropTabs(node.path);
        Collections.delete(node.path);
        reload(col);
      }),
    );
  }

  void move(String col, List<Node> siblings, int index, int delta) => guard(() {
    Collections.reorder(siblings, index, delta);
    // refresh open tabs' seq
    reload(col);
  });
}
