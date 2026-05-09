import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../data/producer_catalog.dart';
import '../data/tap_upgrade_catalog.dart';
import '../models/producer.dart';
import '../providers/game_provider.dart';
import '../widgets/dps_display.dart';
import '../widgets/gold_display.dart';
import '../widgets/upgrade_tile.dart';

class UpgradeScreen extends ConsumerWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final multiplier = ref.watch(buyMultiplierProvider);

    final companions = producerCatalog
        .where((p) => p.category == ProducerCategory.companion)
        .toList();
    final transcendents = producerCatalog
        .where((p) => p.category == ProducerCategory.transcendent)
        .toList();

    return SafeArea(
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _UpgradeHeader(game: game),
            ),
            const SizedBox(height: 8),
            const _BuyMultiplierSelector(),
            const SizedBox(height: 8),
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
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
                labelStyle:
                    TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                unselectedLabelStyle:
                    TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                tabs: [
                  Tab(height: 34, text: '터치'),
                  Tab(height: 34, text: '동료'),
                  Tab(height: 34, text: '초월'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final def in tapUpgradeCatalog)
                        Builder(builder: (_) {
                          final lv = game.tapUpgradeLevel(def.id);
                          final maxN = def.maxAffordable(game.gold, lv);
                          final isMax = multiplier < 0;
                          final n = isMax ? (maxN > 0 ? maxN : 1) : multiplier;
                          final cost = def.costForNext(lv, n);
                          final affordable =
                              isMax ? maxN > 0 : game.canAfford(cost);
                          // Show the EFFECTIVE gain — i.e. raw upgrade × all
                          // currently active multipliers (prestige, equipped
                          // sword, boosters, set, collection). Without this,
                          // the sword-collection bonus would silently apply
                          // but never show up in the buy preview.
                          final rawTap = def.tapPowerPerLevel * n;
                          final effTap = rawTap * notifier.tapMultiplier;
                          return UpgradeTile(
                            icon: def.icon,
                            accent: def.accent,
                            name: def.name,
                            description: def.description,
                            level: lv,
                            cost: cost,
                            buyCount: n,
                            gainLabel:
                                '터치당 +${NumberFormatter.formatPrecise(effTap)}',
                            affordable: affordable,
                            onBuy: () =>
                                notifier.buyTapUpgrade(def.id, multiplier),
                          );
                        }),
                    ],
                  ),
                  _ProducerList(
                    defs: companions,
                    game: game,
                    multiplier: multiplier,
                    notifier: notifier,
                  ),
                  _ProducerList(
                    defs: transcendents,
                    game: game,
                    multiplier: multiplier,
                    notifier: notifier,
                    headerLabel: '동료보다 한참 위의 존재들. 가격이 무서울 정도지만 DPS도 자릿수가 다릅니다.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeHeader extends StatelessWidget {
  final GameState game;

  const _UpgradeHeader({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: GoldDisplay(amount: game.gold)),
          const SizedBox(width: 8),
          DpsDisplay(dps: game.dps),
        ],
      ),
    );
  }
}

class _ProducerList extends StatelessWidget {
  final List<ProducerDef> defs;
  final GameState game;
  final int multiplier;
  final GameNotifier notifier;
  final String? headerLabel;

  const _ProducerList({
    required this.defs,
    required this.game,
    required this.multiplier,
    required this.notifier,
    this.headerLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (headerLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              headerLabel!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
        for (final def in defs)
          Builder(builder: (_) {
            final lv = game.producerLevel(def.id);
            final maxN = def.maxAffordable(game.gold, lv);
            final isMax = multiplier < 0;
            final n = isMax ? (maxN > 0 ? maxN : 1) : multiplier;
            final cost = def.costForNext(lv, n);
            final affordable = isMax ? maxN > 0 : game.canAfford(cost);
            final nextMs = def.nextMilestone(lv);
            final curMult = def.milestoneMultiplier(lv).toInt();
            final msLabel = nextMs == null
                ? '마일스톤 완주! (x$curMult DPS)'
                : '다음 Lv $nextMs → DPS x2 (현재 x$curMult)';
            // Effective gain = raw producer DPS × every active multiplier
            // (prestige, equipped sword, boosters, set, COLLECTION). The
            // collection bonus actually does affect 동료/초월 income — this
            // surfaces it instead of leaving the player wondering.
            final rawDps = def.baseDps * n * def.milestoneMultiplier(lv);
            final effDps = rawDps * notifier.dpsMultiplier;
            return UpgradeTile(
              icon: def.icon,
              accent: def.accent,
              name: def.name,
              description: def.description,
              level: lv,
              cost: cost,
              buyCount: n,
              gainLabel: 'DPS +${NumberFormatter.formatPrecise(effDps)}',
              milestoneLabel: msLabel,
              affordable: affordable,
              onBuy: () => notifier.buyProducer(def.id, multiplier),
            );
          }),
      ],
    );
  }
}

class _BuyMultiplierSelector extends ConsumerWidget {
  const _BuyMultiplierSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(buyMultiplierProvider);
    const options = <(int, String)>[
      (1, 'x1'),
      (10, 'x10'),
      (100, 'x100'),
      (-1, 'Max'),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          for (final opt in options)
            Expanded(
              child: _SegmentButton(
                label: opt.$2,
                selected: selected == opt.$1,
                onTap: () =>
                    ref.read(buyMultiplierProvider.notifier).state = opt.$1,
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.coral : Colors.white;
    final fg = selected ? Colors.white : AppColors.deepCoral;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(
              color: selected
                  ? AppColors.coral
                  : AppColors.coral.withValues(alpha: 0.25),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
