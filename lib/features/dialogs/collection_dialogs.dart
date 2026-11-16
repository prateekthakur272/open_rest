import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/layout.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/overlay.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/features/dialogs/dialogs.dart';
import 'package:open_rest/platform/platform.dart' as plat;
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

mixin _AutoFocus<T extends StatefulWidget> on State<T> {
  final FocusNode fr = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fr.requestFocus();
    });
  }

  @override
  void dispose() {
    fr.dispose();
    super.dispose();
  }
}

/// Dialog for creating a request.
class NewRequestDialog extends StatefulWidget {
  const NewRequestDialog({super.key, required this.state, required this.m});
  final AppState state;
  final ModalNewRequest m;

  @override
  State<NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends State<NewRequestDialog> with _AutoFocus {
  String name = '';
  String method = 'GET';
  String url = '';
  late bool graphql = widget.m.graphql;

  bool get isCurl => url.trimLeft().startsWith('curl ');

  void ok() {
    final state = widget.state;
    state.modal = null;
    if (isCurl) {
      state.createRequestFromCurl(widget.m.collection, widget.m.dir, url);
    } else {
      state.createRequest(
        widget.m.collection,
        widget.m.dir,
        name,
        method,
        url,
        graphql: graphql,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ModalBox(
      title: 'New Request',
      onClose: () => state.modal = null,
      width: 560,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: 'Create',
          onClick: ok,
          primary: true,
          enabled: isCurl || name.trim().isNotEmpty,
        ),
      ],
      content: [
        const SectionLabel('REQUEST TYPE'),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: _TypeCard(
                key: const ValueKey('new-type-http'),
                icon: Ic.http,
                title: 'HTTP',
                caption: 'REST & web APIs',
                color: context.pal.ok,
                selected: !graphql,
                onClick: () => setState(() => graphql = false),
              ),
            ),
            Expanded(
              child: _TypeCard(
                key: const ValueKey('new-type-graphql'),
                icon: Ic.graph,
                title: 'GraphQL',
                caption: 'Queries & schema',
                color: methodColor('GQL', context.pal),
                selected: graphql,
                onClick: () => setState(() => graphql = true),
              ),
            ),
            Expanded(
              child: _TypeCard(
                key: const ValueKey('new-type-websocket'),
                icon: Ic.websocket,
                title: 'WebSocket',
                caption: 'Live messages',
                color: context.pal.syntaxKeyword,
                selected: false,
                soon: true,
              ),
            ),
            Expanded(
              child: _TypeCard(
                key: const ValueKey('new-type-grpc'),
                icon: Ic.grpc,
                title: 'gRPC',
                caption: 'Protobuf services',
                color: context.pal.warn,
                selected: false,
                soon: true,
              ),
            ),
          ],
        ),
        const SectionLabel('NAME'),
        SizedBox(
          width: double.infinity,
          child: Field(
            value: name,
            onChange: (v) => setState(() => name = v),
            placeholder: graphql ? 'Countries' : 'Get users',
            focusRequester: fr,
            highlightVars: false,
          ),
        ),
        const SectionLabel('URL  (or paste a cURL command)'),
        Row(
          spacing: 8,
          children: [
            if (graphql)
              T(
                'GQL',
                color: methodColor('GQL', context.pal),
                weight: FontWeight.w700,
                size: 12,
              )
            else
              Dropdown(
                selected: method,
                options: HTTP_METHODS,
                onSelect: (v) => setState(() => method = v),
                color: methodColor(method, context.pal),
                weight: FontWeight.w700,
              ),
            Expanded(
              child: Field(
                value: url,
                onChange: (v) => setState(() => url = v),
                placeholder: graphql
                    ? 'https://api.example.com/graphql'
                    : 'https://api.example.com/users',
                mono: true,
                onEnter: () {
                  if (isCurl || name.trim().isNotEmpty) ok();
                },
                highlightVars: false,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Dialog for creating a collection.
class NewCollectionDialog extends StatefulWidget {
  const NewCollectionDialog({super.key, required this.state});
  final AppState state;

  @override
  State<NewCollectionDialog> createState() => _NewCollectionDialogState();
}

class _NewCollectionDialogState extends State<NewCollectionDialog>
    with _AutoFocus {
  String name = '';
  String loc = defaultDir;

  void ok() {
    widget.state.modal = null;
    final dir = loc.trim();
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {}
    widget.state.createCollection(dir, name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final p = context.pal;
    return ModalBox(
      title: 'New Collection',
      onClose: () => state.modal = null,
      width: 560,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: 'Create',
          onClick: ok,
          primary: true,
          enabled: name.trim().isNotEmpty && loc.trim().isNotEmpty,
        ),
      ],
      content: [
        const SectionLabel('NAME'),
        SizedBox(
          width: double.infinity,
          child: Field(
            value: name,
            onChange: (v) => setState(() => name = v),
            placeholder: 'My API',
            focusRequester: fr,
            highlightVars: false,
          ),
        ),
        const SectionLabel('LOCATION'),
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
                final d = await plat.Platform.pickDirectory('Choose location');
                if (d != null && mounted) setState(() => loc = d);
              },
            ),
          ],
        ),
        T(
          'A folder is created at the location above. Requests are stored as plain YAML files that work well with git. Export to Postman, Bruno, OpenAPI and more at any time.',
          color: p.muted,
          size: 12,
        ),
      ],
    );
  }
}

/// Dialog for opening an existing collection from disk.
class OpenCollectionDialog extends StatefulWidget {
  const OpenCollectionDialog({super.key, required this.state});
  final AppState state;

  @override
  State<OpenCollectionDialog> createState() => _OpenCollectionDialogState();
}

class _OpenCollectionDialogState extends State<OpenCollectionDialog> {
  String path = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ModalBox(
      title: 'Open Collection',
      onClose: () => state.modal = null,
      width: 560,
      actions: [
        Btn(label: 'Cancel', onClick: () => state.modal = null),
        Btn(
          label: 'Open',
          onClick: () {
            state.modal = null;
            state.openCollection(path.trim());
          },
          primary: true,
          enabled: path.trim().isNotEmpty,
        ),
      ],
      content: [
        const SectionLabel('COLLECTION FOLDER (contains openrest.yaml)'),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Field(
                value: path,
                onChange: (v) => setState(() => path = v),
                mono: true,
                highlightVars: false,
              ),
            ),
            Btn(
              label: 'Browse…',
              icon: Ic.folder,
              onClick: () async {
                final d = await plat.Platform.pickDirectory(
                  'Choose collection folder',
                );
                if (d != null && mounted) setState(() => path = d);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// A selectable protocol card of the new-request dialog: tinted icon, name and a one-line caption.
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    required this.selected,
    this.onClick,
    this.soon = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final bool selected;
  final VoidCallback? onClick;

  /// Not available yet: shown dimmed with a label and not clickable.
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fg = soon ? p.muted : color;
    return Opacity(
      opacity: soon ? 0.55 : 1,
      child: Clickable(
        onClick: soon ? () {} : (onClick ?? () {}),
        cursor: soon ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : p.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : p.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Ico(icon, tint: fg, size: 17)),
                  ),
                  const Spacer(),
                  if (soon)
                    T('Soon', color: p.muted, size: 10, weight: FontWeight.w600)
                  else if (selected)
                    Ico(Ic.check, tint: color, size: 15),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(
                    title,
                    weight: FontWeight.w600,
                    size: 13,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  T(
                    caption,
                    color: p.muted,
                    size: 11,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
