class GameStats {
  int totalTaps;
  int playTimeSeconds;
  double maxDpsEver;
  double lifetimeGold;
  int totalSummons;
  int totalTapUpgradesBought;
  int totalCrits;
  int maxCombo;
  int comboBurstCount;
  int slimesDefeated;
  int skillsUsed;
  int boostersPurchased;
  int maxDailyStreak;
  // v13 — lifetime gold spent (producers, tap upgrades, prestige coin
  // purchases, summons via essence/coin shops, etc). Tracks player-driven
  // outflow rather than passively-burnt currency.
  double totalGoldSpent;

  GameStats({
    this.totalTaps = 0,
    this.playTimeSeconds = 0,
    this.maxDpsEver = 0,
    this.lifetimeGold = 0,
    this.totalSummons = 0,
    this.totalTapUpgradesBought = 0,
    this.totalCrits = 0,
    this.maxCombo = 0,
    this.comboBurstCount = 0,
    this.slimesDefeated = 0,
    this.skillsUsed = 0,
    this.boostersPurchased = 0,
    this.maxDailyStreak = 0,
    this.totalGoldSpent = 0,
  });

  Map<String, dynamic> toJson() => {
        'totalTaps': totalTaps,
        'playTimeSeconds': playTimeSeconds,
        'maxDpsEver': maxDpsEver,
        'lifetimeGold': lifetimeGold,
        'totalSummons': totalSummons,
        'totalTapUpgradesBought': totalTapUpgradesBought,
        'totalCrits': totalCrits,
        'maxCombo': maxCombo,
        'comboBurstCount': comboBurstCount,
        'slimesDefeated': slimesDefeated,
        'skillsUsed': skillsUsed,
        'boostersPurchased': boostersPurchased,
        'maxDailyStreak': maxDailyStreak,
        'totalGoldSpent': totalGoldSpent,
      };

  factory GameStats.fromJson(Map<String, dynamic> json) => GameStats(
        totalTaps: json['totalTaps'] as int? ?? 0,
        playTimeSeconds: json['playTimeSeconds'] as int? ?? 0,
        maxDpsEver: (json['maxDpsEver'] as num?)?.toDouble() ?? 0,
        lifetimeGold: (json['lifetimeGold'] as num?)?.toDouble() ?? 0,
        totalSummons: json['totalSummons'] as int? ?? 0,
        totalTapUpgradesBought: json['totalTapUpgradesBought'] as int? ?? 0,
        totalCrits: json['totalCrits'] as int? ?? 0,
        maxCombo: json['maxCombo'] as int? ?? 0,
        comboBurstCount: json['comboBurstCount'] as int? ?? 0,
        slimesDefeated: json['slimesDefeated'] as int? ?? 0,
        skillsUsed: json['skillsUsed'] as int? ?? 0,
        boostersPurchased: json['boostersPurchased'] as int? ?? 0,
        maxDailyStreak: json['maxDailyStreak'] as int? ?? 0,
        totalGoldSpent: (json['totalGoldSpent'] as num?)?.toDouble() ?? 0,
      );
}

class GameSettings {
  bool haptic;
  bool sound;
  bool darkMode;
  bool tutorialSeen;
  bool highContrast;
  double textScale;
  bool reduceTapHaptics;

  GameSettings({
    this.haptic = true,
    this.sound = true,
    this.darkMode = false,
    this.tutorialSeen = false,
    this.highContrast = false,
    this.textScale = 1.0,
    this.reduceTapHaptics = false,
  });

  Map<String, dynamic> toJson() => {
        'haptic': haptic,
        'sound': sound,
        'darkMode': darkMode,
        'tutorialSeen': tutorialSeen,
        'highContrast': highContrast,
        'textScale': textScale,
        'reduceTapHaptics': reduceTapHaptics,
      };

  factory GameSettings.fromJson(Map<String, dynamic> json) => GameSettings(
        haptic: json['haptic'] as bool? ?? true,
        sound: json['sound'] as bool? ?? true,
        darkMode: json['darkMode'] as bool? ?? false,
        tutorialSeen: json['tutorialSeen'] as bool? ?? false,
        highContrast: json['highContrast'] as bool? ?? false,
        textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
        reduceTapHaptics: json['reduceTapHaptics'] as bool? ?? false,
      );
}
