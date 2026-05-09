import '../models/sword.dart';
import 'region_catalog.dart';
import 'sword_catalog.dart';

/// Signature metadata for "검세권" and equipped formation.
///
/// The catalog already contains many fantasy swords, so this layer gives every
/// sword a permanent regional base and a formation role without rewriting the
/// whole sword table. The distribution is deterministic from catalog order and
/// tier, which keeps existing saves stable as long as ids remain stable.
final Map<String, String> swordRegionAffinities = () {
  final map = <String, String>{};
  for (var i = 0; i < swordCatalog.length; i++) {
    final sword = swordCatalog[i];
    final regionIndex = (i * 7 + sword.tier.index * 3) % regionCatalog.length;
    map[sword.id] = regionCatalog[regionIndex].id;
  }
  return Map<String, String>.unmodifiable(map);
}();

final Map<String, SwordFormationRole> swordFormationRoles = () {
  const roles = SwordFormationRole.values;
  final map = <String, SwordFormationRole>{};
  for (var i = 0; i < swordCatalog.length; i++) {
    final sword = swordCatalog[i];
    final roleIndex = (i + sword.tier.index * 2) % roles.length;
    map[sword.id] = roles[roleIndex];
  }
  return Map<String, SwordFormationRole>.unmodifiable(map);
}();

String swordRegionId(SwordDef sword) =>
    swordRegionAffinities[sword.id] ?? regionCatalog.first.id;

RegionDef swordHomeRegion(SwordDef sword) =>
    regionDefById(swordRegionId(sword));

SwordFormationRole swordFormationRole(SwordDef sword) =>
    swordFormationRoles[sword.id] ?? SwordFormationRole.striker;

List<SwordDef> swordsForRegion(String regionId) => [
      for (final sword in swordCatalog)
        if (swordRegionId(sword) == regionId) sword,
    ];

int ownedSwordCountForRegion(String regionId, Map<String, int> ownedSwords) {
  var count = 0;
  for (final sword in swordsForRegion(regionId)) {
    if ((ownedSwords[sword.id] ?? 0) > 0) count++;
  }
  return count;
}

int totalSwordCountForRegion(String regionId) =>
    swordsForRegion(regionId).length;
