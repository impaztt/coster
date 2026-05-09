import 'package:flutter/material.dart';

import 'achievement.dart';

/// A "repeating" achievement defines an infinite ladder of stages built from
/// a single tracked metric. Each stage has its own target — once reached,
/// the player advances and a new stage with a higher bar appears. Stages
/// are not part of the milestone "completion %" — they're a long-tail
/// reward stream rather than a finite checklist.
class RepeatingAchievementDef {
  final String id;
  final String name; // base name; UI appends roman numeral / stage label
  final String description;
  final AchievementCategory category;
  final IconData icon;
  final Color color;
  // The current value of the tracked metric (e.g. totalTaps).
  final double Function(AchContext) current;
  // Target value for [stage] (1-based).
  final double Function(int stage) targetForStage;
  // Essence reward granted when [stage] is cleared.
  final int Function(int stage) rewardForStage;

  const RepeatingAchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.color,
    required this.current,
    required this.targetForStage,
    required this.rewardForStage,
  });
}

/// A snapshot view used by the UI: which stage is "current" (the next one
/// to clear), how the metric compares to that stage's target, and how many
/// stages have already been completed.
class RepeatingAchProgress {
  final RepeatingAchievementDef def;
  final int clearedStages; // 0 if none yet
  final double currentValue;
  final double currentStageTarget;
  final double previousStageTarget;
  final int rewardOnNextClear;

  const RepeatingAchProgress({
    required this.def,
    required this.clearedStages,
    required this.currentValue,
    required this.currentStageTarget,
    required this.previousStageTarget,
    required this.rewardOnNextClear,
  });

  int get nextStage => clearedStages + 1;

  /// Progress through the *current* stage as a 0..1 ratio.
  double get ratio {
    final span = currentStageTarget - previousStageTarget;
    if (span <= 0) return 1;
    final into = currentValue - previousStageTarget;
    if (into <= 0) return 0;
    if (into >= span) return 1;
    return into / span;
  }

  bool get done => currentValue >= currentStageTarget;
}
