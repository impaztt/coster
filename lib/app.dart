import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers/game_provider.dart';
import 'screens/main_screen.dart';
import 'services/audio_service.dart';
import 'widgets/achievement_toast.dart';
import 'widgets/feature_unlock_toast.dart';
import 'widgets/first_purchase_popup.dart';
import 'widgets/main_coaster_event_host.dart';

class CosterApp extends ConsumerStatefulWidget {
  const CosterApp({super.key});

  @override
  ConsumerState<CosterApp> createState() => _CosterAppState();
}

class _CosterAppState extends ConsumerState<CosterApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Awaiting here doesn't block Flutter's lifecycle dispatch, but it does
      // schedule the local-write continuation immediately so SharedPreferences
      // gets a chance to flush before a force-kill.
      await ref.read(gameProvider.notifier).persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sound = ref.watch(gameProvider.select((s) => s.sound));
    AudioService.instance.setEnabled(sound);

    final darkMode = ref.watch(gameProvider.select((s) => s.darkMode));
    final highContrast = ref.watch(gameProvider.select((s) => s.highContrast));
    final textScale = ref.watch(gameProvider.select((s) => s.textScale));

    return MaterialApp(
      title: '검 키우기',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(highContrast: highContrast),
      darkTheme: buildDarkTheme(highContrast: highContrast),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: AchievementToastHost(
            child: FeatureUnlockToastHost(
              child: MainCoasterEventHost(
                child: FirstPurchasePopupHost(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      home: const MainScreen(),
    );
  }
}
