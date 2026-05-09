import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/achievement_catalog.dart';
import '../models/achievement.dart';
import '../providers/game_provider.dart';

class AchievementScreen extends ConsumerStatefulWidget {
  const AchievementScreen({super.key});

  @override
  ConsumerState<AchievementScreen> createState() => _AchievementScreenState();
}

class _AchievementScreenState extends ConsumerState<AchievementScreen> {
  AchievementCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final ctx = game.achContext();
    final filtered = _filter == null
        ? achievementCatalog
        : achievementCatalog.where((a) => a.category == _filter).toList();
    final total = achievementCatalog.length;
    final unlockedCount = game.unlockedAchievements.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('업적'),
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '전체 진행도',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$unlockedCount / $total',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : unlockedCount / total,
                          minHeight: 8,
                          backgroundColor: Colors.black12,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.coral),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _CategoryChip(
                  label: '전체',
                  color: AppColors.coral,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final cat in AchievementCategory.values)
                  _CategoryChip(
                    label: cat.label,
                    color: cat.color,
                    selected: _filter == cat,
                    onTap: () => setState(() => _filter = cat),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final def = filtered[i];
                final unlocked = game.isAchievementUnlocked(def.id);
                final prog = def.progress(ctx);
                return _AchievementTile(
                  def: def,
                  progress: prog,
                  unlocked: unlocked,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withValues(alpha: selected ? 1.0 : 0.3),
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final AchievementDef def;
  final AchProgress progress;
  final bool unlocked;

  const _AchievementTile({
    required this.def,
    required this.progress,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final color = def.category.color;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unlocked ? color : Colors.black12,
          width: unlocked ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: unlocked ? 0.25 : 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              def.category.icon,
              color: unlocked ? color : Colors.black26,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        def.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: unlocked ? Colors.black87 : Colors.black54,
                        ),
                      ),
                    ),
                    if (unlocked)
                      Icon(Icons.check_circle, color: color, size: 18),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  def.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.ratio,
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _progressLabel(progress),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.diamond,
                        size: 12, color: Color(0xFF7C4DFF)),
                    const SizedBox(width: 2),
                    Text(
                      '+${def.essenceReward}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C4DFF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _progressLabel(AchProgress p) {
    if (p.target == 1) return p.done ? '완료' : '미완료';
    final cur = _compact(p.current);
    final tgt = _compact(p.target);
    return '$cur / $tgt';
  }

  static String _compact(double v) {
    if (v >= 1e18) return '${(v / 1e18).toStringAsFixed(2)}Qi';
    if (v >= 1e15) return '${(v / 1e15).toStringAsFixed(2)}Qa';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(2)}K';
    return v.floor().toString();
  }
}
