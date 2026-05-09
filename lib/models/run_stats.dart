/// Run-scoped counters — reset on every prestige. Use for "in a single
/// prestige run" challenge achievements. Lifetime stats stay on GameStats.
class RunStats {
  int taps;
  int crits;
  int comboBursts;
  int slimesDefeated;
  int summons;
  int skillsUsed;
  int boostersUsed;
  int producerLevelsBought;
  int tapUpgradesBought;
  int swordDismantles;
  double goldEarned;
  double goldSpent;
  double dpsPeak;
  int maxCombo;
  int stockTrades;
  int stockBuys;
  int stockSells;
  double stockProfitRealized;
  double stockDividendsClaimed;
  // True until any tap-upgrade is bought / any sword equipped — used by
  // niche "no-equip" or "no-upgrade" challenges. We only track the cheap
  // booleans that wouldn't bloat per-tick work.
  bool usedAnySkill;
  bool usedAnyBooster;
  bool boughtAnyTapUpgrade;
  bool changedEquippedSword;

  RunStats({
    this.taps = 0,
    this.crits = 0,
    this.comboBursts = 0,
    this.slimesDefeated = 0,
    this.summons = 0,
    this.skillsUsed = 0,
    this.boostersUsed = 0,
    this.producerLevelsBought = 0,
    this.tapUpgradesBought = 0,
    this.swordDismantles = 0,
    this.goldEarned = 0,
    this.goldSpent = 0,
    this.dpsPeak = 0,
    this.maxCombo = 0,
    this.stockTrades = 0,
    this.stockBuys = 0,
    this.stockSells = 0,
    this.stockProfitRealized = 0,
    this.stockDividendsClaimed = 0,
    this.usedAnySkill = false,
    this.usedAnyBooster = false,
    this.boughtAnyTapUpgrade = false,
    this.changedEquippedSword = false,
  });

  void reset() {
    taps = 0;
    crits = 0;
    comboBursts = 0;
    slimesDefeated = 0;
    summons = 0;
    skillsUsed = 0;
    boostersUsed = 0;
    producerLevelsBought = 0;
    tapUpgradesBought = 0;
    swordDismantles = 0;
    goldEarned = 0;
    goldSpent = 0;
    dpsPeak = 0;
    maxCombo = 0;
    stockTrades = 0;
    stockBuys = 0;
    stockSells = 0;
    stockProfitRealized = 0;
    stockDividendsClaimed = 0;
    usedAnySkill = false;
    usedAnyBooster = false;
    boughtAnyTapUpgrade = false;
    changedEquippedSword = false;
  }

  Map<String, dynamic> toJson() => {
        'taps': taps,
        'crits': crits,
        'comboBursts': comboBursts,
        'slimesDefeated': slimesDefeated,
        'summons': summons,
        'skillsUsed': skillsUsed,
        'boostersUsed': boostersUsed,
        'producerLevelsBought': producerLevelsBought,
        'tapUpgradesBought': tapUpgradesBought,
        'swordDismantles': swordDismantles,
        'goldEarned': goldEarned,
        'goldSpent': goldSpent,
        'dpsPeak': dpsPeak,
        'maxCombo': maxCombo,
        'stockTrades': stockTrades,
        'stockBuys': stockBuys,
        'stockSells': stockSells,
        'stockProfitRealized': stockProfitRealized,
        'stockDividendsClaimed': stockDividendsClaimed,
        'usedAnySkill': usedAnySkill,
        'usedAnyBooster': usedAnyBooster,
        'boughtAnyTapUpgrade': boughtAnyTapUpgrade,
        'changedEquippedSword': changedEquippedSword,
      };

  factory RunStats.fromJson(Map<String, dynamic> json) => RunStats(
        taps: (json['taps'] as num?)?.toInt() ?? 0,
        crits: (json['crits'] as num?)?.toInt() ?? 0,
        comboBursts: (json['comboBursts'] as num?)?.toInt() ?? 0,
        slimesDefeated: (json['slimesDefeated'] as num?)?.toInt() ?? 0,
        summons: (json['summons'] as num?)?.toInt() ?? 0,
        skillsUsed: (json['skillsUsed'] as num?)?.toInt() ?? 0,
        boostersUsed: (json['boostersUsed'] as num?)?.toInt() ?? 0,
        producerLevelsBought:
            (json['producerLevelsBought'] as num?)?.toInt() ?? 0,
        tapUpgradesBought: (json['tapUpgradesBought'] as num?)?.toInt() ?? 0,
        swordDismantles: (json['swordDismantles'] as num?)?.toInt() ?? 0,
        goldEarned: (json['goldEarned'] as num?)?.toDouble() ?? 0,
        goldSpent: (json['goldSpent'] as num?)?.toDouble() ?? 0,
        dpsPeak: (json['dpsPeak'] as num?)?.toDouble() ?? 0,
        maxCombo: (json['maxCombo'] as num?)?.toInt() ?? 0,
        stockTrades: (json['stockTrades'] as num?)?.toInt() ?? 0,
        stockBuys: (json['stockBuys'] as num?)?.toInt() ?? 0,
        stockSells: (json['stockSells'] as num?)?.toInt() ?? 0,
        stockProfitRealized:
            (json['stockProfitRealized'] as num?)?.toDouble() ?? 0,
        stockDividendsClaimed:
            (json['stockDividendsClaimed'] as num?)?.toDouble() ?? 0,
        usedAnySkill: json['usedAnySkill'] as bool? ?? false,
        usedAnyBooster: json['usedAnyBooster'] as bool? ?? false,
        boughtAnyTapUpgrade: json['boughtAnyTapUpgrade'] as bool? ?? false,
        changedEquippedSword: json['changedEquippedSword'] as bool? ?? false,
      );
}
