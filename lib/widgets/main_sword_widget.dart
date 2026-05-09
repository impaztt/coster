import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../data/main_sword_evolution.dart';
import '../models/sword.dart';
import 'sword_shape_painter.dart';

/// Animated rendering of the home-tab main sword. The visual is derived
/// entirely from `stage` (0..50) — palette/shape come from the tier, while
/// substage tweaks aura intensity and sparkle count. Higher tiers add
/// extra layers (orbiting sparkles, screen vignette, gentle floating).
class MainSwordWidget extends StatefulWidget {
  final void Function(Offset globalPosition) onTap;
  final double size;
  final int stage;

  const MainSwordWidget({
    super.key,
    required this.onTap,
    required this.stage,
    this.size = 240,
  });

  @override
  State<MainSwordWidget> createState() => _MainSwordWidgetState();
}

class _MainSwordWidgetState extends State<MainSwordWidget>
    with TickerProviderStateMixin {
  late final AnimationController _tap;
  late final AnimationController _sparkle;
  late final AnimationController _float;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_tap);
    _rotation = Tween<double>(begin: 0, end: 0.08)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_tap);
    _sparkle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _tap.dispose();
    _sparkle.dispose();
    _float.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails d) {
    if (_tap.isAnimating) _tap.reset();
    _tap.forward().then((_) {
      if (mounted) _tap.reverse();
    });
    widget.onTap(d.globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage.clamp(0, mainSwordMaxStage);
    final visual = mainSwordVisualFor(stage);
    final tier = mainSwordTierFor(stage);
    final extras = mainSwordSparkleExtras(stage);
    final floats = tier.floats;
    return GestureDetector(
      onTapDown: _handleTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_tap, _sparkle, _float]),
        builder: (_, __) {
          final floatY =
              floats ? math.sin(_float.value * math.pi * 2) * 6.0 : 0.0;
          return Transform.translate(
            offset: Offset(0, floatY),
            child: Transform.rotate(
              angle: _rotation.value,
              child: Transform.scale(
                scale: _scale.value,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Base aura halo.
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              visual.auraColor
                                  .withValues(alpha: visual.auraIntensity),
                              visual.auraColor.withValues(
                                  alpha: visual.auraIntensity * 0.3),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.65, 1.0],
                          ),
                        ),
                      ),
                      // Tier-9+ vignette ring.
                      if (tier.screenVignette)
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  visual.auraColor.withValues(alpha: 0.0),
                                  visual.auraColor.withValues(alpha: 0.15),
                                ],
                                stops: const [0.0, 0.55, 0.85, 1.0],
                              ),
                            ),
                          ),
                        ),
                      // Base sparkle layer (uses stock sparkle painter).
                      if (visual.sparkle != SparkleStyle.none)
                        CustomPaint(
                          size: Size(widget.size, widget.size),
                          painter: _SparkleRingPainter(
                            style: visual.sparkle,
                            color: visual.auraColor,
                            t: _sparkle.value,
                          ),
                        ),
                      // Extra orbiting sparkles for higher stages.
                      if (extras > 0)
                        CustomPaint(
                          size: Size(widget.size, widget.size),
                          painter: _ExtraSparklePainter(
                            count: extras,
                            color: visual.auraColor,
                            t: _sparkle.value,
                            radius: widget.size * 0.42,
                          ),
                        ),
                      // The sword itself.
                      CustomPaint(
                        size:
                            Size(widget.size * 0.7, widget.size * 0.85),
                        painter: _MainSwordPainter(visual),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MainSwordPainter extends CustomPainter {
  final SwordVisual v;
  _MainSwordPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    paintSwordShape(
      canvas,
      size,
      v.shape,
      SwordShapeColors.fromVisual(v),
      outlineWidth: 4,
    );
  }

  @override
  bool shouldRepaint(covariant _MainSwordPainter old) => old.v != v;
}

class _SparkleRingPainter extends CustomPainter {
  final SparkleStyle style;
  final Color color;
  final double t;
  _SparkleRingPainter({
    required this.style,
    required this.color,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.36;
    final count = style == SparkleStyle.orbiting ? 6 : 3;
    final baseR = style == SparkleStyle.orbiting
        ? 5.0
        : style == SparkleStyle.bright
            ? 3.5
            : 2.5;
    for (var i = 0; i < count; i++) {
      final phase = (t + i / count) % 1.0;
      final angle = phase * 2 * math.pi;
      final dx = cx + math.cos(angle) * radius;
      final dy = cy + math.sin(angle) * radius * 0.85;
      final alpha = (math.sin(phase * math.pi) * 0.9 + 0.1).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(dx, dy),
        baseR,
        Paint()..color = color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        Offset(dx, dy),
        baseR * 2,
        Paint()..color = color.withValues(alpha: alpha * 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleRingPainter old) => true;
}

class _ExtraSparklePainter extends CustomPainter {
  final int count;
  final Color color;
  final double t;
  final double radius;
  _ExtraSparklePainter({
    required this.count,
    required this.color,
    required this.t,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var i = 0; i < count; i++) {
      final phase = (t * 0.6 + i / count) % 1.0;
      final angle = phase * 2 * math.pi;
      final dx = cx + math.cos(angle) * radius;
      final dy = cy + math.sin(angle) * radius * 0.95;
      final alpha = (math.sin(phase * math.pi) * 0.7 + 0.2).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(dx, dy),
        3.0,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExtraSparklePainter old) => true;
}
