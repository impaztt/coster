import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show PurchaseStatus;

import '../data/achievement_catalog.dart';
import '../data/feature_unlocks.dart';
import '../data/main_sword_enhancement.dart';
import '../data/main_sword_evolution.dart';
import '../data/prestige_upgrade_catalog.dart';
import '../data/repeating_achievement_catalog.dart';
import '../data/producer_catalog.dart';
import '../data/region_catalog.dart';
import '../data/sword_affinities.dart';
import '../data/sword_catalog.dart';
import '../data/skill_catalog.dart';
import '../data/sword_sets.dart';
import '../data/tap_upgrade_catalog.dart';
import '../models/achievement.dart';
import '../models/booster.dart';
import '../models/producer.dart';
import '../models/run_stats.dart';
import '../models/save_data.dart';
import '../models/skill.dart';
import '../models/stock_market.dart';
import '../models/sword.dart';
import '../services/ad_service.dart';
import '../services/iap_service.dart';
import '../services/sync_service.dart';

/// Buy count: 1, 10, 100 or -1 for Max.
final buyMultiplierProvider = StateProvider<int>((_) => 1);

const stockMarketPriceCurveRebalanceVersion = 16;

/// Cost in 정수 per single summon.
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

const _summonRateBoostPerLevel = <SwordTier, double>{
  SwordTier.sr: 0.20,
  SwordTier.ssr: 0.11,
  SwordTier.lr: 0.06,
  SwordTier.ur: 0.03,
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

Map<SwordTier, double> summonRatesForTotalSummons(int totalSummons) {
  final level = summonRateLevelFor(totalSummons);
  final rates = <SwordTier, double>{
    for (final tier in SwordTier.values) tier: tier.rate,
  };
  if (level <= 0) return rates;

  double boostedTotal = 0;
  for (final entry in _summonRateBoostPerLevel.entries) {
    final gain = entry.value * level;
    boostedTotal += gain;
    rates[entry.key] = (rates[entry.key] ?? 0) + gain;
  }

  rates[SwordTier.n] = max(
    summonRateMinN,
    (rates[SwordTier.n] ?? 0) - boostedTotal * summonRateDrainFromNRatio,
  );
  rates[SwordTier.r] = max(
    summonRateMinR,
    (rates[SwordTier.r] ?? 0) - boostedTotal * (1 - summonRateDrainFromNRatio),
  );

  final total = rates.values.fold<double>(0, (a, b) => a + b);
  if ((total - 100).abs() > 0.0001) {
    rates[SwordTier.r] = (rates[SwordTier.r] ?? 0) + (100 - total);
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
const comebackEssenceStepSeconds = 15 * 60; // +1 essence per 15m
const comebackEssenceCap = 120;

/// Crit + combo config.
const critChance = 0.05; // 5%
const critMultiplier = 10.0;
const comboWindowMs = 1500; // taps within this many ms extend the combo
const comboMax = 50;
const comboBonusPerStack = 0.01; // +1% tap per combo stack, cap +50%

/// Daily login reward table: streak day (1-indexed) → essence reward.
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

  // Exclude any portion of currentGold that came from the essence-for-gold
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

/// Booster shop catalog. (`adOnly`=true means essence cost is N/A; only
/// purchasable via the ad stub.)
class BoosterOffer {
  final String id;
  final String title;
  final String subtitle;
  final BoosterType type;
  final double multiplier;
  final int durationSec;
  final int essenceCost; // 0 → ad-only
  const BoosterOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.multiplier,
    required this.durationSec,
    required this.essenceCost,
  });
}

const boosterOffers = <BoosterOffer>[
  BoosterOffer(
    id: 'dps_2x_30m',
    title: '자동 수익 x2 · 30분',
    subtitle: '동료들의 DPS가 두 배가 돼요',
    type: BoosterType.dps,
    multiplier: 2.0,
    durationSec: 1800,
    essenceCost: 50,
  ),
  BoosterOffer(
    id: 'tap_2x_15m',
    title: '터치 x2 · 15분',
    subtitle: '탭당 획득 골드 두 배',
    type: BoosterType.tap,
    multiplier: 2.0,
    durationSec: 900,
    essenceCost: 30,
  ),
  BoosterOffer(
    id: 'rush_3x_5m',
    title: '골드러시 x3 · 5분',
    subtitle: 'DPS + 터치 모두 3배',
    type: BoosterType.rush,
    multiplier: 3.0,
    durationSec: 300,
    essenceCost: 100,
  ),
];

const premiumAdRemovalProductId = 'premium_ad_removal';
const premiumMonthlyEssencePassProductId = 'premium_monthly_essence_pass';
const premiumStarterPackageProductId = 'premium_starter_package';
const premiumFirstPurchaseProductId = 'premium_first_purchase';
const premiumEssenceSmallProductId = 'premium_essence_small';
const premiumEssenceMediumProductId = 'premium_essence_medium';
const premiumEssenceLargeProductId = 'premium_essence_large';
const premiumEssenceXLargeProductId = 'premium_essence_xlarge';
const premiumMasterPackageProductId = 'premium_master_package';
const premiumSeasonPassProductId = 'premium_season_pass';

const monthlyEssencePassImmediateEssence = 300;
const monthlyEssencePassDailyEssence = 120;
const monthlyEssencePassDurationDays = 30;
const monthlyEssencePassMissedClaimCapDays = 3;

const starterPackageEssence = 1400;
const starterPackageDpsBoostDurationSec = 1800;

/// Season pass (60 days). Larger daily essence + a weekly stipend.
const seasonPassDurationDays = 60;
const seasonPassDailyEssence = 200;
const seasonPassMissedClaimCapDays = 3;

/// Weekly bonus: paid out at most once every 7 days while the pass is
/// active. Designed as the headline "extra" so the pass feels distinct
/// from the cheaper monthly version.
const seasonPassWeeklyEssence = 600;
const seasonPassWeeklyIntervalDays = 7;

/// First-purchase package: heavily front-loaded, one shot per account,
/// only purchasable in the first ad-funnel window.
const firstPurchasePackageEssence = 500;
// Essence packs (consumables — no extra effect, just essence).
const essenceSmallEssence = 110;
const essenceMediumEssence = 380;
const essenceLargeEssence = 1200;
const essenceXLargeEssence = 2800;

const masterPackageEssence = 7500;
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
    id: premiumMonthlyEssencePassProductId,
    title: '월간 정수 보급권',
    subtitle: '30일 동안 매일 정수를 안정적으로 확보',
    priceLabel: '₩5,900',
    benefits: [
      '구매 즉시 정수 300',
      '30일 동안 매일 정수 120',
      '미수령 보상 최대 3일 누적',
    ],
  ),
  PremiumProductDef(
    id: premiumStarterPackageProductId,
    title: '초보자 패키지',
    subtitle: '초반 소환과 성장 템포를 한 번에 보강',
    priceLabel: '₩4,900',
    benefits: [
      '정수 1,400',
      'SR+ 검 1자루 확정 지급',
      '자동 수익 x2 30분',
    ],
  ),
  PremiumProductDef(
    id: premiumFirstPurchaseProductId,
    title: '첫 결제 패키지',
    subtitle: '계정당 1회 — 강력한 진입 보너스',
    priceLabel: '₩1,100',
    benefits: [
      '정수 500',
      'SR 확정 소환권 1',
      '24시간 한정 노출',
    ],
  ),
  PremiumProductDef(
    id: premiumEssenceSmallProductId,
    title: '정수 꾸러미 (소)',
    subtitle: '가장 가벼운 정수 충전',
    priceLabel: '₩1,100',
    benefits: ['정수 110'],
  ),
  PremiumProductDef(
    id: premiumEssenceMediumProductId,
    title: '정수 꾸러미 (중)',
    subtitle: '5분 환금 1회 + 보너스 30',
    priceLabel: '₩3,300',
    benefits: ['정수 380'],
  ),
  PremiumProductDef(
    id: premiumEssenceLargeProductId,
    title: '정수 꾸러미 (대)',
    subtitle: '8시간 환금 1회분 + 보너스 200',
    priceLabel: '₩9,900',
    benefits: ['정수 1,200'],
  ),
  PremiumProductDef(
    id: premiumEssenceXLargeProductId,
    title: '정수 꾸러미 (특대)',
    subtitle: '대량 충전 + 보너스 500',
    priceLabel: '₩19,900',
    benefits: ['정수 2,800'],
  ),
  PremiumProductDef(
    id: premiumSeasonPassProductId,
    title: '시즌 패스',
    subtitle: '60일간 매일 정수 + 주간 보너스',
    priceLabel: '₩14,900',
    benefits: [
      '60일간 매일 정수 200',
      '7일마다 정수 600 추가',
      '구매 즉시 시즌 시작',
    ],
  ),
  PremiumProductDef(
    id: premiumMasterPackageProductId,
    title: '마스터 패키지',
    subtitle: '한 번에 코어 빌드 완성',
    priceLabel: '₩49,900',
    benefits: [
      '정수 7,500',
      'UR 확정 소환권 1',
      '강 보호권 10',
      '24시간 모든 부스터',
    ],
  ),
];

/// Slime config — guaranteed spawn every N taps so the player can
/// predict it. Counter persists in SaveData.tapsSinceSlime.
const slimeSpawnEvery = 250;
const slimeLifetimeMs = 7000;

/// HP the slime takes to defeat — each tap on the slime deals 1 damage.
const slimeMaxHp = 10;

/// Reward when the slime is killed: gold = tapPower × this many taps.
const slimeRewardTaps = 5000;

/// Auto-tap config: when an autoTap booster is active, fire a tap every
/// [autoTapIntervalMs] milliseconds. ~4 taps/sec is comfortable: visible
/// progress without trashing the framerate.
const autoTapIntervalMs = 250;

/// Combo burst: triggered the first time combo reaches comboMax during a
/// single combo streak. Reward = current DPS × this many seconds.
const comboBurstWorthSeconds = 60;

/// Combo surge skill: extra combo stacks per tap and bonus multiplier
/// applied while the surge window is active.
const comboSurgePerTap = 2;
const comboSurgeBonus = 2.0; // tap reward × this while surging

/// Slash burst skill: instant gold equal to current DPS × this seconds.
const slashBurstWorthSeconds = 300;
const essenceGatherAmount = 30;
const ascensionCoreBonusPerLevel = 0.015;

// =========================================================================
// Gold-exchange shop (정수 → 골드 환전소)
//
// Two product lines:
//   • dpsTime  — pays out (currentDps × seconds × dpsTimeYieldFactor) gold.
//                Auto-scales with player power, so a single offer stays
//                relevant across the whole game.
//   • fixed    — pays out a constant gold amount. Useful in early runs
//                before DPS is meaningful, becomes obsolete late-game.
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
  final int essenceCost;
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
    required this.essenceCost,
    required this.kind,
    this.dpsSeconds = 0,
    this.fixedGold = 0,
    this.dailyCap = 0,
  });
}

/// Slight haircut on dpsTime offers vs. true offline-equivalent so that
/// "instant time" never feels strictly better than just playing.
const dpsTimeYieldFactor = 0.85;

/// Floor for dpsTime offers right after prestige (when DPS = 0). We pay out
/// `floor * essenceCost` so a freshly-prestiged player still gets a small
/// nudge instead of zero gold.
const dpsTimeFloorPerEssence = 10000.0; // 10K gold per essence

/// Daily cap for the entire exchange shop, independent of which offers were
/// used. Resets at UTC day rollover via the existing _dayKey() helper.
const goldExchangeDailyLimit = 5;

/// Hard cap for one prestige run. Resets in prestige().
const goldExchangePrestigeLimit = 15;

const goldExchangeOffers = <GoldExchangeOffer>[
  // DPS-time line.
  GoldExchangeOffer(
    id: 'dps_5m',
    title: '5분 환금',
    subtitle: '현재 DPS 기준 5분치 골드',
    essenceCost: 12,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 300,
  ),
  GoldExchangeOffer(
    id: 'dps_30m',
    title: '30분 환금',
    subtitle: '현재 DPS 기준 30분치 골드',
    essenceCost: 50,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 1800,
  ),
  GoldExchangeOffer(
    id: 'dps_2h',
    title: '2시간 환금',
    subtitle: '현재 DPS 기준 2시간치 골드',
    essenceCost: 180,
    kind: GoldExchangeKind.dpsTime,
    dpsSeconds: 7200,
  ),
  GoldExchangeOffer(
    id: 'dps_8h',
    title: '8시간 환금',
    subtitle: '현재 DPS 기준 8시간치 골드 · 하루 1회',
    essenceCost: 600,
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
    essenceCost: 5,
    kind: GoldExchangeKind.fixed,
    fixedGold: 1e6,
  ),
  GoldExchangeOffer(
    id: 'fixed_50m',
    title: '긴급 자금 50M',
    subtitle: '고정 5천만 골드',
    essenceCost: 20,
    kind: GoldExchangeKind.fixed,
    fixedGold: 5e7,
  ),
  GoldExchangeOffer(
    id: 'fixed_500m',
    title: '긴급 자금 500M',
    subtitle: '고정 5억 골드',
    essenceCost: 80,
    kind: GoldExchangeKind.fixed,
    fixedGold: 5e8,
  ),
  GoldExchangeOffer(
    id: 'fixed_3b',
    title: '긴급 자금 3B',
    subtitle: '고정 30억 골드',
    essenceCost: 300,
    kind: GoldExchangeKind.fixed,
    fixedGold: 3e9,
  ),
];

/// Hide the fixed line once the player has prestiged this many times — by
/// then their DPS is large enough that fixed packs are noise.
const goldExchangeFixedHideAfterPrestiges = 3;

// Main sword enhancement types ------------------------------------------------

enum MainSwordEnhanceCurrency { gold, essence, hybrid }

enum MainSwordEnhanceFailure {
  none,
  notEnoughGold,
  notEnoughEssence,
  alreadyMaxed,
  rolledFailure,
}

class MainSwordEnhanceAttemptResult {
  final bool ok; // false → couldn't even attempt (cost / cap reasons)
  final bool success; // true → +1 stage applied
  final int previousStage;
  final int newStage;
  final MainSwordEnhanceFailure reason;
  final int penaltyApplied;
  final double goldSpent;
  final int essenceSpent;
  final bool crossedTierUp;
  final MainSwordMilestoneReward? milestoneReward;
  const MainSwordEnhanceAttemptResult({
    required this.ok,
    required this.success,
    required this.previousStage,
    required this.newStage,
    required this.reason,
    this.penaltyApplied = 0,
    this.goldSpent = 0,
    this.essenceSpent = 0,
    this.crossedTierUp = false,
    this.milestoneReward,
  });
}

enum MainSwordEventType { tierUp, milestone, namingPrompt }

class MainSwordEvent {
  final MainSwordEventType type;
  final int? tierIndex;
  final String? tierName;
  final int? stage;
  final MainSwordMilestoneReward? milestone;
  const MainSwordEvent._({
    required this.type,
    this.tierIndex,
    this.tierName,
    this.stage,
    this.milestone,
  });

  const MainSwordEvent.tierUp({
    required int tierIndex,
    required String tierName,
    required int stage,
  }) : this._(
          type: MainSwordEventType.tierUp,
          tierIndex: tierIndex,
          tierName: tierName,
          stage: stage,
        );

  MainSwordEvent.milestone(MainSwordMilestoneReward reward)
      : this._(
          type: MainSwordEventType.milestone,
          milestone: reward,
          stage: reward.stage,
        );

  const MainSwordEvent.namingPrompt()
      : this._(type: MainSwordEventType.namingPrompt);
}

final mainSwordEventProvider = StreamProvider<MainSwordEvent>(
  (ref) => ref.watch(gameProvider.notifier).mainSwordEventStream,
);

/// Result of attempting a gold-exchange purchase. Communicates the precise
/// reason on failure so the UI can show a useful toast.
enum GoldExchangeFailureReason {
  none,
  notEnoughEssence,
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
  final int rewardEssence;
  final int rewardPrestigeCoins;
  final MissionCycle cycle;
  const MissionDef({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.rewardEssence,
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
  final int rewardEssence;
  final int rewardPrestigeCoins;
  final bool claimed;
  const MissionView({
    required this.id,
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.rewardEssence,
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
    rewardEssence: 15,
    rewardPrestigeCoins: 12,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_upgrade_30',
    title: '강화 루틴',
    description: '강화 레벨 30회 구매',
    target: 30,
    rewardEssence: 18,
    rewardPrestigeCoins: 14,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_skill_5',
    title: '스킬 숙련',
    description: '스킬 5회 사용',
    target: 5,
    rewardEssence: 20,
    rewardPrestigeCoins: 16,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_crit_30',
    title: '정밀 타격',
    description: '치명타 30회 발동',
    target: 30,
    rewardEssence: 18,
    rewardPrestigeCoins: 14,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_slime_5',
    title: '슬라임 처치',
    description: '슬라임 5마리 처치',
    target: 5,
    rewardEssence: 16,
    rewardPrestigeCoins: 12,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_summon_15',
    title: '소환 의식',
    description: '소환 15회',
    target: 15,
    rewardEssence: 22,
    rewardPrestigeCoins: 18,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_combo_burst',
    title: '콤보 폭발',
    description: '콤보 버스트 1회 발동',
    target: 1,
    rewardEssence: 14,
    rewardPrestigeCoins: 10,
    cycle: MissionCycle.daily,
  ),
  MissionDef(
    id: 'daily_booster_1',
    title: '가속 점검',
    description: '부스터 1회 사용',
    target: 1,
    rewardEssence: 20,
    rewardPrestigeCoins: 14,
    cycle: MissionCycle.daily,
  ),
];

const weeklyMissionDefs = <MissionDef>[
  MissionDef(
    id: 'weekly_prestige_5',
    title: '환생 순환',
    description: '환생 5회 달성',
    target: 5,
    rewardEssence: 90,
    rewardPrestigeCoins: 120,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_slime_40',
    title: '황금 사냥',
    description: '슬라임 40마리 처치',
    target: 40,
    rewardEssence: 80,
    rewardPrestigeCoins: 90,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_summon_120',
    title: '수집 주간',
    description: '소환 120회',
    target: 120,
    rewardEssence: 110,
    rewardPrestigeCoins: 110,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_tap_5000',
    title: '터치 마라톤',
    description: '터치 5000회',
    target: 5000,
    rewardEssence: 75,
    rewardPrestigeCoins: 80,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_upgrade_200',
    title: '강화 매니아',
    description: '강화 200회 구매',
    target: 200,
    rewardEssence: 100,
    rewardPrestigeCoins: 110,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_skill_50',
    title: '스킬 마스터',
    description: '스킬 50회 사용',
    target: 50,
    rewardEssence: 90,
    rewardPrestigeCoins: 100,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_crit_300',
    title: '폭풍 일격',
    description: '치명타 300회 발동',
    target: 300,
    rewardEssence: 80,
    rewardPrestigeCoins: 90,
    cycle: MissionCycle.weekly,
  ),
  MissionDef(
    id: 'weekly_booster_5',
    title: '가속 의존',
    description: '부스터 5회 사용',
    target: 5,
    rewardEssence: 120,
    rewardPrestigeCoins: 130,
    cycle: MissionCycle.weekly,
  ),
];

class SummonResult {
  final SwordDef sword;
  final int levelAfter;
  final bool isDuplicate;
  final bool isMaxed;
  SummonResult({
    required this.sword,
    required this.levelAfter,
    required this.isDuplicate,
    required this.isMaxed,
  });
}

class PremiumPurchaseResult {
  final bool ok;
  final String message;
  final int essenceGranted;
  final SummonResult? bonusSummon;

  const PremiumPurchaseResult({
    required this.ok,
    required this.message,
    this.essenceGranted = 0,
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
  final int essence;
  const DailyBonus({required this.streak, required this.essence});
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
  final int essence;
  final Map<String, int> ownedSwords;
  final String? equippedSwordId;
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
  final int mainSwordStage;
  final String? mainSwordName;
  final int mainSwordHighestStage;
  final bool adsRemoved;
  final DateTime? monthlyPassExpiresAt;
  final DateTime? seasonPassExpiresAt;
  final bool firstPurchasePackageClaimed;
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
    required this.essence,
    required this.ownedSwords,
    required this.equippedSwordId,
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
    this.mainSwordStage = 0,
    this.mainSwordName,
    this.mainSwordHighestStage = 0,
    this.adsRemoved = false,
    this.monthlyPassExpiresAt,
    this.seasonPassExpiresAt,
    this.firstPurchasePackageClaimed = false,
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
        essence: 90,
        ownedSwords: {},
        equippedSwordId: null,
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
  int swordLevel(String id) => ownedSwords[id] ?? 0;
  bool ownsSword(String id) => (ownedSwords[id] ?? 0) > 0;
  bool isFeatureUnlocked(String id) => unlockedFeatures.contains(id);

  SwordDef? get equippedSword {
    final id = equippedSwordId;
    if (id == null) return null;
    try {
      return swordById(id);
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
    for (final entry in ownedSwords.entries) {
      if (entry.value <= 0) continue;
      try {
        final tier = swordById(entry.key).tier;
        if (tier == SwordTier.r) hasR = true;
        if (tier == SwordTier.sr) hasSr = true;
        if (tier == SwordTier.ssr) hasSsr = true;
        if (tier == SwordTier.lr) hasLr = true;
        if (tier == SwordTier.ur) hasUr = true;
      } catch (_) {}
      if (entry.value > maxLv) maxLv = entry.value;
      if (entry.value >= SwordDef.maxLevel) maxedCount++;
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
      ownedSwords: ownedSwords,
      ownedSwordCount: ownedSwords.values.where((v) => v > 0).length,
      totalSwordCatalogCount: swordCatalog.length,
      ownsAnyR: hasR,
      ownsAnySr: hasSr,
      ownsAnySsr: hasSsr,
      ownsAnyLr: hasLr,
      ownsAnyUr: hasUr,
      maxSwordLevel: maxLv,
      maxedSwordCount: maxedCount,
      totalSummons: totalSummons,
      prestigeCount: prestigeCount,
      prestigeUpgradeLevels: prestigeUpgradeLevels,
      totalTapUpgradesBought: totalTapUpgradesBought,
      hasEquippedSword: equippedSwordId != null,
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
      essence: essence,
      run: run,
    );
  }
}

class OfflineReward {
  final Duration duration;
  final double gold;
  final int essenceBonus;
  final bool blockedByClockGuard;
  const OfflineReward({
    required this.duration,
    required this.gold,
    this.essenceBonus = 0,
    this.blockedByClockGuard = false,
  });
}

const _milestoneEssence = <int, int>{
  25: 1,
  50: 2,
  100: 5,
  200: 10,
};

int _milestoneEssenceUpTo(int level) {
  int total = 0;
  _milestoneEssence.forEach((threshold, reward) {
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
    _mainSwordEvents.close();
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
        final essenceBonus = min(
            comebackEssenceCap, cappedSeconds ~/ comebackEssenceStepSeconds);
        _pendingOffline = OfflineReward(
          duration: Duration(seconds: cappedSeconds),
          gold: dpsNow * cappedSeconds,
          essenceBonus: essenceBonus,
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
    _save.mainSwordStage =
        _intClamp(_save.mainSwordStage, 0, mainSwordEnhanceMaxStage);
    _save.mainSwordHighestStage = _intClamp(
      _save.mainSwordHighestStage,
      _save.mainSwordStage,
      mainSwordEnhanceMaxStage,
    );
    _save.mainSwordTiersShown.removeWhere(
      (i) => i < 0 || i >= mainSwordTiers.length,
    );
    if (_save.mainSwordCollectionBonusFraction.isNaN ||
        _save.mainSwordCollectionBonusFraction < 0) {
      _save.mainSwordCollectionBonusFraction = 0;
    }
    _save.prestigeCoins = _intClamp(_save.prestigeCoins, 0, 2147483647);
    _save.prestigeCount = _intClamp(_save.prestigeCount, 0, 1000000);
    _save.ascensionCoreLevel = _intClamp(_save.ascensionCoreLevel, 0, 1000000);
    _save.essence = _intClamp(_save.essence, 0, 2147483647);
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
      _save.ownedSwords,
      allowed: swordCatalog.map((e) => e.id).toSet(),
      maxLevel: SwordDef.maxLevel,
    );
    final equipped = _save.equippedSwordId;
    if (equipped != null && (_save.ownedSwords[equipped] ?? 0) <= 0) {
      _save.equippedSwordId = null;
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
    final allowed = swordCatalog.map((e) => e.id).toSet();
    final seen = <String>{};
    final slots = List<String?>.filled(swordFormationSlotCount, null);
    final source = _save.formationSwordIds;
    final limit = source.length < swordFormationSlotCount
        ? source.length
        : swordFormationSlotCount;
    for (var i = 0; i < limit; i++) {
      final id = source[i];
      if (id == null) continue;
      if (!allowed.contains(id)) continue;
      if ((_save.ownedSwords[id] ?? 0) <= 0) continue;
      if (!seen.add(id)) continue;
      slots[i] = id;
    }
    _save.formationSwordIds = slots;
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
      return DailyBonus(streak: 1, essence: dailyRewardFor(1));
    }
    final hours = now.difference(last).inHours;
    if (hours < 24) return null; // already claimed today
    // 24h ≤ elapsed < 48h → streak continues.
    // Beyond 48h → streak resets to day 1.
    final nextStreak =
        hours < 48 ? ((_save.dailyStreak % (dailyRewards.length - 1)) + 1) : 1;
    return DailyBonus(streak: nextStreak, essence: dailyRewardFor(nextStreak));
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
      final dps = _calcDps();
      if (dps > _save.stats.maxDpsEver) _save.stats.maxDpsEver = dps;
      if (dps > _save.run.dpsPeak) _save.run.dpsPeak = dps;
      if (dps > 0) {
        final gain = dps * dt;
        _save.gold += gain;
        _save.totalGoldEarned += gain;
        _save.stats.lifetimeGold += gain;
        _save.run.goldEarned += gain;
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
      essence: _save.essence,
      ownedSwords: Map.unmodifiable(_save.ownedSwords),
      equippedSwordId: _save.equippedSwordId,
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
      mainSwordStage: _save.mainSwordStage,
      mainSwordName: _save.mainSwordName,
      mainSwordHighestStage: _save.mainSwordHighestStage,
      adsRemoved: _save.adsRemoved,
      monthlyPassExpiresAt: _save.monthlyPassExpiresAt,
      seasonPassExpiresAt: _save.seasonPassExpiresAt,
      firstPurchasePackageClaimed: _save.firstPurchasePackageClaimed,
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
    for (final s in swordSets) {
      if (s.swordIds.every((id) => (_save.ownedSwords[id] ?? 0) > 0)) {
        ids.add(s.id);
      }
    }
    return ids;
  }

  double _setDpsBonus() {
    double bonus = 0;
    final completed = _completedSetIds();
    for (final s in swordSets) {
      if (completed.contains(s.id)) bonus += s.dpsBonus;
    }
    return 1.0 + bonus;
  }

  double _setTapBonus() {
    double bonus = 0;
    final completed = _completedSetIds();
    for (final s in swordSets) {
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
          rewardEssence: def.rewardEssence,
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
        _save.essence += def.essenceReward;
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
        _save.essence += def.essenceReward;
        _achievementUnlocks.add(def);
        anyChanged = true;
      }
    }
    if (anyChanged) {
      // Re-emit to reflect new essence + unlock set in a single next frame.
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
        essence: _save.essence,
        ownedSwords: state.ownedSwords,
        equippedSwordId: state.equippedSwordId,
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
    var totalEssenceGranted = 0;
    for (final def in repeatingAchievementCatalog) {
      var cleared = _save.repeatingAchievementStages[def.id] ?? 0;
      final value = def.current(ctx);
      // Cap iterations defensively to avoid runaway loops.
      var safety = 256;
      while (safety-- > 0 && value >= def.targetForStage(cleared + 1)) {
        cleared++;
        totalEssenceGranted += def.rewardForStage(cleared);
      }
      if (cleared != (_save.repeatingAchievementStages[def.id] ?? 0)) {
        _save.repeatingAchievementStages[def.id] = cleared;
        anyChanged = true;
      }
    }
    if (!anyChanged) return;
    if (totalEssenceGranted > 0) _save.essence += totalEssenceGranted;
    // Re-emit so the UI sees the new cleared-stage map and essence.
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
      essence: _save.essence,
      ownedSwords: state.ownedSwords,
      equippedSwordId: state.equippedSwordId,
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
      essence: state.essence,
      ownedSwords: state.ownedSwords,
      equippedSwordId: state.equippedSwordId,
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
    final id = _save.equippedSwordId;
    if (id == null) return 1.0;
    final lv = _save.ownedSwords[id] ?? 0;
    if (lv <= 0) return 1.0;
    try {
      return swordById(id).tapMultAt(lv);
    } catch (_) {
      return 1.0;
    }
  }

  double _equippedDpsMult() {
    final id = _save.equippedSwordId;
    if (id == null) return 1.0;
    final lv = _save.ownedSwords[id] ?? 0;
    if (lv <= 0) return 1.0;
    try {
      return swordById(id).dpsMultAt(lv);
    } catch (_) {
      return 1.0;
    }
  }

  /// Total fractional bonus contributed by every owned sword (incl. the
  /// equipped one — its big equip multiplier is separate, so this stacks
  /// without "double-dipping" on the same source). Returns the raw sum,
  /// e.g. 0.42 for "+42%" — see [_collectionMult] for the multiplier form.
  double _collectionBonusTotal() {
    double total = 0;
    _save.ownedSwords.forEach((id, lv) {
      if (lv <= 0) return;
      try {
        total += swordById(id).ownedBonusAt(lv);
      } catch (_) {}
    });
    // Permanent collection-bonus boosts unlocked via main sword milestones.
    total += _save.mainSwordCollectionBonusFraction;
    return total;
  }

  double _collectionMult() => 1.0 + _collectionBonusTotal();

  List<String?> get formationSwordIds {
    _sanitizeFormationSlots();
    return List.unmodifiable(_save.formationSwordIds);
  }

  FormationSummary get formationSummary => _formationSummary();

  double _formationPower(SwordDef def, int level) {
    final base = switch (def.tier) {
      SwordTier.n => 0.006,
      SwordTier.r => 0.010,
      SwordTier.sr => 0.016,
      SwordTier.ssr => 0.024,
      SwordTier.lr => 0.036,
      SwordTier.ur => 0.052,
    };
    final levelScale = 1.0 + (level.clamp(1, SwordDef.maxLevel) - 1) * 0.08;
    return base * levelScale;
  }

  FormationSummary _formationSummary() {
    _sanitizeFormationSlots();
    var filled = 0;
    var tap = 0.0;
    var dps = 0.0;
    var market = 0.0;
    final roles = <SwordFormationRole>{};
    final regions = <String>{};
    final regionCounts = <String, int>{};

    for (final id in _save.formationSwordIds) {
      if (id == null) continue;
      final level = _save.ownedSwords[id] ?? 0;
      if (level <= 0) continue;
      SwordDef def;
      try {
        def = swordById(id);
      } catch (_) {
        continue;
      }
      filled++;
      final role = swordFormationRole(def);
      final regionId = swordRegionId(def);
      final power = _formationPower(def, level);
      roles.add(role);
      regions.add(regionId);
      regionCounts[regionId] = (regionCounts[regionId] ?? 0) + 1;

      switch (role) {
        case SwordFormationRole.vanguard:
          tap += power * 1.25;
          dps += power * 0.20;
          break;
        case SwordFormationRole.striker:
          tap += power * 0.75;
          dps += power * 0.75;
          break;
        case SwordFormationRole.support:
          tap += power * 0.20;
          dps += power * 1.25;
          break;
        case SwordFormationRole.trader:
          dps += power * 0.35;
          market += power * 1.50;
          break;
        case SwordFormationRole.anchor:
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
    if (roles.length >= swordFormationSlotCount) {
      tap += 0.015;
      dps += 0.015;
      market += 0.025;
    }
    if (filled >= swordFormationSlotCount && regions.length >= filled) {
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
        _mainSwordMult();
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
        _mainSwordMult();
  }

  /// Multiplier from the home-tab main sword's enhancement stage. Applies
  /// to BOTH tap and DPS so progression on the main sword scales evenly
  /// with the rest of the build.
  double _mainSwordMult() => mainSwordStageBonusMult(_save.mainSwordStage);

  /// Public read so the UI can show "+X% from 메인검 +N단계".
  double get mainSwordBonusFraction =>
      _mainSwordMult() - 1.0 + _summonRateBonusFromMainSword();

  /// Permanent +5% summon-rate bonus from clearing +50.
  double _summonRateBonusFromMainSword() =>
      _save.mainSwordHighestStage >= 50 ? 0.05 : 0.0;

  /// Public read for the home screen so it can show "수집 보너스 +X%".
  double get collectionBonusFraction => _collectionBonusTotal();

  bool setFormationSword(int slot, String? swordId) {
    if (slot < 0 || slot >= swordFormationSlotCount) return false;
    _sanitizeFormationSlots();
    if (swordId != null) {
      if ((_save.ownedSwords[swordId] ?? 0) <= 0) return false;
      try {
        swordById(swordId);
      } catch (_) {
        return false;
      }
    }
    for (var i = 0; i < _save.formationSwordIds.length; i++) {
      if (i != slot && _save.formationSwordIds[i] == swordId) {
        _save.formationSwordIds[i] = null;
      }
    }
    _save.formationSwordIds[slot] = swordId;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  void clearFormation() {
    _save.formationSwordIds =
        List<String?>.filled(swordFormationSlotCount, null);
    _emit(loaded: true);
    unawaited(_persist());
  }

  void autoFillFormation() {
    final owned = <SwordDef>[];
    for (final entry in _save.ownedSwords.entries) {
      if (entry.value <= 0) continue;
      try {
        owned.add(swordById(entry.key));
      } catch (_) {}
    }
    owned.sort((a, b) {
      final tierCmp = b.tier.index.compareTo(a.tier.index);
      if (tierCmp != 0) return tierCmp;
      final lvCmp = (_save.ownedSwords[b.id] ?? 0)
          .compareTo(_save.ownedSwords[a.id] ?? 0);
      if (lvCmp != 0) return lvCmp;
      return a.id.compareTo(b.id);
    });

    final picked = <SwordDef>[];
    final usedRoles = <SwordFormationRole>{};
    for (final sword in owned) {
      if (picked.length >= swordFormationSlotCount) break;
      final role = swordFormationRole(sword);
      if (usedRoles.contains(role)) continue;
      picked.add(sword);
      usedRoles.add(role);
    }
    for (final sword in owned) {
      if (picked.length >= swordFormationSlotCount) break;
      if (picked.any((s) => s.id == sword.id)) continue;
      picked.add(sword);
    }

    _save.formationSwordIds =
        List<String?>.filled(swordFormationSlotCount, null);
    for (var i = 0; i < picked.length; i++) {
      _save.formationSwordIds[i] = picked[i].id;
    }
    _emit(loaded: true);
    unawaited(_persist());
  }

  double regionSwordDistrictBonusFraction(String regionId) {
    final regionSwords = swordsForRegion(regionId);
    if (regionSwords.isEmpty) return 0;

    var owned = 0;
    var levelTotal = 0;
    for (final sword in regionSwords) {
      final level = _save.ownedSwords[sword.id] ?? 0;
      if (level <= 0) continue;
      owned++;
      levelTotal += level.clamp(0, SwordDef.maxLevel).toInt();
    }

    final ownedRatio = owned / regionSwords.length;
    final levelRatio = levelTotal / (regionSwords.length * SwordDef.maxLevel);
    final collectionBonus = ownedRatio * 0.18 + levelRatio * 0.22;

    var formationBonus = 0.0;
    for (final id in _save.formationSwordIds) {
      if (id == null) continue;
      final level = _save.ownedSwords[id] ?? 0;
      if (level <= 0) continue;
      SwordDef def;
      try {
        def = swordById(id);
      } catch (_) {
        continue;
      }
      if (swordRegionId(def) != regionId) continue;
      final role = swordFormationRole(def);
      final roleWeight = switch (role) {
        SwordFormationRole.trader => 2.00,
        SwordFormationRole.anchor => 1.15,
        _ => 0.55,
      };
      formationBonus += _formationPower(def, level) * roleWeight;
    }

    return (collectionBonus + formationBonus).clamp(0.0, 0.85).toDouble();
  }

  double regionEffectiveHourlyYield(String regionId) {
    final def = regionDefById(regionId);
    return def.hourlyYield * (1.0 + regionSwordDistrictBonusFraction(regionId));
  }

  double regionIntrinsicPrice(String regionId) {
    final def = regionDefById(regionId);
    return def.initialPrice *
        (1.0 + regionSwordDistrictBonusFraction(regionId) * 0.45);
  }

  /// All multipliers that turn a producer's raw DPS into the effective DPS
  /// shown on the home screen. Upgrade tiles use this to display the gain
  /// the player will actually see (e.g. so the sword-collection bonus
  /// visibly improves the "DPS +N" preview on companion/transcendent buys).
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
  /// New UI should prefer [tapWithFeedback] to access crit/combo info.
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

    final base = _calcTapPower();
    final comboMult = 1.0 + (_combo * comboBonusPerStack).clamp(0.0, 0.5);
    final surgeMult = surge ? comboSurgeBonus : 1.0;
    final isCrit = _random.nextDouble() < critChance;
    final critMult = isCrit ? critMultiplier : 1.0;
    final amount = base * comboMult * surgeMult * critMult;

    _save.gold += amount;
    _save.totalGoldEarned += amount;
    _save.stats.lifetimeGold += amount;
    _save.stats.totalTaps++;
    _save.run.taps++;
    _save.run.goldEarned += amount;
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
    final essenceGain =
        _milestoneEssenceUpTo(newLv) - _milestoneEssenceUpTo(oldLv);
    if (essenceGain > 0) _save.essence += essenceGain;
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
        final floor = dpsTimeFloorPerEssence * offer.essenceCost;
        return raw < floor ? floor : raw;
      case GoldExchangeKind.fixed:
        return offer.fixedGold;
    }
  }

  /// True if the fixed-amount line should be hidden because the player's
  /// progression has outgrown it.
  bool get goldExchangeFixedHidden =>
      _save.prestigeCount >= goldExchangeFixedHideAfterPrestiges;

  /// Attempt to spend essence on a gold-exchange offer.
  GoldExchangeResult buyGoldExchange(String offerId) {
    final offer = goldExchangeOffers.firstWhere(
      (o) => o.id == offerId,
      orElse: () => throw ArgumentError('Unknown exchange offer: $offerId'),
    );
    final now = DateTime.now();
    _rotateGoldExchangeDayIfNeeded(now);

    if (_save.essence < offer.essenceCost) {
      return const GoldExchangeResult(
        ok: false,
        goldGranted: 0,
        reason: GoldExchangeFailureReason.notEnoughEssence,
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
    _save.essence -= offer.essenceCost;
    _save.gold += goldGranted;
    // Critical: do NOT touch totalGoldEarned. The whole point of this
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
  // Main sword enhancement
  // ─────────────────────────────────────────────────────────────────────────

  /// Stream of milestone awards / tier evolutions / first-naming prompts.
  final _mainSwordEvents = StreamController<MainSwordEvent>.broadcast();
  Stream<MainSwordEvent> get mainSwordEventStream => _mainSwordEvents.stream;

  /// Set/replace the main sword's nickname. Empty/whitespace input is
  /// rejected so the UI can default to a placeholder.
  bool setMainSwordName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    _save.mainSwordName = trimmed;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  /// Attempt one main sword enhancement step.
  ///
  /// Stage transitions follow these rules:
  ///   • Success → +1 stage (clamped at mainSwordEnhanceMaxStage).
  ///   • Failure on essence path → no stage change.
  ///   • Failure on gold path → −penalty unless [useProtection] is set.
  ///   • Failure on hybrid → splits the difference: gold-track penalty
  ///     applies, but protection is implied (so no stage loss) at the
  ///     cost of full hybrid pricing.
  MainSwordEnhanceAttemptResult attemptMainSwordEnhance({
    required MainSwordEnhanceCurrency currency,
    MainSwordBoostLevel boostLevel = MainSwordBoostLevel.none,
    bool useProtection = false,
  }) {
    final currentStage = _save.mainSwordStage;
    if (currentStage >= mainSwordEnhanceMaxStage) {
      return const MainSwordEnhanceAttemptResult(
        ok: false,
        success: false,
        previousStage: 0,
        newStage: 0,
        reason: MainSwordEnhanceFailure.alreadyMaxed,
      );
    }
    final targetStage = currentStage + 1;
    final cost = mainSwordEnhanceCost(targetStage);

    // Compute final cost based on currency choice.
    double goldCost = 0;
    int essenceCost = 0;
    double successRate;
    final boost = boostLevel;
    final boostEssenceCost = boost.essenceCost;
    final protection =
        currency == MainSwordEnhanceCurrency.gold && useProtection;

    switch (currency) {
      case MainSwordEnhanceCurrency.gold:
        goldCost = cost.goldCost;
        essenceCost = boostEssenceCost +
            (protection ? mainSwordProtectionEssenceCost : 0);
        successRate =
            (cost.goldSuccessBase + boost.successBonus).clamp(0.0, 1.0);
      case MainSwordEnhanceCurrency.essence:
        essenceCost = cost.essenceCost + boostEssenceCost;
        successRate =
            (cost.essenceSuccessBase + boost.successBonus).clamp(0.0, 1.0);
      case MainSwordEnhanceCurrency.hybrid:
        goldCost = cost.goldCost * mainSwordHybridGoldMultiplier;
        essenceCost =
            (cost.essenceCost * mainSwordHybridEssenceMultiplier).round() +
                boostEssenceCost;
        successRate = (cost.goldSuccessBase +
                mainSwordHybridSuccessBonus +
                boost.successBonus)
            .clamp(0.0, 1.0);
    }

    if (_save.gold < goldCost) {
      return MainSwordEnhanceAttemptResult(
        ok: false,
        success: false,
        previousStage: currentStage,
        newStage: currentStage,
        reason: MainSwordEnhanceFailure.notEnoughGold,
      );
    }
    if (_save.essence < essenceCost) {
      return MainSwordEnhanceAttemptResult(
        ok: false,
        success: false,
        previousStage: currentStage,
        newStage: currentStage,
        reason: MainSwordEnhanceFailure.notEnoughEssence,
      );
    }

    if (goldCost > 0) {
      _save.gold -= goldCost;
      _decayPurchasedGoldUnconverted(goldCost);
      _save.stats.totalGoldSpent += goldCost;
      _save.run.goldSpent += goldCost;
    }
    if (essenceCost > 0) {
      _save.essence -= essenceCost;
    }

    final roll = _random.nextDouble();
    final success = roll < successRate;
    final previousStage = currentStage;
    final firstEverEnhance =
        currentStage == 0 && _save.mainSwordHighestStage == 0;
    int newStage = currentStage;
    int penaltyApplied = 0;
    if (success) {
      newStage = currentStage + 1;
    } else if (currency == MainSwordEnhanceCurrency.essence) {
      // Essence-track failures never lose a stage.
    } else if (currency == MainSwordEnhanceCurrency.hybrid) {
      // Hybrid paid the full price, treat as protected.
    } else if (!protection) {
      penaltyApplied = cost.penaltyOnFail.clamp(0, currentStage);
      newStage = currentStage - penaltyApplied;
    }
    _save.mainSwordStage = newStage.clamp(0, mainSwordEnhanceMaxStage);
    _save.mainSwordEnhanceAttempts++;

    // Milestone + tier-up detection on the *new* stage.
    final wasNewHigh = _save.mainSwordStage > _save.mainSwordHighestStage;
    if (wasNewHigh) {
      _save.mainSwordHighestStage = _save.mainSwordStage;
    }
    final crossedTierUp = success &&
        mainSwordTierIndex(newStage) > mainSwordTierIndex(previousStage);
    if (crossedTierUp) {
      final tierIdx = mainSwordTierIndex(newStage);
      if (!_save.mainSwordTiersShown.contains(tierIdx)) {
        _save.mainSwordTiersShown.add(tierIdx);
        _mainSwordEvents.add(
          MainSwordEvent.tierUp(
            tierIndex: tierIdx,
            tierName: mainSwordTiers[tierIdx].name,
            stage: newStage,
          ),
        );
      }
    }
    MainSwordMilestoneReward? milestone;
    if (success && wasNewHigh) {
      milestone = mainSwordMilestoneAt(newStage);
      if (milestone != null) {
        if (milestone.essence > 0) _save.essence += milestone.essence;
        if (milestone.collectionBonusFraction != null) {
          _save.mainSwordCollectionBonusFraction +=
              milestone.collectionBonusFraction!;
        }
        _mainSwordEvents.add(MainSwordEvent.milestone(milestone));
      }
    }
    if (firstEverEnhance && success && _save.mainSwordName == null) {
      _mainSwordEvents.add(const MainSwordEvent.namingPrompt());
    }

    _emit(loaded: true);
    unawaited(_persist());

    return MainSwordEnhanceAttemptResult(
      ok: true,
      success: success,
      previousStage: previousStage,
      newStage: newStage,
      reason: success
          ? MainSwordEnhanceFailure.none
          : MainSwordEnhanceFailure.rolledFailure,
      penaltyApplied: penaltyApplied,
      goldSpent: goldCost,
      essenceSpent: essenceCost,
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
      _save.essence += def.essenceReward;
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
    if (r.essenceBonus > 0) {
      _save.essence += r.essenceBonus;
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
    _save.essence += bonus.essence;
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
    _save.essence += def.rewardEssence;
    _save.prestigeCoins += def.rewardPrestigeCoins;
    _emit(loaded: true);
    unawaited(_persist());
    return true;
  }

  /// Claim every completed-but-unclaimed mission across both daily and
  /// weekly tracks. Returns aggregate reward totals (count, essence, coins).
  ({int count, int essence, int coins}) claimAllMissions() {
    _rotateMissionWindowsIfNeeded();
    var count = 0;
    var essence = 0;
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
        essence += def.rewardEssence;
        coins += def.rewardPrestigeCoins;
        count++;
      }
    }

    sweep(daily: true);
    sweep(daily: false);
    if (count == 0) return (count: 0, essence: 0, coins: 0);
    _save.essence += essence;
    _save.prestigeCoins += coins;
    _emit(loaded: true);
    unawaited(_persist());
    return (count: count, essence: essence, coins: coins);
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
    return min(days, monthlyEssencePassMissedClaimCapDays);
  }

  int get monthlyPassClaimableEssence =>
      monthlyPassClaimableDays * monthlyEssencePassDailyEssence;

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

      case premiumMonthlyEssencePassProductId:
        final now = DateTime.now();
        final wasActive = hasActiveMonthlyPass;
        final currentExpiresAt = _save.monthlyPassExpiresAt;
        final base = currentExpiresAt != null && currentExpiresAt.isAfter(now)
            ? currentExpiresAt
            : now;
        _save.monthlyPassExpiresAt =
            base.add(const Duration(days: monthlyEssencePassDurationDays));
        if (!wasActive) _save.monthlyPassLastClaimAt = now;
        _save.essence += monthlyEssencePassImmediateEssence;
        _emit(loaded: true);
        unawaited(_persist());
        return const PremiumPurchaseResult(
          ok: true,
          message: '월간 정수 보급권이 적용됐어요',
          essenceGranted: monthlyEssencePassImmediateEssence,
        );

      case premiumStarterPackageProductId:
        if (_save.starterPackagePurchased) {
          return const PremiumPurchaseResult(
            ok: false,
            message: '초보자 패키지는 계정당 1회만 구매할 수 있어요',
          );
        }
        _save.starterPackagePurchased = true;
        _save.essence += starterPackageEssence;
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
          essenceGranted: starterPackageEssence,
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
        _save.essence += firstPurchasePackageEssence;
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
          essenceGranted: firstPurchasePackageEssence,
          bonusSummon: firstSummon,
        );

      case premiumEssenceSmallProductId:
        return _grantEssencePack(essenceSmallEssence, '정수 꾸러미 (소)');
      case premiumEssenceMediumProductId:
        return _grantEssencePack(essenceMediumEssence, '정수 꾸러미 (중)');
      case premiumEssenceLargeProductId:
        return _grantEssencePack(essenceLargeEssence, '정수 꾸러미 (대)');
      case premiumEssenceXLargeProductId:
        return _grantEssencePack(essenceXLargeEssence, '정수 꾸러미 (특대)');

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
        _save.essence += masterPackageEssence;
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
          essenceGranted: masterPackageEssence,
          bonusSummon: masterSummon,
        );

      default:
        return const PremiumPurchaseResult(
          ok: false,
          message: '알 수 없는 상품이에요',
        );
    }
  }

  PremiumPurchaseResult _grantEssencePack(int amount, String label) {
    _save.essence += amount;
    _emit(loaded: true);
    unawaited(_persist());
    return PremiumPurchaseResult(
      ok: true,
      message: '$label 지급 완료',
      essenceGranted: amount,
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

  int get seasonPassClaimableEssence =>
      seasonPassClaimableDays * seasonPassDailyEssence;

  bool get seasonPassWeeklyAvailable {
    if (!hasActiveSeasonPass) return false;
    final last = _save.seasonPassLastWeeklyClaimAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inDays >=
        seasonPassWeeklyIntervalDays;
  }

  int claimSeasonPassDailyEssence() {
    final days = seasonPassClaimableDays;
    if (days <= 0) return 0;
    final amount = days * seasonPassDailyEssence;
    _save.essence += amount;
    _save.seasonPassLastClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
    return amount;
  }

  int claimSeasonPassWeeklyEssence() {
    if (!seasonPassWeeklyAvailable) return 0;
    _save.essence += seasonPassWeeklyEssence;
    _save.seasonPassLastWeeklyClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
    return seasonPassWeeklyEssence;
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
  void grantEssence(int amount) {
    if (amount <= 0) return;
    _save.essence += amount;
    _emit(loaded: true);
    unawaited(_persist());
  }

  /// Bonus gold grant from rewarded ads (offline-reward x2 etc.). Counts
  /// toward lifetime/totalGoldEarned because the player earned it through
  /// ad engagement, not by paying with essence.
  void grantBonusGold(double amount) {
    if (amount <= 0) return;
    _save.gold += amount;
    _save.totalGoldEarned += amount;
    _save.stats.lifetimeGold += amount;
    _emit(loaded: true);
    unawaited(_persist());
  }

  int claimMonthlyPassEssence() {
    final days = monthlyPassClaimableDays;
    if (days <= 0) return 0;
    final amount = days * monthlyEssencePassDailyEssence;
    _save.essence += amount;
    _save.monthlyPassLastClaimAt = DateTime.now();
    _emit(loaded: true);
    unawaited(_persist());
    return amount;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  // ============ Boosters + ads ============

  /// Attempt to buy [offer] with essence. Returns true on success.
  bool buyBoosterWithEssence(BoosterOffer offer) {
    if (_save.essence < offer.essenceCost) return false;
    _save.essence -= offer.essenceCost;
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
          message: '검기 폭발!',
          payload: reward,
        );
      case SkillId.comboSurge:
        _comboSurgeUntil = now.add(const Duration(seconds: 10));
        result = const SkillResult(
          id: SkillId.comboSurge,
          ok: true,
          message: '10초간 콤보 폭주!',
        );
      case SkillId.essenceGather:
        _save.essence += essenceGatherAmount;
        result = SkillResult(
          id: SkillId.essenceGather,
          ok: true,
          message: '정수 +$essenceGatherAmount',
          payload: essenceGatherAmount.toDouble(),
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

  /// Called by the home screen when a golden slime is killed (its HP drops
  /// to 0). Grants gold equal to [slimeRewardTaps] × current tap power and
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

  /// Estimated reward shown on the slime HP bar so the player can see what
  /// finishing it off is worth at the current moment.
  double get slimePreviewReward => _calcTapPower() * slimeRewardTaps;

  // ============ Sword dismantle ============

  /// Returns the amount of essence that dismantling [swordId] would refund,
  /// or 0 if the sword can't be dismantled.
  int dismantleRefund(String swordId) {
    final lv = _save.ownedSwords[swordId] ?? 0;
    if (lv <= 0) return 0;
    if (_save.equippedSwordId == swordId) return 0;
    final SwordDef def;
    try {
      def = swordById(swordId);
    } catch (_) {
      return 0;
    }
    return _dismantleEssencePerLevel(def.tier) * lv;
  }

  int _dismantleEssencePerLevel(SwordTier tier) {
    return switch (tier) {
      SwordTier.n => 2,
      SwordTier.r => 5,
      SwordTier.sr => 12,
      SwordTier.ssr => 25,
      SwordTier.lr => 40,
      SwordTier.ur => 60,
    };
  }

  /// Dismantle an owned, non-equipped sword. Returns essence granted (0 on
  /// failure — usually because the sword is equipped or not owned).
  int dismantleSword(String swordId) {
    final refund = dismantleRefund(swordId);
    if (refund <= 0) return 0;
    _save.ownedSwords.remove(swordId);
    for (var i = 0; i < _save.formationSwordIds.length; i++) {
      if (_save.formationSwordIds[i] == swordId) {
        _save.formationSwordIds[i] = null;
      }
    }
    _save.essence += refund;
    _save.run.swordDismantles++;
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

  // ============ Sword collection / gacha ============

  SwordTier _rollTier({required bool forceSrPlus}) {
    final pool = forceSrPlus
        ? const [SwordTier.sr, SwordTier.ssr, SwordTier.lr, SwordTier.ur]
        : SwordTier.values;
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

  SwordDef _pickRandomOfTier(SwordTier tier) {
    final pool = swordCatalog.where((s) => s.tier == tier).toList();
    return pool[_random.nextInt(pool.length)];
  }

  SummonResult _doOnePull({
    required bool guaranteedRPlus,
    bool forceSrPlus = false,
  }) {
    final pityHit =
        !forceSrPlus && _save.summonsSinceHighRare + 1 >= pityThreshold;
    SwordTier tier;
    if (forceSrPlus || pityHit) {
      tier = _rollTier(forceSrPlus: true);
    } else if (guaranteedRPlus) {
      tier = _rollTier(forceSrPlus: false);
      if (tier == SwordTier.n) tier = SwordTier.r;
    } else {
      tier = _rollTier(forceSrPlus: false);
    }
    final def = _pickRandomOfTier(tier);
    final oldLv = _save.ownedSwords[def.id] ?? 0;
    final wasOwned = oldLv > 0;
    final wasMaxed = oldLv >= SwordDef.maxLevel;
    final newLv = wasMaxed ? SwordDef.maxLevel : (wasOwned ? oldLv + 1 : 1);
    _save.ownedSwords[def.id] = newLv;
    _save.equippedSwordId ??= def.id;
    if (!wasOwned && !_save.formationSwordIds.contains(def.id)) {
      final emptySlot = _save.formationSwordIds.indexWhere((id) => id == null);
      if (emptySlot >= 0) _save.formationSwordIds[emptySlot] = def.id;
    }
    _save.stats.totalSummons++;
    if (tier.index >= SwordTier.sr.index) {
      _save.summonsSinceHighRare = 0;
    } else {
      _save.summonsSinceHighRare++;
    }
    return SummonResult(
      sword: def,
      levelAfter: newLv,
      isDuplicate: wasOwned,
      isMaxed: wasMaxed,
    );
  }

  SummonResult? summonOne() {
    if (_save.essence < summonCostSingle) return null;
    _save.essence -= summonCostSingle;
    final r = _doOnePull(guaranteedRPlus: false);
    _save.run.summons++;
    _incMission('daily_summon_15', 1, daily: true);
    _incMission('weekly_summon_120', 1, daily: false);
    _emit(loaded: true);
    unawaited(_persist());
    return r;
  }

  List<SummonResult>? summonTen() {
    if (_save.essence < summonCostTen) return null;
    _save.essence -= summonCostTen;
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
    if (_save.essence < summonCostHundred) return null;
    _save.essence -= summonCostHundred;
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

  void equipSword(String id) {
    if ((_save.ownedSwords[id] ?? 0) <= 0) return;
    _save.equippedSwordId = id;
    _save.run.changedEquippedSword = true;
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
      final districtBonus = regionSwordDistrictBonusFraction(def.id);
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
