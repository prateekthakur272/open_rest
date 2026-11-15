import 'dart:io';

import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/interop/exporters.dart';
import 'package:open_rest/core/interop/importers.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:path/path.dart' as p;

// Import and export of collections. Extensions of [AppState] so that class stays the single owner of state.

extension AppStateTransfer on AppState {
  void importFrom(
    String kind,
    String? file,
    String text,
    String parent,
  ) => guard(() {
    Directory(parent).createSync(recursive: true);
    String src() => file != null ? File(file).readAsStringSync() : text;
    switch (kind) {
      case 'Postman Collection':
        addCollection(Importers.importPostman(src(), parent));
        break;
      case 'Insomnia':
        addCollection(Importers.importInsomnia(src(), parent));
        break;
      case 'OpenAPI / Swagger':
        addCollection(Importers.importOpenApi(src(), parent));
        break;
      case 'Bruno Collection (folder)':
        if (file == null) {
          throw ArgumentError('Choose a Bruno collection folder');
        }
        addCollection(Importers.importBruno(file, parent));
        break;
      case 'OpenRest Bundle (YAML)':
        addCollection(Importers.importBundle(src(), parent));
        break;
      case 'OpenRest Collection (folder)':
        if (file == null) throw ArgumentError('Choose a collection folder');
        openCollection(file);
        break;
      case 'cURL':
        final col = currentCollection;
        if (col == null) throw StateError('Open or create a collection first');
        createRequestFromCurl(col.path, col.path, text);
        break;
      case 'Postman Environment (Global)':
        final env = Importers.importPostmanEnv(src());
        if (env == null) throw StateError('Not a Postman environment file');
        AppStore.saveGlobalEnv(env);
        globalEnvs = AppStore.loadGlobalEnvs();
        break;
      case 'Postman Environment':
        final col = currentCollection;
        if (col == null) throw StateError('Open or create a collection first');
        final env = Importers.importPostmanEnv(src());
        if (env == null) throw StateError('Not a Postman environment file');
        Collections.saveEnvironment(col.path, env);
        reload(col.path);
        break;
      default:
        throw StateError('Unknown import type');
    }
    modal = null;
    showToast('Import complete');
  });

  void exportCollection(String col, String format, String dest) => guard(() {
    final c = collection(col);
    if (c == null) throw StateError('Collection not found');
    final out = Exporters.export(format, c, dest);
    showToast('Exported to ${p.basename(out)}');
  });
}
