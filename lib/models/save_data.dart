import 'booster.dart';
import 'game_stats.dart';
import 'run_stats.dart';
import 'stock_market.dart';
import 'sword.dart';

class SaveData {
  static const currentVersion = 19;

  int version;
  double gold;
  double totalGoldEarned;
  Map<String, int> producerLevels;
  Map<String, int> tapUpgradeLevels;
  int prestigeSouls;
  int prestigeCount;
  int prestigeCoins;
  Map<String, int> prestigeUpgradeLevels;
  int ascensionCoreLevel;
  DateTime lastSavedAt;
  GameStats stats;
  GameSettings settings;

  // Sword collection (v3)
  int essence;
  Map<String, int> ownedSwords; // id → level (1~10)
  String? equippedSwordId;
  int summonsSinceHighRare; // pity counter (reset on SR+)
  List<String?> formationSwordIds; // 5-slot equipped formation.

  // Achievements (v4)
  Set<String> unlockedAchievements;

  // Daily login bonus (v5)
  DateTime? lastDailyClaimAt;
  int dailyStreak;

  // Time-limited boosters (v6)
  List<Booster> activeBoosters;

  // Deterministic golden-slime spawn counter (v7).
  int tapsSinceSlime;

  // Skill cooldowns (v8): skill id → moment when the skill becomes usable
  // again. Skill is "ready" if missing or in the past.
  Map<String, DateTime> skillReadyAt;

  // Mission progress (v10)
  int dailyMissionDayKey;
  int weeklyMissionWeekKey;
  Map<String, int> dailyMissionProgress;
  Set<String> dailyMissionClaimed;
  Map<String, int> weeklyMissionProgress;
  Set<String> weeklyMissionClaimed;

  // Progressive feature unlocks (v11)
  Set<String> unlockedFeatures;

  // Regional stock market (v12)
  StockMarketState market;

  // Repeating-achievement progress (v13). Map id -> cleared stage count.
  Map<String, int> repeatingAchievementStages;

  // Per-prestige run-scoped stats (v13). Reset on prestige().
  RunStats run;

  // Premium shop state (v15)
  bool adsRemoved;
  DateTime? monthlyPassExpiresAt;
  DateTime? monthlyPassLastClaimAt;
  bool starterPackagePurchased;

  // Premium expansion (v18)
  bool firstPurchasePackageClaimed;
  DateTime? seasonPassExpiresAt;
  DateTime? seasonPassLastClaimAt;
  DateTime? seasonPassLastWeeklyClaimAt;
  bool masterPackagePurchased;
  DateTime? firstLaunchAt; // anchors the 24h first-purchase popup window
  bool firstPurchasePopupShown;

  // Main sword (v18): the single sword anchored to the home tab. Separate
  // from the collection — collection swords still grant passive/active
  // bonuses, but the home tab visually represents this main sword and only
  // its stage controls the home-tap visual evolution.
  int mainSwordStage; // 0~50
  String? mainSwordName; // null until first +1 enhance prompts the user
  int mainSwordHighestStage; // for the permanent title (never decays)
  Set<int> mainSwordTiersShown; // which evolution cutscenes have played
  int mainSwordEnhanceAttempts; // analytics
  // Sum of all milestone collectionBonusFraction grants. Applied as a
  // fraction on top of the existing collection bonus.
  double mainSwordCollectionBonusFraction;

  // Gold-exchange shop (v17): how much of the player's currentGold came from
  // the essence-for-gold exchange and hasn't been spent yet. While this is
  // > 0, that portion of currentGold is excluded from the prestige-coin
  // wealthScore so paying for the exchange can't directly buy prestige
  // coins. Decrements down to 0 as the player spends gold on producers,
  // upgrades, or share purchases.
  double purchasedGoldUnconverted;
  // Daily-rotating exchange counter, keyed on _dayKey().
  int goldExchangeDayKey;
  int goldExchangeDailyCount;
  // Per-prestige-run exchange counter; resets in prestige().
  int goldExchangePrestigeCount;
  // Last day-key the 8-hour pack was used (it has its own once-per-day cap).
  int goldExchangeEightHourDayKey;

  SaveData({
    this.version = currentVersion,
    this.gold = 0,
    this.totalGoldEarned = 0,
    Map<String, int>? producerLevels,
    Map<String, int>? tapUpgradeLevels,
    this.prestigeSouls = 0,
    this.prestigeCount = 0,
    this.prestigeCoins = 0,
    Map<String, int>? prestigeUpgradeLevels,
    this.ascensionCoreLevel = 0,
    DateTime? lastSavedAt,
    GameStats? stats,
    GameSettings? settings,
    this.essence = 90,
    Map<String, int>? ownedSwords,
    this.equippedSwordId,
    this.summonsSinceHighRare = 0,
    List<String?>? formationSwordIds,
    Set<String>? unlockedAchievements,
    this.lastDailyClaimAt,
    this.dailyStreak = 0,
    List<Booster>? activeBoosters,
    this.tapsSinceSlime = 0,
    Map<String, DateTime>? skillReadyAt,
    this.dailyMissionDayKey = 0,
    this.weeklyMissionWeekKey = 0,
    Map<String, int>? dailyMissionProgress,
    Set<String>? dailyMissionClaimed,
    Map<String, int>? weeklyMissionProgress,
    Set<String>? weeklyMissionClaimed,
    Set<String>? unlockedFeatures,
    StockMarketState? market,
    Map<String, int>? repeatingAchievementStages,
    RunStats? run,
    this.adsRemoved = false,
    this.monthlyPassExpiresAt,
    this.monthlyPassLastClaimAt,
    this.starterPackagePurchased = false,
    this.purchasedGoldUnconverted = 0,
    this.goldExchangeDayKey = 0,
    this.goldExchangeDailyCount = 0,
    this.goldExchangePrestigeCount = 0,
    this.goldExchangeEightHourDayKey = 0,
    this.mainSwordStage = 0,
    this.mainSwordName,
    this.mainSwordHighestStage = 0,
    Set<int>? mainSwordTiersShown,
    this.mainSwordEnhanceAttempts = 0,
    this.mainSwordCollectionBonusFraction = 0,
    this.firstPurchasePackageClaimed = false,
    this.seasonPassExpiresAt,
    this.seasonPassLastClaimAt,
    this.seasonPassLastWeeklyClaimAt,
    this.masterPackagePurchased = false,
    this.firstLaunchAt,
    this.firstPurchasePopupShown = false,
  })  : mainSwordTiersShown = mainSwordTiersShown ?? <int>{},
        producerLevels = producerLevels ?? {},
        tapUpgradeLevels = tapUpgradeLevels ?? {},
        prestigeUpgradeLevels = prestigeUpgradeLevels ?? {},
        lastSavedAt = lastSavedAt ?? DateTime.now(),
        stats = stats ?? GameStats(),
        settings = settings ?? GameSettings(),
        ownedSwords = ownedSwords ?? {},
        formationSwordIds = _normalizeFormationSwordIds(formationSwordIds),
        unlockedAchievements = unlockedAchievements ?? <String>{},
        activeBoosters = activeBoosters ?? <Booster>[],
        skillReadyAt = skillReadyAt ?? <String, DateTime>{},
        dailyMissionProgress = dailyMissionProgress ?? <String, int>{},
        dailyMissionClaimed = dailyMissionClaimed ?? <String>{},
        weeklyMissionProgress = weeklyMissionProgress ?? <String, int>{},
        weeklyMissionClaimed = weeklyMissionClaimed ?? <String>{},
        unlockedFeatures = unlockedFeatures ?? <String>{},
        market = market ?? StockMarketState(),
        repeatingAchievementStages =
            repeatingAchievementStages ?? <String, int>{},
        run = run ?? RunStats();

  Map<String, dynamic> toJson() => {
        'version': version,
        'gold': gold,
        'totalGoldEarned': totalGoldEarned,
        'producerLevels': producerLevels,
        'tapUpgradeLevels': tapUpgradeLevels,
        'prestigeSouls': prestigeSouls,
        'prestigeCount': prestigeCount,
        'prestigeCoins': prestigeCoins,
        'prestigeUpgradeLevels': prestigeUpgradeLevels,
        'ascensionCoreLevel': ascensionCoreLevel,
        'lastSavedAt': lastSavedAt.toIso8601String(),
        'stats': stats.toJson(),
        'settings': settings.toJson(),
        'essence': essence,
        'ownedSwords': ownedSwords,
        'equippedSwordId': equippedSwordId,
        'summonsSinceHighRare': summonsSinceHighRare,
        'formationSwordIds': formationSwordIds,
        'unlockedAchievements': unlockedAchievements.toList(),
        'lastDailyClaimAt': lastDailyClaimAt?.toIso8601String(),
        'dailyStreak': dailyStreak,
        'activeBoosters': activeBoosters.map((b) => b.toJson()).toList(),
        'tapsSinceSlime': tapsSinceSlime,
        'skillReadyAt':
            skillReadyAt.map((k, v) => MapEntry(k, v.toIso8601String())),
        'dailyMissionDayKey': dailyMissionDayKey,
        'weeklyMissionWeekKey': weeklyMissionWeekKey,
        'dailyMissionProgress': dailyMissionProgress,
        'dailyMissionClaimed': dailyMissionClaimed.toList(),
        'weeklyMissionProgress': weeklyMissionProgress,
        'weeklyMissionClaimed': weeklyMissionClaimed.toList(),
        'unlockedFeatures': unlockedFeatures.toList(),
        'market': market.toJson(),
        'repeatingAchievementStages': repeatingAchievementStages,
        'run': run.toJson(),
        'adsRemoved': adsRemoved,
        'monthlyPassExpiresAt': monthlyPassExpiresAt?.toIso8601String(),
        'monthlyPassLastClaimAt': monthlyPassLastClaimAt?.toIso8601String(),
        'starterPackagePurchased': starterPackagePurchased,
        'purchasedGoldUnconverted': purchasedGoldUnconverted,
        'goldExchangeDayKey': goldExchangeDayKey,
        'goldExchangeDailyCount': goldExchangeDailyCount,
        'goldExchangePrestigeCount': goldExchangePrestigeCount,
        'goldExchangeEightHourDayKey': goldExchangeEightHourDayKey,
        'mainSwordStage': mainSwordStage,
        'mainSwordName': mainSwordName,
        'mainSwordHighestStage': mainSwordHighestStage,
        'mainSwordTiersShown': mainSwordTiersShown.toList(),
        'mainSwordEnhanceAttempts': mainSwordEnhanceAttempts,
        'mainSwordCollectionBonusFraction': mainSwordCollectionBonusFraction,
        'firstPurchasePackageClaimed': firstPurchasePackageClaimed,
        'seasonPassExpiresAt': seasonPassExpiresAt?.toIso8601String(),
        'seasonPassLastClaimAt': seasonPassLastClaimAt?.toIso8601String(),
        'seasonPassLastWeeklyClaimAt':
            seasonPassLastWeeklyClaimAt?.toIso8601String(),
        'masterPackagePurchased': masterPackagePurchased,
        'firstLaunchAt': firstLaunchAt?.toIso8601String(),
        'firstPurchasePopupShown': firstPurchasePopupShown,
      };

  factory SaveData.fromJson(Map<String, dynamic> json) => SaveData(
        version: json['version'] as int? ?? 0,
        gold: (json['gold'] as num?)?.toDouble() ?? 0,
        totalGoldEarned: (json['totalGoldEarned'] as num?)?.toDouble() ?? 0,
        producerLevels:
            Map<String, int>.from(json['producerLevels'] as Map? ?? {}),
        tapUpgradeLevels:
            Map<String, int>.from(json['tapUpgradeLevels'] as Map? ?? {}),
        prestigeSouls: json['prestigeSouls'] as int? ?? 0,
        prestigeCount: json['prestigeCount'] as int? ?? 0,
        prestigeCoins: json['prestigeCoins'] as int? ?? 0,
        prestigeUpgradeLevels:
            Map<String, int>.from(json['prestigeUpgradeLevels'] as Map? ?? {}),
        ascensionCoreLevel: json['ascensionCoreLevel'] as int? ?? 0,
        lastSavedAt: DateTime.tryParse(json['lastSavedAt'] as String? ?? '') ??
            DateTime.now(),
        stats: GameStats.fromJson(json['stats'] as Map<String, dynamic>? ?? {}),
        settings: GameSettings.fromJson(
            json['settings'] as Map<String, dynamic>? ?? {}),
        essence: json['essence'] as int? ?? 90,
        ownedSwords: Map<String, int>.from(json['ownedSwords'] as Map? ?? {}),
        equippedSwordId: json['equippedSwordId'] as String?,
        summonsSinceHighRare: json['summonsSinceHighRare'] as int? ?? 0,
        formationSwordIds: (json['formationSwordIds'] as List?)
            ?.map((e) => e is String ? e : null)
            .toList(),
        unlockedAchievements: (json['unlockedAchievements'] as List?)
                ?.map((e) => e as String)
                .toSet() ??
            <String>{},
        lastDailyClaimAt:
            DateTime.tryParse(json['lastDailyClaimAt'] as String? ?? ''),
        dailyStreak: json['dailyStreak'] as int? ?? 0,
        activeBoosters: (json['activeBoosters'] as List?)
                ?.map((e) =>
                    Booster.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <Booster>[],
        tapsSinceSlime: json['tapsSinceSlime'] as int? ?? 0,
        skillReadyAt: ((json['skillReadyAt'] as Map?) ?? {}).map(
          (k, v) => MapEntry(
            k as String,
            DateTime.tryParse(v as String? ?? '') ?? DateTime.now(),
          ),
        ),
        dailyMissionDayKey: json['dailyMissionDayKey'] as int? ?? 0,
        weeklyMissionWeekKey: json['weeklyMissionWeekKey'] as int? ?? 0,
        dailyMissionProgress:
            Map<String, int>.from(json['dailyMissionProgress'] as Map? ?? {}),
        dailyMissionClaimed: (json['dailyMissionClaimed'] as List?)
                ?.map((e) => e as String)
                .toSet() ??
            <String>{},
        weeklyMissionProgress:
            Map<String, int>.from(json['weeklyMissionProgress'] as Map? ?? {}),
        weeklyMissionClaimed: (json['weeklyMissionClaimed'] as List?)
                ?.map((e) => e as String)
                .toSet() ??
            <String>{},
        unlockedFeatures: (json['unlockedFeatures'] as List?)
                ?.map((e) => e as String)
                .toSet() ??
            <String>{},
        market: json['market'] == null
            ? StockMarketState()
            : StockMarketState.fromJson(
                Map<String, dynamic>.from(json['market'] as Map)),
        repeatingAchievementStages: Map<String, int>.from(
            json['repeatingAchievementStages'] as Map? ?? const {}),
        run: json['run'] == null
            ? RunStats()
            : RunStats.fromJson(Map<String, dynamic>.from(json['run'] as Map)),
        adsRemoved: json['adsRemoved'] as bool? ?? false,
        monthlyPassExpiresAt:
            DateTime.tryParse(json['monthlyPassExpiresAt'] as String? ?? ''),
        monthlyPassLastClaimAt:
            DateTime.tryParse(json['monthlyPassLastClaimAt'] as String? ?? ''),
        starterPackagePurchased:
            json['starterPackagePurchased'] as bool? ?? false,
        purchasedGoldUnconverted:
            (json['purchasedGoldUnconverted'] as num?)?.toDouble() ?? 0,
        goldExchangeDayKey: json['goldExchangeDayKey'] as int? ?? 0,
        goldExchangeDailyCount: json['goldExchangeDailyCount'] as int? ?? 0,
        goldExchangePrestigeCount:
            json['goldExchangePrestigeCount'] as int? ?? 0,
        goldExchangeEightHourDayKey:
            json['goldExchangeEightHourDayKey'] as int? ?? 0,
        mainSwordStage: json['mainSwordStage'] as int? ?? 0,
        mainSwordName: json['mainSwordName'] as String?,
        mainSwordHighestStage: json['mainSwordHighestStage'] as int? ?? 0,
        mainSwordTiersShown:
            ((json['mainSwordTiersShown'] as List?) ?? const [])
                .map((e) => e as int)
                .toSet(),
        mainSwordEnhanceAttempts: json['mainSwordEnhanceAttempts'] as int? ?? 0,
        mainSwordCollectionBonusFraction:
            (json['mainSwordCollectionBonusFraction'] as num?)?.toDouble() ?? 0,
        firstPurchasePackageClaimed:
            json['firstPurchasePackageClaimed'] as bool? ?? false,
        seasonPassExpiresAt:
            DateTime.tryParse(json['seasonPassExpiresAt'] as String? ?? ''),
        seasonPassLastClaimAt:
            DateTime.tryParse(json['seasonPassLastClaimAt'] as String? ?? ''),
        seasonPassLastWeeklyClaimAt: DateTime.tryParse(
            json['seasonPassLastWeeklyClaimAt'] as String? ?? ''),
        masterPackagePurchased:
            json['masterPackagePurchased'] as bool? ?? false,
        firstLaunchAt:
            DateTime.tryParse(json['firstLaunchAt'] as String? ?? ''),
        firstPurchasePopupShown:
            json['firstPurchasePopupShown'] as bool? ?? false,
      );

  static List<String?> _normalizeFormationSwordIds(List<String?>? source) {
    final slots = List<String?>.filled(swordFormationSlotCount, null);
    if (source == null) return slots;
    final limit = source.length < swordFormationSlotCount
        ? source.length
        : swordFormationSlotCount;
    for (var i = 0; i < limit; i++) {
      slots[i] = source[i];
    }
    return slots;
  }
}
