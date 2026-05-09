/// Coaster set definitions. Owning every member of a set grants the
/// listed bonuses globally (multiplicative on tap and/or DPS).
class CoasterSet {
  final String id;
  final String name;
  final String description;
  final List<String> coasterIds;
  final double dpsBonus; // 0.10 = +10%
  final double tapBonus;

  const CoasterSet({
    required this.id,
    required this.name,
    required this.description,
    required this.coasterIds,
    this.dpsBonus = 0,
    this.tapBonus = 0,
  });
}

const coasterSets = <CoasterSet>[
  CoasterSet(
    id: 'iron_path',
    name: '강철의 길',
    description: '평범한 검들의 정점',
    coasterIds: [
      'iron_shortcoaster',
      'iron_longcoaster',
      'steel_blade',
      'silvered_blade',
    ],
    tapBonus: 0.05,
    dpsBonus: 0.05,
  ),
  CoasterSet(
    id: 'elements',
    name: '원소의 티켓',
    description: '불·물·바람·번개·대지를 한자리에',
    coasterIds: [
      'flame_blade',
      'frost_edge',
      'thunder_slicer',
      'wind_slicer',
      'verdant_blade',
    ],
    dpsBonus: 0.12,
    tapBonus: 0.05,
  ),
  CoasterSet(
    id: 'celestial_bodies',
    name: '천체의 광휘',
    description: '해, 달, 별을 모두 거느리는 자',
    coasterIds: [
      'sun_blade',
      'moon_blade',
      'celestial_blade',
    ],
    dpsBonus: 0.15,
    tapBonus: 0.10,
  ),
  CoasterSet(
    id: 'dragons_grace',
    name: '용의 가호',
    description: '고대 용들의 의지가 한데 모였다',
    coasterIds: [
      'dragon_tooth',
      'dragon_king',
      'phoenix_blade',
      'leviathan_fang',
    ],
    dpsBonus: 0.20,
    tapBonus: 0.10,
  ),
  CoasterSet(
    id: 'legend_heroes',
    name: '전설의 영웅',
    description: '이름만으로도 적이 떨었던 검들',
    coasterIds: [
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

CoasterSet? coasterSetById(String id) {
  for (final s in coasterSets) {
    if (s.id == id) return s;
  }
  return null;
}

/// Set id → set, indexed for fast lookup of which set a coaster belongs to.
final Map<String, CoasterSet> _setsByCoasterId = () {
  final m = <String, CoasterSet>{};
  for (final s in coasterSets) {
    for (final id in s.coasterIds) {
      m[id] = s;
    }
  }
  return m;
}();

CoasterSet? coasterSetForCoasterId(String id) => _setsByCoasterId[id];
