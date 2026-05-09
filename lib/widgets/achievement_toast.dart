import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/achievement.dart';
import '../providers/game_provider.dart';
import '../services/audio_service.dart';

/// Listens for achievement unlocks and shows a sliding toast at the top.
class AchievementToastHost extends ConsumerStatefulWidget {
  final Widget child;
  const AchievementToastHost({super.key, required this.child});

  @override
  ConsumerState<AchievementToastHost> createState() =>
      _AchievementToastHostState();
}

class _AchievementToastHostState
    extends ConsumerState<AchievementToastHost> {
  final List<AchievementDef> _queue = [];
  AchievementDef? _current;

  void _showNext() {
    if (_current != null) return;
    if (_queue.isEmpty) return;
    setState(() => _current = _queue.removeAt(0));
    AudioService.instance.playAchievement();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _current = null);
      _showNext();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AchievementDef>>(
      achievementUnlockProvider,
      (prev, next) {
        next.whenData((def) {
          _queue.add(def);
          _showNext();
        });
      },
    );

    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _ToastCard(def: _current!),
            ),
          ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  final AchievementDef def;
  const _ToastCard({required this.def});

  @override
  Widget build(BuildContext context) {
    final color = def.category.color;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      builder: (_, t, __) {
        final y = (1 - t) * -80;
        return Transform.translate(
          offset: Offset(0, y),
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(def.category.icon, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '업적 해제',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    def.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              def.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          const Icon(Icons.diamond,
                              size: 14, color: Color(0xFF7C4DFF)),
                          const SizedBox(width: 2),
                          Text(
                            '+${def.essenceReward}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: AppColors.deepCoral,
                            ),
                          ),
                        ],
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
