import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Which tab in the upgrade screen owns this producer.
enum ProducerCategory { companion, transcendent }

class ProducerDef {
  static const milestones = <int>[25, 50, 100, 200];

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color accent;
  final double baseCost;
  final double baseDps;
  final double growthRate;
  final ProducerCategory category;

  const ProducerDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.accent,
    required this.baseCost,
    required this.baseDps,
    this.growthRate = 1.15,
    this.category = ProducerCategory.companion,
  });

  double costAt(int currentLevel) =>
      baseCost * math.pow(growthRate, currentLevel).toDouble();

  /// Total cost to buy [count] consecutive levels starting at [currentLevel].
  /// Geometric sum: baseCost * r^lv * (r^count - 1) / (r - 1)
  double costForNext(int currentLevel, int count) {
    if (count <= 0) return 0;
    final r = growthRate;
    return baseCost *
        math.pow(r, currentLevel).toDouble() *
        (math.pow(r, count).toDouble() - 1) /
        (r - 1);
  }

  /// Max affordable count given [gold] at [currentLevel].
  int maxAffordable(double gold, int currentLevel) {
    if (gold <= 0) return 0;
    final r = growthRate;
    final denom = baseCost * math.pow(r, currentLevel).toDouble();
    if (denom <= 0) return 0;
    final ratio = gold * (r - 1) / denom + 1;
    if (ratio <= 1) return 0;
    return (math.log(ratio) / math.log(r)).floor();
  }

  /// Cumulative milestone multiplier for a producer at [level].
  double milestoneMultiplier(int level) {
    int count = 0;
    for (final m in milestones) {
      if (level >= m) count++;
    }
    return math.pow(2, count).toDouble();
  }

  int? nextMilestone(int level) {
    for (final m in milestones) {
      if (level < m) return m;
    }
    return null;
  }

  double dpsAt(int level) => baseDps * level * milestoneMultiplier(level);
}
