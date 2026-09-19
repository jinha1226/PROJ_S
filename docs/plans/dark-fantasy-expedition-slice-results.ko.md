# Dark Fantasy Expedition Slice 구현 결과

기준 계획: [dark-fantasy-expedition-claude-work-plan.ko.md](./dark-fantasy-expedition-claude-work-plan.ko.md)

## 구현된 범위

- `DarkFantasyExpeditionState`를 `PartyEncounterState`에 선택적으로 연결했다.
  - 원정 ID, 현재 방, 완료 방, 캠프 가능 여부, 캠프 CP, 구조 물자, 골드 정산 상태를 저장한다.
  - 멤버별 `stress`, `injury_ids`, `death_tokens`를 저장하고 JSON 저장/복원을 검증한다.
- `DarkExpeditionRules`를 추가했다.
  - 3개 방 진행, 캠프 진입/이탈, `HEAL`·`CALM`·`TREAT_INJURY`, 완료/안전 철수/비상 철수 정산을 제공한다.
  - 원정 중 피해·다운·사망 이벤트를 받아 Stress와 Injury를 갱신하고 이벤트 ID 중복 처리를 막는다.
- Stage Counterplay의 적 Intent를 라운드 계획 생성 시 한 번 결정하도록 고정했다.
  - 실행 시점과 UI 예측 시점이 같은 계획을 읽는다.
- 암흑 원정 시나리오를 3인 파티와 9방 구조로 부트스트랩했다.
  - 일반 종족 선택 모달에 `암흑 원정 시작 · 3인 파티` 버튼을 추가했다.
  - 방을 나갈 때 암흑 원정의 방 완료를 기록하며 기존 무료 회복은 적용하지 않는다.
- 세션 journal에 시작, 방 완료, 캠프, 캠프 행동, 정산을 기록하고 replay/save-load 경로를 연결했다.

## 검증

다음 수용 테스트를 통과했다.

```text
godot --headless --path . --script res://tests/dark_fantasy_expedition_acceptance.gd
DARK_FANTASY_EXPEDITION PASS

godot --headless --path . --script res://tests/stage_counterplay_acceptance.gd
STAGE_COUNTERPLAY PASS

godot --headless --path . --script res://tests/stage_map_acceptance.gd
STAGE_MAP PASS
```

암흑 원정 테스트는 3인 시작, 저장/복원, 이벤트 기반 Stress/Injury, 중복 이벤트, 캠프 CP 소비와 부상 멤버 치료, 세 방 완료, 정산, journal replay를 확인한다.

## 남은 범위

- 기존 전투 생명주기는 아직 `DOWNED`와 `DEAD` 전환을 직접 소유한다. `death_tokens == 3`을 실제 사망 조건으로 사용하는 최종 규칙은 다음 단계에서 전투 시스템과 통합해야 한다.
- 구조 물자 사용 API는 규칙 파일에 있으나 세션 명령과 journal 이벤트까지 완전히 노출하지 않았다.
- 캠프 `HEAL`은 canonical `camp_action`·`entity.recovered`·`health.restored` 이벤트를 사용하도록 연결했지만, 실제 전투에서 다운된 멤버를 대상으로 하는 별도 수용 케이스는 추가할 필요가 있다.
- 현재 캠프와 철수의 전용 화면 조작은 최소 진입점만 제공한다. 캠프 행동 버튼과 철수 결과 화면은 후속 UI 작업이다.
- 전체 레거시 원정 사이클 테스트에는 작업 전부터 있던 폰트 import 누락과 구 스키마 기대값 불일치가 남아 있다. 해당 실패는 이번 암흑 원정 변경의 수용 테스트와 분리해 추적한다.
