import 'package:flutter/material.dart';

/// Static metadata for the 17 시/도 in the stock-market system.
///
/// Volatility is per-minute σ% — converted to per-tick σ in the price
/// simulation. Hourly yield is the dividend rate per hour (e.g. 0.08 = 8%
/// of the holding's market value paid out per hour into the region's
/// pendingDividend).
///
/// Market cap design: 경기도 = 100aa (1×10^17 골드). 이후 지역은
/// 10.0×에서 시작해 뒤로 갈수록 배수가 커지는 계단형 곡선으로 증가한다.
/// 모든 지역 총주식수는 10M (1,000만주)으로 통일.
/// 1주 가격 = 시가총액 / 10M.
class RegionDef {
  final String id;
  final String name;
  final String shortName;
  final int unlockOrder; // 1 = first to unlock (always 경기도)
  final double baseMarketCap;
  final int totalShares;
  final double initialPrice;
  final double volatilityPerMinute;
  final double hourlyYield;
  final Color accent;

  const RegionDef({
    required this.id,
    required this.name,
    required this.shortName,
    required this.unlockOrder,
    required this.baseMarketCap,
    required this.totalShares,
    required this.initialPrice,
    required this.volatilityPerMinute,
    required this.hourlyYield,
    required this.accent,
  });
}

/// Threshold (as a fraction) of ownership in the previous region required
/// to unlock the next.
const regionUnlockOwnershipThreshold = 0.20; // 20%

/// Maximum fraction of total shares any single player can hold. Owning a
/// majority isn't allowed so prices remain a meaningful market signal.
const regionMaxOwnershipFraction = 0.80; // 80%

/// Trade fee fraction applied on both buy and sell.
const stockTradeFee = 0.02; // 2%

/// Wall-clock seconds between price ticks. Candles still bucket on
/// [candleWindowSeconds]; multiple price ticks compose one candle.
const stockPriceTickSeconds = 1.0;

/// Candle window length in seconds.
const candleWindowSeconds = 30;

/// Maximum candles retained per region.
const candleHistoryMax = 60;

/// Dividend accrual interval.
const dividendIntervalSeconds = 3600; // 1 hour

/// Lower / upper bounds applied to current price relative to the
/// region's intrinsic (= initial) market cap. Values picked to satisfy
/// the design rule "최초 시총에서 -90%에서 +1750% 사이".
const stockPriceMinFractionOfIntrinsic = 0.10; // -90%
const stockPriceMaxFractionOfIntrinsic = 18.5; // +1750%

// All regions share this share count after the v3 rebalance — keeps a
// "1주 = 시총/10M" mental model and trims share-count visual noise.
const _baseShares = 10000000; // 10M
const _gyeonggiCap = 1.0e17;
const _incheonCap = _gyeonggiCap * 10.0;
const _chungbukCap = _incheonCap * 10.5;
const _chungnamCap = _chungbukCap * 11.0;
const _sejongCap = _chungnamCap * 11.5;
const _jeonbukCap = _sejongCap * 12.0;
const _jeonnamCap = _jeonbukCap * 12.5;
const _gwangjuCap = _jeonnamCap * 13.0;
const _daejeonCap = _gwangjuCap * 13.5;
const _daeguCap = _daejeonCap * 14.0;
const _gyeongbukCap = _daeguCap * 14.5;
const _gyeongnamCap = _gyeongbukCap * 15.0;
const _busanCap = _gyeongnamCap * 15.5;
const _ulsanCap = _busanCap * 16.0;
const _gangwonCap = _ulsanCap * 16.5;
const _jejuCap = _gangwonCap * 17.0;
const _seoulCap = _jejuCap * 18.0;

const regionCatalog = <RegionDef>[
  RegionDef(
    id: 'gyeonggi',
    name: '경기도',
    shortName: '경기',
    unlockOrder: 1,
    baseMarketCap: _gyeonggiCap,
    totalShares: _baseShares,
    initialPrice: _gyeonggiCap / _baseShares,
    volatilityPerMinute: 0.0075,
    hourlyYield: 0.08,
    accent: Color(0xFF42A5F5),
  ),
  RegionDef(
    id: 'incheon',
    name: '인천광역시',
    shortName: '인천',
    unlockOrder: 2,
    baseMarketCap: _incheonCap,
    totalShares: _baseShares,
    initialPrice: _incheonCap / _baseShares,
    volatilityPerMinute: 0.009,
    hourlyYield: 0.08,
    accent: Color(0xFF26A69A),
  ),
  RegionDef(
    id: 'chungbuk',
    name: '충청북도',
    shortName: '충북',
    unlockOrder: 3,
    baseMarketCap: _chungbukCap,
    totalShares: _baseShares,
    initialPrice: _chungbukCap / _baseShares,
    volatilityPerMinute: 0.0075,
    hourlyYield: 0.09,
    accent: Color(0xFF66BB6A),
  ),
  RegionDef(
    id: 'chungnam',
    name: '충청남도',
    shortName: '충남',
    unlockOrder: 4,
    baseMarketCap: _chungnamCap,
    totalShares: _baseShares,
    initialPrice: _chungnamCap / _baseShares,
    volatilityPerMinute: 0.0075,
    hourlyYield: 0.09,
    accent: Color(0xFF9CCC65),
  ),
  RegionDef(
    id: 'sejong',
    name: '세종특별자치시',
    shortName: '세종',
    unlockOrder: 5,
    baseMarketCap: _sejongCap,
    totalShares: _baseShares,
    initialPrice: _sejongCap / _baseShares,
    volatilityPerMinute: 0.006,
    hourlyYield: 0.10,
    accent: Color(0xFF7E57C2),
  ),
  RegionDef(
    id: 'jeonbuk',
    name: '전라북도',
    shortName: '전북',
    unlockOrder: 6,
    baseMarketCap: _jeonbukCap,
    totalShares: _baseShares,
    initialPrice: _jeonbukCap / _baseShares,
    volatilityPerMinute: 0.0105,
    hourlyYield: 0.10,
    accent: Color(0xFFFFA726),
  ),
  RegionDef(
    id: 'jeonnam',
    name: '전라남도',
    shortName: '전남',
    unlockOrder: 7,
    baseMarketCap: _jeonnamCap,
    totalShares: _baseShares,
    initialPrice: _jeonnamCap / _baseShares,
    volatilityPerMinute: 0.0105,
    hourlyYield: 0.10,
    accent: Color(0xFFFFB74D),
  ),
  RegionDef(
    id: 'gwangju',
    name: '광주광역시',
    shortName: '광주',
    unlockOrder: 8,
    baseMarketCap: _gwangjuCap,
    totalShares: _baseShares,
    initialPrice: _gwangjuCap / _baseShares,
    volatilityPerMinute: 0.009,
    hourlyYield: 0.09,
    accent: Color(0xFFEF5350),
  ),
  RegionDef(
    id: 'daejeon',
    name: '대전광역시',
    shortName: '대전',
    unlockOrder: 9,
    baseMarketCap: _daejeonCap,
    totalShares: _baseShares,
    initialPrice: _daejeonCap / _baseShares,
    volatilityPerMinute: 0.009,
    hourlyYield: 0.09,
    accent: Color(0xFFEC407A),
  ),
  RegionDef(
    id: 'daegu',
    name: '대구광역시',
    shortName: '대구',
    unlockOrder: 10,
    baseMarketCap: _daeguCap,
    totalShares: _baseShares,
    initialPrice: _daeguCap / _baseShares,
    volatilityPerMinute: 0.0105,
    hourlyYield: 0.10,
    accent: Color(0xFFAB47BC),
  ),
  RegionDef(
    id: 'gyeongbuk',
    name: '경상북도',
    shortName: '경북',
    unlockOrder: 11,
    baseMarketCap: _gyeongbukCap,
    totalShares: _baseShares,
    initialPrice: _gyeongbukCap / _baseShares,
    volatilityPerMinute: 0.012,
    hourlyYield: 0.10,
    accent: Color(0xFF8D6E63),
  ),
  RegionDef(
    id: 'gyeongnam',
    name: '경상남도',
    shortName: '경남',
    unlockOrder: 12,
    baseMarketCap: _gyeongnamCap,
    totalShares: _baseShares,
    initialPrice: _gyeongnamCap / _baseShares,
    volatilityPerMinute: 0.0105,
    hourlyYield: 0.11,
    accent: Color(0xFF6D4C41),
  ),
  RegionDef(
    id: 'busan',
    name: '부산광역시',
    shortName: '부산',
    unlockOrder: 13,
    baseMarketCap: _busanCap,
    totalShares: _baseShares,
    initialPrice: _busanCap / _baseShares,
    volatilityPerMinute: 0.009,
    hourlyYield: 0.10,
    accent: Color(0xFF5C6BC0),
  ),
  RegionDef(
    id: 'ulsan',
    name: '울산광역시',
    shortName: '울산',
    unlockOrder: 14,
    baseMarketCap: _ulsanCap,
    totalShares: _baseShares,
    initialPrice: _ulsanCap / _baseShares,
    volatilityPerMinute: 0.0105,
    hourlyYield: 0.11,
    accent: Color(0xFF3949AB),
  ),
  RegionDef(
    id: 'gangwon',
    name: '강원특별자치도',
    shortName: '강원',
    unlockOrder: 15,
    baseMarketCap: _gangwonCap,
    totalShares: _baseShares,
    initialPrice: _gangwonCap / _baseShares,
    volatilityPerMinute: 0.012,
    hourlyYield: 0.12,
    accent: Color(0xFF1E88E5),
  ),
  RegionDef(
    id: 'jeju',
    name: '제주도',
    shortName: '제주',
    unlockOrder: 16,
    baseMarketCap: _jejuCap,
    totalShares: _baseShares,
    initialPrice: _jejuCap / _baseShares,
    volatilityPerMinute: 0.018,
    hourlyYield: 0.14,
    accent: Color(0xFF00ACC1),
  ),
  RegionDef(
    id: 'seoul',
    name: '서울특별시',
    shortName: '서울',
    unlockOrder: 17,
    baseMarketCap: _seoulCap,
    totalShares: _baseShares,
    initialPrice: _seoulCap / _baseShares,
    volatilityPerMinute: 0.006,
    hourlyYield: 0.08,
    accent: Color(0xFFD32F2F),
  ),
];

final Map<String, RegionDef> _byId = {
  for (final r in regionCatalog) r.id: r,
};

RegionDef regionDefById(String id) => _byId[id]!;

/// Returns the next region in unlock order after [id], or null when [id] is
/// the last region.
RegionDef? nextRegionAfter(String id) {
  final cur = _byId[id];
  if (cur == null) return null;
  for (final r in regionCatalog) {
    if (r.unlockOrder == cur.unlockOrder + 1) return r;
  }
  return null;
}

/// Trigger threshold (cumulative gold) that unlocks the stock-market UI.
const stockMarketLifetimeGoldTrigger = 1000000000.0; // 1B
