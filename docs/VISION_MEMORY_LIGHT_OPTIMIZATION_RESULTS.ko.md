# 시야·기억·광원 최적화 결과

- 작업 ID: `VISION-LIGHT-OPT-001`
- 기준 commit: `22245e0`
- protocol: `docs/VISION_MEMORY_LIGHT_OPTIMIZATION_PROTOCOL.ko.md`
- 상태: 완료

## 적용 결과

- `MEMORY` 지형의 불투명도를 `0.38 → 0.30`, 배경/전경 밝기 배수를 각각 `0.74/0.72 → 0.58/0.55`로 낮춰 발견한 지형 전체가 희미한 무채색 기억으로 남는다.
- 시야 밖 벽 횃불과 모닥불 표식은 낮은 불투명도의 정적 표식으로만 남는다. 광원 pool, 주변 타일 밝힘, 불꽃 glow와 flicker는 `VISIBLE`에서만 작동한다.
- 광원 LOS는 관측 projection cache 재구축 시 한 번 계산해 셀별 후보 목록으로 저장한다. 이후 조명 pool, 글자색 보정, 방사형 암흑 mesh의 반복 조회는 사전 계산된 후보와 거리 감쇠만 사용한다.
- 광원 pool 밝기는 고정하고 실제 불꽃 glyph만 제한된 주기로 움직이므로 조명 전체가 매 프레임 다시 계산되지 않는다.
- 인간·오크·기본 humanoid의 후방·주변 시야를 2셀로 늘렸다. 3셀째부터는 어두운 후방 시야 밖이다.
- 이동뿐 아니라 근접 공격과 대상/지점 기술도 행동이 처리되기 전에 대상 방향으로 `party.facing`을 갱신한다. 같은 턴 이후 관측은 이 방향을 사용한다.

## 검증 결과

- `tests/radial_darkness_acceptance.gd`: 통과
  - 동적 암흑/광원이 `VISIBLE` 밖으로 새지 않고, 반복 redraw와 광원 조회에서 LOS 계산 횟수가 증가하지 않음을 확인했다.
- `tests/facing_fov_refresh_acceptance.gd`: 통과
  - 이동 방향 FOV 회전과 전투 대상 방향 계산을 확인했다.
- `tests/run_darkness_compatibility.gd`: 13개 전부 통과
  - 후방 2셀, 3셀 차단, 횃불·암흑 저장 및 소모 회귀를 확인했다.
- `tests/field_turn_acceptance.gd`: 통과
- `tests/solo_start_acceptance.gd`: 통과
- `tests/run_party_ascii_visual_tests.gd`: 이번 변경 관련 테스트는 전부 통과했다. 전체 50개 중 기존 자산/선택 overlay 계약과 관련된 5개 테스트 함수는 기존과 동일하게 실패했으며 이번 시야·광원 변경 범위 밖이다.

## 한계

- 이 변경은 반복 LOS 계산을 제거하는 구조적 최적화다. 실제 기기별 프레임 시간은 브라우저/GPU 환경에서 별도 계측해야 한다.
- `MEMORY`는 마지막으로 본 정적 장면을 표현하며, 시야 밖의 적·위험·광원 변화는 실시간으로 갱신하지 않는다.
