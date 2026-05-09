import 'dart:math' as math;
import 'dart:ui';

import '../models/sword.dart';

/// Main sword has 50 enhancement stages grouped into 10 visual tiers, each
/// 5 substages wide. The "look" of the sword is built parametrically from
/// the tier (which sets a base palette + silhouette) and the substage
/// position inside that tier (which dials saturation / aura / sparkle up).
///
/// This means we never hand-author 50 separate visuals; each tier is a
/// theme and the engine interpolates within it.
class MainSwordTier {
  final int index; // 0-based
  final String name;
  final String description;
  final SwordShape shape;
  final Color blade;
  final Color bladeAccent;
  final Color guard;
  final Color handle;
  final Color pommel;
  final Color aura;
  final SparkleStyle sparkle;
  final double auraIntensityBase;
  final double auraIntensityPeak;
  final bool floats; // sword bobs vertically (cosmetic)
  final bool screenVignette;
  final bool screenFlashOnTap;

  const MainSwordTier({
    required this.index,
    required this.name,
    required this.description,
    required this.shape,
    required this.blade,
    required this.bladeAccent,
    required this.guard,
    required this.handle,
    required this.pommel,
    required this.aura,
    required this.sparkle,
    this.auraIntensityBase = 0.15,
    this.auraIntensityPeak = 0.45,
    this.floats = false,
    this.screenVignette = false,
    this.screenFlashOnTap = false,
  });
}

const mainSwordTiers = <MainSwordTier>[
  // T1 +1~+5
  MainSwordTier(
    index: 0,
    name: '녹슨 검',
    description: '오래 잠들어 있던 시작의 검',
    shape: SwordShape.longsword,
    blade: Color(0xFF8D6E63),
    bladeAccent: Color(0xFF5D4037),
    guard: Color(0xFF6D4C41),
    handle: Color(0xFF3E2723),
    pommel: Color(0xFF8D6E63),
    aura: Color(0xFF8D6E63),
    sparkle: SparkleStyle.none,
    auraIntensityBase: 0.05,
    auraIntensityPeak: 0.2,
  ),
  // T2 +6~+10
  MainSwordTier(
    index: 1,
    name: '강철검',
    description: '제련을 마친 단단한 검',
    shape: SwordShape.longsword,
    blade: Color(0xFFECEFF1),
    bladeAccent: Color(0xFF90A4AE),
    guard: Color(0xFFB0BEC5),
    handle: Color(0xFF4E342E),
    pommel: Color(0xFFCFD8DC),
    aura: Color(0xFFE3F2FD),
    sparkle: SparkleStyle.dim,
    auraIntensityBase: 0.18,
    auraIntensityPeak: 0.35,
  ),
  // T3 +11~+15
  MainSwordTier(
    index: 2,
    name: '룬 검',
    description: '고대 룬어가 깃든 검',
    shape: SwordShape.longsword,
    blade: Color(0xFFB39DDB),
    bladeAccent: Color(0xFF4527A0),
    guard: Color(0xFF311B92),
    handle: Color(0xFF1A237E),
    pommel: Color(0xFF7E57C2),
    aura: Color(0xFF7C4DFF),
    sparkle: SparkleStyle.bright,
    auraIntensityBase: 0.30,
    auraIntensityPeak: 0.55,
  ),
  // T4 +16~+20
  MainSwordTier(
    index: 3,
    name: '화염검',
    description: '꺼지지 않는 불꽃이 깃들었다',
    shape: SwordShape.falchion,
    blade: Color(0xFFFFAB91),
    bladeAccent: Color(0xFFD84315),
    guard: Color(0xFFBF360C),
    handle: Color(0xFF3E2723),
    pommel: Color(0xFFFF5722),
    aura: Color(0xFFFF5722),
    sparkle: SparkleStyle.bright,
    auraIntensityBase: 0.40,
    auraIntensityPeak: 0.70,
  ),
  // T5 +21~+25
  MainSwordTier(
    index: 4,
    name: '빙결검',
    description: '숨이 닿는 모든 것을 얼린다',
    shape: SwordShape.katana,
    blade: Color(0xFFB3E5FC),
    bladeAccent: Color(0xFF0288D1),
    guard: Color(0xFF01579B),
    handle: Color(0xFF002F6C),
    pommel: Color(0xFF81D4FA),
    aura: Color(0xFF03A9F4),
    sparkle: SparkleStyle.bright,
    auraIntensityBase: 0.45,
    auraIntensityPeak: 0.75,
  ),
  // T6 +26~+30
  MainSwordTier(
    index: 5,
    name: '뇌전검',
    description: '검 끝에서 번개가 흐른다',
    shape: SwordShape.rapier,
    blade: Color(0xFFFFF59D),
    bladeAccent: Color(0xFFFBC02D),
    guard: Color(0xFFF57F17),
    handle: Color(0xFF6D4C41),
    pommel: Color(0xFFFFD600),
    aura: Color(0xFFFFEB3B),
    sparkle: SparkleStyle.orbiting,
    auraIntensityBase: 0.50,
    auraIntensityPeak: 0.80,
  ),
  // T7 +31~+35
  MainSwordTier(
    index: 6,
    name: '신성검',
    description: '하늘이 인정한 자만이 휘두를 수 있는',
    shape: SwordShape.claymore,
    blade: Color(0xFFFFFDE7),
    bladeAccent: Color(0xFFFFD54F),
    guard: Color(0xFFFFCA28),
    handle: Color(0xFFFFFFFF),
    pommel: Color(0xFFFFC107),
    aura: Color(0xFFFFEB3B),
    sparkle: SparkleStyle.orbiting,
    auraIntensityBase: 0.60,
    auraIntensityPeak: 0.90,
  ),
  // T8 +36~+40
  MainSwordTier(
    index: 7,
    name: '마룡검',
    description: '검은 안개를 휘감고 떠오른다',
    shape: SwordShape.falchion,
    blade: Color(0xFF263238),
    bladeAccent: Color(0xFFB71C1C),
    guard: Color(0xFF1A1A1A),
    handle: Color(0xFF000000),
    pommel: Color(0xFFD32F2F),
    aura: Color(0xFFB71C1C),
    sparkle: SparkleStyle.orbiting,
    auraIntensityBase: 0.70,
    auraIntensityPeak: 0.95,
    floats: true,
  ),
  // T9 +41~+45
  MainSwordTier(
    index: 8,
    name: '천공검',
    description: '별빛을 따라 호흡하는 검',
    shape: SwordShape.claymore,
    blade: Color(0xFFE3F2FD),
    bladeAccent: Color(0xFF42A5F5),
    guard: Color(0xFF1565C0),
    handle: Color(0xFF0D47A1),
    pommel: Color(0xFF90CAF9),
    aura: Color(0xFF7C4DFF),
    sparkle: SparkleStyle.orbiting,
    auraIntensityBase: 0.80,
    auraIntensityPeak: 1.00,
    floats: true,
    screenVignette: true,
  ),
  // T10 +46~+50
  MainSwordTier(
    index: 9,
    name: '창세검',
    description: '세상을 처음 가른 검',
    shape: SwordShape.claymore,
    blade: Color(0xFFFFFFFF),
    bladeAccent: Color(0xFFE1BEE7),
    guard: Color(0xFFFFD54F),
    handle: Color(0xFFFFFFFF),
    pommel: Color(0xFFE91E63),
    aura: Color(0xFF7C4DFF),
    sparkle: SparkleStyle.orbiting,
    auraIntensityBase: 0.95,
    auraIntensityPeak: 1.00,
    floats: true,
    screenVignette: true,
    screenFlashOnTap: true,
  ),
];

const mainSwordMaxStage = 50;
const mainSwordTierSize = 5;

int mainSwordTierIndex(int stage) {
  if (stage <= 0) return 0;
  return ((stage - 1) ~/ mainSwordTierSize).clamp(0, mainSwordTiers.length - 1);
}

double mainSwordIntraTierProgress(int stage) {
  if (stage <= 0) return 0;
  final into = ((stage - 1) % mainSwordTierSize) + 1;
  return into / mainSwordTierSize;
}

MainSwordTier mainSwordTierFor(int stage) =>
    mainSwordTiers[mainSwordTierIndex(stage)];

/// Resolve a stage to a [SwordVisual] used by the renderer. Within a tier
/// we interpolate aura intensity to give every substage a slightly different
/// look without authoring 50 distinct entries.
SwordVisual mainSwordVisualFor(int stage) {
  final tier = mainSwordTierFor(stage);
  final t = mainSwordIntraTierProgress(stage);
  final auraIntensity = lerpDouble(
        tier.auraIntensityBase,
        tier.auraIntensityPeak,
        t,
      ) ??
      tier.auraIntensityBase;
  return SwordVisual(
    bladeColor: tier.blade,
    bladeAccent: tier.bladeAccent,
    guardColor: tier.guard,
    handleColor: tier.handle,
    pommelColor: tier.pommel,
    auraColor: tier.aura,
    auraIntensity: auraIntensity,
    sparkle: tier.sparkle,
    shape: tier.shape,
  );
}

/// Sparkle "extra" count layered on top of the base sparkle painter, scaled
/// by absolute stage (0..50).
int mainSwordSparkleExtras(int stage) {
  if (stage <= 0) return 0;
  return math.min(12, stage ~/ 4);
}
