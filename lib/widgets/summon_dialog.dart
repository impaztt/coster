import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/sword_affinities.dart';
import '../models/sword.dart';
import '../providers/game_provider.dart';
import '../services/audio_service.dart';
import 'sword_preview.dart';

Future<void> showSummonDialog(
  BuildContext context,
  List<SummonResult> results,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => _SummonRevealDialog(results: results),
  );
}

class _SummonRevealDialog extends StatefulWidget {
  final List<SummonResult> results;
  const _SummonRevealDialog({required this.results});

  @override
  State<_SummonRevealDialog> createState() => _SummonRevealDialogState();
}

class _SummonRevealDialogState extends State<_SummonRevealDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _revealScale;
  late final Animation<double> _revealFade;
  bool _summary = false;

  SwordTier get _highest {
    SwordTier h = SwordTier.n;
    for (final r in widget.results) {
      if (r.sword.tier.index > h.index) h = r.sword.tier;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _revealScale = Tween<double>(begin: 0.3, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_ctrl);
    _revealFade = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: const Interval(0.0, 0.3)))
        .animate(_ctrl);
    _ctrl.forward();
    AudioService.instance.playSummon();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.results.length == 1;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              _highest.color.withValues(alpha: 0.4),
              Colors.black,
            ],
            radius: 1.2,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _highest.color.withValues(alpha: 0.6),
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _summary
                  ? '소환 결과 (${widget.results.length}개)'
                  : '소환 중...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            if (isSingle)
              _SingleReveal(
                result: widget.results.first,
                revealScale: _revealScale,
                revealFade: _revealFade,
              )
            else
              _MultiReveal(
                results: widget.results,
                revealScale: _revealScale,
                revealFade: _revealFade,
                onFlipped: () {
                  if (!_summary) setState(() => _summary = true);
                },
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text(
                '확인',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleReveal extends StatelessWidget {
  final SummonResult result;
  final Animation<double> revealScale;
  final Animation<double> revealFade;

  const _SingleReveal({
    required this.result,
    required this.revealScale,
    required this.revealFade,
  });

  @override
  Widget build(BuildContext context) {
    final tier = result.sword.tier;
    final role = swordFormationRole(result.sword);
    final region = swordHomeRegion(result.sword);
    return AnimatedBuilder(
      animation: revealScale,
      builder: (_, __) {
        return Transform.scale(
          scale: revealScale.value,
          child: Opacity(
            opacity: revealFade.value,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: tier.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${tier.label} · ${tier.korLabel}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: tier.color.withValues(alpha: 0.6),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: Center(
                    child: SwordPreview(
                      visual: result.sword.visual,
                      size: 110,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  result.sword.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _outcomeLabel(result),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${role.label} · ${region.shortName} 검세권',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _outcomeLabel(SummonResult r) {
  if (r.isMaxed) return '이미 최대 레벨';
  if (r.isDuplicate) return '레벨업! → Lv ${r.levelAfter}';
  return '신규 획득 · Lv 1';
}

class _MultiReveal extends StatefulWidget {
  final List<SummonResult> results;
  final Animation<double> revealScale;
  final Animation<double> revealFade;
  final VoidCallback onFlipped;

  const _MultiReveal({
    required this.results,
    required this.revealScale,
    required this.revealFade,
    required this.onFlipped,
  });

  @override
  State<_MultiReveal> createState() => _MultiRevealState();
}

class _MultiRevealState extends State<_MultiReveal> {
  @override
  void initState() {
    super.initState();
    // Reveal summary after initial animation.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) widget.onFlipped();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shouldScroll = widget.results.length > 25;
    final grid = GridView.count(
      crossAxisCount: 5,
      shrinkWrap: !shouldScroll,
      physics: shouldScroll
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.8,
      children: [
        for (final r in widget.results) _MultiCell(result: r),
      ],
    );
    return AnimatedBuilder(
      animation: widget.revealFade,
      builder: (_, __) {
        final content = shouldScroll
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: grid,
                ),
              )
            : grid;
        return Opacity(
          opacity: widget.revealFade.value,
          child: content,
        );
      },
    );
  }
}

class _MultiCell extends StatelessWidget {
  final SummonResult result;
  const _MultiCell({required this.result});

  @override
  Widget build(BuildContext context) {
    final tier = result.sword.tier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: tier.color.withValues(alpha: 0.6),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: tier.color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tier.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: SwordPreview(visual: result.sword.visual, size: 40),
          ),
          const SizedBox(height: 2),
          if (result.isDuplicate && !result.isMaxed)
            const Icon(Icons.arrow_upward,
                size: 10, color: AppColors.deepCoral)
          else if (result.isMaxed)
            const Icon(Icons.check, size: 10, color: Colors.grey)
          else
            const Icon(Icons.fiber_new, size: 10, color: AppColors.deepCoral),
        ],
      ),
    );
  }
}
