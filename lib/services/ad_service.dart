import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_config.dart';

/// Centralized AdMob facade. Only this class talks to google_mobile_ads.
/// Forced ads are tied to bottom-tab navigation; rewarded ads stay opt-in.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool _initialized = false;
  bool _adsRemoved = false;
  int _tabSwitchCount = 0;
  bool _tabInterstitialInFlight = false;

  InterstitialAd? _interstitialCache;
  RewardedAd? _rewardedCache;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;

  bool get isInitialized => _initialized;

  bool get adsRemoved => _adsRemoved;
  set adsRemoved(bool value) {
    if (_adsRemoved == value) return;
    _adsRemoved = value;
    if (value) {
      _tabSwitchCount = 0;
      _tabInterstitialInFlight = false;
      _interstitialCache?.dispose();
      _interstitialCache = null;
    } else if (_initialized) {
      _preloadInterstitial();
    }
  }

  /// Record a real bottom-tab change. Every configured Nth switch attempts an
  /// interstitial. Failed attempts do not consume the count, so the next tab
  /// switch retries once an ad is available.
  bool recordTabSwitch() {
    if (_adsRemoved) {
      debugPrint('[AdService] tab switch ignored (ads removed)');
      return false;
    }

    _tabSwitchCount++;
    debugPrint('[AdService] tab switch '
        '$_tabSwitchCount/${AdConfig.tabSwitchesPerInterstitial}');

    if (_tabSwitchCount < AdConfig.tabSwitchesPerInterstitial) return false;
    if (_tabInterstitialInFlight) return false;

    debugPrint(
        '[AdService] tab-switch threshold hit - attempting interstitial');
    unawaited(_showTabSwitchInterstitial());
    return true;
  }

  Future<void> _showTabSwitchInterstitial() async {
    _tabInterstitialInFlight = true;
    try {
      final shown = await showInterstitial(trigger: 'tab_switch');
      if (shown) {
        final remaining = _tabSwitchCount - AdConfig.tabSwitchesPerInterstitial;
        _tabSwitchCount = remaining > 0 ? remaining : 0;
      }
    } finally {
      _tabInterstitialInFlight = false;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      if (AdConfig.testDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: AdConfig.testDeviceIds),
        );
      }
      _initialized = true;
      _preloadInterstitial();
      _preloadRewarded();
    } catch (e, st) {
      debugPrint('[AdService] init failed: $e\n$st');
    }
  }

  void _preloadInterstitial() {
    if (_adsRemoved || _loadingInterstitial || _interstitialCache != null) {
      return;
    }
    _loadingInterstitial = true;
    debugPrint('[AdService] preloading interstitial '
        '(unit=${AdConfig.interstitialUnitId})');
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialCache = ad;
          _loadingInterstitial = false;
          debugPrint('[AdService] interstitial preloaded');
        },
        onAdFailedToLoad: (err) {
          _loadingInterstitial = false;
          debugPrint('[AdService] interstitial load failed: $err');
        },
      ),
    );
  }

  /// Try to show an interstitial. Returns true only if the ad reached the
  /// screen and was dismissed normally.
  Future<bool> showInterstitial({String? trigger}) async {
    if (_adsRemoved) {
      debugPrint('[AdService] interstitial blocked: ads removed');
      return false;
    }
    if (!_initialized) {
      debugPrint('[AdService] interstitial blocked: SDK not yet initialized');
      return false;
    }

    final ad = _interstitialCache;
    if (ad == null) {
      debugPrint('[AdService] interstitial blocked: no cached ad - '
          'kicking another preload');
      _preloadInterstitial();
      return false;
    }

    debugPrint('[AdService] interstitial showing (trigger=$trigger)');
    _interstitialCache = null;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _preloadInterstitial();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        a.dispose();
        _preloadInterstitial();
        debugPrint('[AdService] interstitial show failed: $err');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    try {
      await ad.show();
    } catch (e) {
      _preloadInterstitial();
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  void _preloadRewarded() {
    if (_loadingRewarded || _rewardedCache != null) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedCache = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (err) {
          _loadingRewarded = false;
          debugPrint('[AdService] rewarded load failed: $err');
        },
      ),
    );
  }

  /// Show a rewarded ad. The returned future resolves with `true` if the
  /// user finished watching and earned the reward.
  Future<bool> showRewarded({String? trigger}) async {
    if (!_initialized) return false;
    final ad = _rewardedCache;
    if (ad == null) {
      _preloadRewarded();
      return false;
    }
    _rewardedCache = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _preloadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        a.dispose();
        _preloadRewarded();
        debugPrint('[AdService] rewarded show failed: $err');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
    } catch (e) {
      _preloadRewarded();
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  bool get rewardedReady => _initialized && _rewardedCache != null;
}
