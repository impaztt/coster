import 'package:flutter/material.dart';

enum SkillId {
  slashBurst('slash_burst'),
  essenceGather('essence_gather'),
  comboSurge('combo_surge');

  final String id;
  const SkillId(this.id);

  static SkillId? fromId(String id) {
    for (final v in SkillId.values) {
      if (v.id == id) return v;
    }
    return null;
  }
}

class SkillDef {
  final SkillId id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final Duration cooldown;

  const SkillDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.cooldown,
  });
}
