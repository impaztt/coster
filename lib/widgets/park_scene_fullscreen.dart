import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/game_provider.dart';

/// Full-bleed illustrated 2D park scene.
///
/// **Purely presentational** — reads `cycleProgress`, `boostGauge`,
/// `mainCoasterStage` from gameProvider and never mutates them. The
/// queue + boarding + exit animation runs an internal local sim that
/// has no effect on gold, upgrades, or any game logic.
///
/// Visual layers (back-to-front):
///   1. Sky gradient + clouds
///   2. Two-tone grass
///   3. Decorative flowers
///   4. White picket fence (park boundary)
///   5. Trees
///   6. Benches, lamp posts (with glow)
///   7. Entrance gate (pillars + banner + star ornament)
///   8. Capacity sign (X/Y board reflecting current queue size)
///   9. Coaster track (X-braced supports + dark outline + colored
///      rail + crossties + station roof + platform pad)
///  10. Sparkle effects around hill peaks (active when boosted)
///  11. Queue / boarding / cart-with-riders / exiting guests
///  12. Floating balloons (animated)
///  13. Queue rope + exit sign (foreground)
class ParkSceneFullscreen extends ConsumerStatefulWidget {
  final void Function(Offset globalPosition) onTap;
  const ParkSceneFullscreen({super.key, required this.onTap});

  @override
  ConsumerState<ParkSceneFullscreen> createState() =>
      _ParkSceneFullscreenState();
}

class _ParkSceneFullscreenState extends ConsumerState<ParkSceneFullscreen>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _ambient = 0;

  final List<_Guest> _guests = [];
  double _spawnTimer = 0;
  double _previousCycle = 0;
  bool _boardedThisCycle = false;
  bool _unloadedThisCycle = false;
  final math.Random _random = math.Random();

  static const _passengersPerCart = 3;
  static const _queueCapacity = 8;
  static const _spawnIntervalSeconds = 1.4;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    for (var i = 0; i < 5; i++) {
      _guests.add(_Guest(
        slot: i,
        state: _GuestState.waiting,
        shirt: _shirtPalette[i % _shirtPalette.length],
        skin: _skinPalette[i % _skinPalette.length],
        hair: _hairPalette[i % _hairPalette.length],
        progress: 1.0,
        bobPhase: _random.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtReal = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dtReal <= 0) return;

    final game = ref.read(gameProvider);
    final boosted = game.boostGauge > 0;
    final dt = boosted ? dtReal * 1.5 : dtReal;
    final cycle = game.cycleProgress;

    _ambient = (_ambient + dtReal * 0.15) % 1.0;

    if (cycle < _previousCycle) {
      _boardedThisCycle = false;
      _unloadedThisCycle = false;
    }
    _previousCycle = cycle;

    _spawnTimer += dt;
    if (_spawnTimer >= _spawnIntervalSeconds &&
        _queueLength() < _queueCapacity) {
      _spawnTimer = 0;
      _spawnGuest();
    }

    if (cycle < _phaseLoadEnd && !_boardedThisCycle) {
      _startBoarding();
      _boardedThisCycle = true;
    }
    if (cycle > _phaseTravelBackEnd && !_unloadedThisCycle) {
      _startUnloading();
      _unloadedThisCycle = true;
    }

    for (final g in List.of(_guests)) {
      g.walkTick(dt);
      if (g.state == _GuestState.gone) {
        _guests.remove(g);
      }
    }

    if (mounted) setState(() {});
  }

  int _queueLength() => _guests
      .where((g) =>
          g.state == _GuestState.entering ||
          g.state == _GuestState.waiting)
      .length;

  void _spawnGuest() {
    final i = _random.nextInt(_shirtPalette.length);
    final j = _random.nextInt(_skinPalette.length);
    final k = _random.nextInt(_hairPalette.length);
    _guests.add(_Guest(
      slot: _queueLength(),
      state: _GuestState.entering,
      shirt: _shirtPalette[i],
      skin: _skinPalette[j],
      hair: _hairPalette[k],
      progress: 0,
      bobPhase: _random.nextDouble(),
    ));
  }

  void _startBoarding() {
    final inQueue = _guests
        .where((g) =>
            g.state == _GuestState.entering ||
            g.state == _GuestState.waiting)
        .toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    final boardCount = math.min(_passengersPerCart, inQueue.length);
    for (var i = 0; i < boardCount; i++) {
      final g = inQueue[i];
      g.state = _GuestState.boarding;
      g.cartSeat = i;
      g.slot = -1;
      g.progress = 0;
    }
    for (var i = boardCount; i < inQueue.length; i++) {
      final g = inQueue[i];
      g.slot = i - boardCount;
      g.progress = 0;
    }
  }

  void _startUnloading() {
    for (final g in _guests) {
      if (g.state != _GuestState.riding) continue;
      g.state = _GuestState.exiting;
      g.cartSeat = -1;
      g.progress = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    return GestureDetector(
      onTapDown: (d) => widget.onTap(d.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _ParkPainter(
          cycle: game.cycleProgress,
          boosted: game.boostGauge > 0,
          ambient: _ambient,
          guests: _guests,
          waitingCount: _queueLength(),
          queueCapacity: _queueCapacity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

// ─── Guest model ────────────────────────────────────────────────────

enum _GuestState { entering, waiting, boarding, riding, exiting, gone }

class _Guest {
  _GuestState state;
  int slot;
  int cartSeat = -1;
  Color shirt;
  Color skin;
  Color hair;
  double progress;
  double bobPhase;

  _Guest({
    required this.state,
    required this.slot,
    required this.shirt,
    required this.skin,
    required this.hair,
    required this.progress,
    required this.bobPhase,
  });

  static const _walkTime = 1.0;

  void walkTick(double dt) {
    if (state == _GuestState.waiting || state == _GuestState.riding) {
      progress = 1.0;
      return;
    }
    progress = (progress + dt / _walkTime).clamp(0.0, 1.0);
    if (progress >= 1.0) {
      switch (state) {
        case _GuestState.entering:
          state = _GuestState.waiting;
        case _GuestState.boarding:
          state = _GuestState.riding;
        case _GuestState.exiting:
          state = _GuestState.gone;
        default:
          break;
      }
    }
  }
}

const _phaseLoadEnd = 0.25;
const _phaseTravelBackEnd = 0.75;

const _shirtPalette = [
  Color(0xFFEF5350),
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFFFCA28),
  Color(0xFFAB47BC),
  Color(0xFF26A69A),
  Color(0xFFFF7043),
  Color(0xFF7E57C2),
  Color(0xFF5C6BC0),
];

const _skinPalette = [
  Color(0xFFFFCC80),
  Color(0xFFFFE0B2),
  Color(0xFFD7CCC8),
  Color(0xFF8D6E63),
  Color(0xFFFFAB91),
];

const _hairPalette = [
  Color(0xFF3E2723),
  Color(0xFF5D4037),
  Color(0xFFFFD54F),
  Color(0xFF263238),
  Color(0xFFBF360C),
  Color(0xFFE91E63),
];

const _flowerColors = [
  Color(0xFFFF6F61),
  Color(0xFFFFEB3B),
  Color(0xFFE040FB),
  Color(0xFFFFFFFF),
  Color(0xFFFF9800),
];

const _balloonColors = [
  Color(0xFFEF5350),
  Color(0xFFFFC107),
  Color(0xFF66BB6A),
];

// ─── Painter ────────────────────────────────────────────────────────

class _ParkPainter extends CustomPainter {
  final double cycle;
  final bool boosted;
  final double ambient;
  final List<_Guest> guests;
  final int waitingCount;
  final int queueCapacity;

  _ParkPainter({
    required this.cycle,
    required this.boosted,
    required this.ambient,
    required this.guests,
    required this.waitingCount,
    required this.queueCapacity,
  });

  static const _yHorizon = 0.40;
  static const _yGround = 0.90;
  static const _yQueueBaseline = 0.80;
  static const _xStation = 0.24;
  static const _xQueueFrontOffset = 0.05;
  static const _xQueueSlotSpacing = 0.034;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintGround(canvas, size);
    _paintFlowers(canvas, size);
    _paintParkFence(canvas, size);
    _paintMidTrees(canvas, size);
    _paintBenches(canvas, size);
    _paintLampPosts(canvas, size);
    _paintEntranceGate(canvas, size);
    _paintCapacitySign(canvas, size);
    _paintTrack(canvas, size);
    _paintLoopSparkles(canvas, size);
    _paintQueueGuests(canvas, size);
    _paintBoardingGuests(canvas, size);
    _paintCartAndRiders(canvas, size);
    _paintExitingGuests(canvas, size);
    _paintBalloons(canvas, size);
    _paintForeground(canvas, size);
  }

  // === Sky =========================================================

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(0, size.height * _yHorizon),
      const [Color(0xFFCFEAFB), Color(0xFFFAF6E5)],
      const [0.0, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = shader);

    for (var i = 0; i < 2; i++) {
      final phase = (ambient + i * 0.5) % 1.0;
      final cx = (phase * 1.3 - 0.15) * size.width;
      final cy = size.height * (0.10 + 0.10 * i);
      _paintCloud(canvas, Offset(cx, cy), 22 + i * 8.0);
    }
  }

  void _paintCloud(Canvas canvas, Offset center, double r) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center.translate(-r * 0.6, r * 0.2), r * 0.7, paint);
    canvas.drawCircle(center.translate(r * 0.7, r * 0.15), r * 0.75, paint);
    canvas.drawCircle(center.translate(r * 0.2, -r * 0.4), r * 0.55, paint);
  }

  // === Ground ======================================================

  void _paintGround(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    canvas.drawRect(
      Rect.fromLTWH(0, h * _yHorizon, w, h * (1 - _yHorizon)),
      Paint()..color = const Color(0xFF8FBC78),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * (_yHorizon + 0.05), w, h * 0.18),
      Paint()..color = const Color(0xFF9DC788).withValues(alpha: 0.7),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.93, w, h * 0.07),
      Paint()..color = const Color(0xFF7AAA66).withValues(alpha: 0.5),
    );
  }

  // === Flowers =====================================================

  void _paintFlowers(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const positions = <List<double>>[
      [0.05, 0.92], [0.12, 0.88], [0.40, 0.93], [0.55, 0.91],
      [0.62, 0.94], [0.77, 0.90], [0.85, 0.93], [0.94, 0.88],
      [0.30, 0.95], [0.48, 0.96], [0.70, 0.95], [0.20, 0.94],
      [0.08, 0.55], [0.88, 0.55],
    ];
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      final cx = w * p[0];
      final cy = h * p[1];
      final color = _flowerColors[i % _flowerColors.length];
      canvas.drawRect(
        Rect.fromLTWH(cx - 0.4, cy, 0.8, 4),
        Paint()..color = const Color(0xFF558B2F),
      );
      final petalPaint = Paint()..color = color;
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5 - math.pi / 2;
        final px = cx + math.cos(a) * 1.6;
        final py = cy - 1 + math.sin(a) * 1.6;
        canvas.drawCircle(Offset(px, py), 1.2, petalPaint);
      }
      canvas.drawCircle(
        Offset(cx, cy - 1),
        0.8,
        Paint()..color = const Color(0xFFFFEB3B),
      );
    }
  }

  // === Park fence ==================================================

  void _paintParkFence(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final fenceY = h * 0.97;
    canvas.drawRect(
      Rect.fromLTWH(0, fenceY, w, 1.5),
      Paint()..color = const Color(0xFFFAFAFA),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, fenceY + 4, w, 1.5),
      Paint()..color = const Color(0xFFFAFAFA),
    );
    final picketPaint = Paint()..color = const Color(0xFFFAFAFA);
    final tipPaint = Paint()..color = const Color(0xFFE0E0E0);
    for (var x = 4.0; x < w; x += 12) {
      canvas.drawRect(Rect.fromLTWH(x, fenceY - 4, 2, 9), picketPaint);
      canvas.drawCircle(Offset(x + 1, fenceY - 4), 1.5, tipPaint);
    }
  }

  // === Trees =======================================================

  void _paintMidTrees(Canvas canvas, Size size) {
    const positions = <List<double>>[
      [0.03, 0.55],
      [0.16, 0.58],
      [0.80, 0.55],
      [0.93, 0.58],
    ];
    for (final p in positions) {
      _paintTree(canvas, size, p[0], p[1]);
    }
  }

  void _paintTree(Canvas canvas, Size size, double xFrac, double yFrac) {
    final cx = size.width * xFrac;
    final cy = size.height * yFrac;
    final h = size.height;
    final foliageR = h * 0.05;

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + h * 0.06),
          width: foliageR * 2.2,
          height: foliageR * 0.6),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 2.5, cy, 5, h * 0.06),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFF6D4C41),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      foliageR,
      Paint()..color = const Color(0xFF388E3C),
    );
    canvas.drawCircle(
      Offset(cx - foliageR * 0.4, cy - foliageR * 0.3),
      foliageR * 0.8,
      Paint()..color = const Color(0xFF4CAF50),
    );
    canvas.drawCircle(
      Offset(cx - foliageR * 0.5, cy - foliageR * 0.5),
      foliageR * 0.35,
      Paint()..color = const Color(0xFF81C784),
    );
  }

  // === Benches =====================================================

  void _paintBenches(Canvas canvas, Size size) {
    _paintBench(canvas, size, 0.42, 0.88);
    _paintBench(canvas, size, 0.66, 0.88);
  }

  void _paintBench(Canvas canvas, Size size, double xFrac, double yFrac) {
    final cx = size.width * xFrac;
    final cy = size.height * yFrac;
    final seatPaint = Paint()..color = const Color(0xFF8D6E63);
    final legPaint = Paint()..color = const Color(0xFF5D4037);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 24, height: 3),
        const Radius.circular(1),
      ),
      seatPaint,
    );
    canvas.drawRect(Rect.fromLTWH(cx - 11, cy + 1, 1.5, 5), legPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 9, cy + 1, 1.5, 5), legPaint);
    canvas.drawRect(Rect.fromLTWH(cx - 11, cy - 5, 1.5, 5), legPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 9, cy - 5, 1.5, 5), legPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 4), width: 24, height: 2),
        const Radius.circular(1),
      ),
      seatPaint,
    );
  }

  // === Lamp posts ==================================================

  void _paintLampPosts(Canvas canvas, Size size) {
    _paintLampPost(canvas, size, 0.06, 0.86);
    _paintLampPost(canvas, size, 0.94, 0.86);
  }

  void _paintLampPost(Canvas canvas, Size size, double xFrac, double yFrac) {
    final cx = size.width * xFrac;
    final cy = size.height * yFrac;
    canvas.drawRect(
      Rect.fromLTWH(cx - 0.7, cy - 28, 1.5, 28),
      Paint()..color = const Color(0xFF424242),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 6, height: 2),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF424242),
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy - 30), width: 6, height: 5),
      Paint()..color = const Color(0xFF424242),
    );
    final pulse = (math.sin(ambient * math.pi * 2) + 1) / 2;
    final glowR = 3.5 + pulse * 1.0;
    canvas.drawCircle(
      Offset(cx, cy - 28),
      glowR * 1.5,
      Paint()
        ..color =
            const Color(0xFFFFEB3B).withValues(alpha: 0.20 + pulse * 0.10),
    );
    canvas.drawCircle(
      Offset(cx, cy - 28),
      glowR,
      Paint()..color = const Color(0xFFFFEE58),
    );
  }

  // === Entrance gate ===============================================

  void _paintEntranceGate(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.10;
    final baseY = h * 0.86;
    final pillarPaint = Paint()..color = const Color(0xFFFFB74D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 18, baseY - 28, 6, 28),
        const Radius.circular(1.5),
      ),
      pillarPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 12, baseY - 28, 6, 28),
        const Radius.circular(1.5),
      ),
      pillarPaint,
    );
    final bannerPaint = Paint()..color = const Color(0xFFEF5350);
    final bannerRect = Rect.fromLTWH(cx - 24, baseY - 36, 48, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(4)),
      bannerPaint,
    );
    final pulse = (math.sin(ambient * math.pi * 2) + 1) / 2;
    final glowAlpha = boosted ? 0.30 + pulse * 0.20 : 0.10 + pulse * 0.08;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(4)),
      Paint()..color = Colors.white.withValues(alpha: glowAlpha),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'COSTER',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, baseY - 35));
    _paintStar(canvas, Offset(cx, baseY - 42), 4, const Color(0xFFFFD54F));
  }

  void _paintStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 - math.pi / 2;
      final rr = i.isEven ? r : r * 0.45;
      final x = c.dx + math.cos(a) * rr;
      final y = c.dy + math.sin(a) * rr;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // === Capacity sign ===============================================

  void _paintCapacitySign(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.18;
    final cy = h * 0.78;
    canvas.drawRect(
      Rect.fromLTWH(cx - 0.7, cy, 1.5, 12),
      Paint()..color = const Color(0xFF6D4C41),
    );
    final boardRect =
        Rect.fromCenter(center: Offset(cx, cy - 2), width: 32, height: 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF8D6E63),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 2), width: 28, height: 11),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFFFFF59D),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '$waitingCount/$queueCapacity',
        style: const TextStyle(
          color: Color(0xFF3E2723),
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - 7));
  }

  // === Track =======================================================

  Path _trackPath(Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path();
    final stationX = _xStation * w;
    final stationY = h * 0.62;
    p.moveTo(stationX, stationY);

    final liftPeakX = w * 0.36;
    final liftPeakY = h * 0.32;
    p.cubicTo(
      stationX + 30, stationY,
      liftPeakX - 25, liftPeakY + 40,
      liftPeakX, liftPeakY,
    );

    final dropX = w * 0.50;
    final dropY = h * 0.62;
    p.cubicTo(
      liftPeakX + 30, liftPeakY,
      dropX - 20, dropY - 50,
      dropX, dropY,
    );

    final hump2X = w * 0.65;
    final hump2Y = h * 0.45;
    p.cubicTo(
      dropX + 20, dropY,
      hump2X - 20, hump2Y + 30,
      hump2X, hump2Y,
    );

    final brakeStartX = w * 0.80;
    final brakeStartY = h * 0.62;
    p.cubicTo(
      hump2X + 20, hump2Y,
      brakeStartX - 25, brakeStartY - 30,
      brakeStartX, brakeStartY,
    );

    p.lineTo(stationX, stationY);
    return p;
  }

  void _paintTrack(Canvas canvas, Size size) {
    final h = size.height;
    final path = _trackPath(size);
    final groundY = h * _yGround;
    final metric = path.computeMetrics().first;

    final pillarPaint = Paint()
      ..color = const Color(0xFF455A64)
      ..strokeWidth = 2.5;
    final bracePaint = Paint()
      ..color = const Color(0xFF607D8B)
      ..strokeWidth = 1.2;
    const supportCount = 9;
    for (var i = 1; i < supportCount; i++) {
      final t = i / supportCount;
      final tan = metric.getTangentForOffset(t * metric.length);
      if (tan == null) continue;
      final p = tan.position;
      if (p.dy >= groundY - 4) continue;
      canvas.drawLine(p, Offset(p.dx, groundY), pillarPaint);
      final mid = (p.dy + groundY) / 2;
      canvas.drawLine(
        Offset(p.dx - 5, p.dy + 8),
        Offset(p.dx + 5, mid + 4),
        bracePaint,
      );
      canvas.drawLine(
        Offset(p.dx + 5, p.dy + 8),
        Offset(p.dx - 5, mid + 4),
        bracePaint,
      );
    }

    final railShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF263238);
    canvas.drawPath(path, railShadow);

    final railColor =
        boosted ? const Color(0xFFFF7043) : const Color(0xFFE53935);
    final railPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = railColor;
    canvas.drawPath(path, railPaint);

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawPath(path, innerPaint);

    const tieCount = 32;
    final tiePaint = Paint()
      ..color = const Color(0xFF8D6E63)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < tieCount; i++) {
      final t = i / tieCount;
      final tan = metric.getTangentForOffset(t * metric.length);
      if (tan == null) continue;
      final p = tan.position;
      if (p.dy > groundY - 6) continue;
      final nx = -tan.vector.dy;
      final ny = tan.vector.dx;
      canvas.drawLine(
        Offset(p.dx - nx * 5, p.dy - ny * 5),
        Offset(p.dx + nx * 5, p.dy + ny * 5),
        tiePaint,
      );
    }

    final stationX = _xStation * size.width;
    final stationY = h * 0.62;
    canvas.drawRect(
      Rect.fromLTWH(stationX - 22, stationY + 4, 50, 6),
      Paint()..color = const Color(0xFFFFE082),
    );
    canvas.drawRect(
      Rect.fromLTWH(stationX - 22, stationY + 10, 50, 1.5),
      Paint()..color = const Color(0xFFFFB300),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stationX - 28, stationY - 16, 60, 6),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFEF5350),
    );
    canvas.drawRect(
      Rect.fromLTWH(stationX - 28, stationY - 13, 60, 2),
      Paint()..color = const Color(0xFFFAFAFA),
    );
    final polePaint = Paint()..color = const Color(0xFF424242);
    canvas.drawRect(
        Rect.fromLTWH(stationX - 27, stationY - 11, 1.5, 14), polePaint);
    canvas.drawRect(
        Rect.fromLTWH(stationX + 30, stationY - 11, 1.5, 14), polePaint);
  }

  // === Loop sparkles (active when boosted) =========================

  void _paintLoopSparkles(Canvas canvas, Size size) {
    if (!boosted) return;
    final h = size.height;
    final w = size.width;
    final spots = [
      Offset(w * 0.36, h * 0.32),
      Offset(w * 0.65, h * 0.45),
    ];
    for (final spot in spots) {
      for (var i = 0; i < 4; i++) {
        final phase = (ambient * 1.5 + i * 0.25) % 1.0;
        final angle = phase * math.pi * 2 + i;
        final r = 8 + (i * 2);
        final px = spot.dx + math.cos(angle) * r;
        final py = spot.dy + math.sin(angle) * r;
        final alpha = (math.sin(phase * math.pi)).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset(px, py),
          1.6,
          Paint()
            ..color = const Color(0xFFFFEB3B).withValues(alpha: alpha),
        );
      }
    }
  }

  // === Cart and riders =============================================

  void _paintCartAndRiders(Canvas canvas, Size size) {
    final path = _trackPath(size);
    final metric = path.computeMetrics().first;
    final pos = _cartPosition(metric, cycle, size);
    if (pos == null) return;

    canvas.save();
    canvas.translate(pos.position.dx, pos.position.dy);
    canvas.rotate(pos.angle);

    final shake = boosted ? math.sin(ambient * math.pi * 30) * 0.4 : 0.0;
    canvas.translate(0, shake);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 14), width: 38, height: 5),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    final body = Rect.fromCenter(center: Offset.zero, width: 44, height: 20);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        body,
        topLeft: const Radius.circular(10),
        topRight: const Radius.circular(10),
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFE53935),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -4), width: 42, height: 4),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFFFFCDD2),
    );
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, 3), width: 42, height: 1.5),
      Paint()..color = const Color(0xFFB71C1C),
    );
    canvas.drawCircle(
      const Offset(18, -2),
      2.5,
      Paint()..color = const Color(0xFFFFEE58),
    );
    canvas.drawCircle(
      const Offset(18, -2),
      4,
      Paint()..color = const Color(0xFFFFEB3B).withValues(alpha: 0.4),
    );
    final wheelPaint = Paint()..color = const Color(0xFF263238);
    canvas.drawCircle(const Offset(-15, 9), 5, wheelPaint);
    canvas.drawCircle(const Offset(15, 9), 5, wheelPaint);
    canvas.drawCircle(
        const Offset(-15, 9), 1.8, Paint()..color = const Color(0xFFB0BEC5));
    canvas.drawCircle(
        const Offset(15, 9), 1.8, Paint()..color = const Color(0xFFB0BEC5));

    final riders =
        guests.where((g) => g.state == _GuestState.riding).toList();
    riders.sort((a, b) => a.cartSeat.compareTo(b.cartSeat));
    for (final r in riders) {
      final dx = -11.0 + r.cartSeat * 11.0;
      _paintRiderInCart(canvas, Offset(dx, -8), r);
    }

    canvas.restore();
  }

  void _paintRiderInCart(Canvas canvas, Offset center, _Guest g) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, 4), width: 6, height: 5),
        const Radius.circular(1.5),
      ),
      Paint()..color = g.shirt,
    );
    canvas.drawCircle(center, 3.6, Paint()..color = g.skin);
    final hairPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: 3.6),
        math.pi,
        math.pi,
      );
    canvas.drawPath(hairPath, Paint()..color = g.hair);
    final eye = Paint()..color = const Color(0xFF263238);
    canvas.drawCircle(center.translate(-1.1, 0.2), 0.5, eye);
    canvas.drawCircle(center.translate(1.1, 0.2), 0.5, eye);
    final armPaint = Paint()
      ..color = g.skin
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(-2, 1.5),
      center.translate(-3.5, -3.5),
      armPaint,
    );
    canvas.drawLine(
      center.translate(2, 1.5),
      center.translate(3.5, -3.5),
      armPaint,
    );
  }

  ({Offset position, double angle})? _cartPosition(
      ui.PathMetric metric, double cycle, Size size) {
    double t;
    if (cycle < _phaseLoadEnd) {
      t = 0.0;
    } else if (cycle > _phaseTravelBackEnd) {
      t = 1.0;
    } else {
      t = (cycle - _phaseLoadEnd) /
          (_phaseTravelBackEnd - _phaseLoadEnd);
    }
    final tan = metric.getTangentForOffset(t * metric.length);
    if (tan == null) return null;
    return (position: tan.position, angle: tan.angle);
  }

  // === Queue / boarding / exit =====================================

  void _paintQueueGuests(Canvas canvas, Size size) {
    for (final g in guests) {
      if (g.state != _GuestState.entering &&
          g.state != _GuestState.waiting) {
        continue;
      }
      final pos = _queuePosition(size, g);
      _paintCharacter(canvas, pos, g, idleBob: g.state == _GuestState.waiting);
    }
  }

  void _paintBoardingGuests(Canvas canvas, Size size) {
    for (final g in guests) {
      if (g.state != _GuestState.boarding) continue;
      final from = _queuePosition(size, g, baseSlot: 0);
      final to = _stationLoadPosition(size);
      final pos = Offset.lerp(from, to, g.progress)!;
      _paintCharacter(canvas, pos, g);
    }
  }

  void _paintExitingGuests(Canvas canvas, Size size) {
    for (final g in guests) {
      if (g.state != _GuestState.exiting) continue;
      final from = _stationLoadPosition(size);
      final to = Offset(size.width + 30, size.height * _yQueueBaseline);
      final pos = Offset.lerp(from, to, g.progress)!;
      _paintCharacter(canvas, pos, g);
    }
  }

  Offset _queuePosition(Size size, _Guest g, {int? baseSlot}) {
    final slot = baseSlot ?? g.slot;
    final w = size.width;
    final h = size.height;
    final x =
        (_xStation - _xQueueFrontOffset - slot * _xQueueSlotSpacing) * w;
    final baselineY = h * _yQueueBaseline;
    if (g.state == _GuestState.entering) {
      final from = Offset(-30, baselineY);
      final to = Offset(x, baselineY);
      return Offset.lerp(from, to, g.progress)!;
    }
    return Offset(x, baselineY);
  }

  Offset _stationLoadPosition(Size size) {
    return Offset(size.width * _xStation, size.height * _yQueueBaseline);
  }

  void _paintCharacter(Canvas canvas, Offset feet, _Guest g,
      {bool idleBob = false}) {
    final bob = idleBob
        ? math.sin((ambient + g.bobPhase) * math.pi * 2) * 0.8
        : 0.0;
    final cx = feet.dx;
    final cy = feet.dy - bob;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, feet.dy + 1), width: 16, height: 4),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    const legColor = Color(0xFF455A64);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 4.5, cy - 13, 3.5, 11),
        const Radius.circular(1.2),
      ),
      Paint()..color = legColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 1, cy - 13, 3.5, 11),
        const Radius.circular(1.2),
      ),
      Paint()..color = legColor,
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - 6.5, cy - 24, 13, 13),
        topLeft: const Radius.circular(3.5),
        topRight: const Radius.circular(3.5),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      ),
      Paint()..color = g.shirt,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 3, cy - 24, 3.5, 13),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 9, cy - 23, 2.8, 10),
        const Radius.circular(1.2),
      ),
      Paint()..color = g.skin,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 6.2, cy - 23, 2.8, 10),
        const Radius.circular(1.2),
      ),
      Paint()..color = g.skin,
    );

    canvas.drawCircle(Offset(cx, cy - 29), 5.4, Paint()..color = g.skin);

    final hairPath = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(cx, cy - 29), radius: 5.4),
        math.pi,
        math.pi,
      );
    canvas.drawPath(hairPath, Paint()..color = g.hair);
    canvas.drawRect(
      Rect.fromLTWH(cx - 5.4, cy - 29, 10.8, 1.5),
      Paint()..color = g.hair,
    );

    final eyePaint = Paint()..color = const Color(0xFF263238);
    canvas.drawCircle(Offset(cx - 1.8, cy - 28.5), 0.8, eyePaint);
    canvas.drawCircle(Offset(cx + 1.8, cy - 28.5), 0.8, eyePaint);
    final cheekPaint = Paint()
      ..color = const Color(0xFFFFAB91).withValues(alpha: 0.6);
    canvas.drawCircle(Offset(cx - 2.5, cy - 27), 0.8, cheekPaint);
    canvas.drawCircle(Offset(cx + 2.5, cy - 27), 0.8, cheekPaint);
  }

  // === Balloons ====================================================

  void _paintBalloons(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const positions = <List<double>>[
      [0.06, 0.50],
      [0.94, 0.48],
      [0.13, 0.45],
    ];
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      final phase = (ambient + i * 0.33) * math.pi * 2;
      final cx = w * p[0];
      final cy = h * p[1] + math.sin(phase) * 3;
      final color = _balloonColors[i % _balloonColors.length];
      canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = color);
      canvas.drawCircle(
        Offset(cx - 1.5, cy - 1.5),
        1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
      final knotPath = Path()
        ..moveTo(cx - 1.2, cy + 4.5)
        ..lineTo(cx, cy + 7)
        ..lineTo(cx + 1.2, cy + 4.5)
        ..close();
      canvas.drawPath(knotPath, Paint()..color = color);
      canvas.drawLine(
        Offset(cx, cy + 7),
        Offset(cx - math.sin(phase) * 1.5, cy + 22),
        Paint()
          ..color = const Color(0xFF424242)
          ..strokeWidth = 0.6,
      );
    }
  }

  // === Foreground (queue rope, exit sign) ==========================

  void _paintForeground(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ropeY = h * (_yQueueBaseline - 0.04);
    final ropeStartX = w * 0.04;
    final ropeEndX = w * (_xStation - 0.005);
    canvas.drawLine(
      Offset(ropeStartX, ropeY),
      Offset(ropeEndX, ropeY),
      Paint()
        ..color = const Color(0xFFFFB74D)
        ..strokeWidth = 1.6,
    );
    final postPaint = Paint()..color = const Color(0xFF6D4C41);
    final postCapPaint = Paint()..color = const Color(0xFFFFD54F);
    for (var x = ropeStartX; x <= ropeEndX; x += 28) {
      canvas.drawRect(Rect.fromLTWH(x, ropeY - 1.5, 2.2, 8), postPaint);
      canvas.drawCircle(Offset(x + 1.1, ropeY - 1.5), 1.5, postCapPaint);
    }

    final ax = w * 0.94;
    final ay = h * (_yQueueBaseline - 0.04);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(ax, ay - 5), width: 1.6, height: 14),
      Paint()..color = const Color(0xFF424242),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ax - 4, ay - 14), width: 22, height: 9),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFF66BB6A),
    );
    final arrow = Path()
      ..moveTo(ax + 11, ay - 17)
      ..lineTo(ax + 15, ay - 14)
      ..lineTo(ax + 11, ay - 11)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    final tp = TextPainter(
      text: const TextSpan(
        text: '출구',
        style: TextStyle(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(ax - 4 - tp.width / 2, ay - 17));
  }

  @override
  bool shouldRepaint(covariant _ParkPainter old) {
    return old.cycle != cycle ||
        old.boosted != boosted ||
        old.ambient != ambient ||
        old.guests != guests ||
        old.waitingCount != waitingCount;
  }
}
