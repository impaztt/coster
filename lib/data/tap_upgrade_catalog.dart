import 'package:flutter/material.dart';
import '../models/tap_upgrade.dart';

// IDs are deliberately preserved so existing achievements, save data, and
// progression keep working. Only display fields reflect the current
// coaster-park operations theme. Cost curves and per-level tap-income numbers
// are untouched.

const tapUpgradeCatalog = <TapUpgradeDef>[
  TapUpgradeDef(
    id: 'sharper_blade',
    name: '빠른 티켓팅',
    description: '탭당 골드 +1',
    icon: Icons.confirmation_number,
    accent: Color(0xFF90CAF9),
    baseCost: 25,
    tapPowerPerLevel: 1,
  ),
  TapUpgradeDef(
    id: 'magic_infusion',
    name: '효율 큐 관리',
    description: '탭당 골드 +5',
    icon: Icons.checklist_rtl,
    accent: Color(0xFFCE93D8),
    baseCost: 250,
    tapPowerPerLevel: 5,
  ),
  TapUpgradeDef(
    id: 'coaster_aura',
    name: '정밀 안전 점검',
    description: '탭당 골드 +25',
    icon: Icons.verified,
    accent: Color(0xFFFFD54F),
    baseCost: 2500,
    tapPowerPerLevel: 25,
  ),
  TapUpgradeDef(
    id: 'divine_strike',
    name: '정시 출발 시스템',
    description: '탭당 골드 +100',
    icon: Icons.alarm_on,
    accent: Color(0xFFFFAB91),
    baseCost: 25000,
    tapPowerPerLevel: 100,
  ),
  TapUpgradeDef(
    id: 'legendary_swing',
    name: 'VIP 패스 발급',
    description: '탭당 골드 +500',
    icon: Icons.workspace_premium,
    accent: Color(0xFFEF5350),
    baseCost: 250000,
    tapPowerPerLevel: 500,
  ),
  TapUpgradeDef(
    id: 'mythic_resonance',
    name: '자동 게이트',
    description: '탭당 골드 +2,500',
    icon: Icons.sensor_door,
    accent: Color(0xFFB39DDB),
    baseCost: 2500000,
    tapPowerPerLevel: 2500,
  ),
  TapUpgradeDef(
    id: 'void_edge',
    name: '디지털 티켓',
    description: '탭당 골드 +12,500',
    icon: Icons.qr_code_2,
    accent: Color(0xFF9575CD),
    baseCost: 25000000,
    tapPowerPerLevel: 12500,
  ),
  TapUpgradeDef(
    id: 'starfall_slash',
    name: '스마트 큐 라인',
    description: '탭당 골드 +62,500',
    icon: Icons.timeline,
    accent: Color(0xFFFFCC80),
    baseCost: 250000000,
    tapPowerPerLevel: 62500,
  ),
  TapUpgradeDef(
    id: 'fate_sever',
    name: '자동 운영 시스템',
    description: '탭당 골드 +312,500',
    icon: Icons.smart_toy,
    accent: Color(0xFFFF8A65),
    baseCost: 2500000000,
    tapPowerPerLevel: 312500,
  ),
  TapUpgradeDef(
    id: 'origin_cleave',
    name: '양자 디스패치',
    description: '탭당 골드 +1,562,500',
    icon: Icons.scatter_plot,
    accent: Color(0xFFFFB74D),
    baseCost: 25000000000,
    tapPowerPerLevel: 1562500,
  ),
  TapUpgradeDef(
    id: 'eternal_rift',
    name: '영원의 운영',
    description: '탭당 골드 +7,812,500',
    icon: Icons.all_inclusive,
    accent: Color(0xFFEF9A9A),
    baseCost: 250000000000,
    tapPowerPerLevel: 7812500,
  ),
];
