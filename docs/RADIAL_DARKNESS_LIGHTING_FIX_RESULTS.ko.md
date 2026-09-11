# 원형 조명 후속 수정 결과

- 작업 ID: `RADIAL-DARKNESS-002`
- 기준 commit: `9abd682`
- protocol: `docs/RADIAL_DARKNESS_LIGHTING_FIX_PROTOCOL.ko.md`
- 상태: 완료

## 구현 결과

- 벽 횃불 광원 판정을 `VISIBLE` 전용에서 이미 발견된 `MEMORY`까지 확장했다.
- 벽 횃불과 대상 사이의 알려진 지형을 따라 LOS를 검사하여 중간 벽 너머로 빛이 새지 않게 했다.
- `UNSEEN` 셀은 광원 및 암흑 그라데이션의 표본에서 계속 제외해 미발견 정보가 노출되지 않는다.
- 벽 횃불 주변의 암흑 alpha를 거리 기반으로 연속 합성하고, MEMORY 상태 횃불의 불꽃과 amber pool을 밝게 조정했다.
- 제품 가방 UI에서 횃불 장착이 성공하면 즉시 점화한다. 장착과 점화를 분리한 시뮬레이션 API, 연료 소모, 소화 및 저장 규칙은 유지했다.
- 기본 시야의 중심/외곽 alpha와 반경을 완화해 전 층을 조금 밝게 만들면서 깊은 층의 상대적 어두움은 유지했다.

## 검증 결과

- `godot --headless --path . --script tests/radial_darkness_acceptance.gd`
  - 360px와 450px에서 MEMORY 벽 횃불 주변 조명, UNSEEN 차단, LOS 벽 차단, 연속 방사형 mesh를 확인했다.
  - 결과: 통과 (`RADIAL DARKNESS: []`)
- `godot --headless --path . --script tests/run_darkness_compatibility.gd`
  - 횃불 장착 UI 자동 점화와 동적 광원 1개 등록을 포함한 13개 테스트를 확인했다.
  - 결과: 13개 통과, 실패 0개
- `godot --headless --path . --script tests/solo_start_acceptance.gd`
  - 제품 시작 흐름 회귀를 확인했다.
  - 결과: 통과 (`SOLO START: []`)

## 한계

- 한 번도 발견하지 않은 `UNSEEN` 벽 횃불은 관측 DTO에 지형 정보가 없으므로 의도적으로 표시하거나 조명하지 않는다. 이미 확인한 뒤 현재 시야 밖이 된 `MEMORY` 횃불만 독립 광원으로 보인다.
