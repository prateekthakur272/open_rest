import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/code_editor.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/codegen/code_gen.dart';
import 'package:open_rest/core/interop/exporters.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/features/dialogs/dialogs.dart';
import 'package:open_rest/platform/platform.dart' as plat;
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Dialog that generates a code snippet for a request.
class CodegenDialog extends StatefulWidget {
  const CodegenDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalCodegen m;

  @override
  State<CodegenDialog> createState() => _CodegenDialogState();
}

class _CodegenDialogState extends State<CodegenDialog> {
  String lang = CodeGen.languages.first;
  String code = '';
  Object? _forDraft;
  String? _forLang;
  int _gen = 0;

  /// `remember(tab.draft, lang) { state.prepareFor(tab) }`: re-prepared when the draft or language changes.
  void _prepare(RequestTab tab) {
    if (identical(_forDraft, tab.draft) && _forLang == lang) return;
    _forDraft = tab.draft;
    _forLang = lang;
    final gen = ++_gen;
    final l = lang;
    widget.state.prepareFor(tab).then((r) {
      if (!mounted || gen != _gen) return;
      final text = r.fold(
        (it) => CodeGen.generate(l, it),
        (e) => '// ${errorText(e)}',
      );
      setState(() => code = text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    RequestTab? tab;
    for (final t in state.tabs) {
      if (t.id == widget.m.tabId) tab = t;
    }
    if (tab == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    _prepare(tab);
    return ModalBox(
      title: 'Generate Code',
      onClose: () => state.modal = null,
      width: 760,
      height: 560,
      actions: [
        Btn(label: 'Close', onClick: () => state.modal = null),
        Btn(
          label: 'Copy',
          onClick: () {
            plat.Platform.copy(code);
            state.showToast('Code copied');
          },
          primary: true,
          icon: Ic.copy,
        ),
      ],
      content: [
        Dropdown(
          selected: lang,
          options: CodeGen.languages,
          onSelect: (v) => setState(() => lang = v),
        ),
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: CodeEditor(
              value: code,
              onChange: (_) {},
              lang: CodeGen.langId(lang),
              readOnly: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog for importing collections from files.
class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key, required this.state});
  final AppState state;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  static const kinds = [
    'Postman Collection',
    'Insomnia',
    'OpenAPI / Swagger',
    'Bruno Collection (folder)',
    'OpenRest Bundle (YAML)',
    'OpenRest Collection (folder)',
    'cURL',
    'Postman Environment',
    'Postman Environment (Global)',
  ];
  String kind = kinds[0];
  String file = '';
  String text = '';
  String loc = defaultDir;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final state = widget.state;
    final needsFile = kind != 'cURL';
    final usesLocation = const [
      'Postman Collection',
      'Insomnia',
      'OpenAPI / Swagger',
      'Bruno Collection (folder)',
      'OpenRest Bundle (YAML)',
    ].contains(kind);
    final isFolder = kind.contains('folder');
    return ModalBox(
      title: 'Import',
      onClose: () => state.modal = null,
      width: 640,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: 'Import',
          icon: Ic.import,
          onClick: () => state.importFrom(
            kind,
            file.trim().isNotEmpty ? file.trim() : null,
            text,
            loc.trim(),
          ),
          primary: true,
          enabled: kind == 'cURL'
              ? text.trim().isNotEmpty
              : (file.trim().isNotEmpty || text.trim().isNotEmpty),
        ),
      ],
      content: [
        SizedBox(
          width: double.infinity,
          child: Dropdown(
            selected: kind,
            options: kinds,
            onSelect: (v) => setState(() {
              kind = v;
              file = '';
            }),
          ),
        ),
        if (needsFile) ...[
          SectionLabel(isFolder ? 'COLLECTION FOLDER' : 'FILE'),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Field(
                  value: file,
                  onChange: (v) => setState(() => file = v),
                  mono: true,
                  highlightVars: false,
                ),
              ),
              Btn(
                label: 'Browse…',
                icon: Ic.folder,
                onClick: () async {
                  final r = await (isFolder
                      ? plat.Platform.pickDirectory('Choose folder')
                      : plat.Platform.pickFile('Choose file'));
                  if (r != null && mounted) setState(() => file = r);
                },
              ),
            ],
          ),
        ],
        if (!isFolder) ...[
          SectionLabel(kind == 'cURL' ? 'CURL COMMAND' : 'OR PASTE CONTENT'),
          SizedBox(
            width: double.infinity,
            height: kind == 'cURL' ? 160 : 90,
            child: AreaField(
              value: text,
              onChange: (v) => setState(() => text = v),
              placeholder: "curl -X POST https://… -H 'Content-Type: application/json' -d '{…}'",
              expands: true,
            ),
          ),
        ],
        if (usesLocation) ...[
          const SectionLabel('CREATE COLLECTION IN'),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Field(
                  value: loc,
                  onChange: (v) => setState(() => loc = v),
                  mono: true,
                  highlightVars: false,
                ),
              ),
              Btn(
                label: 'Browse…',
                icon: Ic.folder,
                onClick: () async {
                  final d = await plat.Platform.pickDirectory(
                    'Choose location',
                  );
                  if (d != null && mounted) setState(() => loc = d);
                },
              ),
            ],
          ),
        ],
        T(
          switch (kind) {
            'cURL' => 'Adds the request to the currently selected collection.',
            'Postman Environment' =>
              'Adds the environment to the currently selected collection.',
            'Postman Environment (Global)' =>
              'Adds a global environment, available to every collection.',
            'Bruno Collection (folder)' => 'Converts a Bruno collection (.bru files with bruno.json, or the newer YAML layout with opencollection.yml) into a new OpenRest collection.',
            'OpenRest Collection (folder)' => 'Opens an existing OpenRest collection folder (contains openrest.yaml).',
            'OpenRest Bundle (YAML)' => 'Creates a collection from a single-file bundle exported by OpenRest.',
            'OpenAPI / Swagger' => 'JSON or YAML. Requests are grouped by tag; the server URL becomes {{baseUrl}} in a Default environment.',
            _ => 'Scripts using pm.* are converted to the bru/expect API where possible.',
          },
          color: p.muted,
          size: 12,
        ),
      ],
    );
  }
}

/// Dialog for exporting a collection.
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalExport m;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportFormat fmt = Exporters.formats.first;
  String dest = '';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final state = widget.state;
    final col = state.collection(widget.m.collection);
    if (col == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.modal = null);
      return const SizedBox.shrink();
    }
    final suggested = Collections.sanitize(col.name) + fmt.ext;
    Future<void> browse() async {
      final r = await (fmt.isDirectory
          ? plat.Platform.pickDirectory('Choose destination folder')
          : plat.Platform.saveFile('Export ${col.name}', suggested));
      if (r != null && mounted) setState(() => dest = r);
    }

    return ModalBox(
      title: 'Export — ${col.name}',
      onClose: () => state.modal = null,
      width: 640,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: 'Export',
          icon: Ic.export,
          onClick: () {
            state.modal = null;
            state.exportCollection(col.path, fmt.id, dest.trim());
          },
          primary: true,
          enabled: dest.trim().isNotEmpty,
        ),
      ],
      content: [
        const SectionLabel('FORMAT'),
        SizedBox(
          width: double.infinity,
          child: Dropdown(
            selected: fmt.label,
            options: [for (final f in Exporters.formats) f.label],
            onSelect: (l) => setState(() {
              fmt = Exporters.formats.firstWhere((f) => f.label == l);
              dest = '';
            }),
          ),
        ),
        T(fmt.hint, color: p.muted, size: 12),
        SectionLabel(
          fmt.isDirectory ? 'DESTINATION FOLDER' : 'DESTINATION FILE',
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Field(
                value: dest,
                onChange: (v) => setState(() => dest = v),
                placeholder: fmt.isDirectory ? '/path/to/folder' : suggested,
                mono: true,
                highlightVars: false,
              ),
            ),
            Btn(label: 'Browse…', onClick: browse, icon: Ic.folder),
          ],
        ),
      ],
    );
  }
}
