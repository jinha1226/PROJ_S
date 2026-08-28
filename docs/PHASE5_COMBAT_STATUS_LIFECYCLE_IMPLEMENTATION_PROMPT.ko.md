# Phase 5 구현 프롬프트 — 공통 전투 판정·상태·생명주기 v1

## 0A. 이 문서의 우선순위와 supersession

이 문서는 Phase 5 구현의 단일 authoritative guide다. 구현 중 애매한 점을 임의로 보완하거나 사용자에게 다시 질문하지 말고, 아래 계약과 acceptance test를 그대로 구현한다.

이 문서는 다음 Phase 4 계약을 **명시적으로 폐기하고 대체한다.**

- `fixed-melee-v1`과 경로별 고정 피해: Simulator 파티 직접 공격 `22`, 파티 적 공격 `14`, Phase 3 lead `22`/threat `18`을 각 coordinator가 직접 결정하던 구조
- `health == 0`이면 즉시 `entity.died`를 내보내던 계약
- `SimEntity.is_alive()` 또는 `health > 0` 하나로 행동 가능·점유·표적 가능·조우 미해결을 모두 판단하던 계약
- `PartyMemberState.status_ids`를 상태 authority로 보던 snapshot v5 계약
- 모든 `combat.*` event를 피해로 분류하던 facade/log 계약

Phase 4의 동일 월드, 직접 조작 주인공, 자율 동료, 배치, pure preview, 원자적 commit, zero-time 자동 재집결, route/touch UX는 유지한다. 충돌 시 전투 피해·HP 0·status·생명주기·전투 event에 한해 이 문서가 우선한다.

## 0. 구현 에이전트에게 주는 단일 목표

다음 두 기능을 하나의 원자적 Phase 5로 완성한다.

1. 파티와 Phase 3가 같은 `assess -> frozen batch -> atomic apply` 전투 kernel을 사용하는 **공통 근접 전투 판정 v1**
2. 모든 전투 개체가 같은 `ACTIVE / DOWNED / DEAD`와 하나의 `BLEEDING` row를 사용하는 **상태·생명주기 v1**

완료 기준은 새 demo만 보이는 것이 아니다. snapshot v6 strict restore, keyed roll 결정론, batch 동시성, status cadence, defeat/victory/regroup, rollback, session DTO, 한국어 log/effect, 기존 full suite가 모두 통과해야 한다.

## 1. 절대 동결 영역

다음은 깨뜨리지 않는다.

- 정수·고정소수점 결정론. float 확률·피해 계산 금지
- 전역 RNG의 기존 state와 draw 순서. 전투 판정은 전역 RNG를 한 번도 소비하지 않는다.
- environment schedule priority `100`, actor schedule priority `200`, 두 schedule의 interval `100`
- 같은 timestamp에서 environment가 actor보다 먼저 처리되는 순서
- Phase 3 decision batch의 기존 “batch 시작 시 유효했던 공격 의도는 모두 남는다”는 의미
- Phase 4 동일 target hero/companion intent 보존
- party preview의 무변경성과 stale/tampered plan 거부
- commit 전체 원자성: 실패 시 snapshot, RNG, event ID, schedule이 byte-equivalent로 복구됨
- 마지막 enemy가 최종 `DEAD`가 된 같은 `processed_step_index` 안에서 시간 `0`으로 끝나는 자동 재집결
- 15x15 기본 view, 장거리 touch route, long-press 위험 정보, portrait double-tap 상세, 최하단 고정 확정 버튼, 큰 글자
- load 직후 과거 transient effect를 재생하지 않는 계약
- event의 `cause_id`와 `instigator_id` 상속 규칙

기존 테스트를 삭제하거나 assertion을 느슨하게 해서 통과시키지 않는다. 새 event chain에 맞춰 정확한 기대값을 갱신한다.

## 2. 명시적 비목표

Phase 5에서는 아래를 구현하지 않는다.

- 신체 부위·절단·장기·상처 위치
- 무기·방어구 item, 장비 슬롯, 내구도
- 스킬·마법·ranged/projectile/AOE
- 명중 위치, cover, flank, initiative
- 여러 status를 조합하는 DSL 또는 script interpreter
- poison, stun, burn, wet, shock 등의 두 번째 status
- 새 ECS, component query framework, 별도 combat scene
- 행동 coordinator의 통합. Phase 3와 Party coordinator는 각자의 제안·성격·관계·AI 책임을 유지한다.
- CRIT. v1 outcome은 `HIT`, `MISS`, `OVERKILL_SKIP`, `FINISHER`뿐이다. profile/event에 사용되지 않는 crit 필드를 미리 넣지 않는다.

확장 seam은 registry와 data row까지만 만든다. 미래 기능의 빈 event·빈 status row·가짜 UI를 추가하지 않는다.

## 3. baseline seam과 교체 경계

| 현재 seam | 현재 의미 | Phase 5 조치 |
|---|---|---|
| `sim/simulator.gd` party direct path | hero/companion가 직접 `22` 적용 | coordinator가 frozen intent만 만들고 공통 kernel 호출 |
| `sim/systems/party_encounter_coordinator.gd` | enemy가 `14`, 별도 melee 호출 | 제안/충돌은 유지하고 frozen batch를 공통 kernel에 전달 |
| `sim/systems/actor_coordinator.gd` | lead `22`, threat `18`, 자체 batch damage | decision event와 batch 구축은 유지하고 공통 kernel apply 사용 |
| `sim/systems/melee_combat_system.gd` | adjacency + 고정 damage + AgentState guard | pure assess, keyed resolve, atomic batch apply의 단일 authority |
| `sim/systems/damage_system.gd` | HP 감소 후 HP 0이면 즉시 death | ACTIVE damage, DOWNED trauma, DOWNED/DEAD transition authority |
| `sim/party_member_state.gd` | party-only `status_ids` | status authority 제거; DTO가 CombatantState에서 파생 |
| `sim/world_state.gd` | snapshot v5, `fixed-melee-v1`, HP liveness | snapshot v6, combatant rows, 공통 predicates, mode-independent event validation |
| `playtest/party_playtest_session.gd` | HP와 party status 중심 projection | life/status/accuracy/detail/effect를 detached event에서 projection |

coordinator를 하나로 합치지 않는다. 공유하는 것은 아래 kernel뿐이다.

```text
coordinator-specific pure proposal/decision
  -> pure attack assessment
  -> canonical frozen batch
  -> one atomic apply kernel
  -> coordinator-specific liveness/outcome reconciliation
```

## 4. authoritative `CombatantState`

`sim/combatant_state.gd`를 새로 만들고 `WorldState.combatant_states: Dictionary`에 entity ID별 별도 canonical row로 둔다. 이것은 새 ECS가 아니라 WorldState가 소유하는 bounded domain row다.

모든 `add_entity()` 성공은 kind-to-profile mapping으로 CombatantState도 함께 만든다. mapping할 수 없는 kind는 명시적 default profile을 사용한다. entity만 있고 combatant row가 없는 부분 성공은 금지한다.

### 4.1 정확한 row

```text
CombatantState schema version: 1

entity_id: int64
life_state: "ACTIVE" | "DOWNED" | "DEAD"
combat_profile_id: String
guarded_until: int64
guard_source_event_id: int64
downed_at: int64                 # ACTIVE/DEAD이면 -1
downed_resolve_at: int64         # ACTIVE/DEAD이면 -1
downed_source_event_id: int64    # ACTIVE/DEAD이면 -1
recovery_lock_until: int64       # creation은 0
recovery_source_event_id: int64
status_rows: Array[CombatStatusRow]
```

`status_rows`는 `status_id` 오름차순이고 최대 8개를 wire validator가 허용하되, Phase 5 runtime registry에는 `BLEEDING` 하나만 존재하므로 실제 크기는 `0..1`이다.

`SimEntity.health`와 `max_health`는 계속 HP authority다. 생명 상태 authority는 CombatantState 하나뿐이다.

guard authority도 CombatantState의 `guarded_until`/`guard_source_event_id` 하나다. 기존 `AgentState.guarded_until`은 v6 row에서 제거하고 AgentState wire를 `agent-state-v2`로 올린다. HOLD와 전투 판정의 모든 read/write를 CombatantState로 옮긴다. 두 필드를 동기화하는 방식은 금지한다.

| life state | HP invariant |
|---|---|
| ACTIVE | `1 <= health <= max_health` |
| DOWNED | `health == 0` |
| DEAD | `health == 0` |

HP 1로 위장한 DOWNED, HP 0 ACTIVE, 별도 party/enemy death flag는 금지한다.

### 4.2 life별 sentinel 표

| field | ACTIVE | DOWNED | DEAD |
|---|---|---|---|
| `guarded_until` | `>= 0` | `0` | `0` |
| `guard_source_event_id` | `guarded_until==0`이면 `-1`; 양수면 valid `action.hold` | `-1` | `-1` |
| `downed_at` | `-1` | `>= 0` | `-1` |
| `downed_resolve_at` | `-1` | future canonical time; protagonist의 same-operation transient DOWNED만 `-1` | `-1` |
| `downed_source_event_id` | `-1` | valid `entity.downed` | `-1` |
| `recovery_lock_until` | `>= 0` | `0` | `0` |
| `recovery_source_event_id` | `recovery_lock_until==0`이면 `-1`; 양수면 valid `entity.recovered` | `-1` | `-1` |
| `status_rows` | `0..1` | `0..1` | empty |

ACTIVE가 DOWNED로 전이할 때 guard와 recovery lock 및 두 source를 `0/-1`로 지운다. DEAD 전이 때 downed fields도 `-1`로 지우고 status를 event와 함께 비운다. recovery 때 `recovery_lock_until=now+100`, `recovery_source_event_id=entity.recovered.id`를 설정한다. 이미 지난 ACTIVE guard/lock timestamp와 그 source event는 audit provenance로 남아도 되며 `can_act`/guard 식은 시각 비교로만 효력을 결정한다.

### 4.3 공통 predicate를 분리한다

WorldState에 다음 의미를 각각 구현하고, 갱신 대상 코드에서는 `SimEntity.is_alive()`를 의사결정에 사용하지 않는다.

```text
can_act(entity_id, at_time) =
  life_state == ACTIVE and at_time >= recovery_lock_until

occupies_tile(entity_id) =
  life_state != DEAD
  # 기존 GROUPED party co-location 예외는 유지

is_environment_exposed(entity_id) =
  life_state in [ACTIVE, DOWNED]

is_explicit_melee_target(entity_id) =
  life_state in [ACTIVE, DOWNED]

is_autonomous_target(entity_id) =
  life_state == ACTIVE

is_unresolved_enemy(entity_id) =
  life_state != DEAD
```

production의 `is_alive()`/`health > 0` liveness 분기는 전부 공통 predicate로 migration한다. 최소 감사 대상은 `movement_system.gd`, `weighted_pathfinder.gd`, `npc_coordinator.gd`(존재 시), `party_exploration_route.gd`, Phase 3 `playtest_session.gd`, Simulator와 두 coordinator다. HP 산술은 DamageSystem, HP/life semantic 비교는 WorldState validator만 허용한다. 구현 완료 시 `rg` allowlist test가 새 production liveness 분기를 잡아야 한다. `SimEntity.is_alive()`를 남기더라도 production call site는 0개다.

### 4.4 DOWNED의 정확한 의미

| 항목 | DOWNED |
|---|---|
| 몸/타일 점유 | 예. DEPLOYED이면 길을 막는다. |
| environment exposure | 예. 불·물·기존 hazard 처리 대상이다. |
| 직접 명시 표적 | 예. 새 batch/새 턴의 finisher 대상이 될 수 있다. |
| 자율 AI 표적 후보 | 아니오. 적·동료 AI가 스스로 마무리하지 않는다. |
| 행동·이동·제안 | 불가 |
| fresh batch 직접 공격 | guaranteed `FINISHER` |
| 추가 양수 damage | 즉시 DEAD로 전이 |
| 자연 종료 | 정해진 시각에 recovery, 또는 BLEED tick/추가 damage로 death |

DOWNED의 자력 이동은 금지한다. 다만 승리 시 zero-time 자동 재집결은 쓰러진 동료를 운반하는 system relocation으로 간주하여 GROUPED anchor로 옮길 수 있다. 이후 그룹 이동도 “운반”이며 그 동료가 행동한 것이 아니다.

DEAD만 비점유·비노출·비표적이다. DEAD party member의 presence는 `DEFEATED`다. DOWNED party member는 기존 `DEPLOYED` 또는 `GROUPED`를 유지한다.

## 5. combat profile registry

`sim/combat_profile_registry.gd`를 만들고 코드에 임의 damage literal을 남기지 않는다.

### 5.1 profile exact schema

```text
profile_id: String
accuracy_milli: int [0, 1000]
evasion_milli: int [0, 1000]
power: int [1, 1000000]
armor_flat: int [0, 1000000]
bleed_proc_milli: int [0, 1000]
bleed_resist_milli: int [0, 1000]
```

### 5.2 v1 registry와 kind mapping

| entity kind | profile ID | acc | eva | power | armor | bleed proc | bleed resist |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hero` | `party-hero-v1` | 600 | 150 | 24 | 2 | 650 | 100 |
| `companion` | `party-companion-v1` | 575 | 130 | 24 | 2 | 550 | 100 |
| `melee_enemy` | `party-goblin-v1` | 550 | 100 | 16 | 2 | 400 | 50 |
| `lead` | `phase3-lead-v1` | 600 | 150 | 24 | 2 | 650 | 100 |
| `melee_threat` | `phase3-threat-v1` | 550 | 100 | 20 | 2 | 400 | 50 |
| `passive_ally` | `phase3-passive-v1` | 500 | 130 | 12 | 2 | 250 | 100 |
| 그 외 | `combatant-default-v1` | 500 | 100 | 12 | 2 | 300 | 100 |

armor는 실제 core 판정에 항상 쓰이는 값이며 dead field가 아니다. 정상 `HIT`, non-guard에서 공격 power에서 대상 armor `2`를 뺀 뒤 기존 체감 피해를 그대로 보존한다.

- hero/companion -> goblin: `22`
- goblin -> hero/companion: `14`
- lead -> threat: `22`
- threat -> lead: `18`

profile dictionary key와 내부 `profile_id`가 다르거나 필드가 빠진 registry는 boot/test에서 즉시 실패한다.

## 6. 공통 판정 수식

모든 산술은 signed int64 중간값을 쓰고 나눗셈은 양수 정수 floor다. overflow를 preflight하고 clamp 뒤에만 event를 만든다.

### 6.1 명중

```text
hit_chance_milli = clamp(
  500 + attacker.accuracy_milli - target.evasion_milli,
  50,
  950
)

hit = hit_roll_milli < hit_chance_milli
```

동률은 miss다. `0..49`는 5% floor, `950..999`는 5% ceiling을 만든다.

### 6.2 armor와 guard

MISS와 FINISHER가 아닌 HIT에만 계산 결과를 적용한다.

```text
base_damage = attacker.power
armor_reduction = min(target.armor_flat, max(0, base_damage - 1))
after_armor = base_damage - armor_reduction

guarded = target life가 batch 시작 때 ACTIVE이고
          attack_start_world_time < frozen_guarded_until

guard_reduction = floor(after_armor * 250 / 1000) if guarded else 0
final_damage = max(1, after_armor - guard_reduction)
```

guard는 25%이고 기존처럼 `22 -> 17`, `14 -> 11`, `18 -> 14`다. 같은 batch에서 새로 HOLD한 guard가 이미 frozen된 공격에 소급 적용되지 않는다.

committed `action.hold`가 성공하면 candidate expiry는 `action world_time + 200`이다. candidate가 기존 `guarded_until`보다 클 때만 `guarded_until`과 `guard_source_event_id=action.hold.id`를 함께 갱신한다. 같거나 짧으면 기존 두 값을 유지한다. action emit/update 실패는 outer rollback이다.

### 6.3 BLEED proc

HIT가 실제 ACTIVE HP damage를 1 이상 적용했을 때만 판정한다. DOWNED finisher, OVERKILL_SKIP, MISS에는 적용하지 않는다.

```text
bleed_chance_milli = clamp(
  attacker.bleed_proc_milli - target.bleed_resist_milli,
  0,
  1000
)

bleed_proc = bleed_roll_milli < bleed_chance_milli
```

대상이 그 HIT로 DOWNED가 되어도 proc이 성공하면 BLEEDING을 적용한다.

## 7. keyed commit roll

전투는 `world.rng.randi*`, `randf`, seed 재설정, 임시 RNG를 모두 금지한다. SHA-256 keyed roll만 사용한다.

### 7.1 processed step은 outer operation이 전달한다

settled world에서 accepted outer operation을 시작하기 직전의 값을 `base_step_index`라 하고 다음을 overflow-safe하게 한 번 계산한다.

```text
processed_step_index := base_step_index + 1
```

Simulator/operation dispatcher가 이 값을 command, schedule occurrence, coordinator, assessment, kernel, DamageSystem, StatusSystem에 명시적으로 전달한다. coordinator나 WorldState가 현재 `_active_step_index`, event 수, schedule 위치에서 추론하면 안 된다.

key의 step, `PARTY_TURN` context, 그리고 그 outer operation에서 발생한 **모든** combat/status/lifecycle event의 `SimEvent.step_index`는 동일한 `processed_step_index`다. 하나의 command가 actor cadence와 enemy ambush를 함께 dispatch해도 모두 같은 값이다. 기준 예시는 settled base step `2`에서 시작하여 processed step `3`이다.

### 7.2 exact commitment와 lane key

```text
commitment_key = {COMBAT_RULESET_ID}|seed={world_seed}|step={processed_step_index}|time={attack_start_world_time}|batch={batch_context}|ordinal={intent_ordinal}|attacker={attacker_id}|target={target_id}

hit_key   = commitment_key + |lane=HIT
bleed_key = commitment_key + |lane=BLEED
```

- `commitment_key`는 `target={target_id}` segment로 끝나며 trailing `|`가 없다.
- `COMBAT_RULESET_ID = deterministic-melee-resolution-v1`
- 모든 정수는 leading zero 없는 canonical decimal
- UTF-8, 공백 없음, field 순서 변경 금지
- lane은 정확히 `HIT` 또는 `BLEED`
- party direct의 `attack_start_world_time`은 outer turn start time, actor cadence/ambush는 해당 occurrence due time이다. row별 MOVE time이나 apply 시각으로 다시 계산하지 않는다.
- `batch_context`는 coordinator가 아래 enum 형태로 만든다.
  - party direct: `PARTY_TURN/{processed_step_index}`
  - party enemy actor cadence: `PARTY_ENEMY/{actor_schedule_id}/{due_time}`
  - enemy ambush: `PARTY_AMBUSH/{actor_schedule_id}/{due_time}`. 즉시 contact에서 schedule occurrence가 없으면 schedule ID는 canonical `-1`, due time은 attack start time이다.
  - Phase 3 actor cadence: `PHASE3_ACTOR/{actor_schedule_id}/{due_time}`

### 7.3 roll 변환

```text
digest = SHA256(UTF8(key))
u31 = big_endian_uint32(digest[0..3]) & 0x7fffffff
roll_milli = u31 % 1000
```

reference vector:

```text
settled base step = 2
processed step = 3
commitment_key = deterministic-melee-resolution-v1|seed=44|step=3|time=200|batch=PARTY_TURN/3|ordinal=0|attacker=1|target=4
commitment hash = 31da9bf354e293ea453d56f126a8a3237d974b4191d48b5472f29ca2a862f418

HIT key = commitment_key + |lane=HIT
hash = bb11037a45dd86174f2045b3c275ff7e09e1eba4fe5a1aaf2d733b0325687ff1
roll = 746

BLEED lane hash = fa1afe5d417c07fa5c2525052dcabe140de1f759b7f8b652f4f46b0036ea102e
BLEED roll = 405
```

hash wire는 항상 lowercase 64-hex다. 서로 다른 key는 서로 다른 digest임을 test하되 `% 1000` roll 충돌은 정상이며 “roll까지 달라야 한다”는 assertion을 두지 않는다.

### 7.4 PartyTurnPlan의 공개 `combat_assessment`

별도 비공개 combat plan은 두지 않는다. PartyTurnPlan의 canonical `actor_rows` 각각에 nullable `combat_assessment` key를 추가한다. action type이 `MELEE`일 때만 Dictionary이고 나머지는 정확히 null이다.

wire key는 아래 목록과 정확히 같고 canonical encode/hash 순서도 아래 순서다.

```text
schema_version: int = 1
attacker_id: canonical int64 String
target_id: canonical int64 String
attacker_position: [int, int]
target_position: [int, int]
attacker_life_state: "ACTIVE"
target_life_state: "ACTIVE" | "DOWNED"
attacker_profile_id: String
target_profile_id: String
target_evasion_milli: int
target_armor_flat: int
frozen_guarded_until: canonical int64 String
guard_source_event_id: canonical int64 String
source: "DIRECT" | "SUGGESTED" | "OVERRIDE"
processed_step_index: canonical int64 String
attack_start_world_time: canonical int64 String
batch_context: String
intent_ordinal: int
intent_mode: "STRIKE" | "FINISHER"
hit_chance_milli: int
bleed_chance_milli: int
base_damage: int
armor_reduction: int
guarded: bool
guard_reduction: int
normal_final_damage: int
commitment_hash: lowercase 64-hex String
```

MELEE actor row를 roster slot, entity ID의 기존 canonical traversal로 읽었을 때 ordinal은 `0..melee_count-1` 연속이어야 한다. gap, duplicate, 음수, row 순서와 다른 ordinal을 wire 단계에서 거부한다. actor/target ID, profile, 두 position, life, guard/source, processed step/time, context, chance/damage, commitment 중 하나라도 다르면 tamper다. raw HIT/BLEED roll과 outcome은 이 row에 절대 넣지 않는다.

PartyTurnPlan accepted actor-row exact key set과 canonical `plan_hash` 입력에 `combat_assessment`를 포함한다. Dictionary insertion order에 의존하지 않고 위 명시 순서로 encode한다. null/non-null 전환도 plan hash와 equality를 바꾼다.

facade는 `combat_assessment`를 deep copy해 그대로 공개한다. commit은 (1) exact shape 검증, (2) 현재 authoritative state에서 같은 순서로 assessment 전부 rebuild, (3) exact deep equality 비교를 한 뒤에만 FrozenAttackIntent를 만든다. mismatch는 `stale_or_tampered_combat_plan`이며 snapshot/RNG/event ID/schedule/`visual_effects`가 모두 no-op이다.

### 7.5 preview와 commit 순수성

preview는 위 assessment의 chance, frozen formula input, `commitment_hash=SHA256(commitment_key)`만 공개한다. raw HIT/BLEED roll과 outcome은 공개하지 않는다.

preview를 100회 호출해도 snapshot, RNG state, `_next_event_id`, step/time, schedule, status, `visual_effects` queue가 모두 동일해야 한다.

## 8. frozen batch와 동시성

`FrozenAttackIntent`는 snapshot authority가 아닌 한 commit 동안만 존재하는 transient value object다. snapshot/UI save에 넣지 않는다.

### 8.1 batch 시작 assessment

coordinator는 mutation 전에 모든 후보를 평가한다.

- attacker가 batch 시작에 `can_act`
- attacker/target 존재
- Chebyshev 거리 1
- target이 ACTIVE이면 normal STRIKE 가능
- target이 DOWNED이면 **사용자가 명시한 target/override만** FINISHER 가능
- DEAD target은 거부
- autonomous proposal은 DOWNED를 선택하지 않음

Phase 3 decision event와 Party proposal/override 결정은 기존 순서를 유지한다. 그 뒤 frozen intent를 `(target_id, attacker_id, original_action_order)`로 정렬하고 `intent_ordinal = 0..N-1`을 부여한다.

### 8.2 apply 순서와 same-target 의미

kernel은 먼저 mutation/event가 전혀 없는 shadow HP/life projection에서 ordinal 순서대로 모든 outcome과 전이를 계산한다. 이 projection으로 OVERKILL_SKIP까지 확정한다. coordinator는 아래의 자기 canonical action 순서로 모든 `action.melee_attack`을 먼저 emit하고 action ID를 intent에 연결한다. 그 뒤 kernel이 ordinal 순서로 projected result를 실제 적용한다. apply 중 실제 상태가 projection과 다르면 assertion이 아니라 transaction failure로 처리하고 전부 rollback한다.

Party outer operation의 정확한 순서는 다음과 같다.

1. 기존 canonical actor-row traversal을 따른다.
2. MOVE/HOLD row는 기존처럼 즉시 commit한다.
3. MELEE row는 projected data를 가진 `action.melee_attack`만 emit하고 action ID와 frozen result를 collect한다. 이 시점에는 damage/status/lifecycle mutation이 없다.
4. `overridden=true` row는 action 종류와 무관하게 해당 leaf action 직후 `party.override_committed(cause_id=leaf.id)`를 emit한다. 즉 MELEE override event도 모든 combat result보다 앞선다.
5. busy/stress의 기존 canonical row mutation을 끝낸다.
6. 모든 frozen MELEE action이 emit된 뒤 intent ordinal 순서로 combat mutation을 apply한다.

Phase 3의 순서는 `모든 decision event -> 모든 action.melee_attack -> ordinal combat result`다. Party와 Phase 3 coordinator는 이 ordering adapter를 각각 소유한다.

공통 kernel은 snapshot을 만들거나 `begin_step`/`finish_step`을 호출하지 않는다. processed step과 rollback snapshot의 단일 owner는 outer Simulator operation이다.

batch 시작에 attacker가 `can_act`였다면 앞선 intent 때문에 apply 시점에 그 attacker가 DOWNED/DEAD가 되어도 frozen intent는 취소되지 않는다. 위치·profile·roll도 batch-start 값을 쓴다.

| target at batch start | target at this resolution | outcome | 후속 mutation |
|---|---|---|---|
| ACTIVE | ACTIVE | keyed `HIT` 또는 `MISS` | HIT만 damage/status |
| ACTIVE | DOWNED 또는 DEAD | `OVERKILL_SKIP` | 없음 |
| DOWNED, explicit | DOWNED | `FINISHER` | downed damage -> DEAD |
| DOWNED, explicit | DEAD | `OVERKILL_SKIP` | 없음 |

`OVERKILL_SKIP`도 action event, 두 roll 계산값, detached result row를 보존한다. 그러나 damage, status, downed, death event를 절대 만들지 않는다.

이 계약으로 다음을 동시에 보존한다.

- Phase 3 batch 시작에 ACTIVE였던 lead/threat의 공격 의도는 앞선 피해로 한쪽이 쓰러져도 사라지지 않는다.
- Party hero/companion이 같은 target을 골랐으면 두 action이 모두 log에 남는다.
- 첫 action이 target을 DOWNED로 만들면 같은 batch의 후속 action은 공짜 finisher가 되지 않는다.
- 다음 fresh turn에 사용자가 DOWNED target을 다시 고르면 명시적 finisher가 된다.

## 9. exact event chain과 `SimEvent.data` schema

중간 `combat.attack_resolved` event는 만들지 않는다. resolution은 `action.melee_attack.data`와 detached `AttackResolution` return DTO에 기록한다. 기존 damage/death visual attribution을 지키기 위해 physical damage의 직접 cause는 action event다. event payload 명칭은 실제 `SimEvent.data` 하나뿐이며 별도 payload alias를 만들지 않는다.

### 9.1 `action.melee_attack`

event actor는 attacker, target은 target, position은 frozen target position, magnitude는 base damage다. 기존 coordinator cause를 받는다. data exact keys:

```text
schema_version
combat_ruleset_id
attacker_profile_id
target_profile_id
batch_context
intent_ordinal
intent_mode                 # STRIKE | FINISHER
target_life_at_batch_start  # ACTIVE | DOWNED
outcome                     # HIT | MISS | OVERKILL_SKIP | FINISHER
processed_step_index
attack_start_world_time
commitment_hash
hit_chance_milli
hit_roll_milli
bleed_chance_milli
bleed_roll_milli
bleed_proc_succeeded
base_damage
target_evasion_milli
armor_flat
armor_reduction
frozen_guarded_until
guard_source_event_id
guarded
guard_reduction
final_damage
```

FINISHER는 `hit_chance_milli=1000`, 두 roll은 canonical key로 계산하되 결과에 쓰지 않고, bleed chance `0`, proc `false`, final damage `0`이다. OVERKILL_SKIP은 frozen normal formula/roll을 그대로 기록하되 final damage `0`, proc `false`다.

### 9.2 chain

```text
MISS:
  action.melee_attack
    -> combat.attack_missed

normal HIT:
  action.melee_attack
    -> combat.physical_damage
       -> entity.downed                 # HP가 0이 된 경우만
       -> status.applied|status.refreshed  # non-DEAD target, BLEED proc 성공 시

protagonist lethal melee:
  action.melee_attack
    -> combat.physical_damage
       -> entity.downed
          -> status.expired(reason=OWNER_DIED), existing row only
          -> entity.died(reason=PARTY_DEFEAT)

same-batch overkill:
  action.melee_attack(outcome=OVERKILL_SKIP) only

fresh finisher / DOWNED additional damage:
  action.melee_attack 또는 원래 damage cause
    -> combat.downed_damage
       -> status.expired(reason=OWNER_DIED), if present
       -> entity.died

BLEED cadence:
  status.tick
    -> combat.physical_damage           # owner가 ACTIVE
       -> entity.downed, if HP 0
  또는
  status.tick
    -> combat.downed_damage             # owner가 이미 DOWNED
       -> status.expired(reason=OWNER_DIED)
       -> entity.died

recovery:
  entity.downed
    -> entity.recovered

ACTIVE typed hazard:
  environment source
    -> combat.fire_damage | combat.electric_damage | combat.{registered_type}_damage
       -> entity.downed, if HP 0
          -> protagonist이면 같은 operation에서 status cleanup -> entity.died

DOWNED typed hazard:
  environment source
    -> combat.downed_damage(reason=HAZARD, original damage_type)
       -> status.expired(reason=OWNER_DIED), if present
       -> entity.died
```

`combat.attack_missed`는 magnitude `0`, cause=action이다. `combat.physical_damage`는 실제 감소 HP, cause=action 또는 status.tick이다. `combat.downed_damage`는 HP가 이미 0이므로 magnitude는 incoming 양수 pressure, data의 `applied_health_damage=0`이다.

status/lifecycle event의 공통 envelope도 고정한다.

- `status.applied`, `status.refreshed`, `status.expired`: actor `-1`, target=owner, owner position, magnitude `0`
- `status.tick`: actor `-1`, target=owner, owner position, magnitude=`tick_damage`
- `entity.downed`, `entity.died`: actor `-1`, target=entity, entity position, magnitude `0`
- `entity.recovered`: actor `-1`, target=entity, entity position, magnitude=`recovered_health`

### 9.3 공통 data

- `combat.attack_missed`: `{schema_version, combat_ruleset_id, outcome:"MISS"}`
- `combat.{type}_damage`: `{schema_version, combat_ruleset_id, damage_type, requested_damage, applied_health_damage}`. Phase 5 core type whitelist는 `physical`, `fire`, `electric`이며 다른 hazard는 registry에 type과 source-event whitelist를 함께 등록한 경우만 허용한다.
- `combat.downed_damage`: `{schema_version, combat_ruleset_id, damage_type, requested_damage, applied_health_damage:0, reason:"FINISHER"|"BLEEDOUT"|"HAZARD"}`
- `entity.downed`: `{schema_version, life_ruleset_id, previous_life_state:"ACTIVE", downed_resolve_at, terminal_immediate}`. protagonist는 `downed_resolve_at:"-1"`, `terminal_immediate:true`; 그 외는 future time과 false다.
- `entity.recovered`: `{schema_version, life_ruleset_id, recovered_health, recovery_lock_until}`
- `entity.died`: `{schema_version, life_ruleset_id, previous_life_state:"DOWNED", reason:"FINISHER"|"BLEEDOUT"|"HAZARD"|"PARTY_DEFEAT", damage_type}`
- status event data는 10절의 exact schema를 쓴다.

data 안의 int64 ID/time은 canonical decimal string이다. 작은 수치·milli·HP는 JSON safe integer다. exact key validator는 누락·추가 key를 모두 거부한다.

### 9.4 cause와 instigator

- action은 coordinator가 제공한 기존 decision/cause를 유지한다. cause가 없으면 `-1`, instigator는 attacker다.
- miss/damage는 action을 직접 cause로 삼고 attacker instigator를 상속한다.
- downed는 damage를 cause로 삼는다.
- status apply/refresh는 해당 physical damage를 cause로 삼는다.
- status tick은 row의 `source_event_id`를 cause로 삼아 마지막 적용 attacker를 상속한다.
- `combat.downed_damage`는 incoming action/status/environment source event를 cause로 삼는다.
- owner-death cleanup의 `status.expired`와 `entity.died`는 둘 다 `combat.downed_damage`를 직접 cause로 삼는다. status expiry를 death의 cause로 끼워 넣지 않는다.
- protagonist immediate cleanup의 `status.expired`와 `entity.died`는 둘 다 같은 `entity.downed`를 직접 cause로 삼는다.
- recovery는 원래 `entity.downed`를 cause로 삼는다.
- actor의 ignite/discharge에서 시작한 `environment.ignited`, `environment.fire_spread`, `environment.electric_arc`는 원래 actor instigator를 typed/downed damage와 death까지 상속한다. system/bootstrap root만 instigator `-1`이다.

source whitelist는 mode와 무관하게 검증한다. `physical`은 `action.melee_attack` 또는 `status.tick(BLEEDING)`, `fire`는 `environment.ignited|environment.fire_spread`, `electric`은 `environment.electric_arc`만 직접 source가 될 수 있다. `combat.downed_damage`의 FINISHER/BLEEDOUT/HAZARD reason과 source type/damage type 조합도 exact whitelist로 검증한다.

physical damage cause validation을 Phase 3 분기 안에 두지 않는다. encounter mode와 무관하게 모든 `combat.physical_damage`, `combat.downed_damage`, status, down/recover/death chain을 WorldState semantic validator가 검증해야 한다. Party-only tamper도 반드시 거부한다.

## 10. BLEEDING v1

`sim/combat_status_row.gd`와 `sim/status_registry.gd`를 만든다. registry에는 아래 하나만 등록한다.

```text
STATUS_RULESET_ID = bounded-status-lifecycle-v1
status_id = BLEEDING
tick_interval = 100
tick_damage = 3
tick_count_after_apply_or_refresh = 3
stacking = NONE
```

### 10.1 row exact schema

```text
schema_version: 1
status_id: "BLEEDING"
applied_at: int64
refreshed_at: int64
next_tick_at: int64
expires_at: int64
source_event_id: int64
```

### 10.2 apply와 refresh

`strict_next_actor_boundary(t) = (floor(t / 100) + 1) * 100`이다.

신규 apply:

```text
applied_at = now
refreshed_at = now
next_tick_at = strict_next_actor_boundary(now)
expires_at = next_tick_at + 200
source_event_id = emitted status.applied event ID
```

`status.applied.cause_id`는 proc을 만든 latest typed damage event다. event emit 성공 뒤 row의 `source_event_id`를 그 applied event ID로 설정한다.

재적용은 stack을 올리지 않는다.

```text
applied_at = old.applied_at
refreshed_at = now
next_tick_at = old.next_tick_at       # 절대 늦추지 않음
expires_at = max(old.expires_at, strict_next_actor_boundary(now) + 200)
source_event_id = emitted status.refreshed event ID
```

`status.refreshed.cause_id`는 재적용을 만든 latest typed damage event다. refresh emit 성공 뒤 source를 refresh event ID로 교체한다. 이후 tick은 이 latest apply/refresh event를 cause로 삼고, tick 자체는 row source를 바꾸지 않는다.

event data exact keys:

```text
schema_version, status_ruleset_id, status_id,
next_tick_at, expires_at, tick_damage
```

### 10.3 tick와 expire

actor status subphase에서 entity ID, status ID 순으로 처리한다.

1. `next_tick_at <= now && next_tick_at <= expires_at`이면 `status.tick`을 emit한다.
2. `next_tick_at += 100`으로 올린 뒤 DamageSystem에 `3 physical`을 전달한다.
3. owner가 DEAD가 아니고 `now >= expires_at`이며 더 처리할 due tick이 없으면 `status.expired(reason=NATURAL)`을 emit하고 row를 제거한다.

정상 schedule은 한 cadence에 한 tick이다. restore validator는 overdue status가 settled decision boundary에 존재하지 못하게 한다. catch-up while loop로 한 timestamp에 여러 tick을 몰아 넣지 않는다.

`status.tick` data: `{schema_version, status_ruleset_id, status_id, tick_damage, scheduled_tick_at}`.

`status.expired` data: `{schema_version, status_ruleset_id, status_id, reason:"NATURAL"|"OWNER_DIED"}`.

NATURAL expire의 `cause_id`는 **같은 subphase에서 방금 emit한 마지막 `status.tick`**이다. OWNER_DIED expire는 9절의 death driver(`combat.downed_damage` 또는 protagonist의 `entity.downed`)를 cause로 삼는다.

death 시 남아 있는 status는 status ID 순서로 `status.expired(reason=OWNER_DIED)`를 먼저 emit하고 row를 지운 뒤 `entity.died`를 emit한다. 어느 emit이든 실패하면 전체 transaction을 복구한다.

worked example, apply 시각 `T0=0`:

```text
T0:   apply, next=100, expires=300
100:  tick 3, next=200
200:  tick 3, next=300
300:  tick 3, next=400; 직후 NATURAL expire/remove
400:  tick 없음
```

## 11. DOWNED recovery와 death

ACTIVE가 damage로 HP 0이 되면 즉시 DOWNED다.

```text
life_state = DOWNED
health = 0
downed_at = now
downed_source_event_id = entity.downed event ID
guarded_until/guard_source_event_id = 0/-1
recovery_lock_until/recovery_source_event_id = 0/-1
```

non-protagonist는 `downed_resolve_at=strict_next_actor_boundary(now)+100`이다.

protagonist lethal은 예외적으로 deadline을 설정하지 않는다. `entity.downed.data.terminal_immediate=true`, `downed_resolve_at=-1`로 emit하면서 party phase를 동기적으로 `PARTY_DEFEATED`로 바꾸고, 즉시 같은 outer operation에서 기존 status를 OWNER_DIED로 정리한 뒤 `entity.died(reason=PARTY_DEFEAT)`를 emit한다. 최종 canonical row는 DEAD sentinel이다. 이 terminal 변경은 이미 frozen된 같은 batch intent를 취소하지 않지만 이후 coordinator 제안/행동을 막는다. melee BLEED proc이 수치상 성공했더라도 이미 DEAD인 protagonist에게 apply/refresh event나 row를 만들지 않는다.

DOWNED에 양수 damage가 다시 들어오면 HP mutation 없이 `combat.downed_damage`를 emit하고 DEAD로 전이한다. fresh-turn FINISHER는 명중 판정 없이 이 경로를 사용한다.

actor lifecycle subphase에 `now >= downed_resolve_at`이고 여전히 DOWNED이면:

- BLEEDING이 없음: recovery
- BLEEDING이 있음: status subphase가 먼저 due tick을 처리하므로 정상 상태에서는 이미 bleedout death가 된다. 위조 snapshot으로 tick이 deadline 뒤라면 semantic validation에서 거부한다.

recovery:

```text
recovered_health = max(1, ceil(max_health * 100 / 1000))
                 = max(1, (max_health + 9) / 10)
life_state = ACTIVE
health = recovered_health
recovery_lock_until = now + 100
recovery_source_event_id = entity.recovered event ID
downed_at/downed_resolve_at/downed_source_event_id = -1
```

recovery는 최대 두 번의 미래 actor boundary 안에 끝난다. BLEEDING 또는 추가 damage는 그보다 먼저 death를 만든다. 따라서 마지막 DOWNED enemy 때문에 전투가 무한 교착되지 않는다.

### 11.1 party 결과

- protagonist가 DOWNED가 되는 즉시 `safe_phase = PARTY_DEFEATED`이고 같은 operation에서 DEAD가 된다.
- companion DOWNED는 combat을 계속한다.
- enemy DOWNED는 unresolved이므로 victory가 아니다.
- 모든 enemy가 DEAD일 때만 `party.victory`를 emit한다.
- 같은 outer operation에서 protagonist lethal과 final enemy death가 함께 발생하면 defeat가 무조건 우선한다. `PARTY_DEFEATED`를 유지하고 `party.victory`/regroup event를 하나도 만들지 않는다.
- 최종 death가 frozen batch, environment, BLEED cadence 어디서 나왔든 해당 atomic 처리 안에서 liveness를 재검사한다.
- `entity.died -> party.victory -> party.regroup_started -> party.member_regrouped* -> party.regroup_completed` 순서와 elapsed time `0`을 유지한다.
- ACTIVE와 DOWNED non-DEAD companion을 anchor로 운반해 GROUPED로 만든다. DEAD/DEFEATED member는 이동시키지 않는다.

## 12. actor cadence subphase

세 번째 schedule을 만들지 않는다. 기존 `system.actor_tick` 하나를 다음 explicit subphase로 나눈다.

```text
0. tick 시작 시 can_act entity ID set을 freeze
1. StatusSystem: BLEED tick/expire, entity ID -> status ID 순
2. Lifecycle: due DOWNED recovery/death, entity ID 순
3. party/Phase3 liveness와 terminal outcome reconcile
4. terminal이 아니면 기존 coordinator process_tick
   - subphase 0 set에 있었고 현재도 can_act인 actor만 사용
5. coordinator 결과 뒤 liveness/victory/regroup reconcile
```

같은 timestamp에서 environment `100`이 먼저, actor `200`이 뒤다. subphase 2에서 recovered된 actor는 subphase 0 set에 없으므로 같은 cadence에 행동하지 않는다. `recovery_lock_until=now+100` 때문에 player command도 그 시각에는 거부되고 다음 actor boundary부터 가능하다.

status/lifecycle subphase 자체와 coordinator를 포함한 actor occurrence 전체가 하나의 outer transaction이다. 중간 성공을 commit하지 않는다.

## 13. event headroom과 rollback

DamageSystem은 HP를 바꾸기 전에 해당 호출의 최악 event 수와 모든 입력을 preflight한다. `emit_event()` 뒤에 HP부터 바꾸는 순서는 금지한다.

최악 event 수:

- normal strike intent: action + miss 또는 damage + downed + status = 최대 `5`
- finisher: action + downed damage + status expire + death = 최대 `4 + status_count`
- status cadence 한 row: tick + damage + downed/death + expire = 최대 `4`
- recovery: `1`
- victory tail: `3 + party_member_count`

batch caller는 mutation 전 아래 conservative bound를 한 번 예약한다.

```text
coordinator_pre_event_count
+ 5 * frozen_intent_count
+ 4 * due_status_row_count
+ due_downed_count
+ possible_victory_tail
```

over-reservation은 허용하지만 under-reservation은 금지한다. overflow-safe saturating arithmetic을 쓴다.

이 per-batch 식은 outer aggregate preflight의 일부일 뿐이다. generic command, Party turn, Phase 3 tick, deployment/contact/ambush, environment fire/electric multi-target 각각에 대해 MOVE/HOLD/action/override/decision, 모든 frozen melee, 모든 due status/downed, 모든 environment target, defeat/victory/regroup tail을 합한 최악 수를 **첫 mutation 전에 한 번** 검사한다. DamageSystem도 자기 local chain을 HP mutation 전에 재검사한다.

모든 accepted outer operation은 mode와 결과에 관계없이 시작 직전 settled canonical snapshot을 unconditional rollback owner로 잡는다. generic Simulator step, Party turn, Phase 3를 포함한 actor occurrence, deployment/contact/ambush, environment multi-target 모두 같은 원칙이다. inner coordinator/kernel/DamageSystem/StatusSystem은 별도 snapshot이나 `begin_step`을 만들 수 없다. 실패는 항상 outer snapshot으로 돌아간다.

다음 fault seam을 test-only hook으로 제공한다. hook은 snapshot/save에 들어가지 않는다.

- `action.melee_attack` emit 직후
- `combat.attack_missed` emit 직후
- damage event emit 직후
- status apply/refresh/tick/expire emit 직후
- entity.downed emit 직후
- entity.recovered emit 직후
- entity.died emit 직후
- actor status/lifecycle subphase 직후, coordinator 직전

어느 `emit_event()`가 null을 반환하거나 seam이 실패해도 outer operation은 거부되고 다음이 pre-operation과 정확히 같아야 한다.

- canonical world snapshot 전체
- RNG state
- `_next_event_id`, `_next_entity_id`, `next_schedule_id`
- events와 event cause/instigator
- schedule rows, due_time, ordering
- HP, CombatantState, status rows, party/agent state
- step_index, world_time
- processed step 전달 상태와 session `visual_effects=[]`

## 14. snapshot v6

다음 ID를 정확히 쓴다.

```text
SNAPSHOT_VERSION = 6
RULESET_VERSION = phase5-combat-status-lifecycle-v1
COMBAT_RULESET_ID = deterministic-melee-resolution-v1
COMBAT_PROFILE_RULESET_ID = combat-profile-registry-v1
COMBATANT_SCHEMA_ID = combatant-state-v1
AGENT_STATE_SCHEMA_ID = agent-state-v2
LIFE_RULESET_ID = active-downed-dead-v1
STATUS_RULESET_ID = bounded-status-lifecycle-v1
PARTY_MEMBER_SCHEMA_ID = party-member-v2
```

top-level snapshot에 위 ID와 `combatant_states`를 exact key로 추가한다. combatant rows는 entity ID 오름차순이다.

PartyMemberState wire에서 `status_ids`를 제거한다. PartyMemberState를 status authority로 다시 쓰지 않는다. session DTO의 `status_ids`는 CombatantState.status_rows를 정렬해 파생한 presentation field다.

모든 ID/time/seed/RNG state는 `Int64Codec` canonical decimal string을 쓴다. `"0"`, `"-1"` 외 leading zero, float, exponent, unsafe JSON integer 대체를 거부한다.

wire validation은 exact keys/type/range/enum/sort/unique를 확인하고 semantic validation은 최소 아래를 확인한다.

- entity set과 combatant row set이 정확히 같음
- profile ID가 registry에 존재하고 entity kind mapping과 일치
- ACTIVE/DOWNED/DEAD와 HP invariant
- life별 guard/down/recovery/status sentinel, source event type, world-time 범위 일치
- AgentState v2에는 `guarded_until` key가 없고 CombatantState만 guard authority
- status registry 존재, row sort/unique, tick/expiry cadence, source event type/cause 일치
- DEAD status row 없음
- party presence/life state와 phase invariant
- unresolved enemy/victory invariant
- mode-independent combat/status/lifecycle event cause chain
- action event의 processed step/context/commitment/hash/두 roll을 재계산할 수 있고 모든 child event step이 cause chain과 같음
- settled boundary에 overdue status/lifecycle 없음
- 두 기존 schedule만 존재하고 priority/cadence 유지

snapshot v5는 migration하지 않고 `unsupported_snapshot_version`으로 명시적 거부한다. 누락된 combatant row를 load 중 자동 생성하지 않는다.

PartyTurnPlan/combat_assessment, FrozenAttackIntent, detached AttackResolution, UI `visual_effects`, hover/selection/camera, fail point는 snapshot에 넣지 않는다.

## 15. session save/version

`PartyPlaytestSession`의 session/save schema를 `3`으로 올리고 기본 경로를 다음으로 바꾼다.

```text
user://living_world_party_encounter_v3.json
```

v2 session/save와 내부 snapshot v5는 명시적으로 거부한다. 실패 load는 현재 session을 한 비트도 바꾸지 않는다.

journal restore는 authoritative event만 복원하고 `visual_effects` queue를 비운다. load 뒤 MISS/HIT/DAMAGE/DOWNED/BLEED/RECOVERED/DEATH effect를 과거 event로부터 재생하지 않는다.

## 16. facade DTO

party card, enemy target, inspector DTO에 다음을 공개한다.

```text
life_state
can_act
occupies_tile
explicit_targetable
autonomous_targetable
combat_profile_id
accuracy_milli
evasion_milli
armor_flat
guarded_until
guard_source_event_id
guard_active
normal_damage
guarded_damage
status_ids                 # derived only
statuses: [
  {status_id, label, tick_damage, next_tick_at, expires_at,
   next_tick_in, expires_in}
]
```

DOWNED enemy도 `enemy_targets()`에 남고 `explicit_targetable=true`, `target_mode=FINISHER`, `autonomous_targetable=false`다. DEAD enemy만 목록에서 빠진다.

preview actor row에는 `accuracy_milli`, target evasion/armor/guard, 예상 normal damage, target life, STRIKE/FINISHER, commitment를 표시한다. UI 설명은 “명중 = 정확도 대 회피”, “방어 = 피해에서 armor를 먼저 뺌”, “가드 = armor 적용 뒤 남은 피해 25% 감소” 순서를 명시한다. raw roll/outcome/effect는 없다.

public 반환 key는 기존 이름 `visual_effects` 하나만 유지한다.

- accepted commit `visual_effects`: 이번 commit에서 새로 생긴 detached event deep copy만 projection
- preview `visual_effects`: 항상 `[]`
- reject/stale/tamper `visual_effects`: 항상 `[]`
- load `visual_effects`: 항상 `[]`

## 17. combat log, narrative, effect

`combat_log`가 `combat.*` prefix를 DAMAGE로 처리하지 않게 exact mapping한다.

| exact event/data outcome | category | `visual_effects.kind` 순서 |
|---|---|---|
| `action.melee_attack`, `HIT` | ATTACK | `SLASH` |
| `action.melee_attack`, `MISS` | ATTACK | `SLASH` |
| `combat.attack_missed` | MISS | `MISS` |
| `action.melee_attack`, `OVERKILL_SKIP` | ATTACK_SKIPPED | `OVERKILL_SKIP` |
| `action.melee_attack`, `FINISHER` | ATTACK | `SLASH` |
| `combat.physical_damage`, `combat.fire_damage`, `combat.electric_damage`, `combat.downed_damage` | DAMAGE | `HIT_FLASH`, 다음 `FLOATING_AMOUNT` |
| `entity.downed` | LIFECYCLE | `DOWNED` |
| `status.applied`, `status.refreshed`, `status.tick` | STATUS | `BLEED` |
| `status.expired` | STATUS | 없음 |
| `entity.recovered` | LIFECYCLE | `RECOVERED` |
| `entity.died` | LIFECYCLE | `DEATH` |

generic `event_type.begins_with("combat.") -> DAMAGE` fallback을 삭제한다. tests도 prefix가 아니라 exact type/category를 검증한다.

한국어 narrative 최소 문구:

- MISS: `{공격자}의 공격이 {대상}을 빗나갔다.`
- HIT: `{공격자}가 {대상}을 공격했다.`
- DAMAGE: `{대상}이(가) {N} 피해를 입었다.`
- DOWNED: `{대상}이(가) 쓰러졌다.`
- BLEED apply: `{대상}에게 출혈이 시작됐다.`
- BLEED refresh: `{대상}의 출혈이 이어졌다.`
- BLEED tick: `{대상}이(가) 출혈로 {N} 피해를 입었다.`
- BLEED expire: `{대상}의 출혈이 멎었다.`
- RECOVERED: `{대상}이(가) 간신히 다시 일어섰다.`
- DEATH: `{대상}이(가) 숨졌다.`
- OVERKILL_SKIP: `{대상}은 이미 쓰러져 있어 같은 순간의 공격이 이어지지 않았다.`
- FINISHER: `{공격자}가 쓰러진 {대상}을 마무리했다.`

grid effect는 detached event projection만 소비한다. event 순서와 같은 strictly increasing `order`를 쓰며, HIT/FINISHER는 기존 `SLASH -> HIT_FLASH -> FLOATING_AMOUNT` 순서를 유지한다. MISS는 `SLASH -> MISS`, OVERKILL_SKIP은 단독 skip, death chain은 damage rows 뒤 DOWNED/DEATH 순이다. load에서는 `_played_effect_ids`를 authoritative history로 채우지 않고도 `visual_effects=[]`를 보장한다. status text와 life badge는 portrait/inspector에서 큰 글자로 보인다.

## 18. 파일 계획

### 18.1 새 파일

- `sim/combatant_state.gd`
- `sim/combat_status_row.gd`
- `sim/combat_profile_registry.gd`
- `sim/status_registry.gd`
- `sim/frozen_attack_intent.gd`
- `sim/systems/status_lifecycle_system.gd`
- `tests/test_phase5_combat_status_lifecycle.gd`
- `tests/run_phase5_tests.gd`

### 18.2 변경 파일

- `sim/world_state.gd`: IDs, combatant rows, predicates, strict v6 wire/semantic validation, universal event cause validation
- `sim/simulator.gd`: processed step 명시 전달, shared actor subphase, unconditional outer rollback/headroom, direct fixed damage 제거
- `sim/party_turn_plan.gd`: actor row nullable exact `combat_assessment` wire와 canonical equality
- `sim/agent_state.gd`: `guarded_until` 제거, agent-state-v2 wire
- `sim/systems/melee_combat_system.gd`: pure assess/keyed resolve/frozen batch atomic kernel
- `sim/systems/damage_system.gd`: preflight, HP/lifecycle, DOWNED trauma, rollback-safe return
- `sim/systems/environment_system.gd`, `sim/systems/exposure_system.gd`: DOWNED exposure와 DEAD 제외
- `sim/systems/movement_system.gd`, `sim/weighted_pathfinder.gd`, `sim/systems/npc_coordinator.gd`: 공통 life predicate migration
- `sim/systems/actor_coordinator.gd`: decision 유지, fixed 22/18 제거, frozen batch adapter
- `sim/systems/party_encounter_coordinator.gd`: proposal/AI 유지, fixed 14 제거, explicit finisher와 victory 의미
- `sim/party_member_state.gd`: `status_ids` authority 제거, v2 wire
- `sim/party_encounter_state.gd`: DOWNED/DEAD phase invariant
- `sim/sim_entity.gd`: production `is_alive()` call site 제거
- `playtest/party_playtest_session.gd`: save v3, DTO, preview, exact log/narrative/effect
- `playtest/party_exploration_route.gd`, `playtest/playtest_session.gd`: Party route/Phase 3 life predicate migration
- `playtest/party_grid_view.gd`: life/status/effect rendering
- `playtest/party_encounter_sandbox.gd`: 큰 글자 badge/상세/선택 불가 사유
- Phase 3/4, snapshot, session, UI test files: 새 authoritative chain에 맞춘 정확 assertion
- `README.md`, `docs/NEXT_DEVELOPMENT_GUIDE.ko.md`: Phase 5 완료 상태와 다음 범위 갱신

이 구현 작업에서 docs/README 갱신까지 포함한다. 단, 구현 전 이 prompt의 계약을 임의로 다시 쓰지 않는다.

## 19. acceptance test matrix

### 19.1 profile·수식·key

- 모든 kind mapping과 exact profile 값
- power `24/16/24/20`과 모든 core armor `2`가 non-guard normal HIT `22/14/22/18`을 만듦
- guard exact `22->17`, `14->11`, `18->14`
- armor가 damage를 1 미만으로 낮추지 않음
- 5%/95% hit clamp, roll 동률 miss
- settled base step 2 -> processed step 3, commitment hash `31da9bf...f418`, HIT `746`, BLEED `405`
- 동일 frozen input은 snapshot round-trip 전후 같은 roll/result
- 전투 전후 global RNG state 동일
- 서로 다른 ordinal/batch/attacker/target/lane은 key와 digest가 다름. `%1000` roll collision은 허용
- 같은 outer operation의 direct/cadence/ambush combat event가 모두 전달받은 동일 processed step을 사용

### 19.2 preview·tamper

- preview 100회 완전 무변경
- MELEE만 exact combat_assessment, MOVE/HOLD는 null, facade는 deep copy
- preview에는 chance/formula/commitment, raw outcome/roll/visual effect 없음
- combat assessment ordinal gap/duplicate/out-of-order를 wire reject
- base revision/processed step/time, context, ordinal, profile, position, life, guard/source, chance/damage, commitment 중 하나를 위조하면 exact no-op
- stale plan도 event ID/schedule/RNG 포함 exact no-op

### 19.3 batch

- Phase 3 decision events가 action보다 먼저 존재
- action intents 전부가 result mutation보다 먼저 존재
- mixed Party rows에서 canonical MOVE/HOLD commit, MELEE action collect, 해당 override event, 마지막 ordinal results 순서
- Phase 3 batch-start ACTIVE lead/threat intent 모두 보존
- hero+companion same ACTIVE target: 두 action, 첫 DOWNED, 둘째 OVERKILL_SKIP, damage/down/status는 한 번뿐
- 첫 intent MISS면 후속 intent가 정상 resolve
- batch-start DOWNED explicit target: 첫 FINISHER, 후속 same-target OVERKILL_SKIP
- autonomous companion/enemy/Phase3 actor가 DOWNED target을 선택하지 않음

### 19.4 life/status

- non-protagonist ACTIVE HP 0 -> 실제 HP0 DOWNED, 즉시 death 아님
- protagonist lethal만 damage -> downed -> death가 같은 outer operation이며 deadline/status proc 없음
- DOWNED가 tile을 막고 environment에 노출됨
- DEAD만 비점유·비노출·비표적
- life별 guard/down/recovery source sentinel과 AgentState guard 부재
- BLEED apply exact next/expiry, 3 damage cadence
- T0 apply, 100/200/300 tick, 300 직후 NATURAL expire, 400 no tick
- refresh가 stack을 만들지 않고 next tick을 늦추지 않으며 expiry만 연장
- MISS/OVERKILL/FINISHER는 BLEED 적용 없음
- BLEED tick이 ACTIVE를 DOWNED로 만들 수 있음
- BLEED tick/additional damage가 DOWNED를 DEAD로 만듦
- 무출혈 DOWNED가 deadline에 10% HP로 recovery
- recovered actor가 같은 actor cadence에 행동하지 않고 다음 cadence부터 가능
- owner death 시 status.expired 후 entity.died, status row 없음

### 19.5 party outcome

- hero DOWNED 즉시 PARTY_DEFEATED 및 같은 operation DEAD
- hero와 final enemy가 같은 operation에서 죽으면 defeat 우선, victory/regroup event 없음
- companion DOWNED combat 지속
- last enemy DOWNED 상태에서 victory/regroup 없음
- downed enemy explicit finisher와 bleedout 두 경로 모두 최종 DEAD 가능
- final enemy가 finisher, BLEED, hazard 각각으로 DEAD가 될 때 동일 processed step에서 `entity.died < party.victory < regroup*`, elapsed 0
- 위 세 victory path의 death/victory/regroup 각 fault seam이 outer snapshot 전체 rollback
- DOWNED companion은 자동 운반/grouped, DEAD companion은 DEFEATED/제자리

### 19.6 event/cause/log

- MISS, HIT, FINISHER, OVERKILL exact chain/data keys/order
- action -> damage/miss -> down/status -> death/recover cause
- instigator가 party, Phase3, actor ignite/discharge environment에서 정확히 상속되고 bootstrap/system만 -1
- ACTIVE fire/electric typed damage와 DOWNED HAZARD downed-damage source whitelist
- Party mode의 forged physical/status/lifecycle cause도 restore 거부
- combat.attack_missed가 DAMAGE category가 아님
- status.*가 DAMAGE category가 아님
- 동료 공격과 BLEED tick이 한국어 log에 보임
- outcome별 exact category/visual effect와 기존 SLASH/HIT_FLASH/FLOATING_AMOUNT order, detached copy
- preview/reject/load `visual_effects` empty, 반환 key 이름 유지

### 19.7 snapshot/session

- snapshot v6 deterministic round-trip byte equality
- v5 명시적 거부
- combatant exact keys/order/int64 codec/semantic tamper 각각 거부
- HP/life/sentinel mismatch, unknown profile/status, overdue tick, invalid guard/recovery/status source event 거부
- PartyMemberState에 status_ids를 넣은 old row 거부
- AgentState에 old guarded_until을 넣은 row 거부
- session v3 save/load, v2 거부, 실패 load no-op
- production `is_alive()`/`health>0` rg allowlist audit가 새 liveness branch를 실패시킴

### 19.8 rollback fault injection

각 seam에서 별도 테스트한다.

- action emit
- miss emit
- damage emit
- status apply/refresh/tick/expire emit
- downed emit
- recovered emit
- death emit
- actor cadence status/lifecycle 뒤

generic/Party/Phase3/deployment/contact/environment multi-target 각각에서 fault를 주입한다. 각 실패에서 canonical snapshot, RNG, next IDs, events, HP/state/status, schedules, base/processed step/time과 `visual_effects=[]`를 전부 비교한다.

## 20. 필수 test runner와 회귀 실행

새 runner:

```bash
godot --headless --path . --script res://tests/run_phase5_tests.gd
```

반드시 함께 실행한다.

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_phase3_tests.gd
godot --headless --path . --script res://tests/run_phase4_tests.gd
godot --headless --path . --script res://tests/party_ui_layout_smoke.gd
```

추가로 기존 session/snapshot/UI test가 full runner에 실제 등록되었는지 확인한다. runner가 테스트 파일을 누락한 false green을 허용하지 않는다.

Phase 3/4 테스트는 핵심 동시성·zero-time regroup·cause/instigator·rollback assertion을 유지한다. 확률 때문에 불안정한 테스트는 확률을 우회하지 말고 고정 seed/key reference로 outcome을 고정한다.

production liveness audit도 runner에서 실행한다.

```bash
rg -n '\.is_alive\(\)|health\s*(==|!=|<=|>=|<|>)\s*0' sim playtest
```

허용 목록은 DamageSystem의 HP 산술과 WorldState의 HP/life semantic validation뿐이다. movement/pathfinder/NPC/Party route/Phase 3 session/coordinator 결과가 하나라도 나오면 실패다. facade가 health 값을 표시하는 read는 비교식이 아니므로 허용 목록이 아니다.

## 21. 구현 순서

### A. profile/hash/predicate/snapshot checkpoint

- IDs, exact profile/status registry, CombatantState/StatusRow/AgentState v2 wire
- processed step 전달과 commitment/lane hash reference
- PartyTurnPlan combat_assessment exact wire/rebuild equality
- 공통 life predicate 및 production liveness call-site migration
- snapshot v6 strict codec/semantic/source/sentinel validation

A가 끝나면 full core와 snapshot/Phase3/Phase4 관련 suite를 green으로 만들고 checkpoint 결과를 보고한다. 실패를 안고 B로 가지 않는다.

### B. kernel/adapters/lifecycle/rollback checkpoint

- pure assess/shadow projection/FrozenAttackIntent/detached resolution
- all-action-first Party/Phase3 adapters와 ambush context
- DamageSystem typed damage, immediate hero death, DOWNED finisher
- BLEED apply/refresh/tick/expire, recovery, actor subphase
- defeat priority, final-death victory/zero-time regroup
- 모든 accepted outer operation aggregate headroom/unconditional rollback/fault seams

B가 끝나면 Phase 5 core, full core, Phase3, Phase4, session-domain suite를 모두 green으로 만들고 checkpoint 결과를 보고한다. 실패를 안고 C로 가지 않는다.

### C. facade/log/UI/docs checkpoint

- session v3 DTO, exact category/narrative, detached `visual_effects`
- evasion/armor/guard/status/life UI와 기존 route/touch/큰 글자 회귀
- UI smoke와 effect ordering/load-no-replay
- README와 NEXT guide 갱신
- 모든 runner 최종 재실행

같은 구현 agent가 A/B/C를 이어서 수행해도 되지만 각 checkpoint마다 변경 파일, test command, 결과를 별도로 보고한다.

## 22. 완료 보고 형식

구현 에이전트는 마지막에 다음만 간결하게 보고한다.

- 변경 파일 목록
- profile/수식/key/status/lifecycle의 실제 구현 값
- snapshot/session version과 save path
- 실행한 각 test command와 pass/fail
- 남은 비목표 또는 실제 blocker
- commit hash와 push 여부

“대체로 동작”은 완료가 아니다. 위 acceptance matrix 중 하나라도 검증하지 못했으면 정확히 미검증으로 표시한다.
