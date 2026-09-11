# 이동 방향 시야 갱신 결과

- 작업 ID: `VISION-FACING-001`
- 기준 commit: `183365a`
- protocol: `docs/FACING_FOV_REFRESH_PROTOCOL.ko.md`
- 상태: 완료

## 원인과 수정

- 필드 턴 시스템이 진형이 `NONE`이 아닐 때만 파티 `facing`을 갱신하고 있었다.
- 제품의 기본 자유 진형은 `NONE`이므로 캐릭터가 이동해도 권위 방향이 초기값인 오른쪽에 고정됐다.
- 모든 성공한 필드 `MOVE`가 실제 이동 벡터로 `party.facing`을 갱신하도록 조건을 제거했다.
- 기존 시야 관측 캐시는 위치·방향·파티 revision을 key로 사용하므로 이동 직후 새 방향으로 FOV가 다시 계산되고 grid 관측 DTO에도 전달된다.

## 검증 결과

- `godot --headless --path . --script tests/facing_fov_refresh_acceptance.gd`
  - 자유 진형 이동 후 권위 방향 변경, 시야 cone 회전, debug 관측 및 grid DTO 방향 전달을 확인했다.
  - 결과: 통과 (`FACING FOV REFRESH: []`)
- `godot --headless --path . --script tests/field_turn_acceptance.gd`
  - 이동·대기·전투·저장 재현을 포함한 필드 턴 회귀를 확인했다.
  - 결과: 통과 (`FIELD TURN: PASS []`)
- `godot --headless --path . --script tests/body_status_scalars_acceptance.gd`
  - 직전 육체 수치 및 `TNS` 변경이 유지되는지 확인했다.
  - 결과: 통과 (`BODY STATUS SCALARS: []`)
