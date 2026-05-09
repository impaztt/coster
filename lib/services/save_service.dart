import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/save_data.dart';

/// Local persistence with a two-slot rolling backup. Every write rotates the
/// existing `current` blob into `previous` before overwriting `current` with
/// the new payload. If `current` is ever unreadable on load (corrupted bytes,
/// truncated write, schema regression), the loader falls back to `previous`
/// so the worst case is "lose the most recent write" instead of "lose the
/// entire save."
class SaveService {
  // Kept as the legacy key string so existing installs migrate seamlessly.
  static const _keyCurrent = 'sw_clicker_save_v1';
  static const _keyPrevious = 'sw_clicker_save_v1_prev';
  static const _pendingAccountLoginKey = 'sw_pending_account_login_v1';

  Future<SaveData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final primary = _tryDecode(prefs.getString(_keyCurrent));
    if (primary != null) return primary;
    // Current slot is missing or unreadable — fall back to the prior snapshot.
    return _tryDecode(prefs.getString(_keyPrevious));
  }

  SaveData? _tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SaveData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SaveData data) async {
    data.lastSavedAt = DateTime.now();
    await _writeRotated(jsonEncode(data.toJson()));
  }

  /// Persist without bumping `lastSavedAt`. Used when applying a cloud save
  /// locally — we must preserve the cloud's timestamp so the next sync
  /// doesn't re-flip the last-write-wins decision.
  Future<void> saveRaw(SaveData data) async {
    await _writeRotated(jsonEncode(data.toJson()));
  }

  Future<void> _writeRotated(String encoded) async {
    final prefs = await SharedPreferences.getInstance();
    final priorRaw = prefs.getString(_keyCurrent);
    if (priorRaw != null && priorRaw.isNotEmpty && priorRaw != encoded) {
      // Promote the existing current snapshot to previous before overwriting.
      // If a crash splits the two writes, the load path still finds a valid
      // save in one slot or the other.
      await prefs.setString(_keyPrevious, priorRaw);
    }
    await prefs.setString(_keyCurrent, encoded);
  }

  Future<void> wipe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrent);
    await prefs.remove(_keyPrevious);
    await prefs.remove(_pendingAccountLoginKey);
  }

  Future<void> markPendingAccountLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingAccountLoginKey, true);
  }

  Future<bool> consumePendingAccountLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_pendingAccountLoginKey) ?? false;
    if (pending) await prefs.remove(_pendingAccountLoginKey);
    return pending;
  }

  Future<void> clearPendingAccountLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingAccountLoginKey);
  }
}
