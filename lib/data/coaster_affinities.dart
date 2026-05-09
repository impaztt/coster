import '../models/coaster.dart';
import 'region_catalog.dart';
import 'coaster_catalog.dart';

/// Signature metadata for "검세권" and equipped formation.
///
/// The catalog already contains many fantasy coasters, so this layer gives every
/// coaster a permanent regional base and a formation role without rewriting the
/// whole coaster table. The distribution is deterministic from catalog order and
/// tier, which keeps existing saves stable as long as ids remain stable.
final Map<String, String> coasterRegionAffinities = () {
  final map = <String, String>{};
  for (var i = 0; i < coasterCatalog.length; i++) {
    final coaster = coasterCatalog[i];
    final regionIndex = (i * 7 + coaster.tier.index * 3) % regionCatalog.length;
    map[coaster.id] = regionCatalog[regionIndex].id;
  }
  return Map<String, String>.unmodifiable(map);
}();

final Map<String, CoasterFormationRole> coasterFormationRoles = () {
  const roles = CoasterFormationRole.values;
  final map = <String, CoasterFormationRole>{};
  for (var i = 0; i < coasterCatalog.length; i++) {
    final coaster = coasterCatalog[i];
    final roleIndex = (i + coaster.tier.index * 2) % roles.length;
    map[coaster.id] = roles[roleIndex];
  }
  return Map<String, CoasterFormationRole>.unmodifiable(map);
}();

String coasterRegionId(CoasterDef coaster) =>
    coasterRegionAffinities[coaster.id] ?? regionCatalog.first.id;

RegionDef coasterHomeRegion(CoasterDef coaster) =>
    regionDefById(coasterRegionId(coaster));

CoasterFormationRole coasterFormationRole(CoasterDef coaster) =>
    coasterFormationRoles[coaster.id] ?? CoasterFormationRole.striker;

List<CoasterDef> coastersForRegion(String regionId) => [
      for (final coaster in coasterCatalog)
        if (coasterRegionId(coaster) == regionId) coaster,
    ];

int ownedCoasterCountForRegion(String regionId, Map<String, int> ownedCoasters) {
  var count = 0;
  for (final coaster in coastersForRegion(regionId)) {
    if ((ownedCoasters[coaster.id] ?? 0) > 0) count++;
  }
  return count;
}

int totalCoasterCountForRegion(String regionId) =>
    coastersForRegion(regionId).length;
