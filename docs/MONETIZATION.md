# Monetization Setup (AdMob + IAP)

This game ships with AdMob interstitial/rewarded ads and Google Play in-app
purchases pre-wired. Default configuration uses test ad units and unregistered
product IDs, so you have to swap constants and finish store-side setup before
publishing.

## 1. Application ID

`android/app/build.gradle.kts` currently hard-codes `com.example.sw_clicker`.
Change this to your own package name before uploading the first build to Play
Console. Once published, the package name cannot be renamed.

## 2. AdMob

### 2-1. Create the AdMob app

1. Go to https://admob.google.com -> Apps -> Add app -> Android.
2. Note the App ID. It looks like `ca-app-pub-XXXX~YYYY`.
3. Create two ad units:
   - Interstitial
   - Rewarded
4. Note each ad unit ID. It looks like `ca-app-pub-XXXX/ZZZZ`.

### 2-2. Wire the IDs into the project

- `android/app/src/main/AndroidManifest.xml`: replace the
  `com.google.android.gms.ads.APPLICATION_ID` meta-data value with your real
  App ID.
- `lib/core/ad_config.dart`: fill in `_prodInterstitialAndroid`,
  `_prodRewardedAndroid`, and the iOS variants when iOS lands, then flip
  `_useProdAds` to `true`.

### 2-3. Add test devices for QA

In `lib/core/ad_config.dart`, append physical test device IDs to
`testDeviceIds`. Get the ID from logcat after your first ad request. The SDK
prints a line like:

```text
Use RequestConfiguration.Builder.setTestDeviceIds(["XXXXXXXX..."])
```

Devices listed here always see test ads even when `_useProdAds` is true.

### 2-4. Account requirements before going live

- Verify payment and tax info in the AdMob dashboard.
- Add a privacy policy URL. Play Console requires it for apps with ads.
- For Korean publishers, register the app's age rating.

## 3. In-App Purchases

### 3-1. Register products in Play Console

Go to Play Console -> Monetize -> Products -> In-app products and create each
ID below with the corresponding price tier. The IDs must match
`lib/core/iap_config.dart` exactly.

| Product ID | Price (KRW) | Type |
|---|---|---|
| `premium_ad_removal` | 4,900 | Non-consumable |
| `premium_monthly_essence_pass` | 5,900 | Consumable |
| `premium_starter_package` | 4,900 | Non-consumable |
| `premium_first_purchase` | 1,100 | Non-consumable |
| `premium_essence_small` | 1,100 | Consumable |
| `premium_essence_medium` | 3,300 | Consumable |
| `premium_essence_large` | 9,900 | Consumable |
| `premium_essence_xlarge` | 19,900 | Consumable |
| `premium_master_package` | 49,900 | Non-consumable |
| `premium_season_pass` | 14,900 | Consumable |

Activate each product after registering. Inactive products will not load.

### 3-2. Closed testing

Add yourself as a license tester in Play Console settings. License testers get
free real-money flows for QA.

### 3-3. Server-side validation

The current implementation grants entitlements client-side after the IAP plugin
returns `purchased` or `restored`. For a hardened production setup, add Google
Play Developer API receipt validation server-side and gate
`purchasePremiumProduct(...)` on a backend acknowledgement.

## 4. Forced Interstitial Cadence

Forced interstitials are triggered by actual bottom-tab changes only.
`AdConfig.tabSwitchesPerInterstitial` controls the count and is currently set
to 10. If an interstitial is not ready at the threshold, the count is retained
and the next tab change retries.

Rewarded ads have no system-wide cap because they are opt-in. Per-slot caps
live in the dialog that calls `AdService.showRewarded`.

## 5. Pre-launch Checklist

- [ ] `applicationId` changed from `com.example.*` to your own
- [ ] AdMob App ID swapped in AndroidManifest.xml
- [ ] Both prod ad-unit IDs filled in `ad_config.dart`
- [ ] `_useProdAds = true` in `ad_config.dart`
- [ ] All 10 IAP products registered and active in Play Console
- [ ] License testers added for QA
- [ ] Privacy policy URL filled in Play Console listing
- [ ] AdMob payment and tax info verified
- [ ] Age rating questionnaire completed
- [ ] Closed testing track ran a full purchase flow end-to-end
