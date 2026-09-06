# 파티 식량(배고픔) 시스템 설계

작성일 2026-09-06. 픽셀던전식 생존 압박을 **파티 단위 게이지 하나**로 옮긴 최소 설계다.
개인 포만도, 수동 식사, 전투 능력 페널티는 범위 밖이다.

## 목표

- "식량을 찾아야 한다 / 떨어지면 굶는다"는 전통 로그라이크 압박을 준다.
- 동료가 늘수록 식량 소모가 커져 파티 규모가 비용이 된다.
- 굶주림은 HP 피해와 스트레스로 나타나고, 동료 반응은 기존 감정·대사 시스템이 만든다.
- 마을 구매와 던전 내 수급(바닥 발견, 몬스터 드롭) 두 경로를 모두 둔다.
- 플레이어가 누를 버튼을 추가하지 않는다. 식사는 전부 자동이다.

## 비범위

- 개인별 배고픔, 수동 식사, 음식 종류 다양화(부패·독 고기 등)
- 배고픔에 따른 공격력·회복량 변화
- 마을 NPC 니즈 모델(`agent_state.hunger`)과의 통합
- 레거시(비-product) 멀티파티 샌드박스 UI

## 1. 권위 데이터

`sim/party_encounter_state.gd`에 정수 필드 2개를 추가한다.

| 필드 | 의미 | 범위 |
|---|---|---|
| `ration_milli` | 파티 식량 게이지 (1/1000 단위) | `0..ration_max×1000` |
| `ration_processed_at` | 마지막으로 감소를 적산한 월드 시각 | `0..MAX_WORLD_TIME` |

- `RATION_SCHEMA_VERSION := 22`. `to_dict`/`from_dict`/`wire_error`에 같은 패턴으로 추가한다.
- 구버전 세이브(schema < 22)는 `ration_milli = ration_max×1000`, `ration_processed_at = world_time`으로 로드한다.
- `wire_error`는 범위 밖 값과 `ration_processed_at > world_time`을 거부한다.
- 표시·DTO용 `ration`은 `ration_milli / 1000`의 파생값이며 저장하지 않는다.
- 굶주림 피해 시각은 별도 필드 없이 `ration_processed_at`을 100시간 단위로 정렬해 계산한다
  (아래 2.3).

규칙 수치는 `data/content/hunger_rules.json` 한 파일에 둔다. 코드에 숫자를 쓰지 않는다.

```json
{
  "content_schema_version": 1,
  "content_type": "HUNGER_RULES",
  "ruleset_id": "party-ration-v1",
  "ration_max": 300,
  "hungry_below": 100,
  "drain_interval": 100,
  "drain_per_interval_milli": 1000,
  "drain_extra_member_milli": 500,
  "starve_interval": 100,
  "starve_damage": 1,
  "starve_stress": 4,
  "food_definition_id": "FOOD_RATION",
  "food_nutrition": 300
}
```

- 1인 파티는 100시간마다 1 감소한다. 만복(300)에서 공복(<100)까지 20,000시간, 굶주림(0)까지
  30,000시간이다. 기본 원정 제한 120,000시간의 약 17% / 25%로, 픽셀던전(300턴/450턴)의
  비율을 따른다.
- 활성 파티원이 n명이면 100시간당 `1000 + 500 × (n−1)` milli 감소한다. 게이지를 milli로
  저장하므로 2인 파티의 1.5/interval 같은 소수 소모도 정확히 누적된다(아래 2.1).
- 초기값은 추정치다. §7 밸런스 시뮬 결과로 이 파일만 조정한다.

## 2. 규칙 — `sim/systems/party_ration_system.gd`

정적 함수만 있는 시스템이다. 입력은 `world`(party_encounter, world_time, inventories, entities)와
규칙 딕셔너리뿐이며 RNG를 소비하지 않는다.

### 2.1 감소 (`drain`)

`party_encounter_coordinator.process_tick`에서 `reconcile_liveness` 직후, safe_phase가
`GROUPED`/`GROUPED_COMPLETE`/`ENGAGED`일 때 매 tick 호출한다. TOWN 단계(expedition_cycle.phase ==
"TOWN")에서는 호출하지 않는다.

```
elapsed = world_time - ration_processed_at
intervals = elapsed / drain_interval            # 정수
if intervals == 0: return
drain_milli = intervals * (drain_per_interval_milli + drain_extra_member_milli * (active_count - 1))
ration_milli = max(0, ration_milli - drain_milli)
ration_processed_at += intervals * drain_interval
```

- `active_count`는 `active_party_member_ids` 중 `life_state == ACTIVE`인 수, 최소 1이다.
- 구간(band)은 파생값이다: `ration_milli == 0` → `STARVING`, `< hungry_below×1000` → `HUNGRY`, 그 외 `FED`.
  구간이 바뀌면 `party.ration_changed {before, after, ration}` 이벤트를 한 번 발행한다.

### 2.2 자동 식사 (`auto_eat`)

`drain` 직후와, 파티 가방에 식량이 들어온 직후(줍기·구매·드롭 획득 커밋 뒤) 호출한다.

- 조건: 구간이 `HUNGRY` 또는 `STARVING`이고 주인공 인벤토리에 `food_definition_id` 스택이 있다.
- 동작: `ItemInventoryOperations.commit_use`로 1개 소비 → `ration_milli = min(ration_max×1000,
  ration_milli + food_nutrition×1000)` → `party.ration_eaten {definition_id, ration}` 이벤트.
- 한 tick에 최대 1개만 먹는다. 식량이 없으면 구간이 `HUNGRY`로 바뀐 그 tick에만
  `party.ration_missing` 이벤트를 발행한다(연속 스팸 금지).
- 동료 개인 인벤토리는 보지 않는다. 식량은 주인공 가방이 파티 가방이다.

### 2.3 굶주림 피해 (`starve`)

- `ration_milli == 0`인 동안, `drain`이 처리한 각 `starve_interval` 경계마다 활성 파티원 전원에게
  `damage_system.apply_damage(entity, starve_damage, "starvation", cause_id = -1)`를 적용한다.
  `drain`이 여러 interval을 한 번에 처리하면 그 수만큼 반복한다(결정론).
- 피해 이벤트는 기존 damage 경로가 발행한다. 다운/사망 처리도 기존 규칙을 따른다.
- 같은 경계에서 `party.ration_starve_tick {member_ids, damage}` 이벤트 1개를 추가로 발행해
  morale/emotion 입력으로 쓴다.

### 2.4 마을 귀환

`simulator.gd`에서 `expedition_cycle.auto_return_if_due`가 참을 반환하는 지점과 명시적 귀환
경로 모두에서 `ration_milli = ration_max×1000`, `ration_processed_at = world_time`으로 리셋한다.
마을에 있는 동안은 감소하지 않는다.

## 3. 식량 공급 (데이터만)

- `data/content/items.json`: `FOOD_RATION` 「배급 식량」, `category: "CONSUMABLE"`,
  `stack_limit: 10`, `use_kind: "EAT"`. `item_registry`의 `use_kind` 허용 목록에 `EAT` 추가.
- 마을 시장 카탈로그(`party_playtest_session.gd`의 리스트): `{"definition_id":"FOOD_RATION",
  "price":6,"stock":6}`. 재입고 규칙은 기존 시장과 동일.
- 시작 인벤토리: `START_RATION_001`, 수량 2.
- 던전 바닥: 층 진입 시(`_enter_campaign_floor`와 초기 층 생성) `_initial_ground_item_rows`와
  같은 결정론적 후보 정렬로 층당 식량 1개를 입구에서 가장 먼 후보 칸에 놓는다. 위치는
  시드·층 배치만의 함수다.
- 드롭: `species_drop_tables.json` 고블린 테이블에 `{"roll_id":"GOBLIN_RATION",
  "definition_id":"FOOD_RATION","chance_per_1000":300,"min_quantity":1,"max_quantity":1}`.

## 4. 스트레스·성격 반응

- `party.ration_starve_tick`을 `party_morale_system.commit_batch`의 입력 행으로 넘겨 활성
  파티원 스트레스를 `starve_stress`만큼 올린다. 회복 규칙은 기존 morale 모델 그대로다.
- `party_emotion_system`은 `party.ration_changed`, `party.ration_missing`,
  `party.ration_starve_tick`을 기존 이벤트 소비 방식대로 감정·대사에 반영한다. 성격별
  차이는 기존 HEXACO 감정 모델이 만든다. 새 성격 규칙은 추가하지 않는다.

## 5. UI (product HUD)

- 상단 rail 귀환 타이머 줄 오른쪽에 `· 식량 ▮▮▮▯` (4칸, `ration / ration_max` 비율).
  `HUNGRY`는 황동, `STARVING`은 빨강 「굶주림」 텍스트로 대체.
- 이벤트 로그 문구: 「배급 식량을 먹었다」, 「식량이 떨어졌다」, 「굶주림 · 전원 −1」.
- `expedition_hud_spec()`에 `ration_band`, `ration_ratio_milli`를 추가하고 `_update_expedition_hud`가
  그린다. 새 버튼·모달 없음. 가방 목록에는 식량이 일반 아이템으로 보인다.
- 관찰 DTO: `party_status()`에 `ration`, `ration_max`, `ration_band` 3개 키를 추가한다.

## 6. 결정론·저장·검증 불변식

- 입력은 월드 시간, 활성 인원, 주인공 인벤토리뿐이다. RNG·프레임 시간·UI를 읽지 않는다.
- 같은 `world_seed + scenario + journal`이면 `ration`, 식사 시각, 굶주림 피해 순서가 동일하다.
- `commit_use` 실패(검증 오류)는 그 tick의 식사를 건너뛰고 상태를 바꾸지 않는다.
- `world_state_error`는 `PartyEncounterState.wire_error`를 통해 `ration_milli` 범위를 검사한다.
- save → load → 같은 명령 재생 시 snapshot 동일. legacy journal replay는 만복으로 시작한다.

## 7. 테스트·밸런스

단위 테스트 `tests/test_party_ration.gd` (+ `run_party_ration_tests.gd`):

1. 1인 파티: 20,000시간 뒤 `HUNGRY`, 30,000시간 뒤 `STARVING`, 경계에서 이벤트 1회.
2. 3인 파티: 같은 시간에 두 배 소모(`1000+500×2`).
3. 공복 진입 시 식량 1개 자동 소비, 게이지 만복, `party.ration_eaten` 1회, journal 없이도 replay 동일.
4. 식량 없음: `party.ration_missing` 1회만, 굶주림 100시간마다 전원 −1, 스트레스 +4.
5. 마을 귀환 리셋, TOWN 단계 무감소.
6. schema 21 세이브 로드 → 만복, 범위 밖 값 거부.
7. 바닥 식량 위치와 고블린 드롭이 시드 고정.

밸런스 시뮬 `tests/run_ration_balance_sim.gd`: 시드 20개 × 파티 1/2/3인, AUTO 탐험으로 원정
1회 완주. 출력: 굶주림 도달 비율, 굶주림 중 총 피해, 층당 발견 식량 수, 원정 종료 시 잔여
식량. 목표 밴드(초기): 1인 굶주림 도달 ≤ 20%, 3인 ≤ 60%. 벗어나면 `hunger_rules.json`만 조정한다.

## 파일별 변경 예상

새 파일: `sim/systems/party_ration_system.gd`, `data/content/hunger_rules.json`,
`tests/test_party_ration.gd`, `tests/run_party_ration_tests.gd`, `tests/run_ration_balance_sim.gd`

수정: `sim/party_encounter_state.gd`(필드·스키마), `sim/systems/party_encounter_coordinator.gd`
(호출), `sim/simulator.gd`(귀환 리셋), `sim/item_registry.gd`(`EAT`), `data/content/items.json`,
`data/content/species_drop_tables.json`, `playtest/party_playtest_session.gd`(시장·시작 인벤토리·층
바닥 식량·DTO), `playtest/party_encounter_sandbox.gd`(rail 게이지·로그 문구),
`tests/party_ui_visual_style_smoke.gd`(rail 게이지 계약).
