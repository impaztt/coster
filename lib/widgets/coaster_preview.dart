import 'package:flutter/material.dart';

import '../models/coaster.dart';
import 'coaster_shape_painter.dart';

/// Small static preview of a coaster (no tap, no sparkle animation).
class CoasterPreview extends StatelessWidget {
  final CoasterVisual visual;
  final double size;
  final bool locked;

  const CoasterPreview({
    super.key,
    required this.visual,
    this.size = 80,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PreviewPainter(visual: visual, locked: locked),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final CoasterVisual visual;
  final bool locked;

  _PreviewPainter({required this.visual, required this.locked});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    if (!locked) {
      canvas.drawCircle(
        Offset(cx, h / 2),
        w * 0.48,
        Paint()
          ..shader = RadialGradient(
            colors: [
              visual.auraColor.withValues(alpha: visual.auraIntensity * 0.8),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: Offset(cx, h / 2), radius: w * 0.48),
          ),
      );
    }

    final colors = locked
        ? const CoasterShapeColors(
            rail: Color(0xFF424242),
            railAccent: Color(0xFF212121),
            trim: Color(0xFF424242),
            wheel: Color(0xFF212121),
            light: Color(0xFF424242),
          )
        : CoasterShapeColors.fromVisual(visual);

    paintCoasterShape(
      canvas,
      size,
      visual.shape,
      colors,
      outlineWidth: 2,
    );

    if (locked) {
      canvas.drawCircle(
        Offset(cx, h * 0.5),
        w * 0.18,
        Paint()..color = Colors.white.withValues(alpha: 0.1),
      );
      final tp = TextPainter(
        text: const TextSpan(
          text: '?',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(cx - tp.width / 2, h * 0.5 - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) =>
      oldDelegate.visual != visual || oldDelegate.locked != locked;
}
