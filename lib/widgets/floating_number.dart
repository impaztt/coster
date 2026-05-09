import 'package:flutter/material.dart';

import '../core/number_format.dart';
import '../core/theme.dart';

class FloatingNumberData {
  final int id;
  final Offset origin;
  final double amount;
  final bool isCrit;
  FloatingNumberData({
    required this.id,
    required this.origin,
    required this.amount,
    this.isCrit = false,
  });
}

class FloatingNumberLayer extends StatelessWidget {
  final List<FloatingNumberData> items;
  final void Function(int id) onDone;

  const FloatingNumberLayer({
    super.key,
    required this.items,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final data in items)
            _FloatingNumber(
              key: ValueKey(data.id),
              data: data,
              onDone: () => onDone(data.id),
            ),
        ],
      ),
    );
  }
}

class _FloatingNumber extends StatefulWidget {
  final FloatingNumberData data;
  final VoidCallback onDone;

  const _FloatingNumber({
    super.key,
    required this.data,
    required this.onDone,
  });

  @override
  State<_FloatingNumber> createState() => _FloatingNumberState();
}

class _FloatingNumberState extends State<_FloatingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final isCrit = widget.data.isCrit;
        final t = _c.value;
        final dy = -80.0 * t;
        final opacity = (1.0 - t).clamp(0.0, 1.0);
        // Crit numbers are bigger, pop in with a brief scale bounce, and use
        // the warm yellow accent instead of coral for instant recognition.
        final scale = isCrit
            ? (t < 0.15 ? 0.6 + (t / 0.15) * 0.9 : 1.5 - t * 0.3)
            : 1.0;
        final width = isCrit ? 140.0 : 80.0;
        return Positioned(
          left: widget.data.origin.dx - width / 2,
          top: widget.data.origin.dy + dy - 20,
          width: width,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: Text(
                  isCrit
                      ? 'CRIT! +${NumberFormatter.format(widget.data.amount)}'
                      : '+${NumberFormatter.format(widget.data.amount)}',
                  style: TextStyle(
                    fontSize: isCrit ? 26 : 22,
                    fontWeight: FontWeight.w900,
                    color: isCrit
                        ? const Color(0xFFB26A00)
                        : AppColors.deepCoral,
                    shadows: const [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 4,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
