import 'dart:io' show Platform;

/// AdMob configuration. The default IDs are Google's published test IDs.
/// The app intentionally does not configure bottom ad strips.
class AdConfig {
  // Android test IDs.
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';

  // iOS test IDs.
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  // Production IDs. Replace these before publishing and flip _useProdAds.
  static const _prodInterstitialAndroid =
      'ca-app-pub-XXXXXXXXXXXXXXXX/0000000000';
  static const _prodRewardedAndroid = 'ca-app-pub-XXXXXXXXXXXXXXXX/0000000000';
  static const _prodInterstitialIos = 'ca-app-pub-XXXXXXXXXXXXXXXX/0000000000';
  static const _prodRewardedIos = 'ca-app-pub-XXXXXXXXXXXXXXXX/0000000000';

  static const bool _useProdAds = false;

  static String get interstitialUnitId =>
      _isAndroid ? _interstitialAndroid : _interstitialIos;
  static String get rewardedUnitId =>
      _isAndroid ? _rewardedAndroid : _rewardedIos;

  static String get _interstitialAndroid =>
      _useProdAds ? _prodInterstitialAndroid : _testInterstitialAndroid;
  static String get _rewardedAndroid =>
      _useProdAds ? _prodRewardedAndroid : _testRewardedAndroid;
  static String get _interstitialIos =>
      _useProdAds ? _prodInterstitialIos : _testInterstitialIos;
  static String get _rewardedIos =>
      _useProdAds ? _prodRewardedIos : _testRewardedIos;

  static bool get _isAndroid {
    try {
      return Platform.isAndroid;
    } catch (_) {
      // dart:io throws on web; ads are mobile-only, but Android IDs are safe.
      return true;
    }
  }

  /// Number of actual bottom-tab changes between forced interstitials.
  static const int tabSwitchesPerInterstitial = 10;

  /// Add physical QA devices here so they receive test ads in prod mode.
  static const List<String> testDeviceIds = <String>[
    // 'ABCDEF1234567890ABCDEF1234567890',
  ];
}
