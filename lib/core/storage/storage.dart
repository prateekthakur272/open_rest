// ignore_for_file: constant_identifier_names
import 'dart:io';
import 'dart:typed_data';

import 'package:open_rest/core/logging/log.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/run/workflow_storage.dart';
import 'package:open_rest/utils/json.dart';
import 'package:open_rest/utils/yml.dart';
import 'package:path/path.dart' as p;

// Storage is synchronous : files are tiny and callers rely on immediate results.

bool _exists(String path) =>
    FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
bool _isDir(String path) => FileSystemEntity.isDirectorySync(path);
bool _isFile(String path) => FileSystemEntity.isFileSync(path);
String _name(String path) => p.basename(path);
String _ext(String path) {
  final e = p.extension(path);
  return e.isEmpty ? '' : e.substring(1);
}

String _nameNoExt(String path) => p.basenameWithoutExtension(path);

List<String> _listDir(String dir) =>
    Directory(dir).listSync(followLinks: true).map((e) => e.path).toList();

/// Trims any of [chars] from both ends of [s].
String _trimChars(String s, String chars) {
  var a = 0;
  var b = s.length;
  while (a < b && chars.contains(s[a])) {
    a++;
  }
  while (b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

double _f32(double v) => (Float32List(1)..[0] = v)[0];

/// Saved UI state.
class SavedState {
  final List<String> collections;
  final Map<String, String> envs;
  final List<String> tabs;
  final String? activeTab;
  final double sidebarWidth;
  final double splitFraction;
  final bool sidebarVisible;
  final String? globalEnv;
  final String? sidebarTab;

  /// Folders / collections that are open in the tree; null when never saved (the default expansion applies).
  final List<String>? expandedFolders;
  final String? selectedCollection;

  const SavedState({
    required this.collections,
    required this.envs,
    this.tabs = const [],
    this.activeTab,
    this.sidebarWidth = 0.22,
    this.splitFraction = 0.45,
    this.sidebarVisible = true,
    this.globalEnv,
    this.sidebarTab,
    this.expandedFolders,
    this.selectedCollection,
  });

  SavedState copyWith({
    List<String>? collections,
    Map<String, String>? envs,
    List<String>? tabs,
    Object? activeTab = _unset,
    double? sidebarWidth,
    double? splitFraction,
    bool? sidebarVisible,
    Object? globalEnv = _unset,
    Object? sidebarTab = _unset,
    Object? expandedFolders = _unset,
    Object? selectedCollection = _unset,
  }) => SavedState(
    collections: collections ?? this.collections,
    envs: envs ?? this.envs,
    tabs: tabs ?? this.tabs,
    activeTab: identical(activeTab, _unset)
        ? this.activeTab
        : activeTab as String?,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    splitFraction: splitFraction ?? this.splitFraction,
    sidebarVisible: sidebarVisible ?? this.sidebarVisible,
    globalEnv: identical(globalEnv, _unset)
        ? this.globalEnv
        : globalEnv as String?,
    sidebarTab: identical(sidebarTab, _unset)
        ? this.sidebarTab
        : sidebarTab as String?,
    expandedFolders: identical(expandedFolders, _unset)
        ? this.expandedFolders
        : expandedFolders as List<String>?,
    selectedCollection: identical(selectedCollection, _unset)
        ? this.selectedCollection
        : selectedCollection as String?,
  );
}

const Object _unset = Object();

/// Last window geometry in dp. x / y are null when the position was never saved (the OS picks it).
class WindowGeometry {
  const WindowGeometry(
    this.width,
    this.height, [
    this.x,
    this.y,
    this.maximized = false,
  ]);

  final double width;
  final double height;
  final double? x;
  final double? y;
  final bool maximized;

  WindowGeometry copyWith({bool? maximized}) =>
      WindowGeometry(width, height, x, y, maximized ?? this.maximized);
}

/// App-level persistence (~/.openrest): settings, opened collections, secrets, selected environments.
class AppStore {
  AppStore._();

  static const String _tag = 'storage';

  /// Override of the data directory; set before first use (tests).
  static String? homeOverride;

  static String? _dirCache;
  static String? _dirCacheKey;

  static String get dir {
    final key = homeOverride ?? '';
    if (_dirCache != null && _dirCacheKey == key) return _dirCache!;
    final String d;
    if (homeOverride != null) {
      d = homeOverride!;
    } else {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? env['HOME'] ?? '')
          : (env['HOME'] ?? env['USERPROFILE'] ?? '');
      d = p.join(home, '.openrest');
    }
    Directory(d).createSync(recursive: true);
    Log.writeTo(p.join(d, 'openrest.log'));
    _dirCache = d;
    _dirCacheKey = key;
    return d;
  }

  static String get _settingsFile => p.join(dir, 'settings.json');
  static String get _stateFile => p.join(dir, 'state.json');
  static String get _secretsFile => p.join(dir, 'secrets.json');

  /// True when nothing has been saved yet: a fresh download that should show the walkthrough.
  static bool isFirstRun() => !_exists(_settingsFile) && !_exists(_stateFile);

  static AppSettings loadSettings() {
    try {
      final m = Json.obj(Json.parse(File(_settingsFile).readAsStringSync()));
      if (m == null) return const AppSettings();
      const d = AppSettings();
      int? i(String k) {
        final v = m[k];
        return v is num ? v.toInt() : null;
      }

      bool? b(String k) {
        final v = m[k];
        return v is bool ? v : null;
      }

      String? s(String k) {
        final v = m[k];
        return v is String ? v : null;
      }

      final dark = b('dark');
      return AppSettings(
        // files from before "System" existed stored a plain "dark": true / false
        theme:
            ThemeMode.of(s('theme')) ??
            (dark == null ? null : (dark ? ThemeMode.Dark : ThemeMode.Light)) ??
            d.theme,
        timeoutMs: i('timeoutMs') ?? d.timeoutMs,
        followRedirects: b('followRedirects') ?? d.followRedirects,
        maxRedirects: i('maxRedirects') ?? d.maxRedirects,
        sslVerify: b('sslVerify') ?? d.sslVerify,
        proxyEnabled: b('proxyEnabled') ?? d.proxyEnabled,
        proxyHost: s('proxyHost') ?? d.proxyHost,
        proxyPort: i('proxyPort') ?? d.proxyPort,
        userAgent: s('userAgent') ?? d.userAgent,
        verticalLayout: b('verticalLayout') ?? d.verticalLayout,
        fontSize: i('fontSize') ?? d.fontSize,
        autoSave: b('autoSave') ?? d.autoSave,
      );
    } catch (e, st) {
      if (_exists(_settingsFile)) {
        Log.warning(_tag, 'Cannot read settings.json, using defaults', e, st);
      }
      return const AppSettings();
    }
  }

  static void saveSettings(AppSettings s) {
    final m = <String, dynamic>{
      'theme': s.theme.id,
      'timeoutMs': s.timeoutMs,
      'followRedirects': s.followRedirects,
      'maxRedirects': s.maxRedirects,
      'sslVerify': s.sslVerify,
      'proxyEnabled': s.proxyEnabled,
      'proxyHost': s.proxyHost,
      'proxyPort': s.proxyPort,
      'userAgent': s.userAgent,
      'verticalLayout': s.verticalLayout,
      'fontSize': s.fontSize,
      'autoSave': s.autoSave,
    };
    _writeFile(_settingsFile, Json.stringify(m, pretty: true));
  }

  static SavedState loadState() {
    try {
      final m = Json.obj(Json.parse(File(_stateFile).readAsStringSync()))!;
      List<String> strs(dynamic v) =>
          Json.arr(v)?.whereType<String>().toList() ?? <String>[];
      final envs = Json.obj(m['envs']);
      final sw = m['sidebarWidth'];
      final sf = m['splitFraction'];
      final sv = m['sidebarVisible'];
      final at = m['activeTab'];
      final ge = m['globalEnv'];
      return SavedState(
        collections: strs(m['collections']),
        envs: envs == null
            ? <String, String>{}
            : {for (final e in envs.entries) e.key: e.value.toString()},
        tabs: strs(m['tabs']),
        activeTab: at is String ? at : null,
        sidebarWidth: sw is num ? _f32(sw.toDouble()) : 0.22,
        splitFraction: sf is num ? _f32(sf.toDouble()) : 0.45,
        sidebarVisible: sv is bool ? sv : true,
        globalEnv: ge is String ? ge : null,
        sidebarTab: m['sidebarTab'] is String
            ? m['sidebarTab'] as String
            : null,
        expandedFolders: m['expandedFolders'] is List
            ? strs(m['expandedFolders'])
            : null,
        selectedCollection: m['selectedCollection'] is String
            ? m['selectedCollection'] as String
            : null,
      );
    } catch (e, st) {
      if (_exists(_stateFile)) {
        Log.warning(_tag, 'Cannot read state.json, starting empty', e, st);
      }
      return const SavedState(collections: [], envs: {});
    }
  }

  static void saveState(SavedState s) {
    _writeFile(
      _stateFile,
      Json.stringify(<String, dynamic>{
        'collections': s.collections,
        'envs': s.envs,
        'tabs': s.tabs,
        'activeTab': s.activeTab,
        // Float fields may be stored as doubles.
        'sidebarWidth': _f32(s.sidebarWidth),
        'splitFraction': _f32(s.splitFraction),
        'sidebarVisible': s.sidebarVisible,
        'globalEnv': s.globalEnv,
        'sidebarTab': s.sidebarTab,
        'expandedFolders': s.expandedFolders,
        'selectedCollection': s.selectedCollection,
      }, pretty: true),
    );
  }

  static String get _windowFile => p.join(dir, 'window.json');

  static WindowGeometry? loadWindow() {
    try {
      final m = Json.obj(Json.parse(File(_windowFile).readAsStringSync()))!;
      final w = _f32((m['width'] as num).toDouble());
      final h = _f32((m['height'] as num).toDouble());
      if (w < 200 || h < 150) return null;
      return WindowGeometry(
        w,
        h,
        m['x'] is num ? _f32((m['x'] as num).toDouble()) : null,
        m['y'] is num ? _f32((m['y'] as num).toDouble()) : null,
        m['maximized'] is bool ? m['maximized'] as bool : false,
      );
    } catch (e, st) {
      if (_exists(_windowFile)) {
        Log.warning(
          _tag,
          'Cannot read window.json, using the default size',
          e,
          st,
        );
      }
      return null;
    }
  }

  static void saveWindow(WindowGeometry g) {
    final m = <String, dynamic>{
      'width': g.width,
      'height': g.height,
      'maximized': g.maximized,
    };
    if (g.x != null) m['x'] = g.x;
    if (g.y != null) m['y'] = g.y;
    _writeFile(_windowFile, Json.stringify(m, pretty: true));
  }

  /// Writing is best effort (a read-only home must not crash the app) but a failure is always logged.
  static void _writeFile(String file, String text) {
    try {
      File(file).writeAsStringSync(text);
    } catch (e, st) {
      Log.error(_tag, 'Cannot write ${p.basename(file)}', e, st);
    }
  }

  static Map<String, dynamic> _secretsMap() {
    try {
      return Map<String, dynamic>.of(
        Json.obj(Json.parse(File(_secretsFile).readAsStringSync())) ??
            <String, dynamic>{},
      );
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String secretKey(String collection, String env, String name) =>
      '$collection|$env|$name';

  static String getSecret(String collection, String env, String name) {
    final v = _secretsMap()[secretKey(collection, env, name)];
    return v is String ? v : '';
  }

  static void removeSecrets(String collection, String env) {
    final m = _secretsMap();
    final prefix = '$collection|$env|';
    final before = m.length;
    m.removeWhere((k, _) => k.startsWith(prefix));
    if (m.length != before) {
      _writeFile(_secretsFile, Json.stringify(m, pretty: true));
    }
  }

  /// Global environments (available to every collection) live next to settings in ~/.openrest/environments.
  static String get globalEnvDir => p.join(dir, 'environments');
  static List<Environment> loadGlobalEnvs() =>
      EnvStore.load(globalEnvDir, EnvStore.GLOBAL_SCOPE);
  static void saveGlobalEnv(Environment env, [String? old]) =>
      EnvStore.save(globalEnvDir, EnvStore.GLOBAL_SCOPE, env, old);
  static void deleteGlobalEnv(String name) =>
      EnvStore.delete(globalEnvDir, EnvStore.GLOBAL_SCOPE, name);

  static void setSecret(
    String collection,
    String env,
    String name,
    String value,
  ) {
    final m = _secretsMap();
    m[secretKey(collection, env, name)] = value;
    _writeFile(_secretsFile, Json.stringify(m, pretty: true));
  }
}

/// Filesystem operations for OpenRest YAML collections.
class Collections {
  Collections._();

  static const Set<String> _ignored = {
    'node_modules',
    '.git',
    'environments',
    'workflows',
  };
  static const Set<String> _reserved = {OrYaml.ROOT_FILE, OrYaml.FOLDER_FILE};
  static const String _ext0 = '.yaml';

  static String sanitize(String name) {
    final s = _trimChars(
      name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-'),
      '. ',
    );
    return s.isEmpty ? 'untitled' : s;
  }

  static Map? _readMap(String f) {
    try {
      final v = Yml.parse(File(f).readAsStringSync());
      return v is Map ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Throws [ArgumentError] when the folder already exists.
  static String create(String parent, String name) {
    final d = p.join(parent, sanitize(name));
    if (_exists(d)) {
      throw ArgumentError("A folder named '${_name(d)}' already exists");
    }
    Directory(d).createSync(recursive: true);
    _writeRoot(d, NodeConfig(name: name), ['node_modules', '.git']);
    return d;
  }

  static void _writeRoot(String dir, NodeConfig cfg, List<String> ignore) {
    final m = <String, dynamic>{'openrest': OrYaml.VERSION};
    m.addAll(OrYaml.configToMap(cfg, false));
    if (ignore.isNotEmpty) m['ignore'] = ignore;
    File(p.join(dir, OrYaml.ROOT_FILE)).writeAsStringSync(Yml.dump(m));
  }

  static bool isCollection(String dir) =>
      _exists(p.join(dir, OrYaml.ROOT_FILE));

  static Collection load(String dir) {
    final root = _readMap(p.join(dir, OrYaml.ROOT_FILE)) ?? <String, dynamic>{};
    final cfg = OrYaml.mapToConfig(root, fallbackName: _name(dir));
    final envs = EnvStore.load(p.join(dir, 'environments'), dir);
    final dotEnv = <String, String>{};
    final envFile = p.join(dir, '.env');
    if (_exists(envFile)) {
      for (final line in File(envFile).readAsLinesSync()) {
        final l = line.trim();
        if (l.isEmpty || l.startsWith('#') || !l.contains('=')) continue;
        final i = l.indexOf('=');
        dotEnv[l.substring(0, i).trim()] = _trimChars(
          l.substring(i + 1).trim(),
          '"\'',
        );
      }
    }
    return Collection(
      path: dir,
      name: cfg.name,
      config: cfg,
      children: _loadChildren(dir),
      environments: envs,
      dotEnv: dotEnv,
      workflows: WorkflowStore.load(dir),
    );
  }

  static List<Node> _loadChildren(String dir) {
    List<String> entries;
    try {
      entries = _listDir(dir);
    } catch (_) {
      entries = [];
    }
    final nodes = <(int, Node)>[];
    for (final e in entries) {
      final n = _name(e);
      if (n.startsWith('.')) continue;
      if (_isDir(e)) {
        if (_ignored.contains(n)) continue;
        final fb = p.join(e, OrYaml.FOLDER_FILE);
        final raw = _readMap(fb);
        final cfg = raw != null
            ? OrYaml.mapToConfig(raw, fallbackName: n)
            : NodeConfig(name: n, seq: 2147483647);
        nodes.add((
          cfg.seq,
          FolderNode(
            path: e,
            name: cfg.name.isEmpty ? n : cfg.name,
            config: cfg,
            children: _loadChildren(e),
          ),
        ));
      } else if ((_ext(e) == 'yaml' || _ext(e) == 'yml') &&
          !_reserved.contains(n)) {
        final r = readRequest(e);
        if (r == null) continue;
        nodes.add((r.seq, RequestNode(path: e, name: r.name, request: r)));
      }
    }
    // Requests first (by seq), then folders (by seq, then name); stable sort.
    final indexed = [for (var i = 0; i < nodes.length; i++) (i, nodes[i])];
    indexed.sort((a, b) {
      final x = a.$2, y = b.$2;
      var c = (x.$2 is FolderNode ? 1 : 0).compareTo(
        y.$2 is FolderNode ? 1 : 0,
      );
      if (c != 0) return c;
      c = x.$1.compareTo(y.$1);
      if (c != 0) return c;
      c = x.$2.name.toLowerCase().compareTo(y.$2.name.toLowerCase());
      if (c != 0) return c;
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2.$2];
  }

  static List<String> requestFiles(String dir) {
    try {
      return _listDir(dir)
          .where(
            (it) =>
                _isFile(it) &&
                (_ext(it) == 'yaml' || _ext(it) == 'yml') &&
                !_reserved.contains(_name(it)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static ApiRequest? readRequest(String f) {
    try {
      return OrYaml.parseRequest(
        File(f).readAsStringSync(),
        fallbackName: _nameNoExt(f),
      );
    } catch (_) {
      return null;
    }
  }

  static void writeRequest(String f, ApiRequest r) {
    Directory(p.dirname(f)).createSync(recursive: true);
    File(f).writeAsStringSync(OrYaml.requestText(r));
  }

  static String uniqueFile(String dir, String base, [String ext = _ext0]) {
    var f = p.join(dir, sanitize(base) + ext);
    var i = 1;
    while (_exists(f) || _reserved.contains(_name(f))) {
      f = p.join(dir, '${sanitize(base)} (${i++})$ext');
    }
    return f;
  }

  static int nextSeq(String dir) {
    List<String> files;
    try {
      files = _listDir(dir)
          .where((it) => RegExp(r'^.*\.y.*ml$').hasMatch(_name(it)))
          .toList();
    } catch (_) {
      files = [];
    }
    var max = 0;
    for (final f in files) {
      if (_reserved.contains(_name(f))) continue;
      final s = readRequest(f)?.seq;
      if (s != null && s > max) max = s;
    }
    return max + 1;
  }

  static void saveRequest(String file, ApiRequest r) => writeRequest(file, r);

  static String createRequest(String dir, ApiRequest r) {
    final f = uniqueFile(dir, r.name);
    writeRequest(f, r.copyWith(seq: nextSeq(dir)));
    return f;
  }

  /// Throws [ArgumentError] when the folder already exists.
  static String createFolder(String parent, String name) {
    final d = p.join(parent, sanitize(name));
    if (_exists(d)) throw ArgumentError('Already exists: ${_name(d)}');
    Directory(d).createSync(recursive: true);
    saveFolderConfig(d, NodeConfig(name: name, seq: 1));
    return d;
  }

  static void _move(String src, String dst) {
    if (_isDir(src)) {
      Directory(src).renameSync(dst);
    } else {
      File(src).renameSync(dst);
    }
  }

  static String renameRequest(String file, String newName) {
    final cur = readRequest(file);
    if (cur == null) throw StateError('Cannot read ${_name(file)}');
    final r = cur.copyWith(name: newName);
    final target = sanitize(newName) == _nameNoExt(file)
        ? file
        : uniqueFile(p.dirname(file), newName);
    writeRequest(file, r);
    if (target != file) _move(file, target);
    return target;
  }

  static String renameFolder(String dir, String newName) {
    final fb = p.join(dir, OrYaml.FOLDER_FILE);
    final raw = _readMap(fb);
    final cfg =
        (raw != null
                ? OrYaml.mapToConfig(raw, fallbackName: _name(dir))
                : NodeConfig(name: _name(dir)))
            .copyWith(name: newName);
    saveFolderConfig(dir, cfg);
    final target = p.join(p.dirname(dir), sanitize(newName));
    if (target != dir && !_exists(target)) {
      _move(dir, target);
      return target;
    }
    return dir;
  }

  static void saveFolderConfig(String dir, NodeConfig cfg) =>
      File(p.join(dir, OrYaml.FOLDER_FILE))
          .writeAsStringSync(Yml.dump(OrYaml.configToMap(cfg, true)));

  static void saveCollectionConfig(String dir, NodeConfig cfg) {
    final old = _readMap(p.join(dir, OrYaml.ROOT_FILE));
    final ig = old?['ignore'];
    _writeRoot(
      dir,
      cfg,
      ig is List
          ? ig.map((it) => it.toString()).toList()
          : ['node_modules', '.git'],
    );
  }

  static void renameCollection(String dir, String name) {
    final raw = _readMap(p.join(dir, OrYaml.ROOT_FILE));
    final old = raw != null
        ? OrYaml.mapToConfig(raw, fallbackName: _name(dir))
        : const NodeConfig();
    saveCollectionConfig(dir, old.copyWith(name: name));
  }

  static void delete(String path) {
    if (_isDir(path)) {
      Directory(path).deleteSync(recursive: true);
    } else if (_exists(path)) {
      File(path).deleteSync();
    }
  }

  static String clone(String file, String newName) {
    final cur = readRequest(file);
    if (cur == null) throw StateError('Cannot read ${_name(file)}');
    final r = cur.copyWith(name: newName, seq: nextSeq(p.dirname(file)));
    final t = uniqueFile(p.dirname(file), newName);
    writeRequest(t, r);
    return t;
  }

  static void _copyDir(String src, String dst) {
    Directory(dst).createSync(recursive: true);
    for (final e in Directory(src).listSync(followLinks: false)) {
      final target = p.join(dst, _name(e.path));
      if (e is Directory) {
        _copyDir(e.path, target);
      } else if (e is File) {
        e.copySync(target);
      }
    }
  }

  static String cloneFolder(String dir, String newName) {
    var t = p.join(p.dirname(dir), sanitize(newName));
    if (_exists(t)) t = p.join(p.dirname(dir), '${sanitize(newName)} copy');
    _copyDir(dir, t);
    renameFolder(t, newName);
    return t;
  }

  /// Throws [ArgumentError] when the target exists or [destDir] is inside [src].
  static String move(String src, String destDir) {
    final t = p.join(destDir, _name(src));
    if (_exists(t)) throw ArgumentError('Target already exists');
    if (p.equals(destDir, src) || p.isWithin(src, destDir)) {
      throw ArgumentError('Cannot move into itself');
    }
    _move(src, t);
    return t;
  }

  /// Swap seq numbers of a request with its neighbour in the same folder.
  static void reorder(List<Node> siblings, int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= siblings.length) return;
    final reqs = siblings.whereType<RequestNode>().toList();
    final a = siblings[index];
    final b = siblings[target];
    if (a is! RequestNode || b is! RequestNode) return;
    final ia = reqs.indexOf(a);
    final ib = reqs.indexOf(b);
    reqs[ia] = b;
    reqs[ib] = a;
    for (var i = 0; i < reqs.length; i++) {
      final n = reqs[i];
      saveRequest(n.path, n.request.copyWith(seq: i + 1));
    }
  }

  static void saveEnvironment(String col, Environment env, [String? oldName]) =>
      EnvStore.save(p.join(col, 'environments'), col, env, oldName);

  static void deleteEnvironment(String col, String name) =>
      EnvStore.delete(p.join(col, 'environments'), col, name);
}

/// Reads/writes environment YAML files in a directory. Used for both scopes:
/// collection environments (`<collection>/environments`) and global ones (`~/.openrest/environments`).
/// Secret values never touch the YAML; they live in AppStore keyed by [scope].
class EnvStore {
  EnvStore._();

  /// Scope key used for secrets of global environments.
  static const String GLOBAL_SCOPE = '<global>';

  static List<Environment> load(String envDir, String scope) {
    if (!_isDir(envDir)) return [];
    final files =
        _listDir(envDir)
            .where((it) => _ext(it) == 'yaml' || _ext(it) == 'yml')
            .toList()
          ..sort(
            (a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()),
          );
    final out = <Environment>[];
    for (final f in files) {
      final m = Collections._readMap(f);
      if (m == null) continue;
      final nm = m['name'];
      final e = OrYaml.mapToEnv(
        m,
        nm is String && nm.trim().isNotEmpty ? nm : _nameNoExt(f),
      );
      out.add(
        e.copyWith(
          vars: e.vars
              .map(
                (v) => e.secrets.contains(v.name)
                    ? v.copyWith(
                        value: AppStore.getSecret(scope, e.name, v.name),
                      )
                    : v,
              )
              .toList(),
        ),
      );
    }
    return out;
  }

  /// Throws [ArgumentError] when renaming onto an existing environment.
  static void save(
    String envDir,
    String scope,
    Environment env, [
    String? oldName,
  ]) {
    Directory(envDir).createSync(recursive: true);
    final file = p.join(envDir, '${Collections.sanitize(env.name)}.yaml');
    if (oldName != null && oldName != env.name) {
      if (_exists(file)) {
        throw ArgumentError(
          "An environment named '${env.name}' already exists",
        );
      }
      final old = p.join(envDir, '${Collections.sanitize(oldName)}.yaml');
      if (_exists(old)) File(old).deleteSync();
      AppStore.removeSecrets(scope, oldName);
    }
    for (final s in env.secrets) {
      final v = env.vars.where((it) => it.name == s);
      AppStore.setSecret(scope, env.name, s, v.isEmpty ? '' : v.first.value);
    }
    File(file).writeAsStringSync(Yml.dump(OrYaml.envToMap(env)));
  }

  static void delete(String envDir, String scope, String name) {
    final f = p.join(envDir, '${Collections.sanitize(name)}.yaml');
    if (_exists(f)) File(f).deleteSync();
    AppStore.removeSecrets(scope, name);
  }
}
