import 'package:flutter/material.dart';

import '../core/number_format.dart';
import '../providers/game_provider.dart';

/// A golden slime that appears every [slimeSpawnEvery] taps. Each tap on the
/// slime deals 1 damage; landing the killing blow fires [onDefeat] which the
/// home screen uses to grant gold (≈ tapPower × [slimeRewardTaps]). If the
/// player can't finish it within [slimeLifetimeMs], it escapes via
/// [onTimeout] with no reward.
class GoldenSlime extends StatefulWidget {
  /// Estimated payout (current tapPower × slimeRewardTaps) — shown above the
  /// HP bar so the player can see what landing the kill is worth right now.
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
          final hpRatio = (_hp / slimeMaxHp).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: SizedBox(
              width: 80,
              height: 96,
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
                    child: _HpBar(ratio: hpRatio, hp: _hp, max: slimeMaxHp),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Transform.translate(
                      offset: Offset(hitShake, 0),
                      child: Transform.scale(
                        scale: pulse * deathScale,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFFFF176), Color(0xFFFFB300)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.55),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.monetization_on,
                                  color: Color(0xFF7A4F00), size: 32),
                              if (flash > 0)
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white
                                        .withValues(alpha: flash),
                                  ),
                                ),
                            ],
                          ),
                        ),
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
  final int hp;
  final int max;
  const _HpBar({required this.ratio, required this.hp, required this.max});

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
                        colors: [Color(0xFFFF8A65), Color(0xFFE53935)],
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
          '$hp / $max',
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
          '+${NumberFormatter.format(reward)}',
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
