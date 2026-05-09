import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/feature_unlocks.dart';
import '../providers/game_provider.dart';
import 'feature_unlock_guide.dart';

class OnboardingDialog extends StatefulWidget {
  final GameState game;
  final bool replayMode;

  const OnboardingDialog({
    super.key,
    required this.game,
    this.replayMode = false,
  });

  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  static const _pageCount = 2;
  final PageController _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _nextOrClose() {
    if (_page < _pageCount - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.replayMode ? '게임 가이드' : '첫 접속 가이드';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.deepCoral),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (widget.replayMode)
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: '닫기',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _PagerIndicator(page: _page, total: _pageCount),
              const SizedBox(height: 10),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  onPageChanged: (v) => setState(() => _page = v),
                  children: [
                    const _QuickStartPage(),
                    _RoadmapPage(game: widget.game),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () {
                        _pageCtrl.previousPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: const Text('이전'),
                    )
                  else
                    const SizedBox(width: 64),
                  const Spacer(),
                  FilledButton(
                    onPressed: _nextOrClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.coral,
                      minimumSize: const Size(104, 44),
                    ),
                    child: Text(
                      _page < _pageCount - 1
                          ? '다음'
                          : (widget.replayMode ? '닫기' : '시작하기'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
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

class _PagerIndicator extends StatelessWidget {
  final int page;
  final int total;

  const _PagerIndicator({required this.page, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == page ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == page ? AppColors.coral : Colors.black26,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _QuickStartPage extends StatelessWidget {
  const _QuickStartPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '처음에는 아래 3가지만 집중하면 성장 속도가 빨라집니다.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.black.withValues(alpha: 0.62),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        const _StepRow(
          icon: Icons.touch_app,
          title: '1) 홈에서 터치로 초반 골드 확보',
          desc: '터치/콤보 구간을 먼저 올리면 초반 체감이 빠르게 올라갑니다.',
        ),
        const _StepRow(
          icon: Icons.upgrade,
          title: '2) 강화에서 터치·동료를 균형 구매',
          desc: '즉시 수익(터치)과 방치 수익(동료)을 같이 키우는 것이 안정적입니다.',
        ),
        const _StepRow(
          icon: Icons.auto_awesome,
          title: '3) 환생 루프로 영구 성장 누적',
          desc: '각인 연구가 열리면 장기 성장 구간이 본격적으로 시작됩니다.',
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3EA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.coral.withValues(alpha: 0.35)),
          ),
          child: Text(
            '잠긴 기능은 설정 > 해금 가이드에서 언제든지 기준/진행도를 확인할 수 있습니다.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoadmapPage extends StatelessWidget {
  final GameState game;
  const _RoadmapPage({required this.game});

  @override
  Widget build(BuildContext context) {
    final unlocked = unlockedFeatureCount(game);
    final total = featureUnlockCatalog.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '앞으로 열릴 기능 로드맵',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Colors.black.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$unlocked / $total 기능 해금됨 · 각 기능을 눌러 상세 팁을 볼 수 있습니다.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: FeatureUnlockRoadmapList(
              game: game,
              compact: true,
              onTap: (def) => showFeatureUnlockDetailSheet(
                context,
                def: def,
                game: game,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _StepRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF00695C)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
