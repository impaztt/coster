import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/coaster.dart';

/// Resolved colors for one coaster draw. The catalog still exposes historic
/// color slots for save/data compatibility; the renderer maps them to coaster
/// parts here.
class CoasterShapeColors {
  final Color rail;
  final Color railAccent;
  final Color trim;
  final Color wheel;
  final Color light;

  const CoasterShapeColors({
    required this.rail,
    required this.railAccent,
    required this.trim,
    required this.wheel,
    required this.light,
  });

  factory CoasterShapeColors.fromVisual(CoasterVisual v) => CoasterShapeColors(
        rail: v.bladeColor,
        railAccent: v.bladeAccent,
        trim: v.guardColor,
        wheel: v.handleColor,
        light: v.pommelColor,
      );
}

/// Render a themed roller-coaster train and track inside [size]. Aura,
/// sparkles, and locked overlays are layered by callers.
void paintCoasterShape(
  Canvas canvas,
  Size size,
  CoasterShape shape,
  CoasterShapeColors colors, {
  required double outlineWidth,
}) {
  final spec = _CoasterShapeSpec.forShape(shape);
  _paintTrack(canvas, size, colors, spec, outlineWidth);
  _paintStationAccent(canvas, size, colors, spec, outlineWidth);
  _paintTrain(canvas, size, colors, spec, outlineWidth);
}

class _CoasterShapeSpec {
  final int cars;
  final double lift;
  final double trainX;
  final double trainY;
  final double trainAngle;
  final bool loop;
  final bool launchLines;
  final bool corkscrew;

  const _CoasterShapeSpec({
    required this.cars,
    required this.lift,
    required this.trainX,
    required this.trainY,
    required this.trainAngle,
    this.loop = false,
    this.launchLines = false,
    this.corkscrew = false,
  });

  factory _CoasterShapeSpec.forShape(CoasterShape shape) => switch (shape) {
        CoasterShape.dagger => const _CoasterShapeSpec(
            cars: 2,
            lift: 0.10,
            trainX: 0.48,
            trainY: 0.52,
            trainAngle: -0.08,
          ),
        CoasterShape.longcoaster => const _CoasterShapeSpec(
            cars: 3,
            lift: 0.18,
            trainX: 0.48,
            trainY: 0.50,
            trainAngle: -0.12,
          ),
        CoasterShape.claymore => const _CoasterShapeSpec(
            cars: 4,
            lift: 0.28,
            trainX: 0.52,
            trainY: 0.48,
            trainAngle: -0.18,
            loop: true,
          ),
        CoasterShape.katana => const _CoasterShapeSpec(
            cars: 3,
            lift: 0.24,
            trainX: 0.50,
            trainY: 0.46,
            trainAngle: -0.32,
          ),
        CoasterShape.rapier => const _CoasterShapeSpec(
            cars: 3,
            lift: 0.12,
            trainX: 0.54,
            trainY: 0.55,
            trainAngle: -0.05,
            launchLines: true,
          ),
        CoasterShape.falchion => const _CoasterShapeSpec(
            cars: 4,
            lift: 0.22,
            trainX: 0.51,
            trainY: 0.48,
            trainAngle: -0.24,
            corkscrew: true,
          ),
      };
}

void _paintTrack(
  Canvas canvas,
  Size size,
  CoasterShapeColors c,
  _CoasterShapeSpec spec,
  double outlineWidth,
) {
  final w = size.width;
  final h = size.height;
  final railWidth = math.max(3.0, w * 0.050);
  final track = Path()
    ..moveTo(w * 0.08, h * 0.70)
    ..cubicTo(
      w * 0.24,
      h * (0.70 - spec.lift),
      w * 0.38,
      h * (0.35 - spec.lift * 0.25),
      w * 0.56,
      h * 0.42,
    )
    ..cubicTo(
      w * 0.70,
      h * 0.48,
      w * 0.80,
      h * 0.68,
      w * 0.94,
      h * 0.58,
    );

  if (spec.loop) {
    _paintLoop(canvas, size, c, outlineWidth);
  }
  if (spec.corkscrew) {
    _paintCorkscrew(canvas, size, c, outlineWidth);
  }

  final outline = Paint()
    ..color = AppColors.outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth + outlineWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final shadow = Paint()
    ..color = c.railAccent.withValues(alpha: 0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final rail = Paint()
    ..color = c.rail
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth * 0.68
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final shine = Paint()
    ..color = Colors.white.withValues(alpha: 0.65)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, railWidth * 0.16)
    ..strokeCap = StrokeCap.round;

  canvas.drawPath(track, outline);
  _paintCrossties(canvas, track, size, c, outlineWidth);
  canvas.drawPath(track, shadow);
  canvas.drawPath(track, rail);
  canvas.drawPath(track, shine);

  if (spec.launchLines) {
    final p = Paint()
      ..color = c.light.withValues(alpha: 0.55)
      ..strokeWidth = outlineWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.48 + i * 0.08);
      canvas.drawLine(Offset(w * 0.08, y), Offset(w * 0.24, y - h * 0.03), p);
    }
  }
}

void _paintLoop(
  Canvas canvas,
  Size size,
  CoasterShapeColors c,
  double outlineWidth,
) {
  final w = size.width;
  final h = size.height;
  final rect = Rect.fromCenter(
    center: Offset(w * 0.60, h * 0.43),
    width: w * 0.42,
    height: h * 0.34,
  );
  final railWidth = math.max(3.0, w * 0.045);
  final outline = Paint()
    ..color = AppColors.outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth + outlineWidth
    ..strokeCap = StrokeCap.round;
  final rail = Paint()
    ..color = c.railAccent
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth
    ..strokeCap = StrokeCap.round;
  final inner = Paint()
    ..color = c.rail
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth * 0.62
    ..strokeCap = StrokeCap.round;
  canvas.drawOval(rect, outline);
  canvas.drawOval(rect, rail);
  canvas.drawOval(rect, inner);
}

void _paintCorkscrew(
  Canvas canvas,
  Size size,
  CoasterShapeColors c,
  double outlineWidth,
) {
  final w = size.width;
  final h = size.height;
  final path = Path();
  for (var i = 0; i <= 40; i++) {
    final t = i / 40;
    final x = w * (0.24 + t * 0.52);
    final y = h * (0.44 + math.sin(t * math.pi * 2) * 0.11);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineWidth + w * 0.032
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(
    path,
    Paint()
      ..color = c.railAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.032
      ..strokeCap = StrokeCap.round,
  );
}

void _paintCrossties(
  Canvas canvas,
  Path path,
  Size size,
  CoasterShapeColors c,
  double outlineWidth,
) {
  final tiePaint = Paint()
    ..color = c.trim
    ..strokeWidth = math.max(2.0, size.width * 0.020)
    ..strokeCap = StrokeCap.round;
  final tieOutline = Paint()
    ..color = AppColors.outline.withValues(alpha: 0.75)
    ..strokeWidth = tiePaint.strokeWidth + outlineWidth * 0.45
    ..strokeCap = StrokeCap.round;

  for (final metric in path.computeMetrics()) {
    final count = math.max(5, (metric.length / (size.width * 0.12)).floor());
    for (var i = 1; i < count; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / count);
      if (tangent == null) continue;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final length = size.width * 0.075;
      final n =
          normal.distance == 0 ? const Offset(0, 1) : normal / normal.distance;
      final a = tangent.position - n * length;
      final b = tangent.position + n * length;
      canvas.drawLine(a, b, tieOutline);
      canvas.drawLine(a, b, tiePaint);
    }
  }
}

void _paintStationAccent(
  Canvas canvas,
  Size size,
  CoasterShapeColors c,
  _CoasterShapeSpec spec,
  double outlineWidth,
) {
  final w = size.width;
  final h = size.height;
  final base = RRect.fromRectAndRadius(
    Rect.fromLTWH(w * 0.15, h * 0.72, w * 0.36, h * 0.08),
    Radius.circular(w * 0.03),
  );
  final roof = Path()
    ..moveTo(w * 0.12, h * 0.72)
    ..lineTo(w * 0.33, h * 0.64)
    ..lineTo(w * 0.54, h * 0.72)
    ..close();
  final outline = Paint()
    ..color = AppColors.outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = outlineWidth
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(roof, Paint()..color = c.light.withValues(alpha: 0.85));
  canvas.drawPath(roof, outline);
  canvas.drawRRect(base, Paint()..color = c.trim);
  canvas.drawRRect(base, outline);

  if (spec.cars >= 4) {
    final flagPole = Paint()
      ..color = AppColors.outline
      ..strokeWidth = outlineWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.55, h * 0.70), Offset(w * 0.55, h * 0.54), flagPole);
    final flag = Path()
      ..moveTo(w * 0.55, h * 0.54)
      ..lineTo(w * 0.70, h * 0.58)
      ..lineTo(w * 0.55, h * 0.62)
      ..close();
    canvas.drawPath(flag, Paint()..color = c.light);
    canvas.drawPath(flag, outline);
  }
}

void _paintTrain(
  Canvas canvas,
  Size size,
  CoasterShapeColors c,
  _CoasterShapeSpec spec,
  double outlineWidth,
) {
  final w = size.width;
  final h = size.height;
  final carW = w * (spec.cars >= 4 ? 0.145 : 0.175);
  final carH = h * 0.105;
  final gap = w * 0.012;
  final totalW = spec.cars * carW + (spec.cars - 1) * gap;
  final center = Offset(w * spec.trainX, h * spec.trainY);

  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(spec.trainAngle);
  canvas.translate(-totalW / 2, -carH / 2);

  for (var i = 0; i < spec.cars; i++) {
    final x = i * (carW + gap);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, 0, carW, carH),
      Radius.circular(carH * 0.30),
    );
    final front = i == spec.cars - 1;
    final bodyColor = Color.lerp(c.rail, c.trim, front ? 0.12 : 0.04) ?? c.rail;
    final shade = RRect.fromRectAndRadius(
      Rect.fromLTWH(x + carW * 0.08, carH * 0.58, carW * 0.84, carH * 0.28),
      Radius.circular(carH * 0.14),
    );

    canvas.drawRRect(body, Paint()..color = bodyColor);
    canvas.drawRRect(
      body,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth,
    );
    canvas.drawRRect(
        shade, Paint()..color = c.railAccent.withValues(alpha: 0.45));

    final window = RRect.fromRectAndRadius(
      Rect.fromLTWH(x + carW * 0.18, carH * 0.18, carW * 0.42, carH * 0.28),
      Radius.circular(carH * 0.08),
    );
    canvas.drawRRect(
        window, Paint()..color = Colors.white.withValues(alpha: 0.72));
    canvas.drawCircle(
      Offset(x + carW * 0.28, carH * 1.05),
      carH * 0.20,
      Paint()..color = AppColors.outline,
    );
    canvas.drawCircle(
      Offset(x + carW * 0.74, carH * 1.05),
      carH * 0.20,
      Paint()..color = AppColors.outline,
    );
    canvas.drawCircle(
      Offset(x + carW * 0.28, carH * 1.05),
      carH * 0.12,
      Paint()..color = c.wheel,
    );
    canvas.drawCircle(
      Offset(x + carW * 0.74, carH * 1.05),
      carH * 0.12,
      Paint()..color = c.wheel,
    );

    if (front) {
      final head = Path()
        ..moveTo(x + carW * 0.82, carH * 0.18)
        ..lineTo(x + carW * 1.05, carH * 0.50)
        ..lineTo(x + carW * 0.82, carH * 0.82)
        ..close();
      canvas.drawPath(head, Paint()..color = c.light);
      canvas.drawPath(
        head,
        Paint()
          ..color = AppColors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineWidth,
      );
    }
  }

  canvas.restore();
}
