import 'package:flutter/foundation.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/node_settings_logic.dart';

/// Draft of a collection or folder config being edited, with save / revert.
class NodeSettingsController extends ChangeNotifier {
  NodeSettingsController(this.state, this.collection, this.node)
    : _saved = _load(state, collection, node) {
    _draft = _saved;
  }

  final AppState state;

  /// Collection path.
  final String collection;

  /// Node path: the collection path itself or a folder path.
  final String node;

  NodeConfig _saved;
  late NodeConfig _draft;
  NodeSection _section = NodeSection.headers;
  int _rev = 0;

  static NodeConfig _load(AppState s, String collection, String node) {
    final col = s.collection(collection);
    if (col == null) return const NodeConfig();
    return node == col.path
        ? col.config
        : (findFolder(col.children, node)?.config ?? const NodeConfig());
  }

  bool get isCollection => node == collection;
  NodeConfig get config => _draft;
  NodeConfig get savedConfig => _saved;
  bool get dirty => nodeConfigDirty(_saved, _draft);
  NodeSection get section => _section;

  /// Changes whenever the draft is reverted, so editors rebuild from it.
  int get revision => _rev;

  set section(NodeSection s) {
    if (s == _section) return;
    _section = s;
    notifyListeners();
  }

  void update(NodeConfig c) {
    _draft = c;
    notifyListeners();
  }

  void save() {
    if (!dirty) return;
    state.saveNodeConfig(collection, node, _draft);
    _saved = _draft;
    notifyListeners();
  }

  /// Picks up a config that changed elsewhere (a rename, an import): an untouched draft is replaced,
  /// an edited one keeps its edits and only follows the new saved name.
  void rebase() {
    final fresh = _load(state, collection, node);
    if (fresh == _saved) return;
    if (!dirty) {
      _saved = fresh;
      _draft = fresh;
      _rev++;
    } else {
      if (_draft.name == _saved.name) {
        _draft = _draft.copyWith(name: fresh.name);
      }
      _saved = fresh;
    }
    notifyListeners();
  }

  void revert() {
    _draft = _saved;
    _rev++;
    notifyListeners();
  }
}
