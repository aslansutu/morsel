import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The mascot from the app icon, drawn natively so it follows the theme: a barcode
/// rising out of a scanner frame, two eyes on top looking down at the bars.
/// Same geometry as tool/brand_icons.py, on a 1024 grid.
class MorselMark extends StatelessWidget {
  const MorselMark({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(
          bars: scheme.primary,
          brackets: scheme.primary.withValues(alpha: 0.4),
          ring: Theme.of(context).scaffoldBackgroundColor,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.bars, required this.brackets, required this.ring});

  final Color bars;
  final Color brackets;

  /// Painted around each eye to separate it from the bars; the colour behind the mark.
  final Color ring;

  static const _bars = [
    (300.0, 40.0), (362.0, 18.0), (404.0, 54.0), (480.0, 22.0),
    (526.0, 40.0), (588.0, 18.0), (630.0, 50.0), (702.0, 22.0),
  ];
  static const _eyes = [Offset(432, 448), Offset(592, 448)];

  static Path _corner(Offset start, Offset elbow, Offset arcEnd, Offset end, {required bool clockwise}) =>
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..arcToPoint(arcEnd, radius: const Radius.circular(50), clockwise: clockwise)
        ..lineTo(end.dx, end.dy);

  static final _brackets = [
    _corner(const Offset(150, 270), const Offset(150, 200), const Offset(200, 150), const Offset(270, 150), clockwise: true),
    _corner(const Offset(754, 150), const Offset(824, 150), const Offset(874, 200), const Offset(874, 270), clockwise: true),
    _corner(const Offset(150, 640), const Offset(150, 710), const Offset(200, 760), const Offset(270, 760), clockwise: false),
    _corner(const Offset(754, 760), const Offset(824, 760), const Offset(874, 710), const Offset(874, 640), clockwise: false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 1024)
      ..clipRect(const Rect.fromLTWH(0, 0, 1024, 1024));
    final stroke = Paint()
      ..color = brackets
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40
      ..strokeCap = StrokeCap.round;
    for (final path in _brackets) {
      canvas.drawPath(path, stroke);
    }
    final fill = Paint()..color = bars;
    for (final (x, w) in _bars) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 520, w, 600), Radius.circular(math.min(10, w / 2))),
        fill,
      );
    }
    for (final eye in _eyes) {
      final white = Rect.fromCenter(center: eye, width: 160, height: 148);
      canvas
        ..drawOval(white.inflate(8), Paint()..color = ring)
        ..drawOval(white, Paint()..color = Colors.white)
        ..drawCircle(eye + const Offset(8, 26), 36, Paint()..color = ink)
        ..drawCircle(eye + const Offset(19, 14), 11, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.bars != bars || old.brackets != brackets || old.ring != ring;
}

/// The logo's frame and bars without the eyes, simplified to stay crisp at icon size.
class ScanGlyph extends StatelessWidget {
  const ScanGlyph({super.key, required this.color, this.size = 26});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GlyphPainter(color));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24 grid.
    canvas
      ..save()
      ..scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (sx, sy) in const [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]) {
      // One corner bracket, mirrored into each corner around the centre.
      canvas
        ..save()
        ..translate(12, 12)
        ..scale(sx, sy)
        ..drawPath(
          Path()
            ..moveTo(-9, -4)
            ..lineTo(-9, -6.5)
            ..arcToPoint(const Offset(-6.5, -9), radius: const Radius.circular(2.5))
            ..lineTo(-4, -9),
          stroke,
        )
        ..restore();
    }
    final fill = Paint()..color = color;
    for (final (x, w) in const [(7.0, 2.0), (10.0, 1.25), (12.25, 2.5), (15.75, 1.25)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 7.5, w, 9), const Radius.circular(0.6)),
        fill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color;
}
