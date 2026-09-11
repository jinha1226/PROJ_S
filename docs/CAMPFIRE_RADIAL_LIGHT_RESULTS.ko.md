# 바닥 모닥불 원형 광원 결과

- 작업 ID: `RADIAL-DARKNESS-003`
- 기준 commit: `3464c4a`
- protocol: `docs/CAMPFIRE_RADIAL_LIGHT_PROTOCOL.ko.md`
- 상태: 완료

## 구현 결과

- 정적 `landmark_camp`와 `fire_intensity > 0`인 바닥 불을 주황색 독립 광원으로 수집한다.
- 야영지 모닥불은 4.2셀 반경, 실제 바닥 불은 2.3셀 반경 안에서 세기에 비례해 부드럽게 감쇠한다.
- 모닥불 광원을 amber pool뿐 아니라 방사형 암흑 mesh alpha에도 합성해 암흑 위에서 실제로 밝게 보이게 했다.
- 이미 발견한 `landmark_camp`는 `MEMORY` 관측에 정적 표식으로 남으며 현재 시야 밖에서도 알려진 주변을 밝힌다.
- 공통 LOS 검사로 중간 벽을 통과하지 않고, `UNSEEN` 셀은 광원 대상에서 제외한다.
- MEMORY 모닥불은 고정된 밝기로 표시하고 현재 보이는 모닥불만 느린 flicker를 사용한다.

## 검증 결과

- `godot --headless --path . --script tests/radial_darkness_acceptance.gd`
  - 결과: 통과 (`RADIAL DARKNESS: []`)
- `godot --headless --path . --script tests/solo_start_acceptance.gd`
  - 결과: 통과 (`SOLO START: []`)
- `godot --headless --path . --script tests/run_party_ascii_visual_tests.gd`
  - 새 `test_ground_fire_lights_neighboring_known_tiles_and_actor_without_unseen_leak` 통과
  - 새 `test_landmark_camp_is_a_soft_radial_light_source` 통과
  - 이전 변경의 MEMORY 벽 횃불 회귀도 통과
  - 전체 결과: 50개 중 44개 테스트 함수 통과, 6개 실패
  - 잔여 실패는 기존의 색상 모드, 런타임 atlas, 선택 bracket, 픽셀 액터 asset/scale 기대값 불일치이며 이번 광원 변경과 무관하다.

## 보안·정보 경계

- 한 번도 발견하지 않은 `UNSEEN` 모닥불은 계속 관측 DTO에 나타나지 않는다.
- MEMORY에는 작성된 정적 야영지 표식만 보존하며, 변화 가능한 화염·피해·액터 정보는 보존하지 않는다.
