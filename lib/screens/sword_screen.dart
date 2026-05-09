import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/achievement_catalog.dart';
import '../data/feature_unlocks.dart';
import '../data/repeating_achievement_catalog.dart';
import '../data/sword_affinities.dart';
import '../data/sword_catalog.dart';
import '../data/sword_sets.dart';
import '../models/achievement.dart';
import '../models/repeating_achievement.dart';
import '../models/sword.dart';
import '../providers/game_provider.dart';
import '../widgets/summon_dialog.dart';
import '../widgets/sword_preview.dart';
import 'stock_market_screen.dart';

class SwordScreen extends ConsumerStatefulWidget {
  const SwordScreen({super.key});

  @override
  ConsumerState<SwordScreen> createState() => _SwordScreenState();
}

class _SwordScreenState extends ConsumerState<SwordScreen> {
  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final tabs = <_StoreHubTab>[
      _StoreHubTab(
        label: '상점',
        view: _NestedStoreTabView(
          tabs: [
            const _StoreHubTab(label: '상품', view: _PremiumStoreView()),
            if (game.isFeatureUnlocked(FeatureUnlocks.summonTab))
              const _StoreHubTab(label: '소환', view: _SummonView()),
          ],
        ),
      ),
      _StoreHubTab(
        label: '무기고',
        view: _NestedStoreTabView(
          tabs: [
            const _StoreHubTab(label: '수집', view: _CollectionView()),
            const _StoreHubTab(label: '착용', view: _FormationView()),
            if (game.isFeatureUnlocked(FeatureUnlocks.swordSetsView))
              const _StoreHubTab(label: '세트', view: _SwordSetsView()),
          ],
        ),
      ),
      if (game.isFeatureUnlocked(FeatureUnlocks.missionsTab) ||
          game.isFeatureUnlocked(FeatureUnlocks.achievementsTab))
        _StoreHubTab(
          label: '임무',
          view: _NestedStoreTabView(
            tabs: [
              if (game.isFeatureUnlocked(FeatureUnlocks.missionsTab))
                const _StoreHubTab(label: '미션', view: _MissionHubView()),
              if (game.isFeatureUnlocked(FeatureUnlocks.achievementsTab))
                const _StoreHubTab(label: '업적', view: _AchievementHubView()),
            ],
          ),
        ),
      if (game.isFeatureUnlocked(FeatureUnlocks.stockMarket))
        const _StoreHubTab(label: '투자', view: StockMarketView()),
    ];

    return SafeArea(
      child: DefaultTabController(
        key: ValueKey(tabs.map((t) => t.label).join('|')),
        length: tabs.length,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const _HeaderBar(),
            const SizedBox(height: 8),
            if (tabs.length > 1)
              Container(
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border:
                      Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.black54,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.deepCoral,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                  tabs: [
                    for (final t in tabs) Tab(height: 34, text: t.label),
                  ],
                ),
              ),
            Expanded(
              child: tabs.length == 1
                  ? tabs.first.view
                  : TabBarView(
                      children: [for (final t in tabs) t.view],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreHubTab {
  final String label;
  final Widget view;
  const _StoreHubTab({required this.label, required this.view});
}

class _NestedStoreTabView extends StatelessWidget {
  final List<_StoreHubTab> tabs;

  const _NestedStoreTabView({required this.tabs});

  @override
  Widget build(BuildContext context) {
    if (tabs.length == 1) return tabs.first.view;

    return DefaultTabController(
      key: ValueKey(tabs.map((t) => t.label).join('|')),
      length: tabs.length,
      child: Column(
        children: [
          Container(
            height: 42,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.black54,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              indicator: BoxDecoration(
                color: AppColors.deepCoral,
                borderRadius: BorderRadius.circular(6),
              ),
              tabs: [for (final tab in tabs) Tab(height: 32, text: tab.label)],
            ),
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final tab in tabs) tab.view],
            ),
          ),
        ],
      ),
    );
  }
}

String _bonusPct(double value) {
  final digits = value >= 0.1 ? 1 : 2;
  return '+${(value * 100).toStringAsFixed(digits)}%';
}

class _HeaderBar extends ConsumerWidget {
  const _HeaderBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final essence = ref.watch(gameProvider).essence;
    final owned = ref.watch(gameProvider).ownedSwords.length;
    final total = swordCatalog.length;
    final bonus = ref.read(gameProvider.notifier).collectionBonusFraction;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _InfoChip(
                  icon: Icons.diamond,
                  color: const Color(0xFF7C4DFF),
                  label: '정수',
                  value: '$essence',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoChip(
                  icon: Icons.collections_bookmark,
                  color: AppColors.deepCoral,
                  label: '수집',
                  value: '$owned / $total',
                ),
              ),
            ],
          ),
          if (bonus > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFAB47BC).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFAB47BC).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Color(0xFF6A1B9A), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '수집 보너스 +${(bonus * 100).toStringAsFixed(bonus >= 1 ? 0 : 1)}% — 터치·동료·초월(초당 수입) 모두 증가',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6A1B9A),
                        ),
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _InfoChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollectionView extends ConsumerStatefulWidget {
  const _CollectionView();

  @override
  ConsumerState<_CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends ConsumerState<_CollectionView> {
  final Set<SwordTier> _collapsed = <SwordTier>{};

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    // Highest tier first so the showcase grades sit at the top.
    final tiers = SwordTier.values.reversed.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      itemCount: tiers.length,
      itemBuilder: (context, i) {
        final tier = tiers[i];
        final defs = swordCatalog.where((d) => d.tier == tier).toList();
        final owned = <SwordDef>[];
        final unowned = <SwordDef>[];
        for (final d in defs) {
          if (game.ownsSword(d.id)) {
            owned.add(d);
          } else {
            unowned.add(d);
          }
        }
        final collapsed = _collapsed.contains(tier);
        return _TierSection(
          tier: tier,
          owned: owned,
          unowned: unowned,
          collapsed: collapsed,
          onToggle: () => setState(() {
            if (collapsed) {
              _collapsed.remove(tier);
            } else {
              _collapsed.add(tier);
            }
          }),
          equippedId: game.equippedSwordId,
          levelOf: game.swordLevel,
          onTapCard: (def) => _showDetail(context, def),
        );
      },
    );
  }

  void _showDetail(BuildContext context, SwordDef def) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SwordDetailSheet(def: def),
    );
  }
}

class _FormationView extends ConsumerWidget {
  const _FormationView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final slots = notifier.formationSwordIds;
    final summary = notifier.formationSummary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        _FormationSummaryCard(
          summary: summary,
          onAuto: game.ownedSwords.isEmpty ? null : notifier.autoFillFormation,
          onClear: summary.filledSlots == 0 ? null : notifier.clearFormation,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < swordFormationSlotCount; i++)
          _FormationSlotCard(
            slot: i,
            swordId: slots[i],
            onPick: () => _openFormationPicker(context, ref, i),
            onClear: slots[i] == null
                ? null
                : () => notifier.setFormationSword(i, null),
          ),
        const SizedBox(height: 8),
        _FormationRuleCard(summary: summary),
      ],
    );
  }
}

class _FormationSummaryCard extends StatelessWidget {
  final FormationSummary summary;
  final VoidCallback? onAuto;
  final VoidCallback? onClear;

  const _FormationSummaryCard({
    required this.summary,
    required this.onAuto,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF263238), Color(0xFF7C4DFF)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '착용',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '보유 검 5자루를 배치해 전투력과 검세권을 동시에 키웁니다.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FormationBonusTile(
                  label: '터치',
                  value: _bonusPct(summary.tapBonus),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FormationBonusTile(
                  label: 'DPS',
                  value: _bonusPct(summary.dpsBonus),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FormationBonusTile(
                  label: '검세권',
                  value: _bonusPct(summary.marketBonus),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAuto,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('추천 편성'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onClear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                child: const Text('비우기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormationBonusTile extends StatelessWidget {
  final String label;
  final String value;

  const _FormationBonusTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormationSlotCard extends StatelessWidget {
  final int slot;
  final String? swordId;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _FormationSlotCard({
    required this.slot,
    required this.swordId,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final id = swordId;
    SwordDef? sword;
    if (id != null) {
      try {
        sword = swordById(id);
      } catch (_) {
        sword = null;
      }
    }
    final role = sword == null ? null : swordFormationRole(sword);
    final region = sword == null ? null : swordHomeRegion(sword);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: role?.color.withValues(alpha: 0.45) ?? Colors.black12,
        ),
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (role?.color ?? Colors.black54).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: sword == null
                  ? Text(
                      '${slot + 1}',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.45),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : SwordPreview(visual: sword.visual, size: 34),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: sword == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${slot + 1}번 착용 슬롯',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '보유한 검을 배치하세요',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sword.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _MiniTag(
                            label: role!.label,
                            color: role.color,
                            icon: role.icon,
                          ),
                          _MiniTag(
                            label: region!.shortName,
                            color: region.accent,
                            icon: Icons.location_city,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onPick,
                icon: const Icon(Icons.swap_horiz),
                tooltip: '선택',
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  tooltip: '해제',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormationRuleCard extends StatelessWidget {
  final FormationSummary summary;

  const _FormationRuleCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '시너지',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '역할 ${summary.distinctRoles}/5 · 지역 ${summary.distinctRegions}/${summary.filledSlots == 0 ? 5 : summary.filledSlots} · 최다 검세권 ${summary.strongestRegionCount}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '역할을 다양하게 섞으면 전투 보너스가 오르고, 같은 지역 검을 묶으면 해당 지역 주식의 내재가치와 배당이 강해집니다.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _MiniTag({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

void _openFormationPicker(BuildContext context, WidgetRef ref, int slot) {
  final game = ref.read(gameProvider);
  final selected = ref.read(gameProvider.notifier).formationSwordIds.toSet();
  final owned = <SwordDef>[];
  for (final entry in game.ownedSwords.entries) {
    if (entry.value <= 0) continue;
    try {
      owned.add(swordById(entry.key));
    } catch (_) {}
  }
  owned.sort((a, b) {
    final tierCmp = b.tier.index.compareTo(a.tier.index);
    if (tierCmp != 0) return tierCmp;
    return a.name.compareTo(b.name);
  });

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      if (owned.isEmpty) {
        return const SizedBox(
          height: 220,
          child: Center(child: Text('배치할 수 있는 보유 검이 없습니다.')),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: owned.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '착용 검 선택',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            );
          }
          final sword = owned[i - 1];
          final role = swordFormationRole(sword);
          final region = swordHomeRegion(sword);
          final alreadySelected = selected.contains(sword.id);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SwordPreview(visual: sword.visual, size: 42),
            title: Text(
              sword.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Wrap(
              spacing: 5,
              children: [
                _MiniTag(label: role.label, color: role.color, icon: role.icon),
                _MiniTag(
                  label: region.shortName,
                  color: region.accent,
                  icon: Icons.location_city,
                ),
              ],
            ),
            trailing: alreadySelected
                ? const Icon(Icons.check_circle, color: AppColors.coral)
                : Icon(Icons.add_circle_outline, color: sword.tier.color),
            onTap: () {
              ref.read(gameProvider.notifier).setFormationSword(slot, sword.id);
              Navigator.of(ctx).pop();
            },
          );
        },
      );
    },
  );
}

class _TierSection extends StatelessWidget {
  final SwordTier tier;
  final List<SwordDef> owned;
  final List<SwordDef> unowned;
  final bool collapsed;
  final VoidCallback onToggle;
  final String? equippedId;
  final int Function(String id) levelOf;
  final void Function(SwordDef def) onTapCard;

  const _TierSection({
    required this.tier,
    required this.owned,
    required this.unowned,
    required this.collapsed,
    required this.onToggle,
    required this.equippedId,
    required this.levelOf,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    final total = owned.length + unowned.length;
    final ratio = total == 0 ? 0.0 : owned.length / total;
    final color = tier.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tier.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tier.korLabel,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${owned.length} / $total',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: ratio >= 1
                                        ? color
                                        : Colors.black.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 5,
                                backgroundColor: Colors.black12,
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!collapsed) ...[
              if (owned.isNotEmpty)
                _OwnershipSubsection(
                  label: '획득',
                  count: owned.length,
                  accent: color,
                  defs: owned,
                  equippedId: equippedId,
                  levelOf: levelOf,
                  onTapCard: onTapCard,
                ),
              if (unowned.isNotEmpty)
                _OwnershipSubsection(
                  label: '미획득',
                  count: unowned.length,
                  accent: Colors.black38,
                  defs: unowned,
                  equippedId: equippedId,
                  levelOf: levelOf,
                  onTapCard: onTapCard,
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _OwnershipSubsection extends StatelessWidget {
  final String label;
  final int count;
  final Color accent;
  final List<SwordDef> defs;
  final String? equippedId;
  final int Function(String id) levelOf;
  final void Function(SwordDef def) onTapCard;

  const _OwnershipSubsection({
    required this.label,
    required this.count,
    required this.accent,
    required this.defs,
    required this.equippedId,
    required this.levelOf,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$label  $count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.7,
            ),
            itemCount: defs.length,
            itemBuilder: (context, i) {
              final def = defs[i];
              final level = levelOf(def.id);
              final owned = level > 0;
              final equipped = equippedId == def.id;
              return _SwordCard(
                def: def,
                level: level,
                owned: owned,
                equipped: equipped,
                onTap: () => onTapCard(def),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SwordCard extends StatelessWidget {
  final SwordDef def;
  final int level;
  final bool owned;
  final bool equipped;
  final VoidCallback onTap;

  const _SwordCard({
    required this.def,
    required this.level,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: equipped
                  ? AppColors.coral
                  : def.tier.color.withValues(alpha: 0.4),
              width: equipped ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: def.tier.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  def.tier.label,
                  style: TextStyle(
                    color: def.tier.color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: SwordPreview(
                  visual: def.visual,
                  locked: !owned,
                  size: 52,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                owned ? def.name : '???',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: owned
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                ),
              ),
              if (owned)
                Text(
                  equipped ? '장착 · L$level' : 'L$level',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: equipped ? AppColors.coral : Colors.black54,
                  ),
                )
              else
                const Text(
                  '미획득',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black38,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwordDetailSheet extends ConsumerWidget {
  final SwordDef def;
  const _SwordDetailSheet({required this.def});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final level = game.swordLevel(def.id);
    final owned = level > 0;
    final equipped = game.equippedSwordId == def.id;
    final role = swordFormationRole(def);
    final region = swordHomeRegion(def);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SwordPreview(visual: def.visual, locked: !owned, size: 90),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: def.tier.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${def.tier.label} · ${def.tier.korLabel}',
                        style: TextStyle(
                          color: def.tier.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      owned ? def.name : '???',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      owned ? def.description : '소환해서 정보를 확인하세요',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _MiniTag(
                          label: role.label,
                          color: role.color,
                          icon: role.icon,
                        ),
                        _MiniTag(
                          label: '검세권 ${region.shortName}',
                          color: region.accent,
                          icon: Icons.location_city,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (owned) ...[
            _StatRow(
              label: '장착 시 터치 배율',
              value: '×${def.tapMultAt(level).toStringAsFixed(2)}',
              sub: level < SwordDef.maxLevel
                  ? '최대 Lv ${SwordDef.maxLevel}: ×${def.tapMultAt(SwordDef.maxLevel).toStringAsFixed(2)}'
                  : '최대 레벨 달성',
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: '장착 시 DPS 배율',
              value: '×${def.dpsMultAt(level).toStringAsFixed(2)}',
              sub: level < SwordDef.maxLevel
                  ? '최대 Lv ${SwordDef.maxLevel}: ×${def.dpsMultAt(SwordDef.maxLevel).toStringAsFixed(2)}'
                  : '최대 레벨 달성',
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: '보유 효과 (장착 안해도 적용)',
              value: '+${(def.ownedBonusAt(level) * 100).toStringAsFixed(2)}%',
              sub: level < SwordDef.maxLevel
                  ? '최대 Lv ${SwordDef.maxLevel}: +${(def.ownedBonusAt(SwordDef.maxLevel) * 100).toStringAsFixed(2)}% — 터치·동료·초월 모두에 적용'
                  : '터치·동료·초월(초당 수입) 모두에 적용',
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: '레벨',
              value: 'Lv $level / ${SwordDef.maxLevel}',
              sub: level < SwordDef.maxLevel ? '중복 획득 시 자동 레벨업' : '',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: equipped
                  ? null
                  : () {
                      ref.read(gameProvider.notifier).equipSword(def.id);
                      Navigator.of(context).pop();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                minimumSize: const Size.fromHeight(50),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: Text(
                equipped ? '장착 중' : '장착하기',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DismantleButton(def: def, level: level, equipped: equipped),
          ] else ...[
            const _StatRow(
              label: '장착 시 터치 배율',
              value: '?',
              sub: '소환 후 표시',
            ),
            const SizedBox(height: 8),
            const _StatRow(
              label: '장착 시 DPS 배율',
              value: '?',
              sub: '소환 후 표시',
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: '보유 효과',
              value: '+${(def.tier.ownedBonusBase * 100).toStringAsFixed(2)}%',
              sub: '획득 즉시 터치·동료·초월(초당 수입) 모두에 적용 (Lv 1 기준)',
            ),
          ],
        ],
      ),
    );
  }
}

class _DismantleButton extends ConsumerWidget {
  final SwordDef def;
  final int level;
  final bool equipped;
  const _DismantleButton({
    required this.def,
    required this.level,
    required this.equipped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameProvider.notifier);
    final refund = notifier.dismantleRefund(def.id);
    final disabled = equipped || refund <= 0;
    final hint =
        equipped ? '장착 중인 검은 분해할 수 없어요' : '분해 시 정수 +$refund (Lv $level 기준)';
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: disabled ? null : () => _confirm(context, ref, refund),
          icon: const Icon(Icons.recycling, size: 18),
          label: Text('분해 (+$refund 정수)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: const Color(0xFF7C4DFF),
            side: BorderSide(
              color: disabled
                  ? Colors.grey.shade400
                  : const Color(0xFF7C4DFF).withValues(alpha: 0.6),
              width: 1.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, int refund) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${def.name} 분해'),
        content: Text(
          '이 검은 컬렉션에서 영구 제거되고, 정수 +$refund 가 지급돼요.\n'
          '되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
            ),
            child: const Text('분해'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final granted = ref.read(gameProvider.notifier).dismantleSword(def.id);
    if (granted > 0 && context.mounted) {
      Navigator.of(context).pop(); // close detail sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${def.name} 분해 · 정수 +$granted'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final String sub;

  const _StatRow({
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.deepCoral,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionHubView extends ConsumerStatefulWidget {
  const _MissionHubView();

  @override
  ConsumerState<_MissionHubView> createState() => _MissionHubViewState();
}

class _MissionHubViewState extends ConsumerState<_MissionHubView> {
  bool _dailyExpanded = true;
  bool _weeklyExpanded = true;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final daily = game.dailyMissions;
    final weekly = game.weeklyMissions;
    final dailyDone = daily.where((m) => m.done).length;
    final weeklyDone = weekly.where((m) => m.done).length;
    final claimable = [
      ...daily,
      ...weekly,
    ].where((m) => m.done && !m.claimed).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MissionProgressCard(
            dailyDone: dailyDone,
            dailyTotal: daily.length,
            weeklyDone: weeklyDone,
            weeklyTotal: weekly.length,
            claimable: claimable,
            onClaimAll: claimable == 0
                ? null
                : () {
                    final r = notifier.claimAllMissions();
                    if (r.count > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '미션 ${r.count}개 일괄 수령 · 정수 +${r.essence} · 코인 +${r.coins}',
                          ),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
          ),
          const SizedBox(height: 12),
          _MissionSection(
            title: '오늘의 미션',
            accent: const Color(0xFF00897B),
            missions: daily,
            expanded: _dailyExpanded,
            onToggle: () => setState(() => _dailyExpanded = !_dailyExpanded),
            onClaim: (id) => notifier.claimMission(id, daily: true),
          ),
          const SizedBox(height: 10),
          _MissionSection(
            title: '주간 미션',
            accent: const Color(0xFF7E57C2),
            missions: weekly,
            expanded: _weeklyExpanded,
            onToggle: () => setState(() => _weeklyExpanded = !_weeklyExpanded),
            onClaim: (id) => notifier.claimMission(id, daily: false),
          ),
        ],
      ),
    );
  }
}

class _MissionProgressCard extends StatelessWidget {
  final int dailyDone;
  final int dailyTotal;
  final int weeklyDone;
  final int weeklyTotal;
  final int claimable;
  final VoidCallback? onClaimAll;
  const _MissionProgressCard({
    required this.dailyDone,
    required this.dailyTotal,
    required this.weeklyDone,
    required this.weeklyTotal,
    required this.claimable,
    required this.onClaimAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.mint.withValues(alpha: 0.9),
            const Color(0xFF7E57C2).withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '미션 보드',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '일일 $dailyDone/$dailyTotal · 주간 $weeklyDone/$weeklyTotal',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  claimable > 0 ? '수령 가능 보상 $claimable개' : '현재 수령 가능한 보상이 없습니다',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton(
                onPressed: onClaimAll,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.deepCoral,
                  minimumSize: const Size(96, 36),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.25),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                ),
                child: const Text(
                  '전체 수령',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissionSection extends StatelessWidget {
  final String title;
  final Color accent;
  final List<MissionView> missions;
  final bool expanded;
  final VoidCallback onToggle;
  final bool Function(String id) onClaim;
  const _MissionSection({
    required this.title,
    required this.accent,
    required this.missions,
    required this.expanded,
    required this.onToggle,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final done = missions.where((m) => m.done).length;
    final claimable = missions.where((m) => m.done && !m.claimed).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$done / ${missions.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: accent.withValues(alpha: 0.7),
                    ),
                  ),
                  if (claimable > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.coral,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '수령 $claimable',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 6),
            for (final m in missions)
              _MissionTaskTile(
                mission: m,
                accent: accent,
                onClaim: () => onClaim(m.id),
              ),
          ],
        ],
      ),
    );
  }
}

class _MissionTaskTile extends StatelessWidget {
  final MissionView mission;
  final Color accent;
  final VoidCallback onClaim;
  const _MissionTaskTile({
    required this.mission,
    required this.accent,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (mission.progress / mission.target).clamp(0.0, 1.0);
    final claimable = mission.done && !mission.claimed;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mission.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (mission.claimed)
                const Text(
                  '수령완료',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                )
              else if (claimable)
                FilledButton(
                  onPressed: onClaim,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    minimumSize: const Size(58, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text(
                    '수령',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            mission.description,
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${mission.progress}/${mission.target} · 정수 +${mission.rewardEssence} · 코인 +${mission.rewardPrestigeCoins}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementHubView extends ConsumerStatefulWidget {
  const _AchievementHubView();

  @override
  ConsumerState<_AchievementHubView> createState() =>
      _AchievementHubViewState();
}

enum _AchKind { milestones, repeating }

class _AchievementHubViewState extends ConsumerState<_AchievementHubView> {
  AchievementCategory? _filter;
  _AchKind _kind = _AchKind.milestones;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final achCtx = game.achContext();
    final milestoneTotal = achievementCatalog.length;
    final milestoneUnlocked = game.unlockedAchievements.length;

    // Repeating-achievement aggregate stats (clears across all tracks).
    var totalClears = 0;
    for (final def in repeatingAchievementCatalog) {
      totalClears += game.repeatingAchievementStages[def.id] ?? 0;
    }

    final filteredMilestones = _filter == null
        ? achievementCatalog
        : achievementCatalog.where((a) => a.category == _filter).toList();
    final filteredRepeats = _filter == null
        ? repeatingAchievementCatalog
        : repeatingAchievementCatalog
            .where((r) => r.category == _filter)
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '마일스톤 진행도',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$milestoneUnlocked / $milestoneTotal',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '반복 도전 클리어',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$totalClears 단계',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: milestoneTotal == 0
                        ? 0
                        : milestoneUnlocked / milestoneTotal,
                    minHeight: 8,
                    backgroundColor: Colors.black12,
                    valueColor: const AlwaysStoppedAnimation(AppColors.coral),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _AchKindToggle(
                  label: '마일스톤',
                  count: milestoneTotal,
                  selected: _kind == _AchKind.milestones,
                  onTap: () => setState(() => _kind = _AchKind.milestones),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AchKindToggle(
                  label: '반복 도전',
                  count: repeatingAchievementCatalog.length,
                  selected: _kind == _AchKind.repeating,
                  onTap: () => setState(() => _kind = _AchKind.repeating),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _AchievementCategoryChip(
                label: '전체',
                color: AppColors.coral,
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final cat in AchievementCategory.values)
                _AchievementCategoryChip(
                  label: cat.label,
                  color: cat.color,
                  selected: _filter == cat,
                  onTap: () => setState(() => _filter = cat),
                ),
            ],
          ),
        ),
        Expanded(
          child: _kind == _AchKind.milestones
              ? ListView.builder(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: filteredMilestones.length,
                  itemBuilder: (context, i) {
                    final def = filteredMilestones[i];
                    final unlocked = game.isAchievementUnlocked(def.id);
                    final progress = def.progress(achCtx);
                    return _AchievementHubTile(
                      def: def,
                      unlocked: unlocked,
                      progress: progress,
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: filteredRepeats.length,
                  itemBuilder: (context, i) {
                    final def = filteredRepeats[i];
                    final cleared =
                        game.repeatingAchievementStages[def.id] ?? 0;
                    final progress = repeatingProgress(def, achCtx, cleared);
                    return _RepeatingAchTile(progress: progress);
                  },
                ),
        ),
      ],
    );
  }
}

class _AchKindToggle extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _AchKindToggle({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.coral : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.coral
                  : AppColors.coral.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.deepCoral,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.deepCoral.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeatingAchTile extends StatelessWidget {
  final RepeatingAchProgress progress;
  const _RepeatingAchTile({required this.progress});

  @override
  Widget build(BuildContext context) {
    final def = progress.def;
    final color = def.color;
    final cleared = progress.clearedStages;
    final stageLabel = _romanNumeral(progress.nextStage);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
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
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(def.icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${def.name} $stageLabel',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '클리어 $cleared',
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '목표 ${_compact(progress.currentStageTarget)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.ratio,
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${_compact(progress.currentValue)} / ${_compact(progress.currentStageTarget)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.diamond,
                        size: 12, color: Color(0xFF7C4DFF)),
                    const SizedBox(width: 2),
                    Text(
                      '+${progress.rewardOnNextClear}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C4DFF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _compact(double v) {
    if (v >= 1e18) return '${(v / 1e18).toStringAsFixed(2)}Qi';
    if (v >= 1e15) return '${(v / 1e15).toStringAsFixed(2)}aa';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(2)}K';
    return v.floor().toString();
  }

  static const _roman = <int, String>{
    1000: 'M',
    900: 'CM',
    500: 'D',
    400: 'CD',
    100: 'C',
    90: 'XC',
    50: 'L',
    40: 'XL',
    10: 'X',
    9: 'IX',
    5: 'V',
    4: 'IV',
    1: 'I',
  };

  static String _romanNumeral(int n) {
    if (n <= 0) return '';
    if (n > 3999) return '$n';
    var v = n;
    final buf = StringBuffer();
    for (final entry in _roman.entries) {
      while (v >= entry.key) {
        buf.write(entry.value);
        v -= entry.key;
      }
    }
    return buf.toString();
  }
}

class _AchievementCategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _AchievementCategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withValues(alpha: selected ? 1.0 : 0.3),
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementHubTile extends StatelessWidget {
  final AchievementDef def;
  final bool unlocked;
  final AchProgress progress;
  const _AchievementHubTile({
    required this.def,
    required this.unlocked,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final color = def.category.color;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unlocked ? color : Colors.black12,
          width: unlocked ? 2 : 1,
        ),
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
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: unlocked ? 0.25 : 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              def.category.icon,
              color: unlocked ? color : Colors.black26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        def.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: unlocked ? Colors.black87 : Colors.black54,
                        ),
                      ),
                    ),
                    if (unlocked)
                      Icon(Icons.check_circle, color: color, size: 18),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  def.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.ratio,
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _progressLabel(progress),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.diamond,
                        size: 12, color: Color(0xFF7C4DFF)),
                    const SizedBox(width: 2),
                    Text(
                      '+${def.essenceReward}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C4DFF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _progressLabel(AchProgress p) {
    if (p.target == 1) return p.done ? '완료' : '미완료';
    final cur = _compact(p.current);
    final tgt = _compact(p.target);
    return '$cur / $tgt';
  }

  static String _compact(double v) {
    if (v >= 1e18) return '${(v / 1e18).toStringAsFixed(2)}Qi';
    if (v >= 1e15) return '${(v / 1e15).toStringAsFixed(2)}Qa';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(2)}K';
    return v.floor().toString();
  }
}

Future<void> _buyPremiumProduct(
  BuildContext context,
  WidgetRef ref,
  String productId,
) async {
  final result =
      ref.read(gameProvider.notifier).purchasePremiumProduct(productId);
  if (!context.mounted) return;
  if (result.bonusSummon != null) {
    await showSummonDialog(context, [result.bonusSummon!]);
  }
  if (!context.mounted) return;
  _toast(context, result.message);
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _PremiumStoreView extends ConsumerWidget {
  const _PremiumStoreView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final products = {
      for (final product in premiumProducts) product.id: product
    };

    List<PremiumProductDef> pick(List<String> ids) => [
          for (final id in ids)
            if (products[id] != null) products[id]!,
        ];

    final recommended = pick([
      if (!notifier.firstPurchasePackageClaimed) premiumFirstPurchaseProductId,
      if (!notifier.starterPackagePurchased) premiumStarterPackageProductId,
      premiumAdRemovalProductId,
    ]);

    final sections = <_StoreSectionData>[
      _StoreSectionData(
        title: '추천',
        subtitle: '초반 성장과 편의 혜택',
        products: recommended,
      ),
      _StoreSectionData(
        title: '패스',
        subtitle: '매일 받는 정수 보급',
        products: pick([
          premiumMonthlyEssencePassProductId,
          premiumSeasonPassProductId,
        ]),
      ),
      _StoreSectionData(
        title: '정수',
        subtitle: '필요할 때 바로 충전',
        products: pick([
          premiumEssenceSmallProductId,
          premiumEssenceMediumProductId,
          premiumEssenceLargeProductId,
          premiumEssenceXLargeProductId,
        ]),
      ),
      _StoreSectionData(
        title: '패키지',
        subtitle: '큰 폭의 성장 묶음',
        products: pick([premiumMasterPackageProductId]),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StoreHeaderPanel(
            essence: game.essence,
            monthlyLabel: notifier.hasActiveMonthlyPass
                ? '월정액 D-${notifier.monthlyPassDaysRemaining}'
                : '월정액 없음',
            seasonLabel: notifier.hasActiveSeasonPass
                ? '시즌 D-${notifier.seasonPassDaysRemaining}'
                : '시즌 없음',
            adLabel: notifier.adsRemoved ? '광고 제거 적용' : '광고 포함',
          ),
          if (notifier.hasActiveMonthlyPass || notifier.hasActiveSeasonPass)
            const SizedBox(height: 16),
          if (notifier.hasActiveMonthlyPass || notifier.hasActiveSeasonPass)
            _PassRewardPanel(
              monthlyClaimable: notifier.monthlyPassClaimableEssence,
              monthlyDaysRemaining: notifier.monthlyPassDaysRemaining,
              seasonClaimable: notifier.seasonPassClaimableEssence,
              seasonDaysRemaining: notifier.seasonPassDaysRemaining,
              seasonWeeklyAvailable: notifier.seasonPassWeeklyAvailable,
              onClaimMonthly: () {
                final amount =
                    ref.read(gameProvider.notifier).claimMonthlyPassEssence();
                _toast(
                  context,
                  amount > 0 ? '정수 $amount개를 수령했어요' : '오늘 받을 정수가 없어요',
                );
              },
              onClaimSeasonDaily: () {
                final amount = ref
                    .read(gameProvider.notifier)
                    .claimSeasonPassDailyEssence();
                _toast(
                  context,
                  amount > 0 ? '정수 $amount개를 수령했어요' : '오늘 받을 정수가 없어요',
                );
              },
              onClaimSeasonWeekly: () {
                final amount = ref
                    .read(gameProvider.notifier)
                    .claimSeasonPassWeeklyEssence();
                _toast(
                  context,
                  amount > 0 ? '주간 보너스 정수 $amount개' : '아직 받을 수 없어요',
                );
              },
            ),
          for (final section in sections)
            if (section.products.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreSection(section: section, notifier: notifier, ref: ref),
            ],
        ],
      ),
    );
  }
}

class _StoreHeaderPanel extends StatelessWidget {
  final int essence;
  final String monthlyLabel;
  final String seasonLabel;
  final String adLabel;

  const _StoreHeaderPanel({
    required this.essence,
    required this.monthlyLabel,
    required this.seasonLabel,
    required this.adLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.coral.withValues(alpha: 0.22),
        ),
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
                  color: AppColors.deepCoral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront,
                  color: AppColors.deepCoral,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '상점',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '정수, 패스, 패키지',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
              _EssencePill(amount: essence),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StoreBadge(
                label: monthlyLabel,
                icon: Icons.calendar_month,
                color: Colors.teal.shade700,
              ),
              _StoreBadge(
                label: seasonLabel,
                icon: Icons.workspace_premium,
                color: const Color(0xFF7E57C2),
              ),
              _StoreBadge(
                label: adLabel,
                icon: Icons.block,
                color: const Color(0xFF546E7A),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EssencePill extends StatelessWidget {
  final int amount;
  const _EssencePill({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond, color: Colors.teal.shade700, size: 16),
          const SizedBox(width: 5),
          Text(
            '$amount',
            style: TextStyle(
              color: Colors.teal.shade800,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassRewardPanel extends StatelessWidget {
  final int monthlyClaimable;
  final int monthlyDaysRemaining;
  final int seasonClaimable;
  final int seasonDaysRemaining;
  final bool seasonWeeklyAvailable;
  final VoidCallback onClaimMonthly;
  final VoidCallback onClaimSeasonDaily;
  final VoidCallback onClaimSeasonWeekly;

  const _PassRewardPanel({
    required this.monthlyClaimable,
    required this.monthlyDaysRemaining,
    required this.seasonClaimable,
    required this.seasonDaysRemaining,
    required this.seasonWeeklyAvailable,
    required this.onClaimMonthly,
    required this.onClaimSeasonDaily,
    required this.onClaimSeasonWeekly,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (monthlyDaysRemaining > 0)
        _ClaimCard(
          title: '월간 보급',
          value: monthlyClaimable > 0 ? '+$monthlyClaimable' : '완료',
          status: 'D-$monthlyDaysRemaining',
          icon: Icons.calendar_today,
          color: Colors.teal.shade700,
          enabled: monthlyClaimable > 0,
          onPressed: onClaimMonthly,
        ),
      if (seasonDaysRemaining > 0)
        _ClaimCard(
          title: '시즌 일일',
          value: seasonClaimable > 0 ? '+$seasonClaimable' : '완료',
          status: 'D-$seasonDaysRemaining',
          icon: Icons.auto_awesome,
          color: const Color(0xFF7E57C2),
          enabled: seasonClaimable > 0,
          onPressed: onClaimSeasonDaily,
        ),
      if (seasonDaysRemaining > 0)
        _ClaimCard(
          title: '시즌 주간',
          value: '+$seasonPassWeeklyEssence',
          status: seasonWeeklyAvailable ? '수령 가능' : '대기',
          icon: Icons.card_giftcard,
          color: AppColors.deepCoral,
          enabled: seasonWeeklyAvailable,
          onPressed: onClaimSeasonWeekly,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StoreSectionTitle(title: '패스 보상', subtitle: '받을 수 있는 정수'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 620;
            final width = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ClaimCard extends StatelessWidget {
  final String title;
  final String value;
  final String status;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _ClaimCard({
    required this.title,
    required this.value,
    required this.status,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rewardText = value.startsWith('+') ? '$value 정수' : value;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$rewardText · $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('수령'),
          ),
        ],
      ),
    );
  }
}

class _StoreSectionData {
  final String title;
  final String subtitle;
  final List<PremiumProductDef> products;

  const _StoreSectionData({
    required this.title,
    required this.subtitle,
    required this.products,
  });
}

class _StoreSection extends StatelessWidget {
  final _StoreSectionData section;
  final GameNotifier notifier;
  final WidgetRef ref;

  const _StoreSection({
    required this.section,
    required this.notifier,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StoreSectionTitle(title: section.title, subtitle: section.subtitle),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 720;
            final gap = twoColumns ? 12.0 : 10.0;
            final width = twoColumns
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: 10,
              children: [
                for (final product in section.products)
                  SizedBox(
                    width: width,
                    child: _StoreProductCard(
                      product: product,
                      meta: _storeProductMeta(product.id),
                      status: _storeProductStatus(product.id, notifier),
                      enabled: _storeProductEnabled(product.id, notifier),
                      onPressed: () =>
                          _buyPremiumProduct(context, ref, product.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StoreSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StoreSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _StoreProductMeta {
  final IconData icon;
  final Color color;
  final String summary;
  final List<String> badges;

  const _StoreProductMeta({
    required this.icon,
    required this.color,
    required this.summary,
    required this.badges,
  });
}

class _StoreProductCard extends StatelessWidget {
  final PremiumProductDef product;
  final _StoreProductMeta meta;
  final String status;
  final bool enabled;
  final VoidCallback onPressed;

  const _StoreProductCard({
    required this.product,
    required this.meta,
    required this.status,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: meta.color.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(meta.icon, color: meta.color, size: 24),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StoreBadge(
                          label: status,
                          icon: enabled ? Icons.local_offer : Icons.check,
                          color: meta.color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      meta.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final badge in meta.badges)
                _StoreBadge(label: badge, icon: Icons.check, color: meta.color),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  product.priceLabel,
                  style: TextStyle(
                    color: meta.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: enabled ? onPressed : null,
                icon:
                    Icon(enabled ? Icons.shopping_bag : Icons.check, size: 16),
                label: Text(enabled ? '구매' : '보유 중'),
                style: FilledButton.styleFrom(
                  backgroundColor: meta.color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoreBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StoreBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

_StoreProductMeta _storeProductMeta(String productId) {
  return switch (productId) {
    premiumAdRemovalProductId => const _StoreProductMeta(
        icon: Icons.block,
        color: Color(0xFF546E7A),
        summary: '전면 광고 OFF · 광고 보상 즉시 수령',
        badges: ['영구 혜택', '편의'],
      ),
    premiumMonthlyEssencePassProductId => _StoreProductMeta(
        icon: Icons.calendar_month,
        color: Colors.teal.shade700,
        summary: '즉시 300 · 매일 120 정수',
        badges: const ['30일', '누적 보상'],
      ),
    premiumStarterPackageProductId => const _StoreProductMeta(
        icon: Icons.inventory_2,
        color: AppColors.deepCoral,
        summary: '정수 1,400 · SR+ 검 · 30분 부스터',
        badges: ['초반 추천', '1회'],
      ),
    premiumFirstPurchaseProductId => const _StoreProductMeta(
        icon: Icons.card_giftcard,
        color: Color(0xFF5E35B1),
        summary: '정수 500 · SR 확정권 · 첫 결제 보너스',
        badges: ['한정', '1회'],
      ),
    premiumEssenceSmallProductId =>
      _essenceMeta('정수 110', Colors.teal.shade600),
    premiumEssenceMediumProductId =>
      _essenceMeta('정수 380', const Color(0xFF00897B)),
    premiumEssenceLargeProductId =>
      _essenceMeta('정수 1,200', const Color(0xFF00796B)),
    premiumEssenceXLargeProductId =>
      _essenceMeta('정수 2,800', const Color(0xFF00695C)),
    premiumSeasonPassProductId => const _StoreProductMeta(
        icon: Icons.workspace_premium,
        color: Color(0xFF7E57C2),
        summary: '60일 매일 정수 · 주간 600 보너스',
        badges: ['장기 효율', '패스'],
      ),
    premiumMasterPackageProductId => const _StoreProductMeta(
        icon: Icons.auto_awesome,
        color: Color(0xFFAD6800),
        summary: '정수 7,500 · UR 검 · 보호권 10',
        badges: ['최대 묶음', '1회'],
      ),
    _ => const _StoreProductMeta(
        icon: Icons.storefront,
        color: AppColors.coral,
        summary: '상점 상품',
        badges: ['상품'],
      ),
  };
}

_StoreProductMeta _essenceMeta(String summary, Color color) {
  return _StoreProductMeta(
    icon: Icons.diamond,
    color: color,
    summary: summary,
    badges: const ['즉시 지급', '정수'],
  );
}

String _storeProductStatus(String productId, GameNotifier notifier) {
  return switch (productId) {
    premiumAdRemovalProductId => notifier.adsRemoved ? '완료' : '영구',
    premiumMonthlyEssencePassProductId => notifier.hasActiveMonthlyPass
        ? 'D-${notifier.monthlyPassDaysRemaining}'
        : '30일',
    premiumSeasonPassProductId => notifier.hasActiveSeasonPass
        ? 'D-${notifier.seasonPassDaysRemaining}'
        : '60일',
    premiumStarterPackageProductId =>
      notifier.starterPackagePurchased ? '완료' : '1회',
    premiumFirstPurchaseProductId =>
      notifier.firstPurchasePackageClaimed ? '완료' : '1회',
    premiumMasterPackageProductId =>
      notifier.masterPackagePurchased ? '완료' : '1회',
    _ => '즉시',
  };
}

bool _storeProductEnabled(String productId, GameNotifier notifier) {
  return switch (productId) {
    premiumAdRemovalProductId => !notifier.adsRemoved,
    premiumStarterPackageProductId => !notifier.starterPackagePurchased,
    premiumFirstPurchaseProductId => !notifier.firstPurchasePackageClaimed,
    premiumMasterPackageProductId => !notifier.masterPackagePurchased,
    _ => true,
  };
}

class _SummonView extends ConsumerWidget {
  const _SummonView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final pityRemaining = pityThreshold - game.summonsSinceHighRare;
    final summonRateLevel = summonRateLevelFor(game.totalSummons);
    final summonRateToNext = summonsToNextRateLevel(game.totalSummons);
    final summonRates = summonRatesForTotalSummons(game.totalSummons);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.coral.withValues(alpha: 0.85),
                  const Color(0xFF7C4DFF).withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '검을 소환하여 수집하세요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '중복 획득은 자동 레벨업 (최대 Lv ${SwordDef.maxLevel})',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '천장 — $pityThreshold회 내에 SR+ 미획득 시 다음 소환 확정',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '남은 회차: $pityRemaining회',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '소환 레벨 Lv$summonRateLevel / $summonRateMaxLevel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  summonRateLevel >= summonRateMaxLevel
                      ? '누적 소환 ${game.totalSummons}회 · 확률 보정 최대치 도달'
                      : '누적 소환 ${game.totalSummons}회 · 다음 레벨까지 $summonRateToNext회',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SummonButton(
            label: '1연 소환',
            cost: summonCostSingle,
            essence: game.essence,
            primary: false,
            onTap: () async {
              final r = notifier.summonOne();
              if (r != null) {
                await showSummonDialog(context, [r]);
              }
            },
          ),
          const SizedBox(height: 10),
          _SummonButton(
            label: '10연 소환 (마지막 R+ 확정)',
            cost: summonCostTen,
            essence: game.essence,
            primary: true,
            onTap: () async {
              final r = notifier.summonTen();
              if (r != null) {
                await showSummonDialog(context, r);
              }
            },
          ),
          const SizedBox(height: 10),
          _SummonButton(
            label: '100연 소환 (10회마다 R+ 확정)',
            cost: summonCostHundred,
            essence: game.essence,
            primary: false,
            onTap: () async {
              final r = notifier.summonHundred();
              if (r != null) {
                await showSummonDialog(context, r);
              }
            },
          ),
          const SizedBox(height: 20),
          _RateTable(
            rates: summonRates,
            rateLevel: summonRateLevel,
            toNextLevel: summonRateToNext,
          ),
          const SizedBox(height: 20),
          _EssenceSources(),
        ],
      ),
    );
  }
}

class _SummonButton extends StatelessWidget {
  final String label;
  final int cost;
  final int essence;
  final bool primary;
  final VoidCallback onTap;

  const _SummonButton({
    required this.label,
    required this.cost,
    required this.essence,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = essence >= cost;
    final bg = enabled
        ? (primary ? AppColors.coral : Colors.white)
        : Colors.grey.shade300;
    final fg = enabled
        ? (primary ? Colors.white : AppColors.deepCoral)
        : Colors.grey.shade600;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: primary
                ? null
                : Border.all(
                    color: AppColors.coral.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.diamond, color: fg, size: 18),
              const SizedBox(width: 4),
              Text(
                '$cost',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateTable extends StatelessWidget {
  final Map<SwordTier, double> rates;
  final int rateLevel;
  final int toNextLevel;

  const _RateTable({
    required this.rates,
    required this.rateLevel,
    required this.toNextLevel,
  });

  String _rateText(SwordTier tier) {
    final rate = rates[tier] ?? tier.rate;
    final delta = rate - tier.rate;
    if (delta.abs() > 0.0001) {
      final sign = delta >= 0 ? '+' : '';
      return '${rate.toStringAsFixed(2)}% ($sign${delta.toStringAsFixed(2)})';
    }
    return '${rate.toStringAsFixed(2)}%';
  }

  @override
  Widget build(BuildContext context) {
    final isMaxLevel = rateLevel >= summonRateMaxLevel;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '등급별 확률',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isMaxLevel
                ? '소환 레벨 Lv$rateLevel (최대)'
                : '소환 레벨 Lv$rateLevel · 다음 레벨까지 $toNextLevel회',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          for (final tier in SwordTier.values.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tier.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tier.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: tier.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tier.korLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    _rateText(tier),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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

class _EssenceSources extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '정수 획득처',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          const _SourceRow(
            icon: Icons.upgrade,
            text: '동료 Lv 25 / 50 / 100 / 200 달성 시',
          ),
          const _SourceRow(
            icon: Icons.calendar_month,
            text: '일일 출석 보너스 (5~60 정수)',
          ),
          const _SourceRow(
            icon: Icons.emoji_events,
            text: '업적 해제 시',
          ),
          const _SourceRow(
            icon: Icons.recycling,
            text: '검 분해 시 (등급·레벨에 비례)',
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SourceRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwordSetsView extends ConsumerWidget {
  const _SwordSetsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final completed = <SwordSet>[];
    final inProgress = <SwordSet>[];
    final untouched = <SwordSet>[];
    for (final s in swordSets) {
      final ownedCount = s.swordIds.where((id) => game.ownsSword(id)).length;
      if (ownedCount == s.swordIds.length) {
        completed.add(s);
      } else if (ownedCount > 0) {
        inProgress.add(s);
      } else {
        untouched.add(s);
      }
    }
    final ordered = [...completed, ...inProgress, ...untouched];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: ordered.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SwordSetsHeader(
            completed: completed.length,
            total: swordSets.length,
          );
        }
        final s = ordered[i - 1];
        return _SwordSetCard(set: s, game: game);
      },
    );
  }
}

class _SwordSetsHeader extends StatelessWidget {
  final int completed;
  final int total;
  const _SwordSetsHeader({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFEC407A).withValues(alpha: 0.85),
            const Color(0xFF7C4DFF).withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '검 세트 컬렉션',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$completed / $total 세트 완성',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '같은 세트의 검을 모두 모으면 영구적으로 터치·DPS 배율이 증가합니다.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwordSetCard extends StatelessWidget {
  final SwordSet set;
  final GameState game;
  const _SwordSetCard({required this.set, required this.game});

  @override
  Widget build(BuildContext context) {
    final ownedIds = <String>[];
    final missingIds = <String>[];
    for (final id in set.swordIds) {
      if (game.ownsSword(id)) {
        ownedIds.add(id);
      } else {
        missingIds.add(id);
      }
    }
    final ratio = ownedIds.length / set.swordIds.length;
    final completed = ratio >= 1.0;
    final accent =
        completed ? const Color(0xFFEC407A) : const Color(0xFF7C4DFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: completed ? accent : Colors.black12,
          width: completed ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          set.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (completed)
                          Icon(Icons.check_circle, color: accent, size: 18),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      set.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${ownedIds.length} / ${set.swordIds.length}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: completed ? accent : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (set.tapBonus > 0)
                _BonusChip(
                  icon: Icons.touch_app,
                  label: '터치',
                  value: '+${(set.tapBonus * 100).toStringAsFixed(0)}%',
                  active: completed,
                ),
              if (set.tapBonus > 0 && set.dpsBonus > 0)
                const SizedBox(width: 6),
              if (set.dpsBonus > 0)
                _BonusChip(
                  icon: Icons.bolt,
                  label: 'DPS',
                  value: '+${(set.dpsBonus * 100).toStringAsFixed(0)}%',
                  active: completed,
                ),
              const Spacer(),
              if (!completed)
                Text(
                  '미보유 ${missingIds.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in set.swordIds)
                _SetSwordChip(
                  swordId: id,
                  owned: game.ownsSword(id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BonusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool active;
  const _BonusChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        active ? const Color(0xFFEC407A) : Colors.black.withValues(alpha: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: active ? 0.7 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetSwordChip extends StatelessWidget {
  final String swordId;
  final bool owned;
  const _SetSwordChip({required this.swordId, required this.owned});

  @override
  Widget build(BuildContext context) {
    final def = swordCatalog.firstWhere(
      (s) => s.id == swordId,
      orElse: () => swordCatalog.first,
    );
    final tierColor = def.tier.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: owned
            ? tierColor.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: owned ? tierColor.withValues(alpha: 0.6) : Colors.black12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            owned ? Icons.check : Icons.lock_outline,
            size: 11,
            color: owned ? tierColor : Colors.black38,
          ),
          const SizedBox(width: 4),
          Text(
            owned ? def.name : '???',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: owned ? tierColor : Colors.black38,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            def.tier.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: owned ? tierColor : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
