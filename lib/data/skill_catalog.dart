import 'package:flutter/material.dart';

import '../models/skill.dart';

const skillCatalog = <SkillDef>[
  SkillDef(
    id: SkillId.slashBurst,
    name: '퍼레이드 피버',
    description: '즉시 골드 = 현재 초당 수익 × 5분',
    icon: Icons.flash_on,
    color: Color(0xFFFFB300),
    // §3.7 v2 — restored to 30 minutes. v1 temporarily shortened this
    // 30→15 while no instant-fire channel existed; with tokens shipping
    // in v2, the cooldown returns to its original 30 and tokens carry
    // the "I need this NOW" lane instead.
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
    id: SkillId.ticketGather,
    name: '티켓 모으기',
    description: '즉시 티켓 +30',
    icon: Icons.diamond,
    color: Color(0xFF7C4DFF),
    cooldown: Duration(hours: 6),
  ),
];

SkillDef skillDefFor(SkillId id) => skillCatalog.firstWhere((s) => s.id == id);
