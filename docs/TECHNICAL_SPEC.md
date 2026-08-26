# Slime Automation — 기술 명세

- 문서 버전: 0.2
- 기준 게임 규칙: IMPLEMENTATION_GUIDE.md 0.2
- 목적: 대화 기록 없이 실제 코드를 작성할 수 있는 클래스·알고리즘 계약
- 대상: Godot 4.6 / GDScript / Compatibility renderer

이 문서는 구현 방법을 고정한다. 게임 규칙이 바뀌면 IMPLEMENTATION_GUIDE.md를 먼저 수정하고 이 문서를 갱신한다.

---

## 1. 프로젝트 설정

### 기본 설정

| 항목 | 값 |
|---|---|
| 프로젝트명 | Slime Automation, 임시 |
| 기본 viewport | 720×1280 |
| Stretch Mode | canvas_items |
| Stretch Aspect | expand |
| 렌더러 | gl_compatibility |
| Web thread support | 끔 |
| 초기 방향 | 세로 |
| 시뮬레이션 틱 | 10Hz, 0.1초 |
| 최대 활성 슬라임 | 12 |
| MVP 활성 슬라임 | 4~6 |

논리 좌표는 720×1280을 기준으로 한다. 화면 비율이 길어지면 중앙 월드의 상하 여백이 늘고, 상단과 하단 UI는 Safe Area 안에 고정한다.

### Autoload

초기 Autoload는 App 하나만 사용한다.

    App
    - 현재 GameSession 소유
    - 새 게임 생성
    - 저장 로드
    - 메인 씬 전환
    - 설정 접근

전역 SignalBus는 만들지 않는다. 게임 이벤트는 GameSession이 중계한다.

### 입력

화면 객체는 직접 마우스와 터치를 각각 처리하지 않는다. InputController가 포인터 이벤트 하나로 정규화한다.

    pointer_id
    screen_position
    pressed
    released
    moved_distance
    consumed

규칙:

- 같은 down/up 쌍은 명령 하나만 생성
- 이동량이 임계값을 넘으면 탭 취소
- 두 번째 손가락은 MVP에서 무시
- 터치에서 생성된 에뮬레이션 마우스 이벤트 중복 차단
- 개발 입력은 release export에서 비활성화

개발 입력:

- F2: 시뮬레이션 ×2
- F3: 시뮬레이션 ×5
- F4: 시뮬레이션 정상화
- F8: 현재 상태 검사
- F9: 테스트 저장
- F10: 테스트 저장 삭제, 개발 빌드만

---

## 2. 메인 씬 트리

    Main
    ├── SessionHost
    ├── World
    │   ├── Background
    │   ├── FacilityLayer
    │   ├── SlimeLayer
    │   └── EffectLayer
    ├── Camera2D
    └── HUD
        ├── SafeArea
        │   ├── TopBar
        │   │   ├── WoodCounter
        │   │   ├── CrystalCounter
        │   │   ├── PopulationCounter
        │   │   └── GoalProgress
        │   ├── ContextPanel
        │   └── ToastLayer
        └── ModalLayer
            ├── MemoryReplaceDialog
            ├── DivisionPreviewDialog
            └── FusionPreviewDialog

### 역할

Main:

- GameSession 생성 또는 연결
- 현재 GameState로 View 생성
- 이벤트를 View와 HUD에 전달
- 씬 종료 시 연결 해제

World:

- 논리 상태를 표시하는 Node만 소유
- 자원, 숙련도, 분열 규칙을 계산하지 않음

SlimeView:

- slime_id 하나와 연결
- 이동 보간
- 임시 슬라임 도형 표시
- 선택 상태
- 작업 진행 링
- 코칭 링
- 분열 준비 아이콘
- 막힘 아이콘
- 포인터 입력을 InputController로 전달

FacilityView:

- facility_id 하나와 연결
- 단계별 임시 외형
- 작업 슬롯 위치 제공
- 잠김과 해금 상태
- 업그레이드 가능 표시
- 자원이나 비용을 직접 변경하지 않음

HUD:

- 선택 상태는 UI 로컬 상태로 관리
- 명령 실행은 GameSession API만 호출
- 오류 코드를 사용자 문구로 변환

ModalLayer:

- 분열·합성·기억 교체처럼 되돌리기 어려운 행동만 담당
- 열려 있는 동안 interaction pause를 활성화
- 닫을 때 interaction pause 해제

---

## 3. 클래스 공통 규칙

### Runtime State

런타임 상태 클래스는 RefCounted 기반 typed class로 작성한다.

필수 메서드:

    to_dict() -> Dictionary
    static from_dict(data: Dictionary) -> StateClass
    clone_state() -> StateClass
    validate(content_registry) -> PackedStringArray

런타임 상태에 넣지 않는 것:

- Node
- NodePath
- Callable
- Signal
- Texture
- AnimationPlayer
- 화면 좌표 캐시
- 번역된 문장

### Definition

정적 콘텐츠는 Resource 기반 typed class로 작성하고 content 폴더의 tres 파일로 저장한다.

필수 필드:

    id: StringName
    display_name_key: StringName
    enabled: bool

ID는 출시 이후 변경하지 않는다. 이름 변경은 display_name_key만 바꾼다.

`unlocked_content_ids`에는 Definition의 실제 ID를 저장한다. `skill_logging`처럼
종류 접두사를 붙인 별도 해금 ID를 만들지 않는다. 모든 Definition ID는
ContentRegistry 전체에서 유일해야 한다.

예:

    logging
    job_logging
    forest

### ID 생성

GameState.next_entity_number를 사용한다.

    slime_%06d

예:

    slime_000001
    slime_000002

ID 발급은 GameSession만 수행한다. 삭제된 ID를 재사용하지 않는다.

---

## 4. CommandResult와 PreviewResult

### CommandResult

    class_name CommandResult
    extends RefCounted

    var ok: bool
    var code: StringName
    var payload: Dictionary

성공:

    ok = true
    code = OK

실패:

    ok = false
    code = 안정적인 오류 ID
    payload = UI 표시나 디버깅에 필요한 최소 데이터

실패 명령은 GameState를 변경하지 않는다.

### PreviewResult

    class_name PreviewResult
    extends RefCounted

    var ok: bool
    var code: StringName
    var preview_token: String
    var source_fingerprint: String
    var result_payload: Dictionary

preview_token은 다음을 포함한 canonical 데이터의 해시다.

- 명령 종류
- 관련 슬라임 상태
- 현재 인구와 한도
- 관련 시설 상태
- 관련 자원
- GameState.schema_version

분열과 합성 확인창이 열려 있는 동안 interaction pause로 시뮬레이션을 멈춘다. 확정 시 같은 순수 함수를 다시 호출하고 fingerprint가 다르면 STALE_PREVIEW를 반환한다.

---

## 5. 상태 클래스 계약

### GameState

필드:

    schema_version: int
    content_version: int
    region_id: StringName
    simulation_tick: int
    next_entity_number: int
    slimes: Dictionary
    facilities: Dictionary
    inventories: Dictionary
    unlocked_content_ids: Dictionary
    goal_states: Dictionary
    last_saved_unix: int

메서드:

    allocate_slime_id() -> StringName
    get_population() -> int
    validate(content_registry) -> PackedStringArray
    to_dict() -> Dictionary
    static from_dict(data: Dictionary) -> GameState

population_cap은 저장하지 않는다. PopulationSystem이 서식지 단계에서 계산한다.

### SlimeState

필드:

    id: StringName
    definition_id: StringName
    display_name: String
    skill_memories: Dictionary
    memory_capacity: int
    routine: Array[RoutineStep]
    routine_cursor: int
    current_job: JobRuntime
    division_meter: int
    generation: int
    parent_ids: Array[StringName]
    fusion_tier: int
    logical_location_id: StringName
    next_cycle_number: int

불변식:

- memory_capacity는 1~3
- skill_memories.size는 memory_capacity 이하
- routine.size는 memory_capacity 이하
- 모든 routine의 skill은 skill_memories에 존재
- routine_cursor는 유효 범위 또는 0
- division_meter는 0 이상
- current_job의 slime_id는 자기 ID와 동일
- next_cycle_number는 1 이상이며 작업 취소·재배치 후에도 감소하지 않음

### SkillProgress

필드:

    skill_id: StringName
    level: int
    xp: int
    total_cycles: int

불변식:

- level은 1~5
- xp는 0 이상
- level 5에서는 xp 0
- total_cycles는 0 이상

### RoutineStep

필드:

    skill_id: StringName
    job_id: StringName
    target_id: StringName
    order: int
    enabled: bool
    blocked_reason: StringName

RoutineStep은 작업 결과를 저장하지 않는다.

### JobRuntime

필드:

    slime_id: StringName
    job_id: StringName
    target_id: StringName
    phase: StringName
    cycle_id: int
    elapsed_ticks: int
    duration_ticks: int
    movement_ticks: int
    coaching_used: bool
    completion_requested: bool
    blocked_reason: StringName
    reservation_id: StringName

새 사이클마다 cycle_id를 1 증가시킨다.

### InventoryState

필드:

    owner_id: StringName
    amounts: Dictionary
    capacities: Dictionary
    reservations: Dictionary

reservations 구조:

    reservation_id
      resource_id: amount

available amount는 amounts에서 예약량을 제외해 계산하거나, 예약 시 amounts에서 빼고 reservations에 보관한다. MVP에서는 후자를 사용한다.

---

## 6. Definition 계약

### ResourceDefinition

    id
    display_name_key
    icon_key
    stack_limit
    is_currency

초기 ID:

- wood
- crystal

### SkillDefinition

    id
    display_name_key
    level_xp_requirements
    level_speed_multipliers
    bonus_every_n_cycles
    animation_key

초기 ID:

- logging
- mining
- repairing

### BalanceDefinition

코드에 하드코딩하지 않고 테스트 fixture에서 교체해야 하는 전역 규칙을 보관한다.

    division_base_cycles
    division_per_extra_skill_cycles

실제 콘텐츠 기본값:

    division_base_cycles: 24
    division_per_extra_skill_cycles: 12

테스트는 같은 알고리즘에 별도 BalanceDefinition을 주입한다.

초기 XP 요구량:

    Lv.1→2: 20
    Lv.2→3: 40
    Lv.3→4: 80
    Lv.4→5: 160

초기 속도 배율:

    Lv.1: 1.00
    Lv.2: 1.10
    Lv.3: 1.25
    Lv.4: 1.45
    Lv.5: 1.70

### JobDefinition

필드:

    id
    required_skill_id
    job_kind
    allowed_target_tags
    base_duration_ticks
    movement_duration_ticks
    inputs
    outputs
    passive_xp
    normal_coaching_progress_ratio
    normal_coaching_xp
    perfect_window_ticks
    perfect_coaching_xp
    min_duration_ticks

초기 ID와 값:

| ID | skill | kind | duration | input | output |
|---|---|---|---:|---|---|
| job_logging | logging | PRODUCTION | 50틱 | 없음 | wood 1 |
| job_mining | mining | PRODUCTION | 60틱 | 없음 | crystal 1 |
| job_repair_ark | repairing | CONSTRUCTION | 40틱 | wood 2, crystal 1 | ark progress 1 |

공통값:

    movement_duration_ticks: 5
    passive_xp: 1
    normal_coaching_progress_ratio: 0.15
    normal_coaching_xp: 1
    perfect_window_ticks: 8
    perfect_coaching_xp: 3
    min_duration_ticks: 15

### FacilityDefinition

초기 ID:

- habitat
- forest
- crystal_mine
- fusion_pool
- ark
- town_storage

각 tier 데이터:

    cost
    worker_slots
    inventory_capacity
    work_speed_multiplier
    population_bonus
    unlocked_content_ids

### GoalDefinition

초기 ID:

- ark_stage_1
- ark_stage_2
- ark_stage_3

| 목표 | 필요 수리 | 보상 |
|---|---:|---|
| ark_stage_1 | 10 | fusion_pool 활성화 |
| ark_stage_2 | 18 | ark visual stage 2 |
| ark_stage_3 | 30 | first_clearing 완료 |

---

## 7. 초기 GameState

새 게임은 아래 상태와 동일해야 한다.

    schema_version: 1
    content_version: 1
    region_id: first_clearing
    simulation_tick: 0
    next_entity_number: 2

    slimes:
      slime_000001
        definition_id: basic_slime
        display_name: Momo, 임시
        skill_memories: 비어 있음
        memory_capacity: 1
        routine: 비어 있음
        division_meter: 12
        generation: 0
        parent_ids: 비어 있음
        fusion_tier: 0
        logical_location_id: habitat
        next_cycle_number: 1

    inventories:
      town_storage
        wood: 0
        crystal: 0

    facilities:
      habitat: tier 0, enabled
      forest: tier 0, enabled, worker slot 1
      crystal_mine: locked
      fusion_pool: locked
      ark: visible, repair locked until repairing is introduced
      town_storage: enabled

    population:
      current: 계산값 1
      capacity: 계산값 4

    unlocks:
      logging
      job_logging
      forest

첫 시작 슬라임은 벌목을 이미 알지 않는다. 플레이어가 선택하고 나무를 눌러야 첫 작업이 시작된다.

---

## 8. GameSession API 계약

### 생성과 시간

    new_game() -> void
    load_game(snapshot: Dictionary) -> CommandResult
    advance_ticks(tick_count: int) -> void
    set_interaction_pause(paused: bool) -> void
    create_snapshot() -> Dictionary
    validate_state() -> PackedStringArray

interaction_pause는 분열·합성·기억 교체 확인창에만 사용한다. 브라우저 백그라운드 정지는 별도 처리한다.

### 교육

    teach(slime_id, target_id, job_id) -> CommandResult

검사 순서:

1. slime_id 존재
2. target_id 존재 및 해금
3. job_id 존재
4. target tag 호환
5. required skill을 이미 보유하는지 확인
6. 새 스킬이고 기억이 가득 찼으면 MEMORY_FULL과 교체 후보 반환
7. 모든 조건 통과 후 기존 작업 취소·예약 반환
8. 스킬이 없으면 Lv.1 / XP 0 생성
9. 단일 루틴을 해당 작업으로 설정
10. assignment_changed 이벤트 적재

교육 시점에는 시설 작업 슬롯을 선점하지 않는다. 슬롯이 가득 차도 교육은 성공하며 JobSystem이 작업 시작을 시도할 때 FACILITY_FULL을 blocked reason으로 기록한다.
교육 성공과 같은 명령 안에서는 작업을 시작하지 않는다. 다음 시뮬레이션 틱에
JobSystem이 루틴을 평가하고 슬롯과 입력 자원을 예약한다.

기억 교체:

    preview_memory_replace(slime_id, forgotten_skill_id, new_job) -> PreviewResult
    commit_memory_replace(preview_token) -> CommandResult

교체 확정 전에는 기존 스킬을 삭제하지 않는다.

교체 확정 시에는 기존 스킬과 그 스킬을 사용하는 모든 routine step을 함께 제거하고, 새 스킬과 새 단일 routine step을 추가한다. 이 변경은 하나의 트랜잭션으로 처리한다.

### 루틴

    set_routine(slime_id, routine_steps) -> CommandResult

검사:

- routine 길이는 1 이상 memory_capacity 이하
- 각 skill은 보유
- 각 target은 job과 호환
- 동일 order 중복 없음
- 동일한 완전 중복 step 없음

성공 시 기존 작업을 취소하고 새 루틴 0번부터 시작한다.

### 코칭

    coach(slime_id, cycle_id) -> CommandResult

검사:

1. 슬라임 존재
2. current_job.phase가 WORKING
3. 전달 cycle_id가 현재 cycle_id와 동일
4. coaching_used가 false
5. interaction_pause가 false

판정:

    remaining_ticks = duration_ticks - elapsed_ticks

    remaining_ticks <= perfect_window_ticks
    → PERFECT
    → completion_requested = true
    → 추가 XP 3

    그 외
    → NORMAL
    → elapsed_ticks += ceil(duration_ticks × 0.15)
    → 추가 XP 1

공통:

- coaching_used = true
- coaching_resolved 이벤트 적재
- 완료 요청은 JobSystem이 다음 시뮬레이션 틱에 처리
- 코칭 자체는 division_meter를 올리지 않음

---

## 9. JobSystem 알고리즘

### 실제 작업 시간

    duration_ticks
    = ceil(base_duration_ticks
      ÷ skill_speed_multiplier
      ÷ facility_speed_multiplier)

    duration_ticks
    = max(duration_ticks, min_duration_ticks)

현재 사이클 시작 시 한 번 계산해 JobRuntime에 저장한다. 도중 레벨업과 시설 업그레이드는 다음 사이클부터 반영한다.

### 작업 시작

1. 현재 루틴 step 선택
2. 시설 활성화와 worker slot 확인
3. 입력 자원 예약 시도
4. 실패하면 blocked_reason 기록
5. 성공하면 cycle_id에 slime.next_cycle_number를 사용하고 next_cycle_number 증가
6. coaching_used false
7. completion_requested false
8. phase MOVING
9. movement_ticks 5 설정

같은 틱에 여러 슬라임이 마지막 작업 슬롯을 요청하면 slime ID 오름차순으로 처리한다. 시설 슬롯은 작업 사이클 시작부터 완료·취소까지 예약하고 사이클 종료 시 해제한다.

reservation_id는 `reservation:<slime_id>:<cycle_id>` 형식으로 결정적으로 만든다.

### 이동 완료

- elapsed movement가 movement_ticks에 도달하면 phase WORKING
- work elapsed를 0으로 초기화
- SlimeView에 phase 이벤트 전달

### 작업 진행

- interaction_pause가 아니면 매 틱 elapsed_ticks 증가
- completion_requested이면 완료 처리
- elapsed_ticks가 duration_ticks에 도달하면 완료 처리

### 완료 처리

PRODUCTION:

1. 출력 저장 공간 확인
2. 출력 추가
3. 예약된 입력이 있다면 commit
4. 숙련 XP +1
5. total_cycles +1
6. division_meter +1
7. job_cycle_completed 이벤트

출력 저장 공간이 부족하면 완료 보상을 일부도 적용하지 않는다. 작업은
`BLOCKED_OUTPUT` 상태로 100% 진행도를 유지하고 시설 슬롯을 계속 점유한다.
입력 예약도 유지하며, 저장 공간 변경 이벤트 또는 10틱 안전 주기에서 완료를
다시 시도한다. 작업을 취소하면 입력 예약과 시설 슬롯을 정상 반환한다.

CONSTRUCTION:

1. 예약 입력 commit
2. 목표 progress +1
3. 숙련 XP +1
4. total_cycles +1
5. division_meter +1
6. ProgressionSystem 호출
7. job_cycle_completed 이벤트

완료 후 routine_cursor를 다음 단계로 이동하고 새 사이클을 시작한다.

### 취소

작업 변경, 분열, 합성 시:

1. reservation_id가 있으면 InventorySystem.release_reservation
2. 시설 worker reservation 해제
3. completion_requested false
4. current_job 초기화
5. 미완료 출력과 XP는 지급하지 않음

---

## 10. InventorySystem 계약

메서드:

    get_amount(inventory_id, resource_id) -> int
    can_add(inventory_id, amounts) -> bool
    try_add(inventory_id, amounts) -> CommandResult
    can_pay(inventory_id, costs) -> bool
    try_pay(inventory_id, costs) -> CommandResult
    try_reserve(inventory_id, costs, reservation_id) -> CommandResult
    commit_reservation(inventory_id, reservation_id) -> CommandResult
    release_reservation(inventory_id, reservation_id) -> CommandResult
    try_transfer(source_id, destination_id, amounts) -> CommandResult

규칙:

- 음수 amount 거부
- 0 amount는 무시
- 여러 자원 작업은 전체가 가능할 때만 실행
- 부분 추가, 부분 소비 금지
- 없는 reservation commit과 release는 오류
- 저장 시 reservation도 포함
- inventory_changed 이벤트는 성공 후 발생

---

## 11. ProficiencySystem 계약

메서드:

    grant_xp(slime_id, skill_id, amount) -> Array[DomainEvent]
    get_speed_multiplier(slime_id, skill_id) -> float
    decrease_all_levels_for_division(skill_memories) -> Dictionary

XP 처리:

1. amount가 0 이하이면 무시
2. Lv.5이면 xp를 증가시키지 않음
3. 현재 xp에 amount 추가
4. 요구 XP 이상이면 요구량 차감 후 level +1
5. 남은 XP가 다음 경계도 넘으면 반복
6. Lv.5 도달 시 xp 0
7. 레벨업 이벤트 발생

분열 처리:

- 모든 SkillProgress를 깊은 복사
- level = max(1, level - 1)
- xp = 0
- total_cycles는 유지
- 원본 Dictionary를 변경하지 않음

---

## 12. Routine Scheduler

메서드:

    find_next_runnable_step(slime, state) -> RoutineSelection

알고리즘:

1. routine이 비어 있으면 IDLE
2. routine_cursor부터 최대 routine.size번 검사
3. disabled step은 건너뜀
4. target 잠김, 재료 부족, 슬롯 부족을 reason으로 기록
5. 실행 가능한 첫 step 반환
6. 실행 가능 step이 없으면 BLOCKED
7. 가장 먼저 만난 구체적인 reason을 대표 reason으로 반환
8. inventory, facility, unlock 이벤트 수신 시 즉시 재검사
9. 이벤트를 놓친 경우를 대비해 10틱마다 재검사

조건문이나 사용자 우선순위 수치는 MVP에서 지원하지 않는다.

---

## 13. PopulationSystem

메서드:

    get_population(state) -> int
    get_capacity(state, content_registry) -> int
    can_add(state, amount) -> bool

capacity는 habitat의 현재 tier population_bonus로 계산한다.

초기:

    tier 0: 4
    tier 1: 6

후속:

    tier 2: 9
    tier 3: 12

GameState에 별도 capacity 값을 저장하지 않는다.

---

## 14. DivisionSystem

API:

    preview_division(slime_id) -> PreviewResult
    commit_division(preview_token) -> CommandResult

필요 게이지:

    balance.division_base_cycles
    + balance.division_per_extra_skill_cycles × (skill_memories.size - 1)

검사:

1. 슬라임 존재
2. 기억한 스킬 1개 이상
3. division_meter가 요구량 이상
4. PopulationSystem.can_add(1)
5. interaction_pause 상태는 preview modal에서만 true
6. 현재 작업 예약을 반환 가능

순수 계산 함수:

    calculate_division_result(source_snapshot) -> Dictionary

결과:

- source_snapshot에서 child A와 child B를 각각 깊은 복사
- 두 개의 새 slime ID 발급
- 두 결과 generation = source generation +1
- parent_ids = source ID를 포함
- 모든 스킬 level -1, 최저 1
- 모든 스킬 xp 0
- division_meter 0
- child A routine은 원본 routine 복사
- child B routine은 비움
- current_job은 양쪽 비움
- source 슬라임 제거
- child A와 B 추가
- child A의 루틴 예약 재시작
- 인구 +1

트랜잭션:

1. commit 시 preview 재계산
2. token 검증
3. 기존 작업 취소와 예약 반환
4. 결과 두 개를 메모리에 완성
5. source 제거와 결과 추가를 한 번에 수행
6. population invariant 검사
7. 이벤트 적재
8. autosave 요청

어느 단계든 실패하면 source 상태를 그대로 유지한다.

---

## 15. FusionSystem

API:

    preview_fusion(slime_a_id, slime_b_id) -> PreviewResult
    commit_fusion(preview_token) -> CommandResult

검사:

1. 서로 다른 ID
2. 두 슬라임 존재
3. 두 슬라임 모두 잠기지 않음
4. 예약 자원 반환 가능
5. 서로 다른 스킬 합집합 계산
6. 결과 capacity 계산
7. 합집합 크기가 capacity 이하

capacity:

    min(3, max(a.memory_capacity, b.memory_capacity) + 1)

스킬 병합:

- 한쪽에만 있는 스킬: 깊은 복사
- 양쪽에 같은 스킬:
  - 레벨이 높은 쪽 선택
  - 레벨이 같으면 XP가 높은 쪽 선택
  - total_cycles는 높은 값 선택
- XP 합산 금지

결과:

- 새 slime ID
- skill_memories 합집합
- memory_capacity 계산값
- routine 비움
- current_job 비움
- division_meter 0
- generation = max(parent generation) +1
- parent_ids = 두 부모 ID
- fusion_tier = max(parent fusion_tier) +1
- logical_location_id = fusion_pool
- 두 부모 제거
- 결과 하나 추가
- 인구 -1

합성 결과는 무작위가 아니며, 미리보기의 skill, level, xp, capacity와 동일해야 한다.

---

## 16. UpgradeSystem

API:

    preview_upgrade(facility_id) -> PreviewResult
    commit_upgrade(preview_token) -> CommandResult

검사:

1. 시설 존재
2. 다음 tier 존재
3. 선행 콘텐츠 해금
4. town_storage 비용 충분
5. 동일 업그레이드 처리 중이 아님

트랜잭션:

1. preview 재계산과 token 검증
2. InventorySystem.try_pay
3. tier +1
4. worker slot, capacity, unlock 재계산
5. population capacity가 달라졌으면 population_changed 이벤트
6. 업그레이드 이벤트
7. autosave 요청

try_pay 성공 후 tier 변경이 실패할 가능성이 없도록 모든 정의 유효성은 먼저 검사한다.

초기 업그레이드:

| ID | 효과 | 비용 |
|---|---|---|
| crystal_mine | 광맥, mining, job_mining 활성화 | wood 8 |
| forest_tier_1 | worker slot 2 | wood 12, crystal 4 |
| mine_tier_1 | worker slot 2 | wood 15, crystal 6 |
| habitat_tier_1 | population cap 6 | wood 20, crystal 8 |

fusion_pool과 합성 UI는 ark_stage_1 완료 이벤트로 활성화한다.

---

## 17. ProgressionSystem

GoalState:

    goal_id
    current_progress
    completed
    reward_claimed

repair 완료 시:

1. 현재 ark goal 선택
2. current_progress +1
3. 필요량 도달 검사
4. completed true
5. 보상 적용
6. reward_claimed true
7. 다음 stage 활성화
8. goal_completed 이벤트
9. autosave 요청

보상은 같은 goal에서 한 번만 적용한다.

초기 목표:

    stage 1: 10회, fusion_pool 활성화
    stage 2: 18회, ark visual stage 2
    stage 3: 30회, first_clearing 완료

첫 crystal 자원이 town_storage에 들어오는 순간 repairing, job_repair_ark,
ark repair interaction을 한 번에 해금한다. GameSession은 성공한 inventory 변경과
같은 상태 변경 흐름 안에서 `ProgressionSystem.reconcile_unlocks(state)`를 호출한 뒤
도메인 이벤트를 적재한다. 이벤트 처리자가 이 해금을 수행하지 않는다. 이 해금은
실제 콘텐츠 ID로 저장하며 같은 조건을 반복 확인해도 한 번만 적용한다.

---

## 18. 도메인 이벤트 계약

이벤트는 Dictionary 또는 typed DomainEvent로 큐에 쌓고 틱 종료 후 전달한다.

필드:

    type
    simulation_tick
    entity_ids
    payload

이벤트 종류:

    assignment_changed
    job_cycle_started
    job_cycle_completed
    job_blocked
    coaching_resolved
    proficiency_changed
    inventory_changed
    population_changed
    division_completed
    fusion_completed
    facility_upgraded
    goal_completed
    unlock_changed
    autosave_requested

규칙:

- 이벤트 처리자가 GameState를 다시 변경하지 않음
- View가 사라진 뒤 연결이 남지 않음
- 이벤트 하나당 UI 갱신 한 번
- 이벤트에 Node 참조 없음

### Canonical 직렬화와 해시

preview fingerprint, 저장 검증, 결정론 테스트는 같은 canonical 직렬화를 사용한다.

1. Dictionary key를 문자열 오름차순으로 재귀 정렬
2. Array 순서는 보존하고 내부 값을 재귀 처리
3. UTF-8 JSON으로 직렬화
4. SHA-256 소문자 hex 문자열 생성

플랫폼 기본 Dictionary 순서나 `hash(Dictionary)`에 의존하지 않는다.

---

## 19. 저장 스키마

최상위 예:

    {
      schema_version: 1,
      content_version: 1,
      build_version: dev,
      save_sequence: 12,
      saved_at_unix: 1787700000,
      last_simulation_unix: 1787700000,
      simulation_tick: 840,
      next_entity_number: 5,
      region_id: first_clearing,
      slimes: {},
      facilities: {},
      inventories: {},
      goals: {},
      unlocks: []
    }

Slime 예:

    slime_000004:
      definition_id: basic_slime
      display_name: Momo
      memory_capacity: 2
      skills:
        logging:
          level: 3
          xp: 12
          total_cycles: 41
        mining:
          level: 2
          xp: 5
          total_cycles: 19
      routine:
        - skill_id: logging
          job_id: job_logging
          target_id: forest
          order: 0
          enabled: true
        - skill_id: mining
          job_id: job_mining
          target_id: crystal_mine
          order: 1
          enabled: true
      routine_cursor: 0
      current_job:
        phase: WORKING
        cycle_id: 42
        elapsed_ticks: 20
        duration_ticks: 40
        coaching_used: false
        reservation_id: empty
      division_meter: 17
      generation: 2
      parent_ids:
        - slime_000001
        - slime_000003
      fusion_tier: 1
      logical_location_id: forest

저장하지 않음:

- 선택 상태
- 열린 modal
- interaction pause
- Tween 진행도
- 애니메이션 프레임
- 실제 화면 좌표
- 계산 가능한 population cap

### A/B 저장

파일:

    save_a.json
    save_b.json

절차:

1. GameState 불변 snapshot 생성
2. canonical Dictionary 직렬화
3. 낮은 sequence 슬롯 선택
4. 새 payload 기록
5. 다시 읽어 파싱과 schema 검사
6. 성공 시 메모리 save_sequence 갱신
7. load 시 유효한 파일 중 높은 sequence 선택

### 저장 시점

- 10~15초 디바운스
- 업그레이드 성공
- 분열 성공
- 합성 성공
- 목표 완료
- 브라우저 focus 상실
- 앱 pause 알림

종료 이벤트 하나만 신뢰하지 않는다.

---

## 20. UI 상태 흐름

### 기본 상태

    NONE
    SLIME_SELECTED
    FACILITY_SELECTED
    MEMORY_REPLACE_MODAL
    DIVISION_MODAL
    FUSION_SELECTING
    FUSION_MODAL

### 교육

    NONE
    → slime tap
    → SLIME_SELECTED
    → compatible facility tap
    → teach command
    → NONE

### 코칭

    NONE
    → active coaching ring tap
    → coach command
    → NONE

SLIME_SELECTED 상태에서는 코칭 링 입력보다 교육 대상 입력을 우선한다.

### 분열

    SLIME_SELECTED
    → divide button
    → preview
    → simulation interaction pause
    → DIVISION_MODAL
    → confirm or cancel
    → pause 해제
    → NONE

### 합성

    facility fusion_pool tap
    → FUSION_SELECTING
    → slime A 선택
    → slime B 선택
    → preview
    → FUSION_MODAL
    → confirm or cancel
    → NONE

합성 선택 중 작업 대상 터치는 무시하고 상단에 현재 선택 상태를 표시한다.

---

## 21. 온보딩 트리거

온보딩 상태는 완료한 이벤트 ID 집합으로 저장한다.

초기 트리거:

| 조건 | 유도 |
|---|---|
| 새 게임 | 첫 슬라임 펄스 |
| 슬라임 선택 | 숲 펄스 |
| 첫 벌목 시작 | 작업 링 소개 |
| 첫 정확 코칭 가능 | 링 강한 펄스 |
| 첫 Lv.2 | 숙련도 한 줄 설명 |
| division meter 충족 | 분열 아이콘 펄스 |
| 첫 분열 완료 | 광맥 해금 비용 강조 |
| 광맥 해금 | 대기 슬라임 펄스 |
| 첫 수정 획득 | 수리 스킬과 방주 작업 해금 |
| 벌목·채굴 활성 | 방주 수리 대상 강조 |
| 방주 1단계 완료 | 합성소 강조 |
| 첫 합성 완료 | 루틴 순서 UI 표시 |
| population cap 도달 | 서식지 업그레이드 강조 |

같은 트리거는 한 번만 노출한다. 긴 강제 팝업은 사용하지 않는다.

---

## 22. 구현 파일 순서

### M0

1. project.godot
2. app/app.gd
3. game/command_result.gd
4. game/state/game_state.gd
5. game/state/slime_state.gd
6. game/state/skill_progress.gd
7. game/state/inventory_state.gd
8. game/definitions/resource_definition.gd
9. game/definitions/skill_definition.gd
10. game/definitions/job_definition.gd
11. game/simulation.gd
12. game/game_session.gd
13. tests/test_runner.gd
14. tests/test_state_validation.gd

### M1

1. game/state/routine_step.gd
2. game/state/job_runtime.gd
3. game/state/facility_state.gd
4. game/definitions/facility_definition.gd
5. game/systems/inventory_system.gd
6. game/systems/assignment_system.gd
7. game/systems/job_system.gd
8. content/resources/wood.tres
9. content/skills/logging.tres
10. content/jobs/job_logging.tres
11. content/facilities/forest.tres
12. content/facilities/town_storage.tres
13. presentation/scenes/main.tscn
14. presentation/views/slime_view.gd
15. presentation/views/facility_view.gd
16. presentation/input/input_controller.gd
17. presentation/ui/hud.gd
18. tests/test_assignment.gd
19. tests/test_job_production.gd

### M2 이후

IMPLEMENTATION_GUIDE.md의 마일스톤 순서와 TEST_PLAN.md의 게이트를 따른다.

---

## 23. 구현 중 금지되는 지름길

- View에서 자원 증가
- Timer 노드를 슬라임마다 생성
- 시설 ID 대신 NodePath 저장
- job_id switch 문을 UI에 작성
- 실패 가능 명령을 여러 단계로 부분 적용
- 분열 미리보기와 실제 결과를 별도 공식으로 계산
- 합성 스킬을 임의 순서로 덮어쓰기
- XP나 자원에 float 사용
- 시스템 시계를 실행 중 시뮬레이션 시간으로 사용
- 테스트 없이 save schema 변경
- MVP에서 운반, 랜덤 특성, 조건부 행동 트리 추가
