import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum IconShape { diamond, circle, square, ring, triangle, cross }

class IconPreset {
  const IconPreset(this.name, this.bg, this.fg, this.shape);
  final String name;
  final Color bg;
  final Color fg;
  final IconShape shape;
}

const iconPresets = [
  IconPreset('ماسة', Color(0xFF16202A), Color(0xFF4FC3F7), IconShape.diamond),
  IconPreset('دائرة', Color(0xFF1B1F3B), Color(0xFFB794F6), IconShape.circle),
  IconPreset('مربع', Color(0xFF14261E), Color(0xFF5BD38A), IconShape.square),
  IconPreset('حلقة', Color(0xFF2A1A12), Color(0xFFF5B84B), IconShape.ring),
  IconPreset('مثلث', Color(0xFF2A1520), Color(0xFFFF7A9C), IconShape.triangle),
  IconPreset('زائد', Color(0xFFE8EEF4), Color(0xFF0B1118), IconShape.cross),
];

/// يرسم القالب نفسه للمعاينة على الشاشة وعند توليد ملف PNG.
class PresetPainter extends CustomPainter {
  PresetPainter(this.preset);
  final IconPreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    canvas.drawRect(Offset.zero & size, Paint()..color = preset.bg);
    final fill = Paint()
      ..color = preset.fg
      ..isAntiAlias = true;
    RRect box(Offset center, double w, double h, double r) =>
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: w, height: h),
            Radius.circular(r));

    switch (preset.shape) {
      case IconShape.diamond:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRRect(box(Offset.zero, s * 0.42, s * 0.42, s * 0.06), fill);
        canvas.restore();
      case IconShape.circle:
        canvas.drawCircle(c, s * 0.24, fill);
      case IconShape.square:
        canvas.drawRRect(box(c, s * 0.46, s * 0.46, s * 0.08), fill);
      case IconShape.ring:
        canvas.drawCircle(
            c,
            s * 0.22,
            fill
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.09);
      case IconShape.triangle:
        final path = Path()
          ..moveTo(c.dx, c.dy - s * 0.25)
          ..lineTo(c.dx + s * 0.26, c.dy + s * 0.2)
          ..lineTo(c.dx - s * 0.26, c.dy + s * 0.2)
          ..close();
        canvas.drawPath(path, fill);
      case IconShape.cross:
        canvas.drawRRect(box(c, s * 0.5, s * 0.13, s * 0.04), fill);
        canvas.drawRRect(box(c, s * 0.13, s * 0.5, s * 0.04), fill);
    }
  }

  @override
  bool shouldRepaint(covariant PresetPainter old) => old.preset != preset;
}

Future<Uint8List> _encode(ui.PictureRecorder rec, int size) async {
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// يولّد أيقونة PNG مربعة (1024×1024) من أحد القوالب.
Future<Uint8List> presetToPng(IconPreset p, {int size = 1024}) async {
  final rec = ui.PictureRecorder();
  PresetPainter(p).paint(Canvas(rec), Size(size.toDouble(), size.toDouble()));
  return _encode(rec, size);
}

/// يحوّل أي صورة من الجهاز إلى PNG مربع بقصّ المنتصف.
Future<Uint8List> customIconToPng(Uint8List bytes, {int size = 1024}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final src = (await codec.getNextFrame()).image;
  final side = math.min(src.width, src.height).toDouble();
  final srcRect = Rect.fromLTWH(
      (src.width - side) / 2, (src.height - side) / 2, side, side);
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(
    src,
    srcRect,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  return _encode(rec, size);
}
