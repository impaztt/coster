import 'package:flutter/material.dart';

import '../models/skill.dart';

const skillCatalog = <SkillDef>[
  SkillDef(
    id: SkillId.slashBurst,
    name: '검기 폭발',
    description: '즉시 골드 = 현재 DPS × 5분',
    icon: Icons.flash_on,
    color: Color(0xFFFFB300),
    cooldown: Duration(minutes: 30),
  ),
  SkillDef(
    id: SkillId.comboSurge,
    name: '콤보 폭주',
    description: '10초간 콤보가 2씩 쌓이고 보너스 ×2',
    icon: Icons.local_fire_department,
    color: Color(0xFFFF5722),
    cooldown: Duration(minutes: 10),
  ),
  SkillDef(
    id: SkillId.essenceGather,
    name: '정수 모이기',
    description: '즉시 정수 +30',
    icon: Icons.diamond,
    color: Color(0xFF7C4DFF),
    cooldown: Duration(hours: 6),
  ),
];

SkillDef skillDefFor(SkillId id) =>
    skillCatalog.firstWhere((s) => s.id == id);
