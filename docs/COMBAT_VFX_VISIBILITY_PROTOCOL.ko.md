# 전투 시각효과 시야 차단 protocol

- 작업 ID: `COMBAT-VFX-FOV-001`
- 기준 commit: `3a7fd64`
- 사용자 관측: 벽 너머에서 NPC가 전투할 때 데미지 숫자가 화면에 표시되어 시야 밖 정보가 노출된다.

## 판정 계약

- `FLOATING_AMOUNT`, `MISS`, `HIT_FLASH`, `DEATH`, `MELEE_VFX`를 포함한 위치 기반 전투 효과는 대상 셀이 현재 `VISIBLE`일 때만 재생한다.
- `MEMORY`, `UNSEEN`, 화면 밖 좌표에서는 효과를 그리지 않는다.
- 단순히 카메라 viewport 안에 있는지는 FOV 판정이 아니다. 현재 관측 셀의 `visibility_state`를 함께 검사한다.
- 벽 뒤 NPC의 전투 결과는 시뮬레이션과 사건 기록에는 남지만 지도 위 실시간 효과로 노출하지 않는다.
- 이미 재생 중인 효과도 관측이 바뀌어 대상 셀이 `VISIBLE`이 아니게 되면 즉시 그리지 않는다.

## 검증

- 같은 화면 좌표라도 `VISIBLE`에서는 데미지 숫자가 보이고 `MEMORY`와 `UNSEEN`에서는 보이지 않아야 한다.
- 숨겨진 효과는 active effect 목록에도 들어가지 않아 불필요한 presentation clock을 만들지 않아야 한다.
- 재생 도중 셀이 `MEMORY`로 바뀌면 draw spec이 즉시 비가시 상태가 되어야 한다.
- 기존 전투 효과의 중복 방지와 가시 영역 표시 계약은 유지해야 한다.
