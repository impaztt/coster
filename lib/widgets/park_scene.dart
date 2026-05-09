import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/game_provider.dart';

/// Home-tab scene rendered by Flame. Replaces the legacy giant-coaster
/// CustomPainter visual. Shows a tiny park diorama: a coaster track, a
/// cart that sweeps left↔right driven by [GameState.cycleProgress], a
/// ticket booth, and a small queue of guests.
///
/// This is scaffold-quality: shapes are colored primitives. Kenney
/// sprites land in task #10 — components here are factored so the
/// renderer for each piece can be swapped out independently.
class ParkSceneWidget extends ConsumerStatefulWidget {
  final void Function(Offset globalPosition) onTap;
  final double size;

  const ParkSceneWidget({
    super.key,
    required this.onTap,
    required this.size,
  });

  @override
  ConsumerState<ParkSceneWidget> createState() => _ParkSceneWidgetState();
}

class _ParkSceneWidgetState extends ConsumerState<ParkSceneWidget> {
  late final ParkScene _scene;

  @override
  void initState() {
    super.initState();
    _scene = ParkScene();
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    _scene.setExternalState(
      cycleProgress: game.cycleProgress,
      boostGauge: game.boostGauge,
      stage: game.mainCoasterStage,
    );
    return GestureDetector(
      // Wrap Flame in our own gesture detector so the home_screen still
      // gets a globalPosition for floating-number popups, exactly like
      // it did with the old MainCoasterWidget. Flame's built-in tap
      // events would force us to translate coordinate systems instead.
      onTapDown: (d) => widget.onTap(d.globalPosition),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: GameWidget(game: _scene),
      ),
    );
  }
}

class ParkScene extends FlameGame {
  double _cycleProgress = 0;
  double _boostGauge = 0;
  // Stage placeholder — stays unused until the visual evolution lands;
  // kept here so the wiring is in place for incremental upgrades.
  // ignore: unused_field
  int _stage = 0;

  late final _TrackComponent _track;
  late final _TrainComponent _train;
  late final _BoothComponent _booth;
  late final _QueueComponent _queue;

  void setExternalState({
    required double cycleProgress,
    required double boostGauge,
    required int stage,
  }) {
    _cycleProgress = cycleProgress;
    _boostGauge = boostGauge;
    _stage = stage;
  }

  @override
  Color backgroundColor() => const Color(0xFFE0F7FA);

  @override
  Future<void> onLoad() async {
    _track = _TrackComponent();
    _train = _TrainComponent();
    _booth = _BoothComponent();
    _queue = _QueueComponent();
    addAll([_track, _booth, _queue, _train]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _track.boosted = _boostGauge > 0;
    _train.position = _trainPositionFor(_cycleProgress);
  }

  /// Stage 0 = a humble back-and-forth shuttle along a horizontal track.
  /// 0..0.5 sweeps left→right, 0.5..1 sweeps back. Higher stages will
  /// route along richer paths.
  Vector2 _trainPositionFor(double t) {
    final w = size.x;
    final h = size.y;
    final left = w * 0.18;
    final right = w * 0.82;
    final y = h * 0.62;
    final eased = t < 0.5 ? t * 2 : (1 - t) * 2;
    final x = left + (right - left) * eased;
    return Vector2(x, y);
  }
}

class _TrackComponent extends Component with HasGameReference<ParkScene> {
  bool boosted = false;

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    final left = w * 0.15;
    final right = w * 0.85;
    final y = h * 0.62;

    // Sub-rail (light track underneath).
    canvas.drawLine(
      Offset(left, y + 6),
      Offset(right, y + 6),
      Paint()
        ..color = const Color(0xFFB2DFDB)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    // Main rail. Boost tints it warm so the player gets an unmistakable
    // "speed up engaged" cue without needing extra HUD chrome.
    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = boosted ? const Color(0xFFFF8A65) : const Color(0xFF26A69A)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    // Crossties (sleepers).
    final tiePaint = Paint()..color = const Color(0xFF8D6E63);
    const tieCount = 8;
    for (var i = 0; i <= tieCount; i++) {
      final tx = left + (right - left) * (i / tieCount);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(tx, y + 14), width: 6, height: 4),
        tiePaint,
      );
    }
  }
}

class _TrainComponent extends PositionComponent {
  @override
  void render(Canvas canvas) {
    // Single car for the stage-0 placeholder — a rounded red box with
    // a porthole to suggest a cabin. Will be a sprite stack later.
    final body = Rect.fromCenter(
      center: Offset.zero,
      width: 36,
      height: 22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(6)),
      Paint()..color = const Color(0xFFE53935),
    );
    canvas.drawCircle(
      const Offset(-6, -2),
      4,
      Paint()..color = const Color(0xFFFFEE58),
    );
    // Wheels.
    canvas.drawCircle(
      const Offset(-10, 12),
      4,
      Paint()..color = const Color(0xFF424242),
    );
    canvas.drawCircle(
      const Offset(10, 12),
      4,
      Paint()..color = const Color(0xFF424242),
    );
  }
}

class _BoothComponent extends Component with HasGameReference<ParkScene> {
  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    final boothCenter = Offset(w * 0.18, h * 0.82);
    // Booth body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: boothCenter, width: 40, height: 30),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFFFB74D),
    );
    // Roof.
    final roofPath = Path()
      ..moveTo(boothCenter.dx - 24, boothCenter.dy - 15)
      ..lineTo(boothCenter.dx + 24, boothCenter.dy - 15)
      ..lineTo(boothCenter.dx, boothCenter.dy - 28)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()..color = const Color(0xFFE57373),
    );
    // Window.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: boothCenter.translate(0, -2), width: 18, height: 12),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF81D4FA),
    );
  }
}

class _QueueComponent extends Component with HasGameReference<ParkScene> {
  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    // A short row of guests waiting next to the booth. Stage 0 is a
    // sleepy park — five tiny figures is enough to read.
    const palette = <Color>[
      Color(0xFFEF5350),
      Color(0xFF42A5F5),
      Color(0xFFAB47BC),
      Color(0xFF66BB6A),
      Color(0xFFFFCA28),
    ];
    final baseX = w * 0.30;
    final y = h * 0.85;
    for (var i = 0; i < palette.length; i++) {
      final cx = baseX + i * 14.0;
      // Body.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, y), width: 8, height: 14),
          const Radius.circular(2),
        ),
        Paint()..color = palette[i],
      );
      // Head.
      canvas.drawCircle(
        Offset(cx, y - 11),
        4,
        Paint()..color = const Color(0xFFFFCC80),
      );
    }
  }
}
