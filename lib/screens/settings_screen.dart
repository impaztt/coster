import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/number_format.dart';
import '../core/theme.dart';
import '../data/achievement_catalog.dart';
import '../data/feature_unlocks.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../services/auth_service.dart';
import '../widgets/feature_unlock_guide.dart';
import '../widgets/onboarding_dialog.dart';
import 'achievement_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final authStatus = ref.watch(authStatusProvider);

    return SafeArea(
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '설정',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black54,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.deepCoral,
                  borderRadius: BorderRadius.all(Radius.circular(7)),
                ),
                labelStyle:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                unselectedLabelStyle:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                tabs: [
                  Tab(height: 34, text: '요약'),
                  Tab(height: 34, text: '환경'),
                  Tab(height: 34, text: '계정'),
                  Tab(height: 34, text: '데이터'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SettingsSummaryView(
                    game: game,
                    authStatus: authStatus,
                    onOpenAchievements: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AchievementScreen(),
                      ),
                    ),
                    onOpenRoadmap: () => showFeatureUnlockRoadmapSheet(
                      context,
                      game: game,
                      title: '설정 - 해금 가이드',
                    ),
                  ),
                  _SettingsEnvironmentView(
                    game: game,
                    onHaptic: (v) =>
                        ref.read(gameProvider.notifier).setHaptic(v),
                    onSound: (v) => ref.read(gameProvider.notifier).setSound(v),
                    onDarkMode: (v) =>
                        ref.read(gameProvider.notifier).setDarkMode(v),
                    onHighContrast: (v) =>
                        ref.read(gameProvider.notifier).setHighContrast(v),
                    onReduceTapHaptics: (v) =>
                        ref.read(gameProvider.notifier).setReduceTapHaptics(v),
                    onTextScale: (v) =>
                        ref.read(gameProvider.notifier).setTextScale(v),
                  ),
                  _SettingsAccountView(
                    authStatus: authStatus,
                    onGoogle: () => _startSocialLogin(
                      context,
                      ref,
                      SocialSignInProvider.google,
                    ),
                    onApple: () => _startSocialLogin(
                      context,
                      ref,
                      SocialSignInProvider.apple,
                    ),
                    onLogout: () => _confirmLogout(context, ref),
                  ),
                  _SettingsDataView(
                    game: game,
                    onOpenRoadmap: () => showFeatureUnlockRoadmapSheet(
                      context,
                      game: game,
                      title: '설정 - 해금 가이드',
                    ),
                    onReplayTutorial: () => showDialog<void>(
                      context: context,
                      builder: (_) => OnboardingDialog(
                        game: game,
                        replayMode: true,
                      ),
                    ),
                    onReset: () => _confirmReset(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        title: const Text('정말 초기화할까요?'),
        content: const Text(
          '모든 진행도, 골드, 강화 레벨, 환생 코인, 통계가 삭제됩니다.\n'
          '이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(gameProvider.notifier).resetAll();
    }
  }

  Future<void> _startSocialLogin(
    BuildContext context,
    WidgetRef ref,
    SocialSignInProvider provider,
  ) async {
    await ref.read(gameProvider.notifier).persist();
    final result =
        await ref.read(authServiceProvider).signInWithSocial(provider);
    if (!context.mounted) return;
    _toast(context, result.message);
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        title: const Text('로그아웃할까요?'),
        content: const Text(
          '현재 기기의 진행도는 유지됩니다.\n'
          '로그아웃 후에는 게스트 상태로 계속 플레이합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await ref.read(authServiceProvider).signOutToGuest();
    await ref.read(gameProvider.notifier).persist();
    if (!context.mounted) return;
    _toast(context, result.message);
  }
}

class _SettingsSummaryView extends StatelessWidget {
  final GameState game;
  final AsyncValue<AuthStatus> authStatus;
  final VoidCallback onOpenAchievements;
  final VoidCallback onOpenRoadmap;

  const _SettingsSummaryView({
    required this.game,
    required this.authStatus,
    required this.onOpenAchievements,
    required this.onOpenRoadmap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        authStatus.when(
          data: (status) => _AccountStatusStrip(status: status),
          loading: () => const _AccountStatusLoadingStrip(),
          error: (_, __) => const _AccountStatusStrip(
            status: AuthStatus(
              userId: null,
              email: null,
              isAnonymous: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle(title: '통계'),
        const SizedBox(height: 8),
        _StatGrid(
          items: [
            _StatItem(
              icon: Icons.touch_app,
              color: AppColors.coral,
              label: '총 터치',
              value: NumberFormatter.format(game.totalTaps.toDouble()),
            ),
            _StatItem(
              icon: Icons.timer,
              color: const Color(0xFF00695C),
              label: '플레이 시간',
              value: _fmtDuration(game.playTimeSeconds),
            ),
            _StatItem(
              icon: Icons.bolt,
              color: const Color(0xFF8D6E00),
              label: '최고 DPS',
              value: NumberFormatter.format(game.maxDpsEver),
            ),
            _StatItem(
              icon: Icons.monetization_on,
              color: AppColors.deepCoral,
              label: '누적 골드',
              value: NumberFormatter.format(game.lifetimeGold),
            ),
            _StatItem(
              icon: Icons.auto_awesome,
              color: AppColors.mint,
              label: '환생 횟수',
              value: '${game.prestigeCount}',
            ),
            _StatItem(
              icon: Icons.trending_up,
              color: const Color(0xFF7E57C2),
              label: '영구 배율',
              value:
                  '+${((game.prestigeMultiplier - 1) * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _SectionTitle(title: '진행'),
        const SizedBox(height: 8),
        _AchievementLink(
          unlocked: game.unlockedAchievements.length,
          total: achievementCatalog.length,
          onTap: onOpenAchievements,
        ),
        const SizedBox(height: 8),
        _UnlockGuideHeader(
          game: game,
          onOpenRoadmap: onOpenRoadmap,
        ),
      ],
    );
  }
}

class _SettingsEnvironmentView extends StatelessWidget {
  final GameState game;
  final ValueChanged<bool> onHaptic;
  final ValueChanged<bool> onSound;
  final ValueChanged<bool> onDarkMode;
  final ValueChanged<bool> onHighContrast;
  final ValueChanged<bool> onReduceTapHaptics;
  final ValueChanged<double> onTextScale;

  const _SettingsEnvironmentView({
    required this.game,
    required this.onHaptic,
    required this.onSound,
    required this.onDarkMode,
    required this.onHighContrast,
    required this.onReduceTapHaptics,
    required this.onTextScale,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _SettingsGroup(
          title: '조작',
          children: [
            _ToggleRow(
              icon: Icons.vibration,
              label: '진동',
              value: game.haptic,
              onChanged: onHaptic,
            ),
            _ToggleRow(
              icon: Icons.touch_app,
              label: '일반 터치 진동 줄이기',
              value: game.reduceTapHaptics,
              onChanged: onReduceTapHaptics,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroup(
          title: '소리',
          children: [
            _ToggleRow(
              icon: Icons.volume_up,
              label: '사운드',
              value: game.sound,
              onChanged: onSound,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroup(
          title: '화면',
          children: [
            _ToggleRow(
              icon: Icons.dark_mode,
              label: '다크 모드',
              value: game.darkMode,
              onChanged: onDarkMode,
            ),
            _ToggleRow(
              icon: Icons.contrast,
              label: '고대비 모드',
              value: game.highContrast,
              onChanged: onHighContrast,
            ),
            _TextScaleSelector(
              value: game.textScale,
              onChanged: onTextScale,
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsAccountView extends StatelessWidget {
  final AsyncValue<AuthStatus> authStatus;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onLogout;

  const _SettingsAccountView({
    required this.authStatus,
    required this.onGoogle,
    required this.onApple,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        const _SectionTitle(title: '계정'),
        const SizedBox(height: 8),
        authStatus.when(
          data: (status) => _AccountCard(
            status: status,
            onGoogle: onGoogle,
            onApple: onApple,
            onLogout: onLogout,
          ),
          loading: () => const _AccountLoadingCard(),
          error: (_, __) => _AccountCard(
            status: const AuthStatus(
              userId: null,
              email: null,
              isAnonymous: true,
            ),
            onGoogle: onGoogle,
            onApple: onApple,
            onLogout: onLogout,
          ),
        ),
      ],
    );
  }
}

class _SettingsDataView extends StatelessWidget {
  final GameState game;
  final VoidCallback onOpenRoadmap;
  final VoidCallback onReplayTutorial;
  final VoidCallback onReset;

  const _SettingsDataView({
    required this.game,
    required this.onOpenRoadmap,
    required this.onReplayTutorial,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        if (game.timeGuardTriggered) ...[
          const _TimeGuardWarning(),
          const SizedBox(height: 14),
        ],
        _SettingsGroup(
          title: '도움말',
          children: [
            _DataActionTile(
              icon: Icons.map_outlined,
              label: '해금 가이드 전체 보기',
              onTap: onOpenRoadmap,
            ),
            _DataActionTile(
              icon: Icons.school,
              label: '튜토리얼 다시 보기',
              onTap: onReplayTutorial,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DangerZone(onReset: onReset),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(
                    height: 1,
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountStatusStrip extends StatelessWidget {
  final AuthStatus status;

  const _AccountStatusStrip({required this.status});

  @override
  Widget build(BuildContext context) {
    final linked = status.isLinkedAccount;
    final title = linked ? '계정 연결됨' : '게스트 플레이';
    final subtitle = linked ? (status.email ?? '로그인 계정') : '현재 기기에 자동 저장';
    final color = linked ? const Color(0xFF00695C) : AppColors.deepCoral;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(linked ? Icons.verified_user : Icons.person_outline,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'ID ${status.shortUserId}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountStatusLoadingStrip extends StatelessWidget {
  const _AccountStatusLoadingStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _DataActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DataActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: AppColors.deepCoral),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeGuardWarning extends StatelessWidget {
  const _TimeGuardWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: const Text(
        '기기 시간 조작이 감지되어 오프라인 보상이 제한되었습니다.\n'
        '시간 자동 설정 사용을 권장합니다.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.redAccent,
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  final VoidCallback onReset;

  const _DangerZone({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: '위험 영역'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '모든 진행도 삭제',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '골드, 강화, 환생 코인, 통계가 삭제되며 복구할 수 없습니다.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 12),
              _DangerButton(onPressed: onReset),
            ],
          ),
        ),
      ],
    );
  }
}

String _fmtDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Colors.black.withValues(alpha: 0.55),
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final List<_StatItem> items;
  const _StatGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.8,
      children: items,
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockGuideHeader extends StatelessWidget {
  final GameState game;
  final VoidCallback onOpenRoadmap;

  const _UnlockGuideHeader({
    required this.game,
    required this.onOpenRoadmap,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = unlockedFeatureCount(game);
    final total = featureUnlockCatalog.length;
    final next = nextRecommendedLockedFeature(game);
    final nextProgress = next?.progress(game);
    final ratio = featureUnlockCompletionRatio(game);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              const Icon(Icons.map_outlined, color: AppColors.deepCoral),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$unlocked / $total 기능 해금',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            next == null
                ? '모든 기능이 해금되었습니다.'
                : '다음 추천 목표: ${next.label} (${nextProgress?.percentText ?? '0%'})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation(AppColors.coral),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenRoadmap,
                icon: const Icon(Icons.visibility),
                label: const Text('전체 기준 보기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.coral),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.coral,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AchievementLink extends StatelessWidget {
  final int unlocked;
  final int total;
  final VoidCallback onTap;

  const _AchievementLink({
    required this.unlocked,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : unlocked / total;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
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
              const Icon(Icons.emoji_events, color: Color(0xFFD81B60)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '전체 업적',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$unlocked / $total 해금',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: Colors.black12,
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFFD81B60)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextScaleSelector extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _TextScaleSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = <double>[0.9, 1.0, 1.15, 1.3];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.text_fields, color: AppColors.coral),
              SizedBox(width: 8),
              Text(
                '글자 크기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final opt in options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _ScaleChip(
                      label: '${(opt * 100).round()}%',
                      selected: (value - opt).abs() < 0.001,
                      onTap: () => onChanged(opt),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScaleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ScaleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.coral : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AuthStatus status;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onLogout;

  const _AccountCard({
    required this.status,
    required this.onGoogle,
    required this.onApple,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final linked = status.isLinkedAccount;
    final title = linked ? (status.email ?? '로그인 계정') : '게스트 플레이 중';
    final subtitle = linked
        ? '클라우드 저장이 이 계정에 연결됩니다'
        : '로그인 없이도 저장됩니다. 계정 연결 시 기기 변경 후에도 이어갈 수 있어요';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (linked ? Colors.teal : AppColors.coral)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  linked ? Icons.verified_user : Icons.person_outline,
                  color: linked ? Colors.teal.shade700 : AppColors.deepCoral,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'ID ${status.shortUserId}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 12),
          if (linked)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('로그아웃'),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: onGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Google로 계속하기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onApple,
                  icon: const Icon(Icons.apple, size: 20),
                  label: const Text('Apple로 계속하기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '비로그인 상태에서도 현재 기기와 게스트 클라우드에 진행도가 자동 저장됩니다.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.52),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AccountLoadingCard extends StatelessWidget {
  const _AccountLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _DangerButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
      label: const Text(
        '데이터 초기화',
        style: TextStyle(
          color: Colors.redAccent,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
