# P4 — 화면 밖 축약 전투 설계

작성일 2026-09-02. 4인 파티 단체전투 시리즈의 4/4.

전체 파티 전투 단계의 완료/미완료 경계는
`docs/PARTY_COMBAT_IMPLEMENTATION_STATUS.ko.md`에서 관리한다.

구현 상태: **P4-1과 P4-2a 완료, P4-2b~P4-4 미구현**. P4-1은 상세/축약 전환 가능
여부와 한 축약 라운드의 예상 피해·이유 trace를 순수 계산한다. P4-2a는 이 출력을
독립 권위 상태에 원자적으로 반영하고 cadence·milli carry·사건·JSON save/replay·전역
처리 예산을 고정한다. 제품 `WorldState`의 entity HP/life와 actor cadence에 연결하는 bridge는
아직 없으므로 실제 플레이 경로의 world time, HP, journal은 변경하지 않는다.

## 목표

플레이어가 참여하거나 관찰하지 않는 먼 두 세력의 전투를 동일-grid 미시 턴으로 계속
렌더링하지 않고도 결정론적으로 진행할 기반을 만든다. 축약 전투는 별도 게임 규칙이 아니라
현재 HP·생명 상태·사기·HEXACO와 상세 전투에서 해결된 공격/방어 수치를 읽는 낮은 해상도
시간 처리다.

## 순차 범위

1. **P4-1 순수 평가:** 상세/축약 경계, strict 입력 DTO, 한 축약 라운드 예상 결과와 trace.
2. **P4-2a 권위 리듀서:** 축약 cadence, 예상 milli 누적/반올림 정책, 피해·다운·사망 사건,
   save/load/replay, atomic rollback과 호출당 전역 work budget.
3. **P4-2b 제품 bridge:** 기존 combat profile·장비·HEXACO 권위에서 입력을 투영하고,
   actor cadence에 도래한 활성 encounter만 리듀서에 제출해 world entity와 journal에 반영.
4. **P4-3 상세 복귀:** 플레이어 접근·관찰·참여 시 축약을 중단하고 권위 결과에서 상세
   동일-grid 전투를 재구성하는 경계와 관찰 DTO.
5. **P4-4 매트릭스:** 상세 전투와 축약 전투의 결과 편향, 정지, 복원 drift를 다중 seed로
   측정하고 제품 세계시간에 연결.

## P4-1 전환 계약

다음 조건을 모두 만족할 때만 `eligible_offscreen`이다.

- 정확히 두 세력이고 양쪽에 `ACTIVE` 구성원이 한 명 이상 있다.
- 조우가 이미 `ENGAGED`다. 접촉 생성과 전투 종료는 축약 라운드가 만들지 않는다.
- 주인공이 참여하지 않는다.
- 플레이어가 현재 전투를 관찰하지 않는다.
- 상세 시뮬레이션 반경 밖이다.
- 처리하지 않은 플레이어 선택이 없다.
- BLEEDING 같은 지속 상태가 없다. 상태 cadence 축약은 P4-2b 이후 별도 범위다.

거부 우선순위는 `encounter_not_engaged → protagonist_participates → player_observes_encounter →
inside_detailed_radius → pending_player_choice → unsupported_status → encounter_terminal`이다.
입력 자체가 strict DTO 계약에 맞지 않는 경우는 유효하지만 상세 전투가 필요한 경우와
구분해 `valid=false`로 반환한다.

## P4-1 입력

`PartyOffscreenCombatModel`은 world 객체를 직접 읽지 않고 아래 분리 DTO만 받는다.

```text
schema_version, encounter_id, encounter_phase, world_time, round_index
protagonist_participates, observed_by_player
within_detailed_radius, pending_player_choice
side_rows[2]
  side_id, command_id, target_id
  member_rows[]
    entity_id, health, max_health, life_state
    power, armor_flat, accuracy_milli, evasion_milli, attack_time
    stress_milli, mental_mode, status_ids
    hexaco {H,E,X,A,C,O}
```

`power`는 P4-2의 world projection이 기존 무기·스탯 계산기를 통해 제공할 해결된 공격
피해 기반값이다. P4 모델이 장비나 종족 스탯 공식을 복제하지 않는다. `attack_time`도 실제
장비/공격 형태에서 해결된 값만 받는다.

## P4-1 라운드 평가

- 입력 세력과 구성원 순서에 무관하게 side ID, entity ID로 정렬한다.
- `FOLLOW`는 평시 `PRESS`; PANIC 과반 또는 저체력·고 stress면 `WITHDRAW`다.
- `RETREAT`는 `WITHDRAW`, `STOP_ATTACK`은 `CEASE`, `HOLD_POSITION`은 방어적인 `HOLD`,
  `ATTACK_TARGET`은 공통 표적을 유지한다.
- 공통 표적이 없으면 HP 비율, armor, entity ID 순으로 약한 활성 대상을 고른다.
- 명중률은 `clamp(500 + accuracy - evasion, 50, 950)`이고, armor와 attack time을 반영한
  예상 피해를 HP 1/1000 단위인 `projected_damage_milli`로 반환한다.
- RNG roll, 실제 명중/빗나감, HP 감소, 다운·사망은 만들지 않는다.
- HEXACO E/C 회복탄력성은 cohesion/readiness 설명값에만 반영하며 숨은 명중 확률로
  사용하지 않는다. 고정 성격 유형은 없다.

## P4-2a 권위 계약

- `ROUND_TIME=100`이고 첫 due time부터 한 번에 한 라운드씩 진행한다.
- 같은 라운드의 impact를 대상별로 먼저 합산한 뒤 동시에 해결한다. 대상별
  `damage_remainder_milli=0..999`를 저장하고 `floor((carry+projected)/1000)`만 HP에 적용한다.
- 축약 범위에는 구조·지속 상태 cadence가 없으므로 치명 피해는 같은 라운드에
  `damage_resolved → entity_downed → entity_died`로 완결한다.
- 매 라운드는 `round_resolved`, 한 세력의 ACTIVE가 0이면 `encounter_resolved`를 남기고
  `next_round_at=-1`로 terminal 처리한다.
- 상태 wire의 ID/time/round는 canonical int64 문자열이고 전체 상태 해시를 포함한다.
  JSON round-trip 뒤 진행 결과, 사건, 해시는 중단 없는 실행과 동일해야 한다.
- caller state를 직접 변경하지 않는다. 입력 하나라도 잘못됐거나 commit 후 검증이 실패하면
  결과 전체를 거부한다. 관찰·상세 반경 등 P4-1 거부 조건은 `paused_rows`로 반환하며 시간을
  진행하지 않는다.
- 한 `advance_batch`의 전역 work budget은 최대 8라운드다. encounter 수나 밀린 시간에
  곱해지지 않으며 남은 due work는 `budget_exhausted=true`로 다음 호출에 이월한다.

이 예산은 플레이 입력의 최악 지연을 제한하기 위한 규칙이다. P4-2a는 제품 frame/step에
연결되지 않아 현재 runtime 비용이 0이다. P4-2b는 모든 NPC나 tile을 scan하지 않고 활성
화면 밖 encounter registry만 actor cadence에서 제출해야 하며, 기존 환경/actor 두 canonical
schedule을 늘리지 않는다.

## 현재 구현과 검증

- 모델: `sim/party_offscreen_combat_model.gd`
- 권위 상태: `sim/party_offscreen_combat_state.gd`
- 권위 리듀서: `sim/party_offscreen_combat_runtime.gd`
- 테스트: `tests/test_party_offscreen_combat_model.gd`,
  `tests/test_party_offscreen_combat_runtime.gd`
- runner: `tests/run_party_offscreen_combat_tests.gd`
- P4-1 집중 테스트: 전환 경계, strict wire, 순수성, 입력 순서 불변, 정수 예상 피해,
  예외 명령, PANIC, HEXACO 회복탄력성
- P4-2a 집중 테스트: milli carry 무편향, 피해/다운/사망/종료 사건, JSON 중단 재개,
  encounter 순서 불변, 40 encounter 전역 8라운드 예산, invalid/pause 원자성

P4-2b에서는 기존 world entity의 HP/life와 P4 상태가 동시에 권위가 되지 않도록 projection과
commit bridge를 하나로 만들어야 한다. P4-2a의 member HP는 bridge 완성 전 격리된 검증
권위이며, 이 상태만으로 제품 상세 전투를 건너뛰는 호출 경로를 추가해서는 안 된다.
