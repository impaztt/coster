import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/theme.dart';
import '../data/main_coaster_enhancement.dart';
import '../data/main_coaster_evolution.dart';
import '../providers/game_provider.dart';
import 'main_coaster_widget.dart';

/// Listens to [mainCoasterEventProvider] and displays:
///   • A modal evolution overlay when the player crosses into a new tier.
///   • A modal naming prompt the very first time +1 succeeds.
///   • A SnackBar for milestone rewards.
class MainCoasterEventHost extends ConsumerStatefulWidget {
  final Widget child;
  const MainCoasterEventHost({super.key, required this.child});

  @override
  ConsumerState<MainCoasterEventHost> createState() =>
      _MainCoasterEventHostState();
}

class _MainCoasterEventHostState extends ConsumerState<MainCoasterEventHost> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<MainCoasterEvent>>(
      mainCoasterEventProvider,
      (prev, next) {
        next.whenData((evt) async {
          switch (evt.type) {
            case MainCoasterEventType.tierUp:
              await _showTierUp(evt);
            case MainCoasterEventType.milestone:
              _showMilestone(evt.milestone!);
            case MainCoasterEventType.namingPrompt:
              await _showNamingPrompt();
          }
        });
      },
    );
    return widget.child;
  }

  Future<void> _showTierUp(MainCoasterEvent evt) async {
    final tierIdx = evt.tierIndex!;
    final tier = mainCoasterTiers[tierIdx];
    if (!mounted) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    await showDialog<void>(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => _TierUpOverlay(
        tierName: tier.name,
        description: tier.description,
        stage: evt.stage ?? 0,
      ),
    );
  }

  void _showMilestone(MainCoasterMilestoneReward reward) {
    if (!mounted) return;
    final parts = <String>[];
    if (reward.ticket > 0) parts.add('티켓 +${reward.ticket}');
    if (reward.title != null) parts.add('호칭 "${reward.title}"');
    if (reward.collectionBonusFraction != null) {
      parts.add(
          '컬렉션 +${(reward.collectionBonusFraction! * 100).toStringAsFixed(0)}%');
    }
    if (reward.summonRateBonusFraction != null) {
      parts.add(
          '도입률 +${(reward.summonRateBonusFraction! * 100).toStringAsFixed(0)}%');
    }
    if (reward.goldenFrame) parts.add('도감 황금 프레임');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '+${reward.stage} 도달 · ${mainCoasterStageUpgradeLabel(reward.stage)} — ${parts.join(' · ')}',
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showNamingPrompt() async {
    if (!mounted) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final controller = TextEditingController();
    final picked = await showDialog<String>(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('내 코스터 이름 짓기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '첫 강화를 시그니처화합니다. 이 코스터의 이름을 지어주세요.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 14,
              decoration: const InputDecoration(
                hintText: '선라이즈 익스프레스',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('확정'),
          ),
        ],
      ),
    );
    if (picked != null && picked.trim().isNotEmpty) {
      ref.read(gameProvider.notifier).setMainCoasterName(picked);
    }
  }
}

class _TierUpOverlay extends StatefulWidget {
  final String tierName;
  final String description;
  final int stage;
  const _TierUpOverlay({
    required this.tierName,
    required this.description,
    required this.stage,
  });

  @override
  State<_TierUpOverlay> createState() => _TierUpOverlayState();
}

class _TierUpOverlayState extends State<_TierUpOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(0),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          final scale =
              0.6 + 0.4 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppColors.coral.withValues(alpha: 0.5 * t),
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                const Spacer(),
                Transform.scale(
                  scale: scale,
                  child: MainCoasterWidget(
                    stage: widget.stage,
                    size: 220,
                    onTap: (_) {},
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: t,
                  child: Text(
                    '진화!',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: AppColors.coral.withValues(alpha: 0.85),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: t,
                  child: Text(
                    widget.tierName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: t,
                  child: Text(
                    widget.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                const Spacer(),
                Opacity(
                  opacity: t,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      side: const BorderSide(color: Colors.white54),
                    ),
                    child: const Text('확인'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}
