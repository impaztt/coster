// Phase 1B — Balance simulator.
//
// Runs a headless "rational player" against the live catalog data so we
// can predict how a balance change affects the gold / prestige curve
// without actually playing. Used as the safety net for §3.1 (multiplier
// stack restructure) — capture baseline numbers now, re-run after the
// refactor, compare.
//
// Scope (v1):
//   - Producer purchasing (greedy by cost-per-dps-gain)
//   - DPS accumulation over simulated time
//   - Prestige loop using the live coin formula (new curve §3.4)
//   - Brand-research-only upgrade spending (simplest meta loop)
//
// Out of scope (v1, extend later if needed):
//   - Tap power / taps (tap becomes irrelevant mid-run per §3.2)
//   - Coasters / gacha / sets / formation
//   - Skills / boosters / main coaster / stock market
//
// Run with:
//   flutter test test/balance_simulator_test.dart --reporter expanded
//
// Output goes via print(); the test() blocks just frame the runs.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:coster/data/prestige_upgrade_catalog.dart';
import 'package:coster/data/producer_catalog.dart';

// ───────────────────────────────────────────────────────────────────────
//  Coin formula (mirrors _calcPrestigeCoinsFromProgress in game_provider).
//  Duplicated here on purpose so we can flip [useNewCurve] for A/B work.
// ───────────────────────────────────────────────────────────────────────

int prestigeCoinsFor({
  required double totalGoldEarned,
  required double currentGold,
  required int producerLevelSum,
  required int tapUpgradeSum,
  required int prestigeCount,
  required Map<String, int> prestigeUpgradeLevels,
  required bool useNewCurve,
}) {
  final wealthBase =
      ((totalGoldEarned + currentGold * 2).clamp(0.0, double.infinity)) / 1e7;

  double wealthScore;
  if (useNewCurve) {
    final exponent = 0.55 - math.min(prestigeCount, 5) * 0.01;
    wealthScore =
        wealthBase > 0 ? math.pow(wealthBase, exponent).toDouble() : 0.0;
  } else {
    wealthScore = wealthBase > 0 ? math.sqrt(wealthBase) : 0.0;
  }

  final progressionScore = producerLevelSum / 30 + tapUpgradeSum / 20;
  final runDepthScore = math.min(10.0, prestigeCount * 0.1);
  final rawScore = wealthScore + progressionScore + runDepthScore;

  final stackBonus = useNewCurve ? 1.0 + prestigeCount * 0.02 : 1.0;
  final adjusted = (rawScore * stackBonus).floor();
  if (adjusted <= 0) return 0;

  final bonus = 1.0 + prestigeCoinGainBonusFraction(prestigeUpgradeLevels);
  return math.max(1, (adjusted * bonus).floor());
}

// ───────────────────────────────────────────────────────────────────────
//  Sim state + tick loop.
// ───────────────────────────────────────────────────────────────────────

class HourlySnapshot {
  final double simHours;
  final double gold;
  final double totalGold;
  final double dps;
  final int prestigeCount;
  final int prestigeCoins;
  final int brandResearchLv;
  final int totalProducerLevels;
  const HourlySnapshot({
    required this.simHours,
    required this.gold,
    required this.totalGold,
    required this.dps,
    required this.prestigeCount,
    required this.prestigeCoins,
    required this.brandResearchLv,
    required this.totalProducerLevels,
  });
}

class SimState {
  double gold = 0;
  double totalGoldEarned = 0;
  int prestigeCount = 0;
  int prestigeCoins = 0;
  final Map<String, int> producerLevels = {};
  final Map<String, int> prestigeUpgradeLevels = {};
  double secondsElapsed = 0;
  final List<HourlySnapshot> snapshots = [];
  final List<String> milestones = [];

  int get totalProducerLevels {
    int s = 0;
    for (final v in producerLevels.values) s += v;
    return s;
  }

  double prestigeMult() =>
      1.0 + prestigeGlobalBonusFraction(prestigeUpgradeLevels);

  double dps() {
    double sum = 0;
    for (final p in producerCatalog) {
      sum += p.dpsAt(producerLevels[p.id] ?? 0);
    }
    return sum * prestigeMult();
  }

  int coinsAvailable({required bool useNewCurve}) => prestigeCoinsFor(
        totalGoldEarned: totalGoldEarned,
        currentGold: gold,
        producerLevelSum: totalProducerLevels,
        tapUpgradeSum: 0,
        prestigeCount: prestigeCount,
        prestigeUpgradeLevels: prestigeUpgradeLevels,
        useNewCurve: useNewCurve,
      );
}

class Simulator {
  final SimState state = SimState();

  /// Real-time seconds per tick (smaller = more precise, slower).
  final double tickSec;

  /// Toggle for A/B of the prestige coin formula.
  final bool useNewCurve;

  Simulator({this.tickSec = 30.0, this.useNewCurve = true});

  // Mirrors the cycle floor in game_provider: every 4 sec of sim time
  // pays 1 gold scaled by the prestige multiplier — i.e. a 0.25 gold/sec
  // baseline that bootstraps the run before any producer is bought.
  static const _cycleSec = 4.0;
  static const _baseRevenuePerCycle = 1.0;

  void tick() {
    // 1. Accrue gold (producer DPS + cycle floor).
    final dps = state.dps();
    final cycleFloor =
        (tickSec / _cycleSec) * _baseRevenuePerCycle * state.prestigeMult();
    final earned = dps * tickSec + cycleFloor;
    state.gold += earned;
    state.totalGoldEarned += earned;
    state.secondsElapsed += tickSec;

    // 2. Greedy purchasing — keep buying as long as the best option is
    // affordable. Buy in bursts of [maxAffordable] for the chosen producer
    // (matches what a player would do with the "max" button).
    while (_buyOneBatch()) {}

    // 3. Prestige if heuristic says yes.
    if (_shouldPrestige()) _doPrestige();

    // 4. Hourly snapshot.
    final h = state.secondsElapsed / 3600;
    if (state.snapshots.isEmpty ||
        h - state.snapshots.last.simHours >= 0.999) {
      state.snapshots.add(HourlySnapshot(
        simHours: h,
        gold: state.gold,
        totalGold: state.totalGoldEarned,
        dps: state.dps(),
        prestigeCount: state.prestigeCount,
        prestigeCoins: state.prestigeCoins,
        brandResearchLv:
            state.prestigeUpgradeLevels[prestigeOverallUpgradeId] ?? 0,
        totalProducerLevels: state.totalProducerLevels,
      ));
    }
  }

  bool _buyOneBatch() {
    // Find producer with best (cost-of-one) / (dps-gain-of-one).
    String? bestId;
    double bestScore = double.infinity;
    for (final p in producerCatalog) {
      final lv = state.producerLevels[p.id] ?? 0;
      final cost = p.costAt(lv);
      if (cost > state.gold) continue;
      final dpsGain = p.dpsAt(lv + 1) - p.dpsAt(lv);
      if (dpsGain <= 0) continue;
      final score = cost / dpsGain;
      if (score < bestScore) {
        bestScore = score;
        bestId = p.id;
      }
    }
    if (bestId == null) return false;
    final def = producerCatalog.firstWhere((p) => p.id == bestId);
    final lv = state.producerLevels[def.id] ?? 0;
    // Buy as many as affordable in one go (capped at +25 per batch so
    // we don't skip past a milestone in a single tick).
    final maxBuy = math.min(25, def.maxAffordable(state.gold, lv));
    final n = maxBuy.clamp(1, 25);
    final cost = def.costForNext(lv, n);
    if (cost > state.gold) return false;
    state.gold -= cost;
    state.producerLevels[def.id] = lv + n;
    return true;
  }

  bool _shouldPrestige() {
    // Heuristic: prestige when available coins would let us buy the next
    // brand-research level AND we already have at least 1 prestige
    // (first prestige fires as soon as coins > 0 to bootstrap).
    final coins = state.coinsAvailable(useNewCurve: useNewCurve);
    if (coins <= 0) return false;
    if (state.prestigeCount == 0) {
      // First prestige: do it once we've earned a meaningful chunk.
      return coins >= 5;
    }
    final overallLv =
        state.prestigeUpgradeLevels[prestigeOverallUpgradeId] ?? 0;
    final def = prestigeUpgradeById(prestigeOverallUpgradeId);
    final nextLevelCost =
        (def.baseCost * math.pow(def.growthRate, overallLv)).floor();
    // Prestige when we'd add at least 2× the cost of the next upgrade —
    // good rule of thumb to avoid resetting too eagerly.
    return coins >= nextLevelCost * 2;
  }

  void _doPrestige() {
    final coins = state.coinsAvailable(useNewCurve: useNewCurve);
    state.prestigeCoins += coins;
    state.prestigeCount++;
    final atH = (state.secondsElapsed / 3600).toStringAsFixed(1);
    state.milestones.add(
      'h$atH  prestige #${state.prestigeCount} +$coins coin (lifetime ${state.prestigeCoins})',
    );
    // Reset run state.
    state.gold = 0;
    state.totalGoldEarned = 0;
    state.producerLevels.clear();

    // Spend coins greedily on brand research (cheapest, infinite cap).
    final def = prestigeUpgradeById(prestigeOverallUpgradeId);
    while (true) {
      final lv = state.prestigeUpgradeLevels[def.id] ?? 0;
      final cost = (def.baseCost * math.pow(def.growthRate, lv)).floor();
      if (state.prestigeCoins < cost) break;
      state.prestigeCoins -= cost;
      state.prestigeUpgradeLevels[def.id] = lv + 1;
    }
  }

  void runHours(double hours) {
    final ticks = (hours * 3600 / tickSec).round();
    for (var i = 0; i < ticks; i++) {
      tick();
    }
  }
}

// ───────────────────────────────────────────────────────────────────────
//  Output helpers.
// ───────────────────────────────────────────────────────────────────────

String _sci(double v) {
  if (v == 0) return '0';
  if (v.abs() < 1000) return v.toStringAsFixed(2);
  return v.toStringAsExponential(2);
}

void _printSummary(String label, SimState s) {
  print('');
  print('═══ $label ═══');
  print('Time:              ${(s.secondsElapsed / 3600).toStringAsFixed(1)}h');
  print('Gold:              ${_sci(s.gold)}');
  print('Total earned:      ${_sci(s.totalGoldEarned)}');
  print('DPS:               ${_sci(s.dps())}');
  print('Prestige count:    ${s.prestigeCount}');
  print('Prestige coins:    ${s.prestigeCoins}');
  print('Brand research lv: ${s.prestigeUpgradeLevels[prestigeOverallUpgradeId] ?? 0}');
  print('Producer total lv: ${s.totalProducerLevels}');
  print('Prestige mult:     ×${s.prestigeMult().toStringAsFixed(2)}');
}

void _printMilestones(SimState s, {int max = 20}) {
  if (s.milestones.isEmpty) return;
  print('');
  print('Milestones (first $max):');
  for (final m in s.milestones.take(max)) {
    print('  $m');
  }
}

void _printHourlyTable(SimState s, {List<int>? hours}) {
  hours ??= const [1, 4, 8, 12, 24, 48, 72, 100];
  print('');
  print('Hourly snapshots:');
  print('  ${'h'.padLeft(4)}  ${'totalGold'.padLeft(10)}  ${'DPS'.padLeft(10)}  prestige  brandLv  prodLv');
  for (final h in hours) {
    final snap = s.snapshots.firstWhere(
      (x) => x.simHours >= h - 0.5,
      orElse: () => s.snapshots.isEmpty
          ? const HourlySnapshot(
              simHours: 0,
              gold: 0,
              totalGold: 0,
              dps: 0,
              prestigeCount: 0,
              prestigeCoins: 0,
              brandResearchLv: 0,
              totalProducerLevels: 0,
            )
          : s.snapshots.last,
    );
    print('  ${h.toString().padLeft(4)}  '
        '${_sci(snap.totalGold).padLeft(10)}  '
        '${_sci(snap.dps).padLeft(10)}  '
        '${snap.prestigeCount.toString().padLeft(8)}  '
        '${snap.brandResearchLv.toString().padLeft(7)}  '
        '${snap.totalProducerLevels}');
  }
}

// ───────────────────────────────────────────────────────────────────────
//  Tests / scenarios.
// ───────────────────────────────────────────────────────────────────────

void main() {
  test('baseline 24h with new prestige curve (§3.4)', () {
    final sim = Simulator(useNewCurve: true);
    sim.runHours(24);
    _printSummary('24h — new curve', sim.state);
    _printHourlyTable(sim.state, hours: const [1, 2, 4, 8, 12, 18, 24]);
    _printMilestones(sim.state, max: 10);
    expect(sim.state.secondsElapsed, closeTo(24 * 3600, 60));
  });

  test('baseline 100h with new prestige curve (§3.4)', () {
    final sim = Simulator(useNewCurve: true);
    sim.runHours(100);
    _printSummary('100h — new curve', sim.state);
    _printHourlyTable(sim.state);
    _printMilestones(sim.state, max: 20);
    expect(sim.state.secondsElapsed, closeTo(100 * 3600, 60));
  });

  test('A/B 24h: old sqrt curve vs new §3.4 curve', () {
    final old = Simulator(useNewCurve: false)..runHours(24);
    final neu = Simulator(useNewCurve: true)..runHours(24);
    _printSummary('24h — OLD (sqrt)', old.state);
    _printSummary('24h — NEW (§3.4)', neu.state);
    print('');
    print('Δ prestige count: ${neu.state.prestigeCount - old.state.prestigeCount}');
    print('Δ brand research: ${(neu.state.prestigeUpgradeLevels[prestigeOverallUpgradeId] ?? 0) - (old.state.prestigeUpgradeLevels[prestigeOverallUpgradeId] ?? 0)}');
    print('Δ total earned (final run): ${_sci(neu.state.totalGoldEarned - old.state.totalGoldEarned)}');
    expect(neu.state.prestigeCount, greaterThanOrEqualTo(old.state.prestigeCount));
  });
}
