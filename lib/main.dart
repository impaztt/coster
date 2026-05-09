import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/supabase_config.dart';
import 'services/ad_service.dart';
import 'services/iap_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  // Mobile-only services. Best-effort init — if the platform doesn't ship
  // these plugins (web/desktop) we just skip and the game still works.
  if (!kIsWeb) {
    unawaited(AdService.instance.initialize());
    unawaited(IapService.instance.initialize());
  }
  runApp(const ProviderScope(child: SwClickerApp()));
}
