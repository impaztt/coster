/// Coaster set definitions. Owning every member of a set grants the
/// listed bonuses globally (multiplicative on tap and/or 초당 수익).
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
    name: '클래식 파크 라인',
    description: '기본 코스터 라인을 완성한 운영자',
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
    name: '원소 테마 존',
    description: '불·물·바람·번개·대지 테마를 한자리에',
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
    name: '스카이 & 스타 존',
    description: '해, 달, 별빛을 모두 담은 야간 명소',
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
    name: '드래곤 어드벤처',
    description: '고대 용 테마가 한데 모인 스릴 구역',
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
    name: '레전드 어트랙션',
    description: '이름만으로도 손님이 모이는 대표 코스터',
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
