import 'dart:async';

import '../models/save_data.dart';
import 'cloud_save_service.dart';
import 'save_service.dart';

/// Coordinates local (SharedPreferences) and cloud (Supabase) saves using
/// last-write-wins on `SaveData.lastSavedAt`.
///
/// - On load: fetch both sides, prefer whichever is newer.
/// - On persist: write local (authoritative, always succeeds), then
///   fire-and-forget push to cloud. Failures are swallowed so an offline
///   tick never blocks gameplay; the next successful push will catch up.
class SyncService {
  final SaveService local;
  final CloudSaveService cloud;

  SyncService({SaveService? local, CloudSaveService? cloud})
      : local = local ?? SaveService(),
        cloud = cloud ?? CloudSaveService();

  /// Resolve local vs cloud and return the effective SaveData for this boot.
  /// Returns null only when neither side has any data.
  Future<SaveData?> loadResolved() async {
    final localSave = await local.load();

    SaveData? cloudSave;
    bool cloudReachable = false;
    try {
      await cloud.ensureSignedIn();
      cloudSave = await cloud.fetch();
      cloudReachable = true;
    } catch (_) {
      // Offline or auth hiccup — fall back to local only.
      return localSave;
    }

    final pendingAccountLogin = await local.consumePendingAccountLogin();
    if (pendingAccountLogin) {
      if (cloudSave != null) {
        await local.saveRaw(cloudSave);
        return cloudSave;
      }
      if (localSave != null) unawaited(_safeUpsert(localSave));
      return localSave;
    }

    if (localSave == null && cloudSave == null) return null;
    if (localSave == null) return cloudSave;
    if (cloudSave == null) {
      if (cloudReachable) unawaited(_safeUpsert(localSave));
      return localSave;
    }

    if (cloudSave.lastSavedAt.isAfter(localSave.lastSavedAt)) {
      await local.saveRaw(cloudSave);
      return cloudSave;
    }
    unawaited(_safeUpsert(localSave));
    return localSave;
  }

  Future<SaveData?> fetchCloudForCurrentUser() async {
    await cloud.ensureSignedIn();
    return cloud.fetch();
  }

  /// Local save always succeeds; cloud push is best-effort.
  Future<void> persist(SaveData save) async {
    await local.save(save);
    unawaited(_safeUpsert(save));
  }

  Future<void> _safeUpsert(SaveData save) async {
    try {
      await cloud.ensureSignedIn();
      await cloud.upsert(save);
    } catch (_) {
      // Next persist tick retries.
    }
  }

  /// Wipes local only. Cloud row is intentionally preserved so the user
  /// can recover after a "reset" if they change their mind — separate
  /// "delete cloud save" action can be added later.
  Future<void> wipe() async {
    await local.wipe();
  }
}
