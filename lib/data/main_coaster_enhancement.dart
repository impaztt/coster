import 'dart:math' as math;

/// Pricing + success-rate model for a single main coaster enhancement attempt
/// targeting [targetStage] (i.e. the stage you're trying to reach, 1..50).
///
/// Both currency tracks scale exponentially with stage. The ticket track
/// is intentionally pricier per unit of real-money value (1000 ticket ≈
/// 10,000 KRW) but in exchange has a higher success rate and never costs
/// the player a stage on failure.
class MainCoasterEnhanceCost {
  final int targetStage;
  final double goldCost;
  final int ticketCost;
  final double goldSuccessBase; // 0..1
  final double ticketSuccessBase; // 0..1
  final int penaltyOnFail; // stages lost on a failed gold attempt
  const MainCoasterEnhanceCost({
    required this.targetStage,
    required this.goldCost,
    required this.ticketCost,
    required this.goldSuccessBase,
    required this.ticketSuccessBase,
    required this.penaltyOnFail,
  });
}

const mainCoasterEnhanceMaxStage = 50;

MainCoasterEnhanceCost mainCoasterEnhanceCost(int targetStage) {
  final s = targetStage.clamp(1, mainCoasterEnhanceMaxStage);
  // Gold scales hard so the late-game requires real upgrade investment to
  // afford an attempt at all.
  final goldCost = 1e6 * math.pow(1.7, s - 1).toDouble();
  // Ticket scales gentler — a single +50 ticket shot costs roughly 20K
  // ticket, which is the headline BM number.
  final ticketCost = (5 * math.pow(1.18, s - 1)).round();

  // Linear decay, floors of 0.01 / 0.20 respectively.
  final goldSuccess = math.max(0.01, 0.96 - (s - 1) * 0.0192);
  final ticketSuccess = math.max(0.20, 1.0 - (s - 1) * 0.0163);

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

  return MainCoasterEnhanceCost(
    targetStage: s,
    goldCost: goldCost,
    ticketCost: ticketCost,
    goldSuccessBase: goldSuccess,
    ticketSuccessBase: ticketSuccess,
    penaltyOnFail: penalty,
  );
}

/// Optional ticket-paid boost stacked onto any enhancement attempt.
enum MainCoasterBoostLevel {
  none,
  small, // +10%p
  medium, // +25%p
  large, // +50%p
}

extension MainCoasterBoostInfo on MainCoasterBoostLevel {
  int get ticketCost => switch (this) {
        MainCoasterBoostLevel.none => 0,
        MainCoasterBoostLevel.small => 5,
        MainCoasterBoostLevel.medium => 25,
        MainCoasterBoostLevel.large => 80,
      };

  double get successBonus => switch (this) {
        MainCoasterBoostLevel.none => 0,
        MainCoasterBoostLevel.small => 0.10,
        MainCoasterBoostLevel.medium => 0.25,
        MainCoasterBoostLevel.large => 0.50,
      };

  String get label => switch (this) {
        MainCoasterBoostLevel.none => '부스트 없음',
        MainCoasterBoostLevel.small => '소 +10%',
        MainCoasterBoostLevel.medium => '중 +25%',
        MainCoasterBoostLevel.large => '대 +50%',
      };
}

/// Cost in ticket for the per-attempt 강 보호권 (failure preserves stage).
const mainCoasterProtectionTicketCost = 50;

/// Hybrid attempt: pay 1.5x of both currencies for guaranteed +40%p.
/// (Caps at 100% so for low stages this is overkill — it shines >+30.)
const mainCoasterHybridGoldMultiplier = 1.5;
const mainCoasterHybridTicketMultiplier = 1.5;
const mainCoasterHybridSuccessBonus = 0.40;

/// How much of the tap/dps stat bonus a stage adds. Linear for now —
/// `mult = 1 + stage * 0.20`, so +0 = 1×, +25 = 6×, +50 = 11×.
double mainCoasterStageBonusMult(int stage) {
  if (stage <= 0) return 1.0;
  return 1.0 + stage * 0.20;
}

/// Milestone rewards distributed when [stage] is reached for the first
/// time (tracked via SaveData.mainCoasterHighestStage). Returns a record
/// describing what to grant; null when no milestone fires.
class MainCoasterMilestoneReward {
  final int stage;
  final int ticket;
  final String? title;
  final double? collectionBonusFraction;
  final double? summonRateBonusFraction;
  final bool goldenFrame;
  const MainCoasterMilestoneReward({
    required this.stage,
    required this.ticket,
    this.title,
    this.collectionBonusFraction,
    this.summonRateBonusFraction,
    this.goldenFrame = false,
  });
}

const _mainCoasterMilestones = <MainCoasterMilestoneReward>[
  MainCoasterMilestoneReward(stage: 5, ticket: 50),
  MainCoasterMilestoneReward(
    stage: 10,
    ticket: 200,
    collectionBonusFraction: 0.01,
  ),
  MainCoasterMilestoneReward(stage: 15, ticket: 500),
  MainCoasterMilestoneReward(stage: 20, ticket: 1000, title: '운영의 길'),
  MainCoasterMilestoneReward(stage: 25, ticket: 2000),
  MainCoasterMilestoneReward(stage: 30, ticket: 4000, title: '코스터의 주인'),
  MainCoasterMilestoneReward(stage: 35, ticket: 6000),
  MainCoasterMilestoneReward(stage: 40, ticket: 10000, title: '레전드 오너'),
  MainCoasterMilestoneReward(stage: 45, ticket: 15000),
  MainCoasterMilestoneReward(
    stage: 50,
    ticket: 30000,
    title: '파크 창세자',
    summonRateBonusFraction: 0.05,
    goldenFrame: true,
  ),
];

MainCoasterMilestoneReward? mainCoasterMilestoneAt(int stage) {
  for (final m in _mainCoasterMilestones) {
    if (m.stage == stage) return m;
  }
  return null;
}
