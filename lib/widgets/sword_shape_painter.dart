import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/sword.dart';

/// Resolved colors for one sword draw. Decoupled from [SwordVisual] so the
/// "locked" preview state can substitute greyed-out colors without forking
/// the geometry code.
class SwordShapeColors {
  final Color blade;
  final Color bladeAccent;
  final Color guard;
  final Color handle;
  final Color pommel;

  const SwordShapeColors({
    required this.blade,
    required this.bladeAccent,
    required this.guard,
    required this.handle,
    required this.pommel,
  });

  factory SwordShapeColors.fromVisual(SwordVisual v) => SwordShapeColors(
        blade: v.bladeColor,
        bladeAccent: v.bladeAccent,
        guard: v.guardColor,
        handle: v.handleColor,
        pommel: v.pommelColor,
      );
}

/// Render a sword of the requested [shape] inside [size]. The aura, sparkle,
/// and locked overlay are intentionally not drawn here — callers (the main
/// [SwordWidget] and the [SwordPreview]) layer those on themselves.
void paintSwordShape(
  Canvas canvas,
  Size size,
  SwordShape shape,
  SwordShapeColors colors, {
  required double outlineWidth,
}) {
  final outline = Paint()
    ..color = AppColors.outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = outlineWidth
    ..strokeJoin = StrokeJoin.round;
  switch (shape) {
    case SwordShape.dagger:
      _paintDagger(canvas, size, colors, outline, outlineWidth);
    case SwordShape.longsword:
      _paintLongsword(canvas, size, colors, outline, outlineWidth);
    case SwordShape.claymore:
      _paintClaymore(canvas, size, colors, outline, outlineWidth);
    case SwordShape.katana:
      _paintKatana(canvas, size, colors, outline, outlineWidth);
    case SwordShape.rapier:
      _paintRapier(canvas, size, colors, outline, outlineWidth);
    case SwordShape.falchion:
      _paintFalchion(canvas, size, colors, outline, outlineWidth);
  }
}

// =============================================================================
// Shape implementations. All work in the same (w, h) canvas frame; the
// existing widget callers sit the painter inside an aspect ratio that's
// roughly 0.82 (taller than wide), so vertical extents up to ~h*0.96 are
// safe to use without clipping.
// =============================================================================

void _paintLongsword(
    Canvas canvas, Size size, SwordShapeColors c, Paint outline, double sw) {
  final w = size.width;
  final h = size.height;
  final cx = w / 2;

  final bladePath = Path()
    ..moveTo(cx, h * 0.04)
    ..lineTo(cx + w * 0.10, h * 0.14)
    ..lineTo(cx + w * 0.10, h * 0.58)
    ..lineTo(cx - w * 0.10, h * 0.58)
    ..lineTo(cx - w * 0.10, h * 0.14)
    ..close();
  canvas.drawPath(bladePath, Paint()..color = c.blade);

  final bladeShadowPath = Path()
    ..moveTo(cx + w * 0.04, h * 0.10)
    ..lineTo(cx + w * 0.10, h * 0.14)
    ..lineTo(cx + w * 0.10, h * 0.58)
    ..lineTo(cx + w * 0.04, h * 0.58)
    ..close();
  canvas.drawPath(
    bladeShadowPath,
    Paint()..color = c.bladeAccent.withValues(alpha: 0.6),
  );
  canvas.drawLine(
    Offset(cx, h * 0.10),
    Offset(cx, h * 0.55),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = sw * 0.75
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(bladePath, outline);

  final guardRect =
      Rect.fromLTWH(cx - w * 0.36, h * 0.58, w * 0.72, h * 0.06);
  final guardRRect =
      RRect.fromRectAndRadius(guardRect, const Radius.circular(6));
  canvas.drawRRect(guardRRect, Paint()..color = c.guard);
  canvas.drawRRect(guardRRect, outline);

  final handleRect = Rect.fromLTWH(cx - w * 0.06, h * 0.64, w * 0.12, h * 0.24);
  final handleRRect =
      RRect.fromRectAndRadius(handleRect, const Radius.circular(8));
  canvas.drawRRect(handleRRect, Paint()..color = c.handle);
  canvas.drawRRect(handleRRect, outline);

  final handleHighlight =
      Rect.fromLTWH(cx - w * 0.04, h * 0.66, w * 0.025, h * 0.20);
  canvas.drawRRect(
    RRect.fromRectAndRadius(handleHighlight, const Radius.circular(2)),
    Paint()..color = Colors.white.withValues(alpha: 0.35),
  );

  canvas.drawCircle(
    Offset(cx, h * 0.92),
    w * 0.09,
    Paint()..color = c.pommel,
  );
  canvas.drawCircle(Offset(cx, h * 0.92), w * 0.09, outline);
  canvas.drawCircle(
    Offset(cx - w * 0.025, h * 0.90),
    w * 0.025,
    Paint()..color = Colors.white.withValues(alpha: 0.6),
  );
}

void _paintDagger(
    Canvas canvas, Size size, SwordShapeColors c, Paint outline, double sw) {
  final w = size.width;
  final h = size.height;
  final cx = w / 2;

  // Short, leaf-shaped blade — much shorter than longsword.
  final bladePath = Path()
    ..moveTo(cx, h * 0.20)
    ..lineTo(cx + w * 0.085, h * 0.30)
    ..lineTo(cx + w * 0.075, h * 0.55)
    ..lineTo(cx - w * 0.075, h * 0.55)
    ..lineTo(cx - w * 0.085, h * 0.30)
    ..close();
  canvas.drawPath(bladePath, Paint()..color = c.blade);

  final shadowPath = Path()
    ..moveTo(cx + w * 0.03, h * 0.26)
    ..lineTo(cx + w * 0.085, h * 0.30)
    ..lineTo(cx + w * 0.075, h * 0.55)
    ..lineTo(cx + w * 0.03, h * 0.55)
    ..close();
  canvas.drawPath(
    shadowPath,
    Paint()..color = c.bladeAccent.withValues(alpha: 0.6),
  );
  canvas.drawLine(
    Offset(cx, h * 0.26),
    Offset(cx, h * 0.53),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = sw * 0.6
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(bladePath, outline);

  // Compact cross guard.
  final guardRect =
      Rect.fromLTWH(cx - w * 0.22, h * 0.55, w * 0.44, h * 0.05);
  final guardRR =
      RRect.fromRectAndRadius(guardRect, const Radius.circular(4));
  canvas.drawRRect(guardRR, Paint()..color = c.guard);
  canvas.drawRRect(guardRR, outline);

  // Short grip.
  final handleRect =
      Rect.fromLTWH(cx - w * 0.05, h * 0.60, w * 0.10, h * 0.20);
  final handleRR =
      RRect.fromRectAndRadius(handleRect, const Radius.circular(6));
  canvas.drawRRect(handleRR, Paint()..color = c.handle);
  canvas.drawRRect(handleRR, outline);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.035, h * 0.62, w * 0.022, h * 0.16),
      const Radius.circular(2),
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.35),
  );

  // Small pommel.
  canvas.drawCircle(
    Offset(cx, h * 0.84),
    w * 0.06,
    Paint()..color = c.pommel,
  );
  canvas.drawCircle(Offset(cx, h * 0.84), w * 0.06, outline);
  canvas.drawCircle(
    Offset(cx - w * 0.018, h * 0.83),
    w * 0.018,
    Paint()..color = Colors.white.withValues(alpha: 0.6),
  );
}

void _paintClaymore(
    Canvas canvas, Size size, SwordShapeColors c, Paint outline, double sw) {
  final w = size.width;
  final h = size.height;
  final cx = w / 2;

  // Long broad blade.
  final bladePath = Path()
    ..moveTo(cx, h * 0.02)
    ..lineTo(cx + w * 0.13, h * 0.12)
    ..lineTo(cx + w * 0.13, h * 0.60)
    ..lineTo(cx - w * 0.13, h * 0.60)
    ..lineTo(cx - w * 0.13, h * 0.12)
    ..close();
  canvas.drawPath(bladePath, Paint()..color = c.blade);

  final shadowPath = Path()
    ..moveTo(cx + w * 0.04, h * 0.08)
    ..lineTo(cx + w * 0.13, h * 0.12)
    ..lineTo(cx + w * 0.13, h * 0.60)
    ..lineTo(cx + w * 0.04, h * 0.60)
    ..close();
  canvas.drawPath(
    shadowPath,
    Paint()..color = c.bladeAccent.withValues(alpha: 0.6),
  );
  // Wide central fuller.
  canvas.drawLine(
    Offset(cx, h * 0.08),
    Offset(cx, h * 0.58),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = sw * 0.9
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(bladePath, outline);

  // Wide cross guard with quillon caps (small circles on the ends).
  final guardRect =
      Rect.fromLTWH(cx - w * 0.42, h * 0.60, w * 0.84, h * 0.07);
  final guardRR =
      RRect.fromRectAndRadius(guardRect, const Radius.circular(8));
  canvas.drawRRect(guardRR, Paint()..color = c.guard);
  canvas.drawRRect(guardRR, outline);
  canvas.drawCircle(
      Offset(cx - w * 0.42, h * 0.635), w * 0.045, Paint()..color = c.guard);
  canvas.drawCircle(Offset(cx - w * 0.42, h * 0.635), w * 0.045, outline);
  canvas.drawCircle(
      Offset(cx + w * 0.42, h * 0.635), w * 0.045, Paint()..color = c.guard);
  canvas.drawCircle(Offset(cx + w * 0.42, h * 0.635), w * 0.045, outline);

  // Two-handed grip with leather wraps drawn as separators.
  final handleRect =
      Rect.fromLTWH(cx - w * 0.07, h * 0.67, w * 0.14, h * 0.24);
  final handleRR =
      RRect.fromRectAndRadius(handleRect, const Radius.circular(8));
  canvas.drawRRect(handleRR, Paint()..color = c.handle);
  canvas.drawRRect(handleRR, outline);
  for (var i = 0; i < 3; i++) {
    final y = h * 0.72 + i * h * 0.06;
    canvas.drawLine(
      Offset(cx - w * 0.06, y),
      Offset(cx + w * 0.06, y),
      Paint()
        ..color = AppColors.outline.withValues(alpha: 0.55)
        ..strokeWidth = sw * 0.5,
    );
  }

  // Hex pommel.
  final pommelPath = Path()
    ..moveTo(cx, h * 0.91)
    ..lineTo(cx + w * 0.10, h * 0.95)
    ..lineTo(cx, h * 0.99)
    ..lineTo(cx - w * 0.10, h * 0.95)
    ..close();
  canvas.drawPath(pommelPath, Paint()..color = c.pommel);
  canvas.drawPath(pommelPath, outline);
}

void _paintKatana(
    Canvas canvas, Size size, SwordShapeColors c, Paint outline, double sw) {
  final w = size.width;
  final h = size.height;
  final cx = w / 2;

  // Curved single-edge blade. Use bezier to bend the silhouette to one side.
  final bladePath = Path()
    ..moveTo(cx + w * 0.04, h * 0.06)
    ..quadraticBezierTo(cx + w * 0.14, h * 0.34, cx + w * 0.06, h * 0.58)
    ..lineTo(cx - w * 0.10, h * 0.58)
    ..quadraticBezierTo(cx - w * 0.02, h * 0.32, cx - w * 0.04, h * 0.08)
    ..close();
  canvas.drawPath(bladePath, Paint()..color = c.blade);

  // Spine shadow on the back (right) edge.
  final spinePath = Path()
    ..moveTo(cx + w * 0.025, h * 0.10)
    ..quadraticBezierTo(cx + w * 0.10, h * 0.34, cx + w * 0.045, h * 0.56)
    ..lineTo(cx + w * 0.06, h * 0.58)
    ..quadraticBezierTo(cx + w * 0.14, h * 0.34, cx + w * 0.04, h * 0.06)
    ..close();
  canvas.drawPath(
    spinePath,
    Paint()..color = c.bladeAccent.withValues(alpha: 0.55),
  );
  // Hamon (cutting edge highlight) along the curving inner edge.
  final hamon = Path()
    ..moveTo(cx - w * 0.07, h * 0.12)
    ..quadraticBezierTo(cx - w * 0.005, h * 0.32, cx - w * 0.07, h * 0.55);
  canvas.drawPath(
    hamon,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw * 0.6
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(bladePath, outline);

  // Tsuba (disc guard).
  canvas.drawCircle(
    Offset(cx, h * 0.60),
    w * 0.18,
    Paint()..color = c.guard,
  );
  canvas.drawCircle(Offset(cx, h * 0.60), w * 0.18, outline);
  canvas.drawCircle(
    Offset(cx, h * 0.60),
    w * 0.07,
    Paint()..color = c.handle,
  );

  // Long wrapped grip.
  final handleRect =
      Rect.fromLTWH(cx - w * 0.06, h * 0.66, w * 0.12, h * 0.28);
  final handleRR =
      RRect.fromRectAndRadius(handleRect, const Radius.circular(4));
  canvas.drawRRect(handleRR, Paint()..color = c.handle);
  canvas.drawRRect(handleRR, outline);
  // Diamond ito (wrap) pattern.
  for (var i = 0; i < 4; i++) {
    final y = h * 0.69 + i * h * 0.06;
    canvas.drawLine(
      Offset(cx - w * 0.055, y),
      Offset(cx + w * 0.055, y + h * 0.03),
      Paint()
        ..color = AppColors.outline.withValues(alpha: 0.55)
        ..strokeWidth = sw * 0.45,
    );
    canvas.drawLine(
      Offset(cx + w * 0.055, y),
      Offset(cx - w * 0.055, y + h * 0.03),
      Paint()
        ..color = AppColors.outline.withValues(alpha: 0.55)
        ..strokeWidth = sw * 0.45,
    );
  }

  // Kashira (rectangular cap pommel).
  final cap = Rect.fromLTWH(cx - w * 0.07, h * 0.93, w * 0.14, h * 0.04);
  final capRR = RRect.fromRectAndRadius(cap, const Radius.circular(2));
  canvas.drawRRect(capRR, Paint()..color = c.pommel);
  canvas.drawRRect(capRR, outline);
}

void _paintRapier(
    Canvas canvas, Size size, SwordShapeColors c, Paint outline, double sw) {
  final w = size.width;
  final h = size.height;
  final cx = w / 2;

  // Very thin, long stabbing blade.
  final bladePath = Path()
    ..moveTo(cx, h * 0.03)
    ..lineTo(cx + w * 0.025, h * 0.10)
    ..lineTo(cx + w * 0.030, h * 0.60)
    ..lineTo(cx - w * 0.030, h * 0.60)
    ..lineTo(cx - w * 0.025, h * 0.10)
    ..close();
  canvas.drawPath(bladePath, Paint()..color = c.blade);
  canvas.drawLine(
    Offset(cx, h * 0.08),
    Offset(cx, h * 0.58),
    Paint()
      ..color = c.bladeAccent.withValues(alpha: 0.7)
      ..strokeWidth = sw * 0.55
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(bladePath, outline);

  // Thin straight cross guard.
  final guardRect =
      Rect.fromLTWH(cx - w * 0.20, h * 0.60, w * 0.40, h * 0.035);
  final guardRR =
      RRect.fromRectAndRadius(guardRect, const Radius.circular(3));
  canvas.drawRRect(guardRR, Paint()..color = c.guard);
  canvas.drawRRect(guardRR, outline);

  // Swept knuckle bow — both sides — drawn as stroked beziers.
  final guardPaint = Paint()
    ..color = c.guard
    ..style = PaintingStyle.stroke
    ..strokeWidth = sw * 1.3
    ..strokeCap = StrokeCap.round;
  final bowOutline = Paint()
    ..color = AppColors.outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = sw * 0.9
    ..strokeCap = StrokeCap.round;
  final bowR = Path()
    ..moveTo(cx + w * 0.18, h * 0.63)
    ..quadraticBezierTo(cx + w * 0.22, h * 0.78, cx + w * 0.05, h * 0.88);
  final bowL = Path()
    ..moveTo(cx - w * 0.18, h * 0.63)
    ..quadraticBezierTo(cx - w * 0.22, h * 0.78, cx - w * 0.05, h * 0.88);
  canvas.drawPath(bowR, guardPaint);
  canvas.drawPath(bowR, bowOutline);
  canvas.drawPath(bowL, guardPaint);
  canvas.drawPath(bowL, bowOutline);

  // Slim grip.
  final handleRect =
      Rect.fromLTWH(cx - w * 0.025, h * 0.635, w * 0.05, h * 0.25);
  final handleRR =
      RRect.fromRectAndRadius(handleRect, const Radius.circular(4));
  canvas.drawRRect(handleRR, Paint()..color = c.handle);
  canvas.drawRRect(handleRR, outline);

  // Sphere pommel, slightly larger than longsword.
  canvas.drawCircle(
    Offset(cx, h * 0.92),
    w * 0.075,
    Paint()..color = c.pommel,
  );
  canvas.drawCircle(Offset(cx, h * 0.92), w * 0.075, outline);
  canvas.drawCircle(
    Offset(cx - w * 0.022, h * 0.90),
    w * 0.022,
    Paint()..color = Colors.white.withValues(alpha: 0.6),
  );
}

void _paintFalchion(
    Canvas canvas, Size size, SwordShapeColors c, Paint outline, double sw) {
  final w = size.width;
  final h = size.height;
  final cx = w / 2;

  // Asymmetric chopper blade — narrows at the hilt, widens toward the upper
  // third on the cutting edge before sweeping back to the point.
  final bladePath = Path()
    ..moveTo(cx + w * 0.02, h * 0.04)
    ..lineTo(cx + w * 0.16, h * 0.30)
    ..lineTo(cx + w * 0.10, h * 0.58)
    ..lineTo(cx - w * 0.08, h * 0.58)
    ..lineTo(cx - w * 0.06, h * 0.10)
    ..close();
  canvas.drawPath(bladePath, Paint()..color = c.blade);

  // Shadow on the back side.
  final shadowPath = Path()
    ..moveTo(cx + w * 0.06, h * 0.18)
    ..lineTo(cx + w * 0.16, h * 0.30)
    ..lineTo(cx + w * 0.10, h * 0.58)
    ..lineTo(cx + w * 0.06, h * 0.58)
    ..close();
  canvas.drawPath(
    shadowPath,
    Paint()..color = c.bladeAccent.withValues(alpha: 0.6),
  );
  // Edge highlight along the leading curve.
  canvas.drawLine(
    Offset(cx - w * 0.045, h * 0.14),
    Offset(cx - w * 0.06, h * 0.55),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = sw * 0.65
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(bladePath, outline);

  // Sturdy cross guard.
  final guardRect =
      Rect.fromLTWH(cx - w * 0.32, h * 0.58, w * 0.64, h * 0.06);
  final guardRR =
      RRect.fromRectAndRadius(guardRect, const Radius.circular(6));
  canvas.drawRRect(guardRR, Paint()..color = c.guard);
  canvas.drawRRect(guardRR, outline);

  final handleRect =
      Rect.fromLTWH(cx - w * 0.06, h * 0.64, w * 0.12, h * 0.24);
  final handleRR =
      RRect.fromRectAndRadius(handleRect, const Radius.circular(8));
  canvas.drawRRect(handleRR, Paint()..color = c.handle);
  canvas.drawRRect(handleRR, outline);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.04, h * 0.66, w * 0.025, h * 0.20),
      const Radius.circular(2),
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.35),
  );

  canvas.drawCircle(
    Offset(cx, h * 0.92),
    w * 0.09,
    Paint()..color = c.pommel,
  );
  canvas.drawCircle(Offset(cx, h * 0.92), w * 0.09, outline);
}
