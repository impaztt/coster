import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../data/producer_catalog.dart';
import '../data/prestige_upgrade_catalog.dart';
import '../models/producer.dart';
import '../models/prestige_upgrade.dart';
import '../providers/game_provider.dart';

class PrestigeScreen extends ConsumerWidget {
  const PrestigeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '환생',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              '이번 회차를 영구 성장으로 전환합니다.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    height: 42,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: const TabBar(
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.black54,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: AppColors.deepCoral,
                        borderRadius: BorderRadius.all(Radius.circular(7)),
                      ),
                      labelStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      tabs: [
                        Tab(height: 34, text: '환생 준비'),
                        Tab(height: 34, text: '각인 연구'),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: TabBarView(
                      children: [
                        _PrestigeOverview(),
                        _PrestigeShop(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrestigeOverview extends ConsumerWidget {
  const _PrestigeOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final coinsGain = game.prestigeCoinsAvailable;
    final canPrestige = coinsGain > 0;
    final currentPct = ((game.prestigeMultiplier - 1) * 100).toStringAsFixed(0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _PrestigeActionPanel(
          coinsGain: coinsGain,
          currentPct: currentPct,
          canPrestige: canPrestige,
          onPrestige: () => _confirmPrestige(
            context,
            ref,
            coinsGain: coinsGain,
          ),
        ),
        const SizedBox(height: 12),
        _PrestigeSummaryGrid(
          items: [
            _PrestigeSummaryItem(
              icon: Icons.currency_exchange,
              color: const Color(0xFF7C4DFF),
              label: '보유 코인',
              value: '${game.prestigeCoins}',
            ),
            _PrestigeSummaryItem(
              icon: Icons.history_toggle_off,
              color: AppColors.deepCoral,
              label: '환생 횟수',
              value: '${game.prestigeCount}회',
            ),
            _PrestigeSummaryItem(
              icon: Icons.monetization_on,
              color: const Color(0xFF00695C),
              label: '현재 회차 골드',
              value: NumberFormatter.format(game.totalGoldEarned),
            ),
            _PrestigeSummaryItem(
              icon: Icons.auto_awesome,
              color: AppColors.mint,
              label: '영구 배율',
              value: '+$currentPct%',
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _PrestigeChangePanel(),
      ],
    );
  }

  Future<void> _confirmPrestige(
    BuildContext context,
    WidgetRef ref, {
    required int coinsGain,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        title: const Text('환생 확인'),
        content: Text(
          '환생 코인 +$coinsGain 을 획득합니다.\n'
          '획득한 코인으로 영구 각인/영구 업그레이드를 구매할 수 있습니다.\n\n'
          '현재 회차 골드와 업그레이드는 초기화됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('환생'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = ref.read(gameProvider.notifier).prestige();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('환생 보상이 아직 0입니다. 더 진행한 뒤 시도해 주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _PrestigeActionPanel extends StatelessWidget {
  final int coinsGain;
  final String currentPct;
  final bool canPrestige;
  final VoidCallback onPrestige;

  const _PrestigeActionPanel({
    required this.coinsGain,
    required this.currentPct,
    required this.canPrestige,
    required this.onPrestige,
  });

  @override
  Widget build(BuildContext context) {
    final status = canPrestige ? '획득 가능' : '진행 필요';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.restart_alt,
                  color: AppColors.deepCoral,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '지금 환생 시',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      '+$coinsGain 코인',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              _PrestigeStatusPill(
                label: status,
                color: canPrestige ? const Color(0xFF00695C) : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PrestigeInlineMetric(
                  label: '현재 영구 배율',
                  value: '+$currentPct%',
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: _PrestigeInlineMetric(
                  label: '환생 후',
                  value: '각인 연구',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canPrestige ? onPrestige : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(canPrestige ? '환생하기' : '아직 보상이 부족합니다'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    canPrestige ? AppColors.coral : Colors.grey.shade300,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrestigeStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _PrestigeStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PrestigeInlineMetric extends StatelessWidget {
  final String label;
  final String value;

  const _PrestigeInlineMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _PrestigeSummaryGrid extends StatelessWidget {
  final List<_PrestigeSummaryItem> items;

  const _PrestigeSummaryGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 360;
        const gap = 8.0;
        final width = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _PrestigeSummaryTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _PrestigeSummaryItem {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _PrestigeSummaryItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
}

class _PrestigeSummaryTile extends StatelessWidget {
  final _PrestigeSummaryItem item;

  const _PrestigeSummaryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: item.color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
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

class _PrestigeChangePanel extends StatelessWidget {
  const _PrestigeChangePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _PrestigeChangeColumn(
              title: '초기화됨',
              color: AppColors.deepCoral,
              icon: Icons.restart_alt,
              items: ['골드', '일반 강화', '현재 회차 진행'],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _PrestigeChangeColumn(
              title: '유지됨',
              color: Color(0xFF00695C),
              icon: Icons.verified,
              items: ['환생 코인', '각인 연구', '수집 보너스'],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrestigeChangeColumn extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<String> items;

  const _PrestigeChangeColumn({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items) ...[
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (item != items.last) const SizedBox(height: 5),
        ],
      ],
    );
  }
}

class _PrestigeShop extends ConsumerWidget {
  const _PrestigeShop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    var maxTranscendentLevel = 0;
    for (final def in producerCatalog) {
      if (def.category != ProducerCategory.transcendent) continue;
      final lv = game.producerLevels[def.id] ?? 0;
      if (lv > maxTranscendentLevel) maxTranscendentLevel = lv;
    }
    final growthUpgrades = prestigeUpgradeCatalog
        .where((def) => def.coinGainBonusPerLevel == 0)
        .toList();
    final efficiencyUpgrades = prestigeUpgradeCatalog
        .where((def) => def.coinGainBonusPerLevel > 0)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _CoinBalanceBar(coins: game.prestigeCoins),
        const SizedBox(height: 16),
        _UpgradeSection(
          title: '핵심 연구',
          subtitle: '중후반 루프를 여는 영구 성장',
          children: [
            _AscensionCoreCard(
              level: game.ascensionCoreLevel,
              unlocked: game.ascensionCoreUnlocked,
              currentMult: game.ascensionCoreMultiplier,
              nextCost: game.ascensionCoreNextCost,
              coins: game.prestigeCoins,
              prestigeCount: game.prestigeCount,
              maxTranscendentLevel: maxTranscendentLevel,
              onBuy: notifier.buyAscensionCore,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _UpgradeSection(
          title: '성장 각인',
          subtitle: '터치, DPS, 전체 수익을 영구 강화',
          children: [
            for (final def in growthUpgrades)
              _ShopTile(
                def: def,
                level: game.prestigeUpgradeLevel(def.id),
                coins: game.prestigeCoins,
                onBuy: () => notifier.buyPrestigeUpgrade(def.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _UpgradeSection(
          title: '환생 효율',
          subtitle: '다음 환생의 코인 획득량 증가',
          children: [
            for (final def in efficiencyUpgrades)
              _ShopTile(
                def: def,
                level: game.prestigeUpgradeLevel(def.id),
                coins: game.prestigeCoins,
                onBuy: () => notifier.buyPrestigeUpgrade(def.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _CoinBalanceBar extends StatelessWidget {
  final int coins;

  const _CoinBalanceBar({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF7C4DFF).withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_exchange, color: Color(0xFF7C4DFF)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '환생 코인',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            '$coins',
            style: const TextStyle(
              color: Color(0xFF5E35B1),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _UpgradeSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrestigeSectionTitle(title: title, subtitle: subtitle),
        const SizedBox(height: 10),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PrestigeSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PrestigeSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.48),
            ),
          ),
        ),
      ],
    );
  }
}

class _AscensionCoreCard extends StatelessWidget {
  final int level;
  final bool unlocked;
  final double currentMult;
  final int nextCost;
  final int coins;
  final int prestigeCount;
  final int maxTranscendentLevel;
  final bool Function() onBuy;
  const _AscensionCoreCard({
    required this.level,
    required this.unlocked,
    required this.currentMult,
    required this.nextCost,
    required this.coins,
    required this.prestigeCount,
    required this.maxTranscendentLevel,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final canBuy = unlocked && coins >= nextCost;
    final prestigeRemaining = (5 - prestigeCount).clamp(0, 5);
    final transcendentRemaining = (25 - maxTranscendentLevel).clamp(0, 25);
    final pct = ((currentMult - 1) * 100).toStringAsFixed(1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: unlocked
            ? null
            : () => _showLockedHint(
                  context,
                  prestigeRemaining: prestigeRemaining,
                  transcendentRemaining: transcendentRemaining,
                ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF90CAF9), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_graph, color: Color(0xFF1565C0)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '초월 코어 연구 (중후반 루프)',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                unlocked
                    ? 'Lv $level · 전체 수익 영구 +$pct%'
                    : '해금 조건: 환생 5회 + 초월 유닛 중 하나 Lv 25',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
              if (!unlocked) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _UnlockRequirementChip(
                      label: '환생',
                      value: '$prestigeCount / 5',
                      done: prestigeRemaining == 0,
                    ),
                    _UnlockRequirementChip(
                      label: '초월 최고',
                      value: 'Lv $maxTranscendentLevel / 25',
                      done: transcendentRemaining == 0,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: unlocked
                      ? (canBuy
                          ? () {
                              final ok = onBuy();
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('조건 미달 또는 코인이 부족합니다'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('환생 코인이 부족합니다'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            })
                      : () => _showLockedHint(
                            context,
                            prestigeRemaining: prestigeRemaining,
                            transcendentRemaining: transcendentRemaining,
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        canBuy ? const Color(0xFF1976D2) : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    unlocked
                        ? '연구 업그레이드 (${NumberFormatter.format(nextCost.toDouble())} 코인)'
                        : '아직 잠겨 있음',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLockedHint(
    BuildContext context, {
    required int prestigeRemaining,
    required int transcendentRemaining,
  }) {
    final remain = <String>[];
    if (prestigeRemaining > 0) remain.add('환생 $prestigeRemaining회');
    if (transcendentRemaining > 0) remain.add('초월 $transcendentRemaining레벨');
    final remainText =
        remain.isEmpty ? '곧 해금됩니다.' : '남은 조건: ${remain.join(' · ')}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '초월 코어는 환생 5회 + 초월 유닛 Lv 25에서 해금됩니다.\n'
            '현재 진행: 환생 $prestigeCount/5 · 초월 최고 Lv $maxTranscendentLevel/25\n'
            '$remainText',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

class _UnlockRequirementChip extends StatelessWidget {
  final String label;
  final String value;
  final bool done;
  const _UnlockRequirementChip({
    required this.label,
    required this.value,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final bg = done
        ? AppColors.mint.withValues(alpha: 0.24)
        : Colors.black.withValues(alpha: 0.05);
    final fg =
        done ? const Color(0xFF00695C) : Colors.black.withValues(alpha: 0.72);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done
              ? AppColors.mint.withValues(alpha: 0.5)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _ShopTile extends StatelessWidget {
  final PrestigeUpgradeDef def;
  final int level;
  final int coins;
  final bool Function() onBuy;

  const _ShopTile({
    required this.def,
    required this.level,
    required this.coins,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final atMax = level >= def.maxLevel;
    final cost = atMax ? 0 : def.costAt(level);
    final canBuy = !atMax && coins >= cost;
    final progress = (level / def.maxLevel).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: def.accent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: def.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(def.icon, color: def.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      def.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: def.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Lv $level / ${def.maxLevel}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: def.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.black.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(def.accent),
            ),
          ),
          const SizedBox(height: 10),
          _UpgradeEffectRow(
            label: '현재',
            value: _effectLabel(def, level),
            color: const Color(0xFF00695C),
          ),
          const SizedBox(height: 5),
          _UpgradeEffectRow(
            label: '다음',
            value: atMax ? '최대 레벨입니다' : _effectLabel(def, level + 1),
            color: def.accent,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canBuy
                  ? () {
                      final ok = onBuy();
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('환생 코인이 부족합니다'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor:
                    canBuy ? AppColors.coral : Colors.grey.shade300,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                atMax ? '최대 레벨' : '구매 ($cost 코인)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _effectLabel(PrestigeUpgradeDef def, int level) {
    final clamped = level.clamp(0, def.maxLevel);
    final parts = <String>[];
    if (def.globalBonusPerLevel > 0) {
      final pct = (def.globalBonusPerLevel * clamped * 100).toStringAsFixed(0);
      parts.add('전체 +$pct%');
    }
    if (def.tapBonusPerLevel > 0) {
      final pct = (def.tapBonusPerLevel * clamped * 100).toStringAsFixed(0);
      parts.add('터치 +$pct%');
    }
    if (def.dpsBonusPerLevel > 0) {
      final pct = (def.dpsBonusPerLevel * clamped * 100).toStringAsFixed(0);
      parts.add('DPS +$pct%');
    }
    if (def.coinGainBonusPerLevel > 0) {
      final pct =
          (def.coinGainBonusPerLevel * clamped * 100).toStringAsFixed(0);
      parts.add('코인 획득 +$pct%');
    }
    if (parts.isEmpty) return '-';
    return parts.join(' / ');
  }
}

class _UpgradeEffectRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _UpgradeEffectRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
