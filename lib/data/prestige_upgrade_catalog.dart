import 'package:flutter/material.dart';

import '../models/prestige_upgrade.dart';

const prestigeOverallUpgradeId = 'legacy_overall';

const prestigeUpgradeCatalog = <PrestigeUpgradeDef>[
  PrestigeUpgradeDef(
    id: prestigeOverallUpgradeId,
    name: '영구 각인',
    description: '전체 배율을 영구 강화합니다.',
    icon: Icons.auto_awesome,
    accent: Color(0xFF00695C),
    baseCost: 5,
    growthRate: 1.12,
    maxLevel: 9999,
    globalBonusPerLevel: 0.02,
  ),
  PrestigeUpgradeDef(
    id: 'legacy_tap',
    name: '검의 유산',
    description: '터치 위력을 영구 강화합니다.',
    icon: Icons.touch_app,
    accent: Color(0xFFFF7043),
    baseCost: 12,
    growthRate: 1.45,
    maxLevel: 40,
    tapBonusPerLevel: 0.12,
  ),
  PrestigeUpgradeDef(
    id: 'legacy_dps',
    name: '동력의 유산',
    description: 'DPS를 영구 강화합니다.',
    icon: Icons.bolt,
    accent: Color(0xFF26A69A),
    baseCost: 12,
    growthRate: 1.45,
    maxLevel: 40,
    dpsBonusPerLevel: 0.12,
  ),
  PrestigeUpgradeDef(
    id: 'legacy_all',
    name: '초월 핵심',
    description: '터치와 DPS를 모두 영구 강화합니다.',
    icon: Icons.auto_awesome,
    accent: Color(0xFFFFB300),
    baseCost: 40,
    growthRate: 1.70,
    maxLevel: 25,
    tapBonusPerLevel: 0.08,
    dpsBonusPerLevel: 0.08,
  ),
  PrestigeUpgradeDef(
    id: 'legacy_coin',
    name: '영혼 재순환',
    description: '환생 시 획득하는 코인을 늘립니다.',
    icon: Icons.currency_exchange,
    accent: Color(0xFF7C4DFF),
    baseCost: 20,
    growthRate: 1.60,
    maxLevel: 30,
    coinGainBonusPerLevel: 0.15,
  ),
];

PrestigeUpgradeDef prestigeUpgradeById(String id) =>
    prestigeUpgradeCatalog.firstWhere((u) => u.id == id);

double prestigeTapBonusFraction(Map<String, int> levels) {
  double total = 0;
  for (final def in prestigeUpgradeCatalog) {
    final lv = levels[def.id] ?? 0;
    total += def.tapBonusPerLevel * lv;
  }
  return total;
}

double prestigeDpsBonusFraction(Map<String, int> levels) {
  double total = 0;
  for (final def in prestigeUpgradeCatalog) {
    final lv = levels[def.id] ?? 0;
    total += def.dpsBonusPerLevel * lv;
  }
  return total;
}

double prestigeCoinGainBonusFraction(Map<String, int> levels) {
  double total = 0;
  for (final def in prestigeUpgradeCatalog) {
    final lv = levels[def.id] ?? 0;
    total += def.coinGainBonusPerLevel * lv;
  }
  return total;
}

double prestigeGlobalBonusFraction(Map<String, int> levels) {
  double total = 0;
  for (final def in prestigeUpgradeCatalog) {
    final lv = levels[def.id] ?? 0;
    total += def.globalBonusPerLevel * lv;
  }
  return total;
}
