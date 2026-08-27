# Phase 2–3 구현 프롬프트: TerrainRegistry·MOVE·ExposureSample·종족 affinity·Playtest Sandbox

## 0. 역할과 목표

당신은 `/mnt/d/STARTU/living-world-sim`의 실제 구현 담당자다. 이 문서는 토론 초안이 아니라 구현 계약이다.

이번 수직 슬라이스의 목표는 다음 네 가지를 한 번에 닫는 것이다.

```text
TerrainRegistry
→ 플레이어와 미래 NPC가 공유할 MOVE command
→ 세계를 바꾸지 않는 ExposureSample·종족별 위험 평가
→ 세로 화면에서 직접 조작하는 Playtest Sandbox
```

자동 테스트만 통과하고 끝내지 않는다. 사용자가 `godot --path ...`로 실행해 이동하고, 불·물 노출을 만들고, 두 종족의 평가 차이와 세계시간 진행을 눈으로 확인할 수 있어야 한다.

기존 63개 회귀를 삭제하거나 의미를 약화해 통과시키지 않는다. 스냅숏·시간·사건·관계 계약을 새 ruleset에 맞게 명시적으로 갱신한다.

## 1. 현재 고정 불변식

다음 Phase 1 계약은 그대로 유지한다.

- `step_index`는 정착한 유효 플레이어 결정 수다.
- `world_time`은 실제 경과한 signed 64-bit 정수 시간이다.
- 같은 시각까지 포함한 사건의 안정 순서는 `event_id`다.
- 유효 행동은 시작 시 즉시 commit된다.
- `(start_time, end_time]`의 예약을 `(due_time, priority, schedule_id)` 순으로 처리한다.
- 종료 시각과 같은 환경 틱은 `actor.ready` marker보다 먼저 처리한다.
- 잘못된 명령은 step/time/RNG/event ID/schedule ID/환경을 전혀 바꾸지 않는다.
- `preview()`와 실제 `step()`은 같은 순수 계획 경로를 사용한다.
- 실제 사건은 timeline의 정확히 한 marker에 순서대로 귀속된다.
- 반환 DTO를 외부에서 변형해도 authoritative world가 변하지 않는다.
- 정착 경계의 예약 큐는 다음 100 배수의 `system.environment_tick` 정확히 하나다.
- core가 받아들인 authoritative state는 반드시 snapshot·checked restore·exact round-trip 가능하다.

MOVE 때문에 이 의미를 바꾸지 않는다. MOVE도 위치를 **행동 시작 시각에** 바꾼다. 행동 구간 안의 환경 틱은 새 위치를 본다.

`actor.ready`는 “행동 시간창이 끝나 다음 결정 경계에 도착했다”는 marker다. 행동 구간의 환경 틱에서 actor가 사망할 수 있으므로 생존 보증을 뜻하지 않는다. 사망했다면 다음 명령은 `actor_dead`로 전체 무변경 거부한다.

## 2. 이번 범위와 비범위

### 구현 범위

- immutable built-in `TerrainRegistry`
- terrain bootstrap API와 producer/restore parity
- 네 방향 한 칸 MOVE
- 생존 개체 1칸 1명 점유 규칙
- 목적지 지형 기반 이동 시간
- 이동 사건·preview·timeline·저장·command journal
- 정착 상태의 순수 `ExposureSample`
- immutable `SpeciesHazardAffinityRegistry`
- 정수 기반 위험 평가 DTO
- 불·정적 얕은 물·동적 젖음·전도성 연결
- persistent electricity가 없다는 명시적 `electric_risk=0`
- snapshot v3와 registry ruleset 고정
- 세로형 `Playtest Sandbox`
- headless 이동·노출 데모와 회귀 테스트

### 비범위

- 길찾기, 자동 위험 회피, NPC 의사결정
- 공격, bump attack, 문, 계단, 밀기, 자리 교환
- 대각선 이동
- 수영 능력·비행·크기별 통과 규칙
- 종족 affinity에 따른 이동 속도 변경
- 연속 유체, 수위 변화, 물 흐름
- persistent 전하·감전 DOT·가상 방전 예측
- 독 상태와 poison scheduler
- 시야·인지·안개·숨은 위험
- procedural dungeon과 최종 대형 맵
- production UI, 아트, 애니메이션, 모바일 제스처 완성
- 범용 ECS, 규칙 DSL, 동적 mod registry

Playtest 맵은 시스템 검증용 작은 경기장이지 최종 월드 크기 결정이 아니다.

## 3. 전체 구조

권장 파일 경계는 다음과 같다. 이름은 동등하게 명확한 경우만 조정할 수 있다.

```text
sim/terrain_registry.gd
sim/traversal_assessment.gd
sim/destination_assessment.gd
sim/exposure_sample.gd
sim/hazard_affinity.gd
sim/exposure_evaluation.gd
sim/species_hazard_affinity_registry.gd
sim/environment_rules.gd
sim/systems/movement_system.gd
sim/systems/exposure_system.gd

playtest/playtest_session.gd
playtest/playtest_sandbox.gd
playtest/playtest_sandbox.tscn

examples/move_exposure_demo.gd
tests/test_terrain_move.gd
tests/test_exposure_affinity.gd
tests/test_playtest_session.gd
```

의존 방향은 아래로 고정한다.

```text
TerrainRegistry ──────────────┐
                             ├→ MovementSystem / Simulator MOVE
WorldState의 정착 snapshot ──┤
                             └→ ExposureSystem → detached sample

sample + detached affinity → pure evaluator → detached evaluation

PlaytestSession → Simulator의 public API만 호출
Playtest UI      → PlaytestSession만 조작
```

UI나 Exposure가 타일·개체를 직접 변경하지 않는다. 시나리오 생성 시 bootstrap을 제외한 모든 세계 진행은 `sim.step(command)`만 통과한다.

`cardinal_neighbors()`는 화재 확산과 전기 BFS가 함께 쓰는 순수 기하 이웃이다. 벽·점유 필터를 여기에 넣지 않는다. 이동 가능성은 별도 `MovementSystem.assess_move()`에서만 평가한다.

미래 NPC와 공유하는 것은 outer `Simulator.step()`가 아니라 `MovementSystem → ActionTimingTable → 검증된 commit` 경로다. 현재 `step_index`는 플레이어 결정 수이므로 NPC가 public `step()`을 재귀적으로 호출하게 만들지 않는다.

## 4. TerrainRegistry 계약

registry는 실행 중 변경할 수 없는 built-in 데이터다. public 조회는 원본 Dictionary를 노출하지 않고 깊은 복사나 immutable DTO를 반환한다.

각 정의는 최소한 다음 필드를 가진다.

```text
terrain_id: String
passable: bool
occupancy_capacity: int
move_time_cost: int
terrain_water_exposure: int
default_flammability: int
default_base_conductivity: int
presentation_key: String
```

범위:

- `terrain_id`는 비어 있지 않고 유일
- passable terrain의 `move_time_cost=1..10000`, `occupancy_capacity=1`
- impassable terrain의 `move_time_cost=0`, `occupancy_capacity=0`
- exposure/material scalar는 `0..100`
- presentation key도 비어 있지 않은 String

v1 built-in 값은 정확히 고정한다.

| terrain_id | passable | capacity | move cost | water exposure | flammability | conductivity |
|---|---:|---:|---:|---:|---:|---:|
| `floor` | true | 1 | 100 | 0 | 0 | 0 |
| `stone_floor` | true | 1 | 100 | 0 | 0 | 5 |
| `wood_floor` | true | 1 | 100 | 0 | 80 | 5 |
| `metal` | true | 1 | 100 | 0 | 0 | 25 |
| `rubble` | true | 1 | 140 | 0 | 10 | 5 |
| `shallow_water` | true | 1 | 130 | 80 | 0 | 60 |
| `wall` | false | 0 | 0 | 0 | 0 | 0 |

`terrain_water_exposure`는 정적 지형 특성이다. 다시 유체 상태인 `water_depth`를 도입하는 것이 아니다. 동적 물 적용은 계속 `wetness`를 사용하고 환경 틱마다 감소한다. 얕은 물 지형 자체는 마르지 않는다.

`SimTile.terrain`은 의미상 `terrain_id`다. 호환을 위해 필드명을 유지해도 되지만 README와 API에서는 terrain ID라고 부른다.

## 5. Terrain bootstrap과 상태 검증

다음과 동등한 checked bootstrap API를 제공한다.

```text
world.bootstrap_set_terrain(position, terrain_id) -> bool
```

성공 조건:

- 정착 상태
- `step_index=0`, `world_time=0`
- 아직 사건이 없음
- position이 bounds 안
- registry에 존재하는 terrain ID
- 해당 칸에 생존 개체가 없음

성공 시 terrain ID와 registry의 기본 flammability/base conductivity를 적용하고, 해당 타일의 fire/wetness와 source/eligibility sentinel을 초기 상태로 정리한다. 실패하면 타일과 모든 ID가 완전히 불변이다.

타일별 재료 override를 금지하지 않는다. 기존 테스트·향후 맵 생성은 bootstrap 중 `flammability`와 `base_conductivity`를 `0..100`에서 조정할 수 있다. 따라서 snapshot은 terrain 기본값과 scalar가 동일할 것을 강요하지 않는다. 다만 terrain ID는 registry에 반드시 존재해야 한다.

`world_state_error()`, `snapshot_wire_error()`와 producer가 같은 terrain registry·범위를 사용한다.

- 알 수 없는 terrain ID의 snapshot은 명시 오류와 `from_snapshot()==null`
- 알 수 없는 terrain을 직접 주입한 world는 `snapshot()==null`
- impassable terrain 위의 생존 개체는 invalid world
- invalid bootstrap은 상태와 ID를 소비하지 않음

## 6. 점유 규칙

Phase 2의 점유는 단순하고 결정론적으로 고정한다.

- 한 passable tile에는 생존 개체가 최대 1명
- 죽은 개체는 이동을 막지 않음
- `add_entity()`는 wall/unknown terrain 또는 다른 생존 개체가 있는 위치를 entity ID 소비 전에 `null`로 거부
- checked restore는 같은 위치의 생존 개체 중복과 impassable 위치를 거부
- `blocking_entity_at(position, except_entity_id=-1)` 또는 동등 query는 ID 정렬 기준으로 결정론적 결과를 냄
- 죽은 시체와 생존 개체가 같은 위치에 저장되는 것은 허용

지금은 점유 index를 따로 유지하지 말고 개체 수가 작은 prototype에 맞춰 안정 정렬 조회를 사용해도 된다. index를 추가한다면 snapshot에서 파생 재구축하며 별도 authoritative 상태로 저장하지 않는다.

## 7. MOVE command wire와 검증

기존 enum 숫자를 바꾸지 않고 마지막에 추가한다.

```text
WAIT=0
IGNITE=1
POUR_WATER=2
DISCHARGE=3
MOVE=4
```

factory:

```text
SimCommand.move_to(actor_id, destination: Vector2i) -> SimCommand
```

command의 기존 `position`은 MOVE에서 목적지다. `power=0`이고 wait duration은 wire shape를 위한 기본값일 뿐 MOVE 의미에 사용하지 않는다.

MOVE 유효 조건:

- `actor_id>=1`; sentinel `-1`은 불가
- actor가 존재하고 생존
- actor의 현재 위치에서 목적지까지 Manhattan distance가 정확히 1
- 목적지가 bounds 안
- 목적지 terrain이 registry에 있고 passable
- 목적지에 다른 생존 개체가 없음
- 목적지 이동 비용이 registry 범위 안

거부 reason은 최소 다음을 구분한다.

```text
move_requires_actor
move_not_cardinal_adjacent
move_out_of_bounds
move_terrain_blocked
move_destination_occupied
```

일반 actor 없음/사망은 기존 `actor_not_found`, `actor_dead`를 유지한다. 벽에 부딪히는 것을 WAIT나 공격으로 암묵 변환하지 않는다. 모든 거부는 완전 no-op이다.

command JSON은 큰 actor ID를 canonical 문자열로 보존한다. MOVE의 `power!=0`, fractional destination, 숫자형 actor ID, 알 수 없는 type은 decode에서 `null`이다. 기존 0..3 wire 숫자는 그대로 해석된다.

`MovementSystem.assess_move(actor_id, destination)`은 위 검증 순서를 수행하는 순수 query이며 detached `TraversalAssessment`를 반환한다.

```text
accepted
reason
actor_id
from_position
to_position
terrain_id
blocking_entity_ids       # 오름차순
sampled_world_time
```

UI나 미래 AI가 이 결과를 보더라도 실행 token으로 쓰지 않는다. `Simulator.step()`은 현재 authoritative state에서 다시 평가한다. player-kind와 NPC-kind actor는 같은 assessment·timing·commit 내부 경로를 쓰되, 이번 단계에서 NPC의 world-time coordinator는 구현하지 않는다.

## 8. MOVE 시간·commit·사건 계약

이동 시간의 유일한 authority는 `ActionTimingTable`이다. Simulator나 UI가 별도 상수를 복제하지 않는다.

```text
MOVE time cost = 목적지 TerrainDefinition.move_time_cost
speed tier = 기존 speed_tier_for(cost)
```

따라서 floor/stone/wood는 100 NORMAL, shallow water는 130 SLOW, rubble은 140 SLOW다. 종족 affinity는 위험 해석일 뿐 이동 비용을 바꾸지 않는다.

preview와 step이 공유하는 `_plan_action()`이 현재 snapshot에서 목적지 terrain과 비용을 다시 읽는다. 오래된 preview를 commit하지 않는다.

MOVE 실행 순서:

```text
start_time
→ action.move root event 생성
→ actor.position을 목적지로 변경
→ (start, end] environment occurrences 처리; 모두 새 위치를 봄
→ actor.ready 시간 경계
→ step 정착
```

`action.move` 사건:

```text
type = "action.move"
actor_id = 이동 actor
position = destination
magnitude = move_time_cost
data = {
  "from_position": [x, y],
  "to_position": [x, y],
  "terrain_id": String,
  "move_time_cost": int
}
```

root 사건과 위치 변경은 이미 검증된 계획을 commit하는 내부 경로다. 둘 사이에 실패 가능한 외부 hook을 두지 않는다.

행동 시작이 `t=80`, 목적지 비용이 100이면 actor는 `t=80`에 목적지에 있고 `t=100` 환경 틱은 목적지의 불을 적용한다. 반대로 불타는 출발 칸에서 빠져나오면 그 틱은 이전 칸의 피해를 주지 않는다. `t=end_time` 환경 틱도 같은 규칙으로 ready보다 먼저 적용한다.

## 9. 화재·젖음 source semantic 강화

Exposure가 source를 사용자와 미래 AI에 노출하므로 기존의 “존재하는 과거 event ID” 검증만으로는 부족하다. restore와 `world_state_error()`에서 producer가 실제 만들 수 있는 의미로 좁힌다.

불이 있는 타일:

- `fire_source_event_id`의 사건 위치가 같은 타일
- source type은 `environment.ignited` 또는 `environment.fire_spread`
- 직접 점화면 `fire_damage_eligible_time == source.world_time`
- 확산이면 `fire_damage_eligible_time == source.world_time + 100`
- checked arithmetic으로 overflow 없음

젖음이 있는 타일:

- `wetness_source_event_id`는 sentinel이 아니며 같은 타일의 `environment.water_applied`
- source event는 실제 증가량 `magnitude>0`
- source time은 현재 시간보다 늦지 않음

즉 `(tile.wetness == 0) == (wetness_source_event_id == -1)`을 양방향으로 지킨다. 정적 `shallow_water`는 tile wetness가 아니므로 동적 wetness source를 요구하지 않는다. source 목록은 현재 활성 상태의 **대표 출처**일 뿐 모든 과거 물 기여를 보존하는 ledger가 아니다.

기존 수동 화재 fixture는 임의 `test.fire`를 snapshot 가능한 source로 남기지 말고, 올바른 `environment.ignited` bootstrap helper나 실제 IGNITE command로 갱신한다. 변조 snapshot은 error string과 null restore로 끝나며 script error·부분 객체를 만들지 않는다.

## 10. ExposureSample 계약

Exposure는 정착한 authoritative world에서 한 위치를 읽는 순수 projection이다.

```text
ExposureSystem.sample(position) -> ExposureSample | null
```

out of bounds이거나 세계가 step 처리 중이면 `null`이다. 호출 전후 snapshot, RNG state, next IDs, 예약 큐가 완전히 같아야 한다.

내부 sample 필드:

```text
position: Vector2i
sampled_step_index: int
sampled_world_time: int
after_event_id: int                 # sample 직전 마지막 event, 없으면 -1
next_environment_time: int

terrain_id: String
passable: bool
move_time_cost: int

fire_intensity: int
fire_damage_eligible_time: int
known_fire_damage_at_next_tick: int
terrain_water_exposure: int
wetness: int
water_exposure: int
conductivity: int
electric_risk: int
electric_certainty: String           # 이번 ruleset에서는 "NONE"
poison_intensity: int

fire_source_event_id: int
wetness_source_event_id: int
source_event_ids: Array[int]        # sentinel 제거, 오름차순 unique
```

계산:

```text
fire_intensity = tile.fire
known_fire_damage_at_next_tick = 현재 불·젖음·eligibility를 다음 cadence에 투영한 확정 피해
terrain_water_exposure = terrain definition 값
wetness = tile.wetness
water_exposure = max(terrain_water_exposure, wetness)
conductivity = tile.effective_conductivity()
electric_risk = 0
electric_certainty = "NONE"
poison_intensity = 0
```

`known_fire_damage_at_next_tick`은 주변 확산 확률을 예언하지 않고 현재 이미 타는 불만 대상으로 한다. 환경 실행 코드와 공식을 복제하지 말고 `EnvironmentRules.project_existing_fire_tick(...)` 같은 pure kernel을 추출해 실제 `_tick_existing_fire()`와 sample이 공유한다. kernel은 suppression, suppression 뒤 fire/wetness, 자연 감소 뒤 fire, eligibility를 반영한 damage를 정수 DTO로 반환한다. 현재 피해 cap 20과 fire decay 5를 한 군데에서만 정의한다.

```text
suppression = min(fire, wetness)
fire_after_suppression = fire - suppression
wetness_after_suppression = wetness - suppression
fire_after_decay = max(0, fire_after_suppression - 5)
known_damage = min(20, fire_after_decay)
  if fire_after_decay > 0
     and fire_damage_eligible_time >= 0
     and next_environment_time >= fire_damage_eligible_time
  else 0
```

환경 틱 마지막의 별도 wetness 자연 감소 2는 위 fire suppression kernel 이후 기존 순서대로 처리한다.

정착 경계에는 persistent charge가 없다. DISCHARGE는 행동 시작 시 BFS arc와 피해까지 모두 완결된다. 따라서 conductivity가 높다는 이유만으로 `electric_risk`를 올리거나 affinity total에 감전 위험을 더하지 않는다. conductivity는 “전기가 들어오면 잘 통하는 성질”을 보여주는 진단값일 뿐이다. 가상 방전 overlay와 persistent 전기는 이후 별도 계약이다.

`to_dict()`에서 step/time/event ID는 canonical decimal string으로 내보내고 위치와 작은 scalar는 JSON 정수로 낸다. DTO와 중첩 배열은 detached다.

## 11. 종족 affinity registry

관계의 `SpeciesRelationTable`과 위험 affinity는 별도 책임이다.

```text
HazardAffinity
  species_id: String
  fire_tolerance: int
  water_tolerance: int
  electric_tolerance: int
  poison_tolerance: int
```

모든 tolerance는 `-100..100`이다. 0은 중립, 양수는 내성, 음수는 취약이며 100은 해당 노출을 완전히 무시한다. 이동 가능성이나 이동 속도를 뜻하지 않는다.

v1 built-in profile:

| species | fire | water | electric | poison |
|---|---:|---:|---:|---:|
| `default` | 0 | 0 | 0 | 0 |
| `human` | 20 | 25 | 10 | 10 |
| `goblin` | -10 | -10 | -10 | 10 |
| `amphibian` | -25 | 100 | -25 | 30 |
| `dwarf` | 40 | -25 | 20 | 20 |

알 수 없거나 빈 species ID는 `default`를 사용한다. registry public 반환값을 바꿔도 원본 profile이 변하지 않아야 한다.

## 12. 위험 평가 공식

평가기는 world, RNG, event emitter를 참조하지 않는 pure 함수다.

```text
evaluate(sample, affinity) -> ExposureEvaluation
```

각 component는 부동소수점 없이 다음 ceil 비율을 쓴다.

```text
component(intensity, tolerance)
  = (intensity * (100 - tolerance) + 99) / 100의 정수 몫

fire_score     = component(sample.fire_intensity, affinity.fire_tolerance)
water_score    = component(sample.water_exposure, affinity.water_tolerance)
electric_score = component(sample.electric_risk, affinity.electric_tolerance)
poison_score   = component(sample.poison_intensity, affinity.poison_tolerance)
total_risk     = fire_score + water_score + electric_score + poison_score
```

구현 언어의 `/`가 float를 만들면 범위가 작더라도 명시적으로 정수 변환하고 테스트로 경계를 고정한다. 입력은 이미 `0..100`, component는 `0..200`, total은 `0..800`이다.

평가 DTO는 최소 다음을 가진다.

```text
species_id
sampled_step_index
sampled_world_time
position
fire_score
water_score
electric_score
poison_score
total_risk
```

동일 sample의 shallow water 80은 human water score 60, amphibian 0, dwarf 100이다. 동일 fire 80은 human 64, amphibian 100이다. 이것이 이번 단계에서 직접 확인할 핵심 종족 차이다.

다음과 동등한 편의 API를 제공한다.

```text
ExposureSystem.evaluate_for_entity(entity_id, position)
  -> {sample, affinity, evaluation} detached DTO | null
```

개체가 없거나 죽었거나 위치가 invalid면 null이다. 이 API를 이후 안전 타일 선택 AI와 Playtest HUD가 그대로 사용한다.

추가로 `assess_destination(entity_id, position)` 또는 동등 public pure API가 traversal legality, authoritative terrain move time, sample, affinity, component score를 하나의 detached `DestinationAssessment`로 묶어 반환한다. 위험 점수는 설명·선택용이며 MOVE accepted 여부나 실제 world-time cost를 절대 바꾸지 않는다.

## 13. snapshot v3와 registry version

지형·이동 비용·affinity는 replay 의미를 바꾸므로 조용히 Phase 1 ruleset으로 저장하지 않는다.

```text
snapshot_version = 3
ruleset_version = "phase2-move-exposure-v1"
terrain_ruleset_id = "terrain-registry-v1"
hazard_affinity_ruleset_id = "hazard-affinity-v1"
```

두 registry ID는 snapshot header의 필수 String이다. 불일치하면 객체를 만들기 전에 명시적으로 거부한다. snapshot v1/v2는 이번 prototype에서 암묵 마이그레이션하지 않는다.

ExposureSample과 evaluation은 파생 DTO이므로 snapshot에 저장하지 않는다. 지형 ID, 동적 타일 상태, entity species와 위치만 저장하면 복원 직후 같은 sample과 score가 나와야 한다.

producer/restore 도메인:

- registry에 없는 terrain 거부
- passable/occupancy 불변식 생성·복원 양쪽 동일
- source event type/position/eligibility 생성·복원 양쪽 동일
- v3 JSON 왕복 exact snapshot
- 중간 저장 전후 MOVE journal 최종 snapshot·timeline·exposure 결과 동일

## 14. PlaytestSession

UI와 simulator 사이에 headless로 테스트할 수 있는 얇은 session을 둔다.

책임:

- 고정 seed와 species로 새 arena 생성
- terrain bootstrap과 player 생성
- 선택 위치 관리
- MOVE/WAIT/IGNITE/POUR_WATER/DISCHARGE command 제출
- accepted command journal을 `command.to_dict()` 배열로 보존
- 마지막 result·events·timeline 보존
- snapshot v3 JSON 저장·불러오기
- 같은 seed reset과 species 변경 reset
- HUD용 current tile sample/evaluation 제공

session은 이동·위험 공식을 복제하지 않는다. Simulator와 ExposureSystem의 public API만 호출한다.

고정 arena는 `32×48`로 하고 외곽 wall, floor 통로, rubble, wood floor, metal, shallow water, 불을 붙여볼 구역을 포함한다. player 출발점과 최소 한 개 목표 지점을 둔다. 이것도 최종 월드 크기가 아니라 scroll/camera와 규칙을 확인하는 경기장이다.

저장 슬롯은 `user://playtest_slot_v1.json` 하나면 충분하다. 파일 실패는 UI를 깨뜨리지 않고 상태 메시지로 설명한다. 테스트는 별도 `/tmp` XDG 경로를 쓴다.

## 15. 세로형 Playtest Sandbox

`project.godot`의 main scene을 sandbox로 설정해 다음으로 바로 실행되게 한다.

```bash
godot --path /mnt/d/STARTU/living-world-sim
```

450×800 기준 최소 UI:

- 상단: seed, species, HP, `step_index`, `world_time`, 다음 환경 틱
- 중앙: player 중심 `9×9` camera window, player·wall·water·rubble·wood·metal·fire·wetness 구분
- 선택 칸 highlight
- 하단: 선택 칸 terrain/material/exposure, 다음 틱 확정 fire damage, electric certainty와 종족별 component·total score
- 최근 사건/거부 reason/timeline을 보여주는 접을 수 있는 log
- 버튼: WAIT, IGNITE, WATER, DISCHARGE, SAVE, LOAD, RESET
- species reset 선택: HUMAN / AMPHIBIAN
- 키보드: 방향키와 WASD로 MOVE
- 마우스/터치: 인접 칸을 누르면 MOVE, 그 외 칸은 선택만 함

맵은 `_draw()` 등 가벼운 방식으로 그려도 된다. production sprite나 애니메이션을 만들지 않는다. 색·문자 legend를 화면에 명시해 처음 실행한 사람도 해석할 수 있게 한다.

행동 뒤 항상 authoritative session에서 HUD를 다시 읽는다. UI가 성공했다고 가정해 player 좌표나 시간을 자체 증가시키지 않는다. actor가 환경 틱에서 죽으면 GAME OVER와 마지막 사건을 표시하고 이동 입력을 simulator의 `actor_dead` 거부로 그대로 보여준다.

화면에서 직접 확인 가능한 시나리오:

1. floor 이동은 100, shallow water 이동은 130, rubble 이동은 140만큼 시간 증가
2. `t=80` 부근에 불 칸으로 MOVE하면 `t=100` 틱이 새 위치를 공격
3. 물 칸 선택 시 HUMAN은 water risk 60, AMPHIBIAN은 0
4. conductivity가 높아도 현재 `electric_risk=0`, 실제 DISCHARGE 순간에만 arc·피해 사건 발생
5. SAVE 후 몇 걸음 이동하고 LOAD하면 위치·시간·불·젖음·평가가 정확히 복원

## 16. 필수 회귀 테스트

기존 63개를 보존하고 아래 동작을 새 테스트로 고정한다. 한 test method에 여러 경계를 묶어도 되지만 항목을 누락하지 않는다.

### TerrainRegistry·bootstrap

1. 모든 built-in ID와 정확한 v1 값
2. registry 반환 DTO 변형이 registry 원본에 영향 없음
3. invalid terrain ID/bounds/늦은 bootstrap이 전체 무변경
4. terrain 설정이 기본 material과 dynamic sentinel을 올바르게 초기화
5. unknown terrain의 world는 snapshot null, v3 restore는 명시 오류/null
6. wall 위 add_entity가 entity ID 소비 전 거부
7. 한 칸의 두 생존 개체 producer와 restore 모두 거부
8. 죽은 개체와 생존 개체의 동거는 허용되고 exact round-trip

### MOVE

9. 네 cardinal 방향 각각 성공, 대각선·제자리·두 칸 이동 거부
10. actor sentinel/없음/사망, bounds, wall, 생존 점유 destination이 완전 no-op
11. 거부 MOVE가 RNG/event/schedule/entity ID/time/step/position을 바꾸지 않음
12. floor 100, shallow water 130, rubble 140과 speed tier 정확
13. `action.move` event의 위치·magnitude·data·actor·timeline 소유 정확
14. MOVE preview 순수성, 오래된 preview 뒤 현재 terrain/time에서 재계획
15. t80 이동이 t100 환경 틱 전에 start commit되고 새 위치가 피해를 받음
16. 불타는 출발 칸에서 빠져나온 actor는 이후 틱에 이전 칸 피해를 받지 않음
17. due==move end 환경 틱이 ready보다 먼저 처리
18. 이동 구간 사망 뒤 step은 정착하지만 다음 MOVE는 actor_dead
19. MOVE command JSON 큰 actor ID exact, invalid power/fraction/type null
20. 같은 seed·MOVE journal의 timeline과 snapshot 동일
21. MOVE 중간 v3 JSON 복원과 연속 실행 결과 동일

### source semantic

22. 직접 불 source 위치/type/eligibility exact 검증
23. 확산 불 source 위치/type/eligibility exact 검증
24. 젖음 source 위치/type/양수 magnitude 검증
25. 잘못된 source type, 다른 위치, 임의 미래 eligibility가 오류/null restore

### Exposure·affinity

26. sample 전후 전체 snapshot·RNG·ID 동일
27. sample의 step/time/after event/next cadence 정확
28. fire, static water, wetness max, conductivity와 shared fire-kernel의 다음 틱 확정 피해 계산 정확
29. persistent charge가 없을 때 electric risk는 항상 0이며 conductivity만으로 점수 증가 없음
30. poison은 0
31. source ID가 sentinel 없이 오름차순 unique
32. out of bounds와 active partial step sample null
33. sample/evaluation 중첩 DTO 변형이 world·registry에 영향 없음
34. tolerance -100/0/100과 ceil 공식 중간 경계 정확
35. shallow water 80의 HUMAN 60, AMPHIBIAN 0, DWARF 100
36. fire 80의 HUMAN 64, AMPHIBIAN 100
37. unknown species가 default와 동일
38. 죽은/없는 entity 평가 null
39. v3 JSON restore 직후 동일 위치의 sample/evaluation exact
40. DestinationAssessment가 traversal/time/sample/component를 detached하게 결합하고 hazard score가 legality나 move cost를 바꾸지 않음

### Playtest·전체 회귀

41. PlaytestSession 같은 seed/species reset이 동일 initial snapshot
42. session MOVE가 command journal, 위치, HUD sample을 갱신
43. session SAVE→변경→LOAD가 snapshot과 evaluation을 복원
44. main scene headless instantiate와 한 MOVE/WAIT smoke test
45. 기존 원소·관계·시간 데모와 회귀 전부 통과
46. 혼합 MOVE/원소/WAIT 100개 명령, 10,000+ world time, midpoint JSON restore 후 snapshot·RNG·event hash·exposure 동일

## 17. 데모와 실행 검증

`examples/move_exposure_demo.gd`는 최소 다음을 출력한다.

```text
human shallow_water: water_score=60 total=60
amphibian shallow_water: water_score=0 total=0
move floor @0→100
move shallow_water @100→230
snapshot restore: exact=true
```

실제 값에 fire 등 다른 exposure를 섞었다면 component를 함께 출력해 기대값을 명확히 한다.

검증 명령:

```bash
XDG_DATA_HOME=/tmp/lws-phase2-data \
XDG_CONFIG_HOME=/tmp/lws-phase2-config \
XDG_CACHE_HOME=/tmp/lws-phase2-cache \
GODOT_SILENCE_ROOT_WARNING=1 \
godot --headless --path /mnt/d/STARTU/living-world-sim \
  --script res://tests/run_tests.gd

godot --headless --path /mnt/d/STARTU/living-world-sim \
  --script res://examples/move_exposure_demo.gd

godot --headless --path /mnt/d/STARTU/living-world-sim \
  --editor --quit
```

두 기존 데모도 다시 실행한다.

```text
res://examples/element_chain_demo.gd
res://examples/time_timeline_demo.gd
```

stdout/stderr에서 `SCRIPT ERROR`, parse error, orphan 관련 새 오류가 없어야 한다.

## 18. 문서 갱신

README에 다음을 추가한다.

- `godot --path .`로 Playtest Sandbox 실행
- 키보드·마우스/터치·버튼 조작
- terrain v1 표와 이동 비용
- MOVE start-commit과 환경 틱 의미
- Exposure가 순수 정착 projection이라는 점
- conductivity와 확정 electric risk의 차이
- affinity 공식과 built-in profile
- snapshot v3 및 v1/v2 비호환 정책
- 작은 playtest arena는 최종 맵 규모가 아니라는 점

`docs/NEXT_DEVELOPMENT_GUIDE.ko.md`에서는 이번 두 단계를 완료로 표시하고 다음을 아래 순서로 둔다.

```text
Playtest Sandbox 유지·각 단계 시나리오 추가
→ 범용 안전 타일 선택 AI
→ 불·물·전기 exposure 연결 확장
→ 독·DOT
→ 인지·관계·기억
→ 자율 동료 1명→3명
```

각 다음 단계의 완료 조건은 계속 아래 셋을 모두 요구한다.

```text
자동 회귀 통과
+ 5분 플레이 시나리오 완주
+ seed·command journal·snapshot으로 재현 가능
```

## 19. 구현 순서

1. registry와 snapshot v3 header부터 추가
2. bootstrap·occupancy producer/restore 대칭 고정
3. MOVE command wire·timing·plan·commit·event
4. source semantic 강화와 기존 fixture 갱신
5. ExposureSample과 pure evaluator
6. headless 데모와 회귀
7. PlaytestSession
8. 세로형 UI/main scene
9. 장기 결정론·JSON midpoint 재개
10. README와 다음 가이드

각 단계에서 전체 테스트를 돌린다. UI를 먼저 만들어 core 규칙을 UI 안에 복제하지 않는다.

## 20. 최종 보고 형식

완료 보고에는 다음을 포함한다.

- 실제 수정·추가 파일
- snapshot/ruleset 변경과 호환 정책
- terrain 값, MOVE 비용·점유·commit 의미
- Exposure·affinity 공식과 electricity 제한
- 전체 테스트 수와 실패 수
- 장기 결정론 최종 world time과 midpoint restore 결과
- 세 데모 결과
- Playtest 실행법과 조작법
- 남은 의도적 제한
- 발견했지만 이번 범위 밖이라 남긴 P2 이하 항목

구현 도중 이 문서와 기존 불변식이 충돌하면 임의로 의미를 바꾸지 말고, 충돌 위치·재현식·가장 작은 수정안을 먼저 보고한다.
