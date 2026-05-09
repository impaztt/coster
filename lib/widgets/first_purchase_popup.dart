import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/game_provider.dart';
import '../services/iap_service.dart';

/// One-shot popup that surfaces the first-purchase package whenever the
/// player meets all three conditions:
///   1. Game has been launched at least once
///   2. Less than 24 hours have passed since the first launch
///   3. The popup hasn't been shown yet AND the package isn't already owned
///
/// We delegate the trigger check to GameNotifier so the rules stay in one
/// place and the widget only owns presentation.
class FirstPurchasePopupHost extends ConsumerStatefulWidget {
  final Widget child;
  const FirstPurchasePopupHost({super.key, required this.child});

  @override
  ConsumerState<FirstPurchasePopupHost> createState() =>
      _FirstPurchasePopupHostState();
}

class _FirstPurchasePopupHostState
    extends ConsumerState<FirstPurchasePopupHost> {
  bool _checked = false;
  Timer? _popupTimer;

  @override
  void dispose() {
    _popupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Run the gate exactly once per app session, after the first frame so
    // we can reliably show a dialog from build context.
    if (!_checked) {
      _checked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _popupTimer = Timer(const Duration(seconds: 4), () async {
          if (!mounted) return;
          final notifier = ref.read(gameProvider.notifier);
          if (!notifier.firstPurchasePopupEligible) return;
          notifier.markFirstPurchasePopupShown();
          await _showPopup();
        });
      });
    }
    return widget.child;
  }

  Future<void> _showPopup() async {
    if (!mounted) return;
    final purchase = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _FirstPurchaseDialog(),
    );
    if (purchase == true) {
      // Best-effort: kick off the store flow. The IapService listener will
      // grant the package on success.
      unawaited(IapService.instance.buy(
        premiumFirstPurchaseProductId,
        consumable: false,
      ));
    }
  }
}

class _FirstPurchaseDialog extends StatelessWidget {
  const _FirstPurchaseDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.card_giftcard, color: AppColors.deepCoral, size: 22),
                SizedBox(width: 6),
                Text(
                  '첫 결제 패키지',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '계정당 단 한 번, ₩1,100',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),
            const _BenefitLine('정수 500'),
            const _BenefitLine('SR 확정 소환권 1매'),
            const _BenefitLine('24시간 한정 노출'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('나중에'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.coral,
                    ),
                    child: const Text('₩1,100 결제'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitLine extends StatelessWidget {
  final String label;
  const _BenefitLine(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.deepCoral, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
