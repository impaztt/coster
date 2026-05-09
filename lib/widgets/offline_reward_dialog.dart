import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../providers/game_provider.dart';
import '../services/ad_service.dart';

class OfflineRewardDialog extends ConsumerWidget {
  final OfflineReward reward;
  const OfflineRewardDialog({super.key, required this.reward});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.yellow.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.nightlight_round,
                color: Color(0xFF8D6E00),
                size: 40,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              reward.blockedByClockGuard ? '오프라인 보상 보호' : '다녀오셨군요!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            if (reward.blockedByClockGuard)
              Text(
                '기기 시간이 비정상으로 감지되어 이번 오프라인 보상은 지급되지 않았습니다.\n'
                '시간 자동 설정을 켜고 다시 접속해 주세요.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent.shade700,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              )
            else ...[
              Text(
                '${_durationLabel(reward.duration)} 동안 동료들이 활약했어요',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '방치 효율 100% · 최대 ${offlineMaxHours}시간 누적',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on,
                    color: AppColors.yellow, size: 32),
                const SizedBox(width: 8),
                Text(
                  '+${NumberFormatter.format(reward.gold)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepCoral,
                  ),
                ),
              ],
            ),
            if (reward.essenceBonus > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.diamond, color: Color(0xFF26A69A), size: 24),
                  const SizedBox(width: 6),
                  Text(
                    '복귀 지원 +${reward.essenceBonus} 정수',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00695C),
                    ),
                  ),
                ],
              ),
            ],
            if (!reward.blockedByClockGuard) ...[
              const SizedBox(height: 8),
              Text(
                '복귀 추천: 일일/주간 미션부터 처리하면 성장 속도가 빨라집니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.48),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                ref.read(gameProvider.notifier).claimOfflineReward(reward);
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text(
                '수령하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            if (!reward.blockedByClockGuard && reward.gold > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _claimDouble(context, ref),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: AppColors.coral, width: 1.5),
                ),
                icon: const Icon(Icons.play_circle_fill,
                    color: AppColors.deepCoral),
                label: Text(
                  '광고 시청 후 2배 수령 (+${NumberFormatter.format(reward.gold)})',
                  style: const TextStyle(
                    color: AppColors.deepCoral,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _claimDouble(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(gameProvider.notifier);
    final earned = await AdService.instance
        .showRewarded(trigger: 'offline_reward_x2');
    if (!context.mounted) return;
    if (earned) {
      // Pay the base reward, then add another full reward worth of gold
      // (and double the essence bonus too) directly.
      notifier.claimOfflineReward(reward);
      notifier.grantBonusGold(reward.gold);
      if (reward.essenceBonus > 0) {
        notifier.grantEssence(reward.essenceBonus);
      }
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

  String _durationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h시간 $m분';
    if (m > 0) return '$m분';
    return '${d.inSeconds}초';
  }
}
