import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../providers/game_provider.dart';

/// Lifetime stats — surfaces the counters that already accumulate in
/// `_save.stats` (and a handful from GameState) but had no UI before.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final playHours = game.playTimeSeconds / 3600;
    return Scaffold(
      appBar: AppBar(title: const Text('통계')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _StatsGroup(
            title: '경제',
            entries: [
              _StatEntry(
                  label: '누적 골드 수입',
                  value: NumberFormatter.format(game.lifetimeGold)),
              _StatEntry(
                  label: '누적 골드 지출',
                  value: NumberFormatter.format(game.totalGoldSpent)),
              _StatEntry(
                  label: '최고 초당 수익',
                  value: '${NumberFormatter.formatPrecise(game.maxDpsEver)} /s'),
              _StatEntry(
                  label: '프레스티지 횟수',
                  value: '${game.prestigeCount}'),
            ],
          ),
          const SizedBox(height: 12),
          _StatsGroup(
            title: '클리커',
            entries: [
              _StatEntry(
                  label: '누적 탭', value: '${NumberFormatter.formatInt(game.totalTaps)}'),
              _StatEntry(
                  label: '크리티컬', value: '${NumberFormatter.formatInt(game.totalCrits)}'),
              _StatEntry(
                  label: '최대 콤보', value: '${game.maxCombo}'),
              _StatEntry(
                  label: '콤보 버스트', value: '${game.comboBurstCount}'),
              _StatEntry(
                  label: 'VIP 손님 응대', value: '${game.slimesDefeated}'),
            ],
          ),
          const SizedBox(height: 12),
          _StatsGroup(
            title: '운영',
            entries: [
              _StatEntry(
                  label: '운영 업그레이드 구매', value: '${game.totalTapUpgradesBought}'),
              _StatEntry(label: '코스터 도입', value: '${game.totalSummons}'),
              _StatEntry(label: '스킬 사용', value: '${game.skillsUsed}'),
              _StatEntry(label: '부스터 구매', value: '${game.boostersPurchased}'),
              _StatEntry(label: '최장 출석 일수', value: '${game.maxDailyStreak}일'),
            ],
          ),
          const SizedBox(height: 12),
          _StatsGroup(
            title: '플레이 시간',
            entries: [
              _StatEntry(
                  label: '누적 플레이',
                  value: playHours >= 1
                      ? '${playHours.toStringAsFixed(1)}시간'
                      : '${(game.playTimeSeconds / 60).toStringAsFixed(0)}분'),
            ],
          ),
          const SizedBox(height: 12),
          _StatsGroup(
            title: '현재 상태',
            entries: [
              _StatEntry(label: '메인 코스터 단계', value: '${game.mainCoasterStage}'),
              _StatEntry(
                  label: '메인 코스터 최고 도달', value: '${game.mainCoasterHighestStage}'),
              _StatEntry(
                  label: '명성 (프레스티지 코인)',
                  value: '${NumberFormatter.formatInt(game.prestigeCoins)}'),
              _StatEntry(
                  label: '도감 (Dex Lv)', value: '${game.dexLv}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsGroup extends StatelessWidget {
  final String title;
  final List<_StatEntry> entries;
  const _StatsGroup({required this.title, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final e in entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Text(
                  e.value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _StatEntry {
  final String label;
  final String value;
  _StatEntry({required this.label, required this.value});
}
