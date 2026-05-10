import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show PurchaseStatus;

import '../data/achievement_catalog.dart';
import '../data/feature_unlocks.dart';
import '../data/main_coaster_enhancement.dart';
import '../data/main_coaster_evolution.dart';
import '../data/prestige_upgrade_catalog.dart';
import '../data/repeating_achievement_catalog.dart';
import '../data/producer_catalog.dart';
import '../data/region_catalog.dart';
import '../data/coaster_affinities.dart';
import '../data/coaster_catalog.dart';
import '../data/skill_catalog.dart';
import '../data/coaster_sets.dart';
import '../data/tap_upgrade_catalog.dart';
import '../models/achievement.dart';
import '../models/booster.dart';
import '../models/producer.dart';
import '../models/run_stats.dart';
import '../models/save_data.dart';
import '../models/skill.dart';
import '../models/stock_market.dart';
import '../models/coaster.dart';
import '../services/ad_service.dart';
import '../services/iap_service.dart';
import '../services/sync_service.dart';

/// Buy count: 1, 10, 100 or -1 for Max.
final buyMultiplierProvider = StateProvider<int>((_) => 1);

const stockMarketPriceCurveRebalanceVersion = 16;

/// Cost in 티켓 per single summon.
const summonCostSingle = 50;
const summonCostTen = 450;
const summonCostHundred = 4500;

/// After this many consecutive non-SR+ pulls, the next pull is guaranteed SR+.
const pityThreshold = 80;

/// Summon-rate progression: every [summonRateLevelStepSummons] pulls, SR+
/// rates are nudged up a little (up to [summonRateMaxLevel]).
const summonRateLevelStepSummons = 100;
const summonRateMaxLevel = 40;
const summonRateMinN = 35.0;
const summonRateMinR = 15.0;
const summonRateDrainFromNRatio = 0.70;

const _summonRateBoostPerLevel = <CoasterTier, double>{
  CoasterTier.sr: 0.20,
  CoasterTier.ssr: 0.11,
  CoasterTier.lr: 0.06,
  CoasterTier.ur: 0.03,
};

int summonRateLevelFor(int totalSummons) {
  if (totalSummons <= 0) return 0;
  return min(totalSummons ~/ summonRateLevelStepSummons, summonRateMaxLevel);
}

int summonsToNextRateLevel(int totalSummons) {
  final level = summonRateLevelFor(totalSummons);
  if (level >= summonRateMaxLevel) return 0;
  final nextTarget = (level + 1) * summonRateLevelStepSummons;
  return max(0, nextTarget - totalSummons);
}

Map<CoasterTier, double> summonRatesForTotalSummons(int totalSummons) {
  final level = summonRateLevelFor(totalSummons);
  final rates = <CoasterTier, double>{
    for (final tier in CoasterTier.values) tier: tier.rate,
  };
  if (level <= 0) return rates;

  double boostedTotal = 0;
  for (final entry in _summonRateBoostPerLevel.entries) {
    final gain = entry.value * level;
    boostedTotal += gain;
    rates[entry.key] = (rates[entry.key] ?? 0) + gain;
  }

  rates[CoasterTier.n] = max(
    summonRateMinN,
    (rates[CoasterTier.n] ?? 0) - boostedTotal * summonRateDrainFromNRatio,
  );
  rates[CoasterTier.r] = max(
    summonRateMinR,
    (rates[CoasterTier.r] ?? 0) -
        boostedTotal * (1 - summonRateDrainFromNRatio),
  );

  final total = rates.values.fold<double>(0, (a, b) => a + b);
  if ((total - 100).abs() > 0.0001) {
    rates[CoasterTier.r] = (rates[CoasterTier.r] ?? 0) + (100 - total);
  }
  return rates;
}

/// Idle earnings config.
const offlineMaxHours = 12;
const offlineMaxSeconds = offlineMaxHours * 3600;
const offlineClockSkewGraceMinutes = 5;
const offlineHardElapsedHours = 72;

/// Minimum away-time (seconds) before the "welcome back" dialog shows.
/// Short enough to verify the feature quickly, long enough to skip tab-switch
/// round-trips.
const offlineMinSeconds = 30;
const comebackTicketStepSeconds = 15 * 60; // +1 ticket per 15m
const comebackTicketCap = 120;

/// Big-ride + combo config.
const critChance = 0.05; // 5%
const critMultiplier = 10.0;
const comboWindowMs = 1500; // taps within this many ms extend the combo
const comboMax = 50;
const comboBonusPerStack = 0.01; // +1% tap per combo stack, cap +50%

/// Boost gauge config (β support mechanic).
/// A tap earns gold immediately, and also charges this gauge. While gauge > 0
/// the simulation runs at [boostTimeMultiplier] (cycles complete faster,
/// idle 초당 수익 accrues faster). Gauge drains over real time.
const boostGaugeMax = 100.0;
const boostGaugeDecayPerSec = 10.0;
const boostTimeMultiplier = 1.5;
const boostChargePerTapPerPower = 5.0; // 1 tapPower also gives +5 gauge
const boostChargeCritBonus = 30.0; // big ride adds an extra pulse

/// Coaster operating cycle (ride loop) — fixed-revenue floor regardless
/// of how many producers / passengers exist. A single cycle takes
/// [cycleSeconds] of effective sim time (i.e. boost-multiplied), and
/// pays [baseRevenuePerCycle] gold scaled by the prestige multiplier.
const cycleSeconds = 4.0;
const baseRevenuePerCycle = 1.0;

/// Daily login reward table: streak day (1-indexed) → ticket reward.
/// Streak resets when the user skips a day (>48h since last claim).
const dailyRewards = <int>[0, 5, 10, 15, 20, 30, 40, 60];
int dailyRewardFor(int streak) {
  if (streak < 1) return dailyRewards[1];
  if (streak >= dailyRewards.length) return dailyRewards.last;
  return dailyRewards[streak];
}

int _calcPrestigeCoinsFromProgress({
  required double totalGoldEarned,
  required double currentGold,
  required double purchasedGoldUnconverted,
  required Map<String, int> producerLevels,
  required Map<String, int> tapUpgradeLevels,
  required int prestigeCount,
  required Map<String, int> prestigeUpgradeLevels,
}) {
  int producerLevelSum = 0;
  for (final lv in producerLevels.values) {
    producerLevelSum += lv;
  }
  int tapUpgradeSum = 0;
  for (final lv in tapUpgradeLevels.values) {
    tapUpgradeSum += lv;
  }

  // Exclude any portion of currentGold that came from the ticket-for-gold
  // exchange. Until the player actually spends it on producers/upgrades,
  // purchased gold contributes nothing to the prestige coin payout.
  final effectiveCurrentGold =
      (currentGold - purchasedGoldUnconverted).clamp(0.0, double.infinity);
  final wealthScore = sqrt(
    ((totalGoldEarned + effectiveCurrentGold * 2).clamp(0.0, double.infinity)) /
        1e7,
  );
  final progressionScore = producerLevelSum / 30 + tapUpgradeSum / 20;
  final runDepthScore = min(10.0, prestigeCount * 0.1);
  final raw = (wealthScore + progressionScore + runDepthScore).floor();
  if (raw <= 0) return 0;

  final bonusMultiplier =
      1.0 + prestigeCoinGainBonusFraction(prestigeUpgradeLevels);
  return max(1, (raw * bonusMultiplier).floor());
}

/// Booster shop catalog. (`adOnly`=true means ticket cost is N/A; only
/// purchasable via the ad stub.)
class BoosterOffer {
  final String id;
  final String title;
  final String subtitle;
  final BoosterType type;
  final double multiplier;
  final int durationSec;
  final int ticketCost; // 0 → ad-only
  const BoosterOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.multiplier,
    required this.durationSec,
    required this.ticketCost,
  });
}

const boosterOffers = <BoosterOffer>[
  BoosterOffer(
    id: 'dps_2x_30m',
    title: '자동 수익 x2 · 30분',
    subtitle: '어트랙션들의 초당 수익이 두 배가 돼요',
    type: BoosterType.dps,
    multiplier: 2.0,
    durationSec: 1800,
    ticketCost: 50,
  ),
  BoosterOffer(
    id: 'tap_2x_15m',
    title: '터치 x2 · 15분',
    subtitle: '탭당 획득 골드 두 배',
    type: BoosterType.tap,
    multiplier: 2.0,
    durationSec: 900,
    ticketCost: 30,
  ),
  BoosterOffer(
    id: 'rush_3x_5m',
    title: '골드러시 x3 · 5분',
    subtitle: '초당 수익 + 터치 모두 3배',
    type: BoosterType.rush,
    multiplier: 3.0,
    durationSec: 300,
    ticketCost: 100,
  ),
];

const premiumAdRemovalProductId = 'premium_ad_removal';
const premiumMonthlyTicketPassProductId = 'premium_monthly_ticket_pass';
const premiumStarterPackageProductId = 'premium_starter_package';
const premiumFirstPurchaseProductId = 'premium_first_purchase';
const premiumTicketSmallProductId = 'premium_essence_small';
const premiumTicketMediumProductId = 'premium_essence_medium';
const premiumTicketLargeProductId = 'premium_essence_large';
const premiumTicketXLargeProductId = 'premium_essence_xlarge';
const premiumMasterPackageProductId = 'premium_master_package';
const premiumSeasonPassProductId = 'premium_season_pass';

const monthlyTicketPassImmediateTicket = 300;
const monthlyTicketPassDailyTicket = 120;
const monthlyTicketPassDurationDays = 30;
const monthlyTicketPassMissedClaimCapDays = 3;

const starterPackageTicket = 1400;
const starterPackageDpsBoostDurationSec = 1800;

/// Season pass (60 days). Larger daily ticket + a weekly stipend.
const seasonPassDurationDays = 60;
const seasonPassDailyTicket = 200;
const seasonPassMissedClaimCapDays = 3;

/// Weekly bonus: paid out at most once every 7 days while the pass is
/// active. Designed as the headline "extra" so the pass feels distinct
/// from the cheaper monthly version.
const seasonPassWeeklyTicket = 600;
const seasonPassWeeklyIntervalDays = 7;

/// First-purchase package: heavily front-loaded, one shot per account,
/// only purchasable in the first ad-funnel window.
const firstPurchasePackageTicket = 500;
// Ticket packs (consumables — no extra effect, just ticket).
const ticketSmallTicket = 110;
const ticketMediumTicket = 380;
const ticketLargeTicket = 1200;
const ticketXLargeTicket = 2800;

const masterPackageTicket = 7500;
const masterPackageProtectionScrolls = 10;
const masterPackageBoosterDurationSec = 86400; // 24h all-buff buffer

class PremiumProductDef {
  final String id;
  final String title;
  final String subtitle;
  final String priceLabel;
  final List<String> benefits;
  const PremiumProductDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.benefits,
  });
}

const premiumProducts = <PremiumProductDef>[
  PremiumProductDef(
    id: premiumAdRemovalProductId,
    title: '광고 제거',
    subtitle: '강제 광고 제거 + 광고 보상 즉시 수령',
    priceLabel: '₩4,900',
    benefits: [
      '강제 광고 영구 제거',
      '부스터 광고 보상 즉시 지급',
      '계정 영구 적용',
    ],
  ),
  PremiumProductDef(
    id: premiumMonthlyTicketPassProductId,
    title: '월간 티켓 보급권',
    subtitle: '30일 동안 매일 티켓을 안정적으로 확보',
    priceLabel: '₩5,900',
    benefits: [
      '구매 즉시 티켓 300',
      '30일 동안 매일 티켓 120',
      '미수령 보상 최대 3일 누적',
    ],
  ),
  PremiumProductDef(
    id: premiumStarterPackageProductId,
    title: '초보자 패키지',
    subtitle: '초반 도입과 성장 템포를 한 번에 보강',
    priceLabel: '₩4,900',
    benefits: [
      '티켓 1,400',
      'SR+ 코스터 1대 확정 지급',
      '자동 수익 x2 30분',
    ],
  ),
  PremiumProductDef(
    id: premiumFirstPurchaseProductId,
    title: '첫 결제 패키지',
    subtitle: '계정당 1회 — 강력한 진입 보너스',
    priceLabel: '₩1,100',
    benefits: [
      '티켓 500',
      'SR 확정 도입권 1',
      '24시간 한정 노출',
    ],
  ),
  PremiumProductDef(
    id: premiumTicketSmallProductId,
    title: '티켓 꾸러미 (소)',
    subtitle: '가장 가벼운 티켓 충전',
    priceLabel: '₩1,100',
    benefits: ['티켓 110'],
  ),
  PremiumProductDef(
    id: premiumTicketMediumProductId,
    title: '티켓 꾸러미 (중)',
    subtitle: '5분 환금 1회 + 보너스 30',
    priceLabel: '₩3,300',
    benefits: ['티켓 380'],
  ),
  PremiumProductDef(
    id: premiumTicketLargeProductId,
    title: '티켓 꾸러미 (대)',
    subtitle: '8시간 환금 1회분 + 보너스 200',
    priceLabel: '₩9,900',
    benefits: ['티켓 1,200'],
  ),
  PremiumProductDef(
    id: premiumTicketXLargeProductId,
    title: '티켓 꾸러미 (특대)',
    subtitle: '대량 충전 + 보너스 500',
    priceLabel: '₩19,900',
    benefits: ['티켓 2,800'],
  ),
  PremiumProductDef(
    id: premiumSeasonPassProductId,
    title: '시즌 패스',
    subtitle: '60일간 매일 티켓 + 주간 보너스',
    priceLabel: '₩14,900',
    benefits: [
      '60일간 매일 티켓 200',
      '7일마다 티켓 600 추가',
      '구매 즉시 시즌 시작',
    ],
  ),
  PremiumProductDef(
    id: premiumMasterPackageProductId,
    title: '마스터 패키지',
    subtitle: '한 번에 코어 빌드 완성',
    priceLabel: '₩49,900',
    benefits: [
      '티켓 7,500',
      'UR 확정 도입권 1',
      '강 보호권 10',
      '24시간 모든 부스터',
    ],
  ),
];

/// Slime config — guaranteed spawn every N taps so the player can
/// predict it. Counter persists in SaveData.tapsSinceSlime.
const slimeSpawnEvery = 250;
const slimeLifetimeMs = 7000;

/// Response steps required to satisfy a bonus VIP guest.
const slimeMaxHp = 10;

/// Reward when the VIP guest is handled: gold = tapPower × this many taps.
const slimeRewardTaps = 5000;

/// Auto-tap config: when an autoTap booster is active, fire a tap every
/// [autoTapIntervalMs] milliseconds. ~4 taps/sec is comfortable: visible
/// progress without trashing the framerate.
const autoTapIntervalMs = 250;

/// Combo burst: triggered the first time combo reaches comboMax during a
/// single combo streak. Reward = current 초당 수익 × this many seconds.
const comboBurstWorthSeconds = 60;

/// Combo surge skill: extra combo stacks per tap and bonus multiplier
/// applied while the surge window is active.
const comboSurgePerTap = 2;
const comboSurgeBonus = 2.0; // tap reward × this while surging

/// Parade fever skill: instant gold equal to current 초당 수익 × this seconds.
const slashBurstWorthSeconds = 300;
const ticketGatherAmount = 30;
const ascensionCoreBonusPerLevel = 0.015;

// =========================================================================
// Gold-exchange shop (티켓 → 골드 환전소)
//
// Two product lines:
//   • dpsTime  — pays out (currentDps × seconds × dpsTimeYieldFactor) gold.
//                Auto-scales with player power, so a single offer stays
//                relevant across the whole game.
//   • fixed    — pays out a constant gold amount. Useful in early runs
//                before 초당 수익 is meaningful, becomes obsolete late-game.
//
// The earned gold is added to currentGold AND tracked separately in
// `purchasedGoldUnconverted` so it is excluded from the prestige-coin
// wealthScore until the player actually spends it on producers/upgrades.
// `totalGoldEarned` is intentionally NOT bumped — purchased gold must
// never directly print prestige coins.
// =========================================================================

enum GoldExchangeKind { dpsTime, fixed }

class GoldExchangeOffer {
  final String id;
  final String title;
  final String subtitle;
  final int ticketCost;
  final GoldExchangeKind kind;
  // For dpsTime: the simulated offline duration in seconds.
  final int dpsSeconds;
  // For fixed: the flat gold amount granted.
  final double fixedGold;
  // Caps the number of times this specific offer can be used per UTC day.
  // 0 = no per-offer cap (still subject to global daily and run caps).
  final int dailyCap;

  const GoldExchangeOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ticketCost,
    required this.kind,
    this.dpsSeconds = 0,
    this.fixedGold = 0,
    this.dailyCap = 0,
  });
}

/// Slight haircut on dpsTime offers vs. true offline-equivalent so that
/// "instant time" never feels strictly better than just playing.
const dpsTimeYieldFactor = 0.85;

/// Floor for dpsTime offers right after prestige (when 초당 수익 = 0). We pay out
/// `floor * ticketCost` so a freshly-prestiged player still gets a small
/// nudge instead of zero gold.
const dpsTimeFloorPerTicket = 10000.0; // 10K gold per ticket

/// Daily cap for the entire exchange shop, independent of which offers were
/// used. Resets at UTC day rollover via the existing _dayKey() helper.
const goldExchangeDailyLimit = 5;

/// Hard cap for one prestige run. Resets in prestige().
const goldExchangePrestigeLimit = 15;

const goldExchangeOffers = <GoldExchangeOffer>[
  // 초당 수익-time line.
  GoldExchangeOffer(
    id: 'dps_5m',
    title: '5분 환금',
    subtitle: '현재 초당 수익 기준 5분치 골드',
    ticketCost: 12,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 300,
  ),
  GoldExchangeOffer(
    id: 'dps_30m',
    title: '30분 환금',
    subtitle: '현재 초당 수익 기준 30분치 골드',
    ticketCost: 50,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 1800,
  ),
  GoldExchangeOffer(
    id: 'dps_2h',
    title: '2시간 환금',
    subtitle: '현재 초당 수익 기준 2시간치 골드',
    ticketCost: 180,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 7200,
  ),
  GoldExchangeOffer(
    id: 'dps_8h',
    title: '8시간 환금',
    subtitle: '현재 초당 수익 기준 8시간치 골드 · 하루 1회',
    ticketCost: 600,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 28800,
    dailyCap: 1,
  ),
  // Fixed-amount line. Becomes invisible once the player has cleared a
  // few prestiges (see GameNotifier.goldExchangeFixedHidden).
  GoldExchangeOffer(
    id: 'fixed_1m',
    title: '긴급 자금 1M',
    subtitle: '고정 100만 골드',
    ticketCost: 5,
    kind: GoldExchangeKind.fixed,
    fixedGold: 1e6,
  ),
  GoldExchangeOffer(
    id: 'fixed_50m',
    title: '긴급 자금 50M',
    subtitle: '고정 5천만 골드',
    ticketCost: 20,
    kind: GoldExchangeKind.fixed,
    fixedGold: 5e7,
  ),
  GoldExchangeOffer(
    id: 'fixed_500m',
    title: '긴급 자금 500M',
    subtitle: '고정 5억 골드',
    ticketCost: 80,
    kind: GoldExchangeKind.fixed,
    fixedGold: 5e8,
  ),
  GoldExchangeOffer(
    id: 'fixed_3b',
    title: '긴급 자금 3B',
    subtitle: '고정 30억 골드',
    ticketCost: 300,
    kind: GoldExchangeKind.fixed,
    fixedGold: 3e9,
  ),
];

/// Hide the fixed line once the player has prestiged this many times — by
/// then their 초당 수익 is large enough that fixed packs are noise.
const goldExchangeFixedHideAfterPrestiges = 3;

// Main coaster enhancement types ------------------------------------------------

enum MainCoasterEnhanceCurrency { gold, ticket, hybrid }

enum MainCoasterEnhanceFailure {
  none,
  notEnoughGold,
  notEnoughTicket,
  alreadyMaxed,
  rolledFailure,
}

class MainCoasterEnhanceAttemptResult {
  final bool ok; // false → couldn't even attempt (cost / cap reasons)
  final bool success; // true → +1 stage applied
  final int previousStage;
  final int newStage;
  final MainCoasterEnhanceFailure reason;
  final int penaltyApplied;
  final double goldSpent;
  final int ticketSpent;
  final bool crossedTierUp;
  final MainCoasterMilestoneReward? milestoneReward;
  const MainCoasterEnhanceAttemptResult({
    required this.ok,
    required this.success,
    required this.previousStage,
    required this.newStage,
    required this.reason,
    this.penaltyApplied = 0,
    this.goldSpent = 0,
    this.ticketSpent = 0,
    this.crossedTierUp = false,
    this.milestoneReward,
  });
}

enum MainCoasterEventType { tierUp, milestone, namingPrompt }

class MainCoasterEvent {
  final MainCoasterEventType type;
  final int? tierIndex;
  final String? tierName;
  final int? stage;
  final MainCoasterMilestoneReward? milestone;
  const MainCoasterEvent._({
    required this.type,
    this.tierIndex,
    this.tierName,
    this.stage,
    this.milestone,
  });

  const MainCoasterEvent.tierUp({
    required int tierIndex,
    required String tierName,
    required int stage,
  }) : this._(
          type: MainCoasterEventType.tierUp,
          tierIndex: tierIndex,
          tierName: tierName,
          stage: stage,
        );

  MainCoasterEvent.milestone(MainCoasterMilestoneReward reward)
      : this._(
          type: MainCoasterEventType.milestone,
          milestone: reward,
          stage: reward.stage,
        );

  const MainCoasterEvent.namingPrompt()
      : this._(type: MainCoasterEventType.namingPrompt);
}

final mainCoasterEventProvider = StreamProvider<MainCoasterEvent>(
  (ref) => ref.watch(gameProvider.notifier).mainCoasterEventStream,
);

/// Result of attempting a gold-exchange purchase. Communicates the precise
/// reason on failure so the UI can show a useful toast.
enum GoldExchangeFailureReason {
  none,
  notEnoughTicket,
  dailyCapReached,
  prestigeCapReached,
  perOfferCapReached,
}

class GoldExchangeResult {
  final bool ok;
  final double goldGranted;
  final GoldExchangeFailureReason reason;
  const GoldExchangeResult({
    required this.ok,
    required this.goldGranted,
    required this.reason,
  });
}

/// Stream of newly unlocked achievements (for toast UI).
final achievementUnlockProvider = StreamProvider<AchievementDef>(
  (ref) => ref.watch(gameProvider.notifier)._achievementUnlocks.stream,
);

/// Stream of newly unlocked features (for toast UI).
final featureUnlockProvider = StreamProvider<FeatureUnlockDef>(
  (ref) => ref.watch(gameProvider.notifier)._featureUnlocks.stream,
);

enum MissionCycle { daily, weekly }

class MissionDef {
  final String id;
  final String title;
  final String description;
  final int target;
  final int rewardTicket;
  final int rewardPrestigeCoins;
  final MissionCycle cycle;
  const MissionDef({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.rewardTicket,
    required this.rewardPrestigeCoins,
    required this.cycle,
  });
}

class MissionView {
  final String id;
  final String title;
  final String description;
  final int progress;
  final int target;
  final int rewardTicket;
  final int rewardPrestigeCoins;
  final bool claimed;
  const MissionView({
    required this.id,
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.rewardTicket,
    required this.rewardPrestigeCoins,
    required this.claimed,
  });

  bool get done => progress >= target;
}

const dailyMissionDefs = <MissionDef>[
  MissionDef(
    id: 'daily_tap_300',
    title: '집중 훈련',
    description: '터치 300회',
    target: 300,
    rewardTicket: 15,
    rewardPrestigeCoins: 12,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_upgrade_30',
    title: '강화 루틴',
    description: '강화 레벨 30회 구매',
    target: 30,
    rewardTicket: 18,
    rewardPrestigeCoins: 14,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_skill_5',
    title: '이벤트 숙련',
    description: '이벤트 5회 사용',
    target: 5,
    rewardTicket: 20,
    rewardPrestigeCoins: 16,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_crit_30',
    title: '정밀 운영',
    description: '대박 탑승 30회 발동',
    target: 30,
    rewardTicket: 18,
    rewardPrestigeCoins: 14,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_slime_5',
    title: 'VIP 손님 응대',
    description: 'VIP 손님 5명 응대',
    target: 5,
    rewardTicket: 16,
    rewardPrestigeCoins: 12,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_summon_15',
    title: '신규 코스터 도입',
    description: '도입 15회',
    target: 15,
    rewardTicket: 22,
    rewardPrestigeCoins: 18,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_combo_burst',
    title: '콤보 폭발',
    description: '콤보 버스트 1회 발동',
    target: 1,
    rewardTicket: 14,
    rewardPrestigeCoins: 10,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_booster_1',
    title: '부스터 점검',
    description: '부스터 1회 사용',
    target: 1,
    rewardTicket: 20,
    rewardPrestigeCoins: 14,
    cycle: MissionCycle.daily,
  ),
];

const weeklyMissionDefs = <MissionDef>[
  MissionDef(
    id: 'weekly_prestige_5',
    title: '재개장 순환',
    description: '재개장 5회 달성',
    target: 5,
    rewardTicket: 90,
    rewardPrestigeCoins: 120,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_slime_40',
    title: '황금 사냥',
    description: 'VIP 손님 40명 응대',
    target: 40,
    rewardTicket: 80,
    rewardPrestigeCoins: 90,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_summon_120',
    title: '수집 주간',
    description: '도입 120회',
    target: 120,
    rewardTicket: 110,
    rewardPrestigeCoins: 110,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_tap_5000',
    title: '터치 마라톤',
    description: '터치 5000회',
    target: 5000,
    rewardTicket: 75,
    rewardPrestigeCoins: 80,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_upgrade_200',
    title: '강화 매니아',
    description: '강화 200회 구매',
    target: 200,
    rewardTicket: 100,
    rewardPrestigeCoins: 110,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_skill_50',
    title: '이벤트 마스터',
    description: '이벤트 50회 사용',
    target: 50,
    rewardTicket: 90,
    rewardPrestigeCoins: 100,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_crit_300',
    title: '폭풍 매진',
    description: '대박 탑승 300회 발동',
    target: 300,
    rewardTicket: 80,
    rewardPrestigeCoins: 90,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_booster_5',
    title: '부스터 루틴',
    description: '부스터 5회 사용',
    target: 5,
    rewardTicket: 120,
    rewardPrestigeCoins: 130,
    cycle: MissionCycle.weekly,
  ),
];

class SummonResult {
  final CoasterDef coaster;
  final int levelAfter;
  final bool isDuplicate;
  final bool isMaxed;
  SummonResult({
    required this.coaster,
    required this.levelAfter,
    required this.isDuplicate,
    required this.isMaxed,
  });
}

class PremiumPurchaseResult {
  final bool ok;
  final String message;
  final int ticketGranted;
  final SummonResult? bonusSummon;

  const PremiumPurchaseResult({
    required this.ok,
    required this.message,
    this.ticketGranted = 0,
    this.bonusSummon,
  });
}

class FormationSummary {
  final int filledSlots;
  final double tapBonus;
  final double dpsBonus;
  final double marketBonus;
  final int distinctRoles;
  final int distinctRegions;
  final int strongestRegionCount;

  const FormationSummary({
    required this.filledSlots,
    required this.tapBonus,
    required this.dpsBonus,
    required this.marketBonus,
    required this.distinctRoles,
    required this.distinctRegions,
    required this.strongestRegionCount,
  });

  static const empty = FormationSummary(
    filledSlots: 0,
    tapBonus: 0,
    dpsBonus: 0,
    marketBonus: 0,
    distinctRoles: 0,
    distinctRegions: 0,
    strongestRegionCount: 0,
  );
}

class TapResult {
  final double amount;
  final bool isCrit;
  final int combo;
  final bool slimeSpawned;
  final bool isBurst;
  final double burstAmount;
  const TapResult({
    required this.amount,
    required this.isCrit,
    required this.combo,
    this.slimeSpawned = false,
    this.isBurst = false,
    this.burstAmount = 0,
  });
}

class SkillResult {
  final SkillId id;
  final bool ok;
  final String message;

  /// Extra payload for UI (e.g. how much gold the burst granted).
  final double payload;
  const SkillResult({
    required this.id,
    required this.ok,
    required this.message,
    this.payload = 0,
  });
}

class DailyBonus {
  final int streak;
  final int ticket;
  const DailyBonus({required this.streak, required this.ticket});
}

class GameState {
  final double gold;
  final double totalGoldEarned;
  final double tapPower;
  final double dps;
  final int prestigeCoins;
  final int prestigeCount;
  final int ascensionCoreLevel;
  final Map<String, int> producerLevels;
  final Map<String, int> tapUpgradeLevels;
  final Map<String, int> prestigeUpgradeLevels;
  final int totalTaps;
  final int playTimeSeconds;
  final double maxDpsEver;
  final double lifetimeGold;
  final int totalSummons;
  final int totalTapUpgradesBought;
  final double totalGoldSpent;
  final bool haptic;
  final bool sound;
  final bool darkMode;
  final bool highContrast;
  final double textScale;
  final bool reduceTapHaptics;
  final int ticket;
  final Map<String, int> ownedCoasters;
  final String? equippedCoasterId;
  final int summonsSinceHighRare;
  final Set<String> unlockedAchievements;
  final int combo;
  final int totalCrits;
  final int maxCombo;
  final int comboBurstCount;
  final int dailyStreak;
  final int maxDailyStreak;
  final DateTime? lastDailyClaimAt;
  final List<Booster> activeBoosters;
  final int tapsUntilSlime;
  final bool autoTapping;
  final bool tutorialSeen;
  final Map<String, DateTime> skillReadyAt;
  final Set<String> completedSetIds;
  final int slimesDefeated;
  final int skillsUsed;
  final int boostersPurchased;
  final bool timeGuardTriggered;
  final List<MissionView> dailyMissions;
  final List<MissionView> weeklyMissions;
  final Set<String> unlockedFeatures;
  final StockMarketState market;
  final Map<String, int> repeatingAchievementStages;
  final RunStats run;
  final double purchasedGoldUnconverted;
  final int goldExchangeDailyUsed;
  final int goldExchangePrestigeUsed;
  final bool goldExchangeEightHourUsedToday;
  final int mainCoasterStage;
  final String? mainCoasterName;
  final int mainCoasterHighestStage;
  final bool adsRemoved;
  final DateTime? monthlyPassExpiresAt;
  final DateTime? seasonPassExpiresAt;
  final bool firstPurchasePackageClaimed;
  // Boost gauge (0..[boostGaugeMax]) — taps fill it, time drains it.
  // While > 0 the home scene runs at boostTimeMultiplier (1.5x).
  final double boostGauge;
  // Current ride-cycle progress (0..1). The HUD can render a thin
  // progress sliver under the boost gauge for player feedback.
  final double cycleProgress;
  final bool loaded;

  const GameState({
    required this.gold,
    required this.totalGoldEarned,
    required this.tapPower,
    required this.dps,
    required this.prestigeCoins,
    required this.prestigeCount,
    required this.ascensionCoreLevel,
    required this.producerLevels,
    required this.tapUpgradeLevels,
    required this.prestigeUpgradeLevels,
    required this.totalTaps,
    required this.playTimeSeconds,
    required this.maxDpsEver,
    required this.lifetimeGold,
    required this.totalSummons,
    required this.totalTapUpgradesBought,
    required this.totalGoldSpent,
    required this.haptic,
    required this.sound,
    required this.darkMode,
    required this.highContrast,
    required this.textScale,
    required this.reduceTapHaptics,
    required this.ticket,
    required this.ownedCoasters,
    required this.equippedCoasterId,
    required this.summonsSinceHighRare,
    required this.unlockedAchievements,
    required this.combo,
    required this.totalCrits,
    required this.maxCombo,
    required this.comboBurstCount,
    required this.dailyStreak,
    required this.maxDailyStreak,
    required this.lastDailyClaimAt,
    required this.activeBoosters,
    required this.tapsUntilSlime,
    required this.autoTapping,
    required this.tutorialSeen,
    required this.skillReadyAt,
    required this.completedSetIds,
    required this.slimesDefeated,
    required this.skillsUsed,
    required this.boostersPurchased,
    required this.timeGuardTriggered,
    required this.dailyMissions,
    required this.weeklyMissions,
    required this.unlockedFeatures,
    required this.market,
    required this.repeatingAchievementStages,
    required this.run,
    this.purchasedGoldUnconverted = 0,
    this.goldExchangeDailyUsed = 0,
    this.goldExchangePrestigeUsed = 0,
    this.goldExchangeEightHourUsedToday = false,
    this.mainCoasterStage = 0,
    this.mainCoasterName,
    this.mainCoasterHighestStage = 0,
    this.adsRemoved = false,
    this.monthlyPassExpiresAt,
    this.seasonPassExpiresAt,
    this.firstPurchasePackageClaimed = false,
    this.boostGauge = 0,
    this.cycleProgress = 0,
    this.loaded = false,
  });

  factory GameState.empty() => GameState(
        gold: 0,
        totalGoldEarned: 0,
        tapPower: 1,
        dps: 0,
        prestigeCoins: 0,
        prestigeCount: 0,
        ascensionCoreLevel: 0,
        producerLevels: {},
        tapUpgradeLevels: {},
        prestigeUpgradeLevels: const {},
        totalTaps: 0,
        playTimeSeconds: 0,
        maxDpsEver: 0,
        lifetimeGold: 0,
        totalSummons: 0,
        totalTapUpgradesBought: 0,
        totalGoldSpent: 0,
        haptic: true,
        sound: true,
        darkMode: false,
        highContrast: false,
        textScale: 1.0,
        reduceTapHaptics: false,
        ticket: 90,
        ownedCoasters: {},
        equippedCoasterId: null,
        summonsSinceHighRare: 0,
        unlockedAchievements: {},
        combo: 0,
        totalCrits: 0,
        maxCombo: 0,
        comboBurstCount: 0,
        dailyStreak: 0,
        maxDailyStreak: 0,
        lastDailyClaimAt: null,
        activeBoosters: const [],
        tapsUntilSlime: slimeSpawnEvery,
        autoTapping: false,
        tutorialSeen: false,
        skillReadyAt: const {},
        completedSetIds: const {},
        slimesDefeated: 0,
        skillsUsed: 0,
        boostersPurchased: 0,
        timeGuardTriggered: false,
        dailyMissions: const [],
        weeklyMissions: const [],
        unlockedFeatures: const {},
        market: StockMarketState(),
        repeatingAchievementStages: const {},
        run: RunStats(),
        loaded: false,
      );

  double get prestigeMultiplier =>
      1.0 + prestigeGlobalBonusFraction(prestigeUpgradeLevels);

  double get ascensionCoreMultiplier =>
      1.0 + ascensionCoreLevel * ascensionCoreBonusPerLevel;

  bool get ascensionCoreUnlocked {
    if (prestigeCount < 5) return false;
    for (final def in producerCatalog) {
      if (def.category != ProducerCategory.transcendent) continue;
      final lv = producerLevels[def.id] ?? 0;
      if (lv >= 25) return true;
    }
    return false;
  }

  int get ascensionCoreNextCost => ascensionCoreCostAt(ascensionCoreLevel);

  int get prestigeCoinsAvailable => _calcPrestigeCoinsFromProgress(
        totalGoldEarned: totalGoldEarned,
        currentGold: gold,
        purchasedGoldUnconverted: purchasedGoldUnconverted,
        producerLevels: producerLevels,
        tapUpgradeLevels: tapUpgradeLevels,
        prestigeCount: prestigeCount,
        prestigeUpgradeLevels: prestigeUpgradeLevels,
      );

  int producerLevel(String id) => producerLevels[id] ?? 0;
  int tapUpgradeLevel(String id) => tapUpgradeLevels[id] ?? 0;
  int prestigeUpgradeLevel(String id) => prestigeUpgradeLevels[id] ?? 0;
  int coasterLevel(String id) => ownedCoasters[id] ?? 0;
  bool ownsCoaster(String id) => (ownedCoasters[id] ?? 0) > 0;
  bool isFeatureUnlocked(String id) => unlockedFeatures.contains(id);

  CoasterDef? get equippedCoaster {
    final id = equippedCoasterId;
    if (id == null) return null;
    try {
      return coasterById(id);
    } catch (_) {
      return null;
    }
  }

  bool canAfford(double cost) => gold >= cost;

  bool isAchievementUnlocked(String id) => unlockedAchievements.contains(id);

  /// Build an AchContext snapshot for progress computations.
  AchContext achContext() {
    int totalProducerLv = 0;
    int ownedProducers = 0;
    for (final v in producerLevels.values) {
      totalProducerLv += v;
      if (v > 0) ownedProducers++;
    }
    bool hasR = false,
        hasSr = false,
        hasSsr = false,
        hasLr = false,
        hasUr = false;
    int maxLv = 0;
    int maxedCount = 0;
    for (final entry in ownedCoasters.entries) {
      if (entry.value <= 0) continue;
      try {
        final tier = coasterById(entry.key).tier;
        if (tier == CoasterTier.r) hasR = true;
        if (tier == CoasterTier.sr) hasSr = true;
        if (tier == CoasterTier.ssr) hasSsr = true;
        if (tier == CoasterTier.lr) hasLr = true;
        if (tier == CoasterTier.ur) hasUr = true;
      } catch (_) {}
      if (entry.value > maxLv) maxLv = entry.value;
      if (entry.value >= CoasterDef.maxLevel) maxedCount++;
    }
    // Stock-market derived stats.
    var unlockedRegions = 0;
    var maxedRegions = 0;
    var totalShares = 0;
    for (final entry in market.regions.entries) {
      final st = entry.value;
      if (st.unlocked) unlockedRegions++;
      totalShares += st.shares;
      // A region is "maxed" once the player hits the 80% ownership cap.
      try {
        final def = regionDefById(entry.key);
        final cap = (def.totalShares * regionMaxOwnershipFraction).floor();
        if (st.shares >= cap && cap > 0) maxedRegions++;
      } catch (_) {
        // Unknown region id — ignore.
      }
    }
    return AchContext(
      totalTaps: totalTaps,
      lifetimeGold: lifetimeGold,
      maxDpsEver: maxDpsEver,
      playTimeSeconds: playTimeSeconds,
      producerLevels: producerLevels,
      totalProducerLevels: totalProducerLv,
      ownedProducerCount: ownedProducers,
      totalProducerCatalogCount: producerCatalog.length,
      ownedCoasters: ownedCoasters,
      ownedCoasterCount: ownedCoasters.values.where((v) => v > 0).length,
      totalCoasterCatalogCount: coasterCatalog.length,
      ownsAnyR: hasR,
      ownsAnySr: hasSr,
      ownsAnySsr: hasSsr,
      ownsAnyLr: hasLr,
      ownsAnyUr: hasUr,
      maxCoasterLevel: maxLv,
      maxedCoasterCount: maxedCount,
      totalSummons: totalSummons,
      prestigeCount: prestigeCount,
      prestigeUpgradeLevels: prestigeUpgradeLevels,
      totalTapUpgradesBought: totalTapUpgradesBought,
      hasEquippedCoaster: equippedCoasterId != null,
      totalCrits: totalCrits,
      maxCombo: maxCombo,
      comboBurstCount: comboBurstCount,
      slimesDefeated: slimesDefeated,
      skillsUsed: skillsUsed,
      boostersPurchased: boostersPurchased,
      maxDailyStreak: maxDailyStreak,
      completedSetCount: completedSetIds.length,
      unlockedRegionCount: unlockedRegions,
      regionsAtMaxOwnership: maxedRegions,
      totalShareUnits: totalShares,
      totalDividendsClaimed: market.totalDividendsClaimed,
      totalStockTrades: market.totalTradesCount,
      totalGoldSpent: totalGoldSpent,
      prestigeCoins: prestigeCoins,
      ticket: ticket,
      run: run,
    );
  }
}

class OfflineReward {
  final Duration duration;
  final double gold;
  final int ticketBonus;
  final bool blockedByClockGuard;
  const OfflineReward({
    required this.duration,
    required this.gold,
    this.ticketBonus = 0,
    this.blockedByClockGuard = false,
  });
}

const _milestoneTicket = <int, int>{
  25: 1,
  50: 2,
  100: 5,
  200: 10,
};

int _milestoneTicketUpTo(int level) {
  int total = 0;
  _milestoneTicket.forEach((threshold, reward) {
    if (level >= threshold) total += reward;
  });
  return total;
}

int ascensionCoreCostAt(int level) {
  final cost = 250 * pow(1.22, level);
  if (cost.isNaN || cost.isInfinite) return 2147483647;
  return cost.round().clamp(0, 2147483647).toInt();
}

class GameNotifier extends Notifier<GameState> {
  final _syncService = SyncService();
  final _random = Random();
  final _achievementUnlocks = StreamController<AchievementDef>.broadcast();
  final _featureUnlocks = StreamController<FeatureUnlockDef>.broadcast();
  Timer? _tickTimer;
  Timer? _saveTimer;
  Timer? _comboDecayTimer;
  Timer? _autoTapTimer;
  DateTime _lastTick = DateTime.now();
  double _playTimeAcc = 0;
  SaveData _save = SaveData();
  OfflineReward? _pendingOffline;
  DailyBonus? _pendingDaily;
  bool _timeGuardTriggered = false;
  int _combo = 0;
  DateTime? _lastTapAt;
  DateTime? _comboSurgeUntil;
  bool _burstFiredThisRun = false;
  bool _featureUnlocksReady = false;
  // Accumulator for the 1-second stock price tick driven by the 50ms timer.
  double _stockTickAcc = 0;
  bool _spareGaussReady = false;
  double _spareGauss = 0;
  // Tap-support boost (β bar). Ephemeral — resets to 0 on app restart, not
  // saved. Tapping earns gold immediately and also fills this gauge; while
  // > 0 the sim ticks at boostTimeMultiplier and decays at
  // boostGaugeDecayPerSec in real time.
  double _boostGauge = 0;
  // Coaster ride-cycle progress (0..1). Each completed cycle pays a fixed
  // baseRevenue floor even with zero producers, so tap-as-speed-up still
  // produces income from frame 0.
  double _cycleProgress = 0;

  @override
  GameState build() {
    ref.onDispose(_dispose);
    Future.microtask(_initialize);
    return GameState.empty();
  }

  void _dispose() {
    _tickTimer?.cancel();
    _saveTimer?.cancel();
    _comboDecayTimer?.cancel();
    _autoTapTimer?.cancel();
    _achievementUnlocks.close();
    _featureUnlocks.close();
    _mainCoasterEvents.close();
    _iapSub?.cancel();
  }

  Future<void> _initialize() async {
    final loaded = await _syncService.loadResolved();
    final now = DateTime.now();
    var loadedVersion = SaveData.currentVersion;
    if (loaded != null) {
      _save = loaded;
      loadedVersion = _save.version;
      _sanitizeLoadedSave();
      _migrateLegacySoulsToOverallUpgrade();
      _rotateMissionWindowsIfNeeded(now: now, force: true);
      final elapsed = _safeOfflineElapsed(now, loaded.lastSavedAt);
      final cappedSeconds =
          elapsed.inSeconds.clamp(0, offlineMaxSeconds).toInt();
      final dpsNow = _calcDps();
      if (_timeGuardTriggered) {
        _pendingOffline = const OfflineReward(
          duration: Duration.zero,
          gold: 0,
          blockedByClockGuard: true,
        );
      } else if (cappedSeconds >= offlineMinSeconds && dpsNow > 0) {
        final ticketBonus =
            min(comebackTicketCap, cappedSeconds ~/ comebackTicketStepSeconds);
        _pendingOffline = OfflineReward(
          duration: Duration(seconds: cappedSeconds),
          gold: dpsNow * cappedSeconds,
          ticketBonus: ticketBonus,
        );
      }
    } else {
      _rotateMissionWindowsIfNeeded(now: now, force: true);
    }
    _bootstrapStockMarket(now: now, loadedVersion: loadedVersion);
    _save.version = SaveData.currentVersion;
    _save.firstLaunchAt ??= now; // anchor first-purchase popup window
    _accrueOfflineDividends(now: now);
    _pendingDaily = _evaluateDailyEligibility();
    _emit(loaded: true);
    // Veteran-safe: silently mark anything that's already triggered, without
    // spamming toasts for unlocks the player earned in past sessions.
    _evaluateFeatureUnlocks(silent: true);
    _featureUnlocksReady = true;
    _startTicker();
    _startAutoSave();
    _wireIapListener();
    // Sync ad-removal state with the ad SDK so forced interstitials are
    // suppressed for paying users immediately on app boot.
    AdService.instance.adsRemoved = _save.adsRemoved;
  }

  StreamSubscription<dynamic>? _iapSub;

  /// Listen for purchase results from in_app_purchase and grant entitlements
  /// locally. We trust client-side success here; server-side receipt
  /// validation is the upgrade path for a future release.
  void _wireIapListener() {
    _iapSub?.cancel();
    _iapSub = IapService.instance.purchaseStream.listen((purchase) {
      // Only purchased/restored grant entitlements. failed/canceled are
      // user-driven dropouts; pending shouldn't fire grants yet.
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        return;
      }
      final result = purchasePremiumProduct(purchase.productID);
      if (result.ok) {
        if (purchase.productID == premiumAdRemovalProductId) {
          AdService.instance.adsRemoved = true;
        }
      }
    });
  }

  Future<bool> loadCloudSaveForCurrentAccount() async {
    final cloudSave = await _syncService.fetchCloudForCurrentUser();
    if (cloudSave == null) {
      await _persist();
      return false;
    }
    final loadedVersion = cloudSave.version;
    final now = DateTime.now();
    _save = cloudSave;
    _pendingOffline = null;
    _pendingDaily = null;
    _timeGuardTriggered = false;
    _combo = 0;
    _lastTapAt = null;
    _comboSurgeUntil = null;
    _burstFiredThisRun = false;
    _sanitizeLoadedSave();
    _migrateLegacySoulsToOverallUpgrade();
    _rotateMissionWindowsIfNeeded(now: now, force: true);
    _bootstrapStockMarket(now: now, loadedVersion: loadedVersion);
    _save.version = SaveData.currentVersion;
    _accrueOfflineDividends(now: now);
    _emit(loaded: true);
    _evaluateFeatureUnlocks(silent: true);
    await _persist();
    return true;
  }

  Duration _safeOfflineElapsed(DateTime now, DateTime lastSavedAt) {
    final skewLimit = now.add(
      const Duration(minutes: offlineClockSkewGraceMinutes),
    );
    if (lastSavedAt.isAfter(skewLimit)) {
      _timeGuardTriggered = true;
      return Duration.zero;
    }
    final elapsed = now.difference(lastSavedAt);
    if (elapsed.inHours > offlineHardElapsedHours) {
      return const Duration(seconds: offlineMaxSeconds);
    }
    return elapsed;
  }

  void _migrateLegacySoulsToOverallUpgrade() {
    final souls = _save.prestigeSouls;
    if (souls <= 0) return;
    final def = prestigeUpgradeById(prestigeOverallUpgradeId);
    final prev = _save.prestigeUpgradeLevels[prestigeOverallUpgradeId] ?? 0;
    final migrated = (prev + souls).clamp(0, def.maxLevel).toInt();
    _save.prestigeUpgradeLevels[prestigeOverallUpgradeId] = migrated;
    _save.prestigeSouls = 0;
  }

  void _sanitizeLoadedSave() {
    _save.gold = _finiteClamp(_save.gold, 0, 1e120);
    _save.totalGoldEarned = _finiteClamp(_save.totalGoldEarned, 0, 1e120);
    _save.purchasedGoldUnconverted = _finiteClamp(
      _save.purchasedGoldUnconverted,
      0,
      _save.gold,
    );
    _save.goldExchangeDailyCount =
        _intClamp(_save.goldExchangeDailyCount, 0, goldExchangeDailyLimit);
    _save.goldExchangePrestigeCount = _intClamp(
        _save.goldExchangePrestigeCount, 0, goldExchangePrestigeLimit);
    _save.mainCoasterStage =
        _intClamp(_save.mainCoasterStage, 0, mainCoasterEnhanceMaxStage);
    _save.mainCoasterHighestStage = _intClamp(
      _save.mainCoasterHighestStage,
      _save.mainCoasterStage,
      mainCoasterEnhanceMaxStage,
    );
    _save.mainCoasterTiersShown.removeWhere(
      (i) => i < 0 || i >= mainCoasterTiers.length,
    );
    if (_save.mainCoasterCollectionBonusFraction.isNaN ||
        _save.mainCoasterCollectionBonusFraction < 0) {
      _save.mainCoasterCollectionBonusFraction = 0;
    }
    _save.prestigeCoins = _intClamp(_save.prestigeCoins, 0, 2147483647);
    _save.prestigeCount = _intClamp(_save.prestigeCount, 0, 1000000);
    _save.ascensionCoreLevel = _intClamp(_save.ascensionCoreLevel, 0, 1000000);
    _save.ticket = _intClamp(_save.ticket, 0, 2147483647);
    _save.dailyStreak = _intClamp(_save.dailyStreak, 0, 100000);
    _save.tapsSinceSlime =
        _intClamp(_save.tapsSinceSlime, 0, slimeSpawnEvery - 1);
    _save.stats.totalTaps = _intClamp(_save.stats.totalTaps, 0, 2147483647);
    _save.stats.totalSummons =
        _intClamp(_save.stats.totalSummons, 0, 2147483647);
    _save.stats.totalTapUpgradesBought =
        _intClamp(_save.stats.totalTapUpgradesBought, 0, 2147483647);
    _save.stats.totalCrits = _intClamp(_save.stats.totalCrits, 0, 2147483647);
    _save.stats.maxCombo = _intClamp(_save.stats.maxCombo, 0, comboMax);
    _save.stats.comboBurstCount =
        _intClamp(_save.stats.comboBurstCount, 0, 2147483647);
    _save.stats.slimesDefeated =
        _intClamp(_save.stats.slimesDefeated, 0, 2147483647);
    _save.stats.skillsUsed = _intClamp(_save.stats.skillsUsed, 0, 2147483647);
    _save.stats.boostersPurchased =
        _intClamp(_save.stats.boostersPurchased, 0, 2147483647);
    _save.settings.textScale =
        _save.settings.textScale.clamp(0.9, 1.3).toDouble();

    _sanitizeLevelMap(
      _save.producerLevels,
      allowed: producerCatalog.map((e) => e.id).toSet(),
      maxLevel: 1000000,
    );
    _sanitizeLevelMap(
      _save.tapUpgradeLevels,
      allowed: tapUpgradeCatalog.map((e) => e.id).toSet(),
      maxLevel: 1000000,
    );
    _sanitizeLevelMap(
      _save.prestigeUpgradeLevels,
      allowed: prestigeUpgradeCatalog.map((e) => e.id).toSet(),
      maxLevel: 1000000,
    );
    _sanitizeLevelMap(
      _save.ownedCoasters,
      allowed: coasterCatalog.map((e) => e.id).toSet(),
      maxLevel: CoasterDef.maxLevel,
    );
    final equipped = _save.equippedCoasterId;
    if (equipped != null && (_save.ownedCoasters[equipped] ?? 0) <= 0) {
      _save.equippedCoasterId = null;
    }
    _sanitizeFormationSlots();

    final skillIds = skillCatalog.map((e) => e.id.id).toSet();
    _save.skillReadyAt.removeWhere((k, v) => !skillIds.contains(k));
    _save.dailyMissionProgress
        .removeWhere((k, v) => !_dailyMissionById.containsKey(k) || v < 0);
    _save.weeklyMissionProgress
        .removeWhere((k, v) => !_weeklyMissionById.containsKey(k) || v < 0);
    _save.dailyMissionClaimed
        .removeWhere((id) => !_dailyMissionById.containsKey(id));
    _save.weeklyMissionClaimed
        .removeWhere((id) => !_weeklyMissionById.containsKey(id));
  }

  double _finiteClamp(double value, double minValue, double maxValue) {
    if (value.isNaN || value.isInfinite) return minValue;
    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;
    return value;
  }

  int _intClamp(int value, int minValue, int maxValue) {
    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;
    return value;
  }

  void _sanitizeLevelMap(
    Map<String, int> source, {
    required Set<String> allowed,
    required int maxLevel,
  }) {
    source.removeWhere(
        (id, lv) => !allowed.contains(id) || lv < 0 || lv > maxLevel);
  }

  void _sanitizeFormationSlots() {
    final allowed = coasterCatalog.map((e) => e.id).toSet();
    final seen = <String>{};
    final slots = List<String?>.filled(coasterFormationSlotCount, null);
    final source = _save.formationCoasterIds;
    final limit = source.length < coasterFormationSlotCount
        ? source.length
        : coasterFormationSlotCount;
    for (var i = 0; i < limit; i++) {
      final id = source[i];
      if (id == null) continue;
      if (!allowed.contains(id)) continue;
      if ((_save.ownedCoasters[id] ?? 0) <= 0) continue;
      if (!seen.add(id)) continue;
      slots[i] = id;
    }
    _save.formationCoasterIds = slots;
  }

  static final Map<String, MissionDef> _dailyMissionById = {
    for (final m in dailyMissionDefs) m.id: m,
  };
  static final Map<String, MissionDef> _weeklyMissionById = {
    for (final m in weeklyMissionDefs) m.id: m,
  };

  int _dayKey(DateTime now) => now.year * 10000 + now.month * 100 + now.day;

  int _weekKey(DateTime now) {
    final monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
    final thursday = monday.add(const Duration(days: 3));
    final year = thursday.year;
    final firstThursday = DateTime(year, 1, 4);
    final firstMonday = firstThursday
        .subtract(Duration(days: firstThursday.weekday - DateTime.monday));
    final week = (monday.difference(firstMonday).inDays ~/ 7) + 1;
    return year * 100 + week;
  }

  void _rotateMissionWindowsIfNeeded({DateTime? now, bool force = false}) {
    final t = now ?? DateTime.now();
    final dayKey = _dayKey(t);
    final weekKey = _weekKey(t);
    if (force || _save.dailyMissionDayKey != dayKey) {
      _save.dailyMissionDayKey = dayKey;
      _save.dailyMissionProgress.clear();
      _save.dailyMissionClaimed.clear();
    }
    if (force || _save.weeklyMissionWeekKey != weekKey) {
      _save.weeklyMissionWeekKey = weekKey;
      _save.weeklyMissionProgress.clear();
      _save.weeklyMissionClaimed.clear();
    }
  }

  /// Decide whether the user is eligible for a daily bonus right now.
  /// Does NOT mutate state — the claim happens via [claimDailyBonus] after
  /// the user taps "수령" on the dialog, so we can reflect it in stats atomically.
  DailyBonus? _evaluateDailyEligibility() {
    final last = _save.lastDailyClaimAt;
    final now = DateTime.now();
    // First-ever claim → day 1.
    if (last == null) {
      return DailyBonus(streak: 1, ticket: dailyRewardFor(1));
    }
    final hours = now.difference(last).inHours;
    if (hours < 24) return null; // already claimed today
    // 24h ≤ elapsed < 48h → streak continues.
    // Beyond 48h → streak resets to day 1.
    final nextStreak =
        hours < 48 ? ((_save.dailyStreak % (dailyRewards.length - 1)) + 1) : 1;
    return DailyBonus(streak: nextStreak, ticket: dailyRewardFor(nextStreak));
  }

  void _startTicker() {
    _lastTick = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = DateTime.now();
      final dt = now.difference(_lastTick).inMilliseconds / 1000.0;
      _lastTick = now;
      _playTimeAcc += dt;
      if (_playTimeAcc >= 1.0) {
        final whole = _playTimeAcc.floor();
        _save.stats.playTimeSeconds += whole;
        _playTimeAcc -= whole;
        _rotateMissionWindowsIfNeeded(now: now);
      }
      // Boost gauge decays in real time regardless of in-sim speed —
      // otherwise tapping would extend its own duration nonlinearly.
      if (_boostGauge > 0) {
        _boostGauge = (_boostGauge - boostGaugeDecayPerSec * dt)
            .clamp(0.0, boostGaugeMax);
      }
      // Effective sim dt: while gauge>0 the world runs at 1.5x. Cycles
      // complete faster AND 초당 수익 income accrues faster, matching the
      // "fast-forward the whole scene" mental model.
      final boosted = _boostGauge > 0;
      final simDt = boosted ? dt * boostTimeMultiplier : dt;

      final dps = _calcDps();
      if (dps > _save.stats.maxDpsEver) _save.stats.maxDpsEver = dps;
      if (dps > _save.run.dpsPeak) _save.run.dpsPeak = dps;
      if (dps > 0) {
        final gain = dps * simDt;
        _save.gold += gain;
        _save.totalGoldEarned += gain;
        _save.stats.lifetimeGold += gain;
        _save.run.goldEarned += gain;
      }
      // Cycle revenue floor: a fixed payout each time a ride loop
      // completes, so the player has income even with zero producers.
      _cycleProgress += simDt / cycleSeconds;
      if (_cycleProgress >= 1.0) {
        final completed = _cycleProgress.floor();
        _cycleProgress -= completed;
        final cycleGain = completed * baseRevenuePerCycle * _prestigeMult();
        _save.gold += cycleGain;
        _save.totalGoldEarned += cycleGain;
        _save.stats.lifetimeGold += cycleGain;
        _save.run.goldEarned += cycleGain;
      }
      _stockTickAcc += dt;
      if (_stockTickAcc >= stockPriceTickSeconds) {
        final ticks = (_stockTickAcc / stockPriceTickSeconds).floor();
        _stockTickAcc -= ticks * stockPriceTickSeconds;
        _runStockSimulation(now: now, ticksElapsed: ticks);
      }
      _emit(loaded: true);
    });
  }

  void _startAutoSave() {
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _persist(),
    );
  }

  Future<void> _persist() async {
    await _syncService.persist(_save);
  }

  void _emit({required bool loaded}) {
    state = GameState(
      gold: _save.gold,
      totalGoldEarned: _save.totalGoldEarned,
      tapPower: _calcTapPower(),
      dps: _calcDps(),
      prestigeCoins: _save.prestigeCoins,
      prestigeCount: _save.prestigeCount,
      ascensionCoreLevel: _save.ascensionCoreLevel,
      producerLevels: Map.unmodifiable(_save.producerLevels),
      tapUpgradeLevels: Map.unmodifiable(_save.tapUpgradeLevels),
      prestigeUpgradeLevels: Map.unmodifiable(_save.prestigeUpgradeLevels),
      totalTaps: _save.stats.totalTaps,
      playTimeSeconds: _save.stats.playTimeSeconds,
      maxDpsEver: _save.stats.maxDpsEver,
      lifetimeGold: _save.stats.lifetimeGold,
      totalSummons: _save.stats.totalSummons,
      totalTapUpgradesBought: _save.stats.totalTapUpgradesBought,
      totalGoldSpent: _save.stats.totalGoldSpent,
      haptic: _save.settings.haptic,
      sound: _save.settings.sound,
      darkMode: _save.settings.darkMode,
      highContrast: _save.settings.highContrast,
      textScale: _save.settings.textScale,
      reduceTapHaptics: _save.settings.reduceTapHaptics,
      ticket: _save.ticket,
      ownedCoasters: Map.unmodifiable(_save.ownedCoasters),
      equippedCoasterId: _save.equippedCoasterId,
      summonsSinceHighRare: _save.summonsSinceHighRare,
      unlockedAchievements: Set.unmodifiable(_save.unlockedAchievements),
      combo: _combo,
      totalCrits: _save.stats.totalCrits,
      maxCombo: _save.stats.maxCombo,
      comboBurstCount: _save.stats.comboBurstCount,
      dailyStreak: _save.dailyStreak,
      maxDailyStreak: _save.stats.maxDailyStreak,
      lastDailyClaimAt: _save.lastDailyClaimAt,
      activeBoosters: List.unmodifiable(_save.activeBoosters),
      tapsUntilSlime: (slimeSpawnEvery - _save.tapsSinceSlime)
          .clamp(0, slimeSpawnEvery)
          .toInt(),
      autoTapping: _autoTapActive(),
      tutorialSeen: _save.settings.tutorialSeen,
      skillReadyAt: Map.unmodifiable(_save.skillReadyAt),
      completedSetIds: Set.unmodifiable(_completedSetIds()),
      slimesDefeated: _save.stats.slimesDefeated,
      skillsUsed: _save.stats.skillsUsed,
      boostersPurchased: _save.stats.boostersPurchased,
      timeGuardTriggered: _timeGuardTriggered,
      dailyMissions: _buildMissionViews(daily: true),
      weeklyMissions: _buildMissionViews(daily: false),
      unlockedFeatures: Set.unmodifiable(_save.unlockedFeatures),
      market: _save.market,
      repeatingAchievementStages:
          Map.unmodifiable(_save.repeatingAchievementStages),
      run: _save.run,
      purchasedGoldUnconverted: _save.purchasedGoldUnconverted,
      goldExchangeDailyUsed: _currentGoldExchangeDailyUsed(),
      goldExchangePrestigeUsed: _save.goldExchangePrestigeCount,
      goldExchangeEightHourUsedToday:
          _save.goldExchangeEightHourDayKey == _dayKey(DateTime.now()),
      mainCoasterStage: _save.mainCoasterStage,
      mainCoasterName: _save.mainCoasterName,
      mainCoasterHighestStage: _save.mainCoasterHighestStage,
      adsRemoved: _save.adsRemoved,
      monthlyPassExpiresAt: _save.monthlyPassExpiresAt,
      seasonPassExpiresAt: _save.seasonPassExpiresAt,
      firstPurchasePackageClaimed: _save.firstPurchasePackageClaimed,
      boostGauge: _boostGauge,
      cycleProgress: _cycleProgress,
      loaded: loaded,
    );
    if (loaded) {
      _checkAchievements();
      _advanceRepeatingAchievements();
      if (_featureUnlocksReady) _evaluateFeatureUnlocks();
    }
  }

  /// Daily exchange usage normalized to "today" — if the saved dayKey is
  /// stale, the counter is implicitly 0.
  int _currentGoldExchangeDailyUsed() {
    if (_save.goldExchangeDayKey != _dayKey(DateTime.now())) return 0;
    return _save.goldExchangeDailyCount;
  }

  bool _autoTapActive() {
    final now = DateTime.now();
    return _save.activeBoosters
        .any((b) => b.type == BoosterType.autoTap && b.isActive(now));
  }

  Set<String> _completedSetIds() {
    final ids = <String>{};
    for (final s in coasterSets) {
      if (s.coasterIds.every((id) => (_save.ownedCoasters[id] ?? 0) > 0)) {
        ids.add(s.id);
      }
    }
    return ids;
  }

  double _setDpsBonus() {
    double bonus = 0;
    final completed = _completedSetIds();
    for (final s in coasterSets) {
      if (completed.contains(s.id)) bonus += s.dpsBonus;
    }
    return 1.0 + bonus;
  }

  double _setTapBonus() {
    double bonus = 0;
    final completed = _completedSetIds();
    for (final s in coasterSets) {
      if (completed.contains(s.id)) bonus += s.tapBonus;
    }
    return 1.0 + bonus;
  }

  List<MissionView> _buildMissionViews({required bool daily}) {
    final defs = daily ? dailyMissionDefs : weeklyMissionDefs;
    final progress =
        daily ? _save.dailyMissionProgress : _save.weeklyMissionProgress;
    final claimed =
        daily ? _save.dailyMissionClaimed : _save.weeklyMissionClaimed;
    return [
      for (final def in defs)
        MissionView(
          id: def.id,
          title: def.title,
          description: def.description,
          progress: (progress[def.id] ?? 0).clamp(0, def.target).toInt(),
          target: def.target,
          rewardTicket: def.rewardTicket,
          rewardPrestigeCoins: def.rewardPrestigeCoins,
          claimed: claimed.contains(def.id),
        ),
    ];
  }

  void _incMission(String id, int amount, {required bool daily}) {
    if (amount <= 0) return;
    _rotateMissionWindowsIfNeeded();
    final defs = daily ? _dailyMissionById : _weeklyMissionById;
    final def = defs[id];
    if (def == null) return;
    final progress =
        daily ? _save.dailyMissionProgress : _save.weeklyMissionProgress;
    final cur = progress[id] ?? 0;
    progress[id] = (cur + amount).clamp(0, def.target).toInt();
  }

  void _checkAchievements() {
    final ctx = state.achContext();
    bool anyChanged = false;
    for (final def in achievementCatalog) {
      if (_save.unlockedAchievements.contains(def.id)) continue;
      if (def.id == 'master_perfectionist') continue; // handled below
      if (def.progress(ctx).done) {
        _save.unlockedAchievements.add(def.id);
        _save.ticket += def.ticketReward;
        _achievementUnlocks.add(def);
        anyChanged = true;
      }
    }
    // Perfectionist: unlocks when every other achievement is done.
    if (!_save.unlockedAchievements.contains('master_perfectionist')) {
      final others =
          achievementCatalog.where((a) => a.id != 'master_perfectionist');
      if (others.every((a) => _save.unlockedAchievements.contains(a.id))) {
        final def = achievementCatalog
            .firstWhere((a) => a.id == 'master_perfectionist');
        _save.unlockedAchievements.add(def.id);
        _save.ticket += def.ticketReward;
        _achievementUnlocks.add(def);
        anyChanged = true;
      }
    }
    if (anyChanged) {
      // Re-emit to reflect new ticket + unlock set in a single next frame.
      state = GameState(
        gold: state.gold,
        totalGoldEarned: state.totalGoldEarned,
        tapPower: state.tapPower,
        dps: state.dps,
        prestigeCoins: state.prestigeCoins,
        prestigeCount: state.prestigeCount,
        ascensionCoreLevel: state.ascensionCoreLevel,
        producerLevels: state.producerLevels,
        tapUpgradeLevels: state.tapUpgradeLevels,
        prestigeUpgradeLevels: state.prestigeUpgradeLevels,
        totalTaps: state.totalTaps,
        playTimeSeconds: state.playTimeSeconds,
        maxDpsEver: state.maxDpsEver,
        lifetimeGold: state.lifetimeGold,
        totalSummons: state.totalSummons,
        totalTapUpgradesBought: state.totalTapUpgradesBought,
        totalGoldSpent: state.totalGoldSpent,
        haptic: state.haptic,
        sound: state.sound,
        darkMode: state.darkMode,
        highContrast: state.highContrast,
        textScale: state.textScale,
        reduceTapHaptics: state.reduceTapHaptics,
        ticket: _save.ticket,
        ownedCoasters: state.ownedCoasters,
        equippedCoasterId: state.equippedCoasterId,
        summonsSinceHighRare: state.summonsSinceHighRare,
        unlockedAchievements: Set.unmodifiable(_save.unlockedAchievements),
        combo: state.combo,
        totalCrits: state.totalCrits,
        maxCombo: state.maxCombo,
        comboBurstCount: state.comboBurstCount,
        dailyStreak: state.dailyStreak,
        maxDailyStreak: state.maxDailyStreak,
        lastDailyClaimAt: state.lastDailyClaimAt,
        activeBoosters: state.activeBoosters,
        tapsUntilSlime: state.tapsUntilSlime,
        autoTapping: state.autoTapping,
        tutorialSeen: state.tutorialSeen,
        skillReadyAt: state.skillReadyAt,
        completedSetIds: state.completedSetIds,
        slimesDefeated: state.slimesDefeated,
        skillsUsed: state.skillsUsed,
        boostersPurchased: state.boostersPurchased,
        timeGuardTriggered: state.timeGuardTriggered,
        dailyMissions: state.dailyMissions,
        weeklyMissions: state.weeklyMissions,
        unlockedFeatures: state.unlockedFeatures,
        market: state.market,
        repeatingAchievementStages: state.repeatingAchievementStages,
        run: state.run,
        loaded: true,
      );
    }
  }

  /// Walk every repeating-achievement track. If the player's metric has
  /// passed the next stage's target, advance the cleared-stage counter and
  /// pay out the stage reward. A single tick may clear multiple stages
  /// (e.g. on cold-start with a veteran save), so loop until caught up.
  void _advanceRepeatingAchievements() {
    final ctx = state.achContext();
    var anyChanged = false;
    var totalTicketGranted = 0;
    for (final def in repeatingAchievementCatalog) {
      var cleared = _save.repeatingAchievementStages[def.id] ?? 0;
      final value = def.current(ctx);
      // Cap iterations defensively to avoid runaway loops.
      var safety = 256;
      while (safety-- > 0 && value >= def.targetForStage(cleared + 1)) {
        cleared++;
        totalTicketGranted += def.rewardForStage(cleared);
      }
      if (cleared != (_save.repeatingAchievementStages[def.id] ?? 0)) {
        _save.repeatingAchievementStages[def.id] = cleared;
        anyChanged = true;
      }
    }
    if (!anyChanged) return;
    if (totalTicketGranted > 0) _save.ticket += totalTicketGranted;
    // Re-emit so the UI sees the new cleared-stage map and ticket.
    state = GameState(
      gold: state.gold,
      totalGoldEarned: state.totalGoldEarned,
      tapPower: state.tapPower,
      dps: state.dps,
      prestigeCoins: state.prestigeCoins,
      prestigeCount: state.prestigeCount,
      ascensionCoreLevel: state.ascensionCoreLevel,
      producerLevels: state.producerLevels,
      tapUpgradeLevels: state.tapUpgradeLevels,
      prestigeUpgradeLevels: state.prestigeUpgradeLevels,
      totalTaps: state.totalTaps,
      playTimeSeconds: state.playTimeSeconds,
      maxDpsEver: state.maxDpsEver,
      lifetimeGold: state.lifetimeGold,
      totalSummons: state.totalSummons,
      totalTapUpgradesBought: state.totalTapUpgradesBought,
      totalGoldSpent: state.totalGoldSpent,
      haptic: state.haptic,
      sound: state.sound,
      darkMode: state.darkMode,
      highContrast: state.highContrast,
      textScale: state.textScale,
      reduceTapHaptics: state.reduceTapHaptics,
      ticket: _save.ticket,
      ownedCoasters: state.ownedCoasters,
      equippedCoasterId: state.equippedCoasterId,
      summonsSinceHighRare: state.summonsSinceHighRare,
      unlockedAchievements: state.unlockedAchievements,
      combo: state.combo,
      totalCrits: state.totalCrits,
      maxCombo: state.maxCombo,
      comboBurstCount: state.comboBurstCount,
      dailyStreak: state.dailyStreak,
      maxDailyStreak: state.maxDailyStreak,
      lastDailyClaimAt: state.lastDailyClaimAt,
      activeBoosters: state.activeBoosters,
      tapsUntilSlime: state.tapsUntilSlime,
      autoTapping: state.autoTapping,
      tutorialSeen: state.tutorialSeen,
      skillReadyAt: state.skillReadyAt,
      completedSetIds: state.completedSetIds,
      slimesDefeated: state.slimesDefeated,
      skillsUsed: state.skillsUsed,
      boostersPurchased: state.boostersPurchased,
      timeGuardTriggered: state.timeGuardTriggered,
      dailyMissions: state.dailyMissions,
      weeklyMissions: state.weeklyMissions,
      unlockedFeatures: state.unlockedFeatures,
      market: state.market,
      repeatingAchievementStages:
          Map.unmodifiable(_save.repeatingAchievementStages),
      run: state.run,
      loaded: true,
    );
  }

  /// Evaluate all feature unlock triggers against current state. New unlocks
  /// are added to the save and broadcast on [_featureUnlocks] (unless
  /// [silent] is true — used on initial load to avoid spamming toasts for
  /// pre-existing veteran progress).
  void _evaluateFeatureUnlocks({bool silent = false}) {
    final s = state;
    var anyChanged = false;
    for (final def in featureUnlockCatalog) {
      if (_save.unlockedFeatures.contains(def.id)) continue;
      if (!def.trigger(s)) continue;
      _save.unlockedFeatures.add(def.id);
      anyChanged = true;
      if (!silent) _featureUnlocks.add(def);
    }
    if (!anyChanged) return;
    state = GameState(
      gold: state.gold,
      totalGoldEarned: state.totalGoldEarned,
      tapPower: state.tapPower,
      dps: state.dps,
      prestigeCoins: state.prestigeCoins,
      prestigeCount: state.prestigeCount,
      ascensionCoreLevel: state.ascensionCoreLevel,
      producerLevels: state.producerLevels,
      tapUpgradeLevels: state.tapUpgradeLevels,
      prestigeUpgradeLevels: state.prestigeUpgradeLevels,
      totalTaps: state.totalTaps,
      playTimeSeconds: state.playTimeSeconds,
      maxDpsEver: state.maxDpsEver,
      lifetimeGold: state.lifetimeGold,
      totalSummons: state.totalSummons,
      totalTapUpgradesBought: state.totalTapUpgradesBought,
      totalGoldSpent: state.totalGoldSpent,
      haptic: state.haptic,
      sound: state.sound,
      darkMode: state.darkMode,
      highContrast: state.highContrast,
      textScale: state.textScale,
      reduceTapHaptics: state.reduceTapHaptics,
      ticket: state.ticket,
      ownedCoasters: state.ownedCoasters,
      equippedCoasterId: state.equippedCoasterId,
      summonsSinceHighRare: state.summonsSinceHighRare,
      unlockedAchievements: state.unlockedAchievements,
      combo: state.combo,
      totalCrits: state.totalCrits,
      maxCombo: state.maxCombo,
      comboBurstCount: state.comboBurstCount,
      dailyStreak: state.dailyStreak,
      maxDailyStreak: state.maxDailyStreak,
      lastDailyClaimAt: state.lastDailyClaimAt,
      activeBoosters: state.activeBoosters,
      tapsUntilSlime: state.tapsUntilSlime,
      autoTapping: state.autoTapping,
      tutorialSeen: state.tutorialSeen,
      skillReadyAt: state.skillReadyAt,
      completedSetIds: state.completedSetIds,
      slimesDefeated: state.slimesDefeated,
      skillsUsed: state.skillsUsed,
      boostersPurchased: state.boostersPurchased,
      timeGuardTriggered: state.timeGuardTriggered,
      dailyMissions: state.dailyMissions,
      weeklyMissions: state.weeklyMissions,
      unlockedFeatures: Set.unmodifiable(_save.unlockedFeatures),
      market: state.market,
      repeatingAchievementStages: state.repeatingAchievementStages,
      run: state.run,
      loaded: true,
    );
  }

  double _prestigeMult() =>
      1.0 + prestigeGlobalBonusFraction(_save.prestigeUpgradeLevels);

  double _ascensionCoreMult() =>
      1.0 + _save.ascensionCoreLevel * ascensionCoreBonusPerLevel;

  double _prestigeShopTapMult() =>
      1.0 + prestigeTapBonusFraction(_save.prestigeUpgradeLevels);

  double _prestigeShopDpsMult() =>
      1.0 + prestigeDpsBonusFraction(_save.prestigeUpgradeLevels);

  double _equippedTapMult() {
    final id = _save.equippedCoasterId;
    if (id == null) return 1.0;
    final lv = _save.ownedCoasters[id] ?? 0;
    if (lv <= 0) return 1.0;
    try {
      return coasterById(id).tapMultAt(lv);
    } catch (_) {
      return 1.0;
    }
  }

  double _equippedDpsMult() {
    final id = _save.equippedCoasterId;
    if (id == null) return 1.0;
    final lv = _save.ownedCoasters[id] ?? 0;
    if (lv <= 0) return 1.0;
    try {
      return coasterById(id).dpsMultAt(lv);
    } catch (_) {
      return 1.0;
    }
  }

  /// Total fractional bonus contributed by every owned coaster (incl. the
  /// equipped one — its big equip multiplier is separate, so this stacks
  /// without "double-dipping" on the same source). Returns the raw sum,
  /// e.g. 0.42 for "+42%" — see [_collectionMult] for the multiplier form.
  double _collectionBonusTotal() {
    double total = 0;
    _save.ownedCoasters.forEach((id, lv) {
      if (lv <= 0) return;
      try {
        total += coasterById(id).ownedBonusAt(lv);
      } catch (_) {}
    });
    // Permanent collection-bonus boosts unlocked via main coaster milestones.
    total += _save.mainCoasterCollectionBonusFraction;
    return total;
  }

  double _collectionMult() => 1.0 + _collectionBonusTotal();

  List<String?> get formationCoasterIds {
    _sanitizeFormationSlots();
    return List.unmodifiable(_save.formationCoasterIds);
  }

  FormationSummary get formationSummary => _formationSummary();

  double _formationPower(CoasterDef def, int level) {
    final base = switch (def.tier) {
      CoasterTier.n => 0.006,
      CoasterTier.r => 0.010,
      CoasterTier.sr => 0.016,
      CoasterTier.ssr => 0.024,
      CoasterTier.lr => 0.036,
      CoasterTier.ur => 0.052,
    };
    final levelScale = 1.0 + (level.clamp(1, CoasterDef.maxLevel) - 1) * 0.08;
    return base * levelScale;
  }

  FormationSummary _formationSummary() {
    _sanitizeFormationSlots();
    var filled = 0;
    var tap = 0.0;
    var dps = 0.0;
    var market = 0.0;
    final roles = <CoasterFormationRole>{};
    final regions = <String>{};
    final regionCounts = <String, int>{};

    for (final id in _save.formationCoasterIds) {
      if (id == null) continue;
      final level = _save.ownedCoasters[id] ?? 0;
      if (level <= 0) continue;
      CoasterDef def;
      try {
        def = coasterById(id);
      } catch (_) {
        continue;
      }
      filled++;
      final role = coasterFormationRole(def);
      final regionId = coasterRegionId(def);
      final power = _formationPower(def, level);
      roles.add(role);
      regions.add(regionId);
      regionCounts[regionId] = (regionCounts[regionId] ?? 0) + 1;

      switch (role) {
        case CoasterFormationRole.vanguard:
          tap += power * 1.25;
          dps += power * 0.20;
          break;
        case CoasterFormationRole.striker:
          tap += power * 0.75;
          dps += power * 0.75;
          break;
        case CoasterFormationRole.support:
          tap += power * 0.20;
          dps += power * 1.25;
          break;
        case CoasterFormationRole.trader:
          dps += power * 0.35;
          market += power * 1.50;
          break;
        case CoasterFormationRole.anchor:
          tap += power * 0.55;
          dps += power * 0.55;
          market += power * 0.55;
          break;
      }
    }

    var strongestRegionCount = 0;
    for (final count in regionCounts.values) {
      if (count > strongestRegionCount) strongestRegionCount = count;
      if (count >= 2) {
        final pairBonus = (count - 1) * 0.006;
        tap += pairBonus;
        dps += pairBonus;
        market += (count - 1) * 0.018;
      }
    }

    if (roles.length >= 4) {
      tap += 0.02;
      dps += 0.02;
    }
    if (roles.length >= coasterFormationSlotCount) {
      tap += 0.015;
      dps += 0.015;
      market += 0.025;
    }
    if (filled >= coasterFormationSlotCount && regions.length >= filled) {
      market += 0.02;
    }

    return FormationSummary(
      filledSlots: filled,
      tapBonus: tap,
      dpsBonus: dps,
      marketBonus: market,
      distinctRoles: roles.length,
      distinctRegions: regions.length,
      strongestRegionCount: strongestRegionCount,
    );
  }

  double _formationTapMult() => 1.0 + _formationSummary().tapBonus;
  double _formationDpsMult() => 1.0 + _formationSummary().dpsBonus;

  double _calcTapPower() {
    double base = 1.0;
    for (final def in tapUpgradeCatalog) {
      final lv = _save.tapUpgradeLevels[def.id] ?? 0;
      base += def.tapPowerPerLevel * lv;
    }
    return base *
        _prestigeMult() *
        _ascensionCoreMult() *
        _prestigeShopTapMult() *
        _equippedTapMult() *
        _boosterTapMult() *
        _setTapBonus() *
        _collectionMult() *
        _formationTapMult() *
        _mainCoasterMult();
  }

  double _calcDps() {
    double sum = 0;
    for (final def in producerCatalog) {
      final lv = _save.producerLevels[def.id] ?? 0;
      sum += def.dpsAt(lv);
    }
    return sum *
        _prestigeMult() *
        _ascensionCoreMult() *
        _prestigeShopDpsMult() *
        _equippedDpsMult() *
        _boosterDpsMult() *
        _setDpsBonus() *
        _collectionMult() *
        _formationDpsMult() *
        _mainCoasterMult();
  }

  /// Multiplier from the home-tab main coaster's enhancement stage. Applies
  /// to BOTH tap and 초당 수익 so progression on the main coaster scales evenly
  /// with the rest of the build.
  double _mainCoasterMult() =>
      mainCoasterStageBonusMult(_save.mainCoasterStage);

  /// Public read so the UI can show "+X% from 메인코스터 +N단계".
  double get mainCoasterBonusFraction =>
      _mainCoasterMult() - 1.0 + _summonRateBonusFromMainCoaster();

  /// Permanent +5% summon-rate bonus from clearing +50.
  double _summonRateBonusFromMainCoaster() =>
      _save.mainCoasterHighestStage >= 50 ? 0.05 : 0.0;

  /// Public read for the home screen so it can show "수집 보너스 +X%".
  double get collectionBonusFraction => _collectionBonusTotal();

  bool setFormationCoaster(int slot, String? coasterId) {
    if (slot < 0 || slot >= coasterFormationSlotCount) return false;
    _sanitizeFormationSlots();
    if (coasterId != null) {
      if ((_save.ownedCoasters[coasterId] ?? 0) <= 0) return false;
      try {
        coasterById(coasterId);
      } catch (_) {
        return false;
      }
    }
    for (var i = 0; i < _save.formationCoasterIds.length; i++) {
      if (i != slot && _save.formationCoasterIds[i] == coasterId) {
        _save.formationCoasterIds[i] = null;
      }
    }
    _save.formationCoasterIds[slot] = coasterId;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  void clearFormation() {
    _save.formationCoasterIds =
        List<String?>.filled(coasterFormationSlotCount, null);
    _emit(loaded: true);
    unawaited(_persist());
  }

  void autoFillFormation() {
    final owned = <CoasterDef>[];
    for (final entry in _save.ownedCoasters.entries) {
      if (entry.value <= 0) continue;
      try {
        owned.add(coasterById(entry.key));
      } catch (_) {}
    }
    owned.sort((a, b) {
      final tierCmp = b.tier.index.compareTo(a.tier.index);
      if (tierCmp != 0) return tierCmp;
      final lvCmp = (_save.ownedCoasters[b.id] ?? 0)
          .compareTo(_save.ownedCoasters[a.id] ?? 0);
      if (lvCmp != 0) return lvCmp;
      return a.id.compareTo(b.id);
    });

    final picked = <CoasterDef>[];
    final usedRoles = <CoasterFormationRole>{};
    for (final coaster in owned) {
      if (picked.length >= coasterFormationSlotCount) break;
      final role = coasterFormationRole(coaster);
      if (usedRoles.contains(role)) continue;
      picked.add(coaster);
      usedRoles.add(role);
    }
    for (final coaster in owned) {
      if (picked.length >= coasterFormationSlotCount) break;
      if (picked.any((s) => s.id == coaster.id)) continue;
      picked.add(coaster);
    }

    _save.formationCoasterIds =
        List<String?>.filled(coasterFormationSlotCount, null);
    for (var i = 0; i < picked.length; i++) {
      _save.formationCoasterIds[i] = picked[i].id;
    }
    _emit(loaded: true);
    unawaited(_persist());
  }

  double regionCoasterDistrictBonusFraction(String regionId) {
    final regionCoasters = coastersForRegion(regionId);
    if (regionCoasters.isEmpty) return 0;

    var owned = 0;
    var levelTotal = 0;
    for (final coaster in regionCoasters) {
      final level = _save.ownedCoasters[coaster.id] ?? 0;
      if (level <= 0) continue;
      owned++;
      levelTotal += level.clamp(0, CoasterDef.maxLevel).toInt();
    }

    final ownedRatio = owned / regionCoasters.length;
    final levelRatio =
        levelTotal / (regionCoasters.length * CoasterDef.maxLevel);
    final collectionBonus = ownedRatio * 0.18 + levelRatio * 0.22;

    var formationBonus = 0.0;
    for (final id in _save.formationCoasterIds) {
      if (id == null) continue;
      final level = _save.ownedCoasters[id] ?? 0;
      if (level <= 0) continue;
      CoasterDef def;
      try {
        def = coasterById(id);
      } catch (_) {
        continue;
      }
      if (coasterRegionId(def) != regionId) continue;
      final role = coasterFormationRole(def);
      final roleWeight = switch (role) {
        CoasterFormationRole.trader => 2.00,
        CoasterFormationRole.anchor => 1.15,
        _ => 0.55,
      };
      formationBonus += _formationPower(def, level) * roleWeight;
    }

    return (collectionBonus + formationBonus).clamp(0.0, 0.85).toDouble();
  }

  double regionEffectiveHourlyYield(String regionId) {
    final def = regionDefById(regionId);
    return def.hourlyYield *
        (1.0 + regionCoasterDistrictBonusFraction(regionId));
  }

  double regionIntrinsicPrice(String regionId) {
    final def = regionDefById(regionId);
    return def.initialPrice *
        (1.0 + regionCoasterDistrictBonusFraction(regionId) * 0.45);
  }

  /// All multipliers that turn a producer's raw 초당 수익 into the effective 초당 수익
  /// shown on the home screen. Upgrade tiles use this to display the gain
  /// the player will actually see (e.g. so the coaster-collection bonus
  /// visibly improves the "초당 수익 +N" preview on companion/transcendent buys).
  double get dpsMultiplier =>
      _prestigeMult() *
      _ascensionCoreMult() *
      _prestigeShopDpsMult() *
      _equippedDpsMult() *
      _boosterDpsMult() *
      _setDpsBonus() *
      _collectionMult() *
      _formationDpsMult();

  /// Counterpart of [dpsMultiplier] for tap-power upgrades.
  double get tapMultiplier =>
      _prestigeMult() *
      _ascensionCoreMult() *
      _prestigeShopTapMult() *
      _equippedTapMult() *
      _boosterTapMult() *
      _setTapBonus() *
      _collectionMult() *
      _formationTapMult();

  /// Drop expired boosters from the save (called before any calculation that
  /// reads them, to avoid "ghost" multipliers after their timer ran out).
  void _reapBoosters() {
    final now = DateTime.now();
    _save.activeBoosters.removeWhere((b) => !b.isActive(now));
  }

  double _boosterDpsMult() {
    _reapBoosters();
    double m = 1.0;
    for (final b in _save.activeBoosters) {
      if (b.type == BoosterType.dps || b.type == BoosterType.rush) {
        m *= b.multiplier;
      }
    }
    return m;
  }

  double _boosterTapMult() {
    _reapBoosters();
    double m = 1.0;
    for (final b in _save.activeBoosters) {
      if (b.type == BoosterType.tap || b.type == BoosterType.rush) {
        m *= b.multiplier;
      }
    }
    return m;
  }

  /// Back-compat shim for callers that still treat tap() as "give me gold".
  /// New UI should prefer [tapWithFeedback] to access big-ride/combo info.
  double tap() => tapWithFeedback().amount;

  TapResult tapWithFeedback() {
    final now = DateTime.now();
    final withinWindow = _lastTapAt != null &&
        now.difference(_lastTapAt!).inMilliseconds <= comboWindowMs;
    final surge = _comboSurgeUntil != null && now.isBefore(_comboSurgeUntil!);
    final increment = surge ? comboSurgePerTap : 1;
    _combo = withinWindow
        ? (_combo + increment).clamp(0, comboMax).toInt()
        : increment;
    _lastTapAt = now;
    if (_combo > _save.stats.maxCombo) _save.stats.maxCombo = _combo;

    // Tap = immediate clicker gold. The boost gauge is now a supporting
    // tempo bonus, not the primary tap reward.
    final base = _calcTapPower();
    final comboMult = 1.0 + (_combo * comboBonusPerStack).clamp(0.0, 0.5);
    final surgeMult = surge ? comboSurgeBonus : 1.0;
    final isCrit = _random.nextDouble() < critChance;
    var amount = base * comboMult * surgeMult;
    if (isCrit) amount *= critMultiplier;
    _save.gold += amount;
    _save.totalGoldEarned += amount;
    _save.stats.lifetimeGold += amount;
    _save.run.goldEarned += amount;

    var charge = base * boostChargePerTapPerPower * comboMult * surgeMult;
    if (isCrit) charge += boostChargeCritBonus;
    _boostGauge = (_boostGauge + charge).clamp(0.0, boostGaugeMax);

    _save.stats.totalTaps++;
    _save.run.taps++;
    _incMission('daily_tap_300', 1, daily: true);
    _incMission('weekly_tap_5000', 1, daily: false);
    if (isCrit) {
      _save.stats.totalCrits++;
      _save.run.crits++;
      _incMission('daily_crit_30', 1, daily: true);
      _incMission('weekly_crit_300', 1, daily: false);
    }
    if (_combo > _save.run.maxCombo) _save.run.maxCombo = _combo;

    _save.tapsSinceSlime++;
    final slimeSpawned = _save.tapsSinceSlime >= slimeSpawnEvery;
    if (slimeSpawned) _save.tapsSinceSlime = 0;

    // Combo burst — fires once when combo first hits the cap during a run.
    bool isBurst = false;
    double burstAmount = 0;
    if (_combo >= comboMax && !_burstFiredThisRun) {
      _burstFiredThisRun = true;
      isBurst = true;
      burstAmount = _calcDps() * comboBurstWorthSeconds;
      _save.gold += burstAmount;
      _save.totalGoldEarned += burstAmount;
      _save.stats.lifetimeGold += burstAmount;
      _save.stats.comboBurstCount++;
      _save.run.comboBursts++;
      _incMission('daily_combo_burst', 1, daily: true);
    }

    _scheduleComboDecay();
    _emit(loaded: true);
    return TapResult(
      amount: amount,
      isCrit: isCrit,
      combo: _combo,
      slimeSpawned: slimeSpawned,
      isBurst: isBurst,
      burstAmount: burstAmount,
    );
  }

  void _scheduleComboDecay() {
    _comboDecayTimer?.cancel();
    _comboDecayTimer = Timer(const Duration(milliseconds: comboWindowMs), () {
      if (_combo == 0) return;
      _combo = 0;
      _burstFiredThisRun = false;
      _emit(loaded: true);
    });
  }

  int buyProducer(String id, int count) {
    final def = producerCatalog.firstWhere((p) => p.id == id);
    final oldLv = _save.producerLevels[id] ?? 0;
    final n = count < 0 ? def.maxAffordable(_save.gold, oldLv) : count;
    if (n <= 0) return 0;
    final cost = def.costForNext(oldLv, n);
    if (_save.gold < cost) return 0;
    final newLv = oldLv + n;
    _save.gold -= cost;
    _decayPurchasedGoldUnconverted(cost);
    _save.stats.totalGoldSpent += cost;
    _save.run.goldSpent += cost;
    _save.run.producerLevelsBought += n;
    _save.producerLevels[id] = newLv;
    _incMission('daily_upgrade_30', n, daily: true);
    _incMission('weekly_upgrade_200', n, daily: false);
    final ticketGain =
        _milestoneTicketUpTo(newLv) - _milestoneTicketUpTo(oldLv);
    if (ticketGain > 0) _save.ticket += ticketGain;
    _emit(loaded: true);
    unawaited(_persist());
    return n;
  }

  int buyTapUpgrade(String id, int count) {
    final def = tapUpgradeCatalog.firstWhere((p) => p.id == id);
    final lv = _save.tapUpgradeLevels[id] ?? 0;
    final n = count < 0 ? def.maxAffordable(_save.gold, lv) : count;
    if (n <= 0) return 0;
    final cost = def.costForNext(lv, n);
    if (_save.gold < cost) return 0;
    _save.gold -= cost;
    _decayPurchasedGoldUnconverted(cost);
    _save.stats.totalGoldSpent += cost;
    _save.run.goldSpent += cost;
    _save.run.tapUpgradesBought += n;
    _save.run.boughtAnyTapUpgrade = true;
    _save.tapUpgradeLevels[id] = lv + n;
    _save.stats.totalTapUpgradesBought += n;
    _incMission('daily_upgrade_30', n, daily: true);
    _incMission('weekly_upgrade_200', n, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return n;
  }

  bool buyPrestigeUpgrade(String id) {
    final def = prestigeUpgradeById(id);
    final lv = _save.prestigeUpgradeLevels[id] ?? 0;
    if (lv >= def.maxLevel) return false;
    final cost = def.costAt(lv);
    if (_save.prestigeCoins < cost) return false;
    _save.prestigeCoins -= cost;
    _save.prestigeUpgradeLevels[id] = lv + 1;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  bool _canUnlockAscensionCore() {
    if (_save.prestigeCount < 5) return false;
    for (final def in producerCatalog) {
      if (def.category != ProducerCategory.transcendent) continue;
      if ((_save.producerLevels[def.id] ?? 0) >= 25) return true;
    }
    return false;
  }

  bool buyAscensionCore() {
    if (!_canUnlockAscensionCore()) return false;
    final cost = ascensionCoreCostAt(_save.ascensionCoreLevel);
    if (_save.prestigeCoins < cost) return false;
    _save.prestigeCoins -= cost;
    _save.ascensionCoreLevel += 1;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gold-exchange shop helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Drain `amount` from the "this gold came from the exchange" tracker.
  /// Once the tracker hits zero, prestige-coin math sees the player's full
  /// currentGold again. Call this at every gold-spend site.
  void _decayPurchasedGoldUnconverted(double amount) {
    if (amount <= 0 || _save.purchasedGoldUnconverted <= 0) return;
    if (amount >= _save.purchasedGoldUnconverted) {
      _save.purchasedGoldUnconverted = 0;
    } else {
      _save.purchasedGoldUnconverted -= amount;
    }
  }

  /// Sync `goldExchangeDayKey` / `goldExchangeDailyCount` to today.
  void _rotateGoldExchangeDayIfNeeded(DateTime now) {
    final today = _dayKey(now);
    if (_save.goldExchangeDayKey != today) {
      _save.goldExchangeDayKey = today;
      _save.goldExchangeDailyCount = 0;
    }
  }

  /// Compute (but don't apply) the gold an [offer] would currently yield.
  /// Returns 0 if the offer is unknown. Useful for the UI to show a live
  /// preview underneath each tile.
  double previewGoldExchangeYield(GoldExchangeOffer offer) {
    switch (offer.kind) {
      case GoldExchangeKind.dpsTime:
        final raw = _calcDps() * offer.dpsSeconds * dpsTimeYieldFactor;
        final floor = dpsTimeFloorPerTicket * offer.ticketCost;
        return raw < floor ? floor : raw;
      case GoldExchangeKind.fixed:
        return offer.fixedGold;
    }
  }

  /// True if the fixed-amount line should be hidden because the player's
  /// progression has outgrown it.
  bool get goldExchangeFixedHidden =>
      _save.prestigeCount >= goldExchangeFixedHideAfterPrestiges;

  /// Attempt to spend ticket on a gold-exchange offer.
  GoldExchangeResult buyGoldExchange(String offerId) {
    final offer = goldExchangeOffers.firstWhere(
      (o) => o.id == offerId,
      orElse: () => throw ArgumentError('Unknown exchange offer: $offerId'),
    );
    final now = DateTime.now();
    _rotateGoldExchangeDayIfNeeded(now);

    if (_save.ticket < offer.ticketCost) {
      return const GoldExchangeResult(
        ok: false,
        goldGranted: 0,
        reason: GoldExchangeFailureReason.notEnoughTicket,
      );
    }
    if (_save.goldExchangeDailyCount >= goldExchangeDailyLimit) {
      return const GoldExchangeResult(
        ok: false,
        goldGranted: 0,
        reason: GoldExchangeFailureReason.dailyCapReached,
      );
    }
    if (_save.goldExchangePrestigeCount >= goldExchangePrestigeLimit) {
      return const GoldExchangeResult(
        ok: false,
        goldGranted: 0,
        reason: GoldExchangeFailureReason.prestigeCapReached,
      );
    }
    if (offer.dailyCap > 0) {
      // Only the 8h pack uses this today, but the model is generic.
      if (offer.id == 'dps_8h' &&
          _save.goldExchangeEightHourDayKey == _dayKey(now)) {
        return const GoldExchangeResult(
          ok: false,
          goldGranted: 0,
          reason: GoldExchangeFailureReason.perOfferCapReached,
        );
      }
    }

    final goldGranted = previewGoldExchangeYield(offer);
    _save.ticket -= offer.ticketCost;
    _save.gold += goldGranted;
    // Important: do NOT touch totalGoldEarned. The whole point of this
    // tracker is to keep purchased gold out of prestige-coin math until
    // the player actually spends it on producers/upgrades.
    _save.purchasedGoldUnconverted += goldGranted;
    _save.goldExchangeDailyCount++;
    _save.goldExchangePrestigeCount++;
    if (offer.id == 'dps_8h') {
      _save.goldExchangeEightHourDayKey = _dayKey(now);
    }
    _emit(loaded: true);
    unawaited(_persist());
    return GoldExchangeResult(
      ok: true,
      goldGranted: goldGranted,
      reason: GoldExchangeFailureReason.none,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main coaster enhancement
  // ─────────────────────────────────────────────────────────────────────────

  /// Stream of milestone awards / tier evolutions / first-naming prompts.
  final _mainCoasterEvents = StreamController<MainCoasterEvent>.broadcast();
  Stream<MainCoasterEvent> get mainCoasterEventStream =>
      _mainCoasterEvents.stream;

  /// Set/replace the main coaster's nickname. Empty/whitespace input is
  /// rejected so the UI can default to a placeholder.
  bool setMainCoasterName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    _save.mainCoasterName = trimmed;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  /// Attempt one main coaster enhancement step.
  ///
  /// Stage transitions follow these rules:
  ///   • Success → +1 stage (clamped at mainCoasterEnhanceMaxStage).
  ///   • Failure on ticket path → no stage change.
  ///   • Failure on gold path → −penalty unless [useProtection] is set.
  ///   • Failure on hybrid → splits the difference: gold-track penalty
  ///     applies, but protection is implied (so no stage loss) at the
  ///     cost of full hybrid pricing.
  MainCoasterEnhanceAttemptResult attemptMainCoasterEnhance({
    required MainCoasterEnhanceCurrency currency,
    MainCoasterBoostLevel boostLevel = MainCoasterBoostLevel.none,
    bool useProtection = false,
  }) {
    final currentStage = _save.mainCoasterStage;
    if (currentStage >= mainCoasterEnhanceMaxStage) {
      return const MainCoasterEnhanceAttemptResult(
        ok: false,
        success: false,
        previousStage: 0,
        newStage: 0,
        reason: MainCoasterEnhanceFailure.alreadyMaxed,
      );
    }
    final targetStage = currentStage + 1;
    final cost = mainCoasterEnhanceCost(targetStage);

    // Compute final cost based on currency choice.
    double goldCost = 0;
    int ticketCost = 0;
    double successRate;
    final boost = boostLevel;
    final boostTicketCost = boost.ticketCost;
    final protection =
        currency == MainCoasterEnhanceCurrency.gold && useProtection;

    switch (currency) {
      case MainCoasterEnhanceCurrency.gold:
        goldCost = cost.goldCost;
        ticketCost = boostTicketCost +
            (protection ? mainCoasterProtectionTicketCost : 0);
        successRate =
            (cost.goldSuccessBase + boost.successBonus).clamp(0.0, 1.0);
      case MainCoasterEnhanceCurrency.ticket:
        ticketCost = cost.ticketCost + boostTicketCost;
        successRate =
            (cost.ticketSuccessBase + boost.successBonus).clamp(0.0, 1.0);
      case MainCoasterEnhanceCurrency.hybrid:
        goldCost = cost.goldCost * mainCoasterHybridGoldMultiplier;
        ticketCost =
            (cost.ticketCost * mainCoasterHybridTicketMultiplier).round() +
                boostTicketCost;
        successRate = (cost.goldSuccessBase +
                mainCoasterHybridSuccessBonus +
                boost.successBonus)
            .clamp(0.0, 1.0);
    }

    if (_save.gold < goldCost) {
      return MainCoasterEnhanceAttemptResult(
        ok: false,
        success: false,
        previousStage: currentStage,
        newStage: currentStage,
        reason: MainCoasterEnhanceFailure.notEnoughGold,
      );
    }
    if (_save.ticket < ticketCost) {
      return MainCoasterEnhanceAttemptResult(
        ok: false,
        success: false,
        previousStage: currentStage,
        newStage: currentStage,
        reason: MainCoasterEnhanceFailure.notEnoughTicket,
      );
    }

    if (goldCost > 0) {
      _save.gold -= goldCost;
      _decayPurchasedGoldUnconverted(goldCost);
      _save.stats.totalGoldSpent += goldCost;
      _save.run.goldSpent += goldCost;
    }
    if (ticketCost > 0) {
      _save.ticket -= ticketCost;
    }

    final roll = _random.nextDouble();
    final success = roll < successRate;
    final previousStage = currentStage;
    final firstEverEnhance =
        currentStage == 0 && _save.mainCoasterHighestStage == 0;
    int newStage = currentStage;
    int penaltyApplied = 0;
    if (success) {
      newStage = currentStage + 1;
    } else if (currency == MainCoasterEnhanceCurrency.ticket) {
      // Ticket-track failures never lose a stage.
    } else if (currency == MainCoasterEnhanceCurrency.hybrid) {
      // Hybrid paid the full price, treat as protected.
    } else if (!protection) {
      penaltyApplied = cost.penaltyOnFail.clamp(0, currentStage);
      newStage = currentStage - penaltyApplied;
    }
    _save.mainCoasterStage = newStage.clamp(0, mainCoasterEnhanceMaxStage);
    _save.mainCoasterEnhanceAttempts++;

    // Milestone + tier-up detection on the *new* stage.
    final wasNewHigh = _save.mainCoasterStage > _save.mainCoasterHighestStage;
    if (wasNewHigh) {
      _save.mainCoasterHighestStage = _save.mainCoasterStage;
    }
    final crossedTierUp = success &&
        mainCoasterTierIndex(newStage) > mainCoasterTierIndex(previousStage);
    if (crossedTierUp) {
      final tierIdx = mainCoasterTierIndex(newStage);
      if (!_save.mainCoasterTiersShown.contains(tierIdx)) {
        _save.mainCoasterTiersShown.add(tierIdx);
        _mainCoasterEvents.add(
          MainCoasterEvent.tierUp(
            tierIndex: tierIdx,
            tierName: mainCoasterTiers[tierIdx].name,
            stage: newStage,
          ),
        );
      }
    }
    MainCoasterMilestoneReward? milestone;
    if (success && wasNewHigh) {
      milestone = mainCoasterMilestoneAt(newStage);
      if (milestone != null) {
        if (milestone.ticket > 0) _save.ticket += milestone.ticket;
        if (milestone.collectionBonusFraction != null) {
          _save.mainCoasterCollectionBonusFraction +=
              milestone.collectionBonusFraction!;
        }
        _mainCoasterEvents.add(MainCoasterEvent.milestone(milestone));
      }
    }
    if (firstEverEnhance && success && _save.mainCoasterName == null) {
      _mainCoasterEvents.add(const MainCoasterEvent.namingPrompt());
    }

    _emit(loaded: true);
    unawaited(_persist());

    return MainCoasterEnhanceAttemptResult(
      ok: true,
      success: success,
      previousStage: previousStage,
      newStage: newStage,
      reason: success
          ? MainCoasterEnhanceFailure.none
          : MainCoasterEnhanceFailure.rolledFailure,
      penaltyApplied: penaltyApplied,
      goldSpent: goldCost,
      ticketSpent: ticketCost,
      crossedTierUp: crossedTierUp,
      milestoneReward: milestone,
    );
  }

  bool prestige() {
    final coins = state.prestigeCoinsAvailable;
    if (coins <= 0) return false;
    _save.prestigeCoins += coins;
    _save.prestigeCount += 1;
    _incMission('weekly_prestige_5', 1, daily: false);
    _save.gold = 0;
    _save.totalGoldEarned = 0;
    _save.purchasedGoldUnconverted = 0;
    _save.goldExchangePrestigeCount = 0;
    _save.producerLevels.clear();
    _save.tapUpgradeLevels.clear();
    _combo = 0;
    _lastTapAt = null;
    _burstFiredThisRun = false;
    _resetStockMarketOnPrestige();
    _unlockNoXChallenges();
    _save.run.reset();
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  /// Fire challenge achievements that depend on "no X this run" conditions
  /// — they need to read run state at the moment of prestige completion,
  /// before reset wipes it.
  void _unlockNoXChallenges() {
    if (_save.prestigeCount < 1) return;
    void unlock(String id) {
      if (_save.unlockedAchievements.contains(id)) return;
      final def = achievementById(id);
      if (def == null) return;
      _save.unlockedAchievements.add(def.id);
      _save.ticket += def.ticketReward;
      _achievementUnlocks.add(def);
    }

    if (!_save.run.usedAnySkill) unlock('ch_no_skill');
    if (!_save.run.usedAnyBooster) unlock('ch_no_booster');
    if (!_save.run.boughtAnyTapUpgrade) unlock('ch_no_tap_upgrade');
  }

  /// Wipe per-run stock holdings on prestige. Lifetime trading stats
  /// (totalTradesCount, totalFeesPaid, totalRealizedProfit,
  /// totalDividendsClaimed) are kept since they're a permanent track.
  void _resetStockMarketOnPrestige() {
    final m = _save.market;
    final eligible = _save.totalGoldEarned >= stockMarketLifetimeGoldTrigger;
    for (final def in regionCatalog) {
      final st = m.regions[def.id];
      if (st == null) continue;
      st.shares = 0;
      st.avgCost = 0;
      st.pendingDividend = 0;
      st.lastAccrualAt = null;
      st.currentPrice = def.initialPrice;
      st.intrinsicPrice = def.initialPrice;
      st.recentCandles.clear();
      st.formingCandle = null;
      // Only the first region stays unlocked — and only if the player has
      // already crossed the lifetime-gold gate (which is preserved across
      // prestige). All later regions must be re-earned via the 20%-of-prev
      // ownership chain in the new run.
      st.unlocked = def.unlockOrder == 1 && eligible;
    }
  }

  void claimOfflineReward(OfflineReward r) {
    _save.gold += r.gold;
    _save.totalGoldEarned += r.gold;
    _save.stats.lifetimeGold += r.gold;
    if (r.ticketBonus > 0) {
      _save.ticket += r.ticketBonus;
    }
    _emit(loaded: true);
    unawaited(_persist());
  }

  OfflineReward? consumeOfflineReward() {
    final r = _pendingOffline;
    _pendingOffline = null;
    return r;
  }

  void setHaptic(bool value) {
    _save.settings.haptic = value;
    _emit(loaded: true);
    unawaited(_persist());
  }

  void setSound(bool value) {
    _save.settings.sound = value;
    _emit(loaded: true);
    unawaited(_persist());
  }

  void setDarkMode(bool value) {
    _save.settings.darkMode = value;
    _emit(loaded: true);
    unawaited(_persist());
  }

  void setHighContrast(bool value) {
    _save.settings.highContrast = value;
    _emit(loaded: true);
    unawaited(_persist());
  }

  void setTextScale(double value) {
    _save.settings.textScale = value.clamp(0.9, 1.3).toDouble();
    _emit(loaded: true);
    unawaited(_persist());
  }

  void setReduceTapHaptics(bool value) {
    _save.settings.reduceTapHaptics = value;
    _emit(loaded: true);
    unawaited(_persist());
  }

  void setTutorialSeen(bool value) {
    _save.settings.tutorialSeen = value;
    _emit(loaded: true);
    unawaited(_persist());
  }

  /// Returns (and clears) the pending daily bonus computed at load time.
  DailyBonus? consumePendingDaily() {
    final r = _pendingDaily;
    _pendingDaily = null;
    return r;
  }

  void claimDailyBonus(DailyBonus bonus) {
    _save.ticket += bonus.ticket;
    _save.dailyStreak = bonus.streak;
    if (bonus.streak > _save.stats.maxDailyStreak) {
      _save.stats.maxDailyStreak = bonus.streak;
    }
    _save.lastDailyClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
  }

  bool claimMission(String id, {required bool daily}) {
    _rotateMissionWindowsIfNeeded();
    final defs = daily ? _dailyMissionById : _weeklyMissionById;
    final def = defs[id];
    if (def == null) return false;
    final progress =
        daily ? _save.dailyMissionProgress : _save.weeklyMissionProgress;
    final claimed =
        daily ? _save.dailyMissionClaimed : _save.weeklyMissionClaimed;
    if (claimed.contains(id)) return false;
    if ((progress[id] ?? 0) < def.target) return false;
    claimed.add(id);
    _save.ticket += def.rewardTicket;
    _save.prestigeCoins += def.rewardPrestigeCoins;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  /// Claim every completed-but-unclaimed mission across both daily and
  /// weekly tracks. Returns aggregate reward totals (count, ticket, coins).
  ({int count, int ticket, int coins}) claimAllMissions() {
    _rotateMissionWindowsIfNeeded();
    var count = 0;
    var ticket = 0;
    var coins = 0;
    void sweep({required bool daily}) {
      final defs = daily ? _dailyMissionById : _weeklyMissionById;
      final progress =
          daily ? _save.dailyMissionProgress : _save.weeklyMissionProgress;
      final claimed =
          daily ? _save.dailyMissionClaimed : _save.weeklyMissionClaimed;
      for (final entry in defs.entries) {
        final id = entry.key;
        final def = entry.value;
        if (claimed.contains(id)) continue;
        if ((progress[id] ?? 0) < def.target) continue;
        claimed.add(id);
        ticket += def.rewardTicket;
        coins += def.rewardPrestigeCoins;
        count++;
      }
    }

    sweep(daily: true);
    sweep(daily: false);
    if (count == 0) return (count: 0, ticket: 0, coins: 0);
    _save.ticket += ticket;
    _save.prestigeCoins += coins;
    _emit(loaded: true);
    unawaited(_persist());
    return (count: count, ticket: ticket, coins: coins);
  }

  // ============ Premium shop ============

  bool get adsRemoved => _save.adsRemoved;

  bool get starterPackagePurchased => _save.starterPackagePurchased;

  bool get firstPurchasePackageClaimed => _save.firstPurchasePackageClaimed;

  bool get masterPackagePurchased => _save.masterPackagePurchased;

  DateTime? get monthlyPassExpiresAt => _save.monthlyPassExpiresAt;

  bool get hasActiveMonthlyPass {
    final expiresAt = _save.monthlyPassExpiresAt;
    return expiresAt != null && expiresAt.isAfter(DateTime.now());
  }

  int get monthlyPassDaysRemaining {
    final expiresAt = _save.monthlyPassExpiresAt;
    if (expiresAt == null) return 0;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return max(
      1,
      (remaining.inSeconds + Duration.secondsPerDay - 1) ~/
          Duration.secondsPerDay,
    );
  }

  int get monthlyPassClaimableDays {
    if (!hasActiveMonthlyPass) return 0;
    final now = DateTime.now();
    final lastClaim = _save.monthlyPassLastClaimAt;
    if (lastClaim == null) return 1;
    final days = _dateOnly(now).difference(_dateOnly(lastClaim)).inDays;
    if (days <= 0) return 0;
    return min(days, monthlyTicketPassMissedClaimCapDays);
  }

  int get monthlyPassClaimableTicket =>
      monthlyPassClaimableDays * monthlyTicketPassDailyTicket;

  PremiumPurchaseResult purchasePremiumProduct(String productId) {
    switch (productId) {
      case premiumAdRemovalProductId:
        if (_save.adsRemoved) {
          return const PremiumPurchaseResult(
            ok: false,
            message: '이미 광고 제거가 적용되어 있어요',
          );
        }
        _save.adsRemoved = true;
        _emit(loaded: true);
        unawaited(_persist());
        return const PremiumPurchaseResult(
          ok: true,
          message: '광고 제거가 적용됐어요',
        );

      case premiumMonthlyTicketPassProductId:
        final now = DateTime.now();
        final wasActive = hasActiveMonthlyPass;
        final currentExpiresAt = _save.monthlyPassExpiresAt;
        final base = currentExpiresAt != null && currentExpiresAt.isAfter(now)
            ? currentExpiresAt
            : now;
        _save.monthlyPassExpiresAt =
            base.add(const Duration(days: monthlyTicketPassDurationDays));
        if (!wasActive) _save.monthlyPassLastClaimAt = now;
        _save.ticket += monthlyTicketPassImmediateTicket;
        _emit(loaded: true);
        unawaited(_persist());
        return const PremiumPurchaseResult(
          ok: true,
          message: '월간 티켓 보급권이 적용됐어요',
          ticketGranted: monthlyTicketPassImmediateTicket,
        );

      case premiumStarterPackageProductId:
        if (_save.starterPackagePurchased) {
          return const PremiumPurchaseResult(
            ok: false,
            message: '초보자 패키지는 계정당 1회만 구매할 수 있어요',
          );
        }
        _save.starterPackagePurchased = true;
        _save.ticket += starterPackageTicket;
        final bonusSummon = _doOnePull(
          guaranteedRPlus: true,
          forceSrPlus: true,
        );
        _save.run.summons++;
        _incMission('daily_summon_15', 1, daily: true);
        _incMission('weekly_summon_120', 1, daily: false);
        _applyBooster(
          BoosterType.dps,
          2.0,
          starterPackageDpsBoostDurationSec,
        );
        _save.stats.boostersPurchased++;
        _save.run.boostersUsed++;
        _save.run.usedAnyBooster = true;
        _emit(loaded: true);
        unawaited(_persist());
        return PremiumPurchaseResult(
          ok: true,
          message: '초보자 패키지가 지급됐어요',
          ticketGranted: starterPackageTicket,
          bonusSummon: bonusSummon,
        );

      case premiumFirstPurchaseProductId:
        if (_save.firstPurchasePackageClaimed) {
          return const PremiumPurchaseResult(
            ok: false,
            message: '첫 결제 패키지는 계정당 1회만 구매할 수 있어요',
          );
        }
        _save.firstPurchasePackageClaimed = true;
        _save.ticket += firstPurchasePackageTicket;
        final firstSummon = _doOnePull(
          guaranteedRPlus: true,
          forceSrPlus: true,
        );
        _save.run.summons++;
        _incMission('daily_summon_15', 1, daily: true);
        _incMission('weekly_summon_120', 1, daily: false);
        _emit(loaded: true);
        unawaited(_persist());
        return PremiumPurchaseResult(
          ok: true,
          message: '첫 결제 패키지가 지급됐어요',
          ticketGranted: firstPurchasePackageTicket,
          bonusSummon: firstSummon,
        );

      case premiumTicketSmallProductId:
        return _grantTicketPack(ticketSmallTicket, '티켓 꾸러미 (소)');
      case premiumTicketMediumProductId:
        return _grantTicketPack(ticketMediumTicket, '티켓 꾸러미 (중)');
      case premiumTicketLargeProductId:
        return _grantTicketPack(ticketLargeTicket, '티켓 꾸러미 (대)');
      case premiumTicketXLargeProductId:
        return _grantTicketPack(ticketXLargeTicket, '티켓 꾸러미 (특대)');

      case premiumSeasonPassProductId:
        final now = DateTime.now();
        final wasActive = hasActiveSeasonPass;
        final currentExpiresAt = _save.seasonPassExpiresAt;
        final base = currentExpiresAt != null && currentExpiresAt.isAfter(now)
            ? currentExpiresAt
            : now;
        _save.seasonPassExpiresAt =
            base.add(const Duration(days: seasonPassDurationDays));
        if (!wasActive) {
          _save.seasonPassLastClaimAt = now;
          _save.seasonPassLastWeeklyClaimAt = null;
        }
        _emit(loaded: true);
        unawaited(_persist());
        return const PremiumPurchaseResult(
          ok: true,
          message: '시즌 패스가 적용됐어요',
        );

      case premiumMasterPackageProductId:
        if (_save.masterPackagePurchased) {
          return const PremiumPurchaseResult(
            ok: false,
            message: '마스터 패키지는 계정당 1회만 구매할 수 있어요',
          );
        }
        _save.masterPackagePurchased = true;
        _save.ticket += masterPackageTicket;
        final masterSummon = _doOnePull(
          guaranteedRPlus: true,
          forceSrPlus: true,
        );
        _save.run.summons++;
        _incMission('daily_summon_15', 1, daily: true);
        _incMission('weekly_summon_120', 1, daily: false);
        _applyBooster(
          BoosterType.dps,
          2.0,
          masterPackageBoosterDurationSec,
        );
        _applyBooster(
          BoosterType.tap,
          2.0,
          masterPackageBoosterDurationSec,
        );
        _save.stats.boostersPurchased += 2;
        _save.run.boostersUsed += 2;
        _save.run.usedAnyBooster = true;
        _emit(loaded: true);
        unawaited(_persist());
        return PremiumPurchaseResult(
          ok: true,
          message: '마스터 패키지가 지급됐어요',
          ticketGranted: masterPackageTicket,
          bonusSummon: masterSummon,
        );

      default:
        return const PremiumPurchaseResult(
          ok: false,
          message: '알 수 없는 상품이에요',
        );
    }
  }

  PremiumPurchaseResult _grantTicketPack(int amount, String label) {
    _save.ticket += amount;
    _emit(loaded: true);
    unawaited(_persist());
    return PremiumPurchaseResult(
      ok: true,
      message: '$label 지급 완료',
      ticketGranted: amount,
    );
  }

  // Season pass helpers (mirror the monthly pass pattern).
  DateTime? get seasonPassExpiresAt => _save.seasonPassExpiresAt;

  bool get hasActiveSeasonPass {
    final expiresAt = _save.seasonPassExpiresAt;
    return expiresAt != null && expiresAt.isAfter(DateTime.now());
  }

  int get seasonPassDaysRemaining {
    final expiresAt = _save.seasonPassExpiresAt;
    if (expiresAt == null) return 0;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return max(
      1,
      (remaining.inSeconds + Duration.secondsPerDay - 1) ~/
          Duration.secondsPerDay,
    );
  }

  int get seasonPassClaimableDays {
    if (!hasActiveSeasonPass) return 0;
    final now = DateTime.now();
    final lastClaim = _save.seasonPassLastClaimAt;
    if (lastClaim == null) return 1;
    final days = _dateOnly(now).difference(_dateOnly(lastClaim)).inDays;
    if (days <= 0) return 0;
    return min(days, seasonPassMissedClaimCapDays);
  }

  int get seasonPassClaimableTicket =>
      seasonPassClaimableDays * seasonPassDailyTicket;

  bool get seasonPassWeeklyAvailable {
    if (!hasActiveSeasonPass) return false;
    final last = _save.seasonPassLastWeeklyClaimAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inDays >=
        seasonPassWeeklyIntervalDays;
  }

  int claimSeasonPassDailyTicket() {
    final days = seasonPassClaimableDays;
    if (days <= 0) return 0;
    final amount = days * seasonPassDailyTicket;
    _save.ticket += amount;
    _save.seasonPassLastClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
    return amount;
  }

  int claimSeasonPassWeeklyTicket() {
    if (!seasonPassWeeklyAvailable) return 0;
    _save.ticket += seasonPassWeeklyTicket;
    _save.seasonPassLastWeeklyClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
    return seasonPassWeeklyTicket;
  }

  // First-purchase popup gating.
  bool get firstPurchasePopupEligible {
    if (_save.firstPurchasePackageClaimed) return false;
    if (_save.firstPurchasePopupShown) return false;
    final firstLaunch = _save.firstLaunchAt;
    if (firstLaunch == null) return false;
    final age = DateTime.now().difference(firstLaunch);
    return age <= const Duration(hours: 24);
  }

  void markFirstPurchasePopupShown() {
    _save.firstPurchasePopupShown = true;
    _emit(loaded: true);
    unawaited(_persist());
  }

  // Bulk grant for milestones / rewarded ads / external testing.
  void grantTicket(int amount) {
    if (amount <= 0) return;
    _save.ticket += amount;
    _emit(loaded: true);
    unawaited(_persist());
  }

  /// Bonus gold grant from rewarded ads (offline-reward x2 etc.). Counts
  /// toward lifetime/totalGoldEarned because the player earned it through
  /// ad engagement, not by paying with ticket.
  void grantBonusGold(double amount) {
    if (amount <= 0) return;
    _save.gold += amount;
    _save.totalGoldEarned += amount;
    _save.stats.lifetimeGold += amount;
    _emit(loaded: true);
    unawaited(_persist());
  }

  int claimMonthlyPassTicket() {
    final days = monthlyPassClaimableDays;
    if (days <= 0) return 0;
    final amount = days * monthlyTicketPassDailyTicket;
    _save.ticket += amount;
    _save.monthlyPassLastClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
    return amount;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  // ============ Boosters + ads ============

  /// Attempt to buy [offer] with ticket. Returns true on success.
  bool buyBoosterWithTicket(BoosterOffer offer) {
    if (_save.ticket < offer.ticketCost) return false;
    _save.ticket -= offer.ticketCost;
    _applyBooster(offer.type, offer.multiplier, offer.durationSec);
    _save.stats.boostersPurchased++;
    _save.run.boostersUsed++;
    _save.run.usedAnyBooster = true;
    _incMission('daily_booster_1', 1, daily: true);
    _incMission('weekly_booster_5', 1, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  /// Dev stub for ad rewards — in production this would actually show an
  /// ad via AdMob / UnityAds and only grant on the completion callback.
  /// Right now we just hand the reward out for testing.
  void grantAdBooster(BoosterOffer offer) {
    _applyBooster(offer.type, offer.multiplier, offer.durationSec);
    _save.stats.boostersPurchased++;
    _save.run.boostersUsed++;
    _save.run.usedAnyBooster = true;
    _incMission('daily_booster_1', 1, daily: true);
    _incMission('weekly_booster_5', 1, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
  }

  void _applyBooster(BoosterType type, double multiplier, int durationSec) {
    _reapBoosters();
    final now = DateTime.now();
    // If the same type+multiplier is already active, extend its timer
    // instead of stacking a second identical booster.
    final existing = _save.activeBoosters.indexWhere(
      (b) => b.type == type && b.multiplier == multiplier,
    );
    if (existing >= 0) {
      final prev = _save.activeBoosters[existing];
      final base = prev.expiresAt.isAfter(now) ? prev.expiresAt : now;
      _save.activeBoosters[existing] = Booster(
        type: type,
        multiplier: multiplier,
        expiresAt: base.add(Duration(seconds: durationSec)),
      );
    } else {
      _save.activeBoosters.add(Booster(
        type: type,
        multiplier: multiplier,
        expiresAt: now.add(Duration(seconds: durationSec)),
      ));
    }
    if (type == BoosterType.autoTap) _ensureAutoTapTimer();
  }

  void _ensureAutoTapTimer() {
    if (_autoTapTimer != null) return;
    _autoTapTimer = Timer.periodic(
      const Duration(milliseconds: autoTapIntervalMs),
      (_) {
        if (!_autoTapActive()) {
          _autoTapTimer?.cancel();
          _autoTapTimer = null;
          _emit(loaded: true);
          return;
        }
        tapWithFeedback();
      },
    );
  }

  // ============ Skills ============

  /// Returns the moment a skill becomes ready, or null if it's already
  /// usable. UI uses this to render cooldown overlays.
  DateTime? skillCooldownEndsAt(SkillId id) {
    final ready = _save.skillReadyAt[id.id];
    if (ready == null) return null;
    return ready.isAfter(DateTime.now()) ? ready : null;
  }

  SkillResult useSkill(SkillId id) {
    final def = skillDefFor(id);
    final cooldownEnd = skillCooldownEndsAt(id);
    if (cooldownEnd != null) {
      return SkillResult(
        id: id,
        ok: false,
        message: '아직 쿨타임이에요',
      );
    }
    final now = DateTime.now();
    SkillResult result;
    switch (id) {
      case SkillId.slashBurst:
        final reward = _calcDps() * slashBurstWorthSeconds;
        _save.gold += reward;
        _save.totalGoldEarned += reward;
        _save.stats.lifetimeGold += reward;
        result = SkillResult(
          id: id,
          ok: true,
          message: '퍼레이드 피버!',
          payload: reward,
        );
      case SkillId.comboSurge:
        _comboSurgeUntil = now.add(const Duration(seconds: 10));
        result = const SkillResult(
          id: SkillId.comboSurge,
          ok: true,
          message: '10초간 콤보 폭주!',
        );
      case SkillId.ticketGather:
        _save.ticket += ticketGatherAmount;
        result = SkillResult(
          id: SkillId.ticketGather,
          ok: true,
          message: '티켓 +$ticketGatherAmount',
          payload: ticketGatherAmount.toDouble(),
        );
    }
    _save.skillReadyAt[id.id] = now.add(def.cooldown);
    _save.stats.skillsUsed++;
    _save.run.skillsUsed++;
    _save.run.usedAnySkill = true;
    _incMission('daily_skill_5', 1, daily: true);
    _incMission('weekly_skill_50', 1, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return result;
  }

  /// Called by the home screen when a golden VIP guest is handled. Grants
  /// gold equal to [slimeRewardTaps] × current tap power and
  /// returns the awarded amount so the UI can show a floating number.
  double defeatGoldenSlime() {
    final reward = _calcTapPower() * slimeRewardTaps;
    _save.gold += reward;
    _save.totalGoldEarned += reward;
    _save.stats.lifetimeGold += reward;
    _save.stats.slimesDefeated++;
    _save.run.slimesDefeated++;
    _incMission('daily_slime_5', 1, daily: true);
    _incMission('weekly_slime_40', 1, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return reward;
  }

  /// Estimated reward shown on the VIP response bar so the player can see what
  /// finishing it off is worth at the current moment.
  double get slimePreviewReward => _calcTapPower() * slimeRewardTaps;

  // ============ Coaster dismantle ============

  /// Returns the amount of ticket that dismantling [coasterId] would refund,
  /// or 0 if the coaster can't be dismantled.
  int dismantleRefund(String coasterId) {
    final lv = _save.ownedCoasters[coasterId] ?? 0;
    if (lv <= 0) return 0;
    if (_save.equippedCoasterId == coasterId) return 0;
    final CoasterDef def;
    try {
      def = coasterById(coasterId);
    } catch (_) {
      return 0;
    }
    return _dismantleTicketPerLevel(def.tier) * lv;
  }

  int _dismantleTicketPerLevel(CoasterTier tier) {
    return switch (tier) {
      CoasterTier.n => 2,
      CoasterTier.r => 5,
      CoasterTier.sr => 12,
      CoasterTier.ssr => 25,
      CoasterTier.lr => 40,
      CoasterTier.ur => 60,
    };
  }

  /// Dismantle an owned, non-equipped coaster. Returns ticket granted (0 on
  /// failure — usually because the coaster is equipped or not owned).
  int dismantleCoaster(String coasterId) {
    final refund = dismantleRefund(coasterId);
    if (refund <= 0) return 0;
    _save.ownedCoasters.remove(coasterId);
    for (var i = 0; i < _save.formationCoasterIds.length; i++) {
      if (_save.formationCoasterIds[i] == coasterId) {
        _save.formationCoasterIds[i] = null;
      }
    }
    _save.ticket += refund;
    _save.run.coasterDismantles++;
    _emit(loaded: true);
    unawaited(_persist());
    return refund;
  }

  Future<void> resetAll() async {
    await _syncService.wipe();
    _save = SaveData();
    _pendingOffline = null;
    _pendingDaily = null;
    _timeGuardTriggered = false;
    _combo = 0;
    _lastTapAt = null;
    _emit(loaded: true);
    // Push the fresh state up immediately so other devices see the reset
    // without waiting for the next auto-save tick.
    await _persist();
  }

  // ============ Coaster collection / gacha ============

  CoasterTier _rollTier({required bool forceSrPlus}) {
    final pool = forceSrPlus
        ? const [
            CoasterTier.sr,
            CoasterTier.ssr,
            CoasterTier.lr,
            CoasterTier.ur
          ]
        : CoasterTier.values;
    final rates = summonRatesForTotalSummons(_save.stats.totalSummons);
    final totalWeight =
        pool.map((t) => rates[t] ?? 0).fold<double>(0, (a, b) => a + b);
    final roll = _random.nextDouble() * totalWeight;
    double cum = 0;
    for (final t in pool) {
      cum += rates[t] ?? 0;
      if (roll < cum) return t;
    }
    return pool.last;
  }

  CoasterDef _pickRandomOfTier(CoasterTier tier) {
    final pool = coasterCatalog.where((s) => s.tier == tier).toList();
    return pool[_random.nextInt(pool.length)];
  }

  SummonResult _doOnePull({
    required bool guaranteedRPlus,
    bool forceSrPlus = false,
  }) {
    final pityHit =
        !forceSrPlus && _save.summonsSinceHighRare + 1 >= pityThreshold;
    CoasterTier tier;
    if (forceSrPlus || pityHit) {
      tier = _rollTier(forceSrPlus: true);
    } else if (guaranteedRPlus) {
      tier = _rollTier(forceSrPlus: false);
      if (tier == CoasterTier.n) tier = CoasterTier.r;
    } else {
      tier = _rollTier(forceSrPlus: false);
    }
    final def = _pickRandomOfTier(tier);
    final oldLv = _save.ownedCoasters[def.id] ?? 0;
    final wasOwned = oldLv > 0;
    final wasMaxed = oldLv >= CoasterDef.maxLevel;
    final newLv = wasMaxed ? CoasterDef.maxLevel : (wasOwned ? oldLv + 1 : 1);
    _save.ownedCoasters[def.id] = newLv;
    _save.equippedCoasterId ??= def.id;
    if (!wasOwned && !_save.formationCoasterIds.contains(def.id)) {
      final emptySlot =
          _save.formationCoasterIds.indexWhere((id) => id == null);
      if (emptySlot >= 0) _save.formationCoasterIds[emptySlot] = def.id;
    }
    _save.stats.totalSummons++;
    if (tier.index >= CoasterTier.sr.index) {
      _save.summonsSinceHighRare = 0;
    } else {
      _save.summonsSinceHighRare++;
    }
    return SummonResult(
      coaster: def,
      levelAfter: newLv,
      isDuplicate: wasOwned,
      isMaxed: wasMaxed,
    );
  }

  SummonResult? summonOne() {
    if (_save.ticket < summonCostSingle) return null;
    _save.ticket -= summonCostSingle;
    final r = _doOnePull(guaranteedRPlus: false);
    _save.run.summons++;
    _incMission('daily_summon_15', 1, daily: true);
    _incMission('weekly_summon_120', 1, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return r;
  }

  List<SummonResult>? summonTen() {
    if (_save.ticket < summonCostTen) return null;
    _save.ticket -= summonCostTen;
    final results = <SummonResult>[];
    for (int i = 0; i < 10; i++) {
      final isLast = i == 9;
      results.add(_doOnePull(guaranteedRPlus: isLast));
    }
    _save.run.summons += results.length;
    _incMission('daily_summon_15', results.length, daily: true);
    _incMission('weekly_summon_120', results.length, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return results;
  }

  List<SummonResult>? summonHundred() {
    if (_save.ticket < summonCostHundred) return null;
    _save.ticket -= summonCostHundred;
    final results = <SummonResult>[];
    for (int i = 0; i < 100; i++) {
      final isLastOfTenBlock = i % 10 == 9;
      results.add(_doOnePull(guaranteedRPlus: isLastOfTenBlock));
    }
    _save.run.summons += results.length;
    _incMission('daily_summon_15', results.length, daily: true);
    _incMission('weekly_summon_120', results.length, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return results;
  }

  void equipCoaster(String id) {
    if ((_save.ownedCoasters[id] ?? 0) <= 0) return;
    _save.equippedCoasterId = id;
    _save.run.changedEquippedCoaster = true;
    _emit(loaded: true);
    unawaited(_persist());
  }

  Future<void> persist() => _persist();

  // ─────────────────────────────────────────────────────────────────────────
  // Stock market — see docs in region_catalog.dart and stock_market.dart.
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensure RegionState entries exist for every catalog region. The first
  /// region (gyeonggi) is unlocked automatically once the lifetime gold
  /// trigger has been hit; later regions wait for the ownership chain.
  void _bootstrapStockMarket({
    required DateTime now,
    required int loadedVersion,
  }) {
    final m = _save.market;
    for (final def in regionCatalog) {
      final existing = m.regions[def.id];
      if (existing == null) {
        m.regions[def.id] = RegionState(
          regionId: def.id,
          unlocked: def.unlockOrder == 1 &&
              _save.totalGoldEarned >= stockMarketLifetimeGoldTrigger,
          currentPrice: def.initialPrice,
          intrinsicPrice: regionIntrinsicPrice(def.id),
          lastAccrualAt: null,
        );
      } else {
        // Migration: pre-rebalance saves had totalShares=100B and
        // initialPrice 1/10000 of the old post-rebalance value. If the
        // stored price is dramatically below that curve, rescale shares ÷ 10000
        // and avgCost × 10000 so the player's gold-equivalent stays close
        // while moving onto the new units. Candles + intra-tick state are
        // dropped because they're priced in old units.
        const oldToNewShareRatio = 10000;
        final previousInitialPrice =
            _previousStockCurveInitialPrice(def.unlockOrder);
        final looksLegacy = existing.currentPrice > 0 &&
            existing.currentPrice < previousInitialPrice * 0.01;
        if (looksLegacy) {
          existing.shares = (existing.shares / oldToNewShareRatio).floor();
          existing.avgCost = existing.avgCost * oldToNewShareRatio;
          existing.currentPrice = previousInitialPrice;
          existing.intrinsicPrice = previousInitialPrice;
          existing.recentCandles.clear();
          existing.formingCandle = null;
        }
        if (loadedVersion < stockMarketPriceCurveRebalanceVersion) {
          _rebaseStockPriceCurve(def, existing);
        }
        // Heal corrupt prices, e.g. legacy zeros.
        if (existing.currentPrice <= 0)
          existing.currentPrice = def.initialPrice;
        if (existing.intrinsicPrice <= 0) {
          existing.intrinsicPrice = def.initialPrice;
        }
        existing.intrinsicPrice = regionIntrinsicPrice(def.id);
        // Cap accidentally-overshot ownership at the configured max so
        // legacy data stays inside the 80% bound.
        final cap = (def.totalShares * regionMaxOwnershipFraction).floor();
        if (existing.shares > cap) existing.shares = cap;
      }
    }
    // First-region auto-unlock for veterans who already crossed the lifetime
    // gold gate before this system shipped.
    final first = m.regions[regionCatalog.first.id];
    if (first != null &&
        !first.unlocked &&
        _save.totalGoldEarned >= stockMarketLifetimeGoldTrigger) {
      first.unlocked = true;
    }
    _checkRegionUnlocks();
  }

  double _previousStockCurveInitialPrice(int unlockOrder) {
    if (unlockOrder <= 1) return regionCatalog.first.initialPrice;
    return regionCatalog.first.initialPrice * pow(4.5, unlockOrder - 1);
  }

  void _rebaseStockPriceCurve(RegionDef def, RegionState state) {
    final previousPrice = _previousStockCurveInitialPrice(def.unlockOrder);
    if (previousPrice <= 0) return;
    final scale = def.initialPrice / previousPrice;
    final intrinsic = regionIntrinsicPrice(def.id);
    if ((scale - 1.0).abs() < 0.000001) {
      state.intrinsicPrice = intrinsic;
      return;
    }

    if (state.shares <= 0) {
      state.avgCost = 0;
      state.currentPrice = def.initialPrice;
      state.recentCandles.clear();
      state.formingCandle = null;
    } else {
      state.currentPrice *= scale;
      state.avgCost =
          state.avgCost > 0 ? state.avgCost * scale : def.initialPrice;
      for (final candle in state.recentCandles) {
        _scaleCandle(candle, scale);
      }
      final forming = state.formingCandle;
      if (forming != null) _scaleCandle(forming, scale);
    }

    final lo = intrinsic * stockPriceMinFractionOfIntrinsic;
    final hi = intrinsic * stockPriceMaxFractionOfIntrinsic;
    state.currentPrice = state.currentPrice.clamp(lo, hi).toDouble();
    state.intrinsicPrice = intrinsic;
  }

  void _scaleCandle(Candle candle, double scale) {
    candle.open *= scale;
    candle.high *= scale;
    candle.low *= scale;
    candle.close *= scale;
  }

  /// Pay missed dividends for the time the user was away. Capped to the same
  /// offlineMaxHours the rest of the game uses, so an extreme idle window
  /// can't be farmed.
  void _accrueOfflineDividends({required DateTime now}) {
    final m = _save.market;
    for (final state in m.regions.values) {
      if (state.shares <= 0) continue;
      final last = state.lastAccrualAt;
      if (last == null) {
        state.lastAccrualAt = now;
        continue;
      }
      var elapsed = now.difference(last);
      if (elapsed.isNegative) {
        state.lastAccrualAt = now;
        continue;
      }
      // Cap to offlineMaxHours so an enormous gap doesn't print fortunes.
      final maxOffline = const Duration(hours: offlineMaxHours);
      if (elapsed > maxOffline) elapsed = maxOffline;
      final hours = elapsed.inSeconds / dividendIntervalSeconds;
      if (hours <= 0) continue;
      final def = regionDefById(state.regionId);
      final perHour = state.shares *
          state.currentPrice *
          regionEffectiveHourlyYield(def.id);
      state.pendingDividend += perHour * hours;
      state.lastAccrualAt = now;
    }
  }

  /// Box-Muller transform for standard normal samples.
  double _randGauss() {
    if (_spareGaussReady) {
      _spareGaussReady = false;
      return _spareGauss;
    }
    double u1, u2;
    do {
      u1 = _random.nextDouble();
      u2 = _random.nextDouble();
    } while (u1 <= 1e-12);
    final mag = sqrt(-2.0 * log(u1));
    _spareGauss = mag * sin(2.0 * pi * u2);
    _spareGaussReady = true;
    return mag * cos(2.0 * pi * u2);
  }

  /// Step prices, candles, and dividends forward by [ticksElapsed] price
  /// ticks. Each tick represents [stockPriceTickSeconds] real seconds, so a
  /// candle (30s window) accumulates 30 / [stockPriceTickSeconds] ticks per
  /// bar.
  void _runStockSimulation({
    required DateTime now,
    required int ticksElapsed,
  }) {
    if (ticksElapsed <= 0) return;
    final m = _save.market;
    // Per-tick σ: convert per-minute volatility to per-tick.
    // σ_tick = σ_min × √(tickSec / 60).
    final tickFactor = sqrt(stockPriceTickSeconds / 60.0);
    // Mean-reversion is intentionally weak so trends can persist over
    // many ticks before being pulled back. Event probability and shock
    // magnitudes are slightly elevated to make the bounded range
    // (-90% to +1750%) feel reachable in long horizons.
    const volatilityBoost = 1.45;
    const driftPerSec = 0.0003;
    const eventProbPerSec = 0.0015;

    for (final state in m.regions.values) {
      if (!state.unlocked) continue;
      final def = regionDefById(state.regionId);
      final districtBonus = regionCoasterDistrictBonusFraction(def.id);
      state.intrinsicPrice = regionIntrinsicPrice(def.id);
      final sigmaPerTick = def.volatilityPerMinute *
          volatilityBoost *
          (1.0 + districtBonus * 0.12) *
          tickFactor;

      for (var i = 0; i < ticksElapsed; i++) {
        // Mean-reverting drift toward intrinsic price (scaled to tick).
        final drift = (state.intrinsicPrice - state.currentPrice) *
            driftPerSec *
            stockPriceTickSeconds;
        final noise = _randGauss() * sigmaPerTick * state.currentPrice;
        var event = 0.0;
        if (_random.nextDouble() < eventProbPerSec * stockPriceTickSeconds) {
          const shocks = [
            -0.18,
            -0.11,
            -0.055,
            0.055,
            0.11,
            0.18,
            0.26,
          ];
          event = shocks[_random.nextInt(shocks.length)] * state.currentPrice;
        }
        var next = state.currentPrice + drift + noise + event;
        // Clamp to [0.10x, 18.5x] of intrinsic price — i.e. -90% to +1750%
        // off the original market cap.
        final lo = state.intrinsicPrice * stockPriceMinFractionOfIntrinsic;
        final hi = state.intrinsicPrice * stockPriceMaxFractionOfIntrinsic;
        if (next < lo) next = lo;
        if (next > hi) next = hi;
        state.currentPrice = next;

        // Update / start forming candle. Candle bucket is 30s, but ticks
        // arrive every [stockPriceTickSeconds]; so each bucket gets several
        // ticks before rolling over. Use millisecond-precision Duration so
        // a fractional tick interval (e.g. 2.5s) still works.
        final tickOffsetMs =
            ((ticksElapsed - i - 1) * stockPriceTickSeconds * 1000).round();
        final tickInstant = now.subtract(Duration(milliseconds: tickOffsetMs));
        final candleStart = _candleStartFor(tickInstant);
        var forming = state.formingCandle;
        if (forming == null || forming.startedAt != candleStart) {
          if (forming != null) {
            state.recentCandles.add(forming);
            if (state.recentCandles.length > candleHistoryMax) {
              state.recentCandles.removeAt(0);
            }
          }
          forming = Candle.flat(candleStart, state.currentPrice);
          state.formingCandle = forming;
        }
        if (state.currentPrice > forming.high)
          forming.high = state.currentPrice;
        if (state.currentPrice < forming.low) forming.low = state.currentPrice;
        forming.close = state.currentPrice;
        // Volume proxy: amplified by recent move magnitude.
        final pctMove = forming.open == 0
            ? 0.0
            : (state.currentPrice - forming.open).abs() / forming.open;
        forming.volume += 1.0 + pctMove * 5.0 + _random.nextDouble() * 0.4;
      }

      // Hourly dividend accrual.
      if (state.shares > 0) {
        final last = state.lastAccrualAt ?? now;
        final elapsed = now.difference(last).inSeconds;
        if (elapsed >= dividendIntervalSeconds) {
          final hours = elapsed ~/ dividendIntervalSeconds;
          final perHour = state.shares *
              state.currentPrice *
              regionEffectiveHourlyYield(def.id);
          state.pendingDividend += perHour * hours;
          state.lastAccrualAt =
              last.add(Duration(seconds: hours * dividendIntervalSeconds));
        }
        if (state.lastAccrualAt == null) state.lastAccrualAt = now;
      }
    }
    _checkRegionUnlocks();
  }

  DateTime _candleStartFor(DateTime t) {
    final epochSec = t.millisecondsSinceEpoch ~/ 1000;
    final bucket = epochSec - (epochSec % candleWindowSeconds);
    return DateTime.fromMillisecondsSinceEpoch(bucket * 1000, isUtc: false);
  }

  /// Unlock the first region once the per-run gold gate is crossed, then
  /// cascade chain unlocks: when ownership of a region passes
  /// [regionUnlockOwnershipThreshold] the next region opens up.
  ///
  /// Runs on every stock-sim tick (~1s) so post-prestige players see the
  /// market re-open as soon as they re-earn the 1B threshold, instead of
  /// having to relaunch the app for `_bootstrapStockMarket` to notice.
  void _checkRegionUnlocks() {
    final m = _save.market;
    final first = m.regions[regionCatalog.first.id];
    if (first != null &&
        !first.unlocked &&
        _save.totalGoldEarned >= stockMarketLifetimeGoldTrigger) {
      first.unlocked = true;
    }
    for (final def in regionCatalog) {
      final state = m.regions[def.id];
      if (state == null || !state.unlocked) continue;
      final next = nextRegionAfter(def.id);
      if (next == null) continue;
      final nextState = m.regions[next.id];
      if (nextState == null || nextState.unlocked) continue;
      final ownership = state.shares / def.totalShares;
      if (ownership >= regionUnlockOwnershipThreshold) {
        nextState.unlocked = true;
      }
    }
  }

  // Read helpers used by the UI.

  RegionDef regionDef(String id) => regionDefById(id);

  RegionState? regionState(String id) => _save.market.regions[id];

  double regionOwnershipFraction(String id) {
    final st = _save.market.regions[id];
    if (st == null) return 0;
    final def = regionDefById(id);
    return st.shares / def.totalShares;
  }

  /// Estimated next dividend size if held for one full hour at current price.
  double regionHourlyDividendEstimate(String id) {
    final st = _save.market.regions[id];
    if (st == null || st.shares <= 0) return 0;
    return st.shares * st.currentPrice * regionEffectiveHourlyYield(id);
  }

  /// Total pending dividend across all regions.
  double get totalPendingDividend {
    var sum = 0.0;
    for (final st in _save.market.regions.values) {
      sum += st.pendingDividend;
    }
    return sum;
  }

  /// Maximum buyable share count given current gold (after fee), respecting
  /// the global ownership cap.
  int maxBuyableShares(String regionId) {
    final st = _save.market.regions[regionId];
    if (st == null || !st.unlocked) return 0;
    final def = regionDefById(regionId);
    final unitTotalCost = st.currentPrice * (1 + stockTradeFee);
    if (unitTotalCost <= 0) return 0;
    final byGold = (_save.gold / unitTotalCost).floor();
    final maxOwnable = (def.totalShares * regionMaxOwnershipFraction).floor();
    final byCap = maxOwnable - st.shares;
    if (byCap <= 0) return 0;
    return byGold < byCap ? byGold : byCap;
  }

  /// Hard cap on the number of shares a player may own for a region.
  int regionMaxOwnableShares(String regionId) {
    final def = regionDefById(regionId);
    return (def.totalShares * regionMaxOwnershipFraction).floor();
  }

  /// Buy [shares] of [regionId] at current price + 2% fee. Returns the
  /// actual number purchased (0 on failure).
  int buyShares(String regionId, int shares) {
    if (shares <= 0) return 0;
    final st = _save.market.regions[regionId];
    if (st == null || !st.unlocked) return 0;
    final def = regionDefById(regionId);
    final price = st.currentPrice;
    final gross = shares * price;
    final fee = gross * stockTradeFee;
    final total = gross + fee;
    if (_save.gold < total) return 0;
    // Cap at the configured max ownership fraction (e.g. 80%).
    final maxOwnable = (def.totalShares * regionMaxOwnershipFraction).floor();
    final remaining = maxOwnable - st.shares;
    final actualShares = shares > remaining ? remaining : shares;
    if (actualShares <= 0) return 0;
    final actualGross = actualShares * price;
    final actualFee = actualGross * stockTradeFee;
    final actualTotal = actualGross + actualFee;

    _save.gold -= actualTotal;
    _decayPurchasedGoldUnconverted(actualTotal);
    _save.stats.totalGoldSpent += actualTotal;
    _save.run.goldSpent += actualTotal;
    _save.run.stockTrades++;
    _save.run.stockBuys++;
    // Update average cost (weighted average).
    final priorBasis = st.avgCost * st.shares;
    final newShares = st.shares + actualShares;
    st.avgCost = (priorBasis + actualGross) / newShares;
    st.shares = newShares;
    if (st.lastAccrualAt == null) st.lastAccrualAt = DateTime.now();
    _save.market.totalTradesCount++;
    _save.market.totalFeesPaid += actualFee;
    _checkRegionUnlocks();
    _emit(loaded: true);
    unawaited(_persist());
    return actualShares;
  }

  /// Sell [shares] of [regionId] at current price minus 2% fee. Returns
  /// (sharesSold, netProceeds, realizedProfit).
  ({int sharesSold, double netProceeds, double realizedProfit}) sellShares(
      String regionId, int shares) {
    if (shares <= 0) {
      return (sharesSold: 0, netProceeds: 0, realizedProfit: 0);
    }
    final st = _save.market.regions[regionId];
    if (st == null || st.shares <= 0) {
      return (sharesSold: 0, netProceeds: 0, realizedProfit: 0);
    }
    final actual = shares > st.shares ? st.shares : shares;
    final price = st.currentPrice;
    final gross = actual * price;
    final fee = gross * stockTradeFee;
    final net = gross - fee;
    final realized = (price - st.avgCost) * actual - fee;

    _save.gold += net;
    st.shares -= actual;
    if (st.shares == 0) {
      st.avgCost = 0;
      // Stop accruing: a future buy will reset lastAccrualAt.
      st.lastAccrualAt = null;
    }
    _save.market.totalTradesCount++;
    _save.market.totalFeesPaid += fee;
    _save.market.totalRealizedProfit += realized;
    _save.run.stockTrades++;
    _save.run.stockSells++;
    _save.run.stockProfitRealized += realized;
    _save.run.goldEarned += net;
    _emit(loaded: true);
    unawaited(_persist());
    return (sharesSold: actual, netProceeds: net, realizedProfit: realized);
  }

  /// Sell every held share across all regions at the current market price.
  /// Each region counted as one trade for stats consistency. Returns
  /// aggregate (regions touched, total shares, net proceeds, realized
  /// profit).
  ({int regionsSold, int sharesSold, double netProceeds, double realizedProfit})
      sellAllShares() {
    var regionsSold = 0;
    var sharesSold = 0;
    var netTotal = 0.0;
    var realizedTotal = 0.0;
    for (final st in _save.market.regions.values) {
      if (st.shares <= 0) continue;
      final price = st.currentPrice;
      final shares = st.shares;
      final gross = shares * price;
      final fee = gross * stockTradeFee;
      final net = gross - fee;
      final realized = (price - st.avgCost) * shares - fee;

      _save.gold += net;
      st.shares = 0;
      st.avgCost = 0;
      st.lastAccrualAt = null;

      _save.market.totalTradesCount++;
      _save.market.totalFeesPaid += fee;
      _save.market.totalRealizedProfit += realized;
      _save.run.stockTrades++;
      _save.run.stockSells++;
      _save.run.stockProfitRealized += realized;
      _save.run.goldEarned += net;

      regionsSold++;
      sharesSold += shares;
      netTotal += net;
      realizedTotal += realized;
    }
    if (regionsSold == 0) {
      return (
        regionsSold: 0,
        sharesSold: 0,
        netProceeds: 0,
        realizedProfit: 0,
      );
    }
    _emit(loaded: true);
    unawaited(_persist());
    return (
      regionsSold: regionsSold,
      sharesSold: sharesSold,
      netProceeds: netTotal,
      realizedProfit: realizedTotal,
    );
  }

  /// Claim pending dividend on a single region. Returns the amount paid out.
  double claimDividend(String regionId) {
    final st = _save.market.regions[regionId];
    if (st == null) return 0;
    final amount = st.pendingDividend;
    if (amount <= 0) return 0;
    st.pendingDividend = 0;
    _save.gold += amount;
    _save.totalGoldEarned += amount;
    _save.stats.lifetimeGold += amount;
    _save.market.totalDividendsClaimed += amount;
    _save.run.stockDividendsClaimed += amount;
    _save.run.goldEarned += amount;
    _emit(loaded: true);
    unawaited(_persist());
    return amount;
  }

  /// Claim pending dividend on every region at once.
  double claimAllDividends() {
    var total = 0.0;
    for (final st in _save.market.regions.values) {
      if (st.pendingDividend <= 0) continue;
      total += st.pendingDividend;
      st.pendingDividend = 0;
    }
    if (total <= 0) return 0;
    _save.gold += total;
    _save.totalGoldEarned += total;
    _save.stats.lifetimeGold += total;
    _save.market.totalDividendsClaimed += total;
    _save.run.stockDividendsClaimed += total;
    _save.run.goldEarned += total;
    _emit(loaded: true);
    unawaited(_persist());
    return total;
  }

  /// Total holdings value at current prices.
  double get totalHoldingsValue {
    var sum = 0.0;
    for (final st in _save.market.regions.values) {
      sum += st.shares * st.currentPrice;
    }
    return sum;
  }
}

final gameProvider =
    NotifierProvider<GameNotifier, GameState>(GameNotifier.new);
