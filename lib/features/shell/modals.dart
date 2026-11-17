import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/features/developer/developer_dialog.dart';
import 'package:open_rest/features/dialogs/collection_dialogs.dart';
import 'package:open_rest/features/dialogs/cookies_dialog.dart';
import 'package:open_rest/features/dialogs/dialogs.dart';
import 'package:open_rest/features/dialogs/env_dialogs.dart';
import 'package:open_rest/features/dialogs/node_settings_dialog.dart';
import 'package:open_rest/features/dialogs/vars_dialog.dart';
import 'package:open_rest/features/dialogs/transfer_dialogs.dart';
import 'package:open_rest/features/onboarding/onboarding.dart';
import 'package:open_rest/features/preferences/preferences.dart';
import 'package:open_rest/features/shell/menus.dart';
import 'package:open_rest/features/shell/palette.dart';
import 'package:open_rest/features/workflow/add_step_dialog.dart';
import 'package:open_rest/features/workflow/response_viewer.dart';

/// Shows whichever modal dialog is currently open.
class Modals extends StatelessWidget {
  const Modals({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final m = state.modal;
    if (m == null) return const SizedBox.shrink();
    return Positioned.fill(child: _dialog(m));
  }

  Widget _dialog(Modal m) => switch (m) {
    ModalPrompt() => PromptDialog(state: state, m: m),
    ModalConfirm() => ModalBox(
      title: m.title,
      onClose: () => state.modal = null,
      width: 420,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: m.confirm,
          onClick: () {
            state.modal = null;
            m.onOk();
          },
          primary: true,
        ),
      ],
      content: [T(m.message)],
    ),
    ModalAddStep() => AddStepDialog(state: state, m: m),
    ModalViewResponse() => ResponseDialog(state: state, m: m),
    ModalNewRequest() => NewRequestDialog(state: state, m: m),
    ModalNewCollection() => NewCollectionDialog(state: state),
    ModalOpenCollection() => OpenCollectionDialog(state: state),
    ModalEnvs() => EnvsDialog(state: state, m: m),
    ModalCodegen() => CodegenDialog(state: state, m: m),
    ModalImport() => ImportDialog(state: state),
    ModalSettings() => PreferencesDialog(state: state),
    ModalAbout() => AboutDialog(state: state),
    ModalDeveloper() => DeveloperDialog(state: state),
    ModalCookies() => CookiesDialog(state: state),
    ModalNodeSettings() => NodeSettingsDialog(state: state, m: m),
    ModalVars() => VarsDialog(state: state, m: m),
    ModalExport() => ExportDialog(state: state, m: m),
    ModalPalette() => Palette(state: state),
    ModalOnboarding() => OnboardingDialog(state: state),
    ModalUpdateAvailable() => UpdateAvailableDialog(
      state: state,
      version: m.version,
    ),
  };
}
