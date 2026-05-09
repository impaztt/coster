import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../data/region_catalog.dart';
import '../data/sword_affinities.dart';
import '../models/stock_market.dart';
import '../providers/game_provider.dart';
import '../widgets/candle_chart.dart';

/// Top-level view rendered inside the store hub investment tab.
class StockMarketView extends ConsumerWidget {
  const StockMarketView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final market = game.market;

    final owned = <_RegionRow>[];
    final tradable = <_RegionRow>[];
    final locked = <_RegionRow>[];
    for (final def in regionCatalog) {
      final st = market.regions[def.id];
      if (st == null) continue;
      final row = _RegionRow(def: def, state: st);
      if (st.shares > 0) {
        owned.add(row);
      } else if (st.unlocked) {
        tradable.add(row);
      } else {
        locked.add(row);
      }
    }

    final totalHoldings = notifier.totalHoldingsValue;
    final totalPending = notifier.totalPendingDividend;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _MarketSummary(
          totalHoldings: totalHoldings,
          totalPending: totalPending,
          realized: market.totalRealizedProfit,
          fees: market.totalFeesPaid,
          dividendsClaimed: market.totalDividendsClaimed,
          onClaimAll: totalPending <= 0
              ? null
              : () {
                  final amount = notifier.claimAllDividends();
                  if (amount > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '📈 전체 배당 +${NumberFormatter.format(amount)}골드 수령',
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
          onSellAll: totalHoldings <= 0
              ? null
              : () => _confirmAndSellAll(context, notifier, totalHoldings),
        ),
        const SizedBox(height: 12),
        if (owned.isNotEmpty) ...[
          const _SectionLabel(label: '보유 종목', accent: AppColors.coral),
          for (final r in owned) _RegionListTile(row: r, status: _Status.owned),
          const SizedBox(height: 12),
        ],
        if (tradable.isNotEmpty) ...[
          const _SectionLabel(
            label: '거래 가능 종목',
            accent: Color(0xFF7C4DFF),
          ),
          for (final r in tradable)
            _RegionListTile(row: r, status: _Status.tradable),
          const SizedBox(height: 12),
        ],
        if (locked.isNotEmpty) ...[
          const _SectionLabel(label: '잠긴 종목', accent: Colors.black38),
          for (final r in locked)
            _LockedTile(
              row: r,
              market: market,
              lifetimeGold: game.lifetimeGold,
            ),
        ],
      ],
    );
  }
}

class _RegionRow {
  final RegionDef def;
  final RegionState state;
  _RegionRow({required this.def, required this.state});
}

Future<void> _confirmAndSellAll(
  BuildContext context,
  GameNotifier notifier,
  double totalHoldings,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('전체 매도'),
      content: Text(
        '보유한 모든 지역의 주식을 현재가로 매도합니다.\n'
        '예상 평가액: ${NumberFormatter.format(totalHoldings)}골드\n'
        '매도 시 2% 수수료가 차감됩니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
          ),
          child: const Text('매도'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final r = notifier.sellAllShares();
  if (r.regionsSold == 0) return;
  if (!context.mounted) return;
  final realizedSign = r.realizedProfit >= 0 ? '+' : '-';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${r.regionsSold}개 지역 ${NumberFormatter.formatInt(r.sharesSold)}주 매도 · 순 ${NumberFormatter.format(r.netProceeds)}골드 ($realizedSign${NumberFormatter.format(r.realizedProfit.abs())})',
      ),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

enum _Status { owned, tradable }

class _MarketSummary extends StatelessWidget {
  final double totalHoldings;
  final double totalPending;
  final double realized;
  final double fees;
  final double dividendsClaimed;
  final VoidCallback? onClaimAll;
  final VoidCallback? onSellAll;
  const _MarketSummary({
    required this.totalHoldings,
    required this.totalPending,
    required this.realized,
    required this.fees,
    required this.dividendsClaimed,
    required this.onClaimAll,
    required this.onSellAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFF7C4DFF)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📈 주식 시장',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: '평가액',
                  value: NumberFormatter.format(totalHoldings),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStat(
                  label: '실현손익',
                  value: (realized >= 0 ? '+' : '') +
                      NumberFormatter.formatPrecise(realized),
                  valueColor:
                      realized >= 0 ? Colors.white : const Color(0xFFFFEBEE),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: '누적 수수료',
                  value: NumberFormatter.format(fees),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStat(
                  label: '누적 배당',
                  value: NumberFormatter.format(dividendsClaimed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '미수령 배당 합계',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        NumberFormatter.format(totalPending),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: onClaimAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFD32F2F),
                    minimumSize: const Size(96, 40),
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.3),
                    disabledForegroundColor: Colors.white,
                  ),
                  child: const Text(
                    '전체 수령',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onSellAll,
            icon: const Icon(Icons.sell, size: 16, color: Colors.white),
            label: const Text(
              '전체 매도',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(40),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.7),
                width: 1.4,
              ),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SummaryStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color accent;
  const _SectionLabel({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionListTile extends ConsumerWidget {
  final _RegionRow row;
  final _Status status;
  const _RegionListTile({required this.row, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = row.def;
    final st = row.state;
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final ownership = st.shares / def.totalShares;
    final districtBonus = notifier.regionSwordDistrictBonusFraction(def.id);
    final effectiveYield = notifier.regionEffectiveHourlyYield(def.id);
    final regionOwned = ownedSwordCountForRegion(def.id, game.ownedSwords);
    final regionTotal = totalSwordCountForRegion(def.id);
    final lastClose = st.recentCandles.isEmpty
        ? (st.formingCandle?.open ?? st.currentPrice)
        : st.recentCandles.last.close;
    final pctChange =
        lastClose == 0 ? 0.0 : (st.currentPrice - lastClose) / lastClose * 100;
    final up = pctChange >= 0;
    final priceColor = up ? const Color(0xFFD32F2F) : const Color(0xFF1976D2);
    final unrealized =
        st.shares > 0 ? (st.currentPrice - st.avgCost) * st.shares : 0.0;
    final unrealizedPct = (st.shares > 0 && st.avgCost > 0)
        ? (st.currentPrice - st.avgCost) / st.avgCost * 100
        : 0.0;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RegionDetailScreen(regionId: def.id),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: def.accent.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: def.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        def.shortName,
                        style: TextStyle(
                          color: def.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          def.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '시가총액 ${NumberFormatter.format(st.currentPrice * def.totalShares)} · 배당 ${(effectiveYield * 100).toStringAsFixed(1)}%/h',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        if (districtBonus > 0) ...[
                          const SizedBox(height: 3),
                          Text(
                            '검세권 +${(districtBonus * 100).toStringAsFixed(1)}% · 지역 검 $regionOwned/$regionTotal',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: def.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NumberFormatter.formatPrecise(st.currentPrice),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${up ? '▲' : '▼'} ${pctChange.abs().toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: priceColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (status == _Status.owned) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: '보유',
                        value: '${(ownership * 100).toStringAsFixed(2)}%',
                      ),
                    ),
                    Expanded(
                      child: _MiniStat(
                        label: '평단',
                        value: NumberFormatter.formatPrecise(st.avgCost),
                      ),
                    ),
                    Expanded(
                      child: _MiniStat(
                        label: '평가손익',
                        value: _profitLabel(unrealized, unrealizedPct),
                        valueColor: unrealized >= 0
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF1976D2),
                      ),
                    ),
                  ],
                ),
                if (st.pendingDividend > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.coral.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.payments,
                            size: 14, color: AppColors.deepCoral),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '미수령 ${NumberFormatter.format(st.pendingDividend)}골드',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.deepCoral,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final paid = notifier.claimDividend(def.id);
                            if (paid > 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '📈 ${def.name} 배당 +${NumberFormatter.format(paid)}골드',
                                  ),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(56, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text(
                            '수령',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _MiniStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}

String _profitLabel(double amount, double pct) {
  final amountSign = amount >= 0 ? '+' : '-';
  final pctSign = pct >= 0 ? '+' : '-';
  return '$amountSign${NumberFormatter.format(amount.abs())} '
      '($pctSign${pct.abs().toStringAsFixed(2)}%)';
}

class _LockedTile extends StatelessWidget {
  final _RegionRow row;
  final StockMarketState market;
  final double lifetimeGold;
  const _LockedTile({
    required this.row,
    required this.market,
    required this.lifetimeGold,
  });

  @override
  Widget build(BuildContext context) {
    final def = row.def;
    // Find which region's 20% gates this one.
    String? blockingMessage;
    final order = def.unlockOrder;
    if (order > 1) {
      // Walk catalog backward to find the predecessor.
      RegionDef? prev;
      for (final r in regionCatalog) {
        if (r.unlockOrder == order - 1) {
          prev = r;
          break;
        }
      }
      if (prev != null) {
        final prevState = market.regions[prev.id];
        final prevOwn =
            prevState == null ? 0.0 : prevState.shares / prev.totalShares;
        final needPct =
            (regionUnlockOwnershipThreshold * 100).toStringAsFixed(0);
        blockingMessage =
            '${prev.name} $needPct% 보유 시 해금 (현재 ${(prevOwn * 100).toStringAsFixed(2)}%)';
      }
    } else {
      final progress =
          (lifetimeGold / stockMarketLifetimeGoldTrigger).clamp(0.0, 1.0);
      blockingMessage =
          '누적 골드 ${NumberFormatter.format(stockMarketLifetimeGoldTrigger)} 달성 시 해금 '
          '(현재 ${NumberFormatter.format(lifetimeGold)} · ${(progress * 100).toStringAsFixed(2)}%)';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.black38, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
                if (blockingMessage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    blockingMessage,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RegionDetailScreen extends ConsumerWidget {
  final String regionId;
  const RegionDetailScreen({super.key, required this.regionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final def = notifier.regionDef(regionId);
    final st = game.market.regions[regionId];
    if (st == null) {
      return Scaffold(
        appBar: AppBar(title: Text(def.name)),
        body: const Center(child: Text('데이터를 불러올 수 없습니다.')),
      );
    }

    final ownership = st.shares / def.totalShares;
    final marketCap = st.currentPrice * def.totalShares;
    final lastClose = st.recentCandles.isEmpty
        ? (st.formingCandle?.open ?? st.currentPrice)
        : st.recentCandles.last.close;
    final pctChange =
        lastClose == 0 ? 0.0 : (st.currentPrice - lastClose) / lastClose * 100;
    final up = pctChange >= 0;
    final priceColor = up ? const Color(0xFFD32F2F) : const Color(0xFF1976D2);
    final unrealized =
        st.shares > 0 ? (st.currentPrice - st.avgCost) * st.shares : 0.0;
    final unrealizedPct = (st.shares > 0 && st.avgCost > 0)
        ? (st.currentPrice - st.avgCost) / st.avgCost * 100
        : 0.0;
    final hourlyEst = notifier.regionHourlyDividendEstimate(regionId);
    final districtBonus = notifier.regionSwordDistrictBonusFraction(regionId);
    final effectiveYield = notifier.regionEffectiveHourlyYield(regionId);
    final regionOwned = ownedSwordCountForRegion(regionId, game.ownedSwords);
    final regionTotal = totalSwordCountForRegion(regionId);

    return Scaffold(
      appBar: AppBar(
        title: Text(def.name),
        backgroundColor: def.accent.withValues(alpha: 0.12),
        foregroundColor: def.accent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시가총액 ${NumberFormatter.format(marketCap)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      NumberFormatter.formatPrecise(st.currentPrice),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${up ? '▲' : '▼'} ${pctChange.abs().toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: priceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (st.pendingDividend > 0)
            _PendingDividendCard(
              region: def,
              amount: st.pendingDividend,
              onClaim: () {
                final paid = notifier.claimDividend(def.id);
                if (paid > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '📈 ${def.name} 배당 +${NumberFormatter.format(paid)}골드 수령',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 12),
          _DistrictBondCard(
            region: def,
            bonus: districtBonus,
            owned: regionOwned,
            total: regionTotal,
            effectiveYield: effectiveYield,
            intrinsicPrice: st.intrinsicPrice,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12),
            ),
            child: CandleChart(
              candles: st.recentCandles,
              forming: st.formingCandle,
              avgCost: st.shares > 0 ? st.avgCost : null,
              intrinsicPrice: st.intrinsicPrice,
            ),
          ),
          const SizedBox(height: 12),
          _HoldingPanel(
            shares: st.shares,
            ownership: ownership,
            avgCost: st.avgCost,
            unrealized: unrealized,
            unrealizedPct: unrealizedPct,
            hourlyEstimate: hourlyEst,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openBuyDialog(context, ref, def),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text(
                    '매수',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: st.shares > 0
                      ? () => _openSellDialog(context, ref, def)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    minimumSize: const Size.fromHeight(50),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text(
                    '매도',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '왕복 수수료 4% — 단기 매매보다 장기 보유 + 시간당 배당이 정석입니다.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openBuyDialog(BuildContext context, WidgetRef ref, RegionDef def) {
    showDialog<void>(
      context: context,
      builder: (_) => _BuyDialog(regionId: def.id),
    );
  }

  void _openSellDialog(BuildContext context, WidgetRef ref, RegionDef def) {
    showDialog<void>(
      context: context,
      builder: (_) => _SellDialog(regionId: def.id),
    );
  }
}

class _PendingDividendCard extends StatelessWidget {
  final RegionDef region;
  final double amount;
  final VoidCallback onClaim;
  const _PendingDividendCard({
    required this.region,
    required this.amount,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.coral.withValues(alpha: 0.85),
          AppColors.deepCoral.withValues(alpha: 0.85),
        ]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '미수령 배당',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${NumberFormatter.format(amount)} 골드',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.deepCoral,
              minimumSize: const Size(80, 40),
            ),
            child: const Text(
              '수령',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistrictBondCard extends StatelessWidget {
  final RegionDef region;
  final double bonus;
  final int owned;
  final int total;
  final double effectiveYield;
  final double intrinsicPrice;

  const _DistrictBondCard({
    required this.region,
    required this.bonus,
    required this.owned,
    required this.total,
    required this.effectiveYield,
    required this.intrinsicPrice,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : owned / total;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: region.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: region.accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_city, size: 18, color: region.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${region.shortName} 검세권',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: region.accent,
                  ),
                ),
              ),
              Text(
                '+${(bonus * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: region.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(region.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '지역 검',
                  value: '$owned / $total',
                  valueColor: region.accent,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '실효 배당',
                  value: '${(effectiveYield * 100).toStringAsFixed(1)}%/h',
                  valueColor: region.accent,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '내재가',
                  value: NumberFormatter.formatPrecise(intrinsicPrice),
                  valueColor: region.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '이 지역에 연결된 검을 모으거나 착용에 배치하면 주식의 내재가치와 배당률이 올라갑니다.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingPanel extends StatelessWidget {
  final int shares;
  final double ownership;
  final double avgCost;
  final double unrealized;
  final double unrealizedPct;
  final double hourlyEstimate;
  const _HoldingPanel({
    required this.shares,
    required this.ownership,
    required this.avgCost,
    required this.unrealized,
    required this.unrealizedPct,
    required this.hourlyEstimate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '보유 수량',
                  value: '${NumberFormatter.formatInt(shares)} 주',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '지분율',
                  value: '${(ownership * 100).toStringAsFixed(3)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '평단가',
                  value:
                      shares > 0 ? NumberFormatter.formatPrecise(avgCost) : '-',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '평가손익',
                  value: shares > 0
                      ? _profitLabel(unrealized, unrealizedPct)
                      : '-',
                  valueColor: shares > 0
                      ? (unrealized >= 0
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF1976D2))
                      : null,
                ),
              ),
            ],
          ),
          if (shares > 0) ...[
            const SizedBox(height: 10),
            _MiniStat(
              label: '시간당 배당 예상',
              value: '${NumberFormatter.format(hourlyEstimate)} 골드',
            ),
          ],
        ],
      ),
    );
  }
}

class _BuyDialog extends ConsumerStatefulWidget {
  final String regionId;
  const _BuyDialog({required this.regionId});

  @override
  ConsumerState<_BuyDialog> createState() => _BuyDialogState();
}

class _BuyDialogState extends ConsumerState<_BuyDialog> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final def = notifier.regionDef(widget.regionId);
    final st = game.market.regions[widget.regionId]!;
    final price = st.currentPrice;
    final maxByGold = notifier.maxBuyableShares(widget.regionId);
    final maxByCap = def.totalShares - st.shares;
    final cap = maxByGold < maxByCap ? maxByGold : maxByCap;
    if (_qty > cap) _qty = cap;
    if (_qty < 1) _qty = cap > 0 ? 1 : 0;

    final gross = _qty * price;
    final fee = gross * stockTradeFee;
    final total = gross + fee;
    final newShares = st.shares + _qty;
    final newOwn = newShares / def.totalShares;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('${def.name} 매수'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('현재가', NumberFormatter.formatPrecise(price)),
            _kv('보유 골드', NumberFormatter.format(game.gold)),
            _kv(
              '최대 매수 가능',
              '${NumberFormatter.formatInt(cap)} 주 (지분 ${(regionMaxOwnershipFraction * 100).toStringAsFixed(0)}% 한도)',
            ),
            const SizedBox(height: 10),
            _QtyStepper(
              value: _qty,
              max: cap,
              onChanged: (v) => setState(() => _qty = v),
            ),
            const SizedBox(height: 12),
            _kv('매수 금액', NumberFormatter.format(gross)),
            _kv('수수료(2%)', NumberFormatter.format(fee)),
            const Divider(height: 16),
            _kv('총 차감', NumberFormatter.format(total), bold: true),
            const SizedBox(height: 4),
            _kv('매수 후 보유율', '${(newOwn * 100).toStringAsFixed(3)}%'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: (cap == 0 || _qty <= 0)
              ? null
              : () {
                  final bought = notifier.buyShares(widget.regionId, _qty);
                  if (bought > 0) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${def.name} ${NumberFormatter.formatInt(bought)}주 매수 완료'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD32F2F),
          ),
          child: const Text('매수 확정'),
        ),
      ],
    );
  }
}

class _SellDialog extends ConsumerStatefulWidget {
  final String regionId;
  const _SellDialog({required this.regionId});

  @override
  ConsumerState<_SellDialog> createState() => _SellDialogState();
}

class _SellDialogState extends ConsumerState<_SellDialog> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final def = notifier.regionDef(widget.regionId);
    final st = game.market.regions[widget.regionId]!;
    final price = st.currentPrice;
    final cap = st.shares;
    if (_qty > cap) _qty = cap;
    if (_qty < 1 && cap > 0) _qty = 1;

    final gross = _qty * price;
    final fee = gross * stockTradeFee;
    final net = gross - fee;
    final realized = (price - st.avgCost) * _qty - fee;
    final realizedPositive = realized >= 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('${def.name} 매도'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('현재가', NumberFormatter.formatPrecise(price)),
            _kv('평단가', NumberFormatter.formatPrecise(st.avgCost)),
            _kv('보유 수량', '${NumberFormatter.formatInt(st.shares)} 주'),
            const SizedBox(height: 10),
            _QtyStepper(
              value: _qty,
              max: cap,
              onChanged: (v) => setState(() => _qty = v),
            ),
            const SizedBox(height: 12),
            _kv('매도 금액', NumberFormatter.format(gross)),
            _kv('수수료(2%)', NumberFormatter.format(fee)),
            const Divider(height: 16),
            _kv('순 수령액', NumberFormatter.format(net), bold: true),
            const SizedBox(height: 4),
            _kv(
              '실현손익',
              (realizedPositive ? '+' : '-') +
                  NumberFormatter.format(realized.abs()),
              valueColor: realizedPositive
                  ? const Color(0xFFD32F2F)
                  : const Color(0xFF1976D2),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: (cap == 0 || _qty <= 0)
              ? null
              : () {
                  final r = notifier.sellShares(widget.regionId, _qty);
                  if (r.sharesSold > 0) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${def.name} ${NumberFormatter.formatInt(r.sharesSold)}주 매도 · 순 ${NumberFormatter.format(r.netProceeds)}골드',
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
          ),
          child: const Text('매도 확정'),
        ),
      ],
    );
  }
}

Widget _kv(String k, String v, {bool bold = false, Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.6),
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    ),
  );
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  const _QtyStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  void _bump(int delta) {
    var next = value + delta;
    if (next < 1) next = 1;
    if (next > max) next = max;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _qbtn('-1000', () => _bump(-1000)),
            _qbtn('-100', () => _bump(-100)),
            _qbtn('-10', () => _bump(-10)),
            _qbtn('-1', () => _bump(-1)),
            _qbtn('+1', () => _bump(1)),
            _qbtn('+10', () => _bump(10)),
            _qbtn('+100', () => _bump(100)),
            _qbtn('+1000', () => _bump(1000)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: max == 0 ? 0 : value.clamp(1, max).toDouble(),
                min: max == 0 ? 0 : 1,
                max: max == 0 ? 1 : max.toDouble(),
                onChanged: max == 0 ? null : (v) => onChanged(v.round()),
              ),
            ),
            FilledButton(
              onPressed: max == 0 ? null : () => onChanged(max),
              style: FilledButton.styleFrom(
                minimumSize: const Size(56, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('최대'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${NumberFormatter.formatInt(value)} 주',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _qbtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
