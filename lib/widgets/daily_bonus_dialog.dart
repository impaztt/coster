import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/game_provider.dart';
import '../services/ad_service.dart';

class DailyBonusDialog extends ConsumerWidget {
  final DailyBonus bonus;
  const DailyBonusDialog({super.key, required this.bonus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxDay = dailyRewards.length - 1;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_month,
                color: Color(0xFF00695C),
                size: 38,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '출석 보너스!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${bonus.streak}일째 연속 접속',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int i = 1; i <= maxDay; i++)
                  _DayCell(
                    day: i,
                    reward: dailyRewardFor(i),
                    state: i < bonus.streak
                        ? _DayState.claimed
                        : i == bonus.streak
                            ? _DayState.today
                            : _DayState.upcoming,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.diamond, color: Color(0xFF26A69A), size: 28),
                const SizedBox(width: 6),
                Text(
                  '+${bonus.essence} 정수',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF00695C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                ref.read(gameProvider.notifier).claimDailyBonus(bonus);
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                '수령',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _claimDouble(context, ref),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.coral, width: 1.5),
              ),
              icon: const Icon(Icons.play_circle_fill,
                  color: AppColors.deepCoral),
              label: Text(
                '광고 시청 후 2배 (+${bonus.essence})',
                style: const TextStyle(
                  color: AppColors.deepCoral,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '7일 주기 · 하루 거르면 1일째부터 다시',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimDouble(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(gameProvider.notifier);
    final earned = await AdService.instance
        .showRewarded(trigger: 'daily_bonus_x2');
    if (!context.mounted) return;
    if (earned) {
      notifier.claimDailyBonus(bonus);
      notifier.grantEssence(bonus.essence);
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('광고를 끝까지 시청해야 2배 보상이 지급돼요'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

enum _DayState { claimed, today, upcoming }

class _DayCell extends StatelessWidget {
  final int day;
  final int reward;
  final _DayState state;
  const _DayCell({
    required this.day,
    required this.reward,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = state == _DayState.today;
    final claimed = state == _DayState.claimed;
    final bg = isToday
        ? AppColors.coral
        : claimed
            ? AppColors.mint.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.05);
    final fg = isToday ? Colors.white : Colors.black.withValues(alpha: 0.75);
    return Container(
      width: 38,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'D$day',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$reward',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
