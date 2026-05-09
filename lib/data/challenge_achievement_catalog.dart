import '../models/achievement.dart';

/// "Challenge" achievements — boolean conditions that aren't a simple
/// lifetime accumulation. Many use [AchContext.run] (per-prestige
/// counters) to gate by "do this in a single run".
///
/// These are still [AchievementDef]s and live in the regular catalog so
/// the milestone progress percentage can include them. They differ only
/// in *how* their predicate reads state — not in their data shape.
AchievementDef _challenge({
  required String id,
  required String name,
  required String description,
  required int essenceReward,
  required bool Function(AchContext) test,
}) {
  return AchievementDef(
    id: id,
    name: name,
    description: description,
    category: AchievementCategory.master,
    essenceReward: essenceReward,
    progress: (ctx) => AchProgress(test(ctx) ? 1 : 0, 1),
  );
}

final challengeAchievementCatalog = <AchievementDef>[
  // ── 1환생-스코프: 폭발적 단일 런 ──
  _challenge(
    id: 'ch_run_taps_10k',
    name: '단숨에 만 번',
    description: '한 환생 안에 터치 10,000회',
    essenceReward: 25,
    test: (c) => c.run.taps >= 10000,
  ),
  _challenge(
    id: 'ch_run_taps_100k',
    name: '단숨에 십만 번',
    description: '한 환생 안에 터치 100,000회',
    essenceReward: 60,
    test: (c) => c.run.taps >= 100000,
  ),
  _challenge(
    id: 'ch_run_crits_1k',
    name: '치명타 폭격기',
    description: '한 환생 안에 치명타 1,000회',
    essenceReward: 35,
    test: (c) => c.run.crits >= 1000,
  ),
  _challenge(
    id: 'ch_run_burst_50',
    name: '버스트 페스티벌',
    description: '한 환생 안에 콤보 버스트 50회',
    essenceReward: 50,
    test: (c) => c.run.comboBursts >= 50,
  ),
  _challenge(
    id: 'ch_run_combo_100',
    name: '한 런 콤보 100',
    description: '한 환생 안에 콤보 100 도달',
    essenceReward: 60,
    test: (c) => c.run.maxCombo >= 100,
  ),
  _challenge(
    id: 'ch_run_combo_200',
    name: '한 런 콤보 200',
    description: '한 환생 안에 콤보 200 도달',
    essenceReward: 120,
    test: (c) => c.run.maxCombo >= 200,
  ),
  _challenge(
    id: 'ch_run_slimes_100',
    name: '슬라임 광란',
    description: '한 환생 안에 슬라임 100마리 처치',
    essenceReward: 30,
    test: (c) => c.run.slimesDefeated >= 100,
  ),
  _challenge(
    id: 'ch_run_summons_50',
    name: '한 런 50소환',
    description: '한 환생 안에 소환 50회',
    essenceReward: 40,
    test: (c) => c.run.summons >= 50,
  ),
  _challenge(
    id: 'ch_run_skills_20',
    name: '한 런 스킬 20',
    description: '한 환생 안에 스킬 20회 사용',
    essenceReward: 30,
    test: (c) => c.run.skillsUsed >= 20,
  ),
  _challenge(
    id: 'ch_run_dps_1t',
    name: '한 런 DPS 1T',
    description: '한 환생 안에 DPS 1T/s 도달',
    essenceReward: 80,
    test: (c) => c.run.dpsPeak >= 1e12,
  ),
  _challenge(
    id: 'ch_run_dps_1aa',
    name: '한 런 DPS 1aa',
    description: '한 환생 안에 DPS 1aa/s 도달',
    essenceReward: 200,
    test: (c) => c.run.dpsPeak >= 1e15,
  ),

  // ── 미니멀 챌린지: ~없이 환생 ──
  // These three are unlocked at the moment of prestige completion when the
  // run-scoped `usedAny*` flags are still false. The provider has explicit
  // logic in prestige() before run.reset(); the test predicate stays false
  // here so _checkAchievements never auto-fires them mid-run.
  _challenge(
    id: 'ch_no_skill',
    name: '스킬 없이',
    description: '스킬 한 번도 안 쓰고 환생',
    essenceReward: 70,
    test: (_) => false,
  ),
  _challenge(
    id: 'ch_no_booster',
    name: '부스터 없이',
    description: '부스터 한 번도 안 쓰고 환생',
    essenceReward: 70,
    test: (_) => false,
  ),
  _challenge(
    id: 'ch_no_tap_upgrade',
    name: '터치 강화 없이',
    description: '터치 강화 한 번도 안 사고 환생',
    essenceReward: 70,
    test: (_) => false,
  ),

  // ── 시즈 (단일 시점) 챌린지 ──
  _challenge(
    id: 'ch_combo_300',
    name: '콤보 300',
    description: '콤보 300 도달',
    essenceReward: 200,
    test: (c) => c.maxCombo >= 300,
  ),
  _challenge(
    id: 'ch_combo_500',
    name: '콤보 500',
    description: '콤보 500 도달',
    essenceReward: 400,
    test: (c) => c.maxCombo >= 500,
  ),
  _challenge(
    id: 'ch_essence_1k',
    name: '정수 천 보유',
    description: '정수 1,000 동시 보유',
    essenceReward: 25,
    test: (c) => c.essence >= 1000,
  ),
  _challenge(
    id: 'ch_essence_10k',
    name: '정수 만 보유',
    description: '정수 10,000 동시 보유',
    essenceReward: 80,
    test: (c) => c.essence >= 10000,
  ),

  // ── 주식 트레이딩 챌린지 ──
  _challenge(
    id: 'ch_stock_run_trades_50',
    name: '단타 데이트레이더',
    description: '한 환생 안에 주식 거래 50회',
    essenceReward: 50,
    test: (c) => c.run.stockTrades >= 50,
  ),
  _challenge(
    id: 'ch_stock_run_buys_20',
    name: '한 런 주식 20매수',
    description: '한 환생 안에 주식 매수 20회',
    essenceReward: 30,
    test: (c) => c.run.stockBuys >= 20,
  ),
  _challenge(
    id: 'ch_stock_run_sells_10',
    name: '한 런 주식 10매도',
    description: '한 환생 안에 주식 매도 10회',
    essenceReward: 30,
    test: (c) => c.run.stockSells >= 10,
  ),
  _challenge(
    id: 'ch_stock_run_div_1b',
    name: '한 런 배당 1B',
    description: '한 환생 안에 배당 1B 수령',
    essenceReward: 50,
    test: (c) => c.run.stockDividendsClaimed >= 1e9,
  ),
  _challenge(
    id: 'ch_stock_run_div_1t',
    name: '한 런 배당 1T',
    description: '한 환생 안에 배당 1T 수령',
    essenceReward: 150,
    test: (c) => c.run.stockDividendsClaimed >= 1e12,
  ),
  _challenge(
    id: 'ch_stock_realized_profit_1t',
    name: '시세차익 1T',
    description: '누적 시세차익 1T',
    essenceReward: 120,
    test: (c) => c.run.stockProfitRealized >= 1e12,
  ),

  // ── 콜렉션 + 메타 ──
  _challenge(
    id: 'ch_run_dismantle_10',
    name: '한 런 분해 10',
    description: '한 환생 안에 검 10자루 분해',
    essenceReward: 25,
    test: (c) => c.run.swordDismantles >= 10,
  ),
  _challenge(
    id: 'ch_run_producer_lv_500',
    name: '한 런 동료 강화 500',
    description: '한 환생 안에 동료 누적 강화 500레벨',
    essenceReward: 40,
    test: (c) => c.run.producerLevelsBought >= 500,
  ),
  _challenge(
    id: 'ch_run_summons_500',
    name: '한 런 500소환',
    description: '한 환생 안에 소환 500회',
    essenceReward: 100,
    test: (c) => c.run.summons >= 500,
  ),
  _challenge(
    id: 'ch_run_gold_earned_1aa',
    name: '한 런 골드 1aa',
    description: '한 환생 안에 1aa 골드 획득',
    essenceReward: 250,
    test: (c) => c.run.goldEarned >= 1e15,
  ),
  _challenge(
    id: 'ch_run_dps_1ab',
    name: '한 런 DPS 1ab',
    description: '한 환생 안에 DPS 1ab/s 도달',
    essenceReward: 500,
    test: (c) => c.run.dpsPeak >= 1e18,
  ),
];
