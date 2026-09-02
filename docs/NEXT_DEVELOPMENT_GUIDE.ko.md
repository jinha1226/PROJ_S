# 다음 개발 가이드

## 현재 완료 기준

2026-09-02 최신 `main`의 안정 경계는 world snapshot v9, 파티 조우 schema v17,
8방향 MOVE, environment/actor 이중 cadence, 최대 4인 동일-grid 파티와 4개 적,
파티 턴 원자 commit, 승리 턴의 zero-time 자동 재집결이다. Phase 5 명중·방어·상태·
다운/죽음, 장비·루팅, 플레이어블 5종족·종족 스탯과 격리된 신체 상태 B0 모델도 같은
`main`에 있다.

4인 파티 단체전투 시리즈는 다음까지 완료됐다.

- P1 동료 자율 전투: 연속형 HEXACO와 Utility AI로 `ENGAGE/PROTECT/RETREAT/HOLD` 선택
- P2 적 무리 전술: 전체 배치 파티 인지, 분대 focus/claim, 이동 목적지 예약
- P3 사기·공포: 권위 stress·`NORMAL/PANIC` 히스테리시스, 거리 전염과 안전 회복
- 자율 제어층: 개별 시야 → 파티 공유 → 자동 경고 → 주인공 행동의 암묵적 집중 표적
- 제품 예외 명령: 공격 대상 지정/후퇴/공격 중지/자리 지키기/따라오기만 권위 사건으로 제공
- 관찰 표면: `[NPC 관찰]`을 4 대 4로 확장해 `NEXT`, 경고, 가는 표적선과 판단 이유 표시

제품 자동 파티 전투에서 동료 선택은 관찰만 수행한다. 이후 빈 칸·적·방어 입력은 주인공
행동이며 개별 동료 override를 생성하지 않는다. 내부 override API는 기존 코어 계약과
회귀 비교를 위해서만 남긴다. 예외 명령 변경은 이미 본 파티 계획을 stale 처리하고,
`party.command_issued`와 세션 journal을 통해 save/load/replay에서 동일하게 재현된다.

현재 검증 기준은 파티 AI 20/20, 적 무리 전술 12/12, 파티 사기 9/9, Phase 4 89/89,
NPC 관찰 21/21이다. 12개 4인 파티 전투·190턴에서 rejected step과 invalid world는 0이다.

## 현재 고정 개발 순서

```text
완료: P1 동료 AI → P2 적 무리 전술 → P3 사기·공포
완료: 공유 인지·자동 경고 → 파티 관찰 UI → 예외 명령 5종 → 제품 개별 override 제거
다음: P4-1 화면 밖 축약 전투의 상세/축약 경계 + 순수 축약 라운드 평가기
이후: P4-2 권위 cadence·사건·save/replay
      → P4-3 상세 전투 복귀·관찰 DTO
      → P4-4 매트릭스·튜닝·제품 연결
```

다음 구현은 **P4-1만** 진행한다. 먼저 어떤 조우가 상세 동일-grid 전투에 남고 어떤 조우가
축약 대상인지 입력 계약으로 고정한다. 그 다음 현재 파티/적 HP·생명 상태·사기·HEXACO·
장비·전투 시간에서 한 축약 라운드의 제안 결과를 만드는 순수 평가기를 작성한다.
P4-1은 world, 사건, RNG, ID, journal을 쓰지 않으며 권위 피해도 적용하지 않는다.
같은 입력은 같은 정수 결과와 이유 trace를 반환하고, 입력/출력 DTO와 전환 거부 이유를
집중 테스트로 먼저 고정한다. 이 결과를 관찰·검토한 뒤에만 P4-2에서 실제 시간 진행과
권위 사건을 연결한다.

파티 자율 제어의 최신 계약은
`docs/superpowers/specs/2026-09-02-party-autonomy-perception-design.md`, P2/P3 계약은 같은
`docs/superpowers/specs` 폴더의 적 무리 전술·사기 설계를 따른다. 개인 성향·행동 AI의
연구 근거와 장기 확장 규칙은 `docs/PERSONALITY_BEHAVIOR_ARCHITECTURE.ko.md`를 따른다.
아래 절은 기존 코어와 장기 backlog의 세부 계약으로 유지하되, 현재 구현 우선순위는 위
P4-1~P4-4 순서가 우선한다.

### 1. TerrainRegistry·MOVE (완료)

- 타일의 통과 가능성·이동 비용·점유 규칙을 데이터 registry로 분리한다.
- `MOVE`는 플레이어와 NPC가 같은 명령 검증·실행 경로를 사용한다.
- 행동 비용은 `ActionTimingTable`에서만 정하고 명령이 임의 비용을 주입하지 못하게 한다.
- 경계 밖, 벽, 죽은 actor, 점유 충돌은 commit 전 무변경 거부한다.
- 동일 시각 다중 actor의 목표 충돌은 아직 player-step 비범위이며, 후속 자율 AI coordinator에서 예약 순서와 독립적인 명시적 동점 규칙을 먼저 고정한다.
- preview에는 이동 종료 시각과 이미 공개 가능한 예약만 표시한다.

안정 baseline 완료 상태: registry v1, 점유 producer/restore 대칭, 네 방향 MOVE, 지형 비용, start-commit, snapshot v3·timeline·JSON 재개 회귀로 고정했다. 8방향 MOVE와 snapshot v4는 Phase 3 정착 항목이다.

### 2. ExposureSample·종족 affinity (완료)

불만을 위한 특수 회피 코드를 만들지 않는다. 타일의 위험을 아래처럼 정규화된 자료로 샘플링한다.

```text
ExposureSample
  position
  sampled_step_index
  sampled_world_time
  next_environment_time
  terrain_id / passable / move_time_cost
  fire_intensity
  known_fire_damage_at_next_tick
  terrain_water_exposure / wetness / water_exposure
  conductivity
  electric_risk / electric_certainty
  poison_intensity       # 아직 0
  source_event_ids
```

종족·개체 성향은 위험 자체를 바꾸지 않고 해석을 바꾼다.

```text
HazardAffinity
  fire_tolerance
  water_tolerance
  electric_tolerance
  poison_tolerance
```

예를 들어 물에 강한 종족은 젖은 길을 낮은 위험으로, 물에 약한 종족은 높은 위험으로 평가한다. affinity는 이동 가능성이나 world-time 비용을 바꾸지 않는다. 최종 위험 점수는 정수 연산만 사용한다.

완료 상태: 동일한 ExposureSample을 human/amphibian/dwarf가 다르게 평가하고, shared fire projection·정적 물·동적 젖음·전도성 진단을 원본 환경 상태와 분리했다.

### 3. Playtest Sandbox 유지·시나리오 추가

- UI는 `PlaytestSession` detached API만 사용하고 simulator/world를 직접 읽지 않는다.
- 새 규칙을 추가할 때마다 작은 arena에 5분짜리 재현 시나리오와 상태·timeline 설명을 먼저 붙인다.
- 작은 32×48 arena는 최종 맵 크기 결정이 아니라 조작·카메라·규칙 검증 fixture로 유지한다.
- SAVE/LOAD와 seed·accepted command journal로 보고된 현상을 즉시 재현할 수 있게 한다.

완료 기준: 자동 회귀와 headless smoke가 통과하고, 5분 플레이 시나리오를 seed·journal·snapshot으로 다시 실행할 수 있다.

#### 3.1 PartyPlaytestSession route·inspection 계약

- `preview_exploration_route(goal)`은 현재 `WeightedPathfinder` 경로, 지형 비용과 각
  살아 있는 동행자의 4원소 위험 ceiling을 동결한 detached draft를 반환한다.
- `start_exploration_route(goal, plan_hash)`와 `continue_exploration_route()`는 호출당
  기존 인접 `SimCommand.MOVE`를 최대 하나만 제출한다. 순간이동, 별도 core command,
  `auto_walk` journal row는 없다.
- 매 hop 전에 phase·생존·현재 위치·weighted suffix·다음 이동 legality·위험 ceiling을
  다시 검사한다. 접촉·사망·새 점유/모서리 장애·경로 변화·위험 증가·core 거부에서
  즉시 멈추며, 이미 accepted된 prefix만 기존 `exploration` journal로 남는다.
- route draft/진행 상태는 snapshot과 save에 넣지 않는다. 정상 reset/load는 이를
  지우고, 잘못된 load는 live world·journal과 함께 그대로 보존한다.
- `combat_log(8, 80)`은 core event를 바꾸지 않고 step별 cause/instigator attribution을
  보존한 한국어 DTO를 반환한다. `inspect_tile(position, viewer_id)`와
  `inspect_party_member(id)`는 distant sample·affinity·관계·성격을 포함한 deep-detached
  projection이며 UI가 `sim/world`를 직접 읽는 우회로가 아니다.

#### 3.2 PartyEncounterSandbox 모바일 표시 계약

- 탐험 grid의 첫 tap은 `preview_exploration_route`만 호출하고 world·journal을 바꾸지
  않는다. 같은 goal+plan hash의 두 번째 tap은 첫 hop 하나만 시작하며, 이후 hop은
  `process_frame`마다 `continue_exploration_route`를 정확히 한 번만 호출한다. 새 타일,
  접촉, 패배, stale path, blocker, 위험 증가와 facade 거부는 동기 loop 없이 즉시
  cancel/stop feedback으로 전환한다. 전투의 MOVE는 기존 인접 한 칸 two-tap을 유지한다.
- `PartyGridView`의 route overlay는 facade가 준 전체 path를 detached copy로 받아
  반투명 tile highlight, segment, 숫자 없는 방향 chevron과 START/NEXT/GOAL marker를
  그린다. camera crop, world↔pixel mapping, FOV 의미를 바꾸지 않으며 창 밖 step은
  input surface가 아니다.
- `TileRiskPopover`는 grid 위 floating `PanelContainer`다. 폭은
  `min(280, viewport-24)`, font는 16px 이상이고 실제 wrapped line 수만큼 높이를 잡아
  viewport 12px 안으로 clamp한다. panel과 모든 child는 `MOUSE_FILTER_IGNORE`이며
  탐험 preview에서만 두 번째 tap 안내를 표시한다. 일반 선택 tap으로는 열리지 않고,
  빈 타일이나 actor 타일의 같은 지점을 약 500ms 길게 누를 때만 `inspect_tile`을
  호출한다. touch drag/mouse motion이 14px을 넘으면 tap과 long press를 함께 취소하며,
  long press를 소비한 release는 이동·대기·선택 signal을 다시 내지 않는다.
- grid pointer target은 press 때 exact cell, center-zone, 44px actor tie-break 순으로 한 번
  동결하고 짧은 release 때 그대로 emit한다. 짧은 tap은 release에서만 확정한다. 진행 중
  route는 pointer가 눌린 동안 pause하고, short release의 cancel/replan이면 재개하지 않으며
  slop을 넘은 drag도 실제 pointer release까지 pause ownership을 유지한다. drag cancel 또는
  long inspection의 release 뒤에는 다음 frame부터 한 hop씩 재개한다.
- 파티 card의 native `InputEventScreenTouch.double_tap` 또는 mouse double click과
  동일 card·350ms·24px fallback만 `MemberDetailModal`을 연다. scrim은 full viewport
  `STOP`, body margin은 12px, 폭은 360에서 최대 336px·450에서 최대 420px,
  close는 44px/18pt, scroll body는 16px 이상이다. 열려 있는 동안
  `grid.modal_open=true`이며 backdrop, close, Escape로 닫는다. route가 active면 modal
  동안 pause하고 닫은 다음 프레임부터 한 hop씩 재개한다. 첫 tap 선택과 두 번째
  double tap 사이에도 route draft를 지우지 않아 modal이 같은 진행 상태를 보존한다.
- `NarrativeLog`는 새 root sibling이 아니라 기존 `InformationScroll` 안에 두고
  `combat_log(8,80)`의 group/row 순서를 그대로 표시한다. 최신 combat commit 뒤 bottom을
  보이되 사용자가 위로 scroll해 최근 8턴 전체를 다시 읽을 수 있어야 한다.

### 4. 범용 안전 타일 선택 AI

- 인접 후보를 `통과 가능성 → 예상 exposure → 목표 진척 → 고정 좌표/방향 동점` 순으로 평가한다.
- 불·물·전기별 별도 도망 함수를 만들지 않는다.
- 선택 결과뿐 아니라 후보 점수와 탈락 이유를 진단 DTO에 남긴다.
- 아직 인지 시스템이 없으므로 테스트 fixture가 제공한 관찰 범위만 평가한다.
- AI가 실제 행동할 때는 플레이어와 같은 `MOVE` command를 제출하고 실행 직전에 재검증한다.

완료 기준: 같은 snapshot에서 같은 개체가 같은 이유로 같은 안전 타일을 고르며, 위험 종류가 추가되어도 선택기 구조가 변하지 않는다.

### 5. 불·물·전기 exposure 연결 확장

- 기존 `ExposureSample` 계약을 유지하며 새 원소 상태와 source certainty를 필드 단위로 확장한다.
- 화재는 이미 현재 세기와 다음 환경 cadence의 확정 피해를 공유 kernel로 계산한다. 이후에도 확률적 확산 성공을 예언하지 않는다.
- 젖음은 현재 물 affinity와 conductivity 진단에 연결돼 있다. persistent charge를 도입할 때만 별도 확정 전기 위험으로 연결한다.
- 전기 위험은 실제 방전 전에는 확정 피해처럼 preview하지 않는다.
- 감지하지 못한 위험은 UI preview와 AI 관찰 양쪽에서 숨긴다.

완료 기준: 물에 강한 종족은 합리적으로 물길을 택할 수 있고, 물에 약하거나 전기에 취약한 종족은 같은 타일을 피한다.

### 6. 독·DOT

- 독 구름·오염 타일과 개체 상태 효과를 같은 예약 코어의 serializable kind로 추가한다.
- 새 handler가 행동 구간 안에 예약을 만들 수 있게 하기 전에 preview occurrence 병합·공개 정책을 먼저 계약한다.
- DOT 피해는 공통 `DamageSystem`만 사용한다.
- cadence 직전 저장, 여러 틱을 넘는 느린 행동, source/cause 상속을 테스트한다.

완료 기준: 독이 플레이어 명령 횟수가 아니라 절대 world time에 따라 진행되고 중간 저장에도 중복·누락이 없다.

### 7. 인지·관계·기억

- 객관적 사건, 개체가 관찰한 결과, 관계 변화, 기억을 서로 다른 계층으로 둔다.
- 보지 못한 개체는 구조·피해를 관계에 반영하지 않는다.
- `instigator_id`는 객관적 책임자이지 관찰자가 정체를 안다는 뜻이 아니다.
- 기억은 사건 ID, 관찰 시각, 주체·대상, 중요도와 신뢰도를 보존한다.
- 관계는 계속 `종족 prior + 제한된 faction 보정 + 제한된 personal 보정` 순서를 지킨다.
- 강한 적대 종족 prior는 일반 도움 몇 번으로 즉시 우호가 되지 않으며, 장벽 해제는 유대·화해 같은 명시 상태로만 한다.

완료 기준: 구조를 실제로 본 수혜자만 감사가 생기고 종족 prior는 여전히 지배적이며, 저장·복원 후 기억과 인과가 같다.

### 8. 자율 동료 1명 → 최대 3명

- 먼저 동료 한 명에게 추종 거리, 위험 허용도, 후퇴 체력, 보호 대상 정책을 준다.
- 동료는 자율 의도를 만들지만 실제 행동은 공통 command·scheduler를 사용한다.
- 이후 최대 세 명으로 늘리며 같은 시각의 이동·목표 충돌을 고정 규칙으로 해결한다.
- UI preview는 감지 가능한 동료의 확정 예약만 노출하고 내부 의도나 숨은 적 예약을 누설하지 않는다.

완료 기준: 플레이어 한 명은 완전 통제되고 동료는 예측 가능한 규칙 안에서 자율적으로 움직이며, 동일 seed/command journal 결과가 같다.

## 성능 단계

기능 순서가 끝나기 전 청크 축약부터 만들지 않는다. 먼저 `64×64`, 개체 `50..100`, 혼합 비용 10,000+ world-time 실행에서 다음을 확인한다.

- 동일 seed·명령열 최종 snapshot/event hash 일치
- 잘못된 cause/source 참조 0
- overdue 예약 0, cadence 중복·누락 0
- 범위 밖 개체와 중복 사망 0
- 한 step occurrence budget 초과 0

그 뒤에만 활성 청크 정밀 시뮬레이션과 먼 지역 축약 시뮬레이션을 분리한다.

## 계속 지킬 비목표

이 순서가 끝나기 전에는 범용 ECS, 규칙 DSL, GOAP, 연속 유체, 멀티스레딩, 비동기 Timer, 완전 이벤트 소싱, 확률 결과를 소비하는 preview를 도입하지 않는다.
