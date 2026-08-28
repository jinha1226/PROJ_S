# 다음 개발 가이드

## 현재 완료 기준

2026-08-28 기준 Phase 3 성격·행동 실험실과 Phase 4 동일-grid 파티 조우가 완료됐다.
snapshot v5, 8방향 MOVE, environment/actor 이중 cadence, 최대 3인 파티 배치,
동료 제안/override, 파티 턴 원자 commit, 승리 턴의 zero-time 자동 재집결을 현재
안정 계약으로 삼는다. 360×640과 450×800 UI는 D-pad 없이 같은 15×15 world grid를
터치한다. 탐험·조우·배치 preview에서는 15×15 전체를, 배치 확정 뒤 전투에서는 같은
`PartyGridView` 인스턴스의 결정론적 9×9 camera crop을 보여 준다. actor와 intent의 필수
좌표 범위가 어느 축이든 9칸 창을 넘으면 같은 grid에서 원점 15×15 전체 창으로
fallback해 전원을 계속 보이고, compact cluster는 9×9를 유지한다. 승리·자동 재집결 뒤
원점 15×15 mapping으로 정확히 돌아온다. 이는 FOV가 아니라 표시 camera다. 큰 글씨,
두 번 탭 이동 미리보기/확정, 행동 overlay, HP·stress·준비·파생 감정을 갖춘 3인 동시
노출 Party HUD를 제공한다. ENGAGED에서만 정보 scroll 밖의 고정 하단
`CombatActionArea`가 보이며, 16px 자동 줄바꿈 `ActionFeedback` 아래 44px/18pt 행동
dock을 둔다. facade의 한국어 거부 `message`는 이 고정 feedback에 즉시 남고,
commit event에서 투영한 slash/hit/피해량/death 효과만 중복 없이 재생한다. 비인접
타일은 개발 sandbox의 결정론적 route macro로 미리 보고, 같은 목적지를 다시 누른 뒤
기존 1칸 `MOVE`를 호출마다 하나씩 실행한다. 이 route는 아직 FOV가 아닌 전체 world
기준이며 affinity로 경로 비용을 바꾸지 않는다. P1에서는 관찰 가능한 셀과 위험 선호를
이 실행 primitive 앞의 정책으로 추가한다. 전체 route 타일에는 반투명 highlight를,
각 edge에는 숫자 없는 방향 chevron을 그려 line과 START/NEXT/GOAL marker를 보강한다.
같은 타일을 약 500ms 길게 누를 때만 terrain·이동비용과 불/물/전기/독 위험을 detached
inspector DTO에서 읽은 floating popover로 띄운다. 짧은 tap은 popover를 열지 않으며,
popover의 모든 child는 touch를 통과시켜 그 다음 짧은 tap을 막지 않는다.
파티 card 첫 tap은 즉시 선택, 같은 card의 native double tap만 전체 화면 상세 modal을
열고 modal 동안 grid와 자동 경로를 막거나 일시정지한다. 전투 사건은
`InformationScroll`의 `전투 기록 · 최근 8턴`에 turn 경계, 이름, 피해 수치, 자동 동료의
공격·피해·사망 attribution을 보존해 표시한다.

`GROUPED_COMPLETE`의 `presentation_state()`는 transient UI 문구와 무관하게
`VICTORY` tone, `승리 · 자동 재집결` banner, green grid style을 계속 반환한다.
따라서 save/load 뒤 새 sandbox도 같은 승리 상태를 보이며 commit 효과는 재생하지 않는다.

- 유효한 플레이어 결정 수 `step_index`와 실제 경과 `world_time`이 분리됨
- 행동은 시작 시 commit되고 `(start, end]` 예약을 완전히 처리한 뒤 정착됨
- 환경 cadence가 절대시간 100 배수에서 drift 없이 실행됨
- `preview()`는 공개 예약만 표시하고 상태·RNG·ID를 바꾸지 않음
- snapshot v5가 registry ID·파티 조우·예약 큐·화재 eligibility와 모든 64비트 시간/ID 참조를 보존함
- 거부 입력과 overflow가 commit 전 전체 무변경으로 끝남
- terrain registry가 통과·점유·이동 비용의 유일한 authority임
- MOVE가 시작 시 commit되고 행동 구간의 환경 틱이 새 위치를 봄
- ExposureSample과 종족 affinity 평가가 세계를 바꾸지 않는 detached projection임

## 현재 고정 개발 순서

```text
완료: 시간/지형/노출 → Phase 3 성격 실험실 → Phase 4 최대 3인 파티 조우·UX
P0: 전투 규칙 v1 — 명중·방어·상태·다운/죽음
P1: FOV/LOS·미니맵 → 관찰 범위·affinity를 반영한 안전 경로 정책
    → 동료 성격/관계/체력 임계 행동
P2: multi encounter·몬스터 영역/무리/생태·세계시간
    → 아이템/장비/루팅 → 목격/기억/소문
```

- P0 완료 기준: 같은 파티 턴에서 명중·방어·상태·다운/죽음의 preview/commit/event/snapshot이 결정론적으로 일치하고 플레이 가능한 한 전투가 끝난다.
- P1 완료 기준: FOV/LOS가 공개한 타일만으로 먼 타일 auto-walk와 affinity 안전 경로를 계획하며, 동료의 성격·관계·현재 HP가 예고된 행동과 실제 행동에 같은 근거로 반영된다.
- P2 완료 기준: 여러 조우와 몬스터 영역·무리 상태가 세계시간에 따라 이어지고, 전리품과 목격·기억·소문이 save/load 뒤에도 같은 인과 사슬을 보존한다.

Phase 3의 구현 계약은 `docs/PHASE3_DUNGEON_PERSONALITY_LAB_IMPLEMENTATION_PROMPT.ko.md`,
Phase 4의 현재 계약은 `docs/PHASE4_PARTY_ENCOUNTER_DEPLOYMENT_IMPLEMENTATION_PROMPT.ko.md`의
최상단 UX 개정을 따른다. 개인 성향·행동 AI의 연구 근거와 장기 확장 규칙은
`docs/PERSONALITY_BEHAVIOR_ARCHITECTURE.ko.md`를 따른다. 마을 구현 문서는 보류된
backlog다. 기존 아래 절 번호는 장기 설계 원칙으로 유지하되 실제 우선순위는 위 P0–P2다.

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
