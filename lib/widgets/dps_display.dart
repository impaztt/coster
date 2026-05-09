import 'package:flutter/material.dart';
import '../core/number_format.dart';
import '../core/theme.dart';

class DpsDisplay extends StatelessWidget {
  final double dps;
  const DpsDisplay({super.key, required this.dps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.mint.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.mint.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 18, color: Color(0xFF00897B)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${NumberFormatter.formatPrecise(dps)}/초',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF00695C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
