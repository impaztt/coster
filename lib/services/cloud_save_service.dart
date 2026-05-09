import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../models/save_data.dart';

/// Thin wrapper around Supabase for the single save-row per user.
/// One row keyed by `user_id`; the entire SaveData lives in a `jsonb` column.
class CloudSaveService {
  SupabaseClient get _client => Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;
  bool get isSignedIn => _client.auth.currentUser != null;

  /// Ensure there is a signed-in user. Anonymous sign-in is used as the
  /// default identity so every install gets a cloud slot immediately.
  /// Returns the user id.
  Future<String> ensureSignedIn() async {
    final existing = _client.auth.currentUser;
    if (existing != null) return existing.id;
    final res = await _client.auth.signInAnonymously();
    final id = res.user?.id;
    if (id == null) {
      throw StateError('Supabase anonymous sign-in returned no user');
    }
    return id;
  }

  Future<SaveData?> fetch() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final row = await _client
        .from(SupabaseConfig.saveTable)
        .select('data')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    final data = row['data'];
    if (data is! Map) return null;
    return SaveData.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> upsert(SaveData save) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _client.from(SupabaseConfig.saveTable).upsert({
      'user_id': uid,
      'data': save.toJson(),
      'last_saved_at': save.lastSavedAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
