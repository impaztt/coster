/// Canonical product IDs for in-app purchases. The strings here MUST match
/// exactly what's registered in Google Play Console (and App Store Connect
/// when iOS lands), or fetching products will silently return an empty
/// list at startup.
///
/// Naming convention: `premium_<short>` — keep IDs lowercase, snake_case,
/// stable forever (you can't rename a published product).
class IapConfig {
  // Existing (already wired through _purchasePremiumProduct)
  static const adRemoval = 'premium_ad_removal';
  static const monthlyEssencePass = 'premium_monthly_essence_pass';
  static const starterPackage = 'premium_starter_package';

  // Phase 1: Entry tier
  static const firstPurchase = 'premium_first_purchase';
  static const essenceSmall = 'premium_essence_small';
  static const essenceMedium = 'premium_essence_medium';

  // Phase 2: Core tier
  static const essenceLarge = 'premium_essence_large';

  // Phase 3: Whale tier
  static const essenceXLarge = 'premium_essence_xlarge';
  static const masterPackage = 'premium_master_package';
  static const seasonPass = 'premium_season_pass';

  /// Full ID set used to bulk-load product details from the store.
  static const allProductIds = <String>{
    adRemoval,
    monthlyEssencePass,
    starterPackage,
    firstPurchase,
    essenceSmall,
    essenceMedium,
    essenceLarge,
    essenceXLarge,
    masterPackage,
    seasonPass,
  };
}
