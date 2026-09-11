# 육체 상태 기초 수치 표시 결과

- 작업 ID: `BODY-STATUS-UI-001`
- 기준 commit: `121215d`
- protocol: `docs/BODY_STATUS_SCALARS_PROTOCOL.ko.md`
- 상태: 완료

## 구현 결과

- 멤버 상세 `body_state` DTO에 피부 질김, 연부조직 완충, 뼈 골절 임계값, 충격 임계값, 의식 임계값을 실제 `body_scalars`에서 읽어 추가했다.
- 육체 상태 카드의 혈액을 비율만 표시하던 방식에서 `현재/최대 (비율)` 표시로 바꿨다.
- 피부 질김, 연부조직 완충, 뼈 강도, 현재/임계 충격, 상처 수와 기존 부위 상태를 함께 표시한다.
- 힘은 `근력 STR`을 유지하고 스트레스는 UI에서 `긴장 TNS`로 분리했다.
- 파티 초상 카드의 기존 스트레스 `STR` 표기도 `TNS`로 교체했다.
- 시뮬레이션, 피해 판정 및 저장 형식은 변경하지 않았다.

## 검증 결과

- `godot --headless --path . --script tests/body_status_scalars_acceptance.gd`
  - 권위 신체 수치와 상세 DTO의 정확한 일치를 확인했다.
  - 육체 상태 문구의 혈액 현재/최대, 피부, 연부조직, 뼈, 충격, 상처 항목을 확인했다.
  - 초상 자원 표기가 `HP`, `MP`, `TNS`이며 스트레스 의미의 `STR`이 없음을 확인했다.
  - 결과: 통과 (`BODY STATUS SCALARS: []`)
- `godot --headless --path . --script tests/solo_start_acceptance.gd`
  - 결과: 통과 (`SOLO START: []`)
- `godot --headless --path . --script tests/run_progression_tests.gd`
  - 이번 변경과 무관한 기존 fixture 및 UI 노드 기대값 불일치로 5개 중 3개 테스트 함수가 실패했다.
  - 전용 검증을 추가해 이번 변경 범위는 독립적으로 확인했다.
