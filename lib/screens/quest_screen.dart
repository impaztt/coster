import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/game_provider.dart';

/// §3.3 Daily Quest — surfaces the existing daily/weekly mission system,
/// which previously had no UI. Tap a completed mission to claim its
/// reward; the bottom CTA sweeps every claimable mission at once.
class QuestScreen extends ConsumerWidget {
  const QuestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final dailies = game.dailyMissions;
    final weeklies = game.weeklyMissions;
    final dailyClaimable = dailies.where((m) => m.done && !m.claimed).length;
    final weeklyClaimable = weeklies.where((m) => m.done && !m.claimed).length;
    final totalClaimable = dailyClaimable + weeklyClaimable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('퀘스트'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        children: [
          _Header(
            dailyClaimable: dailyClaimable,
            weeklyClaimable: weeklyClaimable,
          ),
          const SizedBox(height: 14),
          _SectionTitle(title: '일일 퀘스트', count: dailies.length),
          const SizedBox(height: 6),
          for (final m in dailies) ...[
            _MissionTile(
              view: m,
              onClaim: m.done && !m.claimed
                  ? () => _claim(context, ref, m.id, daily: true)
                  : null,
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 12),
          _SectionTitle(title: '주간 퀘스트', count: weeklies.length),
          const SizedBox(height: 6),
          for (final m in weeklies) ...[
            _MissionTile(
              view: m,
              onClaim: m.done && !m.claimed
                  ? () => _claim(context, ref, m.id, daily: false)
                  : null,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: totalClaimable == 0
                ? null
                : () {
                    final result = notifier.claimAllMissions();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '퀘스트 ${result.count}개 일괄 수령 — 티켓 +${result.ticket}, 명성 +${result.coins}'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
            icon: const Icon(Icons.redeem),
            label: Text(
              totalClaimable == 0
                  ? '수령 가능 퀘스트 없음'
                  : '$totalClaimable개 일괄 수령',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.deepCoral,
              minimumSize: const Size.fromHeight(48),
              disabledBackgroundColor: Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  void _claim(BuildContext context, WidgetRef ref, String id,
      {required bool daily}) {
    final ok =
        ref.read(gameProvider.notifier).claimMission(id, daily: daily);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '보상 수령 완료' : '수령 불가'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int dailyClaimable;
  final int weeklyClaimable;
  const _Header(
      {required this.dailyClaimable, required this.weeklyClaimable});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.deepCoral.withValues(alpha: 0.92),
            AppColors.coral.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.fact_check, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '오늘의 퀘스트',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '일일 $dailyClaimable · 주간 $weeklyClaimable 수령 대기',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style:
              const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _MissionTile extends StatelessWidget {
  final MissionView view;
  final VoidCallback? onClaim;
  const _MissionTile({required this.view, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final ratio = view.target == 0
        ? 0.0
        : (view.progress / view.target).clamp(0.0, 1.0);
    final claimable = onClaim != null;
    final accent = view.claimed
        ? Colors.grey
        : (claimable ? const Color(0xFF2E7D32) : AppColors.deepCoral);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  view.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              if (view.claimed)
                const _Badge(label: '수령됨', color: Colors.grey)
              else if (claimable)
                const _Badge(label: '수령 가능', color: Color(0xFF2E7D32))
              else
                Text(
                  '${view.progress} / ${view.target}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            view.description,
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (view.rewardTicket > 0) ...[
                const Icon(Icons.diamond,
                    size: 13, color: Color(0xFF7C4DFF)),
                const SizedBox(width: 3),
                Text('${view.rewardTicket}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
              ],
              if (view.rewardPrestigeCoins > 0) ...[
                const Icon(Icons.workspace_premium,
                    size: 13, color: Color(0xFF00695C)),
                const SizedBox(width: 3),
                Text('${view.rewardPrestigeCoins}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ],
              const Spacer(),
              if (claimable)
                FilledButton(
                  onPressed: onClaim,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 32),
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                  child: const Text('수령',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}
