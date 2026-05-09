import 'package:flutter/material.dart';

import '../core/number_format.dart';
import '../data/region_catalog.dart';
import '../data/sword_sets.dart';
import '../providers/game_provider.dart';

/// Feature IDs gated by progression. UI checks
/// [GameState.isFeatureUnlocked] before showing the relevant surface.
class FeatureUnlocks {
  static const summonTab = 'summon_tab';
  static const missionsTab = 'missions_tab';
  static const achievementsTab = 'achievements_tab';
  static const boosterShop = 'booster_shop';
  static const prestigeTab = 'prestige_tab';
  static const swordSetsView = 'sword_sets_view';
  static const stockMarket = 'stock_market';
  static const goldExchange = 'gold_exchange';
}

enum FeatureUnlockProgressKind {
  count,
  gold,
  essence,
}

class FeatureUnlockProgress {
  final double current;
  final double target;
  final FeatureUnlockProgressKind kind;

  const FeatureUnlockProgress({
    required this.current,
    required this.target,
    required this.kind,
  });

  bool get isUnlocked => current >= target;

  double get ratio {
    if (target <= 0) return 1.0;
    final raw = current / target;
    if (raw.isNaN || raw.isInfinite) return 0.0;
    return raw.clamp(0.0, 1.0).toDouble();
  }

  String get percentText => '${(ratio * 100).toStringAsFixed(1)}%';

  String get currentText => _formatValue(current);
  String get targetText => _formatValue(target);
  String get progressText => '$currentText / $targetText';

  String _formatValue(double value) {
    final safe = value.isNaN || value.isInfinite ? 0.0 : value;
    return switch (kind) {
      FeatureUnlockProgressKind.count => NumberFormatter.formatInt(
          safe.floor().clamp(0, 1 << 31).toInt(),
        ),
      FeatureUnlockProgressKind.gold => NumberFormatter.format(safe),
      FeatureUnlockProgressKind.essence => NumberFormatter.formatInt(
          safe.floor().clamp(0, 1 << 31).toInt(),
        ),
    };
  }
}

class FeatureUnlockDef {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool Function(GameState state) trigger;

  /// 로드맵 표시 순서 (낮을수록 먼저 보임)
  final int roadmapOrder;

  /// 해금 조건을 사용자에게 문장으로 보여주기 위한 텍스트.
  final String unlockConditionText;

  /// 해금 후 플레이에 어떤 가치가 생기는지 요약.
  final String benefitSummary;

  /// 대략적인 구간 힌트 (초반/중반/후반)
  final String stageHint;

  /// 실제 달성을 위한 짧은 팁.
  final List<String> tips;

  /// 현재 세이브 기준 진행도 계산.
  final FeatureUnlockProgress Function(GameState state) progress;

  const FeatureUnlockDef({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.trigger,
    required this.roadmapOrder,
    required this.unlockConditionText,
    required this.benefitSummary,
    required this.stageHint,
    required this.tips,
    required this.progress,
  });
}

int _maxOwnedWithinSingleSet(GameState state) {
  if (state.ownedSwords.isEmpty) return 0;
  var maxOwned = 0;
  for (final s in swordSets) {
    var owned = 0;
    for (final id in s.swordIds) {
      if ((state.ownedSwords[id] ?? 0) > 0) owned++;
    }
    if (owned > maxOwned) maxOwned = owned;
  }
  return maxOwned;
}

bool _ownsAnySetPair(GameState state) => _maxOwnedWithinSingleSet(state) >= 2;

final featureUnlockCatalog = <FeatureUnlockDef>[
  FeatureUnlockDef(
    id: FeatureUnlocks.missionsTab,
    label: '미션',
    description: '상점 탭의 임무 메뉴가 열립니다. 일일/주간 목표로 정수와 코인을 얻을 수 있어요.',
    icon: Icons.flag,
    color: const Color(0xFF00897B),
    trigger: (s) => s.totalTaps >= 1,
    roadmapOrder: 1,
    unlockConditionText: '총 터치 1회',
    benefitSummary: '정수와 코인을 주는 일일/주간 미션 시작',
    stageHint: '초반',
    tips: const [
      '첫 터치 직후 바로 열리니 시작하자마자 확인하세요.',
      '미션 보상은 성장 초반 가속에 가장 효율적입니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: s.totalTaps.toDouble(),
      target: 1,
      kind: FeatureUnlockProgressKind.count,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.summonTab,
    label: '소환',
    description: '상점 탭의 소환 메뉴가 열립니다. 정수로 검을 뽑아 수집 보너스를 올릴 수 있어요.',
    icon: Icons.auto_awesome,
    color: const Color(0xFF7C4DFF),
    trigger: (s) => s.essence >= 50,
    roadmapOrder: 2,
    unlockConditionText: '정수 50 이상 보유',
    benefitSummary: '검 수집 시작 + 전체 전투력(수집 보너스) 상승',
    stageHint: '초반',
    tips: const [
      '초반 미션/업적으로 정수를 우선 모으세요.',
      '1연보다 10연 이상을 활용하면 희귀 보장 구간이 안정적입니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: s.essence.toDouble(),
      target: 50,
      kind: FeatureUnlockProgressKind.essence,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.achievementsTab,
    label: '업적',
    description: '상점 탭의 임무 메뉴에 업적이 열립니다. 업적 달성으로 정수 보상을 받습니다.',
    icon: Icons.emoji_events,
    color: const Color(0xFFFFB300),
    trigger: (s) => s.unlockedAchievements.isNotEmpty,
    roadmapOrder: 3,
    unlockConditionText: '업적 1개 이상 달성',
    benefitSummary: '업적 기반 정수 수급 루트 오픈',
    stageHint: '초반',
    tips: const [
      '처음엔 터치/골드/강화 관련 업적이 가장 빨리 열립니다.',
      '업적 탭이 열리면 보상을 즉시 수령해 다음 성장에 재투자하세요.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: s.unlockedAchievements.length.toDouble(),
      target: 1,
      kind: FeatureUnlockProgressKind.count,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.swordSetsView,
    label: '검 세트',
    description: '상점 탭의 무기고 메뉴에 세트가 열립니다. 같은 세트 검을 모으면 세트 보너스가 적용됩니다.',
    icon: Icons.workspaces,
    color: const Color(0xFFEC407A),
    trigger: _ownsAnySetPair,
    roadmapOrder: 4,
    unlockConditionText: '같은 세트 검 2종 이상 보유',
    benefitSummary: '세트 완성 시 추가 탭/방치 배율 확보',
    stageHint: '중반',
    tips: const [
      '무작정 고등급만 노리기보다 같은 세트 조합을 먼저 맞추세요.',
      '수집 탭에서 세트 진행도를 같이 확인하며 뽑는 것이 효율적입니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: _maxOwnedWithinSingleSet(s).toDouble(),
      target: 2,
      kind: FeatureUnlockProgressKind.count,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.prestigeTab,
    label: '환생',
    description: '환생 탭이 열립니다. 진행을 초기화하는 대신 영구 성장 코인을 획득할 수 있어요.',
    icon: Icons.auto_awesome,
    color: const Color(0xFF7C4DFF),
    trigger: (s) => s.prestigeCoinsAvailable >= 1,
    roadmapOrder: 5,
    unlockConditionText: '획득 가능 환생코인 1 이상',
    benefitSummary: '영구 성장 루프(각인 연구) 시작',
    stageHint: '중후반',
    tips: const [
      '환생 직전에는 골드/강화를 충분히 올려 코인 획득량을 극대화하세요.',
      '짧은 환생 반복보다 목표 코인 구간을 정해서 길게 모으는 편이 효율적입니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: s.prestigeCoinsAvailable.toDouble(),
      target: 1,
      kind: FeatureUnlockProgressKind.count,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.boosterShop,
    label: '부스터 상점',
    description: '홈 화면 우하단에 부스터 버튼이 열립니다. 정수로 시간제 버프를 구매할 수 있어요.',
    icon: Icons.bolt,
    color: const Color(0xFFFF8A65),
    trigger: (s) => s.prestigeCount >= 1,
    roadmapOrder: 6,
    unlockConditionText: '환생 1회 이상',
    benefitSummary: '짧은 시간 고효율 파밍(탭/DPS 러시) 가능',
    stageHint: '후반',
    tips: const [
      '접속 집중 시간이 짧을 때 러시형 부스터를 우선 쓰세요.',
      '부스터는 미션/업적 몰아서 처리할 때 같이 쓰면 효율이 큽니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: s.prestigeCount.toDouble(),
      target: 1,
      kind: FeatureUnlockProgressKind.count,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.stockMarket,
    label: '주식 시장',
    description: '상점 탭의 투자 메뉴가 열립니다. 지역 지분을 매수해 시간당 배당 수익을 얻을 수 있어요.',
    icon: Icons.show_chart,
    color: const Color(0xFFD32F2F),
    trigger: (s) => s.lifetimeGold >= stockMarketLifetimeGoldTrigger,
    roadmapOrder: 7,
    unlockConditionText:
        '누적 골드 ${NumberFormatter.format(stockMarketLifetimeGoldTrigger)} 이상',
    benefitSummary: '배당 기반의 장기 방치 수익 루트 오픈',
    stageHint: '엔드게임',
    tips: const [
      '주식 해금 직전에는 누적 골드를 빠르게 올릴 수 있는 구간에 집중하세요.',
      '해금 후에는 배당 회수를 루틴화하면 장기 성장 속도가 안정됩니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current: s.lifetimeGold,
      target: stockMarketLifetimeGoldTrigger,
      kind: FeatureUnlockProgressKind.gold,
    ),
  ),
  FeatureUnlockDef(
    id: FeatureUnlocks.goldExchange,
    label: '골드 환금소',
    description: '정수를 골드로 즉시 환전할 수 있어요. 환전한 골드는 환생 코인에 직접 들어가지 않습니다.',
    icon: Icons.currency_exchange,
    color: const Color(0xFFFFB300),
    // Either first prestige clears it (most likely path) OR a player who
    // hasn't prestiged yet but has crawled past 100M gold can also see it.
    trigger: (s) => s.prestigeCount >= 1 || s.lifetimeGold >= 1e8,
    roadmapOrder: 8,
    unlockConditionText: '환생 1회 또는 누적 골드 100M 이상',
    benefitSummary: '정수를 시간 단축에 사용해 페이스 조절',
    stageHint: '중후반',
    tips: const [
      '8시간 환금 슬롯이 정수 효율이 가장 좋아요. 자기 전 한 번 사용해 보세요.',
      '환전한 골드를 강화/주식에 쓰면 그때부터 환생 코인 계산에 정상 반영됩니다.',
    ],
    progress: (s) => FeatureUnlockProgress(
      current:
          s.prestigeCount >= 1 ? 1 : (s.lifetimeGold / 1e8).clamp(0.0, 1.0),
      target: 1,
      kind: FeatureUnlockProgressKind.count,
    ),
  ),
];

final Map<String, FeatureUnlockDef> _byId = {
  for (final d in featureUnlockCatalog) d.id: d,
};

FeatureUnlockDef? featureUnlockDef(String id) => _byId[id];

List<FeatureUnlockDef> featureUnlockRoadmap() {
  final list = [...featureUnlockCatalog];
  list.sort((a, b) => a.roadmapOrder.compareTo(b.roadmapOrder));
  return list;
}

List<FeatureUnlockDef> lockedFeatureDefs(GameState state) => [
      for (final d in featureUnlockRoadmap())
        if (!state.isFeatureUnlocked(d.id)) d,
    ];

int unlockedFeatureCount(GameState state) {
  var n = 0;
  for (final d in featureUnlockCatalog) {
    if (state.isFeatureUnlocked(d.id)) n++;
  }
  return n;
}

double featureUnlockCompletionRatio(GameState state) {
  if (featureUnlockCatalog.isEmpty) return 1.0;
  return unlockedFeatureCount(state) / featureUnlockCatalog.length;
}

FeatureUnlockDef? nextRecommendedLockedFeature(GameState state) {
  final locked = lockedFeatureDefs(state);
  if (locked.isEmpty) return null;
  locked.sort((a, b) {
    final ar = a.progress(state).ratio;
    final br = b.progress(state).ratio;
    final ratioCmp = br.compareTo(ar);
    if (ratioCmp != 0) return ratioCmp;
    return a.roadmapOrder.compareTo(b.roadmapOrder);
  });
  return locked.first;
}
