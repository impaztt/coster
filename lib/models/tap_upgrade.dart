import 'dart:math' as math;
import 'package:flutter/material.dart';

class TapUpgradeDef {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color accent;
  final double baseCost;
  final double tapPowerPerLevel;
  final double growthRate;

  const TapUpgradeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.accent,
    required this.baseCost,
    required this.tapPowerPerLevel,
    this.growthRate = 1.10,
  });

  double costAt(int currentLevel) =>
      baseCost * math.pow(growthRate, currentLevel).toDouble();

  double costForNext(int currentLevel, int count) {
    if (count <= 0) return 0;
    final r = growthRate;
    return baseCost *
        math.pow(r, currentLevel).toDouble() *
        (math.pow(r, count).toDouble() - 1) /
        (r - 1);
  }

  int maxAffordable(double gold, int currentLevel) {
    if (gold <= 0) return 0;
    final r = growthRate;
    final denom = baseCost * math.pow(r, currentLevel).toDouble();
    if (denom <= 0) return 0;
    final ratio = gold * (r - 1) / denom + 1;
    if (ratio <= 1) return 0;
    return (math.log(ratio) / math.log(r)).floor();
  }
}
