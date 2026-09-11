# 전투 시각효과 시야 차단 결과

- 작업 ID: `COMBAT-VFX-FOV-001`
- 기준 commit: `3a7fd64`
- protocol: `docs/COMBAT_VFX_VISIBILITY_PROTOCOL.ko.md`
- 상태: 완료

## 원인과 수정

- 데미지 숫자의 draw spec이 현재 FOV가 아니라 카메라 viewport 포함 여부만 검사하고 있어, 화면 안의 `MEMORY`·`UNSEEN` 셀에서도 숫자가 보일 수 있었다.
- grid에 현재 관측 셀의 `visibility_state == VISIBLE`까지 확인하는 공통 판정을 추가했다.
- 위치 기반 효과는 등록 전에 이 판정을 통과해야 한다. 숨겨진 효과 ID는 소비 처리하여 나중에 해당 장소를 발견했을 때 과거 전투 효과가 재생되지 않는다.
- 이미 재생 중인 일반 전투 효과도 매 draw spec 생성 시 현재 관측 상태를 다시 검사하므로 시야에서 벗어나면 즉시 숨겨진다.
- 근접 공격 overlay도 재생 중 공격자나 대상이 시야에서 벗어나면 slash, flash, particle, 공격자 bump를 모두 숨긴다.
- 시뮬레이션 사건과 전투 결과에는 손대지 않았으며 지도 위 presentation만 차단했다.

## 검증 결과

- `godot --headless --path . --script tests/combat_vfx_visibility_acceptance.gd`
  - `VISIBLE` 데미지 숫자 표시, `MEMORY` 전환 즉시 숨김, `MEMORY`·`UNSEEN`의 숫자/빗나감/사망/근접효과 등록 차단 및 숨겨진 effect ID 소비를 확인했다.
  - 결과: 통과 (`COMBAT VFX VISIBILITY: []`)
- `godot --headless --path . --script tests/run_melee_vfx_overlay_tests.gd`
  - 근접 overlay 11개 회귀 테스트가 모두 통과했다.
- `tests/environment_vfx_acceptance.gd`, `tests/fireball_environment_acceptance.gd`, `tests/solo_start_acceptance.gd`
  - 환경 반응 효과, 화염구 효과와 제품 시작 회귀가 모두 통과했다.
- `godot --headless --path . --script tests/run_product_tests.gd`
  - 이번 변경과 직접 관련된 전투 effect, melee VFX, FOV 안전성 테스트는 통과했다.
  - 전체 184개 중 15개는 기존 런타임 atlas, HUD 노드, 선택 overlay, progression fixture 등 이번 변경과 무관한 계약에서 실패했다.
