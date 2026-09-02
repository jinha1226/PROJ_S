# 과거 세션 인계: 고정 첫 이벤트와 성장 구조

> 상태: **현재 우선순위에서 폐기된 역사 문서**. 고정 첫 이벤트와 성장 구조 작업 당시의
> 결정 기록은 보존하지만, 다음 구현 지시로 사용하지 않는다. 2026-09-02 현재 순서는
> `docs/NEXT_DEVELOPMENT_GUIDE.ko.md`의 파티 단체전투 P4-1이 우선한다.

## 현재 상태

- 기준 커밋: `ac9e40f`
- 고정 첫 이벤트: 설계 완료, 코드 미구현
- 성장 구조: 설계 완료, 코드 미구현
- 다음 구현 모델: `gpt-5.6-sol`, reasoning `medium`
- 다음 세션에서는 먼저 고정 첫 이벤트 MVP만 구현한다.
- 아래 사용자 소유 미추적 파일은 수정하거나 커밋하지 않는다.
  - `docs/ascii_roguelike_character_growth_run_design.txt`
  - `docs/ascii_roguelike_dungeon_boss_plan.txt`

## 확정된 고정 첫 이벤트

`SOLO_COMBAT_V1`의 1층 입구 근처에 실제로 부상한 중립 인물 한 명이 항상 등장한다.

- 인물은 연출용 마커가 아니라 실제 `SimEntity + CombatantState`다.
- `ACTIVE` 상태이며 실제 HP가 약 20% 남아 있다.
- 플레이어는 실제 회복 물약 한 개를 건네거나 지나간다.
- 이벤트의 상황과 역할은 고정하지만 HEXACO 성격은 run seed에 따라 달라진다.
- 같은 seed, save, journal replay에서는 성격과 결과가 완전히 동일해야 한다.
- 도움은 감사를 만들지만 종족 관계의 기본 trust를 즉시 뒤집지 않는다.
- 도움을 줬다고 즉시 영입되거나 생존이 보장되지 않는다.
- 선택 후에도 같은 `entity_id`로 세계에 남는다.
- 입구에서 출구로 향하는 경로의 35~50% 구간을 중앙 합류 지점으로 삼는다.
- NPC는 실제 경로 이동으로 중앙 목표를 향하며 순간이동하거나 다시 생성되지 않는다.
- 중앙 구간에서 같은 NPC가 LOS에 들어오면 재조우를 한 번 기록한다.
- 실제 상태에 따라 생존, 빈사, 사망 또는 시체로 발견될 수 있다.

### 1차 MVP 범위

- 입구 안전 칸에 부상 NPC 생성
- world seed 기반 HEXACO 생성
- `회복 물약 건네기 (N)` / `지나가기`
- 실제 물약 소비와 실제 HP 회복
- trust를 바꾸지 않는 gratitude 기록
- 같은 actor의 실제 인접 경로 이동
- 중앙 합류 구역에서 재조우 기록
- 실제 사망과 비점유 corpse 표시
- strict save/load/journal replay
- 360×640, 450×800 모바일 상호작용

### 이번 MVP의 비범위

- 자율 `HUNT`, `HIDE`, 집단 합류
- 영입 제안과 동료화
- 대화 트리와 퀘스트 편집기
- 다층 이벤트
- NPC 장비·거래·루팅 전반
- grid, ASCII renderer, 전투 공식 재작성

## 기존 코드에서 재사용할 기반

- 실제 actor 생성: `sim/world_state.gd`의 `add_entity()`
- 생명 상태: `sim/combatant_state.gd`, `sim/systems/damage_system.gd`
- HEXACO: `sim/dungeon_population/hexaco_profile.gd`
- 종족 관계: `sim/species_relation_table.gd`
- 개인 관계: `sim/systems/relationship_system.gd`
- 물약 소비: `sim/item_inventory_operations.gd`
- 경로: `sim/weighted_pathfinder.gd`
- 이동 commit: 기존 movement system
- 맵 anchor 계산: `playtest/deterministic_dungeon_map.gd`
- encounter 저장: `sim/party_encounter_state.gd`
- world cadence: `sim/systems/party_encounter_coordinator.gd`
- journal/replay/관찰: `playtest/party_playtest_session.gd`
- 모바일 상호작용: `playtest/party_encounter_sandbox.gd`의 `ProductInteract`
- actor/life 렌더: `playtest/party_grid_view.gd`

`SHOWCASE_V1`의 연출용 쓰러진 영입 후보는 이 이벤트에 재사용하지 않는다.

## 권위 데이터 분리

새 `OpeningEventState`에는 다음 정보만 둔다.

- NPC entity ID
- `PENDING | GAVE_POTION | PASSED` 선택
- HEXACO profile
- spawn position
- convergence band와 goal
- 현재 행동(`WAITING | TRAVEL` 우선)
- choice event ID
- reencounter event ID

다음 정보는 기존 권위만 사용한다.

- HP, 위치, life state: entity/combatant
- 물약 수량: inventory
- 감사와 관계: relationship system
- 실제 이동: movement event
- corpse 여부: 실제 `DEAD` 상태에서 파생

UI 문구와 재조우 상태 라벨은 저장하지 않는다.

## 결정론과 migration 불변식

- 같은 `world_seed + scenario + journal`은 NPC ID, HEXACO, 선택, 이동, snapshot이 동일하다.
- HEXACO는 frame time, UI refresh, `Time`, 전역 RNG 소비에 의존하지 않는다.
- 관찰, assessment, tooltip은 snapshot, journal, RNG를 바꾸지 않는다.
- `GIVE_POTION`은 물약을 정확히 한 개 소비하고 NPC의 실제 HP를 회복한다.
- `PASSED`는 inventory, NPC HP, 관계 수치를 바꾸지 않는다.
- 중복 선택은 시간, journal, RNG, snapshot이 모두 불변인 거절이다.
- gratitude 이후에도 effective trust의 종족 baseline은 유지된다.
- opening NPC는 party/enemy ID 집합과 겹치지 않는다.
- 이동은 매 step 인접 칸이며 teleport event가 존재하지 않는다.
- spawn부터 corpse까지 actor ID가 동일하다.
- 구버전 save에는 nullable `opening_event = null`을 사용한다.
- legacy journal replay에서는 opening NPC를 새로 bootstrap하지 않는다.
- load 검증 실패 시 현재 session을 보존한다.

## 파일별 예상 변경

새 파일:

- `sim/opening_event_state.gd`
- `sim/systems/opening_event_system.gd`
- `tests/test_opening_fixed_event.gd`
- 필요 시 집중 test runner

기존 파일:

- `playtest/deterministic_dungeon_map.gd`: 순수 anchor 계산
- `sim/party_encounter_state.gd`: nullable opening state와 migration
- `sim/systems/relationship_system.gd`: trust를 바꾸지 않는 gratitude API
- `sim/systems/party_encounter_coordinator.gd`: 최소 travel cadence 연결
- `sim/world_state.gd`: opening state/entity 불변식
- `playtest/party_playtest_session.gd`: bootstrap, assessment, commit, replay, observation
- `playtest/party_encounter_sandbox.gd`: 두 선택 UI와 단일 commit
- `playtest/party_grid_view.gd`: 실제 dead NPC corpse의 최소 표시

## 집중 테스트

- 여러 seed에서 spawn이 안전하고 convergence ratio가 35~50%다.
- 같은 seed의 HEXACO가 exact하고 다른 world seed에서는 달라진다.
- personality seed만 바꿔도 opening NPC 성격은 변하지 않는다.
- NPC는 실제 actor이며 초기 HP와 `ACTIVE`가 일치한다.
- GIVE: 물약 1개 소비, 실제 heal, gratitude 증가, trust baseline/영입 불변.
- PASS: inventory, HP, relation 불변.
- 중복 선택 완전 no-op.
- 같은 actor ID가 인접 이동만 수행하고 teleport가 없다.
- 중앙 band LOS 재조우가 최대 한 번 기록된다.
- dead NPC는 통행을 막지 않으며 visible corpse로 나타난다.
- pending, 선택 직후, 이동 중, dead 상태의 save/load/replay가 exact하다.
- 360×640과 450×800에서 44px 이상 버튼과 단일 touch commit을 보장한다.

## 다음 Medium 구현 에이전트용 프롬프트

```text
작업 경로: /mnt/d/STARTU/living-world-sim
모델: gpt-5.6-sol, reasoning medium

이 문서의 '고정 첫 이벤트' 1차 MVP를 구현하라. 코드를 수정하고 집중 테스트를
실행하되 커밋/푸시는 하지 마라. 사용자 소유 미추적 기획 파일 두 개를 수정하지 마라.

SOLO_COMBAT_V1 입구에 실제 ACTIVE 부상 중립 NPC를 기존 적 생성 뒤 마지막 entity로
생성한다. 성격은 world_seed와 전용 고정 slot으로 생성하고 save/replay에 포함한다.
인접한 플레이어에게 실제 POTION_HEALING 한 개를 건네기 또는 지나가기를 제공한다.
GIVE는 기존 inventory operation과 실제 HP 회복을 사용하며 gratitude만 기록한다.
종족 trust baseline, 영입, 파티 구성은 변경하지 않는다. 중복 선택은 atomic no-op이다.

입구→출구 결정론적 최단 경로의 35~50% band와 약 42%의 passable goal을 순수 계산한다.
NPC는 선택 후 같은 entity_id로 기존 pathfinder/movement를 사용해 인접 이동한다.
순간이동, 재스폰, 선택별 고정 생존 결과를 금지한다. 중앙 band에서 같은 NPC가 실제
LOS에 들어오면 reencounter를 한 번 기록한다. 실제 DEAD NPC는 비점유 corpse로 관찰한다.

OpeningEventState에는 ID/choice/profile/anchors/behavior/event IDs만 저장한다. HP/position/life,
inventory, relation을 중복 저장하지 않는다. PartyEncounterState와 session journal에 strict하게
연결하고 legacy save는 nullable migration과 legacy bootstrap-off로 exact replay를 유지한다.

기존 WorldState, CombatantState, HexacoProfile, SpeciesRelationTable, RelationshipSystem,
ItemInventoryOperations, WeightedPathfinder, movement, PartyEncounterState,
PartyEncounterCoordinator, PartyPlaytestSession, ProductInteract, PartyGridView를 재사용한다.
grid/combat/ASCII renderer를 재작성하지 않는다.

HUNT/HIDE/집단합류/영입/대화/다층은 구현하지 않는다. 이후 확장 가능한 behavior seam만 둔다.
새 집중 테스트와 runner를 먼저 작성해 anchor/seed/GIVE/PASS/no-op/movement/reencounter/
save-replay/corpse/mobile UI를 검증한다. 관련 테스트만 실행하고 전체 회귀를 반복하지 않는다.
마지막에 변경 파일, authority flow, migration, 테스트 결과와 남은 위험을 보고한다.
```

## 성장 구조 결정안

기존 무기 숙련과 훈련 집중은 폐기하고 다음 세 축으로 구성한다.

1. 종족: 바뀌지 않는 체질·환경 적응과 소수의 장기 선택
2. 아이템: 무기 공격 형태, 방어, 접사와 태그 조합
3. 몬스터 이능 `변이흔`: 제한 슬롯의 강한 규칙 변화와 부작용

캐릭터 레벨과 XP는 유지한다. 권장 기본 스탯은 `완력 / 기민 / 활력`이다.

- 매 레벨 최대 HP +2
- 3레벨마다 스탯 포인트 +1
- Lv7, Lv17에 종족 포인트 +1
- 레벨은 피해에 직접 곱하지 않는다.
- 공격시간과 사거리 등은 무기 자체의 정체성으로 유지한다.

MVP 종족은 현재 코드에 있는 인간, 드워프, 고블린, 양서인이다. 각 종족은 고정 특징
하나와 두 개의 2단계 가지를 가진다. 한 run에는 두 포인트만 얻는다.

장비 슬롯은 `주손 / 보조손 / 갑옷 / 장신구 1 / 장신구 2`를 유지한다. 일반은 접사 0,
고급 1, 희귀 2이며 접사는 작은 수치형 1개와 조건 반응형 1개로 제한한다.

변이흔은 몬스터 계통별 첫 유효 처치에서 확정 획득한다. 플레이어가 피해에 참여했거나
LOS 안에서 죽음을 목격해야 한다. 장착 슬롯은 3개이며 안전한 `GROUPED` 상태에서만
100시간을 소비해 교체한다. MVP는 passive/on-hit/on-hurt/interact 효과만 사용한다.

기본 UI 탭은 다음 네 개다.

```text
[상태] [종족] [장비] [이능]
```

숙련 탭과 무기별 훈련 ledger는 제거 대상이다. legacy save는 기존 run 동안 보너스를
동결한 뒤 permadeath에서 제거하는 방식이 안전하지만, 개발 save 보존이 필요 없다면
hard cut이 훨씬 작다.

## 아직 사용자와 합의할 결정

- [ ] 기본 스탯 이름을 `완력 / 기민 / 활력`으로 확정할지
- [ ] 종족 포인트 지급 레벨을 `Lv7 / Lv17`로 확정할지
- [ ] 변이흔을 계통별 첫 유효 처치에서 확정 획득할지
- [ ] MVP 변이흔 교체를 안전한 GROUPED 상태 어디서나 허용할지
- [ ] 구버전 숙련 save를 동결 유지할지, 개발 단계 hard cut할지

## 다음 작업 순서

1. 새 세션에서 Sol Medium으로 고정 첫 이벤트 MVP 구현
2. 집중 테스트 검증
3. 배포 후 사용자 웹 플레이 확인
4. 성장 구조의 미합의 결정 5개 확정
5. 숙련 제거와 새 성장 schema는 별도 단계로 구현
