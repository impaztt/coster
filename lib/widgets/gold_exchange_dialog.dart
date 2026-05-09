import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../providers/game_provider.dart';

/// "환금소" — spend essence to instantly receive gold. Two product lines:
/// DPS-time conversion (auto-scales) and fixed amounts (fades out late).
class GoldExchangeDialog extends ConsumerWidget {
  const GoldExchangeDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);

    final dpsOffers = goldExchangeOffers
        .where((o) => o.kind == GoldExchangeKind.dpsTime)
        .toList();
    final fixedOffers = goldExchangeOffers
        .where((o) => o.kind == GoldExchangeKind.fixed)
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(essence: game.essence),
              const SizedBox(height: 8),
              _UsageBar(
                dailyUsed: game.goldExchangeDailyUsed,
                dailyLimit: goldExchangeDailyLimit,
                runUsed: game.goldExchangePrestigeUsed,
                runLimit: goldExchangePrestigeLimit,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const _SectionLabel(
                      icon: Icons.timelapse,
                      label: '환금술 (시간 충전)',
                    ),
                    const SizedBox(height: 6),
                    for (final offer in dpsOffers) ...[
                      _OfferTile(
                        offer: offer,
                        previewGold:
                            notifier.previewGoldExchangeYield(offer),
                        canAfford: game.essence >= offer.essenceCost,
                        eightHourLocked: offer.id == 'dps_8h' &&
                            game.goldExchangeEightHourUsedToday,
                        atDailyCap: game.goldExchangeDailyUsed >=
                            goldExchangeDailyLimit,
                        atRunCap: game.goldExchangePrestigeUsed >=
                            goldExchangePrestigeLimit,
                        onTap: () => _attemptPurchase(context, ref, offer),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (!notifier.goldExchangeFixedHidden) ...[
                      const SizedBox(height: 6),
                      const _SectionLabel(
                        icon: Icons.savings,
                        label: '긴급 자금 보따리',
                      ),
                      const SizedBox(height: 6),
                      for (final offer in fixedOffers) ...[
                        _OfferTile(
                          offer: offer,
                          previewGold:
                              notifier.previewGoldExchangeYield(offer),
                          canAfford: game.essence >= offer.essenceCost,
                          eightHourLocked: false,
                          atDailyCap: game.goldExchangeDailyUsed >=
                              goldExchangeDailyLimit,
                          atRunCap: game.goldExchangePrestigeUsed >=
                              goldExchangePrestigeLimit,
                          onTap: () => _attemptPurchase(context, ref, offer),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '환금한 골드는 환생 코인 계산에서 제외돼요. 강화/주식에 쓰면 그때부터 정상 반영됩니다.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
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
      ),
    );
  }

  Future<void> _attemptPurchase(
    BuildContext context,
    WidgetRef ref,
    GoldExchangeOffer offer,
  ) async {
    final notifier = ref.read(gameProvider.notifier);
    final preview = notifier.previewGoldExchangeYield(offer);
    final game = ref.read(gameProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(offer.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('소비 정수: ${offer.essenceCost}'),
            const SizedBox(height: 4),
            Text('획득 골드: +${NumberFormatter.format(preview)}'),
            const SizedBox(height: 8),
            Text(
              '오늘 환전: ${game.goldExchangeDailyUsed} / $goldExchangeDailyLimit '
              '→ ${game.goldExchangeDailyUsed + 1} / $goldExchangeDailyLimit',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '환금 골드는 환생 코인에 즉시 반영되지 않으며, '
              '강화/주식 등에 사용한 만큼만 코인 계산에 들어갑니다.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('환전'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final result = notifier.buyGoldExchange(offer.id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? '+${NumberFormatter.format(result.goldGranted)} 골드 환전 완료'
              : _failureText(result.reason),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _failureText(GoldExchangeFailureReason r) => switch (r) {
        GoldExchangeFailureReason.notEnoughEssence => '정수가 부족해요',
        GoldExchangeFailureReason.dailyCapReached =>
          '오늘은 환전 횟수를 모두 사용했어요',
        GoldExchangeFailureReason.prestigeCapReached =>
          '이번 회차 환전 횟수를 모두 사용했어요. 환생하면 초기화됩니다',
        GoldExchangeFailureReason.perOfferCapReached =>
          '이 슬롯은 하루 1회만 가능합니다. 내일 다시 시도해 주세요',
        GoldExchangeFailureReason.none => '',
      };
}

class _Header extends StatelessWidget {
  final int essence;
  const _Header({required this.essence});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.currency_exchange,
            color: AppColors.deepCoral, size: 22),
        const SizedBox(width: 6),
        const Text(
          '환금소',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        Icon(Icons.diamond, color: Colors.teal.shade700, size: 18),
        const SizedBox(width: 4),
        Text(
          '$essence',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.teal.shade700,
          ),
        ),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  final int dailyUsed;
  final int dailyLimit;
  final int runUsed;
  final int runLimit;
  const _UsageBar({
    required this.dailyUsed,
    required this.dailyLimit,
    required this.runUsed,
    required this.runLimit,
  });

  @override
  Widget build(BuildContext context) {
    final base = Colors.black.withValues(alpha: 0.6);
    return Row(
      children: [
        Icon(Icons.calendar_today, size: 12, color: base),
        const SizedBox(width: 4),
        Text(
          '오늘 $dailyUsed / $dailyLimit',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: base),
        ),
        const SizedBox(width: 12),
        Icon(Icons.refresh, size: 12, color: base),
        const SizedBox(width: 4),
        Text(
          '회차 $runUsed / $runLimit',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: base),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.deepCoral),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _OfferTile extends StatelessWidget {
  final GoldExchangeOffer offer;
  final double previewGold;
  final bool canAfford;
  final bool eightHourLocked;
  final bool atDailyCap;
  final bool atRunCap;
  final VoidCallback onTap;

  const _OfferTile({
    required this.offer,
    required this.previewGold,
    required this.canAfford,
    required this.eightHourLocked,
    required this.atDailyCap,
    required this.atRunCap,
    required this.onTap,
  });

  bool get _disabled =>
      !canAfford || eightHourLocked || atDailyCap || atRunCap;

  String? get _badge {
    if (eightHourLocked) return '내일 다시 가능';
    if (atRunCap) return '회차 캡 도달';
    if (atDailyCap) return '오늘 캡 도달';
    if (!canAfford) return '정수 부족';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.coral.withValues(alpha: _disabled ? 0.15 : 0.4);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          offer.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _disabled
                                ? Colors.black.withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.85),
                          ),
                        ),
                        if (offer.id == 'dps_8h') ...[
                          const SizedBox(width: 4),
                          const Text(
                            '★',
                            style: TextStyle(
                              color: Color(0xFFFFB300),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offer.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '+${NumberFormatter.format(previewGold)} 골드',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _disabled
                            ? Colors.grey.shade500
                            : AppColors.deepCoral,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _disabled
                          ? Colors.grey.shade300
                          : AppColors.coral,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.diamond,
                          size: 12,
                          color: _disabled
                              ? Colors.grey.shade600
                              : Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${offer.essenceCost}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _disabled
                                ? Colors.grey.shade600
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_badge != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _badge!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
