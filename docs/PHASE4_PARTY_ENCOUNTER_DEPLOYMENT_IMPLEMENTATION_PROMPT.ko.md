# Phase 4 구현 프롬프트 — 동일 월드 파티 조우·배치·재집결

> **역사적 구현 프롬프트:** 배치·재집결 코어의 과거 계약을 보존한다. 아래의 임시 4-facet,
> 제품 개별 companion override, 수동 전술 입력 설명은 현재 파티 제품 계약이 아니다.
> 파티는 HEXACO 6축, 완전 자동 동료, 공유 인지와 다섯 파티 전체 예외 명령을 사용한다.
> 최신 상태는 `docs/PARTY_COMBAT_IMPLEMENTATION_STATUS.ko.md`와
> `docs/superpowers/specs/2026-09-02-party-autonomy-perception-design.md`가 우선한다.

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
확정이다. 인접 칸은 기존 1칸 MOVE를 그대로 확정한다. 비인접 칸의 1차 탭은 현재
전체 world 기준 `WeightedPathfinder` 경로·비용·동행자별 위험 ceiling을 순수 preview하고,
동일 칸 2차 탭부터 호출당 기존 1칸 MOVE를 하나씩 실행한다. 접촉·사망·stale·새
점유/대각 모서리 장애·위험 증가·core 거부에서 즉시 부분 정지한다. 별도 teleport,
core command, `auto_walk` journal kind는 없다. 이는 개발 sandbox용 route macro이며
FOV/LOS와 관찰 범위·affinity 안전 경로 정책은 여전히 후속 단계다.

grid 아래에는 최대 3인의 고정 Party HUD를 둬 360px 폭에서도 세 초상화를 동시에
보인다. 각 슬롯은 atlas 얼굴/상반신 확대 crop, 이름, 실제 HP current/max와 bar,
가짜 MP 대신 실제 busy 기반 행동 준비/행동 중, stress 수치와 bar, HP·stress·personality로
결정론적으로 파생한 감정 icon+한국어를 표시한다. card 첫 tap은 즉시 선택하고 같은
card double tap만 full-screen 상세 modal을 연다. 원소 affinity·현재 exposure·행동 근거·
관계는 session inspector DTO를 소비하는 modal ScrollContainer에 둔다. 같은 타일을 약
500ms 길게 누를 때만 terrain·이동비용·불/물/전기/독 위험을 mouse-ignore floating
popover로 열며, 일반 선택 tap이나 상시 card/context deck에 중복하지 않는다. 파티 턴
일괄 확정, 동료 자동 제안과 override 동시 표시,
보조 16px·본문 18px·핵심 20–24px 및 44px 터치 타깃 계약은 유지한다.

같은 world 좌표와 같은 `PartyGridView` 인스턴스를 유지하되 camera window는 phase에
따라 바뀐다. EXPLORATION·CONTACT·배치 preview와 승리 후 자동 재집결은 원점 기준
15×15 전체, 배치 확정 뒤 ENGAGED는 party/enemy cluster를 중심으로 clamp한 9×9다.
선택 actor/target이 crop 밖이면 다시 포함하도록 recenter한다. actor와 intent를 합친 필수
focus bounds가 x/y 어느 축이든 9칸 창보다 넓으면 같은 grid의 원점 15×15 전체 창으로
fallback해 필수 actor를 하나도 숨기지 않는다. compact cluster는 계속 9×9다. `world_cell_rect`,
`world_to_pixel_center`, 역 mapping과 pointer 입력은 `view_origin + visible_cell_count`를
유일한 authority로 쓰며 crop 밖 world cell은 입력할 수 없다. 이 camera crop은 후속
FOV/LOS와 무관하다.

ENGAGED에는 `⚔ 전투 중` banner/테두리를 계속 표시한다. `CombatActionArea`는
`InformationScroll` 밖 `PartyLayout`의 마지막 고정 sibling이며, 자동 줄바꿈
`ActionFeedback`과 최하단 `CombatActionDock`을 차례로 가진다. dock은 `선택 대기`,
`자동 제안 복원`, `턴 확정`만 가진다. facade가 준 한국어 거부 `message`는 reason token을
UI에서 다시 번역하지 않고 fixed feedback에 즉시 표시하며 scroll 이동과 무관하게 남는다.
설명·turn summary·선택 상세는 scroll 안 `ContextDeck`에 남고 버튼을 중복하지 않는다.
ActionArea는 ENGAGED에서만 높이 84px로 보이고 다른 phase에는 숨김/minimum 0이다.
승리 직후 banner는 `승리 · 자동 재집결`을 알리고 area를 숨기며 15×15로 zoom-out한다.

facade의 모든 feedback은 구조화된 `reason_code/reason_details/message`와
`visual_effects` field를 갖는다. preview/reject는 빈 효과 배열이다. accepted commit만
event에서 투영된 `SLASH/HIT_FLASH/FLOATING_AMOUNT/DEATH`를 UI에 전달하며,
`effect_id`로 중복 재생을 막되 같은 `event_id`의 hit flash와 floating amount는 모두
한 번씩 보인다. 지속 banner와 grid border/tone은 detached `presentation_state()`의
`banner/grid_style`을 소비한다.

`InformationScroll`의 narrative 영역은 `전투 기록 · 최근 8턴`을 유지한다. facade
`combat_log(8,80)`의 turn group과 row 순서를 그대로 사용해 자동 동료 공격, 피해 대상과
수치, instigator/cause, 사망을 이름과 함께 표시한다. 최신 combat commit 뒤 bottom을
보이되 새 root layout sibling을 추가하지 않고 과거 8턴으로 다시 scroll할 수 있어야 한다.

`GROUPED_COMPLETE` presentation은 transient `notice_text`가 아니라 phase에서 직접
도출한다. `banner.title=승리 · 자동 재집결`, `tone=VICTORY`, green `grid_style`을
다음 phase 전까지 유지한다. save/load 뒤 새 sandbox도 같은 banner/style을 즉시
보이고 과거 commit의 `visual_effects`는 다시 재생하지 않는다.

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
preview_exploration_route(goal: Variant) -> Dictionary
exploration_route_draft() -> Dictionary
exploration_route_state() -> Dictionary
start_exploration_route(goal: Variant, plan_hash: String) -> Dictionary
continue_exploration_route() -> Dictionary
cancel_exploration_route() -> Dictionary
preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary
commit_deployment() -> Dictionary
begin_turn(protagonist_action: PartyActionCommand) -> Dictionary
override_companion(entity_id: int, action: PartyActionCommand) -> Dictionary
clear_companion_override(entity_id: int) -> Dictionary
current_turn_preview() -> Dictionary
commit_turn() -> Dictionary
regroup() -> Dictionary
recent_event_log(limit: int = 24) -> Array[Dictionary]
combat_log(turn_limit: int = 8, row_limit: int = 80) -> Dictionary
inspect_tile(position: Variant, viewer_id: int = -1) -> Dictionary
inspect_party_member(entity_id: int) -> Dictionary
save_session_json() -> String
load_session_json(encoded: String) -> Dictionary
```

`begin_turn/override/clear`는 session의 UI draft만 바꾸고 world는 바꾸지 않는다. world fingerprint가 달라지면 draft를 폐기한다. 모든 반환값은 deep detached, Vector2i 대신 `[x,y]`, core object 대신 scalar/Array/Dictionary다.

## 14. 같은 grid scene과 모바일 UI 예산

`PartyEncounterSandbox`는 시작부터 끝까지 `PartyGridView` 하나를 유지한다. phase 전환 때 scene reload, grid 교체, 별도 combat viewport를 금지한다. world 좌표계는 항상 15×15지만 pixel mapping은 camera window에 따라 의도적으로 바뀐다. 테스트는 같은 `grid.get_instance_id()`, 15×15→9×9→15×15 전환, 승리 뒤 원점 full-view mapping의 exact 복귀를 확인한다.

portrait 예산:

| 영역 | 360×640 | 450×800 |
|---|---:|---:|
| top phase/banner | 48 px | 52 px |
| 탐험·조우 15×15 grid | 348×348 px | 405×405 px |
| 전투 9×9 grid | 300×300 px | 360×360 px |
| three-card strip | 160 px | 160 px |
| scroll 정보 영역 | 남는 높이, 최소 30 px | 남는 높이, 최소 30 px |
| ENGAGED 고정 ActionFeedback | 38 px, 16px font | 38 px, 16px font |
| ENGAGED 고정 action dock | 44 px, 18px font | 44 px, 18px font |
| ENGAGED 고정 ActionArea 합계 | 84 px(내부 gap 2 포함) | 84 px(내부 gap 2 포함) |

가로 padding은 총 12 px 이하, horizontal scroll은 금지한다. 세 member card는 항상 한 줄에
보이며 각각 portrait/name, 실제 HP·stress, readiness, 감정 상태를 가진다. 상시
4-element row는 두지 않는다. card 첫 tap은 선택만 하고, 같은 card의 native touch
double tap/mouse double click 또는 350ms·24px fallback만 `MemberDetailModal`을 연다.
modal은 viewport 12px margin, 360에서 최대 336px·450에서 최대 420px 폭, 16px scroll body,
44px/18pt close를 사용한다. full-screen scrim은 input을 STOP하고 backdrop·close·Escape로
닫으며 열린 동안 `grid.modal_open=true`다. 진행 중 route는 modal 동안 pause하고 닫힌 다음
프레임부터 한 hop씩 재개한다. 첫 tap 선택과 두 번째 double tap은 route draft를 지우지
않고 같은 진행 상태를 modal 앞뒤로 보존한다.

모든 버튼과 card touch target은 최소 44×44 px다. grid actor sprite는 cell 안에서 그리되 actor hit rect는 44×44 px로 확장한다. 겹치는 hit rect는 `(pointer와 center 거리, protagonist 우선, roster_slot, entity_id)`로 선택한다. grid 밖, camera crop 밖 click과 modal open 중 world input은 no-op이다.

빈 타일과 actor 타일 모두 같은 지점을 약 500ms 길게 누를 때만
`inspect_tile(position, selected_member)`의 terrain, 이동 비용, 불/물/전기/독/총 위험을
`TileRiskPopover`에 표시한다. 짧은 선택 tap은 popover를 절대 열지 않고 기존
preview/같은-goal 두 번째 tap만 수행한다. popover 폭은
`min(280,viewport-24)`, font는 16px 이상, actual wrapped line 전체가 보이는 높이이며
viewport 12px 안으로 clamp한다. panel과 모든 child는 `MOUSE_FILTER_IGNORE`라 같은 tile의
다음 짧은 tap이 grid로 그대로 전달된다. touch와 mouse 모두 press target을 동결한 뒤
release에서만 short tap을 확정한다. 14px을 넘는 drag는 short/long을 모두 취소하고,
long press를 소비한 release는 world/actor signal을 0회 낸다. 두 번째 tap 안내는
EXPLORATION route에서만 보이고 COMBAT에는 인접 한 칸 계약을 명시한다.

먼 route overlay는 기존 line과 START/NEXT/GOAL marker를 유지하면서 전체 path tile에
반투명 highlight를 깔고 각 segment에 숫자 없는 방향 chevron을 표시한다. 진행 중 route는
grid pointer press 동안 pause한다. short release가 cancel/replan한 route는 재개하지 않고,
slop을 넘은 drag도 실제 release까지 pause ownership을 유지한다. drag cancel이나 long
inspection이면 release 다음 frame부터 다시 한 hop씩 진행한다.

context deck 내용:

- EXPLORATION: 8방향/대기와 탐지 상태
- ENCOUNTER_PREVIEW: WEDGE/LINE/COLUMN, 배치 순서, 확정
- COMBAT: 행동 설명, turn summary, 동료 suggestion과 개별 override의 실제/원래 제안 동시 표시
- GROUPED_COMPLETE: 승리·자동 재집결 완료와 탐험 재개 설명

COMBAT 조작 버튼은 context deck 항목이 아니라 scroll 밖 고정 `CombatActionArea`의
`CombatActionDock`에만 있다. 비전투 phase에는 ActionArea 전체가 layout에서 빠지고,
CONTACT의 44px 배치 버튼은 최소 30px 정보 viewport 안에서 scroll해 실제 접근 가능하다.

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

- 같은 grid instance ID를 유지하면서 compact 전투의 15×15→9×9→15×15가 전환되고 마지막 full mapping이 처음과 정확히 같다.
- 필수 actor/intent bounds가 9칸을 넘으면 전투 중에도 same-grid 15×15 fallback으로 모두 보이며, 360px 폭 cell은 20px 이상이다.
- crop 양 끝 world↔pixel round trip이 정확하고 off-window cell의 pixel/hit/input surface가 없다.
- 360×640, 450×800에서 세 카드·context deck·grid·하단 ActionArea가 overlap/overflow 없이 들어간다.
- ENGAGED ActionArea는 viewport 최하단에서 information scroll과 독립이다. feedback의 모든 wrapped line이 실제 보이고, 세 버튼은 실제 viewport input으로 눌리며 44 px 이상·18 px font다.
- EXPLORATION/CONTACT/PREVIEW/GROUPED_COMPLETE에서는 ActionArea가 hidden/minimum 0이고, CONTACT 배치 버튼은 실제 scroll viewport 안에서 접근된다.
- 모든 touch target 44 px, actor hit rect 44 px, overlap tie-break가 결정론적이다.
- 먼 탐험 타일의 actual ScreenTouch 첫 입력은 world/journal 무변경 full-route preview이고,
  같은 goal 두 번째 입력은 첫 hop 하나만 시작한다. 이후 각 process frame은 최대 한 hop이며
  contact/stale/blocker/risk/reject에서 facade message와 함께 즉시 멈춘다.
- route overlay가 모든 path tile highlight, edge, 방향 chevron과 START/NEXT/GOAL marker를
  detached draw spec으로 보존하며 숫자 clutter 없이 목적지까지 명확히 이어진다.
- 360×640과 450×800 실제 root input에서 100ms 미만 short release만 preview/second-start를
  수행한다. touch/mouse 500ms 이상 hold만 tile popover를 열고, popover는 viewport 안에
  clamp되어 모든 wrapped line이 보이며 다음 short tap을 차단하지 않는다. long release는
  world/journal/draft를 바꾸지 않고, 14px 초과 ScreenDrag는 tap과 popover 모두 취소한다.
- active route의 pointer hold는 queued continuation을 멈추며 drag가 slop을 넘어도 물리적
  release 전에는 재개하지 않는다. long/drag release 뒤 다음 frame부터 정확히 한 hop씩
  재개한다. wrong touch index, OS cancel, modal/camera refresh와
  touch 직후 emulated mouse duplicate는 저장한 target을 emit하지 않는다.
- 실제 native portrait touch는 첫 tap 선택, 같은 card double tap 상세 modal을 지킨다.
  modal은 underlying grid를 막고 backdrop/close/Escape로 닫히며 active route를 pause/resume한다.
- 전투 기록은 facade의 최근 8 turn group을 `InformationScroll` 안에서 보존하고 자동 동료의
  공격·피해 이름/수치와 사망을 표시하며 최신 commit 뒤 bottom과 과거 scroll 양쪽이 가능하다.
- preview/reject는 visual effect가 없고 accepted commit 효과는 `effect_id`별 한 번만 그린다.
- fresh·save/load-restored `GROUPED_COMPLETE`는 local notice 없이도 같은 VICTORY banner/green grid style을 보이며 과거 효과를 replay하지 않는다.
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
