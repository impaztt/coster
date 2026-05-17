import 'coaster_affinities.dart';
import 'region_catalog.dart';

/// §3.3 Park Theme — collection-style bonus tied to owning coasters whose
/// regional affinity matches each region. Designed as an *additive* layer
/// piggy-backing on the §3.1 v1 ADD pool, NOT a new multiplicative layer,
/// so it can't compound with the rest of the stack into the snowball that
/// §3.1 was written to dampen.
///
/// **Sizing rationale (why these numbers):**
/// - 66 coasters split across 17 regions ≈ 4 per region on average.
/// - Milestones at 1 / 3 / 5 / ALL cover both light-roster and completed
///   regions, with ALL absorbing per-region count variance.
/// - Per-step adds: 0.2 / 0.4 / 0.6 / 1.0 percentage points to the pool,
///   max +2.2% per region. With 17 regions the theoretical ceiling is
///   ~+37.4%, but a realistic mid-game roster (~half the catalog) lands
///   near +10-15% — meaningful but well under the §3.1 v1 brake budget.
class RegionThemeMilestone {
  final int requiredCoasters; // -1 means "all coasters in that region"
  final double bonusFraction;
  const RegionThemeMilestone({
    required this.requiredCoasters,
    required this.bonusFraction,
  });
}

const regionThemeMilestones = <RegionThemeMilestone>[
  RegionThemeMilestone(requiredCoasters: 1, bonusFraction: 0.002),
  RegionThemeMilestone(requiredCoasters: 3, bonusFraction: 0.004),
  RegionThemeMilestone(requiredCoasters: 5, bonusFraction: 0.006),
  RegionThemeMilestone(requiredCoasters: -1, bonusFraction: 0.010), // ALL
];

/// How many of [regionThemeMilestones] have been cleared for [regionId]
/// given the player's owned-coaster map. ALL counts as cleared only when
/// the region actually has any coasters at all (defensive).
int regionThemeMilestonesCleared(
    String regionId, Map<String, int> ownedCoasters) {
  final owned = ownedCoasterCountForRegion(regionId, ownedCoasters);
  final total = totalCoasterCountForRegion(regionId);
  var cleared = 0;
  for (final m in regionThemeMilestones) {
    final threshold = m.requiredCoasters < 0 ? total : m.requiredCoasters;
    if (total <= 0) continue;
    if (owned >= threshold) cleared++;
  }
  return cleared;
}

/// Accumulated park-theme bonus fraction for [regionId] — sum of every
/// milestone the player has cleared.
double regionThemeBonusFraction(
    String regionId, Map<String, int> ownedCoasters) {
  final owned = ownedCoasterCountForRegion(regionId, ownedCoasters);
  final total = totalCoasterCountForRegion(regionId);
  if (total <= 0) return 0;
  var bonus = 0.0;
  for (final m in regionThemeMilestones) {
    final threshold = m.requiredCoasters < 0 ? total : m.requiredCoasters;
    if (owned >= threshold) bonus += m.bonusFraction;
  }
  return bonus;
}

/// Total park-theme bonus across all regions — wired into the §3.1 v1 ADD
/// pool inside game_provider so it stacks additively, not multiplicatively.
double totalParkThemeBonusFraction(Map<String, int> ownedCoasters) {
  var total = 0.0;
  for (final region in regionCatalog) {
    total += regionThemeBonusFraction(region.id, ownedCoasters);
  }
  return total;
}
