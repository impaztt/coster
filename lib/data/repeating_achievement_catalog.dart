import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../models/repeating_achievement.dart';

/// Helper: a target ladder where stage 1 = [base], each next stage
/// multiplies by [ratio]. Stages are 1-indexed.
double Function(int) _geometric(double base, double ratio) =>
    (s) => base * _powInt(ratio, s - 1);

double _powInt(double base, int exp) {
  if (exp <= 0) return 1;
  var r = 1.0;
  for (var i = 0; i < exp; i++) {
    r *= base;
  }
  return r;
}

/// Helper: linear arithmetic ladder where stage 1 = [base], each step
/// adds [step].
double Function(int) _linear(int base, int step) =>
    (s) => (base + (s - 1) * step).toDouble();

/// Repeat-track reward global nerf (70% of previous payout).
const _repeatRewardScale = 0.7;

/// Reward curve: small base + slow growth (capped to keep economy sane).
int Function(int) _reward({
  required int base,
  double growth = 1.4,
  int cap = 200,
}) =>
    (s) {
      final raw = base * _powInt(growth, s - 1);
      final clamped = raw > cap ? cap.toDouble() : raw;
      final scaled = (clamped * _repeatRewardScale).round();
      return scaled < 1 ? 1 : scaled;
    };

const _trackTap = Color(0xFFFF7043);
const _trackGold = Color(0xFFFFB300);
const _trackDps = Color(0xFF00ACC1);
const _trackCombat = Color(0xFFEF5350);
const _trackSlime = Color(0xFFFFC107);
const _trackSkill = Color(0xFF42A5F5);
const _trackPrestige = Color(0xFFFFCA28);
const _trackSummon = Color(0xFF7C4DFF);
const _trackStock = Color(0xFFD32F2F);
const _trackDividend = Color(0xFFEC407A);

final repeatingAchievementCatalog = <RepeatingAchievementDef>[
  RepeatingAchievementDef(
    id: 'rep_tap',
    name: '터치 장인',
    description: '터치 누적 마다 단계 상승',
    category: AchievementCategory.tap,
    icon: Icons.touch_app,
    color: _trackTap,
    current: (c) => c.totalTaps.toDouble(),
    targetForStage: _geometric(10000, 10),
    rewardForStage: _reward(base: 5),
  ),
  RepeatingAchievementDef(
    id: 'rep_gold',
    name: '골드 거상',
    description: '누적 골드 단계 상승',
    category: AchievementCategory.gold,
    icon: Icons.monetization_on,
    color: _trackGold,
    current: (c) => c.lifetimeGold,
    targetForStage: _geometric(1e9, 10),
    rewardForStage: _reward(base: 8),
  ),
  RepeatingAchievementDef(
    id: 'rep_dps',
    name: 'DPS 폭주',
    description: '최대 DPS 단계 상승',
    category: AchievementCategory.dps,
    icon: Icons.bolt,
    color: _trackDps,
    current: (c) => c.maxDpsEver,
    targetForStage: _geometric(1e6, 5),
    rewardForStage: _reward(base: 6),
  ),
  RepeatingAchievementDef(
    id: 'rep_prestige',
    name: '환생 순례자',
    description: '환생 누적 단계 상승',
    category: AchievementCategory.prestige,
    icon: Icons.auto_awesome,
    color: _trackPrestige,
    current: (c) => c.prestigeCount.toDouble(),
    targetForStage: _geometric(10, 2),
    rewardForStage: _reward(base: 12),
  ),
  RepeatingAchievementDef(
    id: 'rep_slime',
    name: '슬라임 사냥꾼',
    description: '슬라임 처치 단계 상승',
    category: AchievementCategory.slime,
    icon: Icons.bubble_chart,
    color: _trackSlime,
    current: (c) => c.slimesDefeated.toDouble(),
    targetForStage: _geometric(100, 3),
    rewardForStage: _reward(base: 5),
  ),
  RepeatingAchievementDef(
    id: 'rep_combo_burst',
    name: '콤보 마스터',
    description: '콤보 버스트 단계 상승',
    category: AchievementCategory.combat,
    icon: Icons.local_fire_department,
    color: _trackCombat,
    current: (c) => c.comboBurstCount.toDouble(),
    targetForStage: _geometric(50, 2),
    rewardForStage: _reward(base: 6),
  ),
  RepeatingAchievementDef(
    id: 'rep_skill',
    name: '스킬 학자',
    description: '스킬 사용 단계 상승',
    category: AchievementCategory.skill,
    icon: Icons.flash_on,
    color: _trackSkill,
    current: (c) => c.skillsUsed.toDouble(),
    targetForStage: _geometric(10, 3),
    rewardForStage: _reward(base: 4),
  ),
  RepeatingAchievementDef(
    id: 'rep_summon',
    name: '소환 광신도',
    description: '소환 횟수 단계 상승',
    category: AchievementCategory.summon,
    icon: Icons.diamond,
    color: _trackSummon,
    current: (c) => c.totalSummons.toDouble(),
    targetForStage: _geometric(50, 4),
    rewardForStage: _reward(base: 7),
  ),
  RepeatingAchievementDef(
    id: 'rep_stock_trades',
    name: '시장 트레이더',
    description: '주식 거래 단계 상승',
    category: AchievementCategory.stocks,
    icon: Icons.show_chart,
    color: _trackStock,
    current: (c) => c.totalStockTrades.toDouble(),
    targetForStage: _linear(10, 25),
    rewardForStage: _reward(base: 5),
  ),
  RepeatingAchievementDef(
    id: 'rep_dividend',
    name: '배당왕',
    description: '누적 배당 수령 단계 상승',
    category: AchievementCategory.stocks,
    icon: Icons.payments,
    color: _trackDividend,
    current: (c) => c.totalDividendsClaimed,
    targetForStage: _geometric(1e6, 10),
    rewardForStage: _reward(base: 10),
  ),
];

RepeatingAchievementDef? repeatingAchievementById(String id) {
  for (final r in repeatingAchievementCatalog) {
    if (r.id == id) return r;
  }
  return null;
}

/// Compute progress info for a single repeating track given the player's
/// cleared-stage counter (0 = no stages cleared yet).
RepeatingAchProgress repeatingProgress(
  RepeatingAchievementDef def,
  AchContext ctx,
  int clearedStages,
) {
  final value = def.current(ctx);
  final next = clearedStages + 1;
  final target = def.targetForStage(next);
  final prevTarget =
      clearedStages > 0 ? def.targetForStage(clearedStages) : 0.0;
  return RepeatingAchProgress(
    def: def,
    clearedStages: clearedStages,
    currentValue: value,
    currentStageTarget: target,
    previousStageTarget: prevTarget,
    rewardOnNextClear: def.rewardForStage(next),
  );
}
