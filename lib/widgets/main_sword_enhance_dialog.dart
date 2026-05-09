import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../data/main_sword_enhancement.dart';
import '../data/main_sword_evolution.dart';
import '../providers/game_provider.dart';
import 'main_sword_widget.dart';

class MainSwordEnhanceDialog extends ConsumerStatefulWidget {
  const MainSwordEnhanceDialog({super.key});

  @override
  ConsumerState<MainSwordEnhanceDialog> createState() =>
      _MainSwordEnhanceDialogState();
}

class _MainSwordEnhanceDialogState
    extends ConsumerState<MainSwordEnhanceDialog> {
  MainSwordEnhanceCurrency _currency = MainSwordEnhanceCurrency.gold;
  MainSwordBoostLevel _boost = MainSwordBoostLevel.none;
  bool _useProtection = false;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);
    final stage = game.mainSwordStage;
    final atMax = stage >= mainSwordEnhanceMaxStage;
    final targetStage = atMax ? stage : stage + 1;
    final cost = mainSwordEnhanceCost(targetStage);
    final tierCurrent = mainSwordTierFor(stage);
    final tierNext = mainSwordTierFor(targetStage);
    final selected = _planFor(cost, _currency, _boost, _useProtection);
    final canAfford = game.gold >= selected.goldCost &&
        game.essence >= selected.essenceCost &&
        !atMax;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 720, maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                name: game.mainSwordName ?? '이름 없는 검',
                stage: stage,
                tierLabel: tierCurrent.name,
                essence: game.essence,
              ),
              const SizedBox(height: 12),
              _StagePreview(stage: stage, targetStage: targetStage),
              const SizedBox(height: 10),
              if (atMax)
                const _MaxedPanel()
              else ...[
                _NextStageBar(
                    targetStage: targetStage, tierName: tierNext.name),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _OptionPanel(
                        boost: _boost,
                        useProtection: _useProtection,
                        selectedCurrency: _currency,
                        onBoostChanged: (value) =>
                            setState(() => _boost = value),
                        onProtectionChanged: (value) =>
                            setState(() => _useProtection = value),
                      ),
                      const SizedBox(height: 10),
                      _ModeGrid(
                        selected: _currency,
                        plans: {
                          for (final currency
                              in MainSwordEnhanceCurrency.values)
                            currency: _planFor(
                                cost, currency, _boost, _useProtection),
                        },
                        gold: game.gold,
                        essence: game.essence,
                        onSelected: (value) =>
                            setState(() => _currency = value),
                      ),
                      const SizedBox(height: 10),
                      _AttemptSummary(
                        plan: selected,
                        canAfford: canAfford,
                        onTry: () => _attempt(notifier),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
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

  _EnhancePlan _planFor(
    MainSwordEnhanceCost cost,
    MainSwordEnhanceCurrency currency,
    MainSwordBoostLevel boost,
    bool useProtection,
  ) {
    final boostCost = boost.essenceCost;
    final boostBonus = boost.successBonus;
    return switch (currency) {
      MainSwordEnhanceCurrency.gold => _EnhancePlan(
          currency: currency,
          title: '골드 강화',
          subtitle: '가장 기본적인 시도',
          icon: Icons.paid,
          color: AppColors.deepCoral,
          goldCost: cost.goldCost,
          essenceCost:
              boostCost + (useProtection ? mainSwordProtectionEssenceCost : 0),
          successRate: (cost.goldSuccessBase + boostBonus).clamp(0.0, 1.0),
          failureLabel:
              useProtection ? '실패 시 단계 유지' : '실패 시 -${cost.penaltyOnFail}강',
          protectedOnFail: useProtection,
        ),
      MainSwordEnhanceCurrency.essence => _EnhancePlan(
          currency: currency,
          title: '정수 강화',
          subtitle: '실패해도 단계 유지',
          icon: Icons.diamond,
          color: const Color(0xFF7C4DFF),
          goldCost: 0,
          essenceCost: cost.essenceCost + boostCost,
          successRate: (cost.essenceSuccessBase + boostBonus).clamp(0.0, 1.0),
          failureLabel: '실패 시 단계 유지',
          protectedOnFail: true,
        ),
      MainSwordEnhanceCurrency.hybrid => _EnhancePlan(
          currency: currency,
          title: '하이브리드',
          subtitle: '골드와 정수 모두 사용',
          icon: Icons.auto_awesome,
          color: const Color(0xFFFFB300),
          goldCost: cost.goldCost * mainSwordHybridGoldMultiplier,
          essenceCost:
              (cost.essenceCost * mainSwordHybridEssenceMultiplier).round() +
                  boostCost,
          successRate:
              (cost.goldSuccessBase + mainSwordHybridSuccessBonus + boostBonus)
                  .clamp(0.0, 1.0),
          failureLabel: '실패 시 단계 유지',
          protectedOnFail: true,
        ),
    };
  }

  Future<void> _attempt(GameNotifier notifier) async {
    final result = notifier.attemptMainSwordEnhance(
      currency: _currency,
      boostLevel: _boost,
      useProtection: _useProtection,
    );
    if (!mounted) return;
    if (!result.ok) {
      _toast(_failureLabel(result.reason));
      return;
    }
    if (result.success) {
      _toast('성공! +${result.newStage}강 진입');
    } else if (result.penaltyApplied > 0) {
      _toast('실패: ${result.penaltyApplied}강 하락 (+${result.newStage})');
    } else {
      _toast('실패: 단계 유지');
    }
    setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _failureLabel(MainSwordEnhanceFailure reason) => switch (reason) {
        MainSwordEnhanceFailure.notEnoughGold => '골드가 부족해요',
        MainSwordEnhanceFailure.notEnoughEssence => '정수가 부족해요',
        MainSwordEnhanceFailure.alreadyMaxed => '이미 최대 단계입니다',
        MainSwordEnhanceFailure.rolledFailure ||
        MainSwordEnhanceFailure.none =>
          '',
      };
}

class _EnhancePlan {
  final MainSwordEnhanceCurrency currency;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double goldCost;
  final int essenceCost;
  final double successRate;
  final String failureLabel;
  final bool protectedOnFail;

  const _EnhancePlan({
    required this.currency,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.goldCost,
    required this.essenceCost,
    required this.successRate,
    required this.failureLabel,
    required this.protectedOnFail,
  });
}

class _Header extends StatelessWidget {
  final String name;
  final int stage;
  final String tierLabel;
  final int essence;

  const _Header({
    required this.name,
    required this.stage,
    required this.tierLabel,
    required this.essence,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_fix_high, color: AppColors.deepCoral, size: 22),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              Text(
                '$tierLabel · +$stage강',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
        _EssenceChip(essence: essence),
      ],
    );
  }
}

class _EssenceChip extends StatelessWidget {
  final int essence;

  const _EssenceChip({required this.essence});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond, color: Colors.teal.shade700, size: 15),
          const SizedBox(width: 4),
          Text(
            '$essence',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.teal.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StagePreview extends StatelessWidget {
  final int stage;
  final int targetStage;

  const _StagePreview({required this.stage, required this.targetStage});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: Row(
        children: [
          Expanded(child: _SwordPreviewCard(label: '현재', stage: stage)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, color: AppColors.deepCoral, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: _SwordPreviewCard(
              label: '다음',
              stage: targetStage,
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwordPreviewCard extends StatelessWidget {
  final String label;
  final int stage;
  final bool highlight;

  const _SwordPreviewCard({
    required this.label,
    required this.stage,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.deepCoral : Colors.black54;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? AppColors.coral.withValues(alpha: 0.58)
              : Colors.black12,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$label +$stage',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Expanded(
            child: MainSwordWidget(stage: stage, size: 78, onTap: (_) {}),
          ),
        ],
      ),
    );
  }
}

class _NextStageBar extends StatelessWidget {
  final int targetStage;
  final String tierName;

  const _NextStageBar({required this.targetStage, required this.tierName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag, color: AppColors.deepCoral, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '목표 +$targetStage · $tierName',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionPanel extends StatelessWidget {
  final MainSwordBoostLevel boost;
  final bool useProtection;
  final MainSwordEnhanceCurrency selectedCurrency;
  final ValueChanged<MainSwordBoostLevel> onBoostChanged;
  final ValueChanged<bool> onProtectionChanged;

  const _OptionPanel({
    required this.boost,
    required this.useProtection,
    required this.selectedCurrency,
    required this.onBoostChanged,
    required this.onProtectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final protectionRelevant =
        selectedCurrency == MainSwordEnhanceCurrency.gold;
    return _Panel(
      title: '공통 옵션',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final level in MainSwordBoostLevel.values)
                _ChoiceChipButton(
                  label: _boostLabel(level),
                  subLabel: _boostCostLabel(level),
                  selected: boost == level,
                  onTap: () => onBoostChanged(level),
                ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onProtectionChanged(!useProtection),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: protectionRelevant
                    ? AppColors.deepCoral.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: protectionRelevant
                      ? AppColors.deepCoral.withValues(alpha: 0.22)
                      : Colors.black12,
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: useProtection,
                    onChanged: (value) => onProtectionChanged(value ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '보호권 유지',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          protectionRelevant
                              ? '골드 강화 실패 시 단계 하락 방지 · 정수 $mainSwordProtectionEssenceCost'
                              : '정수/하이브리드는 기본적으로 실패 시 단계가 유지됩니다',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _boostLabel(MainSwordBoostLevel level) => switch (level) {
        MainSwordBoostLevel.none => '부스트 없음',
        MainSwordBoostLevel.small => '+10%',
        MainSwordBoostLevel.medium => '+25%',
        MainSwordBoostLevel.large => '+50%',
      };

  String _boostCostLabel(MainSwordBoostLevel level) {
    if (level.essenceCost <= 0) return '무료';
    return '정수 ${level.essenceCost}';
  }
}

class _ModeGrid extends StatelessWidget {
  final MainSwordEnhanceCurrency selected;
  final Map<MainSwordEnhanceCurrency, _EnhancePlan> plans;
  final double gold;
  final int essence;
  final ValueChanged<MainSwordEnhanceCurrency> onSelected;

  const _ModeGrid({
    required this.selected,
    required this.plans,
    required this.gold,
    required this.essence,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '강화 방식',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 390;
          final width = twoColumns
              ? (constraints.maxWidth - 8) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final plan in plans.values)
                SizedBox(
                  width: width,
                  child: _ModeCard(
                    plan: plan,
                    selected: selected == plan.currency,
                    canAfford:
                        gold >= plan.goldCost && essence >= plan.essenceCost,
                    onTap: () => onSelected(plan.currency),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final _EnhancePlan plan;
  final bool selected;
  final bool canAfford;
  final VoidCallback onTap;

  const _ModeCard({
    required this.plan,
    required this.selected,
    required this.canAfford,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? plan.color : plan.color.withValues(alpha: 0.22);
    return Material(
      color: selected
          ? plan.color.withValues(alpha: 0.1)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(plan.icon, color: plan.color, size: 17),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      plan.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.circle,
                    size: 14,
                    color: selected ? plan.color : Colors.black26,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${(plan.successRate * 100).toStringAsFixed(0)}% · ${canAfford ? '시도 가능' : '재화 부족'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: canAfford ? plan.color : Colors.black45,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                plan.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttemptSummary extends StatelessWidget {
  final _EnhancePlan plan;
  final bool canAfford;
  final VoidCallback onTry;

  const _AttemptSummary({
    required this.plan,
    required this.canAfford,
    required this.onTry,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '이번 시도',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _CostPill(
                  icon: Icons.paid,
                  label: plan.goldCost > 0
                      ? NumberFormatter.format(plan.goldCost)
                      : '없음',
                  color: AppColors.deepCoral,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CostPill(
                  icon: Icons.diamond,
                  label: plan.essenceCost > 0 ? '${plan.essenceCost}' : '없음',
                  color: const Color(0xFF7C4DFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _InfoBadge(
                label: '성공률 ${(plan.successRate * 100).toStringAsFixed(0)}%',
                color: plan.color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _InfoBadge(
                  label: plan.failureLabel,
                  color: plan.protectedOnFail
                      ? const Color(0xFF00695C)
                      : AppColors.deepCoral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: canAfford ? onTry : null,
            icon: const Icon(Icons.auto_fix_high, size: 17),
            label: Text(canAfford ? '${plan.title} 시도' : '재화 부족'),
            style: FilledButton.styleFrom(
              backgroundColor: plan.color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              minimumSize: const Size.fromHeight(42),
            ),
          ),
        ],
      ),
    );
  }
}

class _CostPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CostPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Expanded(
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
          ),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _ChoiceChipButton extends StatelessWidget {
  final String label;
  final String subLabel;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChipButton({
    required this.label,
    required this.subLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.deepCoral : Colors.black54;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.coral.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.coral.withValues(alpha: 0.56)
                : Colors.black12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              subLabel,
              style: TextStyle(
                color: color.withValues(alpha: 0.72),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _MaxedPanel extends StatelessWidget {
  const _MaxedPanel();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Center(
        child: Text(
          '+50강 도달! 더 이상 강화할 수 없습니다',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
