import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/game_provider.dart';

/// Full-bleed cozy/healing-game park scene.
///
/// Pure presentation — reads `cycleProgress`, `boostGauge`,
/// `mainCoasterStage` from gameProvider; mutates none. The internal
/// guest sim has no game-logic effect.
///
/// **Design philosophy** (cozy / healing):
///   - Golden-hour palette (peach + lilac + cream + warm sage)
///   - 6 atmospheric depth bands: mountains → forest → cottage →
///     hills → grass → foreground
///   - Layered foliage (8–12 leaf clusters per tree) + grass blade
///     texture + cobblestone path tiles instead of flat fills
///   - Warm light glows (lanterns, fireflies, sun haze, cottage
///     window) at low alpha to read as ambient atmosphere
///   - Chibi character proportions: oversized head, small body,
///     eye highlights + blush + smile
///   - Cart has soft "face" (round window + headlight) so it reads
///     as friendly rather than mechanical
///   - Drifting petals + fireflies + cottage smoke for ambient life
///   - Subtle radial vignette to settle the eye on center
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
  final List<_Petal> _petals = [];
  final List<_Firefly> _fireflies = [];
  double _spawnTimer = 0;
  double _previousCycle = 0;
  bool _boardedThisCycle = false;
  bool _unloadedThisCycle = false;
  final math.Random _random = math.Random(42);

  static const _passengersPerCart = 2;
  static const _queueCapacity = 6;
  // Realistic-pace pass: 1.6s → 4.0s. Even on an aggressive tapper the
  // cycle resets every ~1-2s; spawning at 1.6s flooded the queue and
  // turned guests into a stream rather than a trickle. 4.0s lets the
  // queue fill to its 6-cap in ~24s — visible, not frantic.
  static const _spawnIntervalSeconds = 4.0;
  static const _petalCount = 14;
  static const _fireflyCount = 8;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    for (var i = 0; i < 4; i++) {
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
    for (var i = 0; i < _petalCount; i++) {
      _petals.add(_Petal(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.04 + _random.nextDouble() * 0.05,
        sway: _random.nextDouble() * math.pi * 2,
        size: 1.4 + _random.nextDouble() * 1.5,
        color: _petalPalette[_random.nextInt(_petalPalette.length)],
      ));
    }
    for (var i = 0; i < _fireflyCount; i++) {
      _fireflies.add(_Firefly(
        baseX: 0.06 + _random.nextDouble() * 0.88,
        baseY: 0.40 + _random.nextDouble() * 0.30,
        amp: 0.015 + _random.nextDouble() * 0.025,
        phase: _random.nextDouble() * math.pi * 2,
        speed: 0.6 + _random.nextDouble() * 0.6,
        twinklePhase: _random.nextDouble() * math.pi * 2,
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
    // Guest walk + spawn run on wall-clock dtReal. Boost speeds up the
    // ride cycle (a game-mechanics signal) — it doesn't accelerate guest
    // pedestrians, which would read as teleporting. Cart speed is owned
    // by [game.cycleProgress] elsewhere and is unaffected by this dt.
    final dt = dtReal;
    final cycle = game.cycleProgress;

    _ambient = (_ambient + dtReal * 0.10) % 1.0;

    for (final p in _petals) {
      p.y += p.speed * dtReal;
      p.sway += dtReal * 1.4;
      if (p.y > 1.05) {
        p.y = -0.05;
        p.x = _random.nextDouble();
      }
    }
    for (final f in _fireflies) {
      f.phase += dtReal * f.speed;
      f.twinklePhase += dtReal * 2.0;
    }

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
          g.state == _GuestState.entering || g.state == _GuestState.waiting)
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
            g.state == _GuestState.entering || g.state == _GuestState.waiting)
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
      // Smooth shift instead of an instant slot swap — `beginSlotShift`
      // preserves the current visual position as the lerp source so the
      // walk reads as a real step forward.
      final newSlot = i - boardCount;
      if (g.state == _GuestState.waiting) {
        g.beginSlotShift(newSlot);
      } else {
        // entering guests already animate via [progress]; we just retarget
        // their destination slot.
        g.slot = newSlot;
      }
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
          stage: game.mainCoasterStage,
          ambient: _ambient,
          guests: _guests,
          petals: _petals,
          fireflies: _fireflies,
          waitingCount: _queueLength(),
          queueCapacity: _queueCapacity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

// ─── Models ─────────────────────────────────────────────────────────

enum _GuestState { entering, waiting, boarding, riding, exiting, gone }

class _Guest {
  _GuestState state;
  int slot;
  // Fractional slot used while a queue shift is in progress. While
  // [slotShiftRemaining] > 0, paint should lerp displaySlot toward
  // [slot] for the smooth one-step-forward walk that replaces the
  // old instantaneous slot swap.
  double displaySlot;
  double slotShiftRemaining;
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
  })  : displaySlot = slot.toDouble(),
        slotShiftRemaining = 0;

  // Realistic-pace pass — was a single 1.0s for every transition, which
  // read as teleporting at any meaningful pixel distance. Differentiated
  // by leg length so each walk feels like a real step rather than a
  // snap.
  static const _enterWalkTime = 2.8; // entrance gate → queue back
  static const _boardWalkTime = 1.8; // queue front → ramp → cart
  static const _exitWalkTime = 2.4; // cart → ramp → exit gate
  static const _slotShiftTime = 0.8; // queue one-step-forward shift

  double _walkTimeForState() {
    switch (state) {
      case _GuestState.entering:
        return _enterWalkTime;
      case _GuestState.boarding:
        return _boardWalkTime;
      case _GuestState.exiting:
        return _exitWalkTime;
      default:
        return _enterWalkTime;
    }
  }

  void walkTick(double dt) {
    // Drain any in-progress slot shift on wall-clock regardless of
    // state — a waiting guest in front of a shifting line should still
    // step forward.
    if (slotShiftRemaining > 0) {
      slotShiftRemaining = (slotShiftRemaining - dt).clamp(0.0, _slotShiftTime);
      if (slotShiftRemaining <= 0) {
        displaySlot = slot.toDouble();
      } else {
        final t = 1.0 - (slotShiftRemaining / _slotShiftTime);
        // Lerp from where we were to where we need to be; the source
        // value is recovered each tick from displaySlot's lag (target -
        // shift size). For the common +1 step this resolves cleanly.
        displaySlot = displaySlot + (slot.toDouble() - displaySlot) * t;
      }
    } else {
      displaySlot = slot.toDouble();
    }

    if (state == _GuestState.waiting || state == _GuestState.riding) {
      progress = 1.0;
      return;
    }
    progress = (progress + dt / _walkTimeForState()).clamp(0.0, 1.0);
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

  /// Begin a smooth one-step-forward shift toward the new [slot] value.
  /// Captures the current visual position as the source so the lerp
  /// stays continuous even if a shift is already in flight.
  void beginSlotShift(int newSlot) {
    if (newSlot == slot) return;
    // displaySlot already reflects current visual position (whether
    // mid-shift or settled), so we just keep it as the start point.
    slot = newSlot;
    slotShiftRemaining = _slotShiftTime;
  }
}

class _Petal {
  double x, y, speed, sway, size;
  Color color;
  _Petal({
    required this.x,
    required this.y,
    required this.speed,
    required this.sway,
    required this.size,
    required this.color,
  });
}

class _Firefly {
  double baseX, baseY, amp, phase, speed, twinklePhase;
  _Firefly({
    required this.baseX,
    required this.baseY,
    required this.amp,
    required this.phase,
    required this.speed,
    required this.twinklePhase,
  });
}

const _phaseLoadEnd = 0.25;
const _phaseTravelOutEnd = 0.50;
const _phaseTravelBackEnd = 0.75;

// ─── Palette ────────────────────────────────────────────────────────
//
// Golden-hour cozy. Warm dominant, low saturation, a touch of cool
// in the sky and shadows for balance.

const _skyTop = Color(0xFFE5DCEC);
const _skyMid = Color(0xFFFAE6D8);
const _skyBot = Color(0xFFFAF0DC);

const _mountainFar = Color(0xFFC6BEC8);
const _mountainNear = Color(0xFFB0A6B2);
const _mountainSnow = Color(0xFFEFE6E8);

const _forestLine = Color(0xFF98AC92);
const _hillsFar = Color(0xFFA8C09A);
const _hillsNear = Color(0xFFC0D8B0);

const _grassMid = Color(0xFFB6CFA0);
const _grassFront = Color(0xFFC8DEB0);
const _grassBlade = Color(0xFF98B888);

const _pathTile = Color(0xFFD4BFA0);
const _pathTileAlt = Color(0xFFC0AB8C);
const _pathGrout = Color(0xFF8E7252);

const _trackRailBoost = Color(0xFFF5C0A8);
const _trackTie = Color(0xFFB89478);
const _trackPillar = Color(0xFFC8B8AA);

const _stationRoof = Color(0xFFDC9A88);
const _stationRoofShade = Color(0xFFC58576);
const _stationWall = Color(0xFFF0DCB8);
const _stationFront = Color(0xFFE0C998);
const _stationStar = Color(0xFFFFD78A);

const _cartBody = Color(0xFFEDB088);
const _cartBodyShade = Color(0xFFD89878);
const _cartHighlight = Color(0xFFFAEAD8);
const _cartTrim = Color(0xFFA08074);

const _treeDark = Color(0xFF7A9A7A);
const _treeMid = Color(0xFF98B898);
const _treeLight = Color(0xFFB8D4B8);
const _treeFruitPink = Color(0xFFF5B8C8);
const _treeFruitYellow = Color(0xFFFFE6A8);

const _mushroomCap = Color(0xFFE8A4A0);
const _mushroomStem = Color(0xFFFAEAD0);

const _rockColor = Color(0xFFB8AEA8);
const _rockShade = Color(0xFFA09690);

const _lanternFrame = Color(0xFF8E7660);
const _lanternGlow = Color(0xFFFFE8B0);
const _firefly = Color(0xFFFFEAA0);

const _cottageWall = Color(0xFFF0DCB8);
const _cottageRoof = Color(0xFFC58576);
const _cottageWindow = Color(0xFFFFE8B0);
const _cottageSmoke = Color(0xFFE5DCEC);

const _shirtPalette = [
  Color(0xFFE8A0A0),
  Color(0xFFA8C7E0),
  Color(0xFFB8D4B0),
  Color(0xFFE8D8A8),
  Color(0xFFC8B0D8),
  Color(0xFFE8C0A8),
  Color(0xFFCEB8E0),
];
const _skinPalette = [
  Color(0xFFFAE0C8),
  Color(0xFFF0D0B8),
  Color(0xFFE0BFA0),
  Color(0xFFC8A088),
  Color(0xFFFFD8B0),
];
const _hairPalette = [
  Color(0xFF6B4F3A),
  Color(0xFF4A3527),
  Color(0xFFD8B878),
  Color(0xFF8E6845),
  Color(0xFF503B2D),
  Color(0xFFB89060),
];
const _petalPalette = [
  Color(0xFFF5C8D0),
  Color(0xFFE8D8F0),
  Color(0xFFFFEAB8),
  Color(0xFFFAEAD8),
];

// ─── Painter ────────────────────────────────────────────────────────

class _ParkPainter extends CustomPainter {
  final double cycle;
  final bool boosted;
  final int stage;
  final double ambient;
  final List<_Guest> guests;
  final List<_Petal> petals;
  final List<_Firefly> fireflies;
  final int waitingCount;
  final int queueCapacity;

  _ParkPainter({
    required this.cycle,
    required this.boosted,
    required this.stage,
    required this.ambient,
    required this.guests,
    required this.petals,
    required this.fireflies,
    required this.waitingCount,
    required this.queueCapacity,
  });

  // Vertical bands.
  static const _yMountain = 0.30;
  static const _yForest = 0.42;
  static const _yHills = 0.50;
  static const _yGrassStart = 0.58;
  static const _yPath = 0.88;

  // Straight horizontal track. The cart shuttles left↔right; one
  // station roughly in the center-left so the queue can be on its
  // left side and the exit walkway on its right.
  double _trackY(Size s) => s.height * 0.58;
  double _trackXLeft(Size s) => s.width * 0.30;
  double _trackXRight(Size s) =>
      s.width * (0.80 + (stage.clamp(0, 50) * 0.0024));

  int get _stageTier {
    if (stage <= 0) return 0;
    return ((stage - 1) ~/ 5).clamp(0, 9).toInt();
  }

  int get _supportCount {
    if (stage <= 1) return 0;
    return math.min(7, 1 + ((stage - 2) ~/ 8));
  }

  int get _cartCarCount {
    if (stage <= 2) return 1;
    return math.min(4, 2 + ((stage - 3) ~/ 16));
  }

  bool get _hasStageLights => stage >= 4;
  bool get _hasTierPennants => stage >= 5;
  double get _stationTrimGrowth => math.min(16.0, stage.clamp(0, 50) * 0.32);

  Color get _stageRailColor => switch (_stageTier) {
        0 => const Color(0xFF8D6E63),
        1 => const Color(0xFFC8A47A),
        2 => const Color(0xFFB0BEC5),
        3 => const Color(0xFFFF8A65),
        4 => const Color(0xFF81D4FA),
        5 => const Color(0xFFFFD54F),
        6 => const Color(0xFFFFF59D),
        7 => const Color(0xFF5E3A48),
        8 => const Color(0xFF90CAF9),
        _ => const Color(0xFFF8F0FF),
      };

  Color get _stageRailAccent => switch (_stageTier) {
        0 => const Color(0xFF5D4037),
        1 => const Color(0xFF8D6E63),
        2 => const Color(0xFF78909C),
        3 => const Color(0xFFD84315),
        4 => const Color(0xFF0288D1),
        5 => const Color(0xFFF57F17),
        6 => const Color(0xFFFFB300),
        7 => const Color(0xFFB71C1C),
        8 => const Color(0xFF42A5F5),
        _ => const Color(0xFFE1BEE7),
      };

  Color get _stageTieColor => Color.lerp(_trackTie, _stageRailAccent, 0.35)!;
  Color get _stageStationRoof =>
      Color.lerp(_stationRoof, _stageRailColor, 0.42)!;
  Color get _stageStationRoofShade =>
      Color.lerp(_stationRoofShade, _stageRailAccent, 0.42)!;
  Color get _stageCartBody => Color.lerp(_cartBody, _stageRailColor, 0.45)!;
  Color get _stageCartBodyShade =>
      Color.lerp(_cartBodyShade, _stageRailAccent, 0.45)!;
  Color get _stageCartTrim => Color.lerp(_cartTrim, _stageRailAccent, 0.35)!;
  Color get _stageCartLight => Color.lerp(_stationStar, _stageRailColor, 0.30)!;

  Offset _cartParkedSpot(Size s) => Offset(_trackXLeft(s), _trackY(s) - 6);
  Offset _stationCenter(Size s) => Offset(_trackXLeft(s), _trackY(s));

  /// Position-class points used by the multi-leg walk system. All
  /// guests transit through these, never cutting across grass.
  Offset _entranceGate(Size s) =>
      Offset(s.width * 0.05, s.height * _yQueueBaseline);
  Offset _boardRampBase(Size s) =>
      Offset(_trackXLeft(s), s.height * _yQueueBaseline);
  Offset _exitRampBase(Size s) =>
      Offset(_trackXLeft(s) + s.width * 0.04, s.height * _yQueueBaseline);
  Offset _boardRampTop(Size s) => _cartParkedSpot(s);
  Offset _exitRampTop(Size s) =>
      Offset(_cartParkedSpot(s).dx + s.width * 0.02, _cartParkedSpot(s).dy);

  static const _yQueueBaseline = 0.78;
  // Queue front (slot 0) sits just LEFT of the station so guests
  // queue toward the boarding ramp, not away from it. Slots step
  // further left toward the entrance gate.
  static const _xQueueFrontFrac = 0.22;
  static const _xQueueSlotSpacing = 0.032;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintSunHaze(canvas, size);
    _paintMountains(canvas, size);
    _paintCottage(canvas, size);
    _paintForestLine(canvas, size);
    _paintHills(canvas, size);
    _paintGrassBand(canvas, size);
    _paintGrassBlades(canvas, size);
    _paintMidTrees(canvas, size);
    _paintWalkPaths(canvas, size); // ← entry/queue/exit walkways
    _paintEntranceGate(canvas, size);
    _paintExitGate(canvas, size);
    _paintBoardingRamp(canvas, size);
    _paintPath(canvas, size);
    _paintMushroomsAndRocks(canvas, size);
    _paintTrack(canvas, size);
    _paintStation(canvas, size);
    _paintLanterns(canvas, size);
    _paintCart(canvas, size);
    _paintQueueGuests(canvas, size);
    _paintBoardingGuests(canvas, size);
    _paintExitingGuests(canvas, size);
    _paintCapacitySign(canvas, size);
    _paintQueueRibbon(canvas, size);
    _paintExitSign(canvas, size);
    _paintForegroundFlowers(canvas, size);
    _paintFireflies(canvas, size);
    _paintPetals(canvas, size);
    _paintVignette(canvas, size);
  }

  // ═══ Walk paths ═══════════════════════════════════════════════
  //
  // Visual flow:
  //   entrance gate (left edge)  ─┐
  //                                ├─ along queue path eastward
  //   queue line (with rope)     ─┘
  //                                ├─ ramp UP into the cart
  //   cart parked at station     ─┐
  //                                ├─ ramp DOWN off the cart
  //   exit walkway eastward       ─┘
  //   exit gate (right edge)
  //
  // We draw the paved walkway underlay first so guests + props sit
  // on top of it.

  void _paintWalkPaths(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Main horizontal walkway band — runs entrance→queue→exit at
    // queue baseline. Slightly darker than the foreground path tile
    // so it reads as a defined route through the grass.
    final walkY = h * (_yQueueBaseline - 0.005);
    final walkRect = Rect.fromLTWH(0, walkY, w, h * 0.07);
    canvas.drawRect(walkRect, Paint()..color = _pathTile);
    // Soft inner stripe for depth.
    canvas.drawRect(
      Rect.fromLTWH(0, walkY + 1.5, w, 1.5),
      Paint()..color = const Color(0xFFE8D8B8),
    );
    // Edge lines (top + bottom).
    final edge = Paint()
      ..color = _pathGrout.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, walkY), Offset(w, walkY), edge);
    canvas.drawLine(
        Offset(0, walkY + h * 0.07), Offset(w, walkY + h * 0.07), edge);
    // Small cobblestone tile breaks for texture.
    final rng = math.Random(21);
    for (var x = 8.0; x < w - 8; x += 26 + rng.nextDouble() * 8) {
      canvas.drawLine(
        Offset(x, walkY + 2),
        Offset(x, walkY + h * 0.07 - 2),
        Paint()
          ..color = _pathGrout.withValues(alpha: 0.20)
          ..strokeWidth = 0.8,
      );
    }
  }

  // ═══ Sky ════════════════════════════════════════════════════════

  void _paintSky(Canvas canvas, Size size) {
    final shader = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(0, size.height * _yGrassStart),
      const [_skyTop, _skyMid, _skyBot],
      const [0.0, 0.6, 1.0],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _paintSunHaze(Canvas canvas, Size size) {
    // Soft golden glow upper-right with no hard sun disk — pure
    // atmospheric light.
    final c = Offset(size.width * 0.78, size.height * 0.08);
    final shader = ui.Gradient.radial(
      c,
      size.width * 0.55,
      [
        const Color(0xFFFFEFC4).withValues(alpha: 0.85),
        const Color(0xFFFFEFC4).withValues(alpha: 0.0),
      ],
      [0.0, 1.0],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);

    // Three slow drifting clouds, very faint.
    for (var i = 0; i < 3; i++) {
      final phase = (ambient + i * 0.34) % 1.0;
      final cx = (phase * 1.3 - 0.15) * size.width;
      final cy = size.height * (0.06 + 0.06 * i);
      _paintCloud(canvas, Offset(cx, cy), 24 + i * 6.0);
    }

    // Very small bird silhouettes, occasional.
    final birdPaint = Paint()
      ..color = const Color(0xFF8E7660).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final bx = size.width * (0.18 + math.sin(ambient * math.pi * 2) * 0.04);
    final by = size.height * (0.12 + math.cos(ambient * math.pi * 2) * 0.005);
    _paintBird(canvas, Offset(bx, by), birdPaint);
    _paintBird(canvas, Offset(bx + 14, by + 4), birdPaint..strokeWidth = 0.8);
  }

  void _paintBird(Canvas canvas, Offset c, Paint paint) {
    final p = Path()
      ..moveTo(c.dx - 4, c.dy + 1)
      ..quadraticBezierTo(c.dx - 2, c.dy - 2, c.dx, c.dy)
      ..quadraticBezierTo(c.dx + 2, c.dy - 2, c.dx + 4, c.dy + 1);
    canvas.drawPath(p, paint);
  }

  void _paintCloud(Canvas canvas, Offset center, double r) {
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawCircle(center, r, fill);
    canvas.drawCircle(center.translate(-r * 0.6, r * 0.2), r * 0.7, fill);
    canvas.drawCircle(center.translate(r * 0.7, r * 0.15), r * 0.75, fill);
    canvas.drawCircle(center.translate(r * 0.2, -r * 0.4), r * 0.55, fill);
  }

  // ═══ Mountains (very far) ══════════════════════════════════════

  void _paintMountains(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final baseY = h * _yMountain;

    // Far layer
    final far = Path()..moveTo(0, baseY);
    final farPeaks = <double>[0.10, 0.25, 0.40, 0.58, 0.72, 0.88];
    for (final fx in farPeaks) {
      far.lineTo(fx * w - 30, baseY);
      far.lineTo(fx * w, baseY - h * 0.06);
      far.lineTo(fx * w + 30, baseY);
    }
    far.lineTo(w, baseY);
    far.close();
    canvas.drawPath(far, Paint()..color = _mountainFar);

    // Near layer with snowcaps
    final near = Path()..moveTo(0, baseY);
    final nearPeaks = <double>[0.18, 0.45, 0.65, 0.92];
    for (final fx in nearPeaks) {
      near.lineTo(fx * w - 38, baseY);
      near.lineTo(fx * w, baseY - h * 0.085);
      near.lineTo(fx * w + 38, baseY);
    }
    near.lineTo(w, baseY);
    near.close();
    canvas.drawPath(near, Paint()..color = _mountainNear);

    // Snowcaps
    for (final fx in nearPeaks) {
      final snow = Path()
        ..moveTo(fx * w - 14, baseY - h * 0.06)
        ..lineTo(fx * w + 14, baseY - h * 0.06)
        ..lineTo(fx * w + 6, baseY - h * 0.078)
        ..lineTo(fx * w, baseY - h * 0.085)
        ..lineTo(fx * w - 6, baseY - h * 0.078)
        ..close();
      canvas.drawPath(snow, Paint()..color = _mountainSnow);
    }
  }

  // ═══ Cottage in distance ═══════════════════════════════════════

  void _paintCottage(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.84;
    final baseY = h * (_yForest + 0.02);

    // Wall
    final wallRect = Rect.fromLTWH(cx - 11, baseY - 14, 22, 14);
    canvas.drawRect(wallRect, Paint()..color = _cottageWall);
    // Window glow
    canvas.drawRect(
      Rect.fromLTWH(cx - 3, baseY - 10, 6, 6),
      Paint()..color = _cottageWindow,
    );
    // Window glow halo
    canvas.drawCircle(
      Offset(cx, baseY - 7),
      8,
      Paint()..color = _cottageWindow.withValues(alpha: 0.35),
    );
    // Door
    canvas.drawRect(
      Rect.fromLTWH(cx + 4, baseY - 7, 4, 7),
      Paint()..color = const Color(0xFF8E7660),
    );
    // Roof — triangle
    final roof = Path()
      ..moveTo(cx - 14, baseY - 14)
      ..lineTo(cx + 14, baseY - 14)
      ..lineTo(cx, baseY - 22)
      ..close();
    canvas.drawPath(roof, Paint()..color = _cottageRoof);
    // Chimney
    canvas.drawRect(
      Rect.fromLTWH(cx + 4, baseY - 22, 3, 6),
      Paint()..color = _cottageRoof,
    );
    // Smoke — 3 puffs drifting up + sway
    for (var i = 0; i < 3; i++) {
      final phase = (ambient * 1.5 + i * 0.33) % 1.0;
      final sx = cx + 5.5 + math.sin(phase * math.pi * 2) * 1.5;
      final sy = baseY - 24 - phase * 14;
      final r = 2.0 + phase * 1.5;
      final alpha = (1 - phase) * 0.7;
      canvas.drawCircle(
        Offset(sx, sy),
        r,
        Paint()..color = _cottageSmoke.withValues(alpha: alpha),
      );
    }
  }

  // ═══ Forest line ═══════════════════════════════════════════════

  void _paintForestLine(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final y = h * _yForest;
    final paint = Paint()..color = _forestLine;
    // Many small bumpy trees forming a treeline.
    for (var i = 0; i < 24; i++) {
      final x = (i / 24) * w + (i.isEven ? 0 : 6);
      final bumpR = 6 + (i % 3) * 1.5;
      canvas.drawCircle(Offset(x, y), bumpR, paint);
    }
    // Cap with a flat band so it grounds onto the hill.
    canvas.drawRect(
      Rect.fromLTWH(0, y, w, 1.5),
      Paint()..color = _forestLine.withValues(alpha: 0.7),
    );
  }

  // ═══ Hills ═════════════════════════════════════════════════════

  void _paintHills(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final y = h * _yHills;
    // Rolling hill silhouette.
    final p = Path()..moveTo(0, y + h * 0.04);
    p.quadraticBezierTo(w * 0.20, y - h * 0.02, w * 0.40, y + h * 0.01);
    p.quadraticBezierTo(w * 0.55, y + h * 0.04, w * 0.72, y - h * 0.01);
    p.quadraticBezierTo(w * 0.86, y + h * 0.02, w, y + h * 0.03);
    p.lineTo(w, y + h * 0.10);
    p.lineTo(0, y + h * 0.10);
    p.close();
    canvas.drawPath(p, Paint()..color = _hillsFar);

    // Lighter near-hill band.
    final p2 = Path()..moveTo(0, y + h * 0.06);
    p2.quadraticBezierTo(w * 0.30, y + h * 0.03, w * 0.60, y + h * 0.06);
    p2.quadraticBezierTo(w * 0.85, y + h * 0.05, w, y + h * 0.07);
    p2.lineTo(w, y + h * 0.14);
    p2.lineTo(0, y + h * 0.14);
    p2.close();
    canvas.drawPath(p2, Paint()..color = _hillsNear);
  }

  // ═══ Grass band ════════════════════════════════════════════════

  void _paintGrassBand(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    canvas.drawRect(
      Rect.fromLTWH(0, h * _yGrassStart, w, h * (_yPath - _yGrassStart)),
      Paint()..color = _grassMid,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.74, w, h * (_yPath - 0.74)),
      Paint()..color = _grassFront.withValues(alpha: 0.85),
    );
  }

  void _paintGrassBlades(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _grassBlade.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final rng = math.Random(11);
    // Scatter small blade strokes in the grass area.
    for (var i = 0; i < 80; i++) {
      final x = rng.nextDouble() * w;
      final y = h * (_yGrassStart + 0.04) + rng.nextDouble() * h * 0.30;
      final tilt = (rng.nextDouble() - 0.5) * 1.0;
      canvas.drawLine(Offset(x, y), Offset(x + tilt, y - 3), paint);
    }
  }

  // ═══ Mid trees (foreground / framing) ══════════════════════════

  void _paintMidTrees(Canvas canvas, Size size) {
    // Trees framing the scene + a couple in the middle distance.
    const trees = <List<double>>[
      [0.04, 0.62, 1.0],
      [0.13, 0.66, 0.85],
      [0.86, 0.62, 0.95],
      [0.95, 0.66, 0.85],
      [0.40, 0.71, 0.65],
      [0.74, 0.71, 0.7],
    ];
    for (final t in trees) {
      _paintFluffyTree(canvas, size, t[0], t[1], t[2]);
    }
  }

  /// Tree drawn as a stack of soft leaf-cluster ovals — way more
  /// believable than a single circle. Light source upper-left so the
  /// rightmost clusters stay darker.
  void _paintFluffyTree(
      Canvas canvas, Size size, double xFrac, double yFrac, double scale) {
    final cx = size.width * xFrac;
    final cy = size.height * yFrac;
    final r = 28 * scale;

    // Soft ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + r * 0.95), width: r * 1.7, height: r * 0.45),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );

    // Trunk — soft tone, gently tapered, faint vertical line for grain.
    final trunkRect =
        Rect.fromLTWH(cx - 3.5 * scale, cy, 7 * scale, 22 * scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trunkRect, Radius.circular(2 * scale)),
      Paint()..color = const Color(0xFFB39A82),
    );
    canvas.drawLine(
      Offset(cx - 1.2 * scale, cy + 3 * scale),
      Offset(cx - 1.2 * scale, cy + 18 * scale),
      Paint()
        ..color = const Color(0xFF9A8166).withValues(alpha: 0.55)
        ..strokeWidth = 0.7,
    );

    // Leaf clusters — base layer (darker), mid layer, light dabs.
    final clusters = <List<double>>[
      // dx, dy, radius factor
      [-0.55, 0.05, 0.78],
      [0.55, 0.05, 0.75],
      [-0.20, -0.12, 0.85],
      [0.25, -0.18, 0.82],
      [0.0, 0.10, 0.90],
      [-0.35, 0.25, 0.65],
      [0.40, 0.22, 0.65],
      [-0.10, -0.40, 0.55],
    ];
    final dark = Paint()..color = _treeDark;
    for (final c in clusters) {
      canvas.drawCircle(
        Offset(cx + c[0] * r, cy + c[1] * r),
        r * c[2] * 0.55,
        dark,
      );
    }
    final mid = Paint()..color = _treeMid;
    for (final c in clusters) {
      // Offset toward upper-left for that lit feel.
      canvas.drawCircle(
        Offset(cx + c[0] * r - r * 0.05, cy + c[1] * r - r * 0.06),
        r * c[2] * 0.42,
        mid,
      );
    }
    final light = Paint()..color = _treeLight;
    final lightSpots = <List<double>>[
      [-0.50, -0.10],
      [0.10, -0.30],
      [-0.10, 0.0],
      [0.40, -0.05],
    ];
    for (final c in lightSpots) {
      canvas.drawCircle(
        Offset(cx + c[0] * r, cy + c[1] * r),
        r * 0.20,
        light,
      );
    }

    // Small fruit dots (alternating pink/yellow) for cozy charm.
    final fruitPaint = Paint();
    final fruitSpots = <List<double>>[
      [-0.42, 0.10],
      [0.30, -0.02],
      [-0.10, 0.20],
      [0.45, 0.18],
    ];
    for (var i = 0; i < fruitSpots.length; i++) {
      fruitPaint.color = i.isEven ? _treeFruitPink : _treeFruitYellow;
      final s = fruitSpots[i];
      canvas.drawCircle(
        Offset(cx + s[0] * r, cy + s[1] * r),
        1.6 * scale,
        fruitPaint,
      );
    }
  }

  // ═══ Path with cobblestone tiles ═══════════════════════════════

  void _paintPath(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Path band at the foreground.
    final pathTop = h * _yPath;
    final pathBot = h * 0.99;
    canvas.drawRect(
      Rect.fromLTWH(0, pathTop, w, pathBot - pathTop),
      Paint()..color = _pathTile,
    );
    // Cobblestone tiles.
    final rng = math.Random(7);
    final tile = Paint();
    final grout = Paint()
      ..color = _pathGrout.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const rows = 2;
    for (var ri = 0; ri < rows; ri++) {
      final y = pathTop + (ri + 0.5) * (pathBot - pathTop) / rows;
      for (var x = -10.0; x < w + 10; x += 22 + rng.nextDouble() * 6) {
        final shift = (ri.isEven ? 0.0 : 11.0);
        final cx = x + shift;
        final tw = 16.0 + rng.nextDouble() * 6;
        final th = 9.0 + rng.nextDouble() * 3;
        tile.color = rng.nextBool() ? _pathTile : _pathTileAlt;
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, y), width: tw, height: th),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(r, tile);
        canvas.drawRRect(r, grout);
      }
    }
  }

  // ═══ Mushrooms + rocks (small props) ═══════════════════════════

  void _paintMushroomsAndRocks(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Rocks scattered.
    const rocks = <List<double>>[
      [0.09, 0.84],
      [0.92, 0.84],
      [0.46, 0.84],
      [0.66, 0.85],
    ];
    for (final r in rocks) {
      final cx = w * r[0];
      final cy = h * r[1];
      // Shadow.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 4), width: 12, height: 3),
        Paint()..color = Colors.black.withValues(alpha: 0.15),
      );
      // Body.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 10, height: 7),
        Paint()..color = _rockColor,
      );
      // Shadow side.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 1.5, cy + 1), width: 6, height: 4),
        Paint()..color = _rockShade,
      );
      // Highlight dot.
      canvas.drawCircle(
        Offset(cx - 2, cy - 1.5),
        1.2,
        Paint()..color = const Color(0xFFE0DAD2),
      );
    }

    // Mushroom clusters.
    const mushrooms = <List<double>>[
      [0.16, 0.83],
      [0.82, 0.83],
      [0.55, 0.85],
    ];
    for (final m in mushrooms) {
      final cx = w * m[0];
      final cy = h * m[1];
      _paintMushroom(canvas, Offset(cx - 4, cy + 1), 0.9);
      _paintMushroom(canvas, Offset(cx + 3, cy), 1.1);
    }
  }

  void _paintMushroom(Canvas canvas, Offset c, double scale) {
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx, c.dy + 4 * scale),
          width: 8 * scale,
          height: 2.5 * scale),
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.drawRect(
      Rect.fromCenter(
          center: c.translate(0, 2 * scale),
          width: 3 * scale,
          height: 4 * scale),
      Paint()..color = _mushroomStem,
    );
    final cap = Path()
      ..moveTo(c.dx - 5 * scale, c.dy + 1 * scale)
      ..quadraticBezierTo(
          c.dx, c.dy - 5.5 * scale, c.dx + 5 * scale, c.dy + 1 * scale)
      ..close();
    canvas.drawPath(cap, Paint()..color = _mushroomCap);
    // Spots.
    final spotPaint = Paint()..color = _mushroomStem;
    canvas.drawCircle(
        c.translate(-1.5 * scale, -1 * scale), 0.8 * scale, spotPaint);
    canvas.drawCircle(
        c.translate(1.5 * scale, -0.5 * scale), 0.6 * scale, spotPaint);
  }

  // ═══ Track ═════════════════════════════════════════════════════

  /// Cart x position by cycle phase. Stays at the left station during
  /// load (0..0.25) and unload (0.75..1.0); shuttles right during
  /// travel-out (0.25..0.50) and back during travel-back (0.50..0.75).
  /// EaseInOut gives a soft accel/decel at each end for the cozy
  /// feel — no abrupt direction flips.
  double _easeInOut(double t) => 0.5 - 0.5 * math.cos(t * math.pi);

  Offset _cartPosition(Size size) {
    final left = _trackXLeft(size);
    final right = _trackXRight(size);
    final y = _trackY(size);
    if (cycle < _phaseLoadEnd) {
      return Offset(left, y);
    } else if (cycle < _phaseTravelOutEnd) {
      final p = (cycle - _phaseLoadEnd) / (_phaseTravelOutEnd - _phaseLoadEnd);
      return Offset(left + (right - left) * _easeInOut(p), y);
    } else if (cycle < _phaseTravelBackEnd) {
      final p = (cycle - _phaseTravelOutEnd) /
          (_phaseTravelBackEnd - _phaseTravelOutEnd);
      return Offset(right - (right - left) * _easeInOut(p), y);
    } else {
      return Offset(left, y);
    }
  }

  void _paintTrack(Canvas canvas, Size size) {
    final left = _trackXLeft(size);
    final right = _trackXRight(size);
    final y = _trackY(size);

    // No long pillars under the track — they were dominating the
    // composition. Instead, two small base blocks anchor the rail
    // ends so the track reads as resting on something, not floating.
    final basePaint = Paint()
      ..color = Color.lerp(_trackPillar, _stageRailAccent, 0.18)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(left - 4, y + 12), width: 14, height: 10),
        const Radius.circular(2.5),
      ),
      basePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(right + 4, y + 12), width: 14, height: 10),
        const Radius.circular(2.5),
      ),
      basePaint,
    );

    if (_supportCount > 0) {
      final supportPaint = Paint()
        ..color = Color.lerp(_trackPillar, _stageRailAccent, 0.24)!;
      final supportShade = Paint()
        ..color = _stageRailAccent.withValues(alpha: 0.24)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i <= _supportCount; i++) {
        final x = left + (right - left) * i / (_supportCount + 1);
        final supportHeight = 16.0 + (i.isEven ? 5.0 : 0.0) + _stageTier * 0.8;
        final support = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y + 12 + supportHeight / 2),
            width: 5.5,
            height: supportHeight,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(support, supportPaint);
        canvas.drawLine(
          Offset(x + 1.2, y + 15),
          Offset(x + 1.2, y + 9 + supportHeight),
          supportShade,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(x, y + 15 + supportHeight),
              width: 18,
              height: 5,
            ),
            const Radius.circular(2),
          ),
          supportPaint,
        );
      }
    }

    // Drop shadow under rails so the track reads anchored.
    canvas.save();
    canvas.translate(0, 3);
    canvas.drawLine(
      Offset(left - 4, y),
      Offset(right + 4, y),
      Paint()
        ..color = const Color(0xFF8E5E50).withValues(alpha: 0.28)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Two parallel rails (top + bottom) — soft coral.
    final railColor = boosted
        ? Color.lerp(_stageRailColor, _trackRailBoost, 0.35)!
        : _stageRailColor;
    final railPaint = Paint()
      ..color = railColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(left - 2, y - 4), Offset(right + 2, y - 4), railPaint);
    canvas.drawLine(
        Offset(left - 2, y + 4), Offset(right + 2, y + 4), railPaint);

    // Soft white inner highlight on the upper rail (light from above).
    canvas.drawLine(
      Offset(left - 2, y - 4.6),
      Offset(right + 2, y - 4.6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round,
    );

    // Wooden crossties between the two rails.
    const tieSpacing = 12.0;
    for (var x = left; x <= right; x += tieSpacing) {
      canvas.drawLine(
        Offset(x, y - 6),
        Offset(x, y + 6),
        Paint()
          ..color = _stageTieColor
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
      // Tiny lighter grain stripe.
      canvas.drawLine(
        Offset(x - 0.3, y - 5.5),
        Offset(x - 0.3, y + 5.5),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.32)
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round,
      );
    }

    if (_hasStageLights) {
      final bulbCount = math.min(10, 3 + stage ~/ 6);
      for (var i = 0; i < bulbCount; i++) {
        final x = left + (right - left) * (i + 0.5) / bulbCount;
        final pulse = 0.4 + 0.3 * math.sin((ambient + i * 0.13) * math.pi * 2);
        canvas.drawCircle(
          Offset(x, y - 12),
          2.2 + pulse,
          Paint()..color = _stageCartLight.withValues(alpha: 0.18),
        );
        canvas.drawCircle(
          Offset(x, y - 12),
          1.3,
          Paint()..color = _stageCartLight.withValues(alpha: 0.78),
        );
      }
    }

    // End buffers — small bumpers at each track end so it doesn't
    // look cut off.
    final bufferPaint = Paint()..color = _trackPillar;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(left - 4, y), width: 5, height: 14),
        const Radius.circular(2),
      ),
      bufferPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(right + 4, y), width: 5, height: 14),
        const Radius.circular(2),
      ),
      bufferPaint,
    );
  }

  // ═══ Station ═══════════════════════════════════════════════════

  void _paintStation(Canvas canvas, Size size) {
    final c = _stationCenter(size);

    // Platform + front face.
    final platTopY = c.dy + 12;
    final platBotY = c.dy + 28;
    final platL = c.dx - 38;
    final platR = c.dx + 38;
    final platTop = Path()
      ..moveTo(platL + 4, platTopY)
      ..lineTo(platR - 4, platTopY)
      ..lineTo(platR, platBotY)
      ..lineTo(platL, platBotY)
      ..close();
    canvas.drawPath(platTop, Paint()..color = _stationWall);
    final platFront = Path()
      ..moveTo(platL, platBotY)
      ..lineTo(platR, platBotY)
      ..lineTo(platR - 4, platBotY + 8)
      ..lineTo(platL + 4, platBotY + 8)
      ..close();
    canvas.drawPath(platFront, Paint()..color = _stationFront);

    // Roof — soft coral with a triangle silhouette so it reads
    // cottage-y, not boxy.
    final roofL = c.dx - 36;
    final roofR = c.dx + 36;
    final roofMid = c.dy - 8;
    final roofPeak = c.dy - 22;
    final roofShape = Path()
      ..moveTo(roofL, roofMid)
      ..lineTo(roofR, roofMid)
      ..lineTo(roofR - 6, roofPeak + 4)
      ..lineTo(c.dx, roofPeak)
      ..lineTo(roofL + 6, roofPeak + 4)
      ..close();
    canvas.drawPath(roofShape, Paint()..color = _stageStationRoof);
    // Lit edge along upper-left.
    final litEdge = Path()
      ..moveTo(roofL, roofMid)
      ..lineTo(c.dx, roofPeak)
      ..lineTo(roofL + 6, roofPeak + 4)
      ..close();
    canvas.drawPath(litEdge, Paint()..color = _stageStationRoofShade);
    // Trim line.
    canvas.drawRect(
      Rect.fromLTWH(
        c.dx - 32 - _stationTrimGrowth / 2,
        c.dy - 9,
        64 + _stationTrimGrowth,
        2,
      ),
      Paint()..color = const Color(0xFFFAEAD8),
    );
    if (_hasStageLights) {
      for (var i = 0; i < 5; i++) {
        final x = c.dx - 24 + i * 12;
        canvas.drawCircle(
          Offset(x, c.dy - 7),
          1.5,
          Paint()..color = _stageCartLight.withValues(alpha: 0.82),
        );
      }
    }
    // Roof support poles.
    final poleColor = Paint()
      ..color = const Color(0xFF9A8E80)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(c.dx - 30, c.dy - 6), Offset(c.dx - 30, c.dy + 12), poleColor);
    canvas.drawLine(
        Offset(c.dx + 30, c.dy - 6), Offset(c.dx + 30, c.dy + 12), poleColor);

    if (_hasTierPennants) {
      // Soft star ornament on roof peak.
      canvas.drawCircle(
        Offset(c.dx, roofPeak - 4),
        3,
        Paint()..color = _stageCartLight,
      );
      canvas.drawCircle(
        Offset(c.dx, roofPeak - 4),
        6,
        Paint()..color = _stageCartLight.withValues(alpha: 0.35),
      );
    }

    // Front step.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(c.dx + 24, platBotY + 4, 18, 6),
        const Radius.circular(2.5),
      ),
      Paint()..color = const Color(0xFFB0CBA8),
    );

    // Hanging banner under roof — simple cream cloth with stitched edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(c.dx, c.dy - 1), width: 36, height: 7),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFFFAEAD8),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: '코스터',
        style: TextStyle(
          color: Color(0xFF6B4F3A),
          fontSize: 6.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - 4.5));
  }

  // ═══ Lanterns (warm glow) ══════════════════════════════════════

  void _paintLanterns(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const positions = <List<double>>[
      [0.20, 0.86],
      [0.50, 0.86],
      [0.80, 0.86],
    ];
    final pulse = (math.sin(ambient * math.pi * 2) + 1) / 2;
    for (final p in positions) {
      final cx = w * p[0];
      final cy = h * p[1];
      // Post.
      canvas.drawRect(
        Rect.fromLTWH(cx - 0.7, cy - 22, 1.5, 22),
        Paint()..color = _lanternFrame,
      );
      // Crossbar.
      canvas.drawRect(
        Rect.fromLTWH(cx - 4, cy - 22, 8, 1.5),
        Paint()..color = _lanternFrame,
      );
      // Lamp body.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 3, cy - 20, 6, 5),
          const Radius.circular(1.2),
        ),
        Paint()..color = _lanternFrame,
      );
      // Glow halo.
      canvas.drawCircle(
        Offset(cx, cy - 18),
        7 + pulse,
        Paint()..color = _lanternGlow.withValues(alpha: 0.30 + pulse * 0.10),
      );
      canvas.drawCircle(
        Offset(cx, cy - 18),
        3,
        Paint()..color = _lanternGlow,
      );
    }
  }

  // ═══ Cart ══════════════════════════════════════════════════════

  void _paintCart(Canvas canvas, Size size) {
    final pos = _cartPosition(size);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    // Boost gentle bounce, never harsh.
    final shake = boosted ? math.sin(ambient * math.pi * 22) * 0.4 : 0.0;
    // Lift cart so its wheels rest right on the upper rail (y - 4).
    canvas.translate(0, shake - 11);

    // Soft drop shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-(_cartCarCount - 1) * 18, 17),
        width: 56 + (_cartCarCount - 1) * 38,
        height: 7,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );

    for (var car = _cartCarCount - 1; car >= 1; car--) {
      _paintTrailerCar(canvas, Offset(-40.0 * car, 1), car);
    }

    // Body — peach with rounded top, soft shading band on bottom.
    final bodyRect =
        Rect.fromCenter(center: Offset.zero, width: 56, height: 24);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        bodyRect,
        topLeft: const Radius.circular(13),
        topRight: const Radius.circular(13),
        bottomLeft: const Radius.circular(5),
        bottomRight: const Radius.circular(5),
      ),
      Paint()..color = _stageCartBody,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(-28, 1, 56, 11),
        bottomLeft: const Radius.circular(5),
        bottomRight: const Radius.circular(5),
      ),
      Paint()..color = _stageCartBodyShade,
    );
    // Cream highlight stripe.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -8), width: 50, height: 3.5),
        const Radius.circular(1.5),
      ),
      Paint()..color = _cartHighlight,
    );

    // Round window (gives the cart a "face" — looks like a soft eye).
    canvas.drawCircle(
      const Offset(-8, -2),
      4.2,
      Paint()..color = _stageCartTrim,
    );
    canvas.drawCircle(
      const Offset(-8, -2),
      3.4,
      Paint()..color = const Color(0xFFB8DCE8),
    );
    canvas.drawCircle(
      const Offset(-9, -3),
      1.4,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Front headlight (soft amber).
    canvas.drawCircle(
      const Offset(20, -2),
      4,
      Paint()..color = _stageCartLight.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      const Offset(20, -2),
      2.2,
      Paint()..color = _stageCartLight,
    );

    // Tiny smile (white arc) below the window so the cart reads
    // friendly.
    final smile = Paint()
      ..color = _stageCartTrim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(-8, 5), width: 8, height: 5),
      0.2,
      math.pi - 0.4,
      false,
      smile,
    );

    // Wheels.
    final wheelOuter = Paint()..color = const Color(0xFF8A7E72);
    final wheelInner = Paint()..color = const Color(0xFFE0D8CC);
    canvas.drawCircle(const Offset(-19, 13), 5.5, wheelOuter);
    canvas.drawCircle(const Offset(19, 13), 5.5, wheelOuter);
    canvas.drawCircle(const Offset(-19, 13), 2.5, wheelInner);
    canvas.drawCircle(const Offset(19, 13), 2.5, wheelInner);

    if (_hasStageLights) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-24, 9, 48, 2.5),
          const Radius.circular(1.2),
        ),
        Paint()..color = _stageCartLight.withValues(alpha: 0.70),
      );
    }

    // Riders — chibi, gently raised arms.
    final riders =
        guests.where((g) => g.state == _GuestState.riding).take(2).toList();
    for (var i = 0; i < riders.length; i++) {
      final dx = -10.0 + i * 20.0;
      _paintRiderInCart(canvas, Offset(dx, -10), riders[i]);
    }

    if (_hasTierPennants) {
      // Tiny flag pennant on top of the cart.
      final flagPole = Paint()
        ..color = _stageCartTrim
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(-22, -12), const Offset(-22, -22), flagPole);
      final flag = Path()
        ..moveTo(-22, -22)
        ..lineTo(-15, -19)
        ..lineTo(-22, -16)
        ..close();
      canvas.drawPath(flag, Paint()..color = _stageCartLight);
    }

    // Boost — soft sparkle dots, no harsh streaks.
    if (boosted) {
      final sparkle = Paint()..color = _lanternGlow.withValues(alpha: 0.75);
      canvas.drawCircle(const Offset(-32, -3), 1.5, sparkle);
      canvas.drawCircle(const Offset(-36, 1), 1.0, sparkle);
      canvas.drawCircle(const Offset(-32, 5), 1.3, sparkle);
    }

    canvas.restore();
  }

  void _paintTrailerCar(Canvas canvas, Offset center, int index) {
    const width = 34.0;
    const height = 20.0;
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final body = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(
        body, Paint()..color = _stageCartBody.withValues(alpha: 0.92));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 4, rect.top + 5, width - 8, 5),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.52),
    );
    if (_hasStageLights) {
      canvas.drawCircle(
        Offset(rect.right - 5, rect.top + 4),
        1.8,
        Paint()..color = _stageCartLight.withValues(alpha: 0.75),
      );
    }
    final wheelOuter = Paint()..color = const Color(0xFF8A7E72);
    final wheelInner = Paint()..color = const Color(0xFFE0D8CC);
    for (final dx in [-width * 0.26, width * 0.26]) {
      final p = center.translate(dx, height * 0.55);
      canvas.drawCircle(p, 4.2, wheelOuter);
      canvas.drawCircle(p, 1.9, wheelInner);
    }
    if (_hasTierPennants && index == _cartCarCount - 1) {
      canvas.drawCircle(
        center.translate(-width * 0.32, -height * 0.42),
        2.2,
        Paint()..color = _stageCartLight.withValues(alpha: 0.9),
      );
    }
  }

  void _paintRiderInCart(Canvas canvas, Offset center, _Guest g) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, 4.5), width: 6, height: 5),
        const Radius.circular(1.5),
      ),
      Paint()..color = g.shirt,
    );
    canvas.drawCircle(center, 3.7, Paint()..color = g.skin);
    final hair = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: 3.7),
        math.pi,
        math.pi,
      );
    canvas.drawPath(hair, Paint()..color = g.hair);
    final eye = Paint()..color = const Color(0xFF5A4A40);
    canvas.drawCircle(center.translate(-1.3, 0), 0.7, eye);
    canvas.drawCircle(center.translate(1.3, 0), 0.7, eye);
    // Eye highlight.
    final eyeHi = Paint()..color = Colors.white;
    canvas.drawCircle(center.translate(-1.0, -0.3), 0.25, eyeHi);
    canvas.drawCircle(center.translate(1.6, -0.3), 0.25, eyeHi);
    // Mini smile.
    canvas.drawArc(
      Rect.fromCenter(
          center: center.translate(0, 1.4), width: 2.2, height: 1.4),
      0,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF6B4F3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..strokeCap = StrokeCap.round,
    );
    // Cheek blush.
    canvas.drawCircle(center.translate(-2.2, 0.8), 0.7,
        Paint()..color = const Color(0xFFF5C8C0).withValues(alpha: 0.7));
    canvas.drawCircle(center.translate(2.2, 0.8), 0.7,
        Paint()..color = const Color(0xFFF5C8C0).withValues(alpha: 0.7));
    // Raised arms.
    final arm = Paint()
      ..color = g.skin
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        center.translate(-2, 1.5), center.translate(-3.5, -3.2), arm);
    canvas.drawLine(center.translate(2, 1.5), center.translate(3.5, -3.2), arm);
  }

  // ═══ Queue / boarding / exit ═══════════════════════════════════

  void _paintQueueGuests(Canvas canvas, Size size) {
    for (final g in guests) {
      if (g.state != _GuestState.entering && g.state != _GuestState.waiting) {
        continue;
      }
      final pos = _queuePosition(size, g);
      _paintCharacter(canvas, pos, g, idleBob: g.state == _GuestState.waiting);
    }
  }

  /// Walk along a series of waypoints with even time per leg.
  /// Returns position + which leg the character is currently on
  /// (used for scale / character orientation).
  ({Offset pos, int leg, double legT}) _walkPath(
      List<Offset> wp, double progress) {
    final legs = wp.length - 1;
    final lp = (progress * legs).clamp(0.0, legs.toDouble());
    final i = lp.floor().clamp(0, legs - 1);
    final t = (lp - i).clamp(0.0, 1.0);
    return (
      pos: Offset.lerp(wp[i], wp[i + 1], t)!,
      leg: i,
      legT: t,
    );
  }

  void _paintBoardingGuests(Canvas canvas, Size size) {
    for (final g in guests) {
      if (g.state != _GuestState.boarding) continue;
      // 2-leg path: queue front → boarding ramp base → cart top.
      // Leg 1 = walking east along the walkway to the ramp.
      // Leg 2 = walking up the ramp onto the cart.
      final waypoints = [
        _queuePosition(size, g, baseSlot: 0),
        _boardRampBase(size),
        _boardRampTop(size),
      ];
      final res = _walkPath(waypoints, _easeInOut(g.progress));
      // Full size during walkway leg, shrink during ramp leg so they
      // hand off smoothly to the smaller in-cart rider rendering.
      final scale = res.leg == 0 ? 1.0 : (1.0 - res.legT * 0.55);
      _paintCharacter(canvas, res.pos, g, scale: scale);
    }
  }

  void _paintExitingGuests(Canvas canvas, Size size) {
    for (final g in guests) {
      if (g.state != _GuestState.exiting) continue;
      // 2-leg path: cart top → exit ramp base → off-screen east.
      // Leg 1 = walking down the unboarding ramp from the cart.
      // Leg 2 = walking east along the walkway to the exit gate.
      final waypoints = [
        _exitRampTop(size),
        _exitRampBase(size),
        Offset(size.width + 30, size.height * _yQueueBaseline),
      ];
      final res = _walkPath(waypoints, _easeInOut(g.progress));
      // Tiny on the cart, growing to full size by the time they
      // reach the walkway.
      final scale = res.leg == 0 ? (0.45 + res.legT * 0.55) : 1.0;
      _paintCharacter(canvas, res.pos, g, scale: scale);
    }
  }

  Offset _queuePosition(Size size, _Guest g, {int? baseSlot}) {
    // baseSlot lets _paintBoardingGuests anchor the path at slot 0
    // regardless of where the guest currently visually sits.
    final slot = baseSlot ?? g.displaySlot;
    final w = size.width;
    final h = size.height;
    final x = (_xQueueFrontFrac - slot * _xQueueSlotSpacing) * w;
    final baselineY = h * _yQueueBaseline;
    if (g.state == _GuestState.entering) {
      // Walk in from the entrance gate (left edge of walkway), not
      // from a random off-screen point — keeps everyone on the path.
      final from = _entranceGate(size);
      final to = Offset(x, baselineY);
      return Offset.lerp(from, to, _easeInOut(g.progress))!;
    }
    return Offset(x, baselineY);
  }

  /// Chibi character. Bigger head, eye highlights, smile, blush.
  /// No outlines — depth through soft shading bands only.
  /// `scale` lets boarding/exit shrink/grow the figure smoothly so
  /// the size hand-off to/from rider-on-cart drawings reads natural.
  void _paintCharacter(Canvas canvas, Offset feet, _Guest g,
      {bool idleBob = false, double scale = 1.0}) {
    final bob =
        idleBob ? math.sin((ambient + g.bobPhase) * math.pi * 2) * 0.7 : 0.0;
    final cx = feet.dx;
    final cy = feet.dy - bob;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    canvas.translate(-cx, -cy);

    // Soft shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, feet.dy + 1), width: 18, height: 5.5),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    // Legs.
    const legColor = Color(0xFF8E7A6A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 5, cy - 13, 4, 11),
        const Radius.circular(1.5),
      ),
      Paint()..color = legColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 1, cy - 13, 4, 11),
        const Radius.circular(1.5),
      ),
      Paint()..color = legColor,
    );

    // Body — chibi proportions, very rounded top.
    final bodyRect = Rect.fromLTWH(cx - 8, cy - 26, 16, 14);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        bodyRect,
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      ),
      Paint()..color = g.shirt,
    );
    // Shading on right.
    canvas.drawRect(
      Rect.fromLTWH(cx + 4, cy - 26, 4, 14),
      Paint()
        ..color = HSLColor.fromColor(g.shirt)
            .withLightness(
                (HSLColor.fromColor(g.shirt).lightness * 0.83).clamp(0.0, 1.0))
            .toColor(),
    );

    // Arms.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 11, cy - 25, 3.4, 11),
        const Radius.circular(1.5),
      ),
      Paint()..color = g.skin,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 7.6, cy - 25, 3.4, 11),
        const Radius.circular(1.5),
      ),
      Paint()..color = g.skin,
    );

    // Head — bigger (chibi).
    final headCenter = Offset(cx, cy - 33);
    canvas.drawCircle(headCenter, 7.2, Paint()..color = g.skin);

    // Hair — top half + small forelock for character.
    final hair = Path()
      ..addArc(
        Rect.fromCircle(center: headCenter, radius: 7.2),
        math.pi,
        math.pi,
      );
    canvas.drawPath(hair, Paint()..color = g.hair);
    canvas.drawRect(
      Rect.fromLTWH(cx - 7.2, cy - 33, 14.4, 1.8),
      Paint()..color = g.hair,
    );
    // Forelock asymmetric.
    final forelock = Path()
      ..moveTo(cx - 4, cy - 33)
      ..quadraticBezierTo(cx - 1, cy - 30, cx + 1, cy - 32)
      ..lineTo(cx - 2, cy - 33.5)
      ..close();
    canvas.drawPath(forelock, Paint()..color = g.hair);

    // Eyes (with highlight).
    final eye = Paint()..color = const Color(0xFF5A4A40);
    canvas.drawCircle(Offset(cx - 2.2, cy - 32), 1.3, eye);
    canvas.drawCircle(Offset(cx + 2.2, cy - 32), 1.3, eye);
    final eyeHi = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - 1.8, cy - 32.4), 0.45, eyeHi);
    canvas.drawCircle(Offset(cx + 2.6, cy - 32.4), 0.45, eyeHi);

    // Smile.
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - 29), width: 3.8, height: 2.4),
      0.1,
      math.pi - 0.2,
      false,
      Paint()
        ..color = const Color(0xFF6B4F3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round,
    );

    // Blush.
    final cheek = Paint()
      ..color = const Color(0xFFF5C8C0).withValues(alpha: 0.75);
    canvas.drawCircle(Offset(cx - 3.2, cy - 30.5), 1.2, cheek);
    canvas.drawCircle(Offset(cx + 3.2, cy - 30.5), 1.2, cheek);

    canvas.restore();
  }

  // ═══ Foreground signs / ribbon / flowers ═══════════════════════

  void _paintCapacitySign(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final signX = w * 0.10;
    final signY = h * (_yQueueBaseline - 0.10);
    canvas.drawRect(
      Rect.fromLTWH(signX - 0.8, signY, 1.6, 18),
      Paint()..color = const Color(0xFF9A8E80),
    );
    final boardRect = Rect.fromCenter(
        center: Offset(signX, signY - 4), width: 38, height: 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFC8A988),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(signX, signY - 4), width: 32, height: 12),
        const Radius.circular(2.5),
      ),
      Paint()..color = const Color(0xFFFAF0E0),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '$waitingCount/$queueCapacity',
        style: const TextStyle(
          color: Color(0xFF6B4F3A),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(signX - tp.width / 2, signY - 11));
  }

  void _paintQueueRibbon(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ropeY = h * (_yQueueBaseline - 0.04);
    final ropeStart = w * 0.04;
    final ropeEnd = w * (_xQueueFrontFrac - 0.005);
    canvas.drawLine(
      Offset(ropeStart, ropeY),
      Offset(ropeEnd, ropeY),
      Paint()
        ..color = const Color(0xFFE8A4A4).withValues(alpha: 0.85)
        ..strokeWidth = 1.6,
    );
    final post = Paint()..color = const Color(0xFF9A8E80);
    final cap = Paint()..color = const Color(0xFFFAEAD8);
    // Bunting flags hanging below the rope.
    final buntingColors = <Color>[
      const Color(0xFFE8A0A0),
      const Color(0xFFE8D8A8),
      const Color(0xFFA8C7E0),
      const Color(0xFFB8D4B0),
    ];
    for (var x = ropeStart; x <= ropeEnd; x += 28) {
      canvas.drawRect(Rect.fromLTWH(x, ropeY - 1.2, 2, 8), post);
      canvas.drawCircle(Offset(x + 1, ropeY - 1.2), 1.5, cap);
    }
    // Bunting flags between posts.
    var i = 0;
    for (var x = ropeStart + 14; x <= ropeEnd - 8; x += 14) {
      final flag = Path()
        ..moveTo(x - 4, ropeY)
        ..lineTo(x + 4, ropeY)
        ..lineTo(x, ropeY + 5)
        ..close();
      canvas.drawPath(
        flag,
        Paint()..color = buntingColors[i % buntingColors.length],
      );
      i++;
    }
  }

  void _paintExitSign(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ax = w * 0.93;
    final ay = h * (_yQueueBaseline - 0.04);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(ax, ay - 6), width: 1.6, height: 16),
      Paint()..color = const Color(0xFF9A8E80),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ax - 4, ay - 16), width: 26, height: 11),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFB0CBA8),
    );
    final tp2 = TextPainter(
      text: const TextSpan(
        text: '출구',
        style: TextStyle(
          color: Color(0xFF4A4A3A),
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(ax - 4 - tp2.width / 2, ay - 21));
  }

  void _paintForegroundFlowers(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Grass clumps + flower dots scattered on the foreground path edges.
    const positions = <List<double>>[
      [0.05, 0.95],
      [0.11, 0.96],
      [0.85, 0.96],
      [0.92, 0.94],
      [0.46, 0.97],
      [0.63, 0.97],
      [0.30, 0.96],
      [0.74, 0.96],
    ];
    final colors = <Color>[
      const Color(0xFFF5C8D0),
      const Color(0xFFE8D8F0),
      const Color(0xFFFFEAB8),
      const Color(0xFFFAEAD8),
      const Color(0xFFE8A0A0),
    ];
    final rng = math.Random(13);
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      final cx = w * p[0];
      final cy = h * p[1];
      final color = colors[i % colors.length];
      // Grass tuft underneath.
      final tuft = Paint()..color = _grassBlade.withValues(alpha: 0.85);
      for (var k = 0; k < 4; k++) {
        final dx = (rng.nextDouble() - 0.5) * 6;
        canvas.drawLine(
          Offset(cx + dx, cy + 3),
          Offset(cx + dx + (rng.nextDouble() - 0.5) * 1.5, cy - 3),
          tuft..strokeWidth = 1.0,
        );
      }
      // 3 small flowers.
      for (var k = 0; k < 3; k++) {
        final fx = cx + (rng.nextDouble() - 0.5) * 8;
        final fy = cy - rng.nextDouble() * 4;
        for (var s = 0; s < 5; s++) {
          final a = s * 2 * math.pi / 5 - math.pi / 2;
          canvas.drawCircle(
            Offset(fx + math.cos(a) * 1.4, fy + math.sin(a) * 1.4),
            1.1,
            Paint()..color = color,
          );
        }
        canvas.drawCircle(
          Offset(fx, fy),
          0.8,
          Paint()..color = const Color(0xFFFFE7A0),
        );
      }
    }
  }

  // ═══ Petals + fireflies ═══════════════════════════════════════

  void _paintPetals(Canvas canvas, Size size) {
    for (final p in petals) {
      final cx = p.x * size.width + math.sin(p.sway) * 6;
      final cy = p.y * size.height;
      final paint = Paint()..color = p.color.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(cx, cy), p.size, paint);
      // Tiny lighter highlight.
      canvas.drawCircle(
        Offset(cx - 0.4, cy - 0.4),
        p.size * 0.35,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }
  }

  void _paintFireflies(Canvas canvas, Size size) {
    final paint = Paint();
    for (final f in fireflies) {
      final cx = f.baseX * size.width + math.sin(f.phase) * f.amp * size.width;
      final cy =
          f.baseY * size.height + math.cos(f.phase * 0.7) * f.amp * size.height;
      final twinkle = (math.sin(f.twinklePhase) + 1) / 2;
      // Outer glow halo.
      paint.color = _firefly.withValues(alpha: 0.20 + twinkle * 0.20);
      canvas.drawCircle(Offset(cx, cy), 5 + twinkle * 1.5, paint);
      // Core.
      paint.color = _firefly.withValues(alpha: 0.85);
      canvas.drawCircle(Offset(cx, cy), 1.2, paint);
    }
  }

  // ═══ Entrance / exit gates + boarding ramp ════════════════════

  /// Park entrance gate at the far left of the walkway. A small
  /// arched frame in pastel coral with a sage banner reading
  /// "입장" — marks where guests enter the queue from off-screen.
  void _paintEntranceGate(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.05;
    final baseY = h * (_yQueueBaseline + 0.02);

    // Pillars (warm ochre).
    final pillar = Paint()..color = const Color(0xFFE6BD8A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 14, baseY - 30, 5, 30),
        const Radius.circular(2),
      ),
      pillar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 9, baseY - 30, 5, 30),
        const Radius.circular(2),
      ),
      pillar,
    );
    // Banner (soft coral).
    final banner = Rect.fromLTWH(cx - 18, baseY - 36, 36, 11);
    canvas.drawRRect(
      RRect.fromRectAndRadius(banner, const Radius.circular(3)),
      Paint()..color = _stationRoof,
    );
    // Cream stitched bottom edge.
    canvas.drawRect(
      Rect.fromLTWH(banner.left, banner.bottom - 1.5, banner.width, 1.2),
      Paint()..color = const Color(0xFFFAEAD8),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: '입장',
        style: TextStyle(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, baseY - 36));

    // Tiny soft star above.
    canvas.drawCircle(
      Offset(cx, baseY - 41),
      2.3,
      Paint()..color = _stationStar,
    );
    canvas.drawCircle(
      Offset(cx, baseY - 41),
      4.5,
      Paint()..color = _stationStar.withValues(alpha: 0.35),
    );
  }

  /// Park exit gate at the far right of the walkway. Similar shape
  /// but sage palette so it reads distinct from the entrance.
  void _paintExitGate(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.95;
    final baseY = h * (_yQueueBaseline + 0.02);

    final pillar = Paint()..color = const Color(0xFFB6CFA0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 14, baseY - 30, 5, 30),
        const Radius.circular(2),
      ),
      pillar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 9, baseY - 30, 5, 30),
        const Radius.circular(2),
      ),
      pillar,
    );
    final banner = Rect.fromLTWH(cx - 18, baseY - 36, 36, 11);
    canvas.drawRRect(
      RRect.fromRectAndRadius(banner, const Radius.circular(3)),
      Paint()..color = const Color(0xFF98B89A),
    );
    canvas.drawRect(
      Rect.fromLTWH(banner.left, banner.bottom - 1.5, banner.width, 1.2),
      Paint()..color = const Color(0xFFFAEAD8),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: '출구',
        style: TextStyle(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, baseY - 36));
  }

  /// Two visible ramps at the station, matching the multi-leg path
  /// the boarding/exit guests follow. Each ramp is a trapezoidal
  /// stair set with directional arrows so the flow reads at a glance:
  ///   - boarding ramp: under the station, going UP to cart
  ///   - exit ramp: just east of station, going DOWN from cart
  void _paintBoardingRamp(Canvas canvas, Size size) {
    final boardBase = _boardRampBase(size);
    final boardTop = _boardRampTop(size);
    final exitBase = _exitRampBase(size);
    final exitTop = _exitRampTop(size);
    final walkY = size.height * _yQueueBaseline;

    final stairPaint = Paint()
      ..color = const Color(0xFFB39A82).withValues(alpha: 0.7)
      ..strokeWidth = 0.8;

    // Boarding ramp — under the station, diagonal up.
    _drawRampStrip(
      canvas,
      baseLeft: Offset(boardBase.dx - 12, walkY - 1),
      baseRight: Offset(boardBase.dx + 6, walkY - 1),
      topLeft: Offset(boardTop.dx - 8, boardTop.dy + 14),
      topRight: Offset(boardTop.dx + 4, boardTop.dy + 14),
      fill: const Color(0xFFE0C998),
      stairs: stairPaint,
    );
    // Up arrow on the boarding ramp (sage = "go").
    _paintRampArrow(
      canvas,
      Offset(boardBase.dx - 3, walkY - 14),
      true,
      const Color(0xFF98B89A),
    );

    // Exit ramp — just east of station, diagonal down to walkway.
    _drawRampStrip(
      canvas,
      baseLeft: Offset(exitBase.dx - 4, walkY - 1),
      baseRight: Offset(exitBase.dx + 14, walkY - 1),
      topLeft: Offset(exitTop.dx - 4, exitTop.dy + 14),
      topRight: Offset(exitTop.dx + 8, exitTop.dy + 14),
      fill: const Color(0xFFD8C098),
      stairs: stairPaint,
    );
    // Down arrow on the exit ramp (coral = "exit").
    _paintRampArrow(
      canvas,
      Offset(exitBase.dx + 5, walkY - 14),
      false,
      const Color(0xFFE8A4A4),
    );
  }

  void _drawRampStrip(
    Canvas canvas, {
    required Offset baseLeft,
    required Offset baseRight,
    required Offset topLeft,
    required Offset topRight,
    required Color fill,
    required Paint stairs,
  }) {
    final p = Path()
      ..moveTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(topLeft.dx, topLeft.dy)
      ..close();
    canvas.drawPath(p, Paint()..color = fill);
    for (var k = 1; k < 5; k++) {
      final t = k / 5.0;
      final lx = baseLeft.dx + t * (topLeft.dx - baseLeft.dx);
      final ly = baseLeft.dy + t * (topLeft.dy - baseLeft.dy);
      final rx = baseRight.dx + t * (topRight.dx - baseRight.dx);
      final ry = baseRight.dy + t * (topRight.dy - baseRight.dy);
      canvas.drawLine(Offset(lx, ly), Offset(rx, ry), stairs);
    }
  }

  void _paintRampArrow(Canvas canvas, Offset c, bool up, Color color) {
    final p = Path();
    if (up) {
      p
        ..moveTo(c.dx, c.dy - 3)
        ..lineTo(c.dx - 3, c.dy + 1)
        ..lineTo(c.dx - 1, c.dy + 1)
        ..lineTo(c.dx - 1, c.dy + 3)
        ..lineTo(c.dx + 1, c.dy + 3)
        ..lineTo(c.dx + 1, c.dy + 1)
        ..lineTo(c.dx + 3, c.dy + 1)
        ..close();
    } else {
      p
        ..moveTo(c.dx, c.dy + 3)
        ..lineTo(c.dx - 3, c.dy - 1)
        ..lineTo(c.dx - 1, c.dy - 1)
        ..lineTo(c.dx - 1, c.dy - 3)
        ..lineTo(c.dx + 1, c.dy - 3)
        ..lineTo(c.dx + 1, c.dy - 1)
        ..lineTo(c.dx + 3, c.dy - 1)
        ..close();
    }
    canvas.drawPath(p, Paint()..color = color.withValues(alpha: 0.85));
  }

  // ═══ Vignette ══════════════════════════════════════════════════

  void _paintVignette(Canvas canvas, Size size) {
    final shader = ui.Gradient.radial(
      Offset(size.width / 2, size.height * 0.55),
      math.max(size.width, size.height) * 0.7,
      [
        Colors.transparent,
        const Color(0xFF6B4F3A).withValues(alpha: 0.0),
        const Color(0xFF6B4F3A).withValues(alpha: 0.20),
      ],
      [0.0, 0.55, 1.0],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ParkPainter old) {
    return old.cycle != cycle ||
        old.boosted != boosted ||
        old.stage != stage ||
        old.ambient != ambient ||
        old.guests != guests ||
        old.petals != petals ||
        old.fireflies != fireflies ||
        old.waitingCount != waitingCount;
  }
}
