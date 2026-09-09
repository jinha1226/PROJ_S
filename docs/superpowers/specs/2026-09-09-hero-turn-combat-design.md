# 주인공 턴제 전투 설계 (동료·적은 자동)

작성일 2026-09-09. 던전 전투의 시간 흐름을 "내가 움직여야 세계가 움직인다"로 되돌린다.
탐험과 같은 규칙이다. 동료와 적은 지금처럼 자기 판단으로 움직이고, 플레이어는 주인공
한 명의 행동만 고른다. 실시간 조작은 없다.

## 목표

- 주인공 차례마다 전투가 멈추고, 탭 한 번이 주인공의 행동 하나가 된다.
- 행동을 넣으면 주인공의 다음 차례까지 동료·적이 각자의 타임라인대로 자동으로 움직인다.
- 원장(저널·재생·스냅샷)은 지금의 행동 단위 스케줄러를 그대로 쓴다. 표시 정책과 예약 종류
  하나만 늘어난다.
- 기존 자동 진행은 토글로 남긴다(잔챙이 싸움 흘려보내기, 기존 테스트).

## 비범위

- 적 종류 추가, 파티 지침, 우두머리 조우, 결산 카드 (후속 조각)
- 동료 조작 확대(1회 지시는 기존 그대로)
- 시뮬 규칙(행동 시간·피해·판정) 변경

## 1. 시간 규칙

전투 시계(`autonomous_battle_clock`)는 표시 커서다. 지금은 `paused`가 아니면 항상 흐르고
스케줄러가 커서보다 앞선 이벤트를 순서대로 커밋한다.

새 규칙: 전투 모드가 `HERO_TURN`일 때, 다음 이벤트가 주인공이고 주인공에게 예약(스킬·
행동·이동 지시)이 없으면 커서는 그 시각에서 멈춘다. 이것을 **주인공 차례 대기**라 한다.
플레이어가 예약을 넣으면 커서가 다시 흘러 주인공 이벤트가 커밋되고, 다음 주인공 차례까지
동료·적 이벤트가 이어진다. 그 사이 표시 속도는 `HERO_TURN_UNITS_PER_SECOND`(초기값 400,
100시간당 0.25초)로, 자동 모드의 200보다 빠르다.

- 조우 시작 직후 주인공이 행동 가능하면 곧바로 주인공 차례 대기가 된다. 별도 진입 정지는
  없다(2026-09-09에 제거한 규칙 유지).
- 위험 정지(HP 25%)와 `[지휘]` 정지는 `AUTO` 모드에서만 동작한다. `HERO_TURN`에서는 항상
  내 차례에 멈추므로 필요 없다.
- `AUTO` 모드는 지금 동작 그대로다. 두 모드는 초상화 행의 버튼 하나로 전환하며
  (`자동`/`수동`), 세션이 아니라 샌드박스 설정이다. 기본은 `HERO_TURN`.

## 2. 주인공 행동 예약 — `reserve_action`

주인공(또는 어떤 파티원이든)의 **기본 행동**을 다음 이벤트에 예약하는 새 예약 종류다.
스킬 예약(`reserve_skill`)·이동 지시(`reserve_move`)와 같은 자리에서 소비된다.

```
individual_battle.reserve_action(actor_id, action) -> DTO
action := {"type":"MELEE","target_id":id} | {"type":"MOVE","destination":[x,y]} | {"type":"HOLD"}
저널 행: {"kind":"reserve_action","operation":{"actor_id":"7","type":"MELEE","target_id":"12"}}
        {"kind":"reserve_action","operation":{"actor_id":"7","type":"MOVE","destination":[x,y]}}
        {"kind":"reserve_action","operation":{"actor_id":"7","type":"HOLD"}}
individual_battle.cancel_action(actor_id)  저널 {"kind":"cancel_reserved_action",...}
```

- 예약 시 검증: ENGAGED, 활성·DEPLOYED, `can_act`, MELEE는 인접한 살아있는 적,
  MOVE는 인접 1칸이고 `coordinator._action_error`가 비어 있음, HOLD는 항상 가능.
- 실행(`Scheduler.step`): 그 액터의 이벤트에서 스킬 예약이 없고 행동 예약이 있으면
  `_ally_row`가 `_suggest` 대신 예약된 `PartyActionCommand`를 쓴다. 실행 시점에 다시
  `_action_error`로 검증하고, 실패하면 스킬 예약과 같은 방식으로 자동 행동으로 대체하고
  `reservation_rejection` 메시지를 돌려준다. 예약은 소비된다.
- 한 액터에는 스킬 예약과 행동 예약 중 하나만 둔다. 새 예약이 이전 예약을 덮는다.
- `AUTO` 모드에서도 같은 API를 쓴다(한 번 지시). 이동 지시(`reserve_move`, 도착 후 유지)는
  `AUTO` 모드의 맵 탭에 그대로 남는다.

## 3. 조작 (HERO_TURN, 주인공 차례 대기 중)

| 입력 | 예약 |
|---|---|
| 빈 칸 탭 (인접) | MOVE 그 칸 |
| 빈 칸 탭 (멀리) | 최단 경로의 첫 칸으로 MOVE. 한 탭에 한 걸음. |
| 적 탭 (인접) | MELEE |
| 적 탭 (멀리) | 그 적 쪽 경로의 첫 칸으로 MOVE |
| 자기 칸 탭 | HOLD (대기) |
| 스킬 버튼 → 대상 | 기존 `reserve_skill` |
| `자동` 버튼 | 모드를 `AUTO`로 전환하고 시계를 흘린다 |

- 대기 중이 아닐 때(시계가 흐르는 동안)의 탭은 다음 주인공 차례에 대한 예약으로 받는다.
  즉 미리 눌러 두면 차례가 오는 즉시 실행된다.
- 예약을 바꾸고 싶으면 다시 탭한다(덮어쓰기). 취소는 자기 칸 탭(HOLD)으로 갈음한다.
- 동료 탭은 지금처럼 인물창(1회 지시 포함)이다.

## 4. 표시

- 타임라인 바: 주인공 차례 대기 중이면 주인공 레인을 강조하고 바 왼쪽 라벨을 `내 차례`로
  바꾼다. 다른 액터의 다음 행동 예고는 이미 있는 레인 순서로 읽는다.
- 초상화 행의 정지 버튼 자리: `HERO_TURN`에서는 `자동`(모드 전환) 버튼, `AUTO`에서는 지금의
  `지휘/재개` 버튼과 그 옆에 `수동` 버튼.
- 맵 위 안내(`battle_notice`): 대기 중 `내 차례 · 칸/적/스킬을 고르세요`, 예약 후 시계가
  흐르는 동안은 비운다.
- 예약된 행동은 주인공 초상화의 금색 점(기존 스킬 예약 표시)과 맵의 대상 칸 테두리로 보인다.

## 5. 불변식

- 시계·모드·대기 상태는 저장하지 않는다. 불러오면 `HERO_TURN`이고, ENGAGED면 곧 주인공
  차례 대기가 된다(주인공 이벤트가 먼저 오지 않으면 그 앞 이벤트까지 흐른 뒤 멈춘다).
- 같은 저널은 두 모드에서 같은 세계를 만든다. 모드는 어느 이벤트를 언제 커밋할지의
  표시 순서만 바꾸고, 커밋 순서 자체는 스케줄러가 정한다.
- 행동 예약은 스킬 예약과 같은 규칙으로 저널에 남고 재생된다. `journal_wire_error`가
  모양을 검사한다.

## 6. 테스트

- `tests/test_individual_battle_scheduler.gd`(있으면 확장): MELEE/MOVE/HOLD 예약 실행,
  실행 시점 무효화 시 자동 대체와 `reservation_rejection`, 스킬 예약과의 배타, 저널 재생 동일.
- `tests/hero_turn_combat_acceptance.gd`(신규, 헤드리스 UI): 조우 → 주인공 차례 대기 →
  인접 적 탭 → 주인공 공격 이벤트 → 동료·적 이벤트가 흐른 뒤 다시 대기 → 먼 칸 탭이
  한 걸음만 → 자기 칸 탭이 HOLD → `자동` 전환 시 대기 없이 진행 → 저장/불러오기 후
  상태 동일.
- 기존 자동 진행을 전제로 한 스위트(`duo_autobattle_smoke`, `battle_command_flow_acceptance`,
  `battle_timeline_integration`, `battle_tap_move_regression`, `battleheart_mvp_acceptance`)는
  픽스처에서 `AUTO` 모드를 켠다. 위험 정지 계약은 `AUTO`에서만 검사한다.

## 파일별 변경 예상

- `sim/systems/individual_battle_scheduler.gd`: `step`이 행동 예약을 받는다.
- `playtest/individual_battle_session.gd`: `reserve_action`, `cancel_action`, `operation_error`,
  `hero_turn_pending()`.
- `playtest/party_playtest_session.gd`: 저널 재생·검증에 두 종류 추가.
- `playtest/autonomous_battle_clock.gd`: 속도 상수 분리(`units_per_second` 인자).
- `playtest/party_encounter_sandbox.gd`: `battle_mode`, 대기 판정, 탭 매핑, 버튼.
- `playtest/battle_command_flow.gd`: `AUTO` 전용 정지 정책으로 한정, 안내 문구.
- `playtest/battle_timeline_bar.gd` / `battle_timeline_presenter.gd`: `내 차례` 강조.
