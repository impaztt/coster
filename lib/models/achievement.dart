import 'package:flutter/material.dart';

import 'run_stats.dart';

enum AchievementCategory {
  tap,
  gold,
  dps,
  playtime,
  producer,
  swordCollect,
  swordLevel,
  summon,
  prestige,
  slime,
  combat,
  skill,
  daily,
  master,
  // v13: introduced with milestone expansion + new content surfaces.
  stocks,
  swordSets,
  collection,
  economy,
}

extension AchievementCategoryInfo on AchievementCategory {
  String get label => switch (this) {
        AchievementCategory.tap => '터치',
        AchievementCategory.gold => '골드',
        AchievementCategory.dps => 'DPS',
        AchievementCategory.playtime => '플레이 시간',
        AchievementCategory.producer => '동료',
        AchievementCategory.swordCollect => '검 수집',
        AchievementCategory.swordLevel => '검 강화',
        AchievementCategory.summon => '소환',
        AchievementCategory.prestige => '환생',
        AchievementCategory.slime => '슬라임',
        AchievementCategory.combat => '전투',
        AchievementCategory.skill => '스킬',
        AchievementCategory.daily => '일일',
        AchievementCategory.master => '마스터',
        AchievementCategory.stocks => '주식',
        AchievementCategory.swordSets => '세트',
        AchievementCategory.collection => '컬렉션',
        AchievementCategory.economy => '경제',
      };

  IconData get icon => switch (this) {
        AchievementCategory.tap => Icons.touch_app,
        AchievementCategory.gold => Icons.monetization_on,
        AchievementCategory.dps => Icons.bolt,
        AchievementCategory.playtime => Icons.timer,
        AchievementCategory.producer => Icons.group,
        AchievementCategory.swordCollect => Icons.collections,
        AchievementCategory.swordLevel => Icons.upgrade,
        AchievementCategory.summon => Icons.diamond,
        AchievementCategory.prestige => Icons.auto_awesome,
        AchievementCategory.slime => Icons.bubble_chart,
        AchievementCategory.combat => Icons.local_fire_department,
        AchievementCategory.skill => Icons.flash_on,
        AchievementCategory.daily => Icons.event_available,
        AchievementCategory.master => Icons.emoji_events,
        AchievementCategory.stocks => Icons.show_chart,
        AchievementCategory.swordSets => Icons.workspaces,
        AchievementCategory.collection => Icons.collections_bookmark,
        AchievementCategory.economy => Icons.savings,
      };

  Color get color => switch (this) {
        AchievementCategory.tap => const Color(0xFFFF7043),
        AchievementCategory.gold => const Color(0xFFFFB300),
        AchievementCategory.dps => const Color(0xFF00ACC1),
        AchievementCategory.playtime => const Color(0xFF7E57C2),
        AchievementCategory.producer => const Color(0xFF26A69A),
        AchievementCategory.swordCollect => const Color(0xFFE53935),
        AchievementCategory.swordLevel => const Color(0xFF8D6E63),
        AchievementCategory.summon => const Color(0xFF7C4DFF),
        AchievementCategory.prestige => const Color(0xFFFFCA28),
        AchievementCategory.slime => const Color(0xFFFFC107),
        AchievementCategory.combat => const Color(0xFFEF5350),
        AchievementCategory.skill => const Color(0xFF42A5F5),
        AchievementCategory.daily => const Color(0xFF66BB6A),
        AchievementCategory.master => const Color(0xFFD81B60),
        AchievementCategory.stocks => const Color(0xFFD32F2F),
        AchievementCategory.swordSets => const Color(0xFFEC407A),
        AchievementCategory.collection => const Color(0xFF5E35B1),
        AchievementCategory.economy => const Color(0xFF2E7D32),
      };
}

/// Progress snapshot returned by [AchievementDef.progress].
class AchProgress {
  final double current;
  final double target;
  const AchProgress(this.current, this.target);

  bool get done => current >= target;
  double get ratio =>
      target <= 0 ? 1 : (current / target).clamp(0.0, 1.0);
}

/// Generic game state view the achievement catalog uses. Keeps [AchievementDef]
/// decoupled from Riverpod / full GameState type.
class AchContext {
  final int totalTaps;
  final double lifetimeGold;
  final double maxDpsEver;
  final int playTimeSeconds;
  final Map<String, int> producerLevels;
  final int totalProducerLevels;
  final int ownedProducerCount;
  final int totalProducerCatalogCount;
  final Map<String, int> ownedSwords;
  final int ownedSwordCount;
  final int totalSwordCatalogCount;
  final bool ownsAnyR;
  final bool ownsAnySr;
  final bool ownsAnySsr;
  final bool ownsAnyLr;
  final bool ownsAnyUr;
  final int maxSwordLevel;
  final int maxedSwordCount;
  final int totalSummons;
  final int prestigeCount;
  final Map<String, int> prestigeUpgradeLevels;
  final int totalTapUpgradesBought;
  final bool hasEquippedSword;
  final int totalCrits;
  final int maxCombo;
  final int comboBurstCount;
  final int slimesDefeated;
  final int skillsUsed;
  final int boostersPurchased;
  final int maxDailyStreak;
  final int completedSetCount;
  // v13 — surfaces introduced with milestone expansion.
  final int unlockedRegionCount;
  final int regionsAtMaxOwnership;
  final int totalShareUnits;
  final double totalDividendsClaimed;
  final int totalStockTrades;
  final double totalGoldSpent;
  final int prestigeCoins;
  final int essence;
  // v13 — current-run scoped counters for challenge achievements.
  final RunStats run;

  const AchContext({
    required this.totalTaps,
    required this.lifetimeGold,
    required this.maxDpsEver,
    required this.playTimeSeconds,
    required this.producerLevels,
    required this.totalProducerLevels,
    required this.ownedProducerCount,
    required this.totalProducerCatalogCount,
    required this.ownedSwords,
    required this.ownedSwordCount,
    required this.totalSwordCatalogCount,
    required this.ownsAnyR,
    required this.ownsAnySr,
    required this.ownsAnySsr,
    required this.ownsAnyLr,
    required this.ownsAnyUr,
    required this.maxSwordLevel,
    required this.maxedSwordCount,
    required this.totalSummons,
    required this.prestigeCount,
    required this.prestigeUpgradeLevels,
    required this.totalTapUpgradesBought,
    required this.hasEquippedSword,
    required this.totalCrits,
    required this.maxCombo,
    required this.comboBurstCount,
    required this.slimesDefeated,
    required this.skillsUsed,
    required this.boostersPurchased,
    required this.maxDailyStreak,
    required this.completedSetCount,
    required this.unlockedRegionCount,
    required this.regionsAtMaxOwnership,
    required this.totalShareUnits,
    required this.totalDividendsClaimed,
    required this.totalStockTrades,
    required this.totalGoldSpent,
    required this.prestigeCoins,
    required this.essence,
    required this.run,
  });
}

class AchievementDef {
  final String id;
  final String name;
  final String description;
  final AchievementCategory category;
  final int essenceReward;
  final AchProgress Function(AchContext) progress;

  const AchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.essenceReward,
    required this.progress,
  });
}
