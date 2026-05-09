import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../services/ad_service.dart';
import '../widgets/daily_bonus_dialog.dart';
import '../widgets/offline_reward_dialog.dart';
import '../widgets/onboarding_dialog.dart';
import 'home_screen.dart';
import 'prestige_screen.dart';
import 'settings_screen.dart';
import 'sword_screen.dart';
import 'upgrade_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _index = 0;
  bool _bootDialogsShown = false;

  static const _pages = <Widget>[
    HomeScreen(),
    UpgradeScreen(),
    SwordScreen(),
    PrestigeScreen(),
    SettingsScreen(),
  ];

  static const _navHome = 0;
  static const _navUpgrade = 1;
  static const _navStore = 2;
  static const _navPrestige = 3;
  static const _navSettings = 4;

  static const _allDestinations = <_NavDestSpec>[
    _NavDestSpec(
      pageIndex: _navHome,
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: '홈',
    ),
    _NavDestSpec(
      pageIndex: _navUpgrade,
      icon: Icons.upgrade_outlined,
      selectedIcon: Icons.upgrade_rounded,
      label: '강화',
    ),
    _NavDestSpec(
      pageIndex: _navStore,
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront,
      label: '상점',
    ),
    _NavDestSpec(
      pageIndex: _navPrestige,
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      label: '환생',
    ),
    _NavDestSpec(
      pageIndex: _navSettings,
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      label: '설정',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    ref.listen(authStatusProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (after == null || !after.isLinkedAccount) return;
      if (before?.userId == after.userId && before?.isLinkedAccount == true) {
        return;
      }
      if (!ref.read(gameProvider).loaded) return;
      Future.microtask(() async {
        await ref.read(gameProvider.notifier).loadCloudSaveForCurrentAccount();
      });
    });
    if (game.loaded && !_bootDialogsShown) {
      _bootDialogsShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runBootDialogs());
    }

    final visible = _allDestinations
        .where(
            (d) => d.featureId == null || game.isFeatureUnlocked(d.featureId!))
        .toList();
    // Map current page index back to a slot in the visible list. If the
    // destination just got hidden (shouldn't happen — unlocks are sticky),
    // fall back to home.
    var slot = visible.indexWhere((d) => d.pageIndex == _index);
    if (slot < 0) {
      slot = 0;
      _index = visible.first.pageIndex;
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: slot,
        onDestinationSelected: (i) {
          final target = visible[i].pageIndex;
          if (target == _index) return; // tapping the current tab — no ad
          setState(() => _index = target);
          AdService.instance.recordTabSwitch();
        },
        destinations: [
          for (final d in visible)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }

  Future<void> _runBootDialogs() async {
    // Offline reward first (time-sensitive context from lastSavedAt), then
    // daily bonus. Both are shown sequentially so the user can't miss one.
    final notifier = ref.read(gameProvider.notifier);
    final game = ref.read(gameProvider);
    if (!game.tutorialSeen && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OnboardingDialog(game: game),
      );
      notifier.setTutorialSeen(true);
    }
    final offline = notifier.consumeOfflineReward();
    if (offline != null && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OfflineRewardDialog(reward: offline),
      );
    }
    final daily = notifier.consumePendingDaily();
    if (daily != null && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DailyBonusDialog(bonus: daily),
      );
    }
  }
}

class _NavDestSpec {
  final int pageIndex;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? featureId;
  const _NavDestSpec({
    required this.pageIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.featureId,
  });
}
