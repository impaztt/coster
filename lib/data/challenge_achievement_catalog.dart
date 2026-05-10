import '../models/achievement.dart';

/// "Challenge" achievements — boolean conditions that aren't a simple
/// lifetime accumulation. Many use [AchContext.run] (per-reopen
/// counters) to gate by "do this in a single run".
///
/// These are still [AchievementDef]s and live in the regular catalog so
/// the milestone progress percentage can include them. They differ only
/// in *how* their predicate reads state — not in their data shape.
AchievementDef _challenge({
  required String id,
  required String name,
  required String description,
  required int ticketReward,
  required bool Function(AchContext) test,
}) {
  return AchievementDef(
    id: id,
    name: name,
    description: description,
    category: AchievementCategory.master,
    ticketReward: ticketReward,
    progress: (ctx) => AchProgress(test(ctx) ? 1 : 0, 1),
  );
}

final challengeAchievementCatalog = <AchievementDef>[
  // ── 1재개장-스코프: 폭발적 단일 런 ──
  _challenge(
    id: 'ch_run_taps_10k',
    name: '단숨에 만 번',
    description: '한 재개장 안에 터치 10,000회',
    ticketReward: 25,
    test: (c) => c.run.taps >= 10000,
  ),
  _challenge(
    id: 'ch_run_taps_100k',
    name: '단숨에 십만 번',
    description: '한 재개장 안에 터치 100,000회',
    ticketReward: 60,
    test: (c) => c.run.taps >= 100000,
  ),
  _challenge(
    id: 'ch_run_crits_1k',
    name: '대박 탑승 폭격',
    description: '한 재개장 안에 대박 탑승 1,000회',
    ticketReward: 35,
    test: (c) => c.run.crits >= 1000,
  ),
  _challenge(
    id: 'ch_run_burst_50',
    name: '버스트 페스티벌',
    description: '한 재개장 안에 콤보 버스트 50회',
    ticketReward: 50,
    test: (c) => c.run.comboBursts >= 50,
  ),
  _challenge(
    id: 'ch_run_combo_100',
    name: '한 런 콤보 100',
    description: '한 재개장 안에 콤보 100 도달',
    ticketReward: 60,
    test: (c) => c.run.maxCombo >= 100,
  ),
  _challenge(
    id: 'ch_run_combo_200',
    name: '한 런 콤보 200',
    description: '한 재개장 안에 콤보 200 도달',
    ticketReward: 120,
    test: (c) => c.run.maxCombo >= 200,
  ),
  _challenge(
    id: 'ch_run_slimes_100',
    name: 'VIP 러시',
    description: '한 재개장 안에 VIP 손님 100명 응대',
    ticketReward: 30,
    test: (c) => c.run.slimesDefeated >= 100,
  ),
  _challenge(
    id: 'ch_run_summons_50',
    name: '한 런 50도입',
    description: '한 재개장 안에 도입 50회',
    ticketReward: 40,
    test: (c) => c.run.summons >= 50,
  ),
  _challenge(
    id: 'ch_run_skills_20',
    name: '한 런 이벤트 20',
    description: '한 재개장 안에 이벤트 20회 사용',
    ticketReward: 30,
    test: (c) => c.run.skillsUsed >= 20,
  ),
  _challenge(
    id: 'ch_run_dps_1t',
    name: '한 런 초당 수익 1T',
    description: '한 재개장 안에 초당 수익 1T/s 도달',
    ticketReward: 80,
    test: (c) => c.run.dpsPeak >= 1e12,
  ),
  _challenge(
    id: 'ch_run_dps_1aa',
    name: '한 런 초당 수익 1aa',
    description: '한 재개장 안에 초당 수익 1aa/s 도달',
    ticketReward: 200,
    test: (c) => c.run.dpsPeak >= 1e15,
  ),

  // ── 미니멀 챌린지: ~없이 재개장 ──
  // These three are unlocked at the moment of prestige completion when the
  // run-scoped `usedAny*` flags are still false. The provider has explicit
  // logic in prestige() before run.reset(); the test predicate stays false
  // here so _checkAchievements never auto-fires them mid-run.
  _challenge(
    id: 'ch_no_skill',
    name: '이벤트 없이',
    description: '이벤트 한 번도 안 쓰고 재개장',
    ticketReward: 70,
    test: (_) => false,
  ),
  _challenge(
    id: 'ch_no_booster',
    name: '부스터 없이',
    description: '부스터 한 번도 안 쓰고 재개장',
    ticketReward: 70,
    test: (_) => false,
  ),
  _challenge(
    id: 'ch_no_tap_upgrade',
    name: '운영 강화 없이',
    description: '운영 강화 한 번도 안 사고 재개장',
    ticketReward: 70,
    test: (_) => false,
  ),

  // ── 시즈 (단일 시점) 챌린지 ──
  _challenge(
    id: 'ch_combo_300',
    name: '콤보 300',
    description: '콤보 300 도달',
    ticketReward: 200,
    test: (c) => c.maxCombo >= 300,
  ),
  _challenge(
    id: 'ch_combo_500',
    name: '콤보 500',
    description: '콤보 500 도달',
    ticketReward: 400,
    test: (c) => c.maxCombo >= 500,
  ),
  _challenge(
    id: 'ch_ticket_1k',
    name: '티켓 천 보유',
    description: '티켓 1,000 동시 보유',
    ticketReward: 25,
    test: (c) => c.ticket >= 1000,
  ),
  _challenge(
    id: 'ch_ticket_10k',
    name: '티켓 만 보유',
    description: '티켓 10,000 동시 보유',
    ticketReward: 80,
    test: (c) => c.ticket >= 10000,
  ),

  // ── 주식 트레이딩 챌린지 ──
  _challenge(
    id: 'ch_stock_run_trades_50',
    name: '단타 데이트레이더',
    description: '한 재개장 안에 주식 거래 50회',
    ticketReward: 50,
    test: (c) => c.run.stockTrades >= 50,
  ),
  _challenge(
    id: 'ch_stock_run_buys_20',
    name: '한 런 주식 20매수',
    description: '한 재개장 안에 주식 매수 20회',
    ticketReward: 30,
    test: (c) => c.run.stockBuys >= 20,
  ),
  _challenge(
    id: 'ch_stock_run_sells_10',
    name: '한 런 주식 10매도',
    description: '한 재개장 안에 주식 매도 10회',
    ticketReward: 30,
    test: (c) => c.run.stockSells >= 10,
  ),
  _challenge(
    id: 'ch_stock_run_div_1b',
    name: '한 런 배당 1B',
    description: '한 재개장 안에 배당 1B 수령',
    ticketReward: 50,
    test: (c) => c.run.stockDividendsClaimed >= 1e9,
  ),
  _challenge(
    id: 'ch_stock_run_div_1t',
    name: '한 런 배당 1T',
    description: '한 재개장 안에 배당 1T 수령',
    ticketReward: 150,
    test: (c) => c.run.stockDividendsClaimed >= 1e12,
  ),
  _challenge(
    id: 'ch_stock_realized_profit_1t',
    name: '시세차익 1T',
    description: '누적 시세차익 1T',
    ticketReward: 120,
    test: (c) => c.run.stockProfitRealized >= 1e12,
  ),

  // ── 콜렉션 + 메타 ──
  _challenge(
    id: 'ch_run_dismantle_10',
    name: '한 런 분해 10',
    description: '한 재개장 안에 코스터 10대 분해',
    ticketReward: 25,
    test: (c) => c.run.coasterDismantles >= 10,
  ),
  _challenge(
    id: 'ch_run_producer_lv_500',
    name: '한 런 직원 강화 500',
    description: '한 재개장 안에 직원 누적 강화 500레벨',
    ticketReward: 40,
    test: (c) => c.run.producerLevelsBought >= 500,
  ),
  _challenge(
    id: 'ch_run_summons_500',
    name: '한 런 500도입',
    description: '한 재개장 안에 도입 500회',
    ticketReward: 100,
    test: (c) => c.run.summons >= 500,
  ),
  _challenge(
    id: 'ch_run_gold_earned_1aa',
    name: '한 런 골드 1aa',
    description: '한 재개장 안에 1aa 골드 획득',
    ticketReward: 250,
    test: (c) => c.run.goldEarned >= 1e15,
  ),
  _challenge(
    id: 'ch_run_dps_1ab',
    name: '한 런 초당 수익 1ab',
    description: '한 재개장 안에 초당 수익 1ab/s 도달',
    ticketReward: 500,
    test: (c) => c.run.dpsPeak >= 1e18,
  ),
];
