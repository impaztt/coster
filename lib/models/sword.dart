import 'package:flutter/material.dart';

enum SwordTier { n, r, sr, ssr, lr, ur }

const swordFormationSlotCount = 5;

extension SwordTierInfo on SwordTier {
  String get label => switch (this) {
        SwordTier.n => 'N',
        SwordTier.r => 'R',
        SwordTier.sr => 'SR',
        SwordTier.ssr => 'SSR',
        SwordTier.lr => 'LR',
        SwordTier.ur => 'UR',
      };

  String get korLabel => switch (this) {
        SwordTier.n => '일반',
        SwordTier.r => '희귀',
        SwordTier.sr => '초희귀',
        SwordTier.ssr => '전설',
        SwordTier.lr => '영웅',
        SwordTier.ur => '신화',
      };

  Color get color => switch (this) {
        SwordTier.n => const Color(0xFF9E9E9E),
        SwordTier.r => const Color(0xFF42A5F5),
        SwordTier.sr => const Color(0xFFAB47BC),
        SwordTier.ssr => const Color(0xFFFFB300),
        SwordTier.lr => const Color(0xFF26A69A),
        SwordTier.ur => const Color(0xFFEF5350),
      };

  /// Roll rate as a percent (sum = 100).
  double get rate => switch (this) {
        SwordTier.n => 55,
        SwordTier.r => 25,
        SwordTier.sr => 11,
        SwordTier.ssr => 6,
        SwordTier.lr => 2,
        SwordTier.ur => 1,
      };

  /// Per-copy passive bonus a sword of this tier contributes to BOTH tap
  /// power and DPS just by being owned (Lv 1, before level scaling). The
  /// idea: collecting feels rewarding even before you equip, but equipping
  /// is still meaningfully better thanks to the big base multipliers.
  double get ownedBonusBase => switch (this) {
        // Baseline is doubled versus previous tuning.
        SwordTier.n => 0.010,
        SwordTier.r => 0.024,
        SwordTier.sr => 0.050,
        SwordTier.ssr => 0.100,
        SwordTier.lr => 0.200,
        SwordTier.ur => 0.360,
      };

  /// Per-level scaling for the passive collection bonus.
  /// Higher tiers scale a bit harder so rare pickups feel more impactful.
  double get ownedBonusLevelStep => switch (this) {
        SwordTier.n => 0.10,
        SwordTier.r => 0.11,
        SwordTier.sr => 0.12,
        SwordTier.ssr => 0.13,
        SwordTier.lr => 0.14,
        SwordTier.ur => 0.15,
      };
}

enum SwordFormationRole { vanguard, striker, support, trader, anchor }

extension SwordFormationRoleInfo on SwordFormationRole {
  String get label => switch (this) {
        SwordFormationRole.vanguard => '선봉',
        SwordFormationRole.striker => '강습',
        SwordFormationRole.support => '지원',
        SwordFormationRole.trader => '상권',
        SwordFormationRole.anchor => '축',
      };

  String get description => switch (this) {
        SwordFormationRole.vanguard => '터치 성장에 강한 착용 역할',
        SwordFormationRole.striker => '터치와 DPS를 함께 올리는 역할',
        SwordFormationRole.support => 'DPS 성장에 강한 착용 역할',
        SwordFormationRole.trader => '검세권과 배당 성장에 강한 역할',
        SwordFormationRole.anchor => '전체 보너스를 안정적으로 받쳐주는 역할',
      };

  IconData get icon => switch (this) {
        SwordFormationRole.vanguard => Icons.shield,
        SwordFormationRole.striker => Icons.flash_on,
        SwordFormationRole.support => Icons.bolt,
        SwordFormationRole.trader => Icons.store,
        SwordFormationRole.anchor => Icons.adjust,
      };

  Color get color => switch (this) {
        SwordFormationRole.vanguard => const Color(0xFFD32F2F),
        SwordFormationRole.striker => const Color(0xFFFF8A65),
        SwordFormationRole.support => const Color(0xFF26A69A),
        SwordFormationRole.trader => const Color(0xFF7C4DFF),
        SwordFormationRole.anchor => const Color(0xFF455A64),
      };
}

enum SparkleStyle { none, dim, bright, orbiting }

/// Distinct silhouette categories used by the sword painter. Default is
/// [SwordShape.longsword] so existing catalog entries that don't specify a
/// shape keep rendering identically to before this enum existed.
enum SwordShape { dagger, longsword, claymore, katana, rapier, falchion }

extension SwordShapeInfo on SwordShape {
  String get korLabel => switch (this) {
        SwordShape.dagger => '단검',
        SwordShape.longsword => '장검',
        SwordShape.claymore => '대검',
        SwordShape.katana => '도',
        SwordShape.rapier => '세검',
        SwordShape.falchion => '곡도',
      };
}

class SwordVisual {
  final Color bladeColor;
  final Color bladeAccent;
  final Color guardColor;
  final Color handleColor;
  final Color pommelColor;
  final Color auraColor;
  final double auraIntensity;
  final SparkleStyle sparkle;
  final SwordShape shape;

  const SwordVisual({
    required this.bladeColor,
    required this.bladeAccent,
    required this.guardColor,
    required this.handleColor,
    required this.pommelColor,
    required this.auraColor,
    this.auraIntensity = 0.3,
    this.sparkle = SparkleStyle.none,
    this.shape = SwordShape.longsword,
  });
}

class SwordDef {
  static const maxLevel = 10;

  final String id;
  final String name;
  final String description;
  final SwordTier tier;
  final double baseTapMult;
  final double baseDpsMult;
  final SwordVisual visual;
  final String? setId;
  final String? eventTag;

  const SwordDef({
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

  /// Passive collection bonus contributed while this sword is owned (even
  /// when not equipped). Returns a fraction (e.g. 0.05 = +5%). Scales the
  /// tier base by a tier-specific level curve, so high-rarity upgrades feel
  /// meaningfully stronger in the collection system.
  double ownedBonusAt(int level) =>
      tier.ownedBonusBase *
      (1 + (level.clamp(1, maxLevel) - 1) * tier.ownedBonusLevelStep);
}
