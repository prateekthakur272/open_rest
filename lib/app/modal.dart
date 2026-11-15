/// The dialog currently shown; one `Modal<Name>` subclass per dialog.
sealed class Modal {
  const Modal();
}

/// Single-line text prompt.
class ModalPrompt extends Modal {
  const ModalPrompt({
    required this.title,
    required this.initial,
    required this.label,
    required this.confirm,
    required this.onOk,
  });
  final String title;
  final String initial;
  final String label;
  final String confirm;
  final void Function(String) onOk;

  ModalPrompt copyWith({
    String? title,
    String? initial,
    String? label,
    String? confirm,
    void Function(String)? onOk,
  }) => ModalPrompt(
    title: title ?? this.title,
    initial: initial ?? this.initial,
    label: label ?? this.label,
    confirm: confirm ?? this.confirm,
    onOk: onOk ?? this.onOk,
  );

  @override
  bool operator ==(Object other) =>
      other is ModalPrompt &&
      other.title == title &&
      other.initial == initial &&
      other.label == label &&
      other.confirm == confirm &&
      other.onOk == onOk;
  @override
  int get hashCode => Object.hash(title, initial, label, confirm, onOk);
}

/// Yes/no confirmation.
class ModalConfirm extends Modal {
  const ModalConfirm({
    required this.title,
    required this.message,
    required this.confirm,
    required this.onOk,
  });
  final String title;
  final String message;
  final String confirm;
  final void Function() onOk;

  ModalConfirm copyWith({
    String? title,
    String? message,
    String? confirm,
    void Function()? onOk,
  }) => ModalConfirm(
    title: title ?? this.title,
    message: message ?? this.message,
    confirm: confirm ?? this.confirm,
    onOk: onOk ?? this.onOk,
  );

  @override
  bool operator ==(Object other) =>
      other is ModalConfirm &&
      other.title == title &&
      other.message == message &&
      other.confirm == confirm &&
      other.onOk == onOk;
  @override
  int get hashCode => Object.hash(title, message, confirm, onOk);
}

/// New request form.
class ModalNewRequest extends Modal {
  const ModalNewRequest({required this.collection, required this.dir});
  final String collection;
  final String dir;

  ModalNewRequest copyWith({String? collection, String? dir}) =>
      ModalNewRequest(
        collection: collection ?? this.collection,
        dir: dir ?? this.dir,
      );

  @override
  bool operator ==(Object other) =>
      other is ModalNewRequest &&
      other.collection == collection &&
      other.dir == dir;
  @override
  int get hashCode => Object.hash(collection, dir);
}

/// New collection form.
class ModalNewCollection extends Modal {
  const ModalNewCollection();
  @override
  bool operator ==(Object other) => other is ModalNewCollection;
  @override
  int get hashCode => 1;
}

/// First-run walkthrough.
class ModalOnboarding extends Modal {
  const ModalOnboarding();
  @override
  bool operator ==(Object other) => other is ModalOnboarding;
  @override
  int get hashCode => 2;
}

class ModalOpenCollection extends Modal {
  const ModalOpenCollection();
  @override
  bool operator ==(Object other) => other is ModalOpenCollection;
  @override
  int get hashCode => 3;
}

/// [collection] == null opens the global environments.
class ModalEnvs extends Modal {
  const ModalEnvs({this.collection});
  final String? collection;

  ModalEnvs copyWith({String? collection}) =>
      ModalEnvs(collection: collection ?? this.collection);

  @override
  bool operator ==(Object other) =>
      other is ModalEnvs && other.collection == collection;
  @override
  int get hashCode => Object.hash('envs', collection);
}

/// Code snippet generator for a request.
class ModalCodegen extends Modal {
  const ModalCodegen({required this.tabId});
  final int tabId;

  ModalCodegen copyWith({int? tabId}) =>
      ModalCodegen(tabId: tabId ?? this.tabId);

  @override
  bool operator ==(Object other) =>
      other is ModalCodegen && other.tabId == tabId;
  @override
  int get hashCode => Object.hash('codegen', tabId);
}

/// Import from another tool.
class ModalImport extends Modal {
  const ModalImport();
  @override
  bool operator ==(Object other) => other is ModalImport;
  @override
  int get hashCode => 4;
}

/// Preferences.
class ModalSettings extends Modal {
  const ModalSettings();
  @override
  bool operator ==(Object other) => other is ModalSettings;
  @override
  int get hashCode => 5;
}

class ModalAbout extends Modal {
  const ModalAbout();
  @override
  bool operator ==(Object other) => other is ModalAbout;
  @override
  int get hashCode => 6;
}

class ModalDeveloper extends Modal {
  const ModalDeveloper();
  @override
  bool operator ==(Object other) => other is ModalDeveloper;
  @override
  int get hashCode => 7;
}

/// Cookie jar viewer.
class ModalCookies extends Modal {
  const ModalCookies();
  @override
  bool operator ==(Object other) => other is ModalCookies;
  @override
  int get hashCode => 8;
}

/// Collection or folder settings.
class ModalNodeSettings extends Modal {
  const ModalNodeSettings({required this.collection, required this.node});
  final String collection;
  final String node;

  ModalNodeSettings copyWith({String? collection, String? node}) =>
      ModalNodeSettings(
        collection: collection ?? this.collection,
        node: node ?? this.node,
      );

  @override
  bool operator ==(Object other) =>
      other is ModalNodeSettings &&
      other.collection == collection &&
      other.node == node;
  @override
  int get hashCode => Object.hash('node', collection, node);
}

/// Variables overview.
class ModalVars extends Modal {
  const ModalVars({required this.collection});
  final String collection;

  ModalVars copyWith({String? collection}) =>
      ModalVars(collection: collection ?? this.collection);

  @override
  bool operator ==(Object other) =>
      other is ModalVars && other.collection == collection;
  @override
  int get hashCode => Object.hash('vars', collection);
}

/// Export a collection.
class ModalExport extends Modal {
  const ModalExport({required this.collection});
  final String collection;

  ModalExport copyWith({String? collection}) =>
      ModalExport(collection: collection ?? this.collection);

  @override
  bool operator ==(Object other) =>
      other is ModalExport && other.collection == collection;
  @override
  int get hashCode => Object.hash('export', collection);
}

/// [parent] == null adds to the top level; otherwise to that block's main (branch 0) or else (branch 1) list.
class ModalAddStep extends Modal {
  const ModalAddStep({required this.tabId, this.parent, this.branch = 0});
  final int tabId;
  final String? parent;
  final int branch;

  ModalAddStep copyWith({int? tabId, String? parent, int? branch}) =>
      ModalAddStep(
        tabId: tabId ?? this.tabId,
        parent: parent ?? this.parent,
        branch: branch ?? this.branch,
      );

  @override
  bool operator ==(Object other) =>
      other is ModalAddStep &&
      other.tabId == tabId &&
      other.parent == parent &&
      other.branch == branch;
  @override
  int get hashCode => Object.hash('addStep', tabId, parent, branch);
}

/// The complete last response of a workflow step.
class ModalViewResponse extends Modal {
  const ModalViewResponse({required this.tabId, required this.stepId});
  final int tabId;
  final String stepId;

  ModalViewResponse copyWith({int? tabId, String? stepId}) => ModalViewResponse(
    tabId: tabId ?? this.tabId,
    stepId: stepId ?? this.stepId,
  );

  @override
  bool operator ==(Object other) =>
      other is ModalViewResponse &&
      other.tabId == tabId &&
      other.stepId == stepId;
  @override
  int get hashCode => Object.hash('viewResponse', tabId, stepId);
}

/// Command palette.
class ModalPalette extends Modal {
  const ModalPalette();
  @override
  bool operator ==(Object other) => other is ModalPalette;
  @override
  int get hashCode => 9;
}
