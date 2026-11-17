import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/context_menu.dart';
import 'package:open_rest/components/drag_devices.dart';
import 'package:open_rest/components/field.dart';
import 'package:open_rest/components/modifiers.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart' show KV;
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';
import 'package:open_rest/utils/url_codec.dart';
import 'package:path/path.dart' as pathlib;

/// The value of a file row: just the file name, with the full path in a tooltip. Click it to edit the path (a
/// path can contain `{{variables}}`); an empty value is shown as an editable field straight away.
class _FileCell extends StatefulWidget {
  const _FileCell({required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  @override
  State<_FileCell> createState() => _FileCellState();
}

class _FileCellState extends State<_FileCell> {
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing && mounted) {
        setState(() => _editing = false);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _edit() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final empty = widget.value.trim().isEmpty;
    if (empty || _editing) {
      return Field(
        value: widget.value,
        onChange: widget.onChange,
        onEnter: () => _focus.unfocus(),
        focusRequester: _focus,
        placeholder: 'File path',
        mono: true,
        bordered: false,
        highlightVars: false,
      );
    }
    return Tooltip(
      message: widget.value,
      waitDuration: const Duration(milliseconds: 250),
      child: Clickable(
        onClick: _edit,
        cursor: SystemMouseCursors.text,
        child: Container(
          height: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: T(
            pathlib.basename(widget.value),
            mono: true,
            color: p.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _DecodeChip extends StatelessWidget {
  const _DecodeChip({required this.onClick});
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        onTap: onClick,
        indicate: true,
        borderRadius: BorderRadius.circular(10),
        builder: (ctx, hov) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: hov ? 0.3 : 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Ico(Ic.codec, tint: p.accent, size: 12),
              T('Decode', color: p.accent, size: 10, weight: FontWeight.w600),
            ],
          ),
        ),
      ),
    );
  }
}

const double _rowH = 34;
const double _handleW = 22;
const double _checkW = 26;

int _flex(double f) => math.max(1, (f * 100000).round());

/// A cell with a focus underline; content is a borderless Field.
class _TableCell extends StatefulWidget {
  const _TableCell({required this.child});
  final Widget child;

  @override
  State<_TableCell> createState() => _TableCellState();
}

class _TableCellState extends State<_TableCell> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => focused = f),
      child: CustomPaint(
        painter: _CellPainter(p, focused),
        child: Align(alignment: Alignment.centerLeft, child: widget.child),
      ),
    );
  }
}

class _CellPainter extends CustomPainter {
  _CellPainter(this.p, this.focused);
  final Pal p;
  final bool focused;
  @override
  void paint(Canvas canvas, Size size) {
    if (focused) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = p.accent.withValues(alpha: 0.07),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 2, size.width, 2),
        Paint()..color = p.accent,
      );
    }
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()
        ..color = p.border
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CellPainter old) => old.focused != focused || old.p != p;
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: T(text, color: p.accent, size: 10, weight: FontWeight.w700),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: kDragDevices,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(
            child: FractionallySizedBox(
              heightFactor: 0.55,
              child: Container(width: 1, color: p.border),
            ),
          ),
        ),
      ),
    );
  }
}

/// Editable key/value grid with enable toggles and drag-to-reorder rows.
class KVTable extends StatefulWidget {
  const KVTable({
    super.key,
    required this.items,
    required this.onChange,
    this.keyHint = 'Name',
    this.valueHint = 'Value',
    this.allowFile = false,
    this.onPickFiles,
    this.keySuggestions = const [],
    this.valueSuggestions,
    this.keyHints,
    this.encodeTools = false,
    this.title,
    this.extra,
    this.autoRows = const [],
    this.showAutoRows = true,
    this.onToggleAutoRows,
    this.autoLabel = 'Auto-generated',
    this.onCopy,
  });

  final List<KV> items;
  final ValueChanged<List<KV>> onChange;
  final String keyHint;
  final String valueHint;
  final bool allowFile;

  /// Opens a multi-select file dialog for a file row. The first file fills the row; each further file is added as
  /// its own row below it, with the same name and content type (repeated fields are how multipart sends many files).
  final Future<List<String>> Function()? onPickFiles;
  final List<String> keySuggestions;
  final List<String> Function(String)? valueSuggestions;
  final String? Function(String)? keyHints;
  final bool encodeTools;
  final String? title;

  /// Extra 74dp column at the end of each real row.
  final Widget Function(BuildContext context, int index, KV kv)? extra;

  /// Read-only rows shown under the editable ones, in the same columns (for example the headers the app adds by
  /// itself). A row's `note` is where it comes from. They never change [items].
  final List<TRow> autoRows;

  /// Whether [autoRows] are shown. With [onToggleAutoRows] set, an eye button in the toolbar flips it.
  final bool showAutoRows;
  final VoidCallback? onToggleAutoRows;

  /// Heading of the [autoRows] block.
  final String autoLabel;

  /// Called with a value when the copy button of an auto row is used.
  final void Function(String)? onCopy;

  @override
  State<KVTable> createState() => _KVTableState();
}

class _KVTableState extends State<KVTable> {
  bool bulk = false;
  String bulkText = '';
  double keyFrac = 0.4;
  double tableW = 1;
  int dragIdx = -1;
  double acc = 0;
  bool codecMenu = false;

  List<KV> get items => widget.items;

  void toggleBulk() {
    if (!bulk) {
      bulkText = items
          .map((it) => '${it.enabled ? "" : "//"}${it.name}: ${it.value}')
          .join('\n');
    }
    setState(() => bulk = !bulk);
  }

  Future<void> _pickFiles(int i) async {
    final paths = await widget.onPickFiles?.call() ?? const <String>[];
    // The table may have changed while the dialog was open: re-read it.
    final current = widget.items;
    if (paths.isEmpty || !mounted || i >= current.length) return;
    final row = current[i];
    widget.onChange(
      List<KV>.of(current)
        ..[i] = row.copyWith(value: paths.first)
        ..insertAll(i + 1, [
          for (final p in paths.skip(1)) row.copyWith(value: p),
        ]),
    );
  }

  void update(int i, KV Function(KV) f) {
    widget.onChange(
      i >= items.length
          ? [...items, f(const KV())]
          : (List<KV>.of(items)..[i] = f(items[i])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final extraW = widget.extra != null ? 74.0 : 0.0;
    final actionsW =
        (widget.allowFile ? 60.0 : 34.0) + (widget.encodeTools ? 26.0 : 0.0);
    final fixedPx = _handleW + _checkW + extraW + actionsW;

    final toolbar = Row(
      spacing: 8,
      children: [
        if (widget.title != null) SectionLabel(widget.title!.toUpperCase()),
        if (widget.onToggleAutoRows != null &&
            widget.autoRows.isNotEmpty &&
            !bulk)
          Tooltip(
            message: widget.showAutoRows
                ? 'Hide ${widget.autoLabel.toLowerCase()} rows (${widget.autoRows.length})'
                : 'Show ${widget.autoLabel.toLowerCase()} rows (${widget.autoRows.length})',
            child: IconBtn(
              key: const ValueKey('toggle-auto-rows'),
              icon: widget.showAutoRows ? Ic.eye : Ic.eyeOff,
              color: widget.showAutoRows ? p.accent : p.muted,
              onClick: widget.onToggleAutoRows!,
            ),
          ),
        if (items.isNotEmpty)
          Builder(
            builder: (_) {
              final on = items.where((it) => it.enabled).length;
              return _CountBadge(
                on == items.length ? '${items.length}' : '$on/${items.length}',
              );
            },
          ),
        const Spacer(),
        if (widget.encodeTools && items.isNotEmpty && !bulk)
          Stack(
            children: [
              IconBtn(
                icon: Ic.codec,
                onClick: () => setState(() => codecMenu = true),
              ),
              ContextMenu(
                open: codecMenu,
                onDismiss: () => setState(() => codecMenu = false),
                items: [
                  MenuItem(
                    'Decode all (URL)',
                    action: () => widget.onChange(
                      items
                          .map(
                            (it) => it.copyWith(
                              name: UrlCodec.decode(it.name),
                              value: UrlCodec.decode(it.value),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  MenuItem(
                    'Encode all (URL)',
                    action: () => widget.onChange(
                      items
                          .map(
                            (it) => it.copyWith(
                              name: UrlCodec.encode(it.name),
                              value: UrlCodec.encode(it.value),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        if (!widget.allowFile)
          IconBtn(
            icon: Ic.edit,
            onClick: toggleBulk,
            color: bulk ? p.accent : p.muted,
          ),
        if (!bulk)
          Btn(
            label: 'Add',
            onClick: () => widget.onChange([...items, const KV()]),
            icon: Ic.add,
          ),
      ],
    );

    if (bulk) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            toolbar,
            T(
              'One  name: value  per line · prefix a line with // to disable it',
              color: p.muted,
              size: 11,
            ),
            AreaField(
              value: bulkText,
              onChange: (t) {
                setState(() => bulkText = t);
                widget.onChange(
                  t.split('\n').where((l) => l.trim().isNotEmpty).map((line) {
                    final tl = line.trimLeft();
                    final off = tl.startsWith('//');
                    var body = off ? tl.substring(2) : tl;
                    body = body.trim();
                    final i = body.indexOf(':');
                    if (i < 0) return KV(name: body, value: '', enabled: !off);
                    return KV(
                      name: body.substring(0, i).trim(),
                      value: body.substring(i + 1).trim(),
                      enabled: !off,
                    );
                  }).toList(),
                );
              },
              placeholder: 'Name: value',
              minHeight: 160,
            ),
          ],
        ),
      );
    }

    final all = items.isNotEmpty && items.every((it) => it.enabled);
    final some = items.any((it) => it.enabled) && !all;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          toolbar,
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(8),
            ),
            // Border is painted over the content so it doesn't change the layout.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.border, width: 1),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                tableW = c.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // header
                    Container(
                      height: 30,
                      color: p.hover.withValues(alpha: 0.5),
                      child: DrawBottomBorder(
                        color: p.border,
                        child: Row(
                          children: [
                            const SizedBox(width: _handleW),
                            SizedBox(
                              width: _checkW,
                              child: Center(
                                child: Opacity(
                                  opacity: items.isEmpty ? 0.3 : 1,
                                  child: Check(
                                    checked: all,
                                    partial: some,
                                    onChange: (v) => widget.onChange(
                                      items
                                          .map(
                                            (it) =>
                                                it.copyWith(enabled: v || some),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: _flex(keyFrac),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      child: T(
                                        widget.keyHint.toUpperCase(),
                                        color: p.muted,
                                        size: 10,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  _ResizeHandle(
                                    onDrag: (dx) => setState(
                                      () => keyFrac =
                                          (keyFrac +
                                                  dx /
                                                      math.max(
                                                        tableW - fixedPx,
                                                        1,
                                                      ))
                                              .clamp(0.15, 0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: _flex(1 - keyFrac),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: T(
                                  widget.valueHint.toUpperCase(),
                                  color: p.muted,
                                  size: 10,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(width: extraW + actionsW),
                          ],
                        ),
                      ),
                    ),
                    // rows (+ one always-ready empty row); drag a row's handle to reorder
                    for (var i = 0; i <= items.length; i++)
                      _row(context, p, i, extraW, actionsW),
                    if (widget.showAutoRows && widget.autoRows.isNotEmpty) ...[
                      Container(
                        key: const ValueKey('auto-rows-label'),
                        height: 26,
                        color: p.hover.withValues(alpha: 0.5),
                        child: DrawBottomBorder(
                          color: p.border,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: _handleW + _checkW + 10,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 6,
                                children: [
                                  T(
                                    widget.autoLabel.toUpperCase(),
                                    color: p.muted,
                                    size: 10,
                                    weight: FontWeight.w600,
                                  ),
                                  T(
                                    '${widget.autoRows.length}',
                                    color: p.muted,
                                    size: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final r in widget.autoRows)
                              _autoRow(p, r, extraW, actionsW),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// A read-only row built like an editable one (same height, bottom rule, cell dividers, 13sp mono text and hover),
  /// marked as generated by a lock in the checkbox column and a chip saying where the value comes from.
  Widget _autoRow(Pal p, TRow r, double extraW, double actionsW) {
    return HoverBuilder(
      key: ValueKey('auto-${r.name}'),
      builder: (ctx, hov) => Container(
        height: _rowH,
        color: hov ? p.hover.withValues(alpha: 0.35) : const Color(0x00000000),
        child: CustomPaint(
          painter: _RowPainter(p, false),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: _handleW),
              SizedBox(
                width: _checkW,
                child: Center(child: Ico(Ic.lock, tint: p.muted, size: 13)),
              ),
              Expanded(
                flex: _flex(keyFrac),
                child: _TableCell(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: T(
                      r.name,
                      mono: true,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: _flex(1 - keyFrac),
                child: _TableCell(
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: T(
                            r.value,
                            mono: true,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (r.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            height: 15,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: p.border),
                            ),
                            // Not `T`: its fixed 24sp line box would not fit in a chip this small.
                            child: Text(
                              r.note,
                              key: ValueKey('auto-source-${r.name}'),
                              maxLines: 1,
                              strutStyle: const StrutStyle(
                                fontSize: 9,
                                height: 1,
                                forceStrutHeight: true,
                              ),
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 9,
                                height: 1,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: extraW),
              SizedBox(
                width: actionsW,
                child: Center(
                  child: hov && widget.onCopy != null
                      ? IconBtn(
                          icon: Ic.copy,
                          onClick: () => widget.onCopy!(r.value),
                          size: 15,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Pal p,
    int i,
    double extraW,
    double actionsW,
  ) {
    final ghost = i >= items.length;
    final kv = i < items.length ? items[i] : const KV();
    final dragging = dragIdx == i;
    return HoverBuilder(
      key: ValueKey(i),
      builder: (ctx, hov) {
        Widget dim(Widget w) =>
            Opacity(opacity: (kv.enabled || ghost) ? 1 : 0.45, child: w);
        return Container(
          height: _rowH,
          color: dragging
              ? p.selected
              : (hov && !ghost
                    ? p.hover.withValues(alpha: 0.35)
                    : const Color(0x00000000)),
          child: CustomPaint(
            painter: _RowPainter(p, dragging),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _handleW,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    supportedDevices: kDragDevices,
                    onVerticalDragStart: ghost
                        ? null
                        : (_) => setState(() {
                            dragIdx = i;
                            acc = 0;
                          }),
                    onVerticalDragUpdate: ghost
                        ? null
                        : (d) {
                            if (dragIdx < 0) return;
                            acc += d.delta.dy;
                            final l = List<KV>.of(items);
                            var moved = false;
                            void swap(int a, int b) {
                              final t = l[a];
                              l[a] = l[b];
                              l[b] = t;
                              moved = true;
                            }

                            var di = dragIdx;
                            while (acc > _rowH / 2 && di < l.length - 1) {
                              swap(di, di + 1);
                              di++;
                              acc -= _rowH;
                            }
                            while (acc < -_rowH / 2 && di > 0) {
                              swap(di, di - 1);
                              di--;
                              acc += _rowH;
                            }
                            if (moved) {
                              setState(() => dragIdx = di);
                              widget.onChange(l);
                            }
                          },
                    onVerticalDragEnd: (_) => setState(() => dragIdx = -1),
                    onVerticalDragCancel: () => setState(() => dragIdx = -1),
                    child: Center(
                      child: (!ghost && (hov || dragging))
                          ? const MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Ico(Ic.drag, size: 16),
                            )
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: _checkW,
                  child: Center(
                    child: Opacity(
                      opacity: ghost ? 0.25 : 1,
                      child: Check(
                        checked: kv.enabled && !ghost,
                        onChange: (v) =>
                            update(i, (k) => k.copyWith(enabled: v)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: _flex(keyFrac),
                  child: _TableCell(
                    child: dim(
                      Row(
                        children: [
                          Expanded(
                            child: Field(
                              value: kv.name,
                              onChange: (n) =>
                                  update(i, (k) => k.copyWith(name: n)),
                              placeholder: widget.keyHint,
                              mono: true,
                              bordered: false,
                              suggestions: widget.keySuggestions,
                              hints: widget.keyHints,
                            ),
                          ),
                          if (widget.encodeTools &&
                              !ghost &&
                              UrlCodec.looksEncoded(kv.name))
                            _DecodeChip(
                              onClick: () => update(
                                i,
                                (k) =>
                                    k.copyWith(name: UrlCodec.decode(k.name)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: _flex(1 - keyFrac),
                  child: _TableCell(
                    child: kv.isFile
                        ? dim(
                            Row(
                              children: [
                                Expanded(
                                  child: _FileCell(
                                    value: kv.value,
                                    onChange: (v) =>
                                        update(i, (k) => k.copyWith(value: v)),
                                  ),
                                ),
                                IconBtn(
                                  icon: Ic.folder,
                                  onClick: () => _pickFiles(i),
                                ),
                              ],
                            ),
                          )
                        : dim(
                            Row(
                              children: [
                                Expanded(
                                  child: Field(
                                    value: kv.value,
                                    onChange: (v) =>
                                        update(i, (k) => k.copyWith(value: v)),
                                    placeholder: widget.valueHint,
                                    mono: true,
                                    bordered: false,
                                    suggestions:
                                        widget.valueSuggestions?.call(
                                          kv.name,
                                        ) ??
                                        const [],
                                  ),
                                ),
                                if (widget.encodeTools &&
                                    !ghost &&
                                    UrlCodec.looksEncoded(kv.value))
                                  _DecodeChip(
                                    onClick: () => update(
                                      i,
                                      (k) => k.copyWith(
                                        value: UrlCodec.decode(k.value),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
                if (widget.extra != null)
                  SizedBox(
                    width: extraW,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        children: [if (!ghost) widget.extra!(context, i, kv)],
                      ),
                    ),
                  ),
                SizedBox(
                  width: actionsW,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!ghost) ...[
                        if (widget.allowFile)
                          IconBtn(
                            icon: kv.isFile ? Ic.attach : Ic.text,
                            onClick: () => update(
                              i,
                              (k) => k.copyWith(isFile: !k.isFile, value: ''),
                            ),
                            color: kv.isFile ? p.accent : p.muted,
                            size: 15,
                          ),
                        if (widget.encodeTools && hov)
                          _RowCodecMenu(onUpdate: (f) => update(i, f)),
                        if (hov)
                          IconBtn(
                            icon: Ic.delete,
                            onClick: () => widget.onChange(
                              List<KV>.of(items)..removeAt(i),
                            ),
                            color: p.err,
                            size: 16,
                          ),
                      ],
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RowPainter extends CustomPainter {
  _RowPainter(this.p, this.dragging);
  final Pal p;
  final bool dragging;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = p.border.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    if (dragging) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 3, size.height),
        Paint()..color = p.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_RowPainter old) => old.dragging != dragging || old.p != p;
}

class _RowCodecMenu extends StatefulWidget {
  const _RowCodecMenu({required this.onUpdate});
  final void Function(KV Function(KV)) onUpdate;

  @override
  State<_RowCodecMenu> createState() => _RowCodecMenuState();
}

class _RowCodecMenuState extends State<_RowCodecMenu> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      IconBtn(
        icon: Ic.codec,
        onClick: () => setState(() => open = true),
        size: 15,
      ),
      ContextMenu(
        open: open,
        onDismiss: () => setState(() => open = false),
        items: [
          MenuItem(
            'Decode value',
            action: () => widget.onUpdate(
              (k) => k.copyWith(value: UrlCodec.decode(k.value)),
            ),
          ),
          MenuItem(
            'Encode value',
            action: () => widget.onUpdate(
              (k) => k.copyWith(value: UrlCodec.encode(k.value)),
            ),
          ),
          MenuItem(
            'Decode name',
            action: () => widget.onUpdate(
              (k) => k.copyWith(name: UrlCodec.decode(k.name)),
            ),
          ),
          MenuItem(
            'Encode name',
            action: () => widget.onUpdate(
              (k) => k.copyWith(name: UrlCodec.encode(k.name)),
            ),
          ),
        ],
      ),
    ],
  );
}

class TRow {
  const TRow(this.name, this.value, [this.note = '']);
  final String name;
  final String value;
  final String note;
}

/// Read-only version of the key/value grid (same look): response headers, inherited headers, etc.
class ReadOnlyTable extends StatefulWidget {
  const ReadOnlyTable({
    super.key,
    required this.rows,
    this.keyHint = 'Name',
    this.valueHint = 'Value',
    this.noteHint,
    this.title,
    this.onCopy,
  });

  final List<TRow> rows;
  final String keyHint;
  final String valueHint;
  final String? noteHint;
  final String? title;
  final void Function(String)? onCopy;

  @override
  State<ReadOnlyTable> createState() => _ReadOnlyTableState();
}

class _ReadOnlyTableState extends State<ReadOnlyTable> {
  double keyFrac = 0.32;
  double tableW = 1;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final noteHint = widget.noteHint;
    final noteW = noteHint != null ? 110.0 : 0.0;
    final fixedPx = 34 + noteW;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (widget.title != null)
          Row(
            spacing: 8,
            children: [
              SectionLabel(widget.title!.toUpperCase()),
              _CountBadge('${widget.rows.length}'),
            ],
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(8),
          ),
          // Border is painted over the content so it doesn't change the layout.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.border, width: 1),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              tableW = c.maxWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 30,
                    color: p.hover.withValues(alpha: 0.5),
                    child: DrawBottomBorder(
                      color: p.border,
                      child: Row(
                        children: [
                          Expanded(
                            flex: _flex(keyFrac),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: T(
                                      widget.keyHint.toUpperCase(),
                                      color: p.muted,
                                      size: 10,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                _ResizeHandle(
                                  onDrag: (dx) => setState(
                                    () => keyFrac =
                                        (keyFrac +
                                                dx /
                                                    math.max(
                                                      tableW - fixedPx,
                                                      1,
                                                    ))
                                            .clamp(0.15, 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: _flex(1 - keyFrac),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: T(
                                widget.valueHint.toUpperCase(),
                                color: p.muted,
                                size: 10,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (noteHint != null)
                            SizedBox(
                              width: noteW,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: T(
                                  noteHint.toUpperCase(),
                                  color: p.muted,
                                  size: 10,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(width: 34),
                        ],
                      ),
                    ),
                  ),
                  SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final r in widget.rows)
                          HoverBuilder(
                            builder: (ctx, hov) => Container(
                              constraints: const BoxConstraints(
                                minHeight: _rowH,
                              ),
                              color: hov
                                  ? p.hover.withValues(alpha: 0.35)
                                  : const Color(0x00000000),
                              child: DrawBottomBorder(
                                color: p.border.withValues(alpha: 0.6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      flex: _flex(keyFrac),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: T(
                                          r.name,
                                          color: p.syntaxKey,
                                          mono: true,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: _flex(1 - keyFrac),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: T(r.value, mono: true),
                                      ),
                                    ),
                                    if (noteHint != null)
                                      SizedBox(
                                        width: noteW,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 10,
                                          ),
                                          child: T(
                                            r.note,
                                            color: p.muted,
                                            size: 11,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: 34,
                                      child: Center(
                                        child: hov
                                            ? IconBtn(
                                                icon: Ic.copy,
                                                onClick: () => widget.onCopy
                                                    ?.call(r.value),
                                                size: 15,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
