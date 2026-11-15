import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart' hide Chip;
import 'package:open_rest/components/buttons.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/core/model/model.dart' show HttpResult;
import 'package:open_rest/platform/platform.dart';
import 'package:open_rest/theme/icons.dart';
import 'package:open_rest/theme/theme.dart';

class ImagePreview extends StatefulWidget {
  const ImagePreview({super.key, required this.res});

  final HttpResult res;

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  ui.Image? _img;
  bool _failed = false;
  bool fit = true;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(ImagePreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.res, widget.res)) _decode();
  }

  Future<void> _decode() async {
    final res = widget.res;
    try {
      final codec = await ui.instantiateImageCodec(res.body);
      final f = await codec.getNextFrame();
      if (!mounted || !identical(res, widget.res)) return;
      setState(() {
        _img = f.image;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final res = widget.res;
    final bmp = _img;
    final deco = BoxDecoration(
      color: p.field,
      borderRadius: BorderRadius.circular(5),
    );
    // Border is painted over the content so it doesn't change the layout.
    final fdeco = BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: p.border, width: 1),
    );
    if (bmp == null) {
      return Container(
        decoration: deco,
        foregroundDecoration: fdeco,
        alignment: Alignment.center,
        child: T(
          _failed ? 'Cannot render this image format' : '',
          color: p.muted,
        ),
      );
    }
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
    final ct = res.contentType;
    final semi = ct.indexOf(';');
    final main = semi >= 0 ? ct.substring(0, semi) : ct;
    final slash = main.indexOf('/');
    final sub = (slash >= 0 ? main.substring(slash + 1) : main).toUpperCase();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: deco,
      foregroundDecoration: fdeco,
      child: Stack(
        children: [
          Positioned.fill(
            child: fit
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: RawImage(image: bmp, fit: BoxFit.contain),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: bmp.width / dpr,
                        height: bmp.height / dpr,
                        child: RawImage(image: bmp, fit: BoxFit.fill),
                      ),
                    ),
                  ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                spacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: p.panel.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: T(
                      '${bmp.width} × ${bmp.height}  ·  $sub',
                      color: p.muted,
                      size: 11,
                    ),
                  ),
                  Btn(
                    label: fit ? 'Actual size' : 'Fit',
                    onClick: () => setState(() => fit = !fit),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MediaPreview extends StatelessWidget {
  const MediaPreview({super.key, required this.res});

  final HttpResult res;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final full = res.contentType;
    final semi = full.indexOf(';');
    final ct = (semi >= 0 ? full.substring(0, semi) : full).toLowerCase();
    String subtype() {
      final s = ct.contains('/') ? ct.substring(ct.indexOf('/') + 1) : ct;
      final plus = s.indexOf('+');
      final r = plus >= 0 ? s.substring(0, plus) : s;
      return r.isEmpty ? 'bin' : r;
    }

    late IconData icon;
    late String label;
    late String ext;
    if (ct.contains('pdf')) {
      icon = Ic.pdf;
      label = 'PDF document';
      ext = '.pdf';
    } else if (ct.startsWith('audio/')) {
      icon = Ic.audio;
      label = 'Audio';
      ext = '.${subtype()}';
    } else if (ct.startsWith('video/')) {
      icon = Ic.video;
      label = 'Video';
      ext = '.${subtype()}';
    } else {
      icon = Ic.fileGeneric;
      label = 'Binary data';
      ext = '.bin';
    }
    final size = res.size < 1024
        ? '${res.size} B'
        : res.size < 1048576
        ? '${(res.size / 1024.0).toStringAsFixed(1)} KB'
        : '${(res.size / 1048576.0).toStringAsFixed(2)} MB';
    return Container(
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(5),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Ico(icon, tint: p.accent, size: 56),
            const SizedBox(height: 10),
            T(label, size: 15, weight: FontWeight.w600),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: T(
                '${ct.isEmpty ? "unknown type" : ct}  ·  $size',
                color: p.muted,
                size: 12,
              ),
            ),
            Btn(
              label: 'Open with default app',
              onClick: () => Platform.openBytes(res.body, ext),
              primary: true,
              icon: Ic.open,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: T(
                "This type can't be rendered inline. Use Save in the header to keep a copy.",
                color: p.muted,
                size: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
