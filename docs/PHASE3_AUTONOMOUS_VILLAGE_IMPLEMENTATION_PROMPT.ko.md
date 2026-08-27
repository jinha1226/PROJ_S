# 보류된 설계 초안 — 10명 NPC 자율 마을

> 상태: 현재 Phase 3 구현 기준이 아니다. 성격과 위협 반응을 먼저 검증하기 위해 `PHASE3_DUNGEON_PERSONALITY_LAB_IMPLEMENTATION_PROMPT.ko.md`로 우선순위를 변경했다. 이 문서는 이후 마을 simulation 단계의 backlog로만 보존한다. 재개할 때는 기존 후보 점수 코드를 그대로 구현하지 말고 `PERSONALITY_BEHAVIOR_ARCHITECTURE.ko.md`의 계층형 Utility·Affordance·실행 분리 계약으로 다시 정리한다.

## 0. 작업 목적

현재의 결정론적 시간·지형·MOVE·Exposure·종족 관계 기반 위에, 세로 화면에서 바로 관찰할 수 있는 **10명 NPC 자율 마을 vertical slice**를 구현한다.

이번 단계의 성공은 NPC가 무작위로 배회하는 것이 아니다. 다음 인과가 화면과 저장 데이터에서 확인돼야 한다.

```text
절대 세계시간과 일과
+ 현재 욕구
+ 종족 prior와 개인 familiarity
+ 현재 위치·점유·경로
→ 후보 의도와 탈락 이유
→ 결정된 행동
→ 이동·활동·대화 사건
→ 욕구·관계·기억의 변화
```

같은 seed와 같은 외부 WAIT journal이면 중간 저장·복원 여부, UI 재생 속도와 무관하게 최종 snapshot과 event sequence가 정확히 같아야 한다.

## 1. 이번 단계에서 고정할 범위

반드시 구현한다.

- 24×24 개발용 마을 fixture와 고정된 NPC 10명
- NPC용 1분 heartbeat와 batch 의사결정
- 8방향 한 칸 MOVE와 결정론적 weighted pathfinding
- `hunger`, `fatigue`, `social_need` 세 욕구
- 집·직장·광장·여관을 사용하는 시간대별 routine
- `MOVE`, `WORK`, `EAT`, `REST`, `SOCIALIZE`, `IDLE` 활동
- 방향성 familiarity, 대화 기억, 종족 prior가 반영되는 사회 대상 선택
- 15×15 `DEBUG OMNI` 관찰 화면
- NPC roster, 선택·추적, 의도/욕구/관계/기억 inspector
- 일시정지, +1분, +10분, +1시간, 자동 관찰
- snapshot v4, playtest session v2, journal replay
- 결정론·저장복원·충돌·반응형 UI 테스트

이번 단계에서는 구현하지 않는다.

- 플레이어 FOV와 hidden-information UI
- 미니맵
- 먼 타일 두 번 터치 플레이어 auto-walk
- NPC별 `actor.ready` 동적 예약
- 완전한 동시 이동, 자리 교환, 이동 chain
- 전투, 경제, 재고, 제작, 번식, 소문, 평판
- 몬스터 포식·영역·무리 생태
- 범용 GOAP, behavior tree, ECS, 비동기 코어 Timer

이 비목표들은 삭제가 아니라 Phase 4 이후 backlog다. 특히 FOV·미니맵·플레이어 auto-walk 요구사항을 문서에서 유지한다.

## 2. 절대 지켜야 할 기존 계약

- `step_index`는 외부에서 accepted 된 결정 수다. NPC heartbeat 내부 행동은 `step_index`를 추가로 올리지 않는다.
- `world_time`은 행동 비용만큼 증가하고, 예약은 `(start, end]`에서 처리된다.
- 플레이어 MOVE는 시작 시 commit된다.
- `preview()`는 상태, RNG, ID를 바꾸지 않는다.
- 거부된 외부 command는 world, schedule, event, journal을 전혀 바꾸지 않는다.
- 환경 cadence는 절대시간 100 배수에서 drift 없이 유지한다.
- UI는 `PlaytestSession`의 detached DTO만 사용하며 `sim.world`를 직접 읽지 않는다.
- Dictionary iteration 순서에 결과를 의존하지 않는다. entity, relation, memory, 후보 목록은 명시적으로 정렬한다.
- core에서 `Timer`, frame delta, wall clock을 읽지 않는다.
- 확률을 꼭 쓰지 않아도 되는 결정에는 RNG를 쓰지 않는다. 같은 입력의 동률은 고정 규칙으로 푼다.

## 3. 시간 모델 — 두 개의 canonical cadence

### 3.1 예약

정착된 world에는 아래 두 repeating schedule만 존재한다.

```text
system.environment_tick  due=다음 100 경계  priority=100  repeat=100
system.npc_tick          due=다음 100 경계  priority=200  repeat=100
```

같은 시각에는 환경 틱이 먼저, NPC 틱이 다음이다. NPC는 그 시각에 갱신된 불·물·전기 상태를 본다.

`system.npc_tick` handler는 새 schedule을 만들지 않는다. 현재의 “schedule handler가 logical schedule ID를 생성하지 않는다” 계약을 유지한다. NPC별 행동 시간은 schedule이 아니라 `AgentState.busy_until`로 표현한다.

### 3.2 NPC tick 순서

매 NPC tick은 아래 단계를 정확히 따른다.

```text
1. 살아 있는 autonomous NPC의 욕구를 현재 world_time까지 모두 갱신
2. 위치·점유·AgentState·관계의 pre-action projection을 고정
3. entity_id 오름차순으로 후보를 만들되 모두 같은 projection을 읽음
4. 각 NPC의 의도와 한 번의 원자 행동을 선택
5. 같은 목적지 충돌을 일괄 해결
6. entity_id 오름차순으로 이미 해결된 결과만 commit
7. 사건·기억·familiarity와 busy_until 갱신
```

순차 commit은 허용하지만 순차 의사결정은 금지한다. NPC 1의 이동 결과를 보고 NPC 2가 후보를 바꾸면 안 된다.

### 3.3 행동 시간

- `busy_until > current_world_time`인 NPC는 욕구만 갱신하고 새 행동을 정하지 않는다.
- MOVE 성공 시 `busy_until = now + destination terrain move_time_cost`.
- WORK/EAT/REST/SOCIALIZE/IDLE 비용은 별도 versioned activity timing table에서 정수로 관리한다.
- 첫 slice에서는 NPC가 한 heartbeat에 최대 한 행동만 commit한다.
- 외부 진행은 `WAIT 100`, `WAIT 1000`, `WAIT 6000`으로 각각 1분, 10분, 1시간을 만든다.
- NPC 결정은 외부 command journal에 중복 기록하지 않는다. accepted WAIT/MOVE 등 외부 명령만 journal에 남고, NPC 사건은 snapshot+ruleset에서 결정론적으로 재생되는 결과다.

## 4. 버전과 snapshot

아래 버전을 올린다.

```text
SNAPSHOT_VERSION = 4
RULESET_VERSION = "phase3-autonomous-village-v1"
SESSION_FORMAT_VERSION = 2
SAVE_PATH = "user://living_world_playtest_v2.json"
```

snapshot v3을 v4로 암묵 변환하지 않는다. 개발 단계에서는 명시적으로 거부한다.

snapshot v4에 최소한 다음을 보존한다.

- 두 canonical schedule과 `next_schedule_id`
- `agent_states`, `next_memory_id`
- NPC별 bounded memory 목록
- `busy_until`, 현재 intent, intent 시작 시각
- 마지막 결정 이유와 bounded 후보 진단
- familiarity와 마지막 사회 접촉 시각
- 기존 species relation, personal relation, 사건 인과

경로 전체, FOV 결과, exposure 점수, effective relation, UI camera·선택·pause·속도는 파생 상태이므로 저장하지 않는다.

wire의 모든 64비트 ID·시간은 기존 canonical decimal string 규칙을 따른다. snapshot 검증은 알 수 없는 activity, profile, memory kind, schedule kind와 잘못된 entity/event 참조를 거부해야 한다.

## 5. 데이터 모델

### 5.1 `AgentProfileRegistry`

버전 고정 정적 데이터다.

```text
profile_id
role_id
role_glyph
home_position
work_positions
meal_positions
social_positions
patrol_points
routine_blocks
need_rates_per_minute
need_thresholds
```

routine block은 `start_minute_of_day`, `end_minute_of_day`, `activity`, `target_zone_id`를 가진다. 자정을 넘는 block도 명시적으로 처리한다.

### 5.2 `AgentState`

authoritative snapshot 상태다.

```text
entity_id
profile_id
hunger                 0..1000
fatigue                0..1000
social_need            0..1000
last_need_update_time
busy_until
current_activity
intent_kind
intent_target_entity_id
intent_target_position
intent_started_time
route_failures
last_decision_time
last_decision_reason
last_decision_score
blocked_reason
candidate_diagnostics  최대 8개
```

욕구 증가는 `world_time` 차이를 abstract minute로 바꾼 정수 연산만 사용한다. 매 tick truncation으로 값이 영원히 사라지지 않도록 rate를 분당 정수로 정의하거나 remainder를 명시적으로 저장한다.

### 5.3 `NpcMemory`

```text
memory_id
observer_id
source_event_id
kind
observed_time
subject_id
target_id
position
salience              0..100
confidence            0..100
firsthand
```

- NPC당 최대 32개.
- 중복 key는 최소 `(observer_id, source_event_id, kind)`다.
- 넘치면 `salience 오름차순 → observed_time 오름차순 → memory_id 오름차순`으로 제거한다.
- 이번 단계에서는 대화 참가자만 대화 기억을 얻는다. 목격·소문 전파는 FOV 이후다.
- 기억은 같은 상대와 매 분 반복 대화하지 않게 하는 실제 cooldown 입력으로 사용한다.

### 5.4 관계 확장

기존 방향성 `PersonalRelation`에 다음을 추가한다.

```text
familiarity            0..100
last_social_time       -1 또는 world_time
```

일반 대화를 `record_aid()`로 처리하지 않는다.

- 대화 성공 시 A→B와 B→A familiarity를 각각 +1한다.
- 같은 방향 관계의 familiarity 증가는 60 abstract minute cooldown을 둔다.
- 일반 대화는 species prior, trust, hostility를 뒤집지 않는다.
- 사회 대상 선택과 inspector에는 `species base`, `personal delta/familiarity`, `effective`를 분리 표시한다.

## 6. 10명 고정 roster

동일 seed에서 ID·초기 위치·profile이 항상 같다. seed는 이후 미세한 deterministic variation에만 쓸 수 있으며 roster 순서를 바꾸면 안 된다.

| ID 순서 | 이름 | 종족 | 역할 | 대표 일과 |
|---:|---|---|---|---|
| 1 | Doran | human | 북쪽 농부 | 집 → 북쪽 밭 → 식사 → 밭 → 집 |
| 2 | Sera | human | 남쪽 농부 | 집 → 남쪽 밭 → 식사 → 밭 → 집 |
| 3 | Borin | dwarf | 대장장이 | 집 → 대장간 → 광장 → 대장간 |
| 4 | Hana | human | 치료사 | 집 → 진료소 → 약초밭 → 진료소 |
| 5 | Tae | human | 상인 | 창고 → 시장 → 여관 → 시장 |
| 6 | Nari | human | 제빵사 | 집 → 빵집 → 여관 → 빵집 |
| 7 | Mira | human | 여관주인 | 여관 업무 → 저녁 사교 → 취침 |
| 8 | Rook | human | 서쪽 경비 | 서문 → 광장 → 북문 순찰 |
| 9 | Sena | human | 동쪽 경비 | 동문 → 광장 → 남문 순찰 |
| 10 | Ido | goblin | 외부 운반인 | 창고·시장·대장간·진료소 순환 |

모두 `village` faction으로 두지만 이번 단계에서 faction bonus는 0이다. `Ido`는 종족 prior가 같은 faction 표식보다 우선하는지 관찰하기 위한 fixture다. 한두 번 대화했다고 인간↔고블린 관계가 곧바로 우호로 바뀌면 실패다.

초기 species 관계표도 scenario bootstrap에서 방향별로 고정한다. 인간↔고블린은 WARY 또는 높은 거리감이 유지되되, 자동 전투가 없는 이번 slice에서 마을 생활 자체가 불가능할 정도의 즉시 적대는 피한다.

## 7. 의사결정 규칙

GOAP 없이 고정 우선순위와 정수 점수를 쓴다.

```text
1. 즉시 위험 회피            priority 500
2. critical fatigue          priority 400
3. critical hunger           priority 390
4. 현재 routine              priority 300
5. social_need               priority 200
6. 귀가/idle                 priority 100
```

이번 Phase 3 마을에는 임의 확률 행동을 넣지 않는다. 후보 동점은 다음 순서로 푼다.

```text
priority 내림차순
→ score 내림차순
→ 예상 terrain path cost 오름차순
→ target y, x 오름차순
→ target entity_id 오름차순
→ actor entity_id 오름차순
```

현재 intent가 여전히 유효하면 작은 hysteresis bonus를 줘서 매 분 목표를 바꾸는 떨림을 막는다. critical need와 위험은 routine을 덮는다.

사회 대상은 다음 필터와 순서를 사용한다.

```text
살아 있음 / 자기 자신 아님
→ 상호작용 거리 안 또는 접근 가능한 대상
→ effective hostility가 금지 임계치 미만
→ social cooldown 아님
→ disposition·familiarity
→ 거리
→ entity_id
```

선택하지 않은 후보도 `candidate_diagnostics`에 score와 정확한 rejection reason을 남긴다.

## 8. 8방향 MOVE와 pathfinding

### 8.1 한 칸 MOVE

인접 판정은 아래와 같다.

```text
delta != (0, 0)
max(abs(delta.x), abs(delta.y)) == 1
```

대각선은 두 orthogonal flank가 모두 지형상 통과 가능하고 살아 있는 blocking entity가 없어야 한다. 두 벽 사이의 코너컷, 점유 개체 사이 비집고 가기를 금지한다.

대각 한 칸 비용은 목적지 terrain의 기존 `move_time_cost` 그대로다. √2 보정은 이번 ruleset에 넣지 않는다.

`WorldState.cardinal_neighbors()`는 불·전기 전파 전용 4방향으로 유지한다. 8방향 이동 순서는 별도 상수/API로 만든다.

### 8.2 순수 경로 질의

새 pathfinder는 world, RNG, event, ID를 전혀 바꾸지 않는 pure query다.

- weighted path cost = 지나간 destination terrain cost 합
- 고정 8방향 neighbor order
- 우선순위 key 최소 `(total_cost, steps, y, x, insertion_sequence)`
- Dictionary iteration 금지
- occupied goal은 실패
- route 전체를 AgentState에 저장하지 않고 매 행동 직전에 재계산
- NPC는 next hop 한 칸만 공통 movement assessment로 다시 검증하고 commit
- unreachable이면 순간이동하지 않고 `path_unreachable` 또는 `occupied` WAIT 진단을 남김

core terrain path cost와 종족 위험 선호를 섞지 않는다. 불·물·전기·독 affinity를 사용한 장거리 safe navigation은 후속 단계다. 단, 현재 칸/next hop의 즉시 치명 위험은 최상위 위험 회피 후보로 거부할 수 있다.

### 8.3 batch 충돌

- 동일 빈 목적지를 여러 NPC가 고르면 `intent priority 내림차순 → actor_id 오름차순`으로 한 명만 성공한다.
- 나머지는 `destination_conflict` WAIT가 된다.
- pre-action 상태에서 점유된 칸으로의 이동은 점유자가 이동 예정이어도 금지한다.
- 자리 교환과 이동 chain은 이번 단계에서 금지한다.
- commit 직전 validation 실패는 assertion으로 숨기지 말고 결정론적 `commit_revalidation_failed` 진단과 WAIT 사건으로 정착시킨다.

## 9. 마을 fixture

- 크기 24×24. 최종 월드 크기 결정이 아니라 개발 fixture다.
- 외곽 벽, 2개 문, 중앙 광장, 여관, 빵집, 대장간, 진료소, 창고, 북/남쪽 밭, 10개 취침 지점을 둔다.
- 모든 routine target은 named zone registry를 통해 얻는다.
- 한 칸 통로를 남발하지 말고 NPC 10명이 막힘 없이 교차할 수 있게 주요 길은 폭 2 이상으로 만든다.
- 기본 시작 시각은 D1 06:50으로 하여 10분 안에 출근 전환이 보이게 한다.
- clock 변경은 bootstrap 전용 API로만 허용하고, 두 cadence를 다음 100 경계에 정확히 재정렬한다.
- 초기 욕구 하나를 의도적으로 높여 routine을 중단하고 EAT/REST로 전환하는 사례가 첫 20분에 보이게 한다.

## 10. Session facade

UI가 사용할 detached API를 최소 다음으로 만든다.

```gdscript
observe_window(camera_center: Vector2i, radius: int = 7) -> Dictionary
village_roster() -> Array[Dictionary]
inspect_entity(entity_id: int) -> Dictionary
advance_minutes(minutes: int) -> Dictionary
set_follow_entity(entity_id: int) -> bool
```

`observe_window()`:

```text
schema_version
mode = "debug_omniscient"
sampled_step_index / sampled_world_time
requested_center / resolved_center / origin / diameter
cells
roster summaries
```

`inspect_entity()`:

```text
entity: id, name, role, species, faction, position, hp, alive
activity: state, busy_until, current intent/target/score/reason
needs: value, urgency, trend
routine: current block and next block
relationships: species base, personal, effective, direction
memories: bounded newest/important rows
last_decision: selected candidate and ranked alternatives/rejections
```

모든 반환값은 깊은 복사다. DTO를 호출자가 변조해도 snapshot이 변하면 안 된다.

`advance_minutes()`는 허용값 1, 10, 60만 받고 대응하는 하나의 external WAIT command를 제출한다. accepted command만 session journal에 남긴다.

## 11. 세로 UI

기존 scene 구조를 재사용하되 관찰 모드로 재편한다.

- 기본 grid: 15×15, `GRID_RADIUS = 7`
- 450×800에서 셀 약 28px, 360×640에서 최소 20px
- 기본 camera: 중앙 광장
- NPC는 entity ID 기반으로 선택한다. NPC가 이동해도 selection이 같은 ID를 추적한다.
- 빈 칸을 누르면 terrain/exposure inspector로 전환한다.
- roster에서 NPC를 누르면 camera recenter 및 follow 가능하다.
- grid glyph는 1..9, 0으로 구분하고 inspector에서 이름·역할을 보여준다.
- 화면에 `DEBUG OMNI` 배지를 항상 표시한다.

112px inspector의 최소 5줄:

```text
이름 · 종족 · 역할 · 위치 · HP
현재 활동 · 의도 → 목표
배고픔 · 피로 · 사회 욕구
대표 방향성 관계
최신 중요 기억 또는 결정 이유
```

Drawer에는 roster, 전체 후보 진단, 모든 방향성 관계, 기억, 사건 로그를 섹션으로 표시한다.

관찰 control:

```text
▶/⏸    +1분    +10분    +1시간    추적
```

- 초기 상태는 PAUSED.
- UI Timer는 언제 `advance_minutes(1)`을 부를지만 정한다.
- 속도는 timeout 간격만 바꾸며 코어 규칙을 바꾸지 않는다.
- 브라우저 focus loss, RESET, LOAD, Drawer/Menu open 시 자동 일시정지한다.
- 복귀 후 wall-clock catch-up을 몰아서 실행하지 않는다.

FOV와 미니맵은 이번 DEBUG OMNI 화면에 넣지 않는다. 후속 player-observation facade에서 roster, inspector, event log까지 함께 정보 차단한 뒤 도입한다.

## 12. 사건 계약

최소 사건 종류를 versioned allowlist에 추가한다.

```text
ai.intent_selected
ai.action_blocked
activity.work
activity.eat
activity.rest
social.conversation
relationship.familiarity_changed
memory.recorded
```

MOVE는 기존 `action.move`를 사용한다. 모든 사건은 actor/target/source/cause 참조가 유효해야 한다. 한 NPC tick에서 생길 수 있는 사건 수를 simulator의 event headroom preflight에 보수적으로 포함한다.

NPC 내부 사건은 해당 `system.npc_tick` timeline marker에 귀속한다. preview에는 공개 cadence만 표시하고 숨은 구체 intent를 미리 노출하지 않는다.

## 13. 필수 테스트

### 시간·scheduler

- 정착 snapshot에 environment/npc schedule이 정확히 하나씩 존재
- 같은 100 경계에서 environment priority 100 → npc priority 200 순서
- 여러 분 WAIT와 분할 WAIT의 최종 snapshot/event hash 동일
- NPC tick이 `step_index`를 추가로 올리지 않음
- handler가 새 schedule ID를 만들지 않음
- event/schedule overflow는 commit 전 전체 무변경 거부

### 이동·경로

- 8방향 MOVE 허용, 제자리/두 칸 이동 거부
- 양 flank 중 하나라도 막히면 대각 코너컷 거부
- 점유 flank 사이 비집기 거부
- 환경의 cardinal 확산은 여전히 4방향
- weighted path와 모든 동점 결과 고정
- path query가 snapshot/RNG/event/ID를 바꾸지 않음
- 막힌 길에서 순간이동·중복 점유 없음

### 자율행동

- 같은 seed에서 roster ID/profile/초기 위치가 동일
- 같은 pre-action projection에서 batch intent를 계산
- 동일 목적지 충돌 승자가 항상 동일
- 아침 출근, 정오 식사, 저녁 사교, 밤 귀가/휴식 관찰
- critical hunger/fatigue가 routine을 덮고 해소 후 복귀
- busy NPC는 새 행동을 고르지 않음
- 모든 이동은 한 칸 action.move
- 24시간 동안 중복 점유, 범위 밖 위치, unknown target 0

### 관계·기억

- 대화 참가자 두 방향 familiarity만 증가
- cooldown 안의 반복 대화는 familiarity를 중복 증가시키지 않음
- 대화는 aid/gratitude로 기록되지 않음
- 일반 대화 후에도 인간↔고블린 species prior가 지배적
- memory dedupe와 32개 eviction 순서 고정
- 관계 A→B와 B→A inspector 방향이 섞이지 않음

### 저장·재현

- 중간 MOVE, blocked action, 대화 직후 snapshot JSON round trip
- 연속 24시간과 중간 save/load 24시간의 snapshot/event hash 일치
- 같은 WAIT journal을 ×1/×4 UI 속도로 실행해도 결과 동일
- v3 snapshot과 v1 session을 명시적으로 거부
- detached DTO 변조가 world를 바꾸지 않음

### UI

- 15×15 = 225 cell과 가장자리 camera clamp
- 선택 NPC가 이동해도 같은 entity ID와 inspector가 따라감
- 죽거나 사라진 선택 대상 fallback
- pause 중 timeout은 world 무변경
- timer 1회당 settled `advance_minutes(1)` 정확히 1회
- 450×800과 360×640에서 panel 겹침·가로 overflow 없음
- modal/focus loss 중 자동 진행 차단
- headless scene load와 한 프레임 smoke 통과

## 14. 구현 권장 순서

한 단계씩 테스트를 통과시키고 다음으로 간다.

```text
A. ruleset/snapshot v4 + 두 cadence 계약
B. 8방향 MOVE + pure weighted pathfinder
C. AgentProfile/AgentState/Memory 직렬화
D. NpcCoordinator batch decide/resolve/commit
E. routine·욕구·활동
F. SOCIALIZE·familiarity·memory
G. 24×24 마을과 10명 roster
H. detached Session DTO + journal/save/load
I. 15×15 observer UI + roster/follow/inspector/time controls
J. 장기 결정론·반응형 UI·웹 export 검증
```

## 15. 구현 완료 보고 형식

완료 보고에는 다음만 명확히 적는다.

- 실제 구현한 행동과 아직 비목표인 항목
- 추가·수정한 core 파일과 UI 파일
- snapshot/ruleset/session 버전
- 테스트 개수와 실패 수
- 24시간 연속 vs save/load 결정론 결과
- 450×800, 360×640 UI smoke 결과
- 남은 설계 위험

테스트를 통과하지 않은 기능을 완료로 보고하지 않는다. 사용자가 요청하지 않은 push/deploy는 하지 않는다.
