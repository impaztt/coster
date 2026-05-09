import 'dart:math' as math;

/// Pricing + success-rate model for a single main sword enhancement attempt
/// targeting [targetStage] (i.e. the stage you're trying to reach, 1..50).
///
/// Both currency tracks scale exponentially with stage. The essence track
/// is intentionally pricier per unit of real-money value (1000 essence ≈
/// 10,000 KRW) but in exchange has a higher success rate and never costs
/// the player a stage on failure.
class MainSwordEnhanceCost {
  final int targetStage;
  final double goldCost;
  final int essenceCost;
  final double goldSuccessBase; // 0..1
  final double essenceSuccessBase; // 0..1
  final int penaltyOnFail; // stages lost on a failed gold attempt
  const MainSwordEnhanceCost({
    required this.targetStage,
    required this.goldCost,
    required this.essenceCost,
    required this.goldSuccessBase,
    required this.essenceSuccessBase,
    required this.penaltyOnFail,
  });
}

const mainSwordEnhanceMaxStage = 50;

MainSwordEnhanceCost mainSwordEnhanceCost(int targetStage) {
  final s = targetStage.clamp(1, mainSwordEnhanceMaxStage);
  // Gold scales hard so the late-game requires real upgrade investment to
  // afford an attempt at all.
  final goldCost = 1e6 * math.pow(1.7, s - 1).toDouble();
  // Essence scales gentler — a single +50 essence shot costs roughly 20K
  // essence, which is the headline BM number.
  final essenceCost = (5 * math.pow(1.18, s - 1)).round();

  // Linear decay, floors of 0.01 / 0.20 respectively.
  final goldSuccess = math.max(0.01, 0.96 - (s - 1) * 0.0192);
  final essenceSuccess = math.max(0.20, 1.0 - (s - 1) * 0.0163);

  // Penalty bands from the design.
  int penalty;
  if (s <= 5) {
    penalty = 0;
  } else if (s <= 25) {
    penalty = 1;
  } else if (s <= 40) {
    penalty = 2;
  } else {
    penalty = 3;
  }

  return MainSwordEnhanceCost(
    targetStage: s,
    goldCost: goldCost,
    essenceCost: essenceCost,
    goldSuccessBase: goldSuccess,
    essenceSuccessBase: essenceSuccess,
    penaltyOnFail: penalty,
  );
}

/// Optional essence-paid boost stacked onto any enhancement attempt.
enum MainSwordBoostLevel {
  none,
  small, // +10%p
  medium, // +25%p
  large, // +50%p
}

extension MainSwordBoostInfo on MainSwordBoostLevel {
  int get essenceCost => switch (this) {
        MainSwordBoostLevel.none => 0,
        MainSwordBoostLevel.small => 5,
        MainSwordBoostLevel.medium => 25,
        MainSwordBoostLevel.large => 80,
      };

  double get successBonus => switch (this) {
        MainSwordBoostLevel.none => 0,
        MainSwordBoostLevel.small => 0.10,
        MainSwordBoostLevel.medium => 0.25,
        MainSwordBoostLevel.large => 0.50,
      };

  String get label => switch (this) {
        MainSwordBoostLevel.none => '부스트 없음',
        MainSwordBoostLevel.small => '소 +10%',
        MainSwordBoostLevel.medium => '중 +25%',
        MainSwordBoostLevel.large => '대 +50%',
      };
}

/// Cost in essence for the per-attempt 강 보호권 (failure preserves stage).
const mainSwordProtectionEssenceCost = 50;

/// Hybrid attempt: pay 1.5x of both currencies for guaranteed +40%p.
/// (Caps at 100% so for low stages this is overkill — it shines >+30.)
const mainSwordHybridGoldMultiplier = 1.5;
const mainSwordHybridEssenceMultiplier = 1.5;
const mainSwordHybridSuccessBonus = 0.40;

/// How much of the tap/dps stat bonus a stage adds. Linear for now —
/// `mult = 1 + stage * 0.20`, so +0 = 1×, +25 = 6×, +50 = 11×.
double mainSwordStageBonusMult(int stage) {
  if (stage <= 0) return 1.0;
  return 1.0 + stage * 0.20;
}

/// Milestone rewards distributed when [stage] is reached for the first
/// time (tracked via SaveData.mainSwordHighestStage). Returns a record
/// describing what to grant; null when no milestone fires.
class MainSwordMilestoneReward {
  final int stage;
  final int essence;
  final String? title;
  final double? collectionBonusFraction;
  final double? summonRateBonusFraction;
  final bool goldenFrame;
  const MainSwordMilestoneReward({
    required this.stage,
    required this.essence,
    this.title,
    this.collectionBonusFraction,
    this.summonRateBonusFraction,
    this.goldenFrame = false,
  });
}

const _mainSwordMilestones = <MainSwordMilestoneReward>[
  MainSwordMilestoneReward(stage: 5, essence: 50),
  MainSwordMilestoneReward(
    stage: 10,
    essence: 200,
    collectionBonusFraction: 0.01,
  ),
  MainSwordMilestoneReward(stage: 15, essence: 500),
  MainSwordMilestoneReward(stage: 20, essence: 1000, title: '강화의 길'),
  MainSwordMilestoneReward(stage: 25, essence: 2000),
  MainSwordMilestoneReward(stage: 30, essence: 4000, title: '검의 주인'),
  MainSwordMilestoneReward(stage: 35, essence: 6000),
  MainSwordMilestoneReward(stage: 40, essence: 10000, title: '검신'),
  MainSwordMilestoneReward(stage: 45, essence: 15000),
  MainSwordMilestoneReward(
    stage: 50,
    essence: 30000,
    title: '창세자',
    summonRateBonusFraction: 0.05,
    goldenFrame: true,
  ),
];

MainSwordMilestoneReward? mainSwordMilestoneAt(int stage) {
  for (final m in _mainSwordMilestones) {
    if (m.stage == stage) return m;
  }
  return null;
}
