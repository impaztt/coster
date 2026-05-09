/// Sword set definitions. Owning every member of a set grants the
/// listed bonuses globally (multiplicative on tap and/or DPS).
class SwordSet {
  final String id;
  final String name;
  final String description;
  final List<String> swordIds;
  final double dpsBonus; // 0.10 = +10%
  final double tapBonus;

  const SwordSet({
    required this.id,
    required this.name,
    required this.description,
    required this.swordIds,
    this.dpsBonus = 0,
    this.tapBonus = 0,
  });
}

const swordSets = <SwordSet>[
  SwordSet(
    id: 'iron_path',
    name: '강철의 길',
    description: '평범한 검들의 정점',
    swordIds: [
      'iron_shortsword',
      'iron_longsword',
      'steel_blade',
      'silvered_blade',
    ],
    tapBonus: 0.05,
    dpsBonus: 0.05,
  ),
  SwordSet(
    id: 'elements',
    name: '원소의 정수',
    description: '불·물·바람·번개·대지를 한자리에',
    swordIds: [
      'flame_blade',
      'frost_edge',
      'thunder_slicer',
      'wind_slicer',
      'verdant_blade',
    ],
    dpsBonus: 0.12,
    tapBonus: 0.05,
  ),
  SwordSet(
    id: 'celestial_bodies',
    name: '천체의 광휘',
    description: '해, 달, 별을 모두 거느리는 자',
    swordIds: [
      'sun_blade',
      'moon_blade',
      'celestial_blade',
    ],
    dpsBonus: 0.15,
    tapBonus: 0.10,
  ),
  SwordSet(
    id: 'dragons_grace',
    name: '용의 가호',
    description: '고대 용들의 의지가 한데 모였다',
    swordIds: [
      'dragon_tooth',
      'dragon_king',
      'phoenix_blade',
      'leviathan_fang',
    ],
    dpsBonus: 0.20,
    tapBonus: 0.10,
  ),
  SwordSet(
    id: 'legend_heroes',
    name: '전설의 영웅',
    description: '이름만으로도 적이 떨었던 검들',
    swordIds: [
      'hero_excalibur',
      'hero_durandal',
      'hero_gram',
      'hero_kusanagi',
      'hero_balmung',
    ],
    dpsBonus: 0.30,
    tapBonus: 0.20,
  ),
];

SwordSet? swordSetById(String id) {
  for (final s in swordSets) {
    if (s.id == id) return s;
  }
  return null;
}

/// Set id → set, indexed for fast lookup of which set a sword belongs to.
final Map<String, SwordSet> _setsBySwordId = () {
  final m = <String, SwordSet>{};
  for (final s in swordSets) {
    for (final id in s.swordIds) {
      m[id] = s;
    }
  }
  return m;
}();

SwordSet? swordSetForSwordId(String id) => _setsBySwordId[id];
