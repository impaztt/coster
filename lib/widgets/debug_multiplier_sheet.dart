import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../models/multiplier_breakdown.dart';
import '../providers/game_provider.dart';

/// Dev-only diagnostic sheet showing the live tap/dps multiplier stack.
/// Triggered via long-press on the gold counter. After §3.1 v1, layers
/// are tagged multiplicative (MULT) or additive (ADD). Final stack is
/// `base × ∏MULT × (1 + ΣADD)`.
class DebugMultiplierSheet extends ConsumerWidget {
  const DebugMultiplierSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DebugMultiplierSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameProvider.notifier);
    ref.watch(gameProvider);
    final b = notifier.multiplierBreakdown;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            '디버그 — 멀티플라이어 스택',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            '§3.1 v1 — MULT는 곱셈, ADD는 가산 풀(합쳐서 1+Σ로 결합)',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _baseRow('TAP base', b.tapBase, 'DPS base', b.dpsBase),
          const Divider(height: 24),
          ...b.layers.map((l) => _LayerRow(layer: l)),
          const Divider(height: 24),
          _SummaryTotals(b: b),
          const SizedBox(height: 12),
          _baseRow(
            'TAP final',
            b.tapTotal,
            'DPS final',
            b.dpsTotal,
            bold: true,
          ),
          const SizedBox(height: 24),
          _ContributionTable(breakdown: b),
        ],
      ),
    );
  }

  Widget _baseRow(
    String l1,
    double v1,
    String l2,
    double v2, {
    bool bold = false,
  }) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      color: bold ? Colors.black : Colors.black87,
    );
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l1, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              Text(NumberFormatter.format(v1), style: style),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l2, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              Text(NumberFormatter.format(v2), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerRow extends StatelessWidget {
  final MultiplierLayer layer;
  const _LayerRow({required this.layer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
            decoration: BoxDecoration(
              color: layer.additive
                  ? Colors.purple.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: layer.additive
                    ? Colors.purple.shade200
                    : Colors.blue.shade200,
                width: 0.8,
              ),
            ),
            child: Text(
              layer.additive ? 'ADD' : 'MULT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: layer.additive
                    ? Colors.purple.shade800
                    : Colors.blue.shade800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              layer.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: _ValueBadge(
              value: layer.tap,
              additive: layer.additive,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: _ValueBadge(
              value: layer.dps,
              additive: layer.additive,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueBadge extends StatelessWidget {
  final double value;
  final bool additive;
  const _ValueBadge({required this.value, required this.additive});

  @override
  Widget build(BuildContext context) {
    final isNoop = (value - 1.0).abs() < 1e-9;
    final isHot = value >= 10.0;
    final isVeryHot = value >= 100.0;
    final color = isNoop
        ? Colors.black26
        : isVeryHot
            ? Colors.red.shade700
            : isHot
                ? Colors.orange.shade800
                : additive
                    ? Colors.purple.shade700
                    : Colors.green.shade700;
    final label = additive
        ? (isNoop ? '+0%' : '+${((value - 1.0) * 100).toStringAsFixed(1)}%')
        : '×${NumberFormatter.format(value)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SummaryTotals extends StatelessWidget {
  final MultiplierBreakdown b;
  const _SummaryTotals({required this.b});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('MULT × (TAP)', '×${NumberFormatter.format(b.multiplicativeTap)}',
            '(DPS)', '×${NumberFormatter.format(b.multiplicativeDps)}'),
        const SizedBox(height: 2),
        _row(
            'ADD pool (TAP)',
            '+${(b.additiveTapFraction * 100).toStringAsFixed(1)}%',
            '(DPS)',
            '+${(b.additiveDpsFraction * 100).toStringAsFixed(1)}%'),
        const SizedBox(height: 6),
        _row(
          'TOTAL × (TAP)',
          '×${NumberFormatter.format(b.totalTapMult)}',
          '(DPS)',
          '×${NumberFormatter.format(b.totalDpsMult)}',
          bold: true,
        ),
      ],
    );
  }

  Widget _row(String l1, String v1, String l2, String v2, {bool bold = false}) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(l1, style: TextStyle(fontSize: 11, color: bold ? Colors.black : Colors.black54)),
        ),
        Expanded(
          flex: 3,
          child: Text(v1, style: style, textAlign: TextAlign.right),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(l2, style: TextStyle(fontSize: 11, color: bold ? Colors.black : Colors.black54)),
        ),
        Expanded(
          flex: 3,
          child: Text(v2, style: style, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _ContributionTable extends StatelessWidget {
  final MultiplierBreakdown breakdown;
  const _ContributionTable({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    // For multiplicative layers, contribution = ln(value) / total ln.
    // For additive layers, contribution = (value-1) / additive pool size.
    final multLayers = breakdown.layers.where((l) => !l.additive).toList();
    final addLayers = breakdown.layers.where((l) => l.additive).toList();
    final totalTapLog = _logTotal(multLayers.map((l) => l.tap));
    final totalDpsLog = _logTotal(multLayers.map((l) => l.dps));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '기여도 분석',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'MULT 레이어: log-scale 비중. ADD 레이어: 가산 풀 내 비중.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        ...multLayers.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text(l.name, style: const TextStyle(fontSize: 11))),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TAP ${_logPct(l.tap, totalTapLog).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'DPS ${_logPct(l.dps, totalDpsLog).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            )),
        if (addLayers.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('— ADD pool —', style: TextStyle(fontSize: 10, color: Colors.black45)),
          ...addLayers.map((l) {
            final tapShare = breakdown.additiveTapFraction > 0
                ? (l.tap - 1.0) / breakdown.additiveTapFraction * 100
                : 0;
            final dpsShare = breakdown.additiveDpsFraction > 0
                ? (l.dps - 1.0) / breakdown.additiveDpsFraction * 100
                : 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text(l.name, style: const TextStyle(fontSize: 11))),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TAP ${tapShare.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'DPS ${dpsShare.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  static double _logTotal(Iterable<double> mults) {
    double s = 0;
    for (final m in mults) {
      if (m > 1) s += _ln(m);
    }
    return s;
  }

  static double _logPct(double m, double total) {
    if (total <= 0 || m <= 1) return 0;
    return _ln(m) / total * 100;
  }

  static double _ln(double x) {
    if (x <= 0) return 0;
    const ln10 = 2.302585092994046;
    return _log10(x) * ln10;
  }

  static double _log10(double x) {
    if (x <= 0) return 0;
    var v = x;
    var e = 0;
    while (v >= 10) {
      v /= 10;
      e++;
    }
    while (v < 1) {
      v *= 10;
      e--;
    }
    final y = v - 1;
    final ln = y -
        y * y / 2 +
        y * y * y / 3 -
        y * y * y * y / 4 +
        y * y * y * y * y / 5 -
        y * y * y * y * y * y / 6;
    const ln10 = 2.302585092994046;
    return e + ln / ln10;
  }
}
