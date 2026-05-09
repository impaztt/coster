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
  static const monthlyTicketPass = 'premium_monthly_ticket_pass';
  static const starterPackage = 'premium_starter_package';

  // Phase 1: Entry tier
  static const firstPurchase = 'premium_first_purchase';
  static const ticketSmall = 'premium_essence_small';
  static const ticketMedium = 'premium_essence_medium';

  // Phase 2: Core tier
  static const ticketLarge = 'premium_essence_large';

  // Phase 3: Whale tier
  static const ticketXLarge = 'premium_essence_xlarge';
  static const masterPackage = 'premium_master_package';
  static const seasonPass = 'premium_season_pass';

  /// Full ID set used to bulk-load product details from the store.
  static const allProductIds = <String>{
    adRemoval,
    monthlyTicketPass,
    starterPackage,
    firstPurchase,
    ticketSmall,
    ticketMedium,
    ticketLarge,
    ticketXLarge,
    masterPackage,
    seasonPass,
  };
}
