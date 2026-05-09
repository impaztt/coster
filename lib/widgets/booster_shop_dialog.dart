import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/game_provider.dart';
import '../services/ad_service.dart';

class BoosterShopDialog extends ConsumerWidget {
  const BoosterShopDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.deepCoral, size: 22),
                const SizedBox(width: 6),
                const Text(
                  '부스터 상점',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Icon(Icons.diamond, color: Colors.teal.shade700, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${game.essence}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.teal.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final offer in boosterOffers) ...[
              _OfferRow(
                offer: offer,
                canAffordEssence: game.essence >= offer.essenceCost,
                adsRemoved: notifier.adsRemoved,
                onBuyEssence: () {
                  final ok = notifier.buyBoosterWithEssence(offer);
                  if (!ok) _toast(context, '정수가 부족해요');
                },
                onWatchAd: () async {
                  // 광고 제거 IAP 보유자는 즉시 지급 (광고 시청 단계 스킵).
                  if (notifier.adsRemoved) {
                    notifier.grantAdBooster(offer);
                    _toast(context, '광고 제거 혜택으로 즉시 지급됐어요');
                    return;
                  }
                  final earned = await AdService.instance
                      .showRewarded(trigger: 'booster_shop');
                  if (!context.mounted) return;
                  if (earned) {
                    notifier.grantAdBooster(offer);
                    _toast(context, '광고 시청 완료 — 부스터가 적용됐어요');
                  } else {
                    _toast(context, '광고를 끝까지 시청해야 보상이 지급돼요');
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            Text(
              '같은 부스터를 다시 사면 남은 시간이 연장돼요.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  final BoosterOffer offer;
  final bool canAffordEssence;
  final bool adsRemoved;
  final VoidCallback onBuyEssence;
  final VoidCallback onWatchAd;

  const _OfferRow({
    required this.offer,
    required this.canAffordEssence,
    required this.adsRemoved,
    required this.onBuyEssence,
    required this.onWatchAd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.coral.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            offer.subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BuyButton(
                  label: '정수 ${offer.essenceCost}',
                  icon: Icons.diamond,
                  enabled: canAffordEssence,
                  filled: true,
                  onTap: onBuyEssence,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BuyButton(
                  label: adsRemoved ? '광고 제거 보상' : '광고 시청',
                  icon: adsRemoved ? Icons.flash_on : Icons.play_circle_fill,
                  enabled: true,
                  filled: false,
                  onTap: onWatchAd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;
  const _BuyButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? (enabled ? AppColors.coral : Colors.grey.shade300)
        : Colors.transparent;
    final fg = filled
        ? (enabled ? Colors.white : Colors.grey.shade600)
        : AppColors.deepCoral;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(
                    color: AppColors.coral.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
