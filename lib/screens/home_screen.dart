import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import 'quest_screen.dart';
import '../core/theme.dart';
import '../data/feature_unlocks.dart';
import '../data/skill_catalog.dart';
import '../models/booster.dart';
import '../models/skill.dart';
import '../providers/game_provider.dart';
import '../services/audio_service.dart';
import '../widgets/booster_shop_dialog.dart';
import '../widgets/debug_multiplier_sheet.dart';
import '../widgets/gold_exchange_dialog.dart';
import '../widgets/main_coaster_enhance_dialog.dart';
import '../widgets/park_scene_fullscreen.dart';
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
  // When false, the locked-feature peek + status panel + action bar
  // are hidden behind a small toggle bar so the park scene takes
  // the full middle area. Defaults to false (start with the park
  // visible) — the user pings the toggle to bring HUD back.
  bool _bottomExpanded = false;
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
    // Keep it clear of the top bar and the coaster center by biasing the
    // random position toward the horizontal edges and avoiding the middle
    // band where the main coaster sits.
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
      // Pop a big floating number where the VIP guest was so the reward feels
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

  void _openMainCoasterEnhance() {
    showDialog<void>(
      context: context,
      builder: (_) => const MainCoasterEnhanceDialog(),
    );
  }

  void _openRevenueDetails() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final game = ref.watch(gameProvider);
          final notifier = ref.read(gameProvider.notifier);
          return _RevenueDetailSheet(game: game, notifier: notifier);
        },
      ),
    );
  }

  void _handleSkillTap(SkillId id) {
    final notifier = ref.read(gameProvider.notifier);
    final game = ref.read(gameProvider);
    final tokens = game.skillTokens[id.id] ?? 0;
    final onCooldown = notifier.skillCooldownEndsAt(id) != null;
    final result = (tokens > 0 && onCooldown)
        ? notifier.useSkillWithToken(id)
        : notifier.useSkill(id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(result.message),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _openQuests() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const QuestScreen()),
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
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () =>
                            DebugMultiplierSheet.show(context),
                        child: GoldDisplay(amount: game.gold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RevenueDetailsButton(onTap: _openRevenueDetails),
                    const SizedBox(width: 6),
                    _QuestButton(
                      claimable: game.dailyMissions
                              .where((m) => m.done && !m.claimed)
                              .length +
                          game.weeklyMissions
                              .where((m) => m.done && !m.claimed)
                              .length,
                      onTap: _openQuests,
                    ),
                  ],
                ),
              ),
              if (game.rideTimeRemainingSec > 0) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RideTimeBadge(
                    remainingSec: game.rideTimeRemainingSec,
                    mult: game.rideTimeMult,
                  ),
                ),
              ],
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
              // Park scene fills the available middle area between
              // the top HUD and the bottom controls. Bounded so its
              // painter never overflows behind the locked-feature
              // card / status panel / action bar.
              Expanded(
                child: ParkSceneFullscreen(onTap: _handleTap),
              ),
              // Toggle bar — always visible. Tap to expand/collapse
              // the bottom HUD stack so the park scene can grow into
              // the freed space.
              _BottomHudToggle(
                expanded: _bottomExpanded,
                onTap: () => setState(() => _bottomExpanded = !_bottomExpanded),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _bottomExpanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (lockedFeatures.isNotEmpty &&
                              nextLocked != null) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
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
                              collectionFraction:
                                  notifier.collectionBonusFraction,
                              boosters: game.activeBoosters,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _SkillBar(
                              skillReadyAt: game.skillReadyAt,
                              skillTokens: game.skillTokens,
                              onTap: _handleSkillTap,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _HomeActionBar(
                              boosterUnlocked: game.isFeatureUnlocked(
                                  FeatureUnlocks.boosterShop),
                              exchangeUnlocked: game.isFeatureUnlocked(
                                  FeatureUnlocks.goldExchange),
                              stage: game.mainCoasterStage,
                              onBooster: _openBoosterShop,
                              onExchange: _openGoldExchange,
                              onEnhance: _openMainCoasterEnhance,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      )
                    : const SizedBox(height: 6),
              ),
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

/// §3.7 v2 — three-skill home HUD row. Each tile shows the skill icon, a
/// cooldown overlay (sweeping radial), and an instant-token badge (0..3).
/// Tap fires the skill via token when available + on cooldown, otherwise
/// via the natural cooldown path. Driven by a 1Hz timer so the cooldown
/// sweep stays smooth between game-state emits.
class _SkillBar extends StatefulWidget {
  final Map<String, DateTime> skillReadyAt;
  final Map<String, int> skillTokens;
  final void Function(SkillId) onTap;

  const _SkillBar({
    required this.skillReadyAt,
    required this.skillTokens,
    required this.onTap,
  });

  @override
  State<_SkillBar> createState() => _SkillBarState();
}

class _SkillBarState extends State<_SkillBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        for (var i = 0; i < skillCatalog.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SkillTile(
              def: skillCatalog[i],
              now: now,
              readyAt: widget.skillReadyAt[skillCatalog[i].id.id],
              tokens: widget.skillTokens[skillCatalog[i].id.id] ?? 0,
              onTap: () => widget.onTap(skillCatalog[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _SkillTile extends StatelessWidget {
  final SkillDef def;
  final DateTime now;
  final DateTime? readyAt;
  final int tokens;
  final VoidCallback onTap;

  const _SkillTile({
    required this.def,
    required this.now,
    required this.readyAt,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cdRemaining = readyAt == null
        ? Duration.zero
        : readyAt!.isAfter(now) ? readyAt!.difference(now) : Duration.zero;
    final onCooldown = cdRemaining > Duration.zero;
    final ratio = onCooldown
        ? (1.0 -
            (cdRemaining.inMilliseconds / def.cooldown.inMilliseconds))
            .clamp(0.0, 1.0)
        : 1.0;
    final canTokenBurst = onCooldown && tokens > 0;
    final tappable = !onCooldown || canTokenBurst;

    return Material(
      color: tappable ? def.color : def.color.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      elevation: tappable ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tappable ? onTap : null,
        child: SizedBox(
          height: 52,
          child: Stack(
            children: [
              if (onCooldown)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: Colors.transparent,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.18)),
                      minHeight: 52,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(def.icon, size: 20, color: Colors.white),
                    const SizedBox(height: 2),
                    Text(
                      onCooldown
                          ? _fmtCooldown(cdRemaining)
                          : '준비',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              // Token badge — top-right corner. Always visible so players
              // see "0/3" early, building awareness of the system.
              Positioned(
                top: 3,
                right: 4,
                child: _TokenBadge(
                  tokens: tokens,
                  active: canTokenBurst,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtCooldown(Duration d) {
    if (d.inMinutes >= 1) {
      return '${d.inMinutes}분';
    }
    return '${d.inSeconds}초';
  }
}

class _TokenBadge extends StatelessWidget {
  final int tokens;
  final bool active;
  const _TokenBadge({required this.tokens, required this.active});

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.white : Colors.white.withValues(alpha: 0.30);
    final fg = active ? Colors.black87 : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '⚡$tokens',
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
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
            label: '업그레이드 $stage',
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

/// §3.2 Ride Time visual badge — pulses softly so the player can see when
/// the DPS burst is active. Pure presentation, reads state from parent.
class _RideTimeBadge extends StatelessWidget {
  final int remainingSec;
  final double mult;

  const _RideTimeBadge({required this.remainingSec, required this.mult});

  @override
  Widget build(BuildContext context) {
    final pct = (mult - 1.0) * 100;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.deepCoral.withValues(alpha: 0.95),
            AppColors.coral.withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha: 0.40),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 18, color: Colors.white),
          const SizedBox(width: 6),
          const Text(
            'RIDE TIME',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '+${pct.toStringAsFixed(0)}% DPS',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${remainingSec}s',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// §3.3 — Quest entry button on the top HUD. Shows a small dot when any
/// daily/weekly mission is ready to claim, mirroring the redeem-all CTA
/// inside QuestScreen.
class _QuestButton extends StatelessWidget {
  final int claimable;
  final VoidCallback onTap;

  const _QuestButton({required this.claimable, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '퀘스트',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fact_check,
                    size: 18, color: Color(0xFF2E7D32)),
                const SizedBox(width: 5),
                const Text(
                  '퀘스트',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                if (claimable > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '$claimable',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RevenueDetailsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RevenueDetailsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '수익 상세',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.query_stats, size: 18, color: AppColors.deepCoral),
                SizedBox(width: 5),
                Text(
                  '수익',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepCoral,
                  ),
                ),
              ],
            ),
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
                    label: '탭 수익',
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

class _RevenueDetailSheet extends StatelessWidget {
  final GameState game;
  final GameNotifier notifier;

  const _RevenueDetailSheet({required this.game, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final activeBoosters =
        game.activeBoosters.where((b) => b.isActive(now)).toList();
    final comboPct = (game.combo * comboBonusPerStack).clamp(0.0, 0.5);
    final permanentPct = (game.prestigeMultiplier - 1).clamp(0.0, 9999999.0);
    final collectionPct = notifier.collectionBonusFraction;
    final mainCoasterPct = notifier.mainCoasterRevenueBonusFraction;
    final pendingDividend = notifier.totalPendingDividend;
    final holdingsValue = notifier.totalHoldingsValue;
    final strongestBoost = activeBoosters.isEmpty
        ? 1.0
        : activeBoosters
            .map((b) => b.multiplier)
            .fold<double>(1.0, (a, b) => a > b ? a : b);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.query_stats, color: AppColors.deepCoral),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '수익 상세',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RevenueSection(
                title: '현재 수익',
                children: [
                  _RevenueMetric(
                    icon: Icons.touch_app,
                    label: '탭당 골드',
                    value: '+${NumberFormatter.formatPrecise(game.tapPower)}',
                    color: const Color(0xFF8D6E00),
                  ),
                  _RevenueMetric(
                    icon: Icons.bolt,
                    label: '초당 수익',
                    value: '${NumberFormatter.formatPrecise(game.dps)} /s',
                    color: const Color(0xFF00838F),
                  ),
                  _RevenueMetric(
                    icon: Icons.nightlight_round,
                    label: '최대 방치 보상',
                    value:
                        '+${NumberFormatter.format(game.dps * offlineMaxSeconds)}',
                    subLabel: '$offlineMaxHours시간 기준',
                    color: const Color(0xFF5E35B1),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _RevenueSection(
                title: '배율 구성',
                children: [
                  _RevenueMetric(
                    icon: Icons.auto_awesome,
                    label: '브랜드 연구',
                    value: _pct(permanentPct),
                    color: const Color(0xFF00695C),
                  ),
                  _RevenueMetric(
                    icon: Icons.collections_bookmark,
                    label: '코스터 수집',
                    value: _pct(collectionPct),
                    color: const Color(0xFF6A1B9A),
                  ),
                  _RevenueMetric(
                    icon: Icons.train,
                    label: '메인 코스터',
                    value: _pct(mainCoasterPct),
                    subLabel: '${game.mainCoasterStage}단계',
                    color: AppColors.deepCoral,
                  ),
                  _RevenueMetric(
                    icon: Icons.local_fire_department,
                    label: '현재 콤보',
                    value: _pct(comboPct),
                    subLabel: 'x${game.combo}',
                    color: const Color(0xFFE53935),
                  ),
                  _RevenueMetric(
                    icon: Icons.flash_on,
                    label: '활성 부스터',
                    value: activeBoosters.isEmpty
                        ? '없음'
                        : '${activeBoosters.length}개 · x${_multLabel(strongestBoost)}',
                    color: const Color(0xFFFF8A00),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _RevenueSection(
                title: '지역 투자',
                children: [
                  _RevenueMetric(
                    icon: Icons.location_city,
                    label: '평가 가치',
                    value: NumberFormatter.format(holdingsValue),
                    color: const Color(0xFF7C4DFF),
                  ),
                  _RevenueMetric(
                    icon: Icons.payments,
                    label: '미수령 배당',
                    value: '+${NumberFormatter.format(pendingDividend)}',
                    color: AppColors.deepCoral,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pct(num fraction) {
    final pct = fraction * 100;
    final digits = pct >= 100 ? 0 : 1;
    return '+${pct.toStringAsFixed(digits)}%';
  }

  static String _multLabel(double value) {
    final digits = value % 1 == 0 ? 0 : 1;
    return value.toStringAsFixed(digits);
  }
}

class _RevenueSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _RevenueSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _RevenueMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subLabel;
  final Color color;

  const _RevenueMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.subLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subLabel != null)
                Text(
                  subLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
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

/// Visible-from-anywhere progress bar for the next VIP guest spawn. Replaces the
/// old text-only "VIP 손님까지 N회 터치" hint. While a VIP guest is on screen, the
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
    final title = active ? 'VIP 손님 출현' : '다음 VIP 손님';
    final label = active
        ? '응대 보상 +${NumberFormatter.format(reward)}'
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
            child: Icon(Icons.workspace_premium, color: accent, size: 18),
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

/// Slim handle bar above the bottom HUD stack. Tapping toggles the
/// expanded state — when collapsed, the park scene grows into the
/// space the HUD would occupy. The chevron icon flips to indicate
/// the action it'll perform on next tap.
class _BottomHudToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _BottomHudToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Container(
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: Colors.black.withValues(alpha: 0.06), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 16,
                color: Colors.black.withValues(alpha: 0.65),
              ),
              const SizedBox(width: 4),
              Text(
                expanded ? '대시보드 접기' : '대시보드 펼치기',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
