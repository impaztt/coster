import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../data/feature_unlocks.dart';
import '../models/booster.dart';
import '../providers/game_provider.dart';
import '../services/audio_service.dart';
import '../widgets/booster_shop_dialog.dart';
import '../widgets/gold_exchange_dialog.dart';
import '../widgets/main_sword_enhance_dialog.dart';
import '../widgets/main_sword_widget.dart';
import '../widgets/dps_display.dart';
import '../widgets/floating_number.dart';
import '../widgets/feature_unlock_guide.dart';
import '../widgets/golden_slime.dart';
import '../widgets/gold_display.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final List<FloatingNumberData> _floats = [];
  final List<_SlimeSpawn> _slimes = [];
  int _nextId = 0;
  int _nextSlimeId = 0;
  final _rng = Random();

  void _handleTap(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPos);
    final result = ref.read(gameProvider.notifier).tapWithFeedback();
    final state = ref.read(gameProvider);
    if (state.haptic) {
      if (state.reduceTapHaptics) {
        if (result.isCrit) HapticFeedback.mediumImpact();
      } else if (result.isCrit) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
    if (state.sound) AudioService.instance.playTap();
    setState(() {
      _floats.add(FloatingNumberData(
        id: _nextId++,
        origin: local,
        amount: result.amount,
        isCrit: result.isCrit,
      ));
      if (result.slimeSpawned) _spawnSlime(box.size);
    });
  }

  void _removeFloat(int id) {
    if (!mounted) return;
    setState(() => _floats.removeWhere((f) => f.id == id));
  }

  void _spawnSlime(Size bounds) {
    final id = _nextSlimeId++;
    // Keep it clear of the top bar and the sword center by biasing the
    // random position toward the horizontal edges and avoiding the middle
    // band where the main sword sits.
    final w = bounds.width;
    final h = bounds.height;
    final leftSide = _rng.nextBool();
    final dx = leftSide
        ? 16.0 + _rng.nextDouble() * (w * 0.25)
        : w * 0.6 + _rng.nextDouble() * (w * 0.25) - 16.0;
    final dy = h * 0.25 + _rng.nextDouble() * (h * 0.45);
    _slimes.add(_SlimeSpawn(id: id, offset: Offset(dx, dy)));
  }

  void _defeatSlime(int id, Offset slimeOffset) {
    if (!mounted) return;
    final reward = ref.read(gameProvider.notifier).defeatGoldenSlime();
    if (ref.read(gameProvider).haptic) HapticFeedback.heavyImpact();
    setState(() {
      _slimes.removeWhere((s) => s.id == id);
      // Pop a big floating number where the slime was so the reward feels
      // grounded in the actual kill, not a phantom number from elsewhere.
      _floats.add(FloatingNumberData(
        id: _nextId++,
        origin: slimeOffset + const Offset(40, 30),
        amount: reward,
        isCrit: true,
      ));
    });
  }

  void _slimeTimedOut(int id) {
    if (!mounted) return;
    setState(() => _slimes.removeWhere((s) => s.id == id));
  }

  void _openBoosterShop() {
    showDialog<void>(
      context: context,
      builder: (_) => const BoosterShopDialog(),
    );
  }

  void _openGoldExchange() {
    showDialog<void>(
      context: context,
      builder: (_) => const GoldExchangeDialog(),
    );
  }

  void _openMainSwordEnhance() {
    showDialog<void>(
      context: context,
      builder: (_) => const MainSwordEnhanceDialog(),
    );
  }

  void _openUnlockRoadmap() {
    final game = ref.read(gameProvider);
    showFeatureUnlockRoadmapSheet(
      context,
      game: game,
      title: '홈 - 기능 로드맵',
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final slimeActive = _slimes.isNotEmpty;
    final lockedFeatures = lockedFeatureDefs(game);
    final nextLocked = nextRecommendedLockedFeature(game);

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(child: GoldDisplay(amount: game.gold)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SlimeProgressBar(
                  remaining: game.tapsUntilSlime,
                  total: slimeSpawnEvery,
                  active: slimeActive,
                  reward: notifier.slimePreviewReward,
                ),
              ),
              const SizedBox(height: 10),
              DpsDisplay(dps: game.dps),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 240.0;
                      final size = height.clamp(128.0, 240.0).toDouble();
                      return MainSwordWidget(
                        onTap: _handleTap,
                        stage: game.mainSwordStage,
                        size: size,
                      );
                    },
                  ),
                ),
              ),
              if (lockedFeatures.isNotEmpty && nextLocked != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _LockedFeaturePeekCard(
                    lockedCount: lockedFeatures.length,
                    def: nextLocked,
                    progress: nextLocked.progress(game),
                    onTap: _openUnlockRoadmap,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _CompactBattleStatusPanel(
                  combo: game.combo,
                  tapPower: game.tapPower,
                  maxIdleReward: game.dps * offlineMaxSeconds,
                  idleHours: offlineMaxHours,
                  prestigeMultiplier: game.prestigeMultiplier,
                  collectionFraction: notifier.collectionBonusFraction,
                  boosters: game.activeBoosters,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _HomeActionBar(
                  boosterUnlocked:
                      game.isFeatureUnlocked(FeatureUnlocks.boosterShop),
                  exchangeUnlocked:
                      game.isFeatureUnlocked(FeatureUnlocks.goldExchange),
                  stage: game.mainSwordStage,
                  onBooster: _openBoosterShop,
                  onExchange: _openGoldExchange,
                  onEnhance: _openMainSwordEnhance,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
          FloatingNumberLayer(items: _floats, onDone: _removeFloat),
          for (final slime in _slimes)
            Positioned(
              left: slime.offset.dx,
              top: slime.offset.dy,
              child: GoldenSlime(
                previewReward: notifier.slimePreviewReward,
                onDefeat: () => _defeatSlime(slime.id, slime.offset),
                onTimeout: () => _slimeTimedOut(slime.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SlimeSpawn {
  final int id;
  final Offset offset;
  const _SlimeSpawn({required this.id, required this.offset});
}

class _HomeActionBar extends StatelessWidget {
  final bool boosterUnlocked;
  final bool exchangeUnlocked;
  final int stage;
  final VoidCallback onBooster;
  final VoidCallback onExchange;
  final VoidCallback onEnhance;

  const _HomeActionBar({
    required this.boosterUnlocked,
    required this.exchangeUnlocked,
    required this.stage,
    required this.onBooster,
    required this.onExchange,
    required this.onEnhance,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HomeActionButton(
            icon: Icons.auto_fix_high,
            label: '강화 +$stage',
            color: const Color(0xFF7C4DFF),
            onTap: onEnhance,
          ),
        ),
        if (boosterUnlocked) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _HomeActionButton(
              icon: Icons.bolt,
              label: '부스터',
              color: AppColors.deepCoral,
              onTap: onBooster,
            ),
          ),
        ],
        if (exchangeUnlocked) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _HomeActionButton(
              icon: Icons.currency_exchange,
              label: '환전',
              color: const Color(0xFFFFB300),
              onTap: onExchange,
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HomeActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedFeaturePeekCard extends StatelessWidget {
  final int lockedCount;
  final FeatureUnlockDef def;
  final FeatureUnlockProgress progress;
  final VoidCallback onTap;

  const _LockedFeaturePeekCard({
    required this.lockedCount,
    required this.def,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: def.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(def.icon, size: 14, color: def.color),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '잠김 기능 $lockedCount개',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '다음 추천: ${def.label} · ${progress.progressText} (${progress.percentText})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.62),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 5,
                  backgroundColor: Colors.black12,
                  valueColor: AlwaysStoppedAnimation(def.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactBattleStatusPanel extends StatelessWidget {
  final int combo;
  final double tapPower;
  final double maxIdleReward;
  final int idleHours;
  final double prestigeMultiplier;
  final double collectionFraction;
  final List<Booster> boosters;

  const _CompactBattleStatusPanel({
    required this.combo,
    required this.tapPower,
    required this.maxIdleReward,
    required this.idleHours,
    required this.prestigeMultiplier,
    required this.collectionFraction,
    required this.boosters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final comboPct = (combo * comboBonusPerStack).clamp(0.0, 0.5) * 100;
    final permanentPct = ((prestigeMultiplier - 1) * 100).clamp(0.0, 9999999.0);
    final collectionPct = (collectionFraction * 100).clamp(0.0, 9999999.0);
    final now = DateTime.now();
    final activeBoosters = boosters.where((b) => b.isActive(now)).toList();
    Duration minRemaining = Duration.zero;
    double strongestBoost = 1.0;
    if (activeBoosters.isNotEmpty) {
      minRemaining = activeBoosters
          .map((b) => b.remaining(now))
          .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      strongestBoost = activeBoosters
          .map((b) => b.multiplier)
          .fold<double>(1.0, (a, b) => a > b ? a : b);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceAlt.withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CompactBattleMetric(
                    icon: Icons.touch_app,
                    label: '탭',
                    value: '+${NumberFormatter.formatPrecise(tapPower)}',
                    color: const Color(0xFF8D6E00),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CompactBattleMetric(
                    icon: Icons.nightlight_round,
                    label: '방치 ${idleHours}h',
                    value: '+${NumberFormatter.format(maxIdleReward)}',
                    color: const Color(0xFF5E35B1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _CompactBattleMetric(
                    icon: Icons.auto_awesome,
                    label: '영구',
                    value: '+${permanentPct.toStringAsFixed(0)}%',
                    color: const Color(0xFF00695C),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CompactBattleMetric(
                    icon: Icons.collections_bookmark,
                    label: '수집',
                    value:
                        '+${collectionPct.toStringAsFixed(collectionFraction >= 1 ? 0 : 1)}%',
                    color: const Color(0xFF6A1B9A),
                  ),
                ),
              ],
            ),
            if (combo > 1 || activeBoosters.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (combo > 1)
                      _CompactEffectChip(
                        icon: Icons.local_fire_department,
                        label: '콤보 x$combo · +${comboPct.toStringAsFixed(0)}%',
                        color: AppColors.deepCoral,
                      ),
                    if (activeBoosters.isNotEmpty)
                      _CompactEffectChip(
                        icon: Icons.bolt,
                        label:
                            '부스터 ${activeBoosters.length}개 · x${strongestBoost.toStringAsFixed(strongestBoost % 1 == 0 ? 0 : 1)} · ${_fmtDuration(minRemaining)}',
                        color: AppColors.deepCoral,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final totalSec = d.inSeconds.clamp(0, 1 << 31);
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _CompactBattleMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _CompactBattleMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color.withValues(alpha: 0.82),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactEffectChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CompactEffectChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visible-from-anywhere progress bar for the next slime spawn. Replaces the
/// old text-only "슬라임까지 N회 터치" hint. While a slime is on screen, the
/// bar switches to an "출현 중!" call-to-action so the player knows it's the
/// active state, not a stuck progress meter.
class _SlimeProgressBar extends StatelessWidget {
  final int remaining;
  final int total;
  final bool active;
  final double reward;
  const _SlimeProgressBar({
    required this.remaining,
    required this.total,
    required this.active,
    required this.reward,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = active ? 1.0 : ((total - remaining) / total).clamp(0.0, 1.0);
    final accent = active ? const Color(0xFFE53935) : const Color(0xFFFFB300);
    final title = active ? '슬라임 출현' : '다음 슬라임';
    final label = active
        ? '처치 보상 +${NumberFormatter.format(reward)}'
        : '$remaining회 터치 후 출현 · 보상 +${NumberFormatter.format(reward)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Icon(Icons.bubble_chart, color: accent, size: 18),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: accent.computeLuminance() < 0.5
                            ? accent
                            : const Color(0xFF8D6E00),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black.withValues(alpha: 0.58),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
