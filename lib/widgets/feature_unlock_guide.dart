import 'package:flutter/material.dart';

import '../data/feature_unlocks.dart';
import '../providers/game_provider.dart';

Future<void> showFeatureUnlockRoadmapSheet(
  BuildContext context, {
  required GameState game,
  String title = '기능 해금 로드맵',
}) {
  final next = nextRecommendedLockedFeature(game);
  final unlocked = unlockedFeatureCount(game);
  final total = featureUnlockCatalog.length;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.map_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _UnlockRoadmapSummary(
                  unlocked: unlocked,
                  total: total,
                  next: next,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: FeatureUnlockRoadmapList(
                      game: game,
                      onTap: (def) => showFeatureUnlockDetailSheet(
                        ctx,
                        def: def,
                        game: game,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showFeatureUnlockDetailSheet(
  BuildContext context, {
  required FeatureUnlockDef def,
  required GameState game,
}) {
  final progress = def.progress(game);
  final unlocked = game.isFeatureUnlocked(def.id);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: def.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(def.icon, color: def.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      def.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _FeatureStatusChip(unlocked: unlocked),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                def.description,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.66),
                ),
              ),
              const SizedBox(height: 12),
              _InfoLine(
                icon: Icons.track_changes,
                label: '해금 조건',
                value: def.unlockConditionText,
              ),
              const SizedBox(height: 6),
              _InfoLine(
                icon: Icons.rocket_launch,
                label: '핵심 가치',
                value: def.benefitSummary,
              ),
              const SizedBox(height: 6),
              _InfoLine(
                icon: Icons.timeline,
                label: '권장 구간',
                value: def.stageHint,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unlocked
                          ? '진행도: 해금 완료'
                          : '진행도: ${progress.progressText} (${progress.percentText})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: unlocked ? 1.0 : progress.ratio,
                        minHeight: 8,
                        backgroundColor: Colors.black12,
                        valueColor: AlwaysStoppedAnimation(def.color),
                      ),
                    ),
                  ],
                ),
              ),
              if (def.tips.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '빠른 달성 팁',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                for (final tip in def.tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle, size: 14),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class FeatureUnlockRoadmapList extends StatelessWidget {
  final GameState game;
  final bool includeUnlocked;
  final bool compact;
  final int? maxItems;
  final ValueChanged<FeatureUnlockDef>? onTap;

  const FeatureUnlockRoadmapList({
    super.key,
    required this.game,
    this.includeUnlocked = true,
    this.compact = false,
    this.maxItems,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var defs = featureUnlockRoadmap();
    if (!includeUnlocked) {
      defs = defs.where((d) => !game.isFeatureUnlocked(d.id)).toList();
    }
    if (maxItems != null && defs.length > maxItems!) {
      defs = defs.take(maxItems!).toList();
    }
    if (defs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '모든 기능이 해금되었습니다.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final def in defs)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 8 : 10),
            child: _UnlockRoadmapTile(
              def: def,
              game: game,
              compact: compact,
              onTap: onTap,
            ),
          ),
      ],
    );
  }
}

class _UnlockRoadmapSummary extends StatelessWidget {
  final int unlocked;
  final int total;
  final FeatureUnlockDef? next;

  const _UnlockRoadmapSummary({
    required this.unlocked,
    required this.total,
    required this.next,
  });

  @override
  Widget build(BuildContext context) {
    final ratio =
        total == 0 ? 1.0 : (unlocked / total).clamp(0.0, 1.0).toDouble();
    final nextLabel = next == null ? '모든 기능 해금 완료' : '다음 목표: ${next!.label}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$unlocked / $total 기능 해금',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            nextLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF00897B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockRoadmapTile extends StatelessWidget {
  final FeatureUnlockDef def;
  final GameState game;
  final bool compact;
  final ValueChanged<FeatureUnlockDef>? onTap;

  const _UnlockRoadmapTile({
    required this.def,
    required this.game,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = game.isFeatureUnlocked(def.id);
    final p = def.progress(game);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked ? def.color.withValues(alpha: 0.35) : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: def.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(def.icon, size: 18, color: def.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  def.label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              _FeatureStatusChip(unlocked: unlocked),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            def.benefitSummary,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.68),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              '조건: ${def.unlockConditionText}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  unlocked ? '해금 완료' : p.progressText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: unlocked
                        ? const Color(0xFF2E7D32)
                        : Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
              Text(
                unlocked ? '100%' : p.percentText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: unlocked ? const Color(0xFF2E7D32) : def.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: unlocked ? 1.0 : p.ratio,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(
                unlocked ? const Color(0xFF2E7D32) : def.color,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap!(def),
        child: card,
      ),
    );
  }
}

class _FeatureStatusChip extends StatelessWidget {
  final bool unlocked;
  const _FeatureStatusChip({required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final bg = unlocked ? const Color(0xFF2E7D32) : const Color(0xFF616161);
    final text = unlocked ? '해금됨' : '잠김';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.black.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
