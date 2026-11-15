import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/core/storage/storage.dart';

// Environments (per collection and global) and folder / collection settings. Extensions of [AppState] so that class stays the single owner of state.

extension AppStateEnvironments on AppState {
  void setEnv(String col, String? name) {
    if (name == null) {
      activeEnv.remove(col);
    } else {
      activeEnv[col] = name;
    }
    persist();
  }

  void saveEnvironment(String col, Environment env, String? old) => guard(() {
    require(env.name.trim().isNotEmpty, () => 'Environment name required');
    Collections.saveEnvironment(col, env, old);
    reload(col);
    if (old != null && old != env.name && activeEnv[col] == old) {
      setEnv(col, env.name);
    }
  });

  void deleteEnvironment(String col, String name) => guard(() {
    Collections.deleteEnvironment(col, name);
    if (activeEnv[col] == name) setEnv(col, null);
    reload(col);
  });

  // global environments

  void setGlobalEnv(String? name) {
    activeGlobalEnv = name;
    persist();
  }

  void saveGlobalEnvironment(Environment env, String? old) => guard(() {
    require(env.name.trim().isNotEmpty, () => 'Environment name required');
    AppStore.saveGlobalEnv(env, old);
    globalEnvs = AppStore.loadGlobalEnvs();
    if (old != null && old != env.name && activeGlobalEnv == old) {
      setGlobalEnv(env.name);
    }
  });

  void deleteGlobalEnvironment(String name) => guard(() {
    AppStore.deleteGlobalEnv(name);
    globalEnvs = AppStore.loadGlobalEnvs();
    if (activeGlobalEnv == name) setGlobalEnv(null);
  });

  void saveNodeConfig(String col, String node, NodeConfig cfg) => guard(() {
    if (node == col) {
      Collections.saveCollectionConfig(col, cfg);
    } else {
      Collections.saveFolderConfig(node, cfg);
    }
    reload(col);
    showToast('Settings saved');
  });
}
