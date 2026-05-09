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

class StockMarketState {
  Map<String, RegionState> regions;
  int totalTradesCount;
  double totalFeesPaid;
  double totalDividendsClaimed;
  double totalRealizedProfit;

  StockMarketState({
    Map<String, RegionState>? regions,
    this.totalTradesCount = 0,
    this.totalFeesPaid = 0,
    this.totalDividendsClaimed = 0,
    this.totalRealizedProfit = 0,
  }) : regions = regions ?? <String, RegionState>{};

  Map<String, dynamic> toJson() => {
        'regions':
            regions.map((k, v) => MapEntry(k, v.toJson())),
        'totalTradesCount': totalTradesCount,
        'totalFeesPaid': totalFeesPaid,
        'totalDividendsClaimed': totalDividendsClaimed,
        'totalRealizedProfit': totalRealizedProfit,
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
      );
}
