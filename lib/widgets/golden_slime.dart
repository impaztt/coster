import 'package:flutter/material.dart';

import '../core/number_format.dart';
import '../providers/game_provider.dart';

/// A golden VIP guest that appears every [slimeSpawnEvery] taps. Each tap
/// advances the response, and completing it fires [onDefeat] so the home
/// screen can grant the bonus gold.
class GoldenSlime extends StatefulWidget {
  /// Estimated payout shown above the response bar.
  final double previewReward;
  final VoidCallback onDefeat;
  final VoidCallback onTimeout;
  const GoldenSlime({
    super.key,
    required this.previewReward,
    required this.onDefeat,
    required this.onTimeout,
  });

  @override
  State<GoldenSlime> createState() => _GoldenSlimeState();
}

class _GoldenSlimeState extends State<GoldenSlime>
    with TickerProviderStateMixin {
  late final AnimationController _lifeC;
  late final AnimationController _pulseC;
  late final AnimationController _hitC;
  late final AnimationController _deathC;
  int _hp = slimeMaxHp;
  bool _dead = false;

  @override
  void initState() {
    super.initState();
    _lifeC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: slimeLifetimeMs),
    )..forward().whenComplete(() {
        if (mounted && !_dead) widget.onTimeout();
      });
    _pulseC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _hitC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _deathC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void dispose() {
    _lifeC.dispose();
    _pulseC.dispose();
    _hitC.dispose();
    _deathC.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_dead) return;
    setState(() => _hp -= 1);
    _hitC.forward(from: 0);
    if (_hp <= 0) {
      _dead = true;
      _lifeC.stop();
      _deathC.forward();
      widget.onDefeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_lifeC, _pulseC, _hitC, _deathC]),
        builder: (context, _) {
          // Fade in fast, hold, fade out in the last 20% of life.
          final life = _lifeC.value;
          final lifeOpacity = life < 0.1
              ? life / 0.1
              : life > 0.8
                  ? (1.0 - (life - 0.8) / 0.2).clamp(0.0, 1.0)
                  : 1.0;
          // Once dead the death anim drives opacity (fade out + pop).
          final deathT = _deathC.value;
          final opacity = _dead
              ? (1.0 - deathT).clamp(0.0, 1.0)
              : lifeOpacity.clamp(0.0, 1.0);
          final pulse = 1.0 + 0.12 * _pulseC.value;
          final hitShake = (1.0 - _hitC.value) * (_hitC.value > 0 ? 4 : 0);
          final deathScale = _dead ? (1.0 + 0.6 * deathT) : 1.0;
          // Brief white flash when hit so the tap registers visually.
          final flash = (1.0 - _hitC.value).clamp(0.0, 1.0) < 0.5
              ? (0.5 - (1.0 - _hitC.value)).clamp(0.0, 0.5) * 1.4
              : 0.0;
          final responseRatio =
              ((slimeMaxHp - _hp) / slimeMaxHp).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: SizedBox(
              width: 88,
              height: 108,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _RewardChip(reward: widget.previewReward),
                  ),
                  Positioned(
                    top: 18,
                    left: 6,
                    right: 6,
                    child: _HpBar(
                      ratio: responseRatio,
                      handled: slimeMaxHp - _hp,
                      max: slimeMaxHp,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Transform.translate(
                      offset: Offset(hitShake, 0),
                      child: Transform.scale(
                        scale: pulse * deathScale,
                        child: _VipGuestAvatar(flash: flash),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HpBar extends StatelessWidget {
  final double ratio;
  final int handled;
  final int max;
  const _HpBar({
    required this.ratio,
    required this.handled,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: Colors.black.withValues(alpha: 0.35)),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFF176), Color(0xFFFFB300)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '응대 $handled / $max',
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VipGuestAvatar extends StatelessWidget {
  final double flash;
  const _VipGuestAvatar({required this.flash});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 54,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF4A148C), Color(0xFF1A237E)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.48),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 7,
                    child: Container(
                      width: 24,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD54F),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 9,
                    child: Icon(
                      Icons.workspace_premium,
                      color: Color(0xFFFFD54F),
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 13,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFB74D)],
                ),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 14,
                    child: Container(
                      width: 29,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF212121),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 17,
                    left: 9,
                    child: Container(width: 7, height: 2, color: Colors.white),
                  ),
                  Positioned(
                    top: 17,
                    right: 9,
                    child: Container(width: 7, height: 2, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 8,
                    child: Container(
                      width: 13,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8D4A00),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CrownPoint(height: 13),
                    _CrownPoint(height: 18),
                    _CrownPoint(height: 13),
                  ],
                ),
                Container(
                  width: 34,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD54F),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFFF8F00)),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            bottom: 17,
            child: Container(
              width: 21,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFFB300)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'VIP',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF8D6E00),
                ),
              ),
            ),
          ),
          if (flash > 0)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: flash),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CrownPoint extends StatelessWidget {
  final double height;
  const _CrownPoint({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: const BoxDecoration(
        color: Color(0xFFFFD54F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  final double reward;
  const _RewardChip({required this.reward});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFB26A00).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'VIP +${NumberFormatter.format(reward)}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
