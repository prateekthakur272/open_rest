import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:open_rest/components/syntax_highlight.dart';

import 'package:open_rest/components/editing.dart';
import 'package:open_rest/components/field.dart' show LocalVars;
import 'package:open_rest/components/modifiers.dart' show overlayScrollbarTheme;
import 'package:open_rest/components/text.dart';
import 'package:open_rest/theme/theme.dart';

class _GutterPainter extends CustomPainter {
  _GutterPainter({
    required this.p,
    required this.ys,
    required this.gutterW,
    required this.curLine,
    required this.focused,
    required this.errorLine,
    required this.viewH,
    required this.scroll,
    required this.contentH,
  }) : super(repaint: scroll);

  final Pal p;
  final List<double> ys;
  final double gutterW;
  final int curLine;
  final bool focused;
  final int errorLine;
  final double viewH;
  final ScrollController scroll;
  final double contentH;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 10.0;
    const lineH = 19.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, gutterW, size.height),
      Paint()..color = p.hover.withValues(alpha: 0.35),
    );
    canvas.drawLine(
      Offset(gutterW, 0),
      Offset(gutterW, size.height),
      Paint()
        ..color = p.border
        ..strokeWidth = 1,
    );
    final viewTop = scroll.hasClients ? scroll.offset : 0.0;
    final viewBottom = viewTop + viewH;
    for (var i = 0; i < ys.length; i++) {
      final y = top + ys[i];
      if (y + lineH < viewTop - lineH || y > viewBottom + lineH) continue;
      final isErr = i + 1 == errorLine;
      if (isErr) {
        final nextY = i + 1 < ys.length ? top + ys[i + 1] : top + contentH;
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, math.max(lineH, nextY - y)),
          Paint()..color = p.err.withValues(alpha: 0.14),
        );
      }
      final color = isErr
          ? p.err
          : (i + 1 == curLine && focused
                ? p.text
                : p.muted.withValues(alpha: 0.65));
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontFamily: monoFamily,
            fontFamilyFallback: monoFallback,
            fontSize: 12,
            height: lineH / 12,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(gutterW - 10 - tp.width, y));
    }
  }

  @override
  bool shouldRepaint(_GutterPainter old) => true;
}

/// Multi-line editor with line numbers, syntax highlighting and search.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.value,
    required this.onChange,
    this.lang = 'text',
    this.readOnly = false,
    this.placeholder = '',
    this.showStatus = false,
    this.lineNumbers = true,
    this.errorLine = -1,
    this.scrollbar = false,
  });

  final String value;
  final ValueChanged<String> onChange;
  final String lang;
  final bool readOnly;
  final String placeholder;
  final bool showStatus;
  final bool lineNumbers;
  final int errorLine;

  /// Shows a vertical scrollbar along the right edge.
  final bool scrollbar;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final HighlightTransform _ctl = HighlightTransform();
  final ScrollController _vs = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _syncing = false;
  String _lastText = '';

  // Per-line layout cache.
  String? _layoutText;
  double _layoutW = -1;
  List<double> _ys = const [];
  double _contentH = 0;

  @override
  void initState() {
    super.initState();
    _ctl.text = widget.value;
    _lastText = widget.value;
    _ctl.addListener(_onCtl);
    _focus.addListener(() {
      if (mounted && _focused != _focus.hasFocus) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
  }

  void _onCtl() {
    if (_syncing || !mounted) return;
    final t = _ctl.text;
    setState(() {});
    if (t != _lastText) {
      _lastText = t;
      if (t != widget.value) widget.onChange(t);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctl.text != widget.value) {
          _setText(widget.value, widget.value.length);
        }
      });
    }
  }

  void _setText(String t, int caret) {
    _syncing = true;
    _ctl.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: caret.clamp(0, t.length)),
    );
    _lastText = t;
    _syncing = false;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (_ctl.text != widget.value) {
      _syncing = true;
      _ctl.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _lastText = widget.value;
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _vs.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _layoutLines(String text, double width, TextStyle style) {
    if (_layoutText == text && _layoutW == width) return;
    _layoutText = text;
    _layoutW = width;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(1, width));
    final ys = <double>[];
    var start = 0;
    while (true) {
      ys.add(tp.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy);
      final nl = text.indexOf('\n', start);
      if (nl < 0) break;
      start = nl + 1;
    }
    _ys = ys;
    _contentH = tp.height;
    tp.dispose();
  }

  Widget _withScrollbar(Widget scrollView) => widget.scrollbar
      ? overlayScrollbarTheme(Scrollbar(controller: _vs, child: scrollView))
      : scrollView;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final known = LocalVars.of(context);
    final style = TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: 13,
      height: 19 / 13,
      color: p.text,
    );
    _ctl.lang = widget.lang;
    _ctl.pal = p;
    _ctl.known = known;
    final text = _ctl.text;
    var lineCount = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) lineCount++;
    }
    final sel = _ctl.selection;
    final end = sel.isValid ? sel.end : text.length;
    final (ln, col) = lineCol(text, end);
    final gutterW = widget.lineNumbers
        ? (math.max(2, lineCount.toString().length) * 8 + 20).toDouble()
        : 0.0;
    final readOnly = widget.readOnly;

    return LayoutBuilder(
      builder: (context, cons) {
        final minH = cons.hasBoundedHeight ? cons.maxHeight : 0.0;
        final textW = cons.maxWidth - gutterW - 20 - 3;
        if (widget.lineNumbers) _layoutLines(text, textW, style);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(5),
          ),
          // Border is painted over the content so it doesn't change the layout.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _focused ? p.accent.withValues(alpha: 0.7) : p.border,
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              _withScrollbar(
                SingleChildScrollView(
                  controller: _vs,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minH),
                    child: CustomPaint(
                      painter: widget.lineNumbers
                          ? _GutterPainter(
                              p: p,
                              ys: _ys,
                              gutterW: gutterW,
                              curLine: ln,
                              focused: _focused,
                              errorLine: widget.errorLine,
                              viewH: minH,
                              scroll: _vs,
                              contentH: _contentH,
                            )
                          : null,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!_focus.hasFocus) {
                            _focus.requestFocus();
                            _ctl.selection = TextSelection.collapsed(
                              offset: _ctl.text.length,
                            );
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: gutterW + 10,
                            right: 10,
                            top: 10,
                            bottom: widget.showStatus ? 30 : 10,
                          ),
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onKeyEvent: (node, e) {
                              if (readOnly ||
                                  (e is! KeyDownEvent &&
                                      e is! KeyRepeatEvent) ||
                                  e.logicalKey != LogicalKeyboardKey.tab) {
                                return KeyEventResult.ignored;
                              }
                              if (!HardwareKeyboard.instance.isShiftPressed) {
                                final s = _ctl.selection;
                                final a = math.min(s.start, s.end),
                                    b = math.max(s.start, s.end);
                                final nt = _ctl.text.replaceRange(a, b, '  ');
                                _setText(nt, a + 2);
                                _lastText = nt;
                                widget.onChange(nt);
                              }
                              return KeyEventResult.handled;
                            },
                            child: TextField(
                              controller: _ctl,
                              focusNode: _focus,
                              readOnly: readOnly,
                              style: style,
                              cursorColor: p.accent,
                              cursorWidth: 2,
                              cursorRadius: Radius.zero,
                              cursorOpacityAnimates: false,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              scrollPhysics:
                                  const NeverScrollableScrollPhysics(),
                              autocorrect: false,
                              enableSuggestions: false,
                              onTapOutside: (_) {},
                              inputFormatters: readOnly
                                  ? null
                                  : [
                                      TextInputFormatter.withFunction(
                                        (o, n) => smartEdit(o, n, widget.lang),
                                      ),
                                    ],
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                                hintText: widget.placeholder,
                                hintStyle: style.copyWith(
                                  color: p.muted.withValues(alpha: 0.6),
                                  letterSpacing: bodyLetterSpacing,
                                  leadingDistribution:
                                      TextLeadingDistribution.even,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.showStatus)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.panel.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      spacing: 10,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        T(
                          'Ln $ln, Col $col',
                          color: p.muted,
                          size: 11,
                          mono: true,
                        ),
                        T('${text.length} chars', color: p.muted, size: 11),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
