# Slime Automation — 테스트 계획

- 문서 버전: 0.2
- 기준 게임 규칙: IMPLEMENTATION_GUIDE.md 0.2
- 기준 기술 계약: TECHNICAL_SPEC.md 0.2
- 목적: 기능 완료와 배포 가능 여부를 객관적으로 판정

기능은 화면에서 한 번 작동한 것으로 완료하지 않는다. 성공 경로, 실패 경로, 상태 불변식, 저장 왕복, 모바일 입력을 모두 통과해야 한다.

---

## 1. 테스트 계층

### 도메인 테스트

- Node와 씬을 만들지 않는다.
- GameState, GameSession, System만 생성한다.
- 실제 시간과 렌더링을 사용하지 않는다.
- 고정 틱과 명령 목록으로 결과를 비교한다.
- 모든 핵심 규칙은 이 계층에서 먼저 검증한다.

실행 형태:

    godot --headless --path . --script res://tests/test_runner.gd

실패가 하나라도 있으면 exit code 1, 모두 성공하면 0을 반환한다.

### 씬 통합 테스트

- Main 씬 인스턴스 생성
- GameSession 이벤트와 View 연결
- 동일 이벤트로 UI가 한 번만 갱신되는지 확인
- 씬을 다시 열었을 때 신호가 중복 연결되지 않는지 확인
- 저장 상태에서 View가 재구성되는지 확인

### 브라우저 스모크 테스트

- index.html 로드
- Canvas 생성
- JavaScript, WebGL, 리소스 오류 없음
- 첫 터치 후 상태 변경
- 저장 후 새로고침 복원
- 브라우저 백그라운드 후 복귀

### 수동 플레이 테스트

- 첫 15~20분 세로 슬라이스
- 연타와 잘못된 입력
- 분열·합성 취소
- 저장과 새로고침
- 실제 iPhone과 Android

---

## 2. 공통 불변식

모든 명령과 시뮬레이션 틱 뒤 개발 빌드에서 검사한다.

| ID | 불변식 |
|---|---|
| INV-001 | 현재 슬라임 수는 0 이상 population cap 이하 |
| INV-002 | 자원은 정수이며 음수가 아님 |
| INV-003 | 숙련 레벨은 Lv.1~5 |
| INV-004 | Lv.5의 XP는 0 |
| INV-005 | skill memory 수는 memory capacity 이하 |
| INV-006 | routine 길이는 memory capacity 이하 |
| INV-007 | routine의 모든 skill은 실제 보유 |
| INV-008 | 작업은 존재하는 슬라임과 시설만 참조 |
| INV-009 | 동일 entity ID가 중복되지 않음 |
| INV-010 | 제거된 합성 부모가 시설 예약에 남지 않음 |
| INV-011 | reservation은 존재하는 작업과 연결됨 |
| INV-012 | goal 보상은 한 번만 지급 |
| INV-013 | 모든 content ID가 ContentRegistry에서 해석됨 |
| INV-014 | routine cursor는 유효 범위 |
| INV-015 | 분열 성공 시 인구 +1 |
| INV-016 | 합성 성공 시 인구 -1 |

상태 검사 실패는 개발 빌드에서 즉시 오류를 발생시키고, CI에서는 테스트 실패로 처리한다.

---

## 3. 테스트 Fixture

밸런스 변경으로 규칙 테스트가 깨지지 않도록 실제 콘텐츠와 분리된 fixture를 사용한다.

기본 fixture:

    tick duration: 0.1초
    logging duration: 10틱
    mining duration: 12틱
    repair duration: 8틱
    movement duration: 2틱
    passive XP: 1
    normal coaching: 진행도 20%, XP 1
    perfect window: 마지막 2틱
    perfect coaching XP: 3
    division requirement: 4회
    population cap: 4
    wood output: 1
    repair cost: wood 2, crystal 1

각 테스트는 새로운 GameState를 생성한다. 테스트 사이에서 singleton 상태나 저장 파일을 공유하지 않는다.

---

## 4. M0 상태와 시뮬레이션

### STATE-001 새 게임 초기 상태

사전 조건:

- 저장 파일 없음

실행:

- GameSession.new_game

기대:

- 슬라임 1마리
- population 1/4
- memory capacity 1
- skill 없음
- division meter 12, 실제 콘텐츠 기준
- wood 0, crystal 0
- forest enabled
- crystal mine locked
- 모든 불변식 통과

### STATE-002 ID 증가

실행:

- ID 3개 발급

기대:

- slime_000002, slime_000003, slime_000004
- 중복 없음
- 삭제 후에도 ID 재사용 없음

### SIM-001 틱 분할 결정론

실행 A:

- advance_ticks 100 한 번

실행 B:

- advance_ticks 1을 100번

기대:

- canonical state hash 동일

### SIM-002 렌더 FPS 독립

실행:

- 같은 명령 기록을 30FPS와 60FPS 형태의 틱 묶음으로 진행

기대:

- 최종 상태 hash 동일

### STATE-003 직렬화 왕복

실행:

- state to_dict
- JSON 직렬화·파싱
- GameState.from_dict

기대:

- canonical state 동일
- Node 또는 Callable 필드 없음

M0 게이트:

- STATE-001~003 통과
- SIM-001~002 통과
- headless command exit code 0

---

## 5. M1 교육과 자동 작업

### ASSIGN-001 첫 벌목 교육

사전 조건:

- skill 없는 slime_000001
- forest enabled, slot 비어 있음

실행:

- teach(slime_000001, forest, job_logging)
- advance_ticks 1

기대:

- logging Lv.1 생성
- routine step 하나
- forest 예약
- assignment_changed 한 번
- 성공 코드 OK

### ASSIGN-002 호환되지 않는 대상

실행:

- logging job을 ark에 교육

기대:

- INVALID_TARGET
- skill, routine, reservation 변화 없음

### ASSIGN-003 잠긴 시설

실행:

- mining job을 locked crystal_mine에 교육

기대:

- TARGET_LOCKED
- 상태 변화 없음

### ASSIGN-004 같은 스킬 재배치

사전 조건:

- logging Lv.3, XP 15

실행:

- 다른 logging target으로 재배치
- advance_ticks 1

기대:

- level과 XP 유지
- 이전 미완료 사이클 보상 없음
- 기존 예약 해제
- 새 target 예약

### ASSIGN-005 기억 가득 참

사전 조건:

- capacity 1
- logging 보유

실행:

- mining 교육 시도

기대:

- MEMORY_FULL
- 교체 preview payload 제공
- logging 삭제되지 않음

### JOB-001 완료 전 보상 없음

실행:

- logging 작업을 완료 1틱 전까지 진행

기대:

- wood 0
- XP 0
- division meter 변화 없음

### JOB-002 완료 시 한 번 지급

실행:

- logging 완료 틱 진행
- 추가 틱 진행

기대:

- wood 1
- passive XP 1
- division meter +1
- 같은 cycle에서 중복 지급 없음

### JOB-003 작업 취소

사전 조건:

- 작업 진행 90%

실행:

- 다른 target으로 재배치

기대:

- 이전 작업 output과 XP 미지급
- current job 교체
- 이전 facility 예약 해제

### JOB-004 시설 슬롯

사전 조건:

- forest slot 1
- slime A가 forest 사용 중

실행:

- slime B를 forest에 교육

기대:

- 교육 명령은 성공하고 routine이 생성됨
- JobSystem 시작 시 FACILITY_FULL blocked reason
- active worker 예약 수는 1을 넘지 않음
- 상태 불변식 통과

### JOB-005 입력 자원 예약

사전 조건:

- wood 2, crystal 1
- repair 시작 가능

실행:

- repair 시작 후 작업 취소

기대:

- 시작 시 reservation 생성
- 취소 시 wood 2, crystal 1 반환
- goal progress 0

M1 게이트:

- ASSIGN-001~005 통과
- JOB-001~005 통과
- 실제 화면에서 1분 무입력 벌목
- 첫 사용자가 30초 안에 교육 성공

---

## 6. M2 코칭과 숙련

### COACH-001 일반 코칭

사전 조건:

- WORKING
- perfect window 이전
- coaching_used false

실행:

- coach with current cycle ID

기대:

- 진행도 정의값만큼 증가
- 추가 XP 1
- coaching_used true
- NORMAL 이벤트

### COACH-002 정확한 코칭

사전 조건:

- remaining ticks가 perfect window 안
- coaching_used false

실행:

- coach

기대:

- completion_requested true
- 추가 XP 3
- 다음 simulation tick에 한 번만 완료
- PERFECT 이벤트

### COACH-003 연타 방지

실행:

- 같은 cycle에 coach 두 번

기대:

- 첫 요청 성공
- 두 번째 COACHING_ALREADY_USED
- XP와 진행도 한 번만 증가

### COACH-004 오래된 cycle ID

실행:

- 이전 cycle ID로 coach

기대:

- STALE_CYCLE 또는 INVALID_CYCLE
- 현재 작업 변화 없음

### COACH-005 비작업 상태

실행:

- IDLE slime coach

기대:

- NOT_WORKING
- 상태 변화 없음

### PROF-001 단일 레벨 상승

사전 조건:

- Lv.1 XP 19

실행:

- XP 1 지급

기대:

- Lv.2 XP 0
- proficiency_changed 한 번

### PROF-002 여러 경계 상승

사전 조건:

- Lv.1 XP 0
- 큰 테스트 XP 지급

기대:

- 요구량을 순서대로 차감
- 정확한 최종 level과 XP
- 각 레벨업 이벤트 순서 유지

### PROF-003 최대 레벨

사전 조건:

- Lv.5 XP 0

실행:

- XP 100 지급

기대:

- Lv.5 XP 0 유지
- 레벨업 이벤트 없음

### PROF-004 다음 사이클 적용

사전 조건:

- 작업 중간에 level 상승

기대:

- 현재 JobRuntime duration 유지
- 다음 cycle부터 새 speed multiplier 적용

M2 게이트:

- COACH-001~005 통과
- PROF-001~004 통과
- 코칭 없이도 생산 지속
- 적극 코칭이 방치보다 체감상 빠름
- 10분 플레이에서 연타 피로 없음

---

## 7. M3 분열과 인구

### DIV-001 정상 분열

사전 조건:

- population 1/4
- division meter 충족
- logging Lv.4 XP 10

실행:

- preview
- commit

기대:

- source 제거
- 결과 2마리
- 양쪽 logging Lv.3 XP 0
- 양쪽 division meter 0
- generation +1
- parent_ids에 source ID
- 한쪽 routine 유지, 다른 쪽 empty
- population 2/4

### DIV-002 Lv.1 하한

사전 조건:

- logging Lv.1

실행:

- 분열

기대:

- 양쪽 Lv.1 XP 0
- Lv.0 없음

### DIV-003 복합 스킬 감소

사전 조건:

- logging Lv.5
- mining Lv.2
- capacity 2

실행:

- 분열

기대:

- 양쪽 logging Lv.4
- 양쪽 mining Lv.1
- capacity 2 유지

### DIV-004 게이지 부족

실행:

- 요구량 미만에서 preview 또는 commit

기대:

- NOT_READY_TO_DIVIDE
- source 유지
- 상태 변화 없음

### DIV-005 정원 가득 참

사전 조건:

- population 4/4
- meter 충족

실행:

- 분열

기대:

- POPULATION_FULL
- meter 보존
- 인구 변화 없음

### DIV-006 오래된 preview

사전 조건:

- preview 생성

실행:

- 관련 상태 변경 후 기존 token commit

기대:

- STALE_PREVIEW
- source 유지

### DIV-007 작업 중 분열

사전 조건:

- repair 작업 중, 자원 reservation 존재

실행:

- 분열 확정

기대:

- reservation 반환
- 미완료 goal progress 없음
- 결과 두 마리 생성
- 한쪽 routine 재시작 가능

M3 게이트:

- DIV-001~007 통과
- 반복 분열로 cap 초과 불가
- preview와 결과 일치
- 실패 무손실

---

## 8. M4 경제와 목표

### ECON-001 광맥 해금

사전 조건:

- wood 8

실행:

- unlock crystal mine

기대:

- wood 0
- crystal mine enabled
- skill_mining enabled
- job_mining enabled
- unlock 이벤트 한 번

### ECON-002 비용 부족

사전 조건:

- wood 충분, crystal 부족

실행:

- habitat upgrade

기대:

- INSUFFICIENT_RESOURCE
- wood와 crystal 모두 변화 없음
- tier 변화 없음

### ECON-003 중복 터치

실행:

- 같은 upgrade command 빠르게 두 번

기대:

- 한 번만 성공
- 비용 한 번만 차감

### ECON-004 서식지 확장

사전 조건:

- habitat tier 0
- 비용 충분

실행:

- tier 1 upgrade

기대:

- capacity 4→6
- population 저장값을 직접 수정하지 않음
- population_changed 이벤트

### GOAL-001 수리 재료 부족

사전 조건:

- wood 1, crystal 1

실행:

- repair 시작 시도

기대:

- blocked reason WOOD_SHORTAGE
- 어떤 자원도 차감되지 않음

### GOAL-001A 첫 수정 해금

사전 조건:

- repairing과 ark repair가 잠김

실행:

- 첫 crystal을 town_storage에 추가

기대:

- skill_repairing 해금
- job_repair_ark 해금
- ark repair interaction 해금
- 같은 이벤트 반복 시 중복 해금 이벤트 없음

### GOAL-002 stage 완료

사전 조건:

- stage 1 progress 9
- 재료 충분

실행:

- repair 1회 완료

기대:

- progress 10
- stage 1 completed
- fusion pool enabled
- reward 한 번
- stage 2 활성

### GOAL-003 보상 중복 방지

실행:

- 완료 이벤트 재처리

기대:

- fusion pool 활성 상태 유지
- 보상 중복 없음

M4 게이트:

- ECON-001~004 통과
- GOAL-001, GOAL-001A, GOAL-002~003 통과
- 15~20분 밸런스 fixture에서 방주 완주 가능

---

## 9. M5 합성과 루틴

### FUS-001 서로 다른 스킬 합성

사전 조건:

- A logging Lv.4 XP 5, capacity 1
- B mining Lv.3 XP 7, capacity 1

실행:

- preview
- commit

기대:

- A와 B 제거
- 결과 1마리
- logging Lv.4 XP 5
- mining Lv.3 XP 7
- capacity 2
- routine empty
- division meter 0
- population -1

### FUS-002 같은 스킬 합성

사전 조건:

- A logging Lv.4 XP 2
- B logging Lv.3 XP 30

실행:

- 합성

기대:

- logging Lv.4 XP 2
- XP 합산 없음

### FUS-003 같은 레벨

사전 조건:

- A logging Lv.3 XP 10
- B logging Lv.3 XP 15

실행:

- 합성

기대:

- logging Lv.3 XP 15

### FUS-004 자기 자신

실행:

- A와 A 합성

기대:

- INVALID_FUSION_PAIR
- A 유지

### FUS-005 결과 용량 초과

사전 조건:

- 합집합 skill 수가 결과 capacity보다 큼

실행:

- preview

기대:

- FUSION_SKILL_LIMIT
- 부모 유지

### FUS-006 오래된 preview

사전 조건:

- preview 후 부모 XP 변화

실행:

- 기존 token commit

기대:

- STALE_PREVIEW
- 부모 유지

### FUS-007 작업 예약 반환

사전 조건:

- 부모 중 하나가 repair reservation 보유

실행:

- 합성

기대:

- reservation 반환
- 미완료 progress 없음
- 결과 생성

### ROUTINE-001 두 단계 순환

사전 조건:

- logging과 mining 보유
- routine logging→mining

실행:

- 충분한 틱 진행

기대:

- wood와 crystal이 번갈아 증가
- routine cursor 순환
- 순서 유실 없음

### ROUTINE-002 한 단계 막힘

사전 조건:

- repair 재료 부족
- logging 실행 가능
- routine repair→logging

실행:

- scheduler 진행

기대:

- repair skip
- logging 실행
- 전체 slime이 영구 정지하지 않음

### ROUTINE-003 모든 단계 막힘

기대:

- phase BLOCKED
- 대표 reason 표시
- 관련 자원 또는 시설 이벤트 후 재검사

M5 게이트:

- FUS-001~007 통과
- ROUTINE-001~003 통과
- 2단계 루틴 5분 soak test 통과

---

## 10. M6 저장과 온보딩

### SAVE-001 현재 버전 왕복

실행:

- 모든 주요 상태가 있는 snapshot 저장·로드

기대:

- canonical state hash 동일

### SAVE-002 A/B 복구

사전 조건:

- A sequence 10 정상
- B sequence 11 손상

실행:

- load

기대:

- A 선택
- 크래시 없음
- 복구 로그

### SAVE-003 future schema

사전 조건:

- 현재보다 높은 schema version

실행:

- load

기대:

- 안전한 거부
- 기존 메모리 상태 교체 안 함

### SAVE-004 migration, schema v2가 생긴 시점부터 활성

사전 조건:

- v1 fixture
- v1→v2 migrator

실행:

- load

기대:

- v2 상태로 변환
- validate 통과
- 새 슬롯에 재저장

현재 schema가 v1인 동안에는 이 테스트를 `PENDING_SCHEMA_V2`로 보고 M6 게이트에서
제외한다. schema_version을 올리는 변경은 migrator와 이 테스트를 동시에 추가해야 한다.

### SAVE-005 분열 전후

실행:

- 분열 직전 저장·로드
- 분열 직후 저장·로드

기대:

- 어느 경우도 중간 상태 없음
- 인구와 스킬 정확

### SAVE-006 합성 전후

분열 테스트와 같은 기준을 합성에 적용한다.

### ONBOARD-001 트리거 한 번

실행:

- 같은 조건 이벤트 여러 번 발생

기대:

- 온보딩 안내 한 번만 표시
- 완료 ID 저장

### ONBOARD-002 순서

실행:

- 정상 첫 플레이 이벤트

기대:

- 벌목 → 코칭 → 분열 → 광맥 → 수리 → 합성 순서
- 한 번에 두 개의 강제 안내 없음

M6 게이트:

- SAVE-001~006 통과
- ONBOARD-001~002 통과
- 브라우저 새로고침 복원
- 첫 플레이 15~20분 완주

---

## 11. M7 Web과 모바일

### WEB-001 export 파일

기대 파일:

- index.html
- JavaScript loader
- wasm
- pck

### WEB-002 직접 접속

기대:

- GitHub Pages URL 로드
- 리소스 404 없음
- Canvas 표시
- 콘솔 치명 오류 없음

### WEB-003 저장 새로고침

실행:

- 진행
- 저장
- 페이지 새로고침

기대:

- 이전 상태 복원

### TOUCH-001 단일 명령

실행:

- 한 번 터치

기대:

- touch와 emulated mouse로 명령 두 번 발생하지 않음

### TOUCH-002 탭과 드래그

실행:

- 포인터를 이동 임계값 이상 드래그

기대:

- 탭 명령 취소

### TOUCH-003 교육과 코칭 충돌

실행:

- SLIME_SELECTED 상태에서 coaching ring과 target 영역 경계 터치

기대:

- 우선순위 규칙에 따라 교육 또는 안전한 취소
- 두 명령 동시 실행 없음

### TOUCH-004 작업장 카메라

실행:

- 두 손가락 pinch in/out
- 확대 후 한 손가락 drag
- `− / 배율 / +` 버튼 입력
- 확대된 상태에서 슬라임과 시설 터치

기대:

- 터치 중심의 월드 좌표가 확대 전후 유지됨
- 카메라가 월드 바깥으로 이동하지 않음
- 배율 버튼으로 overview fit 복귀 가능
- 카메라 변환 후에도 슬라임·시설 hit test가 일치함
- touch 뒤 emulated mouse 입력으로 명령이 중복되지 않음

### PERF-001 최대 개체

사전 조건:

- 슬라임 12
- 모든 시설 작업 중
- HUD와 효과 활성

기대:

- 일반 기기 60FPS 목표
- 중저가 기기 30FPS 이하 지속 하락 없음
- simulation p95 예산 초과 없음

### PERF-002 메모리 soak

실행:

- 20분 정상 플레이

기대:

- View와 signal 누수 없음
- 메모리 지속 증가 없음
- 이벤트 queue 누적 없음

M7 게이트:

- WEB-001~003 통과
- TOUCH-001~003 통과
- PERF-001~002 통과
- iPhone Safari와 Android Chrome 수동 완주

---

## 12. 수동 탐색 체크리스트

- [ ] 초당 10회 연타
- [ ] 작업 완료 1틱 전 재배치
- [ ] 정원 상태에서 반복 분열
- [ ] 합성 대상 선택 후 취소
- [ ] 합성 preview 중 부모 상태 변화 시도
- [ ] 기억 교체 확인창 취소
- [ ] 자원 하나만 부족한 업그레이드
- [ ] 모든 루틴 단계 막힘
- [ ] facility slot 경쟁
- [ ] 주요 modal 상태에서 브라우저 백그라운드
- [ ] 주요 명령 직후 새로고침
- [ ] 5분 완전 방치
- [ ] 20분 일반 플레이
- [ ] 화면 회전
- [ ] 핀치 확대·축소와 확대 상태 드래그
- [ ] 확대 후 슬라임·시설 터치 정확도
- [ ] 브라우저 주소창 확장·축소
- [ ] 저장 불가 또는 사생활 보호 환경

---

## 13. 버그 우선순위

P0:

- 저장 손상 또는 진행 유실
- 자원 복제
- 슬라임 복제·소실
- population cap 초과
- 분열·합성 반쪽 상태
- Web 로드 불가

P1:

- 작업 영구 정지
- 숙련도 잘못 계산
- 시설 비용 부분 차감
- 코칭 반복 적용
- 모바일 입력 중복
- 목표 진행 불가

P2:

- UI 갱신 지연
- 잘못된 막힘 문구
- 애니메이션 끊김
- 레이아웃 오버플로

P3:

- 임시 도형 스타일
- 미세한 이펙트와 사운드 문제

P0과 P1이 하나라도 열려 있으면 다음 마일스톤으로 넘어가지 않는다.
