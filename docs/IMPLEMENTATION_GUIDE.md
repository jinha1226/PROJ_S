# Slime Automation Game — 설계·구현 가이드

- 문서 버전: 0.2
- 작성일: 2026-08-26
- 상태: 구현 기준 문서
- 대상: Godot 4.6 / GDScript / Mobile Web

> 직접 가르쳐 숙련시키고, 분열로 늘리고, 합성으로 행동을 조합하는 슬라임 자동화 게임.

이 문서는 게임 규칙, 코드 경계, 구현 순서, 테스트 기준을 한곳에서 관리하는 기준 문서다. 밸런스 숫자는 첫 플레이 테스트용 시작값이며, 핵심 규칙과 데이터 구조는 가능한 한 유지한다.

관련 문서:

- [문서 진입점과 우선순위](README.md)
- [클래스·메서드·상태 전이 계약](TECHNICAL_SPEC.md)
- [기능별 검증 항목](TEST_PLAN.md)

---

## 1. 제품 방향

### 플레이어 역할

플레이어는 반복 클릭으로 재화를 직접 캐는 노동자가 아니다. 슬라임에게 일을 가르치고, 필요한 공정을 코칭하며, 분열과 합성으로 자동화 구조를 설계한다.

    교육
    → 자동 작업
    → 코칭
    → 숙련
    → 분열 또는 합성
    → 시설과 생산망 확장
    → 지역 목표 달성

### 일반 클리커와의 대응

| 일반 클리커 | 이 게임 |
|---|---|
| 유닛 구매 | 슬라임 분열 |
| 유닛 레벨업 구매 | 실제 작업과 코칭으로 숙련 |
| 상위 유닛 합성 | 슬라임 합성 |
| 클릭 대미지 | 코칭 효과 |
| 생산량 업그레이드 | 시설 기능·작업 슬롯 확장 |
| 유닛 보유 한도 | 서식지 수용량 |
| 새 사업 해금 | 새 작업과 생산 공정 해금 |
| 스테이지 완료 | 방주 완성과 지역 이동 |

핵심 원칙:

> 슬라임은 행동으로 성장하고, 시설은 재화로 성장한다.

숙련도는 재화로 직접 구매하지 않는다. 재화는 시설, 인구 한도, 새 기능, 지역 목표에 사용한다.

### 플랫폼과 화면

- Godot 4.6, GDScript
- 세로형 모바일 Web 우선
- 마우스와 터치 동시 지원
- 고정 작업 지점이 있는 연속형 한 화면
- 8×8 격자 없음
- 자유 건물 배치 없음
- 복잡한 길 찾기 없음
- 첫 구현은 도형과 임시 색상 사용
- 실제 에셋은 시스템 검증 후 적용

---

## 2. MVP 범위

### 포함

- 첫 지역 한 화면
- 목재와 수정
- 벌목, 채굴, 수리
- 슬라임 선택과 작업 교육
- 자동 작업
- 사이클당 한 번의 코칭
- 작업별 숙련도 Lv.1~5
- 분열과 총 슬라임 수 제한
- 결정적인 합성
- 최대 3칸의 순차 실행 루틴
- 서식지·작업 슬롯·기능 해금
- 방주 3단계 목표
- 로컬 저장
- GitHub Actions Web 빌드
- 모바일 브라우저 테스트

### 제외

- 실제 그래픽 에셋
- 운반과 개별 시설 물류
- 오프라인 진행 보상
- 피로, 배고픔, 부상, 화재
- 랜덤 유전자, 돌연변이, 희귀도
- 장비와 전투
- 조건부 행동 트리
- 자유 건설과 길 찾기
- 여러 지역
- 프레스티지
- 계정, 서버, 클라우드 저장
- 광고와 결제

MVP 완료 전 제외 항목을 구현하지 않는다.

---

## 3. 첫 15~20분 플레이 흐름

진행 해금은 실제 시간보다 플레이 이벤트를 기준으로 한다.

| 목표 구간 | 경험 | 해금 |
|---|---|---|
| 시작~1분 | 슬라임 선택 → 나무 터치 → 벌목 학습 | 목재와 숙련도 UI |
| 1~2분 | 일반 코칭과 정확한 코칭 | 첫 숙련 레벨업, 분열 |
| 2~4분 | 첫 분열과 두 번째 슬라임 교육 | 수정 광맥 |
| 4~7분 | 벌목·채굴·수리 역할 배치 | 방주 1단계 |
| 7~10분 | 전문 슬라임 둘을 합성 | 2단계 루틴 |
| 10~15분 | 인구·작업 슬롯 확장 | 방주 2단계 |
| 15~20분 | 생산 병목 조정과 수리 | 방주 완성 |

한 번에 새로운 시스템을 하나만 노출한다. 긴 설명창보다 대상 강조와 짧은 상황 문구로 행동을 유도한다.

첫 플레이 테스트 합격 기준:

> 15~20분 안에 교육, 코칭, 숙련, 분열, 합성, 복합 루틴, 시설 성장, 방주 완성을 모두 경험한다.

---

## 4. 기술 구조

### 상태 변경 흐름

    화면 입력
    → GameSession 명령 API
    → System이 GameState 변경
    → 이벤트 큐에 결과 기록
    → 틱 종료 후 이벤트 전달
    → View와 UI 갱신

- GameState: 플레이 상태의 유일한 원본
- Definition: 작업·스킬·시설·밸런스 정적 데이터
- System: 상태를 변경하는 규칙
- View: 화면 표시와 애니메이션
- GameSession: 명령, 시뮬레이션, 이벤트 연결점

UI와 View는 GameState를 직접 수정하지 않는다. 슬라임 Node가 자원이나 숙련도를 직접 계산하지 않는다.

### 권장 폴더

    res://
    ├── app/
    │   └── app.gd
    ├── game/
    │   ├── game_session.gd
    │   ├── simulation.gd
    │   ├── command_result.gd
    │   ├── state/
    │   │   ├── game_state.gd
    │   │   ├── slime_state.gd
    │   │   ├── skill_progress.gd
    │   │   ├── routine_step.gd
    │   │   ├── job_runtime.gd
    │   │   ├── facility_state.gd
    │   │   └── inventory_state.gd
    │   ├── definitions/
    │   │   ├── resource_definition.gd
    │   │   ├── skill_definition.gd
    │   │   ├── job_definition.gd
    │   │   ├── facility_definition.gd
    │   │   ├── upgrade_definition.gd
    │   │   └── goal_definition.gd
    │   └── systems/
    │       ├── assignment_system.gd
    │       ├── job_system.gd
    │       ├── inventory_system.gd
    │       ├── coaching_system.gd
    │       ├── proficiency_system.gd
    │       ├── population_system.gd
    │       ├── division_system.gd
    │       ├── fusion_system.gd
    │       ├── upgrade_system.gd
    │       └── progression_system.gd
    ├── content/
    │   ├── resources/
    │   ├── skills/
    │   ├── jobs/
    │   ├── facilities/
    │   ├── upgrades/
    │   ├── goals/
    │   └── balance_config.tres
    ├── presentation/
    │   ├── scenes/
    │   ├── views/
    │   ├── input/
    │   └── ui/
    ├── persistence/
    │   └── save_repository.gd
    └── tests/

빈 시스템 파일을 한꺼번에 만들지 않는다. 해당 마일스톤에서 실제로 쓰이는 파일만 추가한다.

### 중앙 시뮬레이션

시뮬레이션은 0.1초 고정 틱으로 진행한다.

    simulation.advance_ticks(tick_count)

처리 순서는 항상 같다.

1. 루틴 선택과 작업 자리 예약
2. 이동과 작업 진행
3. 완료 작업의 자원 트랜잭션
4. 숙련도와 분열 게이지 반영
5. 시설·목표·해금 검사
6. 이벤트 전달

화면은 매 프레임 위치를 보간하지만 게임 결과에는 관여하지 않는다.

---

## 5. 데이터 모델

### GameState

    schema_version
    content_version
    region_id
    simulation_tick
    next_entity_number
    slimes: id → SlimeState
    facilities: id → FacilityState
    inventories: id → InventoryState
    unlocked_content_ids
    goal_progress
    last_saved_unix

ID는 slime_000012, facility_tree_01처럼 저장과 테스트에 안정적인 문자열을 사용한다. Node나 NodePath를 저장하지 않는다.

### SlimeState

    id
    definition_id
    display_name
    skill_memories: skill_id → SkillProgress
    memory_capacity
    routine: RoutineStep[]
    routine_cursor
    current_job: JobRuntime
    division_meter
    generation
    parent_ids
    fusion_tier

skill_memories와 routine을 분리한다.

- skill_memories: 슬라임이 실제로 보유한 스킬과 숙련도
- routine: 보유 스킬을 어느 대상에서 어떤 순서로 실행할지

MVP에서는 기억한 스킬 수와 루틴 길이를 모두 memory_capacity 이하로 제한한다.

### SkillProgress

    skill_id
    level: 1~5
    xp
    total_cycles

total_cycles는 N사이클마다 추가 생산 같은 예측 가능한 보너스 계산에 사용한다.

### RoutineStep

    job_id
    target_id
    order
    enabled
    blocked_reason

### JobRuntime

    phase
    routine_step_index
    cycle_id
    elapsed_ticks
    duration_ticks
    coaching_used
    blocked_reason
    reserved_inputs
    source_id
    destination_id

작업 단계:

    IDLE
    MOVING
    WORKING
    DEPOSITING
    BLOCKED

향후 운반을 추가할 때 PICKING_UP과 CARRYING을 추가한다.

### FacilityState

    id
    definition_id
    tier
    inventory_id
    enabled
    reserved_worker_ids

### InventoryState

    owner_id
    amounts: resource_id → int
    capacity_by_resource

모든 자원 추가, 소비, 이동은 InventorySystem만 처리한다.

---

## 6. 정적 콘텐츠 데이터

### SkillDefinition

    id
    display_name
    level_xp_requirements[5]
    level_speed_multipliers[5]
    level_bonus_every_n_cycles[5]
    animation_key

### JobDefinition

    id
    required_skill_id
    allowed_target_tags
    job_kind
    base_duration_ticks
    input_resources
    output_resources
    passive_xp
    normal_coaching_progress
    normal_coaching_xp
    perfect_window_ticks
    perfect_coaching_progress
    perfect_coaching_xp
    perfect_bonus_output

초기 job_kind:

- PRODUCTION
- CONSTRUCTION
- TRANSPORT: 데이터와 인터페이스만 대비하고 구현은 후순위

벌목과 채굴은 전용 코드를 각각 만들지 않고 같은 생산 작업 코드를 데이터만 바꿔 사용한다.

### FacilityDefinition

    tiers[]
      cost
      worker_slots
      inventory_capacity
      work_speed_multiplier
      unlocked_job_ids
      population_bonus

단순 생산량 증가보다 다음 기능 변화를 우선한다.

- 작업자 슬롯 증가
- 인구 한도 증가
- 새 자원과 공정 해금
- 합성 기능 활성화

---

## 7. GameSession 명령 API

UI는 다음 API만 호출한다.

    teach(slime_id, target_id, job_id) -> CommandResult
    set_routine(slime_id, routine_steps) -> CommandResult
    coach(slime_id, cycle_id) -> CommandResult

    preview_division(slime_id) -> PreviewResult
    commit_division(preview_token) -> CommandResult

    preview_fusion(slime_a_id, slime_b_id) -> PreviewResult
    commit_fusion(preview_token) -> CommandResult

    upgrade_facility(facility_id) -> CommandResult
    advance_ticks(tick_count)

실패는 사용자 문장이 아닌 안정적인 코드로 반환한다.

    OK
    INVALID_SLIME
    INVALID_TARGET
    TARGET_LOCKED
    FACILITY_FULL
    MEMORY_FULL
    COACHING_ALREADY_USED
    NOT_READY_TO_DIVIDE
    POPULATION_FULL
    INSUFFICIENT_RESOURCE
    INVALID_FUSION_PAIR
    FUSION_SKILL_LIMIT
    STALE_PREVIEW

UI가 오류 코드를 짧고 친근한 문장으로 변환한다.

---

## 8. 기능별 구현 가이드

### 8.1 슬라임 선택과 교육

규칙:

1. 슬라임을 누르면 선택한다.
2. 호환되는 작업 대상만 펄스 표시한다.
3. 대상을 누르면 작업을 습득하고 즉시 배치된다.
4. 이미 가진 스킬이면 숙련도를 유지하고 대상만 변경한다.
5. 기억이 가득 찬 상태에서 새 스킬을 가르치면 교체 결과를 확인받는다.
6. 작업 재배치로 숙련도는 사라지지 않는다.
7. 새 스킬로 기억을 덮어쓸 때만 기존 스킬과 숙련도를 잃는다.
8. 작업 변경 시 완료되지 않은 이전 사이클은 취소한다.

입력 구분:

    슬라임 선택 + 대상 터치
    → 교육 또는 재배치

    선택된 슬라임 없음 + 작업 코칭 링 터치
    → 코칭

교육 성공 후 선택을 자동 해제한다. 코칭 링은 모바일에서 최소 64px 터치 영역을 사용한다.

작업 항목:

- 선택·해제 상태
- 선택 외곽선과 호환 대상 강조
- teach 유효성 검사
- 첫 스킬 Lv.1 / XP 0 생성
- JobSystem의 시설 작업 슬롯 예약 시도와 자리 대기 처리
- 기억 교체 미리보기
- 성공·실패 이벤트
- 모바일 중복 입력 방지

완료 조건:

- 처음 보는 사용자가 30초 안에 슬라임 선택 → 나무 → 자동 벌목을 수행한다.
- 잘못 누른 한 번의 터치로 기존 숙련도가 삭제되지 않는다.
- 유효하지 않은 대상은 상태를 전혀 변경하지 않는다.

### 8.2 자동 작업

작업 흐름:

    루틴 선택
    → 시설 자리 예약
    → 작업 위치로 이동
    → 작업
    → 입력 자원 확정 소비
    → 출력 자원 지급
    → 숙련 XP와 분열 게이지 반영
    → 다음 루틴 단계

수리처럼 입력 자원이 필요한 작업은 시작할 때 자원을 예약한다. 작업이 취소되면 반환하고 완료되면 실제 소비로 확정한다.

초기 작업값:

| 스킬 | 기본 시간 | 결과 |
|---|---:|---|
| 벌목 | 5초 | 목재 +1 |
| 채굴 | 6초 | 수정 +1 |
| 수리 | 4초 | 목재 2·수정 1 소비, 방주 +1 |

첫 지역은 town_storage 공동 창고를 사용한다. 향후 운반을 위해 시설별 InventoryState와 try_transfer 인터페이스는 처음부터 준비한다.

막힘 처리:

- 재료 부족: 해당 작업 건너뜀
- 시설 슬롯 부족: 해당 작업 건너뜀 또는 한 단계 루틴이면 대기
- 저장 공간 부족: 생산 중단
- 잠긴 대상: 작업 중단
- 복합 루틴: 다음 실행 가능한 단계 탐색
- 모든 단계가 막힘: BLOCKED와 대표 이유 표시
- 상태 변경 이벤트 또는 1초 안전 주기로 재검사

완료 조건:

- 교육 후 입력 없이 1분간 안정적으로 생산한다.
- 자원은 완료 시 정확히 한 번만 지급된다.
- 작업 취소로 자원이 복제되거나 사라지지 않는다.
- 같은 입력 기록은 반복 실행해도 같은 결과를 낸다.

### 8.3 코칭

코칭은 연타가 아니라 한 작업 사이클에 한 번의 개입이다.

초기 규칙:

- 자동 완료: 숙련 XP +1
- 일반 코칭: 진행도 +15%, 추가 XP +1
- 정확한 코칭: 현재 사이클 즉시 완료, 추가 XP +3
- 작업 사이클당 코칭 1회
- 코칭하지 않아도 생산과 기본 XP 유지
- Lv.5 이후에도 작업 가속 효과 유지
- 코칭 자체는 분열 게이지를 추가로 주지 않음

정확한 코칭 구간은 작업 마지막 0.6~0.8초를 시작값으로 사용한다.

피드백:

- 코칭 가능 구간: 작업 링 펄스
- 일반 코칭: 작은 파동과 +숙련
- 정확한 코칭: 큰 눌림·튕김과 짧은 성공 문구
- 이미 사용: 다음 사이클까지 회색 링
- 선택하지 않은 슬라임의 코칭 신호는 약하게 표시

완료 조건:

- 한 사이클에서 여러 번 눌러도 첫 입력만 적용된다.
- 방치와 적극 코칭의 성장 속도 차이가 명확하다.
- 10분 플레이해도 연타 피로가 발생하지 않는다.

### 8.4 숙련도

숙련도는 스킬별로 독립 저장한다.

| 현재 레벨 | 다음 레벨 XP | 작업 속도 배율 |
|---|---:|---:|
| Lv.1 | 20 | ×1.00 |
| Lv.2 | 40 | ×1.10 |
| Lv.3 | 80 | ×1.25 |
| Lv.4 | 160 | ×1.45 |
| Lv.5 | 최대 | ×1.70 |

최소 작업 시간은 1.5초로 제한한다. 숙련 효과는 다음 사이클부터 적용한다.

MVP에서는 속도 증가만 활성화한다. 다음 확정형 보너스는 플레이 테스트 후 추가한다.

    Lv.3: 5사이클마다 추가 생산 +1
    Lv.4: 4사이클마다 추가 생산 +1
    Lv.5: 3사이클마다 추가 생산 +1

확률형 보너스는 사용하지 않는다.

완료 조건:

- 레벨은 항상 Lv.1~5 범위다.
- 재배치 시 같은 스킬 숙련도가 유지된다.
- 기억을 실제로 덮어쓰기 전에는 숙련도가 삭제되지 않는다.
- Lv.5에서 XP가 무한히 증가하지 않는다.

### 8.5 분열

세대와 분열 횟수는 무한하다. 동시에 존재할 수 있는 수만 제한한다.

분열 게이지:

    필요 작업 완료 횟수
    = 24 + 12 × (보유 스킬 수 - 1)

첫 시작 슬라임은 12/24로 시작시켜 첫 분열을 빠르게 경험시킨다.

조건:

- 분열 게이지 충족
- 현재 수 +1이 서식지 한도 이하
- 합성·분열 처리 중이 아님
- 예약 입력 자원을 안전하게 반환할 수 있음
- 유효한 스킬을 하나 이상 보유

실행 규칙:

    슬라임 1마리 → 2마리
    양쪽 모두 보유한 모든 스킬 레벨 -1
    최소 레벨 Lv.1
    양쪽 모든 스킬 XP 0
    양쪽 분열 게이지 0
    기억 용량과 스킬 조합 전승
    한 마리는 기존 루틴 재시작
    다른 한 마리는 대기
    총인구 +1

분열 전 상태 스냅숏 하나에서 두 결과를 계산한다.

미리보기 예:

    현재 인구 3/4 → 4/4
    벌목 Lv.4 → Lv.3 ×2
    채굴 Lv.2 → Lv.1 ×2
    경험치와 분열 게이지가 초기화됩니다.

미리보기에는 상태 버전 토큰을 붙인다. 이후 상태가 바뀌면 확정 요청은 STALE_PREVIEW로 거부한다.

완료 조건:

- 성공 시 개체 수가 정확히 +1이다.
- 정원이 가득 차면 게이지가 보존된다.
- 실패는 항상 무손실이다.
- 미리보기와 실제 결과가 완전히 같다.

### 8.6 총 슬라임 수 제한

| 단계 | 총수 한도 | 비용 |
|---|---:|---:|
| 기본 | 4 | 없음 |
| 확장 1 | 6 | 목재 20, 수정 8 |
| 확장 2 | 9 | 후속 지역 |
| 확장 3 | 12 | 후속 지역 |

MVP에서는 4→6까지만 구현한다.

- 정원이 가득 차면 분열 불가
- 분열 게이지는 가득 찬 상태로 보존
- 합성은 인구를 줄이므로 정원에서도 가능
- 슬라임 삭제 기능은 MVP에서 제공하지 않음
- 인구 한도는 서식지 정의에서 계산하고 중복 저장하지 않음

### 8.7 합성

두 슬라임을 소비해 하나의 복합 슬라임을 만든다.

조건:

- 서로 다른 두 슬라임
- 두 슬라임 모두 유효하고 잠기지 않음
- 예약 자원과 진행 중인 작업을 취소·환불 가능
- 결과의 서로 다른 스킬 수가 3 이하

서로 다른 스킬은 레벨과 XP를 그대로 보존한다.

    벌목 Lv.4 + 채굴 Lv.3
    → 벌목 Lv.4 / 채굴 Lv.3

같은 스킬:

    결과 레벨 = 더 높은 레벨
    결과 XP = 더 높은 레벨 부모의 XP

MVP에서는 XP를 합산하지 않는다. 분열과 합성을 반복해 XP가 복제되는 문제를 막는다.

기억 용량:

    일반 + 일반 → 2칸
    복합 + 일반 → 3칸
    최대 3칸

    result_capacity = min(3, max(parent_capacity) + 1)

스킬 합집합이 결과 용량보다 크면 합성을 막는다. 성공한 합성은 모든 스킬을 보존한다.

실행 결과:

- 부모 둘 제거
- 새 ID의 결과 슬라임 생성
- 분열 게이지 0
- 부모 ID 기록
- 기존 작업과 예약 취소
- 결과 루틴 비움
- 총인구 -1
- 플레이어가 새 루틴 설정

완료 조건:

- 합성은 완전히 결정적이다.
- 실패나 취소 시 상태가 변하지 않는다.
- 결과와 미리보기가 완전히 같다.
- 부모와 결과가 동시에 남는 반쪽 상태가 없다.

### 8.8 복합 루틴

복합 슬라임은 최대 3개 행동을 한 사이클씩 순서대로 수행한다.

    벌목 1회 → 채굴 1회 → 반복

MVP 루틴 UI:

- 아이콘 1~3개
- 좌우 버튼으로 순서 변경
- 슬롯 켜기·끄기
- 각 슬롯의 작업 대상 선택

실행 규칙:

1. 현재 슬롯 실행 가능 여부 검사
2. 가능하면 한 사이클 수행
3. 다음 슬롯으로 이동
4. 막히면 다음 활성 슬롯 검사
5. 모든 슬롯이 막히면 대기
6. 대표 막힘 이유 표시

조건문, 우선순위 수치, 반복 횟수 편집은 구현하지 않는다.

완료 조건:

- 2단계 루틴이 5분 동안 순서를 잃지 않는다.
- 막힌 단계가 다른 실행 가능한 단계를 영구적으로 막지 않는다.
- 모든 단계가 막혔을 때 원인을 확인할 수 있다.

### 8.9 시설과 재화

| 시설 | 기본 상태 | 첫 업그레이드 |
|---|---|---|
| 서식지 | 인구 4 | 인구 6: 목재 20, 수정 8 |
| 숲 | 슬롯 1 | 슬롯 2: 목재 12, 수정 4 |
| 광맥 | 목재 8로 시설·채굴 스킬·채굴 작업 해금, 슬롯 1 | 슬롯 2: 목재 15, 수정 6 |
| 합성소 | 비활성 | 방주 1단계 완료 시 활성 |
| 방주 | 수리 슬롯 1 | 첫 지역 목표 |

첫 수정이 공동 창고에 들어오면 수리 스킬과 방주 수리 작업을 해금한다. 이미 해금된 상태에서는 같은 보상을 다시 처리하지 않는다.

구매 처리:

    다음 단계와 선행 조건 확인
    → 모든 비용 보유 확인
    → 비용을 원자적으로 차감
    → 시설 단계 변경
    → 작업 슬롯·인구·해금 재계산
    → 이벤트 전달

재화 하나라도 부족하면 어떤 재화도 차감하지 않는다. 연속 터치로 같은 업그레이드를 두 번 구매하지 못하게 한다.

완료 조건:

- 모은 재화에 항상 다음 사용처가 보인다.
- 재화 소비가 슬라임 숙련도를 직접 올리지 않는다.
- 업그레이드 실패는 무손실이다.

### 8.10 방주 목표

방주는 시스템 확인용 첫 목표이며 세계관 확정 전 교체할 수 있다.

| 단계 | 수리 횟수 | 총 소비 | 보상 |
|---|---:|---:|---|
| 1단계 | 10 | 목재 20, 수정 10 | 합성소 활성화 |
| 2단계 | 18 | 목재 36, 수정 18 | 목표 외형 변화 |
| 3단계 | 30 | 목재 60, 수정 30 | 지역 완료 |

수리 슬라임은 재료가 있는 동안 자동으로 수리한다. 재료가 없으면 정확한 부족 자원을 표시한다.

완료 조건:

- 목표 3단계가 데이터로 정의된다.
- 각 단계 보상은 한 번만 발생한다.
- 첫 플레이 테스트에서 전체 목표를 15~20분 안에 완료한다.

---

## 9. UI/UX

### 기본 레이아웃

    상단
    목재 | 수정 | 슬라임 수/한도 | 방주 진척도

    중앙
    슬라임과 시설이 있는 연속형 월드

    하단
    선택한 슬라임 또는 시설의 상황별 카드

슬라임 카드:

- 이름
- 스킬 아이콘·레벨·XP
- 현재 루틴
- 작업 진행도
- 분열 게이지
- 준비됐을 때만 분열 버튼

시설 카드:

- 현재 작업자 수/슬롯
- 생산 또는 목표 진행도
- 다음 업그레이드 효과
- 비용과 부족한 재화

터치 기준:

- 주요 터치 영역 최소 48×48
- 코칭 영역 최소 64px
- 버튼 간격 최소 8px
- hover에만 의존하지 않음
- 선택 상태를 색상·외곽선·움직임으로 표시
- 빈 공간 터치로 선택 해제
- 두 번째 손가락 입력 무시
- 같은 터치에서 명령 한 번만 생성
- 노치와 브라우저 UI에서 중요 버튼 이격

막힘 문구:

- 목재 부족
- 수정 부족
- 작업 자리 없음
- 저장 공간 가득 참
- 대상이 잠겨 있음

---

## 10. 도메인 이벤트

GameSession이 틱 종료 후 다음 이벤트를 전달한다.

    assignment_changed(slime_id)
    job_cycle_started(slime_id, target_id, job_id, cycle_id)
    job_cycle_completed(slime_id, target_id, job_id, cycle_id)
    job_blocked(slime_id, reason_code)

    coaching_resolved(slime_id, result_type, gained_xp)
    proficiency_changed(slime_id, skill_id, old_level, new_level)

    inventory_changed(inventory_id, resource_id, old_amount, new_amount)
    population_changed(current, capacity)

    division_completed(source_id, result_ids)
    fusion_completed(parent_ids, result_id)
    facility_upgraded(facility_id, new_tier)
    goal_completed(goal_id)

이벤트에 Node 참조를 전달하지 않는다.

---

## 11. 저장

저장 항목:

    schema_version
    content_version
    build_version
    save_sequence
    saved_at_unix
    last_simulation_unix
    simulation_tick
    next_entity_number
    region_id
    slimes
    skill_memories
    routines
    division_meter
    facilities
    inventories
    goals
    unlocks

저장하지 않는 항목:

- 선택된 슬라임
- 열린 팝업
- 애니메이션 프레임
- 픽셀 좌표
- Node와 NodePath
- 계산 가능한 인구 한도
- UI 캐시

안전한 저장:

- save_a.json과 save_b.json을 번갈아 사용
- 저장마다 save_sequence 증가
- 저장 후 다시 열어 파싱 검사
- 로드할 때 유효한 파일 중 sequence가 높은 파일 선택
- 10~15초 디바운스 자동 저장
- 시설 구매, 분열, 합성, 목표 완료 직후 저장
- 앱 백그라운드 전환 시 저장 시도

마이그레이션은 v1→v2, v2→v3처럼 버전별 순수 함수로 연결한다. 첫 버전에서 오프라인 생산은 계산하지 않지만 last_simulation_unix는 기록한다.

---

## 12. 자동 테스트

### 공통 불변식

- 현재 슬라임 수는 0 이상 population_cap 이하
- 모든 자원은 정수이며 음수가 아님
- 숙련도 레벨은 Lv.1~5
- 기억한 스킬 수와 루틴 길이는 기억 용량 이하
- 기억 용량은 최대 3
- 작업 참조는 유효한 슬라임과 시설을 가리킴
- 합성으로 제거된 슬라임은 작업에 남지 않음
- 동일 ID가 두 번 존재하지 않음
- 분열 성공은 개체 수 정확히 +1
- 합성 성공은 개체 수 정확히 -1
- 구매 실패는 상태를 변경하지 않음
- 저장 콘텐츠 ID는 실제 정의와 연결됨

### 필수 테스트

교육·작업:

- 유효한 교육으로 스킬과 루틴 생성
- 유효하지 않은 교육은 무손실
- 같은 스킬 중복 생성 방지
- 작업 99%에서 재배치해도 결과 미지급
- 작업 슬롯 초과 방지

코칭·숙련:

- 사이클당 코칭 한 번
- 정확 판정 구간 경계
- XP 경계에서 정확한 레벨 상승
- Lv.5 초과 방지
- 숙련 효과는 다음 사이클부터 적용

분열:

- 준비되지 않은 분열 거부
- 정원에서 분열 거부 및 게이지 보존
- 모든 스킬 레벨 -1, 최저 Lv.1
- 양쪽 XP와 분열 게이지 초기화
- 오래된 미리보기 토큰 거부
- 실패 시 원본 보존

합성:

- 자기 자신과 합성 불가
- 서로 다른 스킬 합집합 유지
- 같은 스킬 XP 복제 방지
- 부모 제거와 결과 생성을 원자적으로 처리
- 미리보기와 결과 일치

시설·목표:

- 자원 부족 시 어떤 비용도 차감되지 않음
- 연속 터치 중복 구매 방지
- 해금과 보상은 한 번만 발생
- 서식지 확장 직후 분열 가능 여부 갱신

저장:

- 저장 후 로드한 상태가 원본과 동일
- 최신 슬롯 손상 시 이전 슬롯 복구
- 이전 버전 fixture 마이그레이션
- 분열·합성 직전과 직후 저장 왕복
- 정의되지 않은 콘텐츠 ID 안전 처리

### 결정론 테스트

동일한 초기 상태와 명령 기록을 다음 방식으로 재생한다.

- 한 틱씩 진행
- 여러 틱을 묶어 진행
- 렌더링 30FPS 가정
- 렌더링 60FPS 가정
- 중간 저장 후 재개

모든 최종 상태 해시가 같아야 한다.

---

## 13. 모바일 Web과 성능

기준:

- 일반 모바일 60FPS 목표
- 중저가 모바일 30FPS 이하로 지속 하락하지 않음
- 최대 12마리 기준
- 20분 플레이 후 메모리 지속 증가 없음

구현 지침:

- 슬라임마다 Timer를 만들지 않음
- 슬라임마다 개별 시뮬레이션 루프를 만들지 않음
- 중앙 시뮬레이션이 모든 슬라임 갱신
- 숫자 팝업과 파티클은 필요할 때 풀링
- 화면 밖 장식 애니메이션 정지
- Compatibility 렌더러 사용
- Web export는 초기 단일 스레드 사용
- PWA는 초기 비활성화

실기기:

- iPhone Safari
- Android Chrome
- 중저가 Android 한 대 이상
- 데스크톱 Chrome
- 데스크톱 Firefox

수동 극단 테스트:

- 초당 10회 연타
- 작업 완료 직전 재배치
- 정원 상태에서 연속 분열
- 작업 중인 슬라임 합성 시도
- 확인창 취소와 확정 반복
- 주요 상태에서 새로고침
- 5분 완전 방치
- 20분 일반 플레이
- 브라우저 백그라운드 후 복귀
- 화면 회전과 주소창 크기 변화

---

## 14. GitHub Actions

CI:

    Godot 버전과 export template 고정
    → 리소스 import
    → 헤드리스 도메인 테스트
    → 씬 스모크 테스트
    → Web release export
    → 출력 파일 검사
    → build artifact 업로드

Pages:

    main push 또는 수동 실행
    → 동일 테스트 통과
    → Pages artifact 업로드
    → 배포

테스트 실패 시 배포하지 않는다. Web 결과에는 index.html, JavaScript loader, wasm, pck가 모두 있어야 한다.

---

## 15. 구현 마일스톤

### M0. 기반

작업:

- 새 Godot 프로젝트
- Definition과 State 분리
- GameSession과 중앙 고정 틱
- 임시 도형 View
- 헤드리스 테스트 러너

완료 조건:

> 화면 없이 GameState를 생성하고 시간 진행과 상태 검사를 수행할 수 있다.

### M1. 교육과 자동 벌목

작업:

- 슬라임 선택
- 대상 강조
- 벌목 교육
- 이동·작업·반복
- 목재 창고
- 작업 슬롯

완료 조건:

> 교육 후 아무 입력 없이 1분간 목재가 안정적으로 쌓인다.

### M2. 코칭과 숙련도

작업:

- 작업 링
- 일반·정확 코칭
- 사이클당 1회 제한
- 숙련 Lv.1~5
- 레벨별 속도 반영

완료 조건:

> 방치와 적극 코칭의 성장 차이가 수치와 손맛에서 명확하다.

이 시점에 재미를 검증한다. 재미가 없으면 다음 시스템을 추가하지 않고 교육·코칭·작업 감각을 수정한다.

### M3. 분열과 인구 제한

작업:

- 분열 게이지
- 결과 미리보기 토큰
- 스킬 레벨 감소
- 개체 수 +1
- 정원 4
- 분열 실패 처리

완료 조건:

> 분열 결과가 항상 미리보기와 같고 실패는 무손실이다.

### M4. 경제와 지역 목표

작업:

- 수정 광맥
- 채굴과 수리
- 공동 창고
- 시설 해금과 작업 슬롯 업그레이드
- 서식지 4→6
- 방주 3단계

완료 조건:

> 자원 생산, 시설 확장, 목표 수리가 하나의 진행 루프를 만든다.

### M5. 합성과 복합 루틴

작업:

- 합성 대상 선택
- 결과 미리보기 토큰
- 스킬 합집합
- 기억 용량 2~3
- 루틴 정렬
- 막힌 단계 건너뛰기

완료 조건:

> 두 행동을 가진 슬라임이 5분 동안 안정적으로 순차 작업한다.

### M6. 저장과 온보딩

작업:

- A/B 저장 슬롯
- 세이브 버전과 마이그레이션
- 새로고침 복구
- 이벤트 기반 기능 노출
- 첫 15~20분 밸런스 조정

완료 조건:

> 새로고침 후 자원, 슬라임, 숙련, 루틴, 시설, 목표가 복원된다.

### M7. 모바일 Web 배포

작업:

- GitHub Actions 테스트
- Web export
- GitHub Pages 배포
- iPhone Safari와 Android Chrome 검수
- 20분 soak test

완료 조건:

> 모바일에서 첫 지역을 처음부터 끝까지 오류 없이 완료한다.

---

## 16. 범위 통제와 리스크

### 교육과 코칭 입력 혼동

- 교육은 선택 + 대상
- 코칭은 별도 작업 링
- 한 터치가 두 명령으로 처리되지 않게 함

### 합성 조합 폭발

- MVP 기억 용량 최대 3
- 숨겨진 조합 보너스 없음
- 스킬 조합별 전용 코드 없음
- 공통 작업 종류를 데이터로 구성

### 분열로 상태 폭증

- 세대는 무한
- 동시 개체 수 최대 12
- 첫 버전은 최대 6까지 실제 플레이
- 복합 슬라임은 스킬 수만큼 분열 요구량 증가

### 자동화 후 관전 문제

- 사이클당 한 번의 코칭
- 숙련과 분열 게이지
- 병목 작업 재배치
- 분열·합성 타이밍 선택
- 시설과 목표 사이 재화 배분

### 재미 검증 전 구조 과잉

- ECS를 만들지 않음
- 범용 행동 트리를 만들지 않음
- 빈 시스템 파일을 미리 만들지 않음
- M2 재미 검증 전 후속 시스템을 구현하지 않음

---

## 17. 개발 중 반드시 지킬 규칙

1. UI는 GameSession 명령만 호출한다.
2. 게임 상태에는 Node와 NodePath를 저장하지 않는다.
3. 자원 변경은 InventorySystem만 수행한다.
4. 분열·합성·업그레이드는 전체 조건을 먼저 검사하고 원자적으로 실행한다.
5. 분열·합성 미리보기와 실제 실행은 같은 순수 계산 함수를 사용한다.
6. 확률보다 플레이어가 예측할 수 있는 결과를 우선한다.
7. 기능 완료는 규칙 테스트, 실패 처리, 저장 왕복, 모바일 입력까지 포함한다.
8. 재미가 확인되지 않은 상태에서 후속 시스템을 추가하지 않는다.

---

## 18. 바로 다음 작업

첫 구현은 M0과 M1까지만 진행한다.

1. 새 Godot 프로젝트 생성
2. GameState, SlimeState, JobDefinition, GameSession 작성
3. 고정 틱 시뮬레이션 작성
4. 도형 슬라임 하나와 나무 하나 배치
5. 슬라임 선택 → 나무 터치 → 자동 벌목 구현
6. 목재 생산 결정론 테스트 작성
7. 모바일 터치와 Web export 확인

M1이 안정적으로 작동한 다음 M2 코칭과 숙련도를 구현한다.
