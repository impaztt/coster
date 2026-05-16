// Persisted models for the regional stock market system.
// All prices are in gold and stored as doubles. Shares are integers.

class Candle {
  final DateTime startedAt;
  double open;
  double high;
  double low;
  double close;
  double volume;

  Candle({
    required this.startedAt,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  factory Candle.flat(DateTime at, double price) => Candle(
        startedAt: at,
        open: price,
        high: price,
        low: price,
        close: price,
      );

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      };

  factory Candle.fromJson(Map<String, dynamic> json) => Candle(
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        open: (json['open'] as num?)?.toDouble() ?? 0,
        high: (json['high'] as num?)?.toDouble() ?? 0,
        low: (json['low'] as num?)?.toDouble() ?? 0,
        close: (json['close'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
      );
}

class RegionState {
  final String regionId;
  bool unlocked;
  int shares;
  double avgCost;
  double currentPrice;
  double intrinsicPrice;
  double pendingDividend;
  DateTime? lastAccrualAt;
  List<Candle> recentCandles;
  Candle? formingCandle;

  RegionState({
    required this.regionId,
    this.unlocked = false,
    this.shares = 0,
    this.avgCost = 0,
    required this.currentPrice,
    required this.intrinsicPrice,
    this.pendingDividend = 0,
    this.lastAccrualAt,
    List<Candle>? recentCandles,
    this.formingCandle,
  }) : recentCandles = recentCandles ?? <Candle>[];

  Map<String, dynamic> toJson() => {
        'regionId': regionId,
        'unlocked': unlocked,
        'shares': shares,
        'avgCost': avgCost,
        'currentPrice': currentPrice,
        'intrinsicPrice': intrinsicPrice,
        'pendingDividend': pendingDividend,
        'lastAccrualAt': lastAccrualAt?.toIso8601String(),
        'recentCandles': recentCandles.map((c) => c.toJson()).toList(),
        'formingCandle': formingCandle?.toJson(),
      };

  factory RegionState.fromJson(Map<String, dynamic> json) => RegionState(
        regionId: json['regionId'] as String? ?? '',
        unlocked: json['unlocked'] as bool? ?? false,
        shares: (json['shares'] as num?)?.toInt() ?? 0,
        avgCost: (json['avgCost'] as num?)?.toDouble() ?? 0,
        currentPrice: (json['currentPrice'] as num?)?.toDouble() ?? 0,
        intrinsicPrice: (json['intrinsicPrice'] as num?)?.toDouble() ?? 0,
        pendingDividend: (json['pendingDividend'] as num?)?.toDouble() ?? 0,
        lastAccrualAt: json['lastAccrualAt'] == null
            ? null
            : DateTime.tryParse(json['lastAccrualAt'] as String),
        recentCandles: (json['recentCandles'] as List?)
                ?.map((e) => Candle.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <Candle>[],
        formingCandle: json['formingCandle'] == null
            ? null
            : Candle.fromJson(
                Map<String, dynamic>.from(json['formingCandle'] as Map)),
      );
}

/// §3.5 v2 market events. Types & semantics:
///   • bubble    — single-region intrinsic price boost (e.g. ×1.5) for 3-6h
///   • correction — global intrinsic price drop (e.g. ×0.8) for ~1h
/// Multiplier is applied multiplicatively on top of [regionIntrinsicPrice];
/// price simulation's mean-reversion drift then pulls actual prices toward
/// the new level over the event window.
enum MarketEventType { bubble, correction }

class MarketEvent {
  final String id;
  final MarketEventType type;
  /// null when the event applies to all regions (e.g. correction).
  final String? regionId;
  final double priceMultiplier;
  final DateTime startedAt;
  final DateTime endsAt;

  const MarketEvent({
    required this.id,
    required this.type,
    required this.regionId,
    required this.priceMultiplier,
    required this.startedAt,
    required this.endsAt,
  });

  bool isActive(DateTime now) =>
      now.isAfter(startedAt) && now.isBefore(endsAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'regionId': regionId,
        'priceMultiplier': priceMultiplier,
        'startedAt': startedAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
      };

  factory MarketEvent.fromJson(Map<String, dynamic> json) => MarketEvent(
        id: json['id'] as String? ?? '',
        type: MarketEventType.values.firstWhere(
          (e) => e.name == (json['type'] as String?),
          orElse: () => MarketEventType.correction,
        ),
        regionId: json['regionId'] as String?,
        priceMultiplier:
            (json['priceMultiplier'] as num?)?.toDouble() ?? 1.0,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        endsAt: DateTime.tryParse(json['endsAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class StockMarketState {
  Map<String, RegionState> regions;
  int totalTradesCount;
  double totalFeesPaid;
  double totalDividendsClaimed;
  double totalRealizedProfit;
  /// §3.5 v2 — active bubble / correction events. Persisted so events
  /// survive app restarts but expire normally on the wall clock.
  List<MarketEvent> activeEvents;
  /// §3.5 v2 — last attempt to roll for a new event. Used by the
  /// scheduler to gate the dice across the configured cooldown window.
  DateTime? lastEventRollAt;

  StockMarketState({
    Map<String, RegionState>? regions,
    this.totalTradesCount = 0,
    this.totalFeesPaid = 0,
    this.totalDividendsClaimed = 0,
    this.totalRealizedProfit = 0,
    List<MarketEvent>? activeEvents,
    this.lastEventRollAt,
  })  : regions = regions ?? <String, RegionState>{},
        activeEvents = activeEvents ?? <MarketEvent>[];

  Map<String, dynamic> toJson() => {
        'regions':
            regions.map((k, v) => MapEntry(k, v.toJson())),
        'totalTradesCount': totalTradesCount,
        'totalFeesPaid': totalFeesPaid,
        'totalDividendsClaimed': totalDividendsClaimed,
        'totalRealizedProfit': totalRealizedProfit,
        'activeEvents': activeEvents.map((e) => e.toJson()).toList(),
        'lastEventRollAt': lastEventRollAt?.toIso8601String(),
      };

  factory StockMarketState.fromJson(Map<String, dynamic> json) =>
      StockMarketState(
        regions: ((json['regions'] as Map?) ?? {}).map(
          (k, v) => MapEntry(
            k as String,
            RegionState.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        totalTradesCount: (json['totalTradesCount'] as num?)?.toInt() ?? 0,
        totalFeesPaid: (json['totalFeesPaid'] as num?)?.toDouble() ?? 0,
        totalDividendsClaimed:
            (json['totalDividendsClaimed'] as num?)?.toDouble() ?? 0,
        totalRealizedProfit:
            (json['totalRealizedProfit'] as num?)?.toDouble() ?? 0,
        activeEvents: (json['activeEvents'] as List?)
                ?.map((e) =>
                    MarketEvent.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <MarketEvent>[],
        lastEventRollAt:
            DateTime.tryParse(json['lastEventRollAt'] as String? ?? ''),
      );
}
