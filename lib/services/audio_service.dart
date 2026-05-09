import 'package:flutter/services.dart';

/// Minimal audio layer using system sounds. Toggled by [setEnabled]; all `play*`
/// methods are no-ops when disabled. Richer sounds (bundled WAV assets via
/// `audioplayers` or `just_audio`) can be swapped in here later without
/// changing callers.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  bool _enabled = true;

  void setEnabled(bool v) {
    _enabled = v;
  }

  void playTap() {
    if (!_enabled) return;
    SystemSound.play(SystemSoundType.click);
  }

  void playBuy() {
    if (!_enabled) return;
    SystemSound.play(SystemSoundType.click);
  }

  void playSummon() {
    if (!_enabled) return;
    SystemSound.play(SystemSoundType.alert);
  }

  void playAchievement() {
    if (!_enabled) return;
    SystemSound.play(SystemSoundType.alert);
  }
}
