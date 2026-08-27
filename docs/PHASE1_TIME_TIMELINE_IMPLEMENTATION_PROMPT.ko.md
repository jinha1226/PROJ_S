# Living World Simulator — 턴·세계시간 분리와 행동 타임라인 구현 프롬프트

## 역할과 작업 위치

당신은 Godot 4.6/GDScript 기반 헤드리스 결정론적 시뮬레이션 코어의 구현 담당자다.

- 작업 프로젝트: `/mnt/d/STARTU/living-world-sim`
- 다른 프로젝트(`PROJ_G`, `slime-automation` 등)는 절대 수정하지 않는다.
- 현재 코드와 29개 회귀 테스트를 모두 먼저 읽고 시작한다.
- 그래픽, 씬, 실제 모바일 UI는 만들지 않는다.
- 이 문서의 preview/timeline 모델은 이후 UI가 소비할 헤드리스 데이터 계약이다.
- 구현 후 전체 테스트, 기존 원소 데모, 신규 시간 데모를 직접 실행한다.

## 최종 목표

현재의 아래 결합을 제거한다.

```text
플레이어 명령 1회
= world.turn 1 증가
= EnvironmentSystem.advance_turn() 1회
```

다음 세 축을 명시적으로 분리한다.

```text
step_index  플레이어가 내린 유효한 결정의 순서
world_time  세계에서 실제로 경과한 64비트 정수 시간
event_id    같은 시각을 포함한 모든 사건의 완전한 결정론적 순서
```

플레이어가 명령을 선택하면 행동은 현재 시각에 해결되고, 그 행동의 시간 비용 안에 예정된 환경·상태·향후 NPC 사건을 시간순으로 처리한다. 플레이어가 다시 행동 가능한 시각에 시뮬레이션이 멈춘다.

이번 단계에서 실제 NPC, MOVE, 독, UI를 구현하지 않는다. 대신 이후 시스템이 같은 시간축에 안전하게 올라갈 수 있는 스케줄러와 다음 정보를 제공한다.

```text
행동 속도: FAST / NORMAL / SLOW
행동 시작·종료 세계시간
플레이어가 다시 행동하기 전 처리될 공개 가능한 타임라인 항목
실제로 처리된 타임라인 항목
```

## 1. 용어와 절대 불변식

### 1.1 `step_index`

- 유효한 플레이어 명령 하나가 완전히 정착한 뒤 정확히 1 증가한다.
- 한 행동 동안 환경 틱이 0회, 1회, 여러 회 실행돼도 1만 증가한다.
- 거부된 명령은 증가시키지 않는다.
- NPC와 예약 시스템은 독자적으로 `step_index`를 증가시키지 않는다.
- 게임 달력 계산에 사용하지 않는다.

### 1.2 `world_time`

- 음수가 아닌 64비트 정수다.
- 시간 비용이 있는 유효한 행동만 전진시킨다.
- 처리 중에는 각 예약 항목의 정확한 `due_time`으로 이동하고, 모든 항목 처리 후 행동 종료 시각에 도달한다.
- 절대로 감소하지 않는다.
- 거부 입력과 순수 preview는 변경하지 않는다.

기준 단위는 아래로 고정한다.

```text
STANDARD_ACTION_COST = 100
TIME_UNITS_PER_ABSTRACT_MINUTE = 100
ENVIRONMENT_INTERVAL = 100
```

즉 표준 행동 하나는 UI 달력상 추상 1분에 대응한다. 이는 물리적으로 공격 한 번이 60초라는 뜻이 아니라 살아 있는 세계를 관찰할 수 있게 압축한 달력 규칙이다.

### 1.3 `event_id`

- 사건의 완전한 전역 순서다.
- 같은 `world_time`의 사건도 ID로 안정적으로 정렬된다.
- `cause_id`는 항상 더 작은 기존 사건을 가리킨다.
- 파생 사건은 원인보다 이른 `world_time`을 가질 수 없다.

### 1.4 플레이어 결정 경계

`Simulator.step()` 호출 전후에는 세계가 정착된 상태여야 한다.

- 처리 대기 중인 즉시 피해가 없어야 한다.
- `due_time <= world_time`인 미처리 예약 항목이 없어야 한다.
- 스냅숏은 이 정착 경계에서만 허용한다.

플레이 시작 후 UI에 노출하는 **유일한 세계 진행 API는 원자적인 `Simulator.step()`** 이다. 월드 생성용 `add_entity`, fixture의 타일 설정처럼 플레이 이전 bootstrap API까지 금지한다는 뜻은 아니다.

- `commit_action()`과 `advance_time()`처럼 사용자가 따로 호출할 수 있는 반쪽 API를 만들지 않는다.
- 한 번의 `step()`은 검증부터 행동, 예약 처리, 정착까지 전부 끝낸 뒤 반환한다.
- `preview()`와 달력 계산은 순수 조회 API다.
- 저장은 `step()` 도중이 아니라 위 정착 경계에서만 가능하다.
- 처리 한도 초과나 정착 불변식 위반은 일부 진행된 세계를 정상적인 거부 결과로 돌려주는 상황이 아니라 구현 결함이다. 가능한 한 commit 전 순수 계획 단계에서 거부하고, 예상하지 못한 위반은 fail-fast 한다.

## 2. 프로토타입 행동 시간표

작은 데이터 기반 `ActionTimingTable` 또는 동등한 순수 규칙 계층을 둔다. 명령 객체가 임의의 시간 비용을 제출하도록 하지 않는다.

이번 단계의 고정값:

```text
WAIT          100  NORMAL  # wait() 기본값
IGNITE        120  SLOW
POUR_WATER     80  FAST
DISCHARGE     160  SLOW
MAX_WAIT_COST 10000
```

속도 등급:

```text
cost < 100   FAST
cost == 100  NORMAL
cost > 100   SLOW
```

이 수치는 최종 밸런스가 아니라 시간 분리 계약을 실제로 검증하기 위한 첫 규칙이다. 코드 여러 곳에 `match`를 복제하지 말고 한 계층에서만 비용과 등급을 계산한다.

시간 분리가 단지 이름 변경이 아님을 검증하고 휴식 UI의 기반을 만들기 위해 WAIT만 명시적 기간을 허용한다.

```gdscript
SimCommand.wait(actor_id)                         # 기존 호환: 100
SimCommand.wait_for(duration_time_units, actor_id) # 1..10000
```

- `duration_time_units`는 양의 정수여야 하며 범위를 벗어나면 명령 전체를 무변경 거부한다.
- WAIT의 실제 비용과 등급은 요청 기간으로부터 `ActionTimingTable`이 계산한다.
- WAIT 이외 명령이 명령 데이터로 임의 비용을 주입할 수 있게 만들지 않는다.
- 명령을 저장하거나 예약할 필요가 생기면 호출자가 가진 가변 객체를 보관하지 말고 검증된 값을 복사한 DTO만 사용한다. 이번 단계에서 행동 자체는 예약하지 않는다.

향후 종족·상태·지형 보정은 basis point 정수 계산으로 확장할 수 있어야 하지만, 아직 사용하지 않는 속도 필드나 MOVE를 미리 만들지 않는다.

### 2.1 명령 journal wire 계약

`SimCommand.to_dict()/from_dict()`를 JSON 명령 journal에 사용할 것이므로 snapshot과 같은 정밀도 원칙을 지킨다.

- `actor_id`는 sentinel을 포함한 canonical decimal string으로 저장한다.
- `type`, `power`, WAIT duration, `position[x,y]`는 명시적으로 작은 JSON 정수다. JSON parser가 만든 `.0` 값은 정확한 정수이고 범위 안일 때만 허용하되, `0.5`를 `int()`로 절삭하지 않는다.
- `position`은 길이 2의 배열과 Vector2i 범위를 검증한다.
- `SimCommand.command_wire_error(data)` 또는 동등한 순수 검증을 먼저 거치고, malformed `from_dict()`는 `null`을 반환한다. 이를 `step(null)`에 넘겨도 전체 무변경 거부다.
- `2^53+1` 이상의 actor ID도 `to_dict → JSON → from_dict` 뒤 정확히 같아야 한다.
- 이 command wire는 snapshot v2와 별개로 schema/version을 명시하거나 최소한 README에 현재 계약을 고정한다.

## 3. 행동 해결 의미론

행동은 **시작 시점에 commit**되고, 다음 행동 가능 시각까지 세계가 진행된다.

예:

```text
현재 world_time = 80
DISCHARGE 비용 = 160
행동 종료 시각 = 240

@80   방전 행동과 즉시 전기 아크·피해
@100  환경 틱
@200  환경 틱
@240  플레이어 다시 준비, 시뮬레이션 정지
```

예약 구간은 다음으로 고정한다.

```text
(start_time, end_time]
```

- 종료 시각과 같은 예약 항목은 플레이어가 다시 준비되기 전에 처리한다.
- 시작 시각과 같은 예약 항목은 호출 전 정착 불변식상 존재하면 안 된다.
- 행동 비용은 항상 양수다.

거부 입력은 행동, 즉시 효과, 시간, 스케줄러, RNG, 사건 ID를 전혀 변경하지 않는다.

`accepted`는 **현재 상태에서 명령을 실행할 자격과 형식이 유효하다**는 뜻이지, 환경 효과가 성공했다는 뜻이 아니다. 예를 들어 범위 안의 비가연성 타일에 유효한 IGNITE를 쓰면 행동과 `environment.ignition_failed`가 기록되고 120을 소비한다. 효과 성공 여부를 `accepted`와 혼동하지 않는다.

이번 단계의 행동 효과는 모두 시작 시점에 완결된다. 행동 완료 예약, 캐스팅 중 취소, 중간 피해로 인한 취소는 구현하지 않는다. 비용은 행동 후 회복 중 세계가 경과하는 시간이며, 시작 후 다시 계산하지 않는다.

## 4. 결정론적 예약 스케줄러

작고 범용적인 직렬화 가능 스케줄러를 만든다. `Callable`, Godot signal, Timer, Node, 실제 시계, 비동기를 사용하지 않는다.

예약 큐와 다음 ID는 시스템 객체가 아니라 `WorldState`가 소유해 스냅숏의 일부가 되게 한다.

최소 예약 모델:

```text
schedule_id: int
due_time: int             # GDScript int = signed 64-bit
priority: int
kind: String
owner_id: int
source_event_id: int
repeat_interval: int      # 0이면 일회성
payload: JSON-safe Dictionary
```

정렬 키:

```text
(due_time, priority, schedule_id)
```

동일 시각의 처리 결과가 Dictionary 삽입 순서에 좌우되지 않아야 한다.

반복 항목은 처리 지연이 누적되지 않도록 다음처럼 재예약한다.

```text
next_due = previous_due + repeat_interval
```

`current_time + repeat_interval`을 사용하지 않는다. 반복 간격은 양수여야 한다. 처리기가 현재 시각 이하로 새 항목을 예약하는 것도 거부한다.

반복 항목은 매 발생마다 새 ID를 소비하지 않고 같은 `schedule_id`를 유지한 채 `due_time`만 위 공식으로 전진시킨다. 따라서 preview와 실제 timeline에서 같은 환경 cadence의 여러 발생은 같은 schedule ID를 가진다. 새 논리 예약을 처음 만들 때만 `next_schedule_id`를 소비한다.

이번 단계의 실제 예약 종류는 하나다.

```text
system.environment_tick
due_time = 100
priority = 100
repeat_interval = 100
```

스케줄러는 일반 데이터를 반환하고, `Simulator`가 `kind`를 명시적으로 dispatch한다. 범용 스크립트 DSL은 만들지 않는다.

preview와 실제 marker parity를 보장하기 위해 이번 단계의 dispatch handler는 새로운 논리 예약을 만들지 않는다. 이미 존재하는 반복 항목의 같은-ID 재예약만 허용한다. 향후 NPC/상태 handler가 행동 구간 안에 새 공개 예약을 만들 수 있게 할 때는 preview 공개 정책과 marker 병합 규칙을 먼저 별도 계약으로 추가한다.

한 행동에서 비정상적으로 많은 항목이 생성되는 무한 루프를 검출하는 방어 한도를 둔다. 단, 정상적인 테스트용 긴 행동을 임의로 잘라 성공 처리하지 말고 명시적으로 실패시킨다.

preview와 실제 실행은 아래 **하나의 occurrence 열거 규칙**을 공유한다.

```text
정착 큐의 모든 row: due_time > start_time
처리 조건: due_time <= end_time
반복 occurrence 뒤 virtual/live next_due = checked_add(previous_due, repeat_interval)
next_due <= end_time이면 같은 schedule_id의 다음 occurrence도 열거
occurrence 정렬: (at_time, priority, schedule_id)
due_time == end_time인 모든 occurrence 뒤에 actor.ready
```

- 큐 안에서는 `schedule_id`가 유일하다.
- timeline occurrence의 식별자는 `(schedule_id, at_time)`이며 반복 occurrence끼리는 같은 ID를 재사용한다.
- preview의 가상 열거는 큐나 `next_schedule_id`를 변경하지 않는다.
- `MAX_SCHEDULE_OCCURRENCES_PER_STEP = 1024`로 둔다. 현재 WAIT 상한과 단일 100 간격 cadence에서는 정상 계획이 이 값에 훨씬 못 미친다.
- 순수 계획 단계에서 occurrence 수가 한도를 넘으면 `schedule_budget_exceeded`로 전체 무변경 거부한다. 계획 수와 실제 처리 수가 다르거나 dispatch가 계획에 없던 `due_time <= end_time` 항목을 만들면 정상 거부가 아니라 구현 결함으로 fail-fast 한다.

## 5. 순수 행동 preview와 UI용 타임라인

`Simulator.preview(command)` 또는 동등한 API를 만든다. 내부에는 검증과 정규화된 비용·시간 마커를 한 번만 정의하는 순수 `_plan_action(command)` 또는 동등 계층을 두고, `preview()`와 `step()`이 함께 사용한다.

- `step()`은 과거 preview 객체를 신뢰하거나 실행 토큰처럼 받지 않고, 호출 순간의 현재 세계에서 다시 계획한다.
- preview 뒤 다른 행동으로 시간이 흘렀다면 예전 preview는 낡은 표시일 뿐이며 새 `step()` 결과는 현재 상태 기준이어야 한다.
- 계획은 명령 실행 가능 여부와 시간표만 계산한다. 확률적 효과 결과는 계산하지 않는다.

이 함수는 아래를 절대 변경하지 않는다.

```text
world_time
step_index
RNG state
event log / next event ID
schedule queue / next schedule ID
tile, entity, relation state
```

최소 preview 결과:

```text
accepted: bool
reason: String
processed_step_index: int
start_time: int
end_time: int
time_cost: int
speed_tier: FAST | NORMAL | SLOW
calendar_start: Dictionary
calendar_end: Dictionary
timeline: Array[TimelineEntry]
```

최소 `TimelineEntry`:

```text
kind: String
at_time: int
offset: int
actor_id: int
owner_id: int
schedule_id: int
presentation_key: String
certainty: String
event_ids: Array[int]  # preview에서는 항상 빈 배열
```

runtime preview/timeline DTO는 같은 Godot 프로세스 안에서 소비하는 깊은 복사 자료이므로 시간과 ID를 GDScript `int`로 유지한다. 이는 snapshot wire format이 아니다. 나중에 JSON으로 내보낼 때는 snapshot과 같은 canonical decimal-string adapter를 별도로 거쳐야 하며, 현재 `to_dict()`를 장기 저장 포맷으로 간주하지 않는다.

마커 필드는 다음으로 고정한다.

```text
offset = at_time - start_time
action.start / actor.ready: schedule_id=-1, owner_id=-1
system.environment_tick: schedule_id와 owner_id는 예약 row 값
certainty: "CERTAIN"
presentation_key:
  timeline.action_start
  timeline.environment_tick
  timeline.actor_ready
```

preview 타임라인은 최소한 다음을 포함한다.

```text
action.start
구간 안의 system.environment_tick 0..N개
actor.ready
```

UI 문장을 코어에 하드코딩하지 않는다. `presentation_key`만 제공한다.

현재는 인지 시스템이 없으므로 환경 틱은 일반적인 예약 항목으로만 표시한다. 향후 NPC·독을 추가할 때 시야 밖 개체나 감지하지 못한 위험을 preview에 노출하면 안 된다는 원칙을 README와 다음 가이드에 명시한다.

preview는 RNG 결과, 화재 확산 성공, 예상 피해처럼 아직 확정되지 않은 결과를 예언하지 않는다. **언제 어떤 공개 스케줄 종류가 처리되는지**만 알려준다.

preview 및 timeline 반환 컨테이너는 깊은 복사된 DTO여야 한다. 호출자가 배열이나 Dictionary를 바꿔도 세계의 스케줄, 사건, 이후 결과가 변하지 않아야 한다.

## 6. `Simulator.step()` 결과 계약

`consumes_turn`처럼 두 의미가 섞인 이름을 제거하거나 명확히 폐기하고 다음 계약으로 갱신한다.

```text
accepted: bool
consumes_time: bool
reason: String
processed_step_index: int
start_time: int
end_time: int
time_cost: int
speed_tier: String
events: Array[SimEvent]
timeline: Array[TimelineEntry]
root_event_id: int
```

거부 결과:

```text
accepted = false
consumes_time = false
time_cost = 0
start_time == end_time == current world_time
events = []
timeline = []
root_event_id = -1
processed_step_index = -1
speed_tier = ""
```

거부 preview도 `processed_step_index=-1`, `start_time=end_time=current world_time`, 비용 0, 빈 등급·timeline으로 고정한다. `calendar_start`와 `calendar_end`는 현재 시각의 같은 projection이다.

이번 단계의 모든 유효 행동은 양의 비용이므로 결과 불변식은 다음과 같다.

```text
accepted == consumes_time
accepted => end_time - start_time == time_cost > 0
rejected => start_time == end_time && time_cost == 0
```

유효 결과의 `time_cost`, 시간 범위, 속도 등급은 실행 직전 같은 상태에서 얻은 preview와 정확히 일치해야 한다. 실제 타임라인의 예약 마커도 preview와 일치해야 한다.

실제 timeline의 마커에는 그 구간에서 실제 생성된 사건 ID를 안정 순서로 **빠짐없이** 채운다.

- `action.start.event_ids[0] == root_event_id`이며, 이어서 행동 commit이 같은 시작 시각에 만든 점화·아크·즉시 피해 등 모든 파생 사건을 ID 순으로 담는다.
- 각 `system.environment_tick.event_ids`는 그 처리 한 번에서 생긴 사건들이다. 아무 사건도 없으면 빈 배열이다.
- `actor.ready.event_ids`는 이번 단계에서 빈 배열이다.
- preview와 실제 timeline의 `kind`, `at_time`, `offset`, `schedule_id` 순서는 같고 `event_ids`만 실행 후 채워진다.
- `StepResult.events`의 모든 사건 ID와 marker들의 모든 ID는 양방향으로 정확히 일치해야 한다. 중복·누락·이번 step 밖의 가짜 ID가 없어야 하며 각 marker 내부 ID도 증가 순서다. `actor.ready.event_ids`는 반드시 비어 있다.
- timeline은 완전한 상태 재생 자료는 아니지만 사건을 orphan으로 남기지는 않는다.

`StepResult.events`도 authoritative `world.events`의 가변 객체 참조를 그대로 노출하지 않는다. 같은 값의 분리된 `SimEvent` 복사본 또는 immutable DTO를 반환해 UI가 결과 사건을 바꿔도 세계 로그와 snapshot이 변하지 않게 한다.

## 7. 고정 처리 순서

```text
명령 검증
→ 순수 timing/preview 계산
→ processed_step_index = world.step_index + 1로 고정
→ processed_step_index와 현재 world_time에서 행동 사건 및 즉시 효과 commit
→ 즉시 피해 완전 정착
→ (start, end]의 예약 항목을 시간순 처리
   → world_time = due_time
   → kind dispatch
   → 반복 항목 drift 없이 재예약
→ world_time = end_time
→ 정착 불변식 확인
→ step_index += 1
→ 결과 반환
```

예약 항목 여러 개가 같은 시각이면 고정 정렬 순서로 모두 처리한 뒤 다음 시각으로 이동한다.

`world.step_index`는 정착된 플레이어 결정 수다. 따라서 첫 행동의 모든 사건은 `step_index=1`이고, 반환 직전 `world.step_index`도 1이 된다. 진행 중 값을 외부에서 관찰하거나 저장할 수 있게 만들지 않는다.

이를 위해 `WorldState`에 스냅숏으로 저장하지 않는 내부 `active_step_index`(평상시 `-1`) 또는 동등한 명시적 emission context를 둔다.

```text
step 시작 commit 직전: active_step_index = world.step_index + 1
emit_event(): active_step_index >= 0이면 그 값을 사건에 기록
step 정착 직전: world.step_index = active_step_index, active_step_index = -1
```

환경 틱을 포함한 한 `step()`의 모든 사건은 같은 active index를 사용한다. 스냅숏과 `step()` 반환 시 `active_step_index == -1`을 assert한다. 정착 상태에서 테스트/설정용으로 직접 사건을 내보내야 한다면 현재 완료된 `world.step_index`를 사용하되, 공개 게임 진행 경로는 반드시 원자적 `step()`을 통한다.

## 8. 환경 시스템 리팩터링

`EnvironmentSystem.advance_turn()`은 플레이어 턴 개념을 가져서는 안 된다. `process_tick()` 또는 의미가 같은 이름으로 변경하고 예약된 환경 간격 한 번만 처리한다.

현재 `pending_damage`가 시스템 객체에 남을 수 있는 구조도 제거한다.

- 전기 방전은 즉시 행동 효과다.
- BFS로 아크와 피해 요청을 결정론적으로 수집한 뒤 같은 `world_time`에 `DamageSystem`으로 모두 적용한다.
- 호출이 반환될 때 남은 전기 피해 요청이 없어야 한다.
- 화재 피해 요청은 한 환경 틱 내부의 로컬 배열로만 수집하고 틱 종료 전에 적용한다.
- 시스템 필드의 미정착 피해 큐는 스냅숏 밖에 존재해서는 안 된다.

기존 원소 계약은 시간축만 바꾸고 유지한다.

- 물–불 반응은 환경 틱당 한 번
- 직접/확산 점화의 공통 preview/commit 공식
- 2단계 확산 충돌
- 새 확산 및 같은 틱 재점화 불은 다음 환경 틱까지 피해 유예
- 전기 부모 아크 인과관계
- 불·전기 공통 `DamageSystem`

여러 환경 틱이 한 플레이어 행동 구간에 들어오면 위 규칙을 각 틱에 정확히 한 번씩 순차 적용한다.

기존의 “새 확산 불은 다음 `advance_turn()`까지 무피해”를 암묵적인 함수 호출 횟수로 두지 않는다. 타일에 직렬화되는 명시적 `fire_damage_eligible_time`을 둔다.

```text
행동으로 직접 점화: eligible_time = action start_time
환경 틱 T에서 확산 또는 같은 틱 재점화: eligible_time = T + ENVIRONMENT_INTERVAL
소화 또는 소진: eligible_time = -1
```

환경 틱은 `current_due_time >= eligible_time`인 불만 피해 대상으로 삼는다. 따라서 T에서 확산된 불은 T+100 환경 틱부터 피해를 주며, 느린 행동 중 다음 환경 틱이 오면 플레이어의 다음 입력 전에 피해가 발생할 수 있다. 이것이 이번 단계의 의도적인 **세계시간 기반 위험 정책**이다.

sentinel을 피해 가능 시각으로 오인하지 않도록 아래 상태 불변식을 생성·소화·소진·복원 때 모두 검증한다.

```text
fire == 0  <=> fire_damage_eligible_time == -1
fire == 0  <=> fire_source_event_id == -1
fire > 0   => fire_damage_eligible_time >= 0 && fire_source_event_id가 존재
damage 대상 => fire > 0 && eligible_time >= 0 && current_due_time >= eligible_time
```

불이 일부 약화되거나 자연 감소 후 남아 있으면 기존 eligibility를 유지한다. 테스트/bootstrap이 수동으로 불을 만들 때도 유효한 source 사건과 eligibility를 함께 설정해야 한다.

환경 변화량 상수도 호출 횟수의 의미를 숨기지 않도록 `*_PER_ENVIRONMENT_TICK`으로 이름을 바꾼다. 여러 틱을 하나의 큰 계산으로 합치지 않는다. 특히 확산 RNG는 각 due tick에서 정확히 한 번씩 순서대로 소비한다.

## 9. 사건 모델

`SimEvent.turn`을 다음으로 대체한다.

```text
step_index: int
world_time: int
```

첫 행동에서 행동 사건과 그 행동 구간의 예약 사건은 같은 `step_index`를 가질 수 있지만 서로 다른 `world_time`을 가진다.

예:

```text
step_index=1 world_time=80   action.discharge
step_index=1 world_time=80   environment.electric_arc
step_index=1 world_time=100  environment.fire_burned_out
step_index=1 world_time=200  environment.fire_spread
```

`describe()`는 두 값을 모두 읽을 수 있게 표시한다. 사건 복원 검증에 다음을 추가한다.

- 사건 배열에서 `step_index`와 `world_time`이 **각각 독립적으로** 비감소 순서. `step_index`가 증가했다는 이유로 `world_time` 역행을 허용하지 않는다.
- 같은 `(step_index, world_time)` 안에서는 ID 순서이며, 전체 사건 ID는 기존처럼 연속 증가
- `event.step_index <= world.step_index`
- `event.world_time <= world.world_time`
- `cause.id < effect.id`
- 파생 사건의 `world_time >= cause.world_time`
- 파생 사건의 `instigator_id == cause.instigator_id`
- 루트 사건은 `cause_id == -1`이며 `instigator_id == actor_id`
- 타일의 불·젖음 source event는 존재하고 그 사건 시각이 현재 `world_time`보다 늦지 않음
- 같은 시각의 사건은 ID 순서

## 10. 달력 projection

작은 순수 `WorldClock` 모델을 둔다. 별도 달력 누적값을 저장하지 않고 `world_time`과 고정 규칙에서 파생한다.

```text
100 time units = 추상 1분
24시간 = 1일
15일 = 1계절
4계절 = 1년
```

최소 반환값:

```text
absolute_minute
minute_of_hour
hour_of_day
day_index
day_of_season
season_index
year_index
period_id: DAWN | DAY | DUSK | NIGHT
```

모든 index/day 필드는 내부에서 0 기반이다. UI가 사람에게 `1일`, `1년`으로 보일 때만 1을 더한다.

권장 시간대:

```text
DAWN   05:00..06:59
DAY    07:00..17:59
DUSK   18:00..19:59
NIGHT  20:00..04:59
```

이번 단계에서는 낮밤 사건이나 효과를 발생시키지 않는다. projection과 경계 테스트만 만든다.

## 11. 스냅숏과 버전

시간 의미가 바뀌므로 아래를 갱신한다.

```text
SNAPSHOT_VERSION = 2
RULESET_VERSION = phase1-time-v1
```

새 스냅숏 필수 상태:

```text
step_index
world_time
calendar_ruleset_id
next_schedule_id
scheduled_entries
fire_damage_eligible_time
```

snapshot에서 시간·ID의 본체와 **그 모든 참조**는 기존 RNG 계약처럼 signed 64-bit GDScript `int`의 canonical 10진 문자열을 사용한다.

최소 대상:

```text
step_index, world_time, due_time, repeat_interval, fire_damage_eligible_time
entity_id, next_entity_id와 actor/target/instigator/owner/observer/subject 참조
event_id, next_event_id, cause_id, tile source IDs, relation processed source IDs
schedule_id, next_schedule_id, schedule source_event_id
```

문법:

```text
0 또는 양수: "0" | [1-9][0-9]*
양수 ID: [1-9][0-9]*
sentinel 허용 참조: "-1" | [1-9][0-9]*
```

`+1`, `01`, `-0`, 공백, 지수, 소수, int64 범위 초과, JSON 숫자 값을 조용히 받아 절삭하지 않는다. 위치·크기·우선순위·피해량처럼 명시적으로 작은 값은 JSON 정수를 쓸 수 있지만 복원 전에 정수 타입과 허용 범위를 검사한다. Godot JSON parser의 정확한 `100.0`은 허용할 수 있으나 `100.5`나 문자열 `"100"`을 정수로 coercion하지 않는다.

사건 `data`와 예약 payload의 정수는 이번 단계에서 JSON safe integer 범위 `[-(2^53-1), 2^53-1]`로 제한한다. ID·시간을 metadata에 넣을 때는 숫자가 아니라 명시적 canonical string 필드를 사용한다. 이렇게 해야 큰 임의 정수가 JSON 왕복 중 조용히 반올림되지 않는다.

모든 시간·ID 덧셈은 wraparound 전에 검사하는 `checked_add` 또는 동등한 방식이어야 한다.

```text
step_index + 1
world_time + time_cost
previous_due + repeat_interval
environment_tick_time + ENVIRONMENT_INTERVAL
next_entity/event/schedule_id + 1
```

`MAX_WORLD_TIME = INT64_MAX - ENVIRONMENT_INTERVAL`로 두고 순수 계획의 `end_time`이 이를 넘으면 `time_overflow`로 전체 무변경 거부한다. 이벤트 수는 맵·개체 수·계획된 환경 occurrence에서 보수적인 최대치를 commit 전에 계산해 `_next_event_id` headroom이 부족하면 역시 무변경 거부한다. 이 보수적 최대치 계산 자체도 checked/saturating arithmetic을 사용한다. 계획 뒤 예상 밖 ID 고갈은 구현 결함으로 fail-fast 한다.

v1의 `turn`은 새 의미를 정확히 복원할 수 없으므로 조용히 추정해 읽지 않는다. 이번 프로토타입에서는 v1을 명시적으로 거부한다. 마이그레이션이 필요하다면 별도 명시적 migrator와 손실 정책을 만들어야 하며 `from_snapshot()` 내부에서 암묵적으로 바꾸지 않는다.

외부 스냅숏 거부를 `assert`에 의존하지 않는다. Godot의 assert는 빌드 설정에 따라 제거될 수 있고, headless 실행에서는 script error를 기록한 뒤 호출자가 부분 복원 객체를 받을 수도 있다.

```text
WorldState.snapshot_restore_error(data) -> String
LivingWorldSimulator.from_snapshot(data) -> valid simulator | null
```

- `snapshot_restore_error()`는 header, container shape, 모든 scalar wire type/range, ID 참조, 사건 시간/인과, 타일 sentinel, 관계, scheduler cadence를 **부작용 없이 전부** 검증하고 성공 시 빈 문자열을 반환한다.
- `from_snapshot()`은 위 오류가 하나라도 있으면 `null`을 반환하며 세계·시스템 객체를 호출자에게 절대 노출하지 않는다. 상세 이유가 필요하면 먼저 error API를 호출한다.
- 잘못된 width/height로 객체나 거대한 배열을 만들기 전에 raw container와 범위를 검증한다.
- semantic validation도 오류 문자열/명시적 Result 경로를 사용한다. `assert`는 이미 검증된 내부 상태의 개발용 보조 불변식에만 쓴다.
- Debug/Release 양쪽에서 거부 의미가 같아야 한다.

### 11.1 Producer/restore 도메인 일치

코어가 정상적으로 받아들여 authoritative state에 반영한 값은 반드시 같은 v2 ruleset으로 저장·복원 가능해야 한다.

```text
accepted producer mutation
→ snapshot() != null
→ snapshot_restore_error(snapshot) == ""
→ from_snapshot(snapshot) != null
→ restored.snapshot() == snapshot
```

- dimension, 총 tile 수, entity health, event magnitude/position/reference, tile scalar, schedule scalar 제한은 생성·bootstrap API와 restore가 **같은 validator/상수**를 사용한다.
- 외부/동적 크기는 `LivingWorldSimulator.create(...) -> simulator | null` 또는 동등한 checked factory를 제공한다. raw `.new()`가 내부 prevalidated 경로라면 문서에 명시하고 같은 제한을 assert 전에 검사한다.
- `add_entity()`는 invalid max health/position/tag를 ID 소비 전에 `null`로 거부한다.
- `emit_event()`는 invalid magnitude/position/entity reference/data를 event ID 소비 전에 `null`로 거부한다.
- `schedule_entry()`는 invalid due/repeat/priority/kind/payload를 schedule ID 소비 전에 `-1`로 거부한다.
- public `schedule_entry()`가 scalar상 유효해도 이번 ruleset의 kind별 cardinality/cadence를 깨뜨리면 schedule ID 소비 전에 `-1`로 거부한다. 특히 두 번째 `system.environment_tick`을 추가해 `snapshot()==null`인 자기모순 상태를 만들 수 없어야 한다. 동일 시각 정렬·budget 같은 스케줄러 단위 테스트에 임의 row가 필요하면 명시적인 test-only/unsafe fixture 경로를 사용하며 production API 계약과 섞지 않는다.
- 타일 public bootstrap 필드를 직접 잘못 설정하는 것까지 완전히 막지 못한다면, `world_state_error()` 또는 동등 검증을 거친 `snapshot()`이 invalid world에서 `null`을 반환해 복원 불가능한 save를 만들지 않게 한다.
- 크기 cap을 유지한다면 생성과 복원 양쪽에 동일 적용하고 README에 수치를 기록한다. cap을 제거한다면 곱 overflow와 raw tile-array shape를 객체 할당 전에 검증한다.

종족 관계 snapshot row의 `(observer_species_id, subject_species_id)`도 유일해야 한다. 같은 방향 pair가 두 번 나오면 마지막 row로 조용히 덮지 말고 raw validation에서 거부한다. 두 ID를 구분 문자로 이어 붙인 문자열을 key로 쓰지 않는다. ID 자체에 그 문자가 들어오면 서로 다른 pair가 충돌할 수 있으므로 nested map이나 구조적 pair key로 비교한다.

스냅숏 정렬과 검증:

- 예약 항목을 정렬된 canonical 순서로 저장
- 중복 `schedule_id` 거부
- 모든 반복 간격과 due time 검증
- `due_time > world_time`인 정착 상태만 허용
- `next_schedule_id` 충돌 방지
- JSON 왕복 후 전체 스냅숏 동등성
- 변조 스냅숏은 script error만 찍고 객체를 반환해서는 안 되며 checked restore가 `null`을 반환

이번 ruleset의 예약 kind별 검증:

- allowlist는 `system.environment_tick` 하나
- 해당 row가 정확히 하나 존재
- `priority=100`, `repeat_interval=100`, `owner_id=-1`, `source_event_id=-1`, 빈 payload
- `due_time`은 현재 `world_time`보다 큰 다음 100 배수와 정확히 일치
- 새 세계에서는 schedule ID 1, next ID 2로 시작
- 알 수 없는 kind나 변조된 cadence는 step 도중이 아니라 복원 시 거부

## 12. 필수 회귀 테스트

기존 29개 테스트를 삭제해 통과시키지 말고 새 시간 의미에 맞게 갱신한다.

### 명령과 시간

1. 모든 고정 명령과 `wait_for()`의 비용 및 FAST/NORMAL/SLOW 등급이 정확함
2. 유효 명령 하나당 `step_index`는 정확히 1 증가
3. 서로 다른 비용만큼 `world_time`이 정확히 증가
4. 거부 명령이 step/time/RNG/사건/스케줄/환경을 전혀 변경하지 않음
5. 행동 사건은 시작 시각, `actor.ready`는 종료 시각
6. `wait_for(0)`, 음수, 최대 초과, 비정수 복원은 전체 무변경 거부
7. 유효하지만 비가연성 IGNITE 실패는 SLOW 비용 120을 소비하고 실패 사건을 남김
8. command JSON journal에서 큰 actor ID가 정확히 왕복하고 fractional position/type/power/duration은 null decode 및 step 전체 무변경 거부

### preview

9. preview 호출 전후 전체 스냅숏이 동일함
10. preview가 RNG와 다음 사건·예약 ID를 소비하지 않음
11. preview 비용·등급·시간 범위가 실제 step 결과와 동일함
12. `action.start → 예약 항목들 → actor.ready` 순서가 정확함
13. 잘못된 명령 preview는 빈 타임라인과 비용 0
14. preview 뒤 다른 step을 실행한 후 원래 명령을 step하면 낡은 계획이 아닌 현재 시각에서 재계산됨
15. 반환된 preview/timeline을 외부에서 변형해도 스냅숏과 다음 실행이 동일함
16. 첫 행동의 root·즉시 효과·환경 사건이 모두 `processed_step_index=1`이고 정착 뒤 active context가 남지 않음
17. 반환된 `StepResult.events` 객체를 변형해도 authoritative world event와 snapshot이 동일함

### 예약 경계와 반복

18. `t=0`에서 빠른 물 행동 80은 환경 틱을 처리하지 않음
19. 이후 표준 WAIT로 `t=100` 환경 틱을 정확히 한 번 통과
20. `t=80`에서 느린 DISCHARGE 160은 `t=100`, `t=200` 틱을 정확히 두 번 처리
21. `wait_for(250)`는 step 1회, 시간 250 증가, 환경 틱 100·200을 처리
22. 종료 시각과 같은 예약 항목은 ready 전에 포함
23. 동일 시각 항목은 `(priority, schedule_id)` 순서
24. 반복 due time이 `100, 200, 300...`으로 drift 없음
25. 한 행동에 여러 환경 틱이 있어도 step은 1만 증가
26. `wait_for(250)`과 합계 250인 분할 WAIT들의 환경 물리 상태·RNG·다음 due time이 같음. 행동/step/event provenance 차이는 비교 대상에서 제외
27. preview가 동일 schedule ID로 100·200 occurrence를 펼치며 next schedule ID를 소비하지 않음
28. 모든 result event ID가 실제 timeline 전체에서 정확히 한 번 나타나고 즉시 파생 사건은 action.start에 귀속

### 원소 회귀

29. 전기 아크·피해가 행동 시작 시각에 즉시 완결되고 미정착 큐가 없음
30. 물–불 반응이 환경 틱마다 한 번만 계산됨
31. 한 행동에 환경 틱 두 번이면 불·젖음이 정확히 두 단계 진행
32. 직접 점화 불은 첫 도래 환경 틱부터 피해 가능
33. T에 생긴 확산 불과 같은 틱 재점화 불은 T에는 무피해, T+100부터 피해 가능
34. 느린 행동 구간 안에 T+100이 오면 새 확산 불 피해가 다음 입력 전에 발생
35. 확산 직후 저장·복원해도 eligibility, 다음 피해와 cause가 동일
36. `fire>0/eligible=-1`, `fire=0/eligible>=0`, source 불일치 스냅숏을 거부
37. 직접 점화, 확산, 전기 인과 사슬의 시간은 원인보다 이르지 않음
38. 기존 관계 공식과 고블린 구조 사례가 변하지 않음

### 저장·결정론

39. 예약 큐 포함 메모리 스냅숏 재개가 연속 실행과 동일
40. 큰 64비트 시간과 모든 ID·참조의 canonical string JSON 왕복이 정확함
41. 소수, 숫자형 64비트 필드, 작은 정수 필드의 비정수, 음수 금지 시간, 범위 초과를 절삭 없이 거부
42. `INT64_MAX` 근처 end/repeat/eligibility/next-ID overflow가 commit 전 무변경 거부됨
43. JSON 중간 저장 후 서로 다른 비용의 명령열 최종 상태·RNG·사건·스케줄 동일
44. 환경 cadence 직전 저장·복원 후 due tick을 중복·누락 없이 한 번만 처리
45. 알 수 없는 kind, 누락·중복 environment row, 변조 interval/priority/due를 복원 시 거부
46. 같은 시드·명령열의 타임라인과 전체 스냅숏 동일
47. v1 스냅숏을 조용히 읽지 않고 명시적으로 거부
48. 사건 step/time 각각의 비감소, cause time, instigator 상속, 타일 source time 검증. `step1@100 → step2@0` 변조도 거부
49. 혼합 비용으로 10,000 time unit 이상 실행한 두 시뮬레이터의 전체 스냅숏과 사건 해시가 동일
50. fire/source/eligibility 불일치 등 모든 semantic 변조에서 error API가 이유를 반환하고 `from_snapshot()`은 script error 의존 없이 `null` 반환
51. 최대 허용 dimension/health/magnitude/tile scalar 경계에서 producer와 restore 도메인이 같고, 거부된 mutation은 ID·상태를 소비하지 않음
52. 코어가 생성한 모든 valid snapshot은 checked restore와 exact round-trip을 통과하고 invalid bootstrap state의 snapshot은 `null`. 추가 environment row처럼 ruleset cardinality를 깨는 public schedule 요청도 ID 소비 전 거부
53. 중복 species relation 방향 pair를 조용히 덮지 않고 명시적으로 거부. ID에 구분 문자가 포함된 서로 다른 두 pair는 중복으로 오인하지 않고 각각 정확히 왕복

### 달력

54. 100 time unit 경계에서 추상 분이 정확히 증가
55. 05:00/07:00/18:00/20:00의 시간대 경계
56. 0 기반 15일 계절, 60일 연도 경계

## 13. 데모와 문서

신규 `examples/time_timeline_demo.gd`를 추가한다.

최소 출력 시나리오:

```text
@0 POUR_WATER preview: FAST, cost 80
timeline: action@0 → ready@80

@80 DISCHARGE preview: SLOW, cost 160
timeline: action@80 → environment@100 → environment@200 → ready@240
```

preview 직후 실제 step을 실행해 계획된 시간 마커와 실제 마커가 일치하는 것도 출력한다.

README를 다음 기준으로 갱신한다.

- `step_index`, `world_time`, `event_id`의 차이
- 행동은 시작 시 commit, 종료까지 예약 처리
- 행동 비용과 속도 등급
- 달력은 world time의 projection
- preview는 스케줄만 알리고 확률 결과나 감지 못한 정보를 예언하지 않음
- 실제 UI는 아직 없음

`docs/NEXT_DEVELOPMENT_GUIDE.ko.md`의 다음 순서는 아래로 갱신한다.

```text
시간 코어·타임라인
→ TerrainRegistry·MOVE
→ ExposureSample·종족 affinity
→ 범용 안전 타일 선택 AI
→ 불·물·전기 exposure 연결
→ 독·DOT
→ 인지·관계·기억
→ 동료 1명에서 최대 3명
```

## 14. 비목표와 과설계 방지선

- 실제 UI, 아이콘, 애니메이션, 현지화 문장
- MOVE, 길찾기, NPC AI, 동료 스케줄
- 독, 출혈, 욕구, 낮밤 효과
- 실제 시계·프레임 시간과 시뮬레이션 연결
- 멀티스레딩, 비동기, Godot Timer/signal
- 범용 이벤트 DSL 또는 ECS
- handler registry, Callable 저장, 취소 토큰, dependency graph
- preview용 별도 복제 스케줄러
- 감지하지 못한 위험의 예측
- 확률적 결과를 preview에서 미리 RNG 소비해 보여주기
- 긴 휴식·여행의 청크 축약
- 행동 완료 예약·캐스팅 취소·플레이어 입력을 위한 긴 행동 중단
- v1 스냅숏의 암묵적 추정 마이그레이션

## 15. 실행과 최종 보고

Godot 사용자 경로는 `/tmp` 아래 XDG 경로를 사용한다.

```bash
XDG_DATA_HOME=/tmp/living-world-sim-time-data \
XDG_CONFIG_HOME=/tmp/living-world-sim-time-config \
XDG_CACHE_HOME=/tmp/living-world-sim-time-cache \
GODOT_SILENCE_ROOT_WARNING=1 \
godot --headless --path /mnt/d/STARTU/living-world-sim \
  --script res://tests/run_tests.gd
```

최종 보고에 포함할 것:

1. 변경·신규 파일
2. 실제 시간 비용과 동일 시각 정렬 규칙
3. step 처리 순서
4. preview와 실제 timeline 계약
5. 추가·갱신한 테스트 목록과 총 통과 수
6. 기존·신규 데모 결과
7. JSON 중간 저장 장기 결정론 검증 결과
8. 남은 위험과 MOVE/Hazard 연동 전 진입 조건
