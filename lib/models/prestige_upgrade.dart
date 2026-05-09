import 'dart:math' as math;
import 'package:flutter/material.dart';

class PrestigeUpgradeDef {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color accent;
  final int baseCost;
  final double growthRate;
  final int maxLevel;
  final double tapBonusPerLevel; // 0.10 = +10% tap/lv
  final double dpsBonusPerLevel; // 0.10 = +10% dps/lv
  final double coinGainBonusPerLevel; // 0.10 = +10% prestige coin gain/lv
  final double globalBonusPerLevel; // 0.02 = +2% to both tap/dps per lv

  const PrestigeUpgradeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.accent,
    required this.baseCost,
    required this.growthRate,
    required this.maxLevel,
    this.tapBonusPerLevel = 0,
    this.dpsBonusPerLevel = 0,
    this.coinGainBonusPerLevel = 0,
    this.globalBonusPerLevel = 0,
  });

  int costAt(int currentLevel) {
    if (currentLevel < 0) return baseCost;
    return (baseCost * math.pow(growthRate, currentLevel)).round();
  }
}
