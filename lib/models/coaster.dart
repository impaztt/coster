import 'package:flutter/material.dart';

enum CoasterTier { n, r, sr, ssr, lr, ur }

const coasterFormationSlotCount = 5;

extension CoasterTierInfo on CoasterTier {
  String get label => switch (this) {
        CoasterTier.n => 'N',
        CoasterTier.r => 'R',
        CoasterTier.sr => 'SR',
        CoasterTier.ssr => 'SSR',
        CoasterTier.lr => 'LR',
        CoasterTier.ur => 'UR',
      };

  String get korLabel => switch (this) {
        CoasterTier.n => '일반',
        CoasterTier.r => '희귀',
        CoasterTier.sr => '초희귀',
        CoasterTier.ssr => '전설',
        CoasterTier.lr => '영웅',
        CoasterTier.ur => '신화',
      };

  Color get color => switch (this) {
        CoasterTier.n => const Color(0xFF9E9E9E),
        CoasterTier.r => const Color(0xFF42A5F5),
        CoasterTier.sr => const Color(0xFFAB47BC),
        CoasterTier.ssr => const Color(0xFFFFB300),
        CoasterTier.lr => const Color(0xFF26A69A),
        CoasterTier.ur => const Color(0xFFEF5350),
      };

  /// Roll rate as a percent (sum = 100).
  double get rate => switch (this) {
        CoasterTier.n => 55,
        CoasterTier.r => 25,
        CoasterTier.sr => 11,
        CoasterTier.ssr => 6,
        CoasterTier.lr => 2,
        CoasterTier.ur => 1,
      };

  /// Per-copy passive bonus a coaster of this tier contributes to BOTH tap
  /// power and auto revenue just by being owned (Lv 1, before level scaling).
  /// idea: collecting feels rewarding even before you equip, but equipping
  /// is still meaningfully better thanks to the big base multipliers.
  double get ownedBonusBase => switch (this) {
        // Baseline is doubled versus previous tuning.
        CoasterTier.n => 0.010,
        CoasterTier.r => 0.024,
        CoasterTier.sr => 0.050,
        CoasterTier.ssr => 0.100,
        CoasterTier.lr => 0.200,
        CoasterTier.ur => 0.360,
      };

  /// Per-level scaling for the passive collection bonus.
  /// Higher tiers scale a bit harder so rare pickups feel more impactful.
  double get ownedBonusLevelStep => switch (this) {
        CoasterTier.n => 0.10,
        CoasterTier.r => 0.11,
        CoasterTier.sr => 0.12,
        CoasterTier.ssr => 0.13,
        CoasterTier.lr => 0.14,
        CoasterTier.ur => 0.15,
      };
}

enum CoasterFormationRole { vanguard, striker, support, trader, anchor }

extension CoasterFormationRoleInfo on CoasterFormationRole {
  String get label => switch (this) {
        CoasterFormationRole.vanguard => '입구',
        CoasterFormationRole.striker => '스릴',
        CoasterFormationRole.support => '운영',
        CoasterFormationRole.trader => '상권',
        CoasterFormationRole.anchor => '대표',
      };

  String get description => switch (this) {
        CoasterFormationRole.vanguard => '탭 매출 성장에 강한 배치 역할',
        CoasterFormationRole.striker => '탭 매출과 방치 수익을 함께 올리는 역할',
        CoasterFormationRole.support => '방치 수익 성장에 강한 배치 역할',
        CoasterFormationRole.trader => '지역 인지도와 배당 성장에 강한 역할',
        CoasterFormationRole.anchor => '전체 보너스를 안정적으로 받쳐주는 대표 역할',
      };

  IconData get icon => switch (this) {
        CoasterFormationRole.vanguard => Icons.shield,
        CoasterFormationRole.striker => Icons.flash_on,
        CoasterFormationRole.support => Icons.bolt,
        CoasterFormationRole.trader => Icons.store,
        CoasterFormationRole.anchor => Icons.adjust,
      };

  Color get color => switch (this) {
        CoasterFormationRole.vanguard => const Color(0xFFD32F2F),
        CoasterFormationRole.striker => const Color(0xFFFF8A65),
        CoasterFormationRole.support => const Color(0xFF26A69A),
        CoasterFormationRole.trader => const Color(0xFF7C4DFF),
        CoasterFormationRole.anchor => const Color(0xFF455A64),
      };
}

enum SparkleStyle { none, dim, bright, orbiting }

/// Distinct silhouette categories used by the coaster painter. Default is
/// [CoasterShape.longcoaster] so existing catalog entries that don't specify a
/// shape keep rendering identically to before this enum existed.
enum CoasterShape { dagger, longcoaster, claymore, katana, rapier, falchion }

extension CoasterShapeInfo on CoasterShape {
  String get korLabel => switch (this) {
        CoasterShape.dagger => '소형 열차',
        CoasterShape.longcoaster => '스틸 트랙',
        CoasterShape.claymore => '하이퍼 트랙',
        CoasterShape.katana => '커브 트랙',
        CoasterShape.rapier => '런치 트랙',
        CoasterShape.falchion => '트위스트 트랙',
      };
}

class CoasterVisual {
  final Color bladeColor;
  final Color bladeAccent;
  final Color guardColor;
  final Color handleColor;
  final Color pommelColor;
  final Color auraColor;
  final double auraIntensity;
  final SparkleStyle sparkle;
  final CoasterShape shape;

  const CoasterVisual({
    required this.bladeColor,
    required this.bladeAccent,
    required this.guardColor,
    required this.handleColor,
    required this.pommelColor,
    required this.auraColor,
    this.auraIntensity = 0.3,
    this.sparkle = SparkleStyle.none,
    this.shape = CoasterShape.longcoaster,
  });
}

class CoasterDef {
  static const maxLevel = 10;

  final String id;
  final String name;
  final String description;
  final CoasterTier tier;
  final double baseTapMult;
  final double baseDpsMult;
  final CoasterVisual visual;
  final String? setId;
  final String? eventTag;

  const CoasterDef({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.baseTapMult,
    this.baseDpsMult = 1.0,
    required this.visual,
    this.setId,
    this.eventTag,
  });

  /// At level L (1~10), effective multiplier = base * (1 + (L-1) * 0.1).
  /// So Lv 1 = base, Lv 10 = 1.9 * base.
  double tapMultAt(int level) =>
      baseTapMult * (1 + (level.clamp(1, maxLevel) - 1) * 0.1);
  double dpsMultAt(int level) =>
      baseDpsMult * (1 + (level.clamp(1, maxLevel) - 1) * 0.1);

  /// Passive collection bonus contributed while this coaster is owned (even
  /// when not equipped). Returns a fraction (e.g. 0.05 = +5%). Scales the
  /// tier base by a tier-specific level curve, so high-rarity upgrades feel
  /// meaningfully stronger in the collection system.
  double ownedBonusAt(int level) =>
      tier.ownedBonusBase *
      (1 + (level.clamp(1, maxLevel) - 1) * tier.ownedBonusLevelStep);
}
