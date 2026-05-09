import 'package:flutter/material.dart';

import '../models/stock_market.dart';

/// Korean-style candlestick chart (red = up, blue = down) with a volume
/// histogram and optional reference lines. Renders the most recent
/// [candles] left → right plus a [forming] candle at the right edge.
class CandleChart extends StatelessWidget {
  final List<Candle> candles;
  final Candle? forming;
  final double? avgCost;
  final double? intrinsicPrice;
  final double height;

  const CandleChart({
    super.key,
    required this.candles,
    this.forming,
    this.avgCost,
    this.intrinsicPrice,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CandleChartPainter(
          candles: candles,
          forming: forming,
          avgCost: avgCost,
          intrinsicPrice: intrinsicPrice,
        ),
      ),
    );
  }
}

class _CandleChartPainter extends CustomPainter {
  static const Color _upColor = Color(0xFFD32F2F); // 빨강 = 상승 (한국식)
  static const Color _downColor = Color(0xFF1976D2); // 파랑 = 하락
  static const Color _gridColor = Color(0x1F000000);
  static const Color _avgLineColor = Color(0xFFEC407A);
  static const Color _intrinsicLineColor = Color(0x66607D8B);
  static const int _visibleCandleSlots = 42;

  final List<Candle> candles;
  final Candle? forming;
  final double? avgCost;
  final double? intrinsicPrice;

  _CandleChartPainter({
    required this.candles,
    required this.forming,
    required this.avgCost,
    required this.intrinsicPrice,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allCandles = <Candle>[
      ...candles,
      if (forming != null) forming!,
    ];
    if (allCandles.isEmpty) {
      _drawEmpty(canvas, size);
      return;
    }
    final visible = allCandles.length > _visibleCandleSlots
        ? allCandles.sublist(allCandles.length - _visibleCandleSlots)
        : allCandles;

    // Reserve space at the bottom for the volume histogram.
    final priceTop = 4.0;
    final priceBottom = size.height * 0.72;
    final volumeTop = size.height * 0.78;
    final volumeBottom = size.height - 14;

    // Auto-zoom to the visible candles only. Reference lines are drawn when
    // they are inside this viewport, but they no longer squash the candles.
    final range = _priceViewport(visible);
    final pMin = range.$1;
    final pMax = range.$2;
    final priceSpan = pMax - pMin;

    // Volume range.
    var vMax = 0.0;
    for (final c in visible) {
      if (c.volume > vMax) vMax = c.volume;
    }
    if (vMax <= 0) vMax = 1;

    // Layout: leave 56px on the right for price labels.
    const labelGap = 56.0;
    final plotLeft = 4.0;
    final plotRight = size.width - labelGap;
    final plotWidth = plotRight - plotLeft;
    if (plotWidth <= 0) return;

    // Fewer visible slots keeps 30-second candles readable on phones.
    const slotCount = _visibleCandleSlots;
    final slotWidth = plotWidth / slotCount;
    final candleWidth = (slotWidth * 0.76).clamp(2.0, 14.0);

    // Grid + price labels (5 horizontal lines).
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final tp = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );
    for (var i = 0; i <= 4; i++) {
      final yFrac = i / 4;
      final y = priceTop + yFrac * (priceBottom - priceTop);
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(plotRight, y),
        gridPaint,
      );
      final priceAtY = pMax - yFrac * priceSpan;
      tp.text = TextSpan(
        text: _fmt(priceAtY),
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      tp.layout(maxWidth: labelGap - 4);
      tp.paint(canvas, Offset(plotRight + 4, y - tp.height / 2));
    }

    double yForPrice(double p) =>
        priceTop + (1 - (p - pMin) / priceSpan) * (priceBottom - priceTop);

    // Reference lines (intrinsic, then avg) — drawn before candles so they
    // sit underneath the wicks visually.
    if (_insideViewport(intrinsicPrice, pMin, pMax)) {
      _drawDashedLine(
        canvas,
        Offset(plotLeft, yForPrice(intrinsicPrice!)),
        Offset(plotRight, yForPrice(intrinsicPrice!)),
        _intrinsicLineColor,
        dash: 4,
        gap: 4,
      );
    }
    if (_insideViewport(avgCost, pMin, pMax)) {
      _drawDashedLine(
        canvas,
        Offset(plotLeft, yForPrice(avgCost!)),
        Offset(plotRight, yForPrice(avgCost!)),
        _avgLineColor,
        dash: 6,
        gap: 4,
        strokeWidth: 1.4,
      );
      tp.text = TextSpan(
        text: '평단 ${_fmt(avgCost!)}',
        style: const TextStyle(
          color: _avgLineColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      );
      tp.layout(maxWidth: labelGap + 40);
      tp.paint(canvas, Offset(plotLeft + 4, yForPrice(avgCost!) - 12));
    }

    // Candles — right-aligned: latest is the rightmost slot.
    final startSlot = slotCount - visible.length;
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final slot = startSlot + i;
      final cx = plotLeft + slot * slotWidth + slotWidth / 2;
      final isUp = c.close >= c.open;
      final color = isUp ? _upColor : _downColor;
      // Wick.
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(cx, yForPrice(c.high)),
        Offset(cx, yForPrice(c.low)),
        wickPaint,
      );
      // Body.
      final bodyTop = yForPrice(isUp ? c.close : c.open);
      final bodyBottom = yForPrice(isUp ? c.open : c.close);
      final body = Rect.fromLTRB(
        cx - candleWidth / 2,
        bodyTop,
        cx + candleWidth / 2,
        bodyBottom < bodyTop + 2 ? bodyTop + 2 : bodyBottom,
      );
      final bodyPaint = Paint()..color = color;
      // Up candles in Korean charts are typically drawn as filled boxes.
      // Down candles are also filled — same convention used by KRX clients.
      canvas.drawRect(body, bodyPaint);

      // Volume bar.
      final vH = (c.volume / vMax) * (volumeBottom - volumeTop);
      final vTop = volumeBottom - vH;
      final volPaint = Paint()..color = color.withValues(alpha: 0.55);
      canvas.drawRect(
        Rect.fromLTRB(
          cx - candleWidth / 2,
          vTop,
          cx + candleWidth / 2,
          volumeBottom,
        ),
        volPaint,
      );
    }

    final latest = visible.last.close;
    _drawCurrentPriceMarker(
      canvas,
      y: yForPrice(latest),
      plotLeft: plotLeft,
      plotRight: plotRight,
      labelGap: labelGap,
      label: _fmt(latest),
      color: visible.last.close >= visible.last.open ? _upColor : _downColor,
    );

    // Bottom and right axis lines.
    final axisPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(plotLeft, priceBottom),
      Offset(plotRight, priceBottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotLeft, volumeBottom),
      Offset(plotRight, volumeBottom),
      axisPaint,
    );

    // "거래량" label tucked above the histogram.
    tp.text = const TextSpan(
      text: '거래량',
      style: TextStyle(
        color: Colors.black38,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    );
    tp.layout(maxWidth: 60);
    tp.paint(canvas, Offset(plotLeft + 2, volumeTop - 12));
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: '데이터 수집 중...',
        style: TextStyle(color: Colors.black38, fontSize: 12),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color, {
    double dash = 4,
    double gap = 4,
    double strokeWidth = 1,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    final total = (b - a).distance;
    final dx = (b.dx - a.dx) / total;
    final dy = (b.dy - a.dy) / total;
    var d = 0.0;
    var on = true;
    while (d < total) {
      final segLen = on ? dash : gap;
      final endD = (d + segLen).clamp(0, total).toDouble();
      if (on) {
        canvas.drawLine(
          Offset(a.dx + dx * d, a.dy + dy * d),
          Offset(a.dx + dx * endD, a.dy + dy * endD),
          paint,
        );
      }
      d = endD;
      on = !on;
    }
  }

  (double, double) _priceViewport(List<Candle> visible) {
    var pMin = double.infinity;
    var pMax = -double.infinity;
    for (final c in visible) {
      if (c.low < pMin) pMin = c.low;
      if (c.high > pMax) pMax = c.high;
    }

    final last = visible.last.close <= 0 ? 1.0 : visible.last.close;
    if (!pMin.isFinite || !pMax.isFinite || pMin <= 0 || pMax <= 0) {
      pMin = last * 0.9925;
      pMax = last * 1.0075;
    }

    var span = pMax - pMin;
    final minSpan = last * 0.012;
    if (span < minSpan) {
      final center = (pMin + pMax) * 0.5;
      pMin = center - minSpan * 0.5;
      pMax = center + minSpan * 0.5;
      span = pMax - pMin;
    }

    final pad = (span * 0.12).clamp(last * 0.002, last * 0.05).toDouble();
    pMin = (pMin - pad).clamp(last * 0.001, double.infinity).toDouble();
    pMax += pad;
    if (pMax <= pMin) pMax = pMin + last * 0.01;
    return (pMin, pMax);
  }

  bool _insideViewport(double? value, double pMin, double pMax) {
    if (value == null || value <= 0) return false;
    return value >= pMin && value <= pMax;
  }

  void _drawCurrentPriceMarker(
    Canvas canvas, {
    required double y,
    required double plotLeft,
    required double plotRight,
    required double labelGap,
    required String label,
    required Color color,
  }) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), linePaint);

    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(plotRight + 3, y - 8, labelGap - 6, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      labelRect,
      Paint()..color = color.withValues(alpha: 0.13),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: labelGap - 10);
    tp.paint(canvas, Offset(plotRight + labelGap - tp.width - 6, y - 6));
  }

  String _fmt(double v) {
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }

  @override
  bool shouldRepaint(covariant _CandleChartPainter old) {
    return old.candles != candles ||
        old.forming != forming ||
        old.avgCost != avgCost ||
        old.intrinsicPrice != intrinsicPrice;
  }
}
