enum BoosterType {
  dps('dps'),
  tap('tap'),
  rush('rush'), // affects both dps + tap
  autoTap('auto_tap'); // simulates taps for the player; multiplier ignored

  final String id;
  const BoosterType(this.id);

  static BoosterType fromId(String id) =>
      BoosterType.values.firstWhere((e) => e.id == id, orElse: () => dps);
}

class Booster {
  final BoosterType type;
  final double multiplier;
  final DateTime expiresAt;

  Booster({
    required this.type,
    required this.multiplier,
    required this.expiresAt,
  });

  Duration remaining(DateTime now) {
    final diff = expiresAt.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  bool isActive(DateTime now) => expiresAt.isAfter(now);

  Map<String, dynamic> toJson() => {
        'type': type.id,
        'multiplier': multiplier,
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory Booster.fromJson(Map<String, dynamic> json) => Booster(
        type: BoosterType.fromId(json['type'] as String? ?? 'dps'),
        multiplier: (json['multiplier'] as num?)?.toDouble() ?? 2.0,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
