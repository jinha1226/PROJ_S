# 물약 지연·사망 시 확대 1차 점검

- 날짜: 2026-09-10
- 상태: 코드 정적 점검만 완료. 재현 측정·수정·회귀 테스트는 미완료.
- 당시 기준 커밋: `949a53e` 이후 작업 트리. 시야·아이템 등 다른 세션의 미커밋 변경이 다수 존재하므로 줄 번호보다 함수명을 기준으로 추적한다.

## 1. 물약 사용 지연 후보

`playtest/party_playtest_session.gd::_use_field_potion`은 `capture_rollback_memento()`의 기본 검증 경로를 사용하고, 시간 진행 뒤 `world_state_error()`로 전체 상태 검증을 수행한다. 이미 일부 필드 이동/휴식 경로는 `capture_rollback_memento(false)`와 `runtime_step_postcondition_error(event_start)`를 사용한다.

아이템의 게임 내 시간 비용은 `ITEM_ACTION_TIME_COST = 100`이다. 이 값은 실제 벽시계 입력 지연과 별개이므로, 렉을 줄인다는 이유만으로 비용을 0으로 바꾸지 않는다.

다음 측정을 먼저 수행한다:

1. 입력 처리 → preview_use → 롤백 사본/검증 → commit_use → 게임 시간 진행 → 사후 검증 → HUD/이펙트.
2. 새 게임과 긴 이벤트 이력이 있는 같은 시드의 부상 상황을 비교한다.
3. 전체 검증이 주원인으로 확인되면 실행 중 국소 검증으로 전환하되 아이템 소비·HP·회복 이벤트 검증을 유지한다. 저장/로드의 전체 검증은 유지한다.
4. 실패 시 롤백, 소모 1회, 회복 후 적 행동 순서, 구버전 replay, 전투 후 저장을 확인한다.

프로파일링 전에는 전체 검증이 지연의 확정 원인이라고 단정하지 않는다. 새 횃불·시야 계산과 HUD 전체 재생성도 시간 구간별로 함께 측정한다.

## 2. 사망 시 화면 확대 후보

`playtest/party_encounter_sandbox.gd::_current_grid_view_dimensions`는 `hero_skill_row.visible`에 따라 맵 가용 높이에서 48px를 빼거나 뺀 값을 되돌린다. `_render_hero_skill_row`는 상태에 따라 이 행을 숨길 수 있다. 사망/종료 전환에서 이 조건이 달라지면 줌 입력 없이 지도 영역·타일 크기가 변할 가능성이 있다.

확인할 값: 사망 직전/직후 viewport 크기, 루트 rect, grid rect, view columns/rows, cell size, zoom count, 스킬행/파티카드/명령행의 크기와 표시 상태.

후보 수정은 종료 시 플레이 화면의 높이/카메라 투영을 유지하고, 비활성 스킬행 공간을 보존하거나 종료 UI를 overlay로 표시하는 방식이다. 실제로 달라지는 레이아웃을 재현한 뒤 선택한다. 화면 확대 원인이 브라우저 viewport 변경이라면 별도 대응이 필요하다.

360/390/450px 너비와 실제 모바일 뷰포트에서 직전/직후 캡처를 비교한다. 재시작, 마을 귀환, 핀치 줌의 정상 동작을 함께 검사한다.

## 3. 현재 구현 보류 사유

수정 대상 `party_playtest_session.gd`, `party_encounter_sandbox.gd`, `party_grid_view.gd`, `world_state.gd`는 다른 세션이 시야·아이템 기능을 구현 중인 파일과 직접 겹친다. 사용자에게 작업 인계 또는 상대 작업 완료 여부를 확인한 뒤 수정한다. 이번 점검은 코드를 변경하거나 버그가 해결됐다고 보고하지 않는다.
