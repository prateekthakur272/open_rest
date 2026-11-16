import 'dart:io' show File;

import 'package:flutter/widgets.dart';
import 'package:open_rest/components/segmented.dart';
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart';
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

/// Editor for TLS client certificate settings (collection, folder or request).
class TlsEditor extends StatelessWidget {
  const TlsEditor({
    super.key,
    required this.config,
    required this.onChange,
    this.inheritLabel = 'Inherit',
    this.allowNone = true,
    this.baseDir,
  });

  final TlsConfig config;
  final ValueChanged<TlsConfig> onChange;

  /// Label of the inherit option, e.g. "Inherit from folder / collection".
  final String inheritLabel;

  /// Whether the explicit "No certificate" option is offered (not needed at collection level).
  final bool allowNone;

  /// Directory that relative paths resolve against (the collection folder); used for the file status only.
  final String? baseDir;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = config;
    // One selector covers the mode and the certificate format: Custom is split into its two formats.
    const pfxLabel = 'PFX / PKCS#12';
    const pemLabel = 'PEM';
    final options = [
      inheritLabel,
      if (allowNone) 'No certificate',
      pfxLabel,
      pemLabel,
    ];
    final selected = switch (c.mode) {
      TlsMode.inherit => inheritLabel,
      TlsMode.none => 'No certificate',
      TlsMode.custom => c.format == TlsFormat.pem ? pemLabel : pfxLabel,
    };
    void select(String label) {
      if (label == inheritLabel) {
        onChange(c.copyWith(mode: TlsMode.inherit));
      } else if (label == 'No certificate') {
        onChange(c.copyWith(mode: TlsMode.none));
      } else {
        onChange(
          c.copyWith(
            mode: TlsMode.custom,
            format: label == pemLabel ? TlsFormat.pem : TlsFormat.pfx,
          ),
        );
      }
    }

    Widget row(
      String label,
      String value,
      ValueChanged<String> set, {
      required String placeholder,
      required String pickTitle,
      bool browse = true,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 3,
        children: [
          Row(
            spacing: 6,
            children: [
              SizedBox(width: 110, child: T(label, color: pal.muted, size: 12)),
              Expanded(
                child: Field(
                  value: value,
                  onChange: set,
                  placeholder: placeholder,
                  mono: true,
                ),
              ),
              if (browse)
                Btn(
                  label: 'Browse',
                  icon: Ic.folder,
                  onClick: () async {
                    final f = await Platform.pickFile(pickTitle);
                    if (f != null) set(f);
                  },
                ),
              if (value.isNotEmpty)
                IconBtn(
                  icon: Ic.close,
                  onClick: () => set(''),
                  color: pal.muted,
                ),
            ],
          ),
          if (value.trim().isNotEmpty && !value.contains('{{'))
            Padding(
              padding: const EdgeInsets.only(left: 116),
              child: _status(pal, value),
            ),
        ],
      );
    }

    final pem = c.format == TlsFormat.pem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Segmented(
            options: options,
            selected: selected,
            onSelect: select,
          ),
        ),
        if (c.mode == TlsMode.inherit)
          T(
            'Uses the client certificate set on the parent folder or collection, if any.',
            color: pal.muted,
            size: 12,
          ),
        if (c.mode == TlsMode.none)
          T(
            'No client certificate is sent, even if a parent defines one.',
            color: pal.muted,
            size: 12,
          ),
        if (c.mode == TlsMode.custom) ...[
          if (!pem)
            row(
              'PFX file',
              c.pfxPath,
              (v) => onChange(c.copyWith(pfxPath: v)),
              placeholder: '/path/to/client.pfx',
              pickTitle: 'Choose PFX file',
            )
          else ...[
            row(
              'Certificate',
              c.certPath,
              (v) => onChange(c.copyWith(certPath: v)),
              placeholder: '/path/to/client.crt',
              pickTitle: 'Choose certificate',
            ),
            row(
              'Private key',
              c.keyPath,
              (v) => onChange(c.copyWith(keyPath: v)),
              placeholder: '/path/to/client.key',
              pickTitle: 'Choose private key',
            ),
          ],
          row(
            'CA bundle',
            c.caPath,
            (v) => onChange(c.copyWith(caPath: v)),
            placeholder: 'Optional: trust a private CA',
            pickTitle: 'Choose CA bundle',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 3,
            children: [
              Row(
                spacing: 6,
                children: [
                  SizedBox(
                    width: 110,
                    child: T('Passphrase', color: pal.muted, size: 12),
                  ),
                  Expanded(
                    child: Field(
                      value: c.passphrase,
                      onChange: (v) => onChange(c.copyWith(passphrase: v)),
                      placeholder: '{{certPassphrase}}',
                      mono: true,
                      password: true,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 116),
                child: T(
                  'Use a secret environment variable such as {{certPassphrase}} so the passphrase is not saved in the collection files.',
                  color: pal.muted,
                  size: 11,
                ),
              ),
            ],
          ),
          T(
            'Only file paths are stored, never the certificate contents. Relative paths are resolved from the collection folder; absolute paths do not carry over to other machines.',
            color: pal.muted,
            size: 11,
          ),
        ],
      ],
    );
  }

  Widget _status(Pal pal, String path) {
    var v = path.trim();
    if (baseDir != null && !File(v).isAbsolute) v = '$baseDir/$v';
    final ok = File(v).existsSync();
    return T(
      ok ? 'File found' : 'File not found',
      color: ok ? pal.ok : pal.err,
      size: 11,
    );
  }
}
