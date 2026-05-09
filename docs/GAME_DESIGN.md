# 검 키우기 (Idle Sword Clicker) — 기획서 v2

## 1. 프로젝트 개요
- **게임명**: 검 키우기 (Idle Sword Clicker)
- **장르**: 클리커 + 방치형(Idle) RPG
- **플랫폼**: iOS / Android
- **개발**: Flutter (Material 3 + Riverpod)
- **톤**: 캐주얼·아기자기·친근감 (파스텔 코랄/민트, 둥근 카드, 부드러운 애니메이션)

---

## 2. 핵심 컨셉
검을 터치해 골드를 모은다. 골드로 검을 강화하거나 동료를 고용해 자동 수익(DPS)을 늘린다. 게임을 꺼도 오프라인 시간만큼 골드가 누적된다 (최대 12시간, 효율 100%). 일정 진척 후 환생으로 영구 배율을 얻어 다시 시작한다.

---

## 3. 핵심 시스템

### 3.1 기본 루프
1. 검 터치 → 골드 획득
2. 골드로 업그레이드 구매 (탭 강화 / 동료 고용)
3. 자동 수익 증가
4. 반복 → 환생으로 영구 배율 획득

### 3.2 터치 시스템
```
획득 골드 = tapPower × prestigeMultiplier
```
- `tapPower` 초기값 1
- Tap 강화 업그레이드로 누적 (`+N per level`)
- `prestigeMultiplier = 1 + (souls × 0.02)`

### 3.3 자동 수익 (Idle)
- **50ms 틱**으로 부드럽게 누적: `gold += dps × dt`
- DPS = Σ(producer.baseDps × producer.level) × prestigeMultiplier
- 이유: 1초 단위는 시각적으로 끊김 — 50ms = 20Hz로 자연스러운 카운터

### 3.4 오프라인 보상
```
elapsed = clamp(now - lastSavedAt, 0, 12h)
reward  = dps × elapsed × 1.0      // 효율 100%
```
- 부재 30초 미만 시 팝업 생략 (UX 마찰 감소, 탭 전환 round-trip 무시)
- 재접속 첫 프레임에서 `OfflineRewardDialog` 노출
- 홈 화면에 상시 "방치 보상 최대 +X / 12h" 칩 노출 (DPS>0 시)
- `lastSavedAt`은 모든 mutation에서 즉시 갱신 + 10s 오토세이브 + 라이프사이클 hidden 시 저장 — 재접속까지의 경과 시간 측정 정확도 ±10s 이내

---

## 4. 업그레이드

### 4.1 Tap 강화 (5종)
가격 공식: `baseCost × 1.10 ^ level`

| ID | 이름 | 기본가 | tapPower/lv |
|---|---|---|---|
| sharper_blade | 날카로운 검날 | 25 | 1 |
| magic_infusion | 마력 주입 | 250 | 5 |
| sword_aura | 검기 각성 | 2,500 | 25 |
| divine_strike | 신성한 일격 | 25,000 | 100 |
| legendary_swing | 전설의 일섬 | 250,000 | 500 |

### 4.2 자동 수익 — 동료 (12종)
가격 공식: `baseCost × 1.15 ^ level`
성장 패턴: 비용 ×10, DPS ×7

| ID | 이름 | 기본가 | 기본 DPS |
|---|---|---|---|
| apprentice | 견습 검사 | 50 | 1 |
| mercenary | 용병 | 500 | 8 |
| knight | 기사 | 5,000 | 60 |
| mage_swordsman | 마검사 | 50,000 | 400 |
| sword_saint | 검성 | 500,000 | 3,000 |
| dragon_slayer | 용살자 | 5,000,000 | 22,000 |
| sword_god | 검신 | 50,000,000 | 150,000 |
| legendary_hero | 전설의 영웅 | 500,000,000 | 1,000,000 |
| ancient_warrior | 고대 전사 | 5e9 | 7,000,000 |
| dimension_blade | 차원검 | 5e10 | 50,000,000 |
| time_keeper | 시간의 수호자 | 5e11 | 350,000,000 |
| cosmic_swordmaster | 우주 검성 | 5e12 | 2,500,000,000 |

### 4.3 마일스톤 배율 (Phase 2 예정)
각 producer Lv 25/50/100/200 도달 시 해당 producer DPS ×2 영구 누적

---

## 5. 환생 시스템 (검의 혼)
```
soulsGained         = floor(sqrt(totalGoldEarned / 1e9))
prestigeMultiplier  = 1 + (totalSouls × 0.02)   // 1 soul당 +2%
```
- 첫 환생 가능: 누적 골드 1B (≈ 1~2시간)
- 환생 시 리셋: gold, totalGoldEarned, producerLevels, tapUpgradeLevels
- 환생 시 유지: prestigeSouls, prestigeCount
- "다음 환생 시 +N 소울" UI 상시 노출

---

## 6. UI 구성

### 6.1 메인 화면 (3개 탭)
- **홈**: 검 + 골드/DPS + 터치 피드백 (FloatingNumber)
- **강화**: Tap 강화 + 동료 리스트 (스크롤 카드)
- **환생**: 누적 골드/예상 소울/실행 버튼 + 영구 배율 표시

### 6.2 캐주얼 톤 가이드
- **컬러**: 코랄 `#FF8A65` (primary) / 민트 `#80CBC4` (secondary) / 노랑 `#FFD54F` (accent) / 크림 `#FFF8E1` (배경)
- **모서리**: 카드/버튼 radius 20+
- **검**: CustomPainter로 둥글둥글한 픽셀풍 검
- **애니메이션**: 검 0.92↔1.0 스케일 펄스(120ms) + 살짝 회전
- **숫자 피드백**: 터치 위치에서 +N이 올라가며 페이드(800ms)

---

## 7. 데이터 구조

```dart
class SaveData {
  int version;              // 마이그레이션
  double gold;
  double totalGoldEarned;   // 환생 계산
  Map<String, int> producerLevels;
  Map<String, int> tapUpgradeLevels;
  int prestigeSouls;
  int prestigeCount;
  DateTime lastSavedAt;
  GameStats stats;          // totalTaps 등
}
```
- **저장**: SharedPreferences + JSON (단순/충분)
- **자동 저장**: 30초 + 백그라운드 진입
- **버전 필드**로 마이그레이션 대비

---

## 8. 폴더 구조
```
lib/
  main.dart
  app.dart
  core/        # number_format, theme
  models/      # save_data, producer, tap_upgrade, game_stats
  data/        # producer_catalog, tap_upgrade_catalog
  services/    # save_service
  providers/   # game_provider (Riverpod)
  screens/     # main, home, upgrade, prestige
  widgets/     # sword, gold_display, dps_display, upgrade_tile,
               # floating_number, offline_reward_dialog, prestige_dialog
```

---

## 9. 공식 정리

| 항목 | 공식 |
|---|---|
| 터치 골드 | `tapPower × prestigeMultiplier` |
| DPS | `Σ(producer.baseDps × level) × prestigeMultiplier` |
| Producer 가격 | `baseCost × 1.15 ^ currentLevel` |
| Tap 강화 가격 | `baseCost × 1.10 ^ currentLevel` |
| 오프라인 보상 | `dps × min(elapsed, 12h) × 1.0` |
| 환생 소울 | `floor(sqrt(totalGoldEarned / 1e9))` |
| 환생 배율 | `1 + souls × 0.02` |

---

## 10. 개발 우선순위

**Phase 1 (MVP, 현재)**
1. 검 터치 → 골드 + 애니메이션
2. 숫자 포맷 (K/M/B/T → aa/ab...)
3. Producer 12종 + Tap 강화 5종
4. 50ms idle 틱 + 자동저장
5. 오프라인 보상 (100% 효율)
6. 환생 시스템

**Phase 2**
- 마일스톤 배율
- 크리티컬 + 콤보
- 글로벌 부스터

**Phase 3**
- 업적 시스템
- 사운드
- 광고 보상 후크 (2× 부스터, 오프라인 시간 연장)
- 클라우드 저장

---

## 11. 비고
- 첫 실행 시 안내(튜토리얼)는 Phase 2에서 추가
- 다국어는 한국어 단일 (Phase 3에서 i18n)
- 광고는 후크만 준비 (실제 SDK 연결은 별도)
