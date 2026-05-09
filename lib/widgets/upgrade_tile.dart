import 'package:flutter/material.dart';

import '../core/number_format.dart';
import '../core/theme.dart';

class UpgradeTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String name;
  final String description;
  final int level;
  final double cost;
  final int buyCount;
  final String gainLabel;
  final String? milestoneLabel;
  final bool affordable;
  final VoidCallback onBuy;

  const UpgradeTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.name,
    required this.description,
    required this.level,
    required this.cost,
    required this.buyCount,
    required this.gainLabel,
    required this.affordable,
    required this.onBuy,
    this.milestoneLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: affordable
              ? accent.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Lv $level',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 5),
                  _GainPill(
                    label: gainLabel,
                    color: const Color(0xFF00695C),
                  ),
                  if (milestoneLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      milestoneLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _BuyButton(
              cost: cost,
              buyCount: buyCount,
              affordable: affordable,
              onBuy: onBuy,
            ),
          ],
        ),
      ),
    );
  }
}

class _GainPill extends StatelessWidget {
  final String label;
  final Color color;

  const _GainPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  final double cost;
  final int buyCount;
  final bool affordable;
  final VoidCallback onBuy;

  const _BuyButton({
    required this.cost,
    required this.buyCount,
    required this.affordable,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final bg = affordable ? AppColors.coral : Colors.grey.shade300;
    final fg = affordable ? Colors.white : Colors.grey.shade600;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: affordable ? onBuy : null,
        child: Container(
          width: 86,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'x$buyCount',
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monetization_on, color: fg, size: 16),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      NumberFormatter.format(cost),
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
