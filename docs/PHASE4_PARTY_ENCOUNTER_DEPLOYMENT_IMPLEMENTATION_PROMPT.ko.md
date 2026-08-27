# Phase 4 구현 프롬프트 — 동일 월드 파티 조우·배치·재집결

## 0A. 2026-08-28 자동 재집결 UX 개정 — 최우선 계약

이 절은 아래 문서의 `REGROUP_READY` 명시 입력, `+100` 재집결 command,
`PartyPlaytestSession.regroup()`, `RegroupConfirm`, journal `regroup`, ruleset/session v1
기술을 모두 대체한다. 충돌 시 이 절이 authoritative하다.

- 마지막 적을 죽인 `party turn` 하나가 `party.victory → party.regroup_started →
  party.member_regrouped* → party.regroup_completed`를 같은 `step_index` 안에서 원자적으로
  commit한다. `party.regroup_started.cause_id`는 `party.victory.id`다.
- 살상 행동 뒤 예정된 environment/actor cadence를 먼저 기존 DEPLOYED 위치에서 모두
  처리한다. 그 뒤 `finish_step()` 직전 zero-time finalizer가 토큰을 합친다. 별도 시간,
  step, 입력, 버튼, journal row가 없다.
- `REGROUP_READY`는 transaction 내부의 transient 호환 상태일 뿐이다. v2의 settled
  snapshot에는 나타날 수 없고 restore validator가 거부한다. 정상 UI가 `REGROUP` 화면을
  관찰해서도 안 된다.
- snapshot은 v5를 유지하되 `RULESET_VERSION="phase4-party-encounter-v2"`,
  `PartyPlaytestSession.SESSION_FORMAT_VERSION=2`, save path는
  `user://living_world_party_encounter_v2.json`이다. v1 ruleset/session을 조용히 해석하지 않는다.
- UI는 전투 종료 즉시 자동 재집결 완료와 탐험 재개를 한국어로 알린다. 수동 재집결
  surface는 없다.

이번 UX 기준은 탐험 D-pad를 제거하고 동일 15×15 grid를 기본 이동 입력으로 쓴다.
탐험과 전투 MOVE 모두 1차 타일 탭은 순수 preview, 동일 칸 2차 탭은 선택/이동
확정이다. 비인접 칸은 상태를 바꾸지 않고 “장거리 이동은 아직 지원하지 않습니다”라고
알린다. 장거리 auto-walk는 FOV/LOS와 함께 후속 단계다.

grid 아래에는 최대 3인의 고정 Party HUD를 둬 360px 폭에서도 세 초상화를 동시에
보인다. 각 슬롯은 atlas 얼굴/상반신 확대 crop, 이름, 실제 HP current/max와 bar,
가짜 MP 대신 실제 busy 기반 행동 준비/행동 중, stress 수치와 bar, HP·stress·personality로
결정론적으로 파생한 감정 icon+한국어를 표시한다. 원소와 행동 근거는 선택 상세
ScrollContainer로 내린다. 파티 턴 일괄 확정, 동료 자동 제안과 override 동시 표시,
보조 16px·본문 18px·핵심 20–24px 및 44px 터치 타깃 계약은 유지한다.

## 0. Sol High에게 주는 단일 목표

이 저장소에 아래 플레이 흐름을 구현하라.

```text
EXPLORATION: 15×15 월드에서 주인공 토큰 하나만 표시·직접 조작
→ 적 탐지 또는 매복
ENCOUNTER_PREVIEW: 같은 grid 위에서 최대 3명 배치
→ 주인공 행동 직접 지정 + 동료 제안 미리보기 + 동료별 override
COMBAT: 한 번의 파티 턴으로 원자적 commit
→ 승리 후 자동 합체하지 않음
REGROUP: 사용자가 명시적으로 재집결
→ 다시 주인공 토큰 하나만 점유·표시
```

새 전투 장면이나 별도 좌표계를 만들지 않는다. 탐험, 배치, 전투, 재집결은 모두 같은 `SimWorldState`, 같은 15×15 tile 좌표, 같은 grid `Control` 인스턴스를 사용한다.

## 1. 절대 동결 영역

아래 네 파일과 공개 계약은 Phase 3의 rigid 4-room/12-actor fixture다. 수정, 이름 변경, 상속, 재사용을 금지한다.

- `sim/encounter_lab_state.gd`의 `EncounterLabState`
- `sim/systems/actor_coordinator.gd`의 `ActorCoordinator`
- `playtest/playtest_session.gd`의 `PlaytestSession`
- `playtest/playtest_sandbox.gd`와 기존 scene의 personality lab

Phase 4는 반드시 병렬의 nullable 도메인으로 추가한다.

- `PartyEncounterState`
- `PartyEncounterCoordinator`
- `PartyPlaytestSession`
- `PartyEncounterSandbox`

기존 테스트를 삭제·skip·완화하지 않는다. snapshot 버전 기대값처럼 계약상 필요한 assertion만 v5로 갱신하고, 기존 테스트의 검증 의도와 Phase 3 fixture 결과는 보존한다.

## 2. 원칙과 비목표

원칙:

- core가 phase, 점유, HP, status, 시간, 사건의 SSOT다. UI visibility가 규칙이 아니다.
- preview는 순수 함수이며 RNG, ID, event, world time, entity, relation, stress를 바꾸지 않는다.
- commit은 전체 파티 행동을 한 transaction으로 처리한다.
- 모든 정렬과 동률 해소는 명시하며 Dictionary iteration 순서에 의존하지 않는다.
- int64 wire 값은 기존 `Int64Codec` canonical decimal string 규칙을 따른다.
- facade는 JSON-shaped detached DTO만 반환한다. core 객체나 내부 Array/Dictionary 참조를 노출하지 않는다.
- 성격과 관계는 동료 제안과 stress에만 영향을 준다. 합법적인 override를 거부시키지 않는다.

엄격한 MVP 비목표:

- hazard-aware AI pathing
- FOV, fog of war, line-of-sight 탐지, minimap
- 한 world의 동시/연속 multiple encounter
- inventory, equipment, skills, cooldown skill bar
- drag deployment
- ranged attack, hit roll, random damage
- 자리 교환, 이동 chain, 완전 동시 이동
- 동료의 자의적 명령 거부, 이탈, 배신

## 3. authoritative 상태와 UI 상태를 분리한다

`PartyEncounterState.safe_phase`는 settled snapshot에 저장되는 상태다.

```text
GROUPED           탐험 중, 주인공만 점유
CONTACT           탐지 완료, 배치 결정을 기다림
ENGAGED           배치 완료, 파티 턴 결정을 기다림
REGROUP_READY     적 전멸, 명시적 재집결을 기다림
GROUPED_COMPLETE  재집결 완료, encounter 종료
PARTY_DEFEATED    주인공 사망으로 종료
```

UI의 `view_mode`는 저장하지 않고 매 refresh마다 다음처럼 파생한다.

```text
GROUPED/GROUPED_COMPLETE → EXPLORATION
CONTACT                  → ENCOUNTER_PREVIEW
ENGAGED                  → COMBAT
REGROUP_READY            → REGROUP
PARTY_DEFEATED           → COMBAT + terminal overlay
```

`DEPLOYING`, animation 진행률, 선택 카드, 열린 deck, hover, camera는 authoritative phase가 아니다. transaction 중간 상태를 snapshot할 수 없어야 한다.

각 party member의 `presence`는 다음 중 하나다.

```text
DEPLOYED   grid를 점유하고 이동·공격·피격 대상이 됨
GROUPED    주인공 anchor에 논리적으로 동행하지만 별도 cell을 점유하지 않음
DORMANT    이번 전투의 미배치 reserve; cell·target·path obstacle이 아님
DEFEATED   HP 0; cell·target·path obstacle이 아님
```

`GROUPED`와 `DORMANT`는 sprite만 숨겨 구현하지 않는다. `SimWorldState.occupying_entities_at()`와 `blocking_entity_at()`가 이 상태를 제외해야 하며 renderer도 같은 core DTO를 따른다. entity의 유효한 저장 좌표가 anchor여도 점유하지 않는다.

## 4. 파티원 HP·status·원소 노출 계약

세 파티원은 grouped 여부와 무관하게 각자의 `SimEntity.health/max_health`, `status_ids`, `species_id`를 유지한다. 합산 HP를 만들지 않는다.

`PartyPlaytestSession.party_cards()`는 roster slot 순서로 정확히 세 row를 반환한다.

```text
entity_id, roster_slot, role, display_name
health, max_health, alive, status_ids, presence
logical_position
element_exposure {
  applicable, sampled_step_index, sampled_world_time, position,
  fire_score, water_score, electric_score, poison_score, total_risk
}
stress, override_state
```

결정론적 위치·노출 규칙:

- `DEPLOYED`: 자기 entity position에서 기존 `ExposureSystem.evaluate_for_entity()`를 사용한다.
- `GROUPED`: 주인공 현재 position을 `logical_position`으로 사용해 각자의 species affinity로 따로 평가한다.
- 같은 environment tick의 fire/electric damage도 grouped 생존자 각각에게 entity ID 오름차순으로 적용한다.
- `DORMANT/DEFEATED`: `applicable=false`, position `[-1,-1]`, 네 component와 total은 0이다.
- status는 정렬·중복 없는 최대 8개 stable ID다. MVP bootstrap은 빈 배열이어도 UI에 `정상`으로 보인다.
- 이 DTO 계산은 snapshot이나 event를 바꾸지 않는다.

이를 위해 환경 피해용 `exposed_entities_at(position)`을 점유 query와 분리한다. Phase 3에서는 두 query 결과가 기존과 같아야 한다.

## 5. fixture와 탐지·매복

`PartyPlaytestSession.reset_party(world_seed, personality_seed)`는 정확히 15×15 world, 주인공 1명, 동료 2명, melee enemy 1~2명을 만든다. 파티원은 roster slot `0,1,2`; slot 0은 주인공이다. 최초에는 주인공만 `DEPLOYED`, 동료는 `GROUPED`다.

탐지는 `system.actor_tick`에서만 평가한다. FOV 대신 Chebyshev 거리와 snapshot 저장 정수 반경을 쓴다.

```text
party_detects = distance(anchor, nearest_enemy) <= party_detection_radius
enemy_detects = distance(anchor, nearest_enemy) <= enemy_detection_radius
둘 다 true  → DETECTED
party만 true → PARTY_AMBUSH
enemy만 true → ENEMY_AMBUSH
둘 다 false → GROUPED 유지
```

nearest enemy 동률은 `(distance, entity_id)`다. contact event와 `contact_kind`, enemy ID, anchor, facing을 한 transaction으로 저장한다. facing은 적 방향의 절댓값이 큰 축, 동률이면 세로축 우선으로 cardinalize한다.

`PARTY_AMBUSH`는 배치 뒤 적 `busy_until = now + 100`, `DETECTED`는 보정 없음, `ENEMY_AMBUSH`는 CONTACT 전환 transaction 안에서 적의 합법적인 opening melee/HOLD를 entity ID 순서로 먼저 적용한다. opening batch가 실패하면 contact 전체가 rollback된다.

## 6. 배치와 formation

한 encounter에 `MAX_DEPLOYED_PARTY = 3`이며 주인공을 포함한다. sandbox roster는 세 명이지만 API는 선택 companion ID 배열을 받고 초과를 거부한다.

지원 preset과 local offsets:

```text
WEDGE:  protagonist (0,0), companion 1 back-left, companion 2 back-right
LINE:   protagonist (0,0), companion 1 left,      companion 2 right
COLUMN: protagonist (0,0), companion 1 back,      companion 2 back×2
```

`back=-facing`, `right=(-facing.y, facing.x)`, `left=-right`로 world offset을 계산한다.

`preview_deployment(preset_id, companion_ids)`는 순수하다. 배치 순서는 주인공, 그다음 `(roster_slot, entity_id)`다. 주인공은 contact anchor를 유지한다. companion은 preset 목표 cell을 먼저 시도하고, 막혔으면 anchor 반경 1, 2의 후보를 `(Chebyshev distance, Manhattan distance, y, x)`로 탐색한다.

cell은 bounds 안, passable, 기존 점유 없음, 먼저 예약한 deployment 없음, diagonal flank 규칙 충족이어야 한다. 적 cell은 항상 차단한다. 두 companion을 모두 놓을 수 없으면 `deployment_space_unavailable`로 전체 거부하고 state/event/ID는 불변이다. 선택되지 않은 생존 companion은 `DORMANT`다.

`commit_deployment(plan)`은 plan의 base fingerprint를 다시 검증한다. stale 또는 leaf 실패 시 모두 rollback한다. 성공 event 순서는 contact cause 뒤 `(party roster_slot, entity_id)`이고, 마지막에 `party.deployment_completed`를 emit한 뒤 `ENGAGED`로 전환한다.

## 7. 파티 턴 command와 순수 preview

기존 `SimCommand` wire를 억지로 확장하지 않는다. 다음 병렬 immutable value object를 만든다.

```gdscript
PartyActionCommand.hold(actor_id: int)
PartyActionCommand.move_to(actor_id: int, destination: Vector2i)
PartyActionCommand.melee(actor_id: int, target_id: int)

PartyTurnRequest.new(protagonist_action: PartyActionCommand, overrides: Array)
# overrides row: {actor_id, action}; companion마다 최대 하나, actor_id 오름차순 wire
```

지원 leaf는 `HOLD`, 인접 8방향 `MOVE`, 인접 `MELEE`뿐이다. MOVE는 기존 `MovementSystem.assess_move_in_projection()`, MELEE는 기존 `MeleeCombatSystem.can_attack()`의 pre-action projection 규칙을 공유한다. HOLD와 MELEE cost는 100, MOVE는 terrain cost다.

`PartyEncounterCoordinator.preview_party_turn(request)`는:

1. `ENGAGED`, settled world, 주인공 ready/alive/deployed, request canonical shape를 검증한다.
2. 주인공 직접 행동을 검증한다.
3. 각 ready deployed companion에 deterministic suggestion을 만든다.
4. companion별 합법적인 override가 있으면 suggestion 대신 사용한다.
5. frozen pre-action occupancy에서 destination conflict를 해결한다.
6. event headroom과 최대 time cost를 preflight한다.
7. detached `PartyTurnPlan`을 반환한다.

plan은 `accepted/reason`, canonical request, base step/time/revision/fingerprint, actor rows, total time cost, 예상 timeline을 가진다. fingerprint는 canonical snapshot의 전부가 아니라 해당 encounter revision, step/time, actor position/HP/presence/busy, enemy position/HP, 관련 tile terrain을 stable key order로 JSON화한 SHA-256이다.

preview 호출 전후 snapshot JSON, RNG state, next IDs, events, relations, stress가 byte-identical이어야 한다.

## 8. 제안, override, 성격·관계·stress

동료 suggestion 후보는 MELEE, 인접 MOVE, HOLD다. hard legality 후 fixed integer score 내림차순, 동률은 `MELEE < MOVE(direction order) < HOLD`의 명시 rank로 고른다.

성격과 관계가 허용되는 영향은 다음뿐이다.

- aggression/boldness: MELEE 접근·공격 점수
- composure: 위험 tile을 향하는 일반 MOVE의 감점과 stress 완화
- companion→protagonist effective trust/gratitude/grievance: 주인공 target 보조와 근접 유지 점수
- override가 suggestion과 다르면 stress delta 계산

MVP 경로 탐색은 hazard score를 읽지 않는다. 제안 MOVE는 목표까지의 기존 geometric/terrain path 첫 칸만 사용한다.

override는 합법성이 같다면 항상 실행한다. stress, 낮은 trust, 높은 fear, personality label 때문에 `refused`, 임의 HOLD, command 교체를 만들지 않는다. stress는 `0..1000` 정수이며 override commit 성공 시에만 갱신한다. preview나 실패 transaction은 stress를 바꾸지 않는다.

## 9. 충돌, ordering, commit, rollback

같은 destination을 요구한 MOVE 우선순위는:

```text
DIRECT protagonist > OVERRIDE companion > SUGGESTED companion
→ roster_slot 오름차순 → actor_id 오름차순
```

SUGGESTED loser는 HOLD로 deterministic downgrade하고 plan에 `destination_conflict_suggested_hold`을 남긴다. DIRECT/OVERRIDE끼리 충돌하거나 override가 pre-action 점유 cell로 이동하면 preview 전체를 `destination_conflict`로 거부한다. swap과 vacated-cell chain은 MVP에서 거부한다.

`commit_party_turn(plan)`은 base fingerprint와 canonical plan hash를 재계산한다. step/time/revision/HP/position/busy/terrain이 하나라도 바뀌면 `stale_party_plan`이며 무변경이다.

성공 commit 순서:

```text
freeze pre-action projection
→ 모든 leaf·event headroom·time overflow 재검증
→ action intent를 (protagonist first, roster_slot, actor_id)로 staging
→ MOVE/MELEE/HOLD leaf event와 damage를 같은 순서로 commit
→ override stress commit
→ 각 member busy_until = start + individual cost
→ external step_index 한 번 증가
→ world_time을 max individual cost만큼 진행하며 기존 schedule 처리
→ 적 전멸이면 REGROUP_READY
```

같은 batch 시작 시 살아 있고 공격이 pre-action에서 합법이었던 actor의 MELEE는 앞선 damage로 actor가 죽더라도 실행한다. target이 먼저 죽어 남는 초과 공격은 action event만 emit하고 damage 0으로 정규화한다. 이 규칙을 테스트로 고정한다.

어떤 actor leaf, schedule handler, event emission, damage, stress 갱신이 실패해도 pre-step snapshot으로 world time, schedules, RNG, IDs, events, HP, positions, presence, busy, revision 전부 복원한다. 부분 commit은 금지한다.

## 10. 시간과 actor cadence

기존 두 repeating schedule을 유지한다.

```text
system.environment_tick priority=100 repeat=100
system.actor_tick       priority=200 repeat=100
```

별도 combat clock, paused sub-world, encounter turn counter를 만들지 않는다. 파티 MOVE/MELEE/HOLD와 enemy action은 같은 `world_time`과 `busy_until`을 사용한다. accepted 외부 exploration command, deployment, party-turn, regroup만 각각 `step_index`를 한 번 증가시키며 내부 actor action은 증가시키지 않는다.

`Simulator._dispatch_schedule("system.actor_tick")`는 mutual exclusion에 따라 lab이면 기존 `ActorCoordinator`, party이면 새 `PartyEncounterCoordinator`, 둘 다 null이면 no-op을 호출한다. 두 coordinator를 같은 tick에 호출하지 않는다.

## 11. 승리와 명시적 재집결

마지막 enemy가 죽은 transaction의 settled end에서 `safe_phase=REGROUP_READY`가 된다. UI는 `REGROUP`을 보여주며 자동으로 토큰을 합치지 않는다.

`PartyPlaytestSession.regroup()`은 살아 있는 주인공, 적 0, settled world, `REGROUP_READY`일 때만 가능하다. cost 100인 원자적 command다.

- 주인공 현재 position을 새 group anchor로 삼는다.
- 생존 companion을 roster 순으로 `GROUPED`, 모든 미배치 `DORMANT`도 `GROUPED`로 만든다.
- companion 저장 position을 anchor로 정규화한다.
- defeated는 `DEFEATED`로 유지한다.
- `party.regroup_started`, member별 `party.member_regrouped`, `party.regroup_completed`를 emit한다.
- `GROUPED_COMPLETE`로 전환한 뒤 world에는 주인공 하나만 점유·render된다.

regroup 버튼을 누르지 않은 상태를 저장·불러와도 `REGROUP_READY` 그대로여야 한다.

## 12. snapshot v5와 canonical serialization

`SimWorldState.SNAPSHOT_VERSION = 5`, `RULESET_VERSION = "phase4-party-encounter-v1"`로 올린다. v4를 암묵 migration하지 말고 `unsupported_snapshot_version`으로 거부한다.

top-level에 정확히 다음 key를 추가한다.

```text
party_encounter: null | PartyEncounterState.to_dict()
```

`encounter_lab`와 `party_encounter`는 XOR-or-null이다. 둘 다 non-null이면 wire와 runtime validation 모두 `encounter_mode_conflict`로 거부한다. lab snapshot도 v5에서 `party_encounter:null`을 canonical하게 포함한다.

`PartyEncounterState` wire는 stable exact keys, 정렬된 member/enemy rows, canonical int64 string, bounded array, 알려진 enum만 허용한다. 최소 저장 필드:

```text
schema_version, encounter_id, safe_phase, revision
protagonist_id, party_member_ids, enemy_ids
group_anchor, facing, contact_kind, contact_enemy_id
party_detection_radius, enemy_detection_radius
formation_id, member_rows, enemy_busy_rows
```

member row는 `entity_id, roster_slot, role, presence, busy_until, stress, status_ids, personality_profile`을 가진다. 주인공 personality는 nullable exact contract, companion은 canonical profile을 요구한다. suggestion, preview, fingerprint, UI view_mode, selection, hit rect는 저장하지 않는다.

restore는 wire 검증 뒤 semantic 검증을 한다. entity 참조, HP/presence, 중복 ID, max deployed 3, anchor/position, phase별 점유 수, enemy 생존 수, schedule 두 개, event cause chain을 검증한다. parse 실패는 null restore이며 live session을 바꾸지 않는다.

`PartyPlaytestSession.SESSION_FORMAT_VERSION = 1`, save path는 `user://living_world_party_encounter_v1.json`이다. journal에는 canonical exploration request, deployment request, party turn request, regroup command만 기록한다. suggestion 결과는 기록하지 않고 replay 시 같은 preview를 재생성해 snapshot equality를 확인한다.

## 13. facade DTO와 정확한 공개 API

새 core API:

```gdscript
SimWorldState.occupying_entities_at(position: Vector2i) -> Array
SimWorldState.exposed_entities_at(position: Vector2i) -> Array
SimWorldState.party_member_state(entity_id: int)

LivingWorldSimulator.preview_party_turn(request) -> PartyTurnPlan
LivingWorldSimulator.step_party_turn(plan) -> SimStepResult
LivingWorldSimulator.preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary
LivingWorldSimulator.deploy_party(plan: Dictionary) -> SimStepResult
LivingWorldSimulator.regroup_party() -> SimStepResult
```

새 session API:

```gdscript
reset_party(world_seed: int, personality_seed: int) -> bool
party_status() -> Dictionary
observe_party_world() -> Dictionary
party_cards() -> Array[Dictionary]
preview_exploration(command: SimCommand) -> Dictionary
commit_exploration(command: SimCommand) -> Dictionary
preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary
commit_deployment() -> Dictionary
begin_turn(protagonist_action: PartyActionCommand) -> Dictionary
override_companion(entity_id: int, action: PartyActionCommand) -> Dictionary
clear_companion_override(entity_id: int) -> Dictionary
current_turn_preview() -> Dictionary
commit_turn() -> Dictionary
regroup() -> Dictionary
recent_event_log(limit: int = 24) -> Array[Dictionary]
save_session_json() -> String
load_session_json(encoded: String) -> Dictionary
```

`begin_turn/override/clear`는 session의 UI draft만 바꾸고 world는 바꾸지 않는다. world fingerprint가 달라지면 draft를 폐기한다. 모든 반환값은 deep detached, Vector2i 대신 `[x,y]`, core object 대신 scalar/Array/Dictionary다.

## 14. 같은 grid scene과 모바일 UI 예산

`PartyEncounterSandbox`는 시작부터 끝까지 `PartyGridView` 하나를 유지한다. phase 전환 때 scene reload, grid 교체, 별도 combat viewport를 금지한다. 테스트는 `grid.get_instance_id()`와 world cell→pixel mapping이 EXPLORATION부터 regroup 이후까지 동일함을 확인한다.

portrait 예산:

| 영역 | 360×640 | 450×800 |
|---|---:|---:|
| top phase/status bar | 40 px | 48 px |
| 15×15 grid | 300×300 px | 330×330 px |
| three-card strip | 108 px 이하 | 138 px 이하 |
| context deck | 남은 180 px 이하 | 남은 260 px 이하 |

가로 padding은 총 12 px 이하, horizontal scroll은 금지한다. 세 member card는 항상 한 줄에 보이며 각각 portrait/name, HP, status, 4-element compact indicator, suggestion/override badge를 가진다. 선택 card만 상세 문구를 context deck에 펼친다.

모든 버튼과 card touch target은 최소 44×44 px다. grid actor sprite는 cell 안에서 그리되 actor hit rect는 최소 28×28 px로 확장한다. 겹치는 hit rect는 `(pointer와 center 거리, protagonist 우선, roster_slot, entity_id)`로 선택한다. grid 밖 click과 modal open 중 world input은 no-op이다.

context deck 내용:

- EXPLORATION: 8방향/대기와 탐지 상태
- ENCOUNTER_PREVIEW: WEDGE/LINE/COLUMN, 배치 순서, 확정
- COMBAT: 주인공 HOLD/MOVE/MELEE, 동료 suggestion 두 개, 개별 override/복원, 턴 확정
- REGROUP: 전투 결과와 큰 `재집결` 버튼

360×640과 450×800에서 overlap, clipping, horizontal overflow, 20 px 미만 cell, phase 변경 중 selection 상실이 없어야 한다.

## 15. 한국어 narrative events

raw enum을 사용자 log에 그대로 노출하지 않는다. 최소 mapping:

```text
encounter.detected          "고블린과 파티가 서로를 발견했다."
encounter.party_ambush      "파티가 고블린보다 먼저 기척을 알아챘다."
encounter.enemy_ambush      "고블린이 숨어 있던 곳에서 파티를 덮쳤다."
party.member_deployed       "동료 나래가 대형의 왼쪽에 자리를 잡았다."
party.deployment_completed  "파티가 전투 대형을 갖췄다."
action.move                 "주인공이 (x,y)로 움직였다."
action.melee_attack         "동료 나래가 고블린을 공격했다."
combat.physical_damage      "고블린이 N의 피해를 입었다."
party.override_committed    "나래는 지시한 행동으로 계획을 바꿨다."
party.victory               "마지막 적이 쓰러졌다. 파티를 재집결할 수 있다."
party.regroup_started       "주인공이 동료들을 불러 모았다."
party.member_regrouped      "나래가 주인공 곁으로 돌아왔다."
party.regroup_completed     "파티가 다시 한 무리로 길을 나설 준비를 마쳤다."
```

preview suggestion은 사건이 아니므로 event log에 쓰지 않는다. 이름의 한국어 조사 처리는 기존 `_subject/_object/_topic`와 동등한 helper를 새 session 안에 둔다.

## 16. 정확한 파일 계획

새 파일:

- `sim/party_member_state.gd` — role/presence/busy/stress/status/profile canonical row
- `sim/party_encounter_state.gd` — safe phase, roster, contact, formation, v5 nested wire
- `sim/party_action_command.gd` — HOLD/MOVE/MELEE canonical value object
- `sim/party_turn_request.gd` — protagonist action과 companion overrides canonical wire
- `sim/party_turn_plan.gd` — immutable detached preview와 fingerprint
- `sim/systems/party_encounter_coordinator.gd` — detection, deployment, suggestion, enemy tick, atomic batch
- `playtest/party_playtest_session.gd` — fixture, draft, journal, save/load, Korean DTO
- `playtest/party_grid_view.gd` — 동일 grid render/input/hit rect
- `playtest/party_encounter_sandbox.gd`
- `playtest/party_encounter_sandbox.tscn`
- `tests/test_phase4_party_encounter.gd`
- `tests/test_party_playtest_session.gd`
- `tests/test_party_playtest_ui.gd`
- `tests/party_ui_layout_smoke.gd`

변경 파일:

- `sim/world_state.gd` — snapshot v5, nullable `party_encounter`, occupancy/exposure query, XOR validation
- `sim/simulator.gd` — party coordinator rebuild·dispatch, parallel preview/commit transaction API
- `sim/systems/environment_system.gd` — 피해 query를 `exposed_entities_at`으로 분리
- `sim/systems/movement_system.gd` — projection이 Party non-occupancy를 존중하는 regression-safe query
- `sim/systems/melee_combat_system.gd` — party preflighted attack와 이미 죽은 attacker의 staged attack 지원
- `project.godot` — main scene만 새 party sandbox로 변경; 기존 lab scene 보존
- `tests/test_snapshot_time.gd`, `tests/test_phase3_personality_lab.gd` — 삭제 없이 v5 header/null key 기대만 갱신
- `tests/run_tests.gd` — 기존 자동 발견을 유지하므로 원칙상 변경 불필요

동결 네 파일에는 diff가 없어야 한다.

## 17. 테스트와 acceptance criteria

core:

- 최초 world에서 주인공 하나만 점유·render되고 grouped companion은 collision/path blocker가 아니다.
- grouped 세 명의 HP/status/exposure DTO가 개별 species 기준으로 결정론적이다.
- grouped fire/electric 피해가 세 entity에 ID 순으로 개별 적용된다.
- 거리 경계 바로 밖/안과 세 contact kind가 정확하며 같은 seed 결과가 같다.
- deployment preset 회전, fallback ordering, 최대 3명, 공간 부족 무변경 실패를 검증한다.
- DORMANT/GROUPED가 단순 sprite hide가 아니라 occupancy와 target query에서 제외된다.
- party와 lab의 nullable XOR를 wire/runtime 모두 거부한다.
- Phase 3 lab v5 round trip과 행동 결과가 버전 key 외 기존과 같다.

turn:

- 주인공 direct, companion suggestion, 개별 override 두 개를 한 번만 commit한다.
- personality/relation 변화가 suggestion/stress에는 반영되지만 합법 override는 절대 거부하지 않는다.
- HOLD/MOVE/MELEE legality, cost, busy_until, max-cost world time을 검증한다.
- preview 100회 호출 전후 snapshot/event/RNG/ID가 같다.
- stale step/time/revision/HP/position/terrain 각각이 `stale_party_plan`으로 무변경 실패한다.
- suggested destination loser는 HOLD, direct/override conflict는 전체 거부한다.
- 마지막 actor fault injection에서도 HP/event/stress/position/time/ID 부분 commit이 없다.
- 같은 batch staged melee, dead target 초과 공격 규칙을 고정한다.
- `system.actor_tick`과 environment tick ordering, internal action의 step_index 불증가를 검증한다.

regroup/snapshot/session:

- 승리 직후 `REGROUP_READY`이며 여전히 배치 토큰이 보이고 자동 합체하지 않는다.
- 명시적 regroup 뒤 주인공 한 토큰만 점유·render되고 companion HP/status는 보존된다.
- REGROUP_READY와 GROUPED_COMPLETE 각각 v5 round trip이 동일하다.
- noncanonical int64, enum, row order, duplicate ID/status, 4명 배치, lab-party 동시 상태를 거부한다.
- save→load→replay snapshot JSON과 event log가 같다.
- facade DTO를 깊게 변조해도 world와 draft가 바뀌지 않는다.

UI:

- 같은 grid instance ID와 225-cell coordinate mapping이 전 phase에서 유지된다.
- 360×640, 450×800에서 세 카드·context deck·grid가 overlap/overflow 없이 들어간다.
- 모든 touch target 44 px, actor hit rect 28 px, overlap tie-break가 결정론적이다.
- companion 하나 override/clear가 다른 companion draft를 바꾸지 않는다.
- modal/focus loss/echo input 중 commit되지 않는다.
- 한국어 log에 raw `ENGAGED`, `MELEE`, `party.override_committed`가 노출되지 않는다.

완료 조건은 다음 두 명령이 모두 0으로 끝나는 것이다.

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/party_ui_layout_smoke.gd
```

## 18. 단계별 구현 순서

```text
A. v5 schema와 PartyMemberState/PartyEncounterState exact validation
B. occupancy/exposure query 분리 후 기존 전체 test green
C. PartyActionCommand/Request/Plan과 pure fingerprint preview
D. GROUPED 탐험, actor-tick detection, 세 ambush branch
E. formation preview/atomic deployment/failure tests
F. companion suggestion/override/stress와 destination resolution
G. simulator party-turn transaction, melee, rollback fault injection
H. victory/REGROUP_READY/explicit regroup
I. PartyPlaytestSession detached DTO, journal replay, save/load
J. 하나의 PartyGridView와 portrait UI
K. Phase 3 regression + Phase 4 soak + 두 viewport smoke
```

각 단계에서 기존 suite를 먼저 green으로 되돌린 뒤 다음 단계로 간다. UI로 core 결함을 가리지 않는다.

## 19. 완료 보고 형식

- 새 파일과 변경 파일 목록
- 동결 네 파일의 `git diff`가 비어 있다는 확인
- snapshot/ruleset/session 버전
- grouped non-occupancy와 exposure 구현 방식
- detection/formation/conflict tie-break 요약
- preview purity와 rollback fault-injection 결과
- 기존 테스트 수 / 새 테스트 수 / failure 수
- 360×640, 450×800 smoke 결과
- 남은 위험과 엄격한 MVP 제외 항목

commit, push, deploy는 사용자가 따로 요청하지 않으면 하지 않는다.
