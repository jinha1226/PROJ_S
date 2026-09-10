# 적 인지·은신 단계 2 구현 결과

실험 ID: `LIGHT-VISION-002`
기준 구현 commit: `9735f4a`

## 구현 내용

- `PartyPlaytestSession.enemy_vision_overlay()`를 추가했다. 플레이어의 현재 공통 시야에 들어온 적만 후보가 되며, 오버레이 칸도 플레이어가 현재 보는 칸과 적의 `VisionRules` 결과의 교집합으로 제한된다.
- `PartyGridView.set_enemy_vision_overlay()`와 실제 셀 색상 오버레이를 추가했다. 상태별 색상은 `SUSPICIOUS`, `ALERT`, `HUNTING`, `SEARCHING`, `RETURNING`을 구분하고 식별 강도에 따라 투명도를 조절한다.
- 샌드박스에서 `V` 키로 오버레이를 켜고 끌 수 있다. 토글과 진단 질의는 RNG·시간·이벤트·저장 상태를 변경하지 않는다.
- 시야를 잃은 적은 `last_known_target_position`을 유지하고 그 위치를 조사한다. `RETURNING` 상태가 귀환 지점에 도착했을 때는 직접 필드를 바꾸지 않고 다음 권위 인지 갱신에서 `enemy.awareness_changed` 이벤트를 남긴 뒤 `UNAWARE`로 전환한다.

## 검증 결과

- 환경·시야·단계 2 테스트: 71개, 실패 0개
- 파티 AI·공통 인지 회귀: 12개, 실패 0개
- Phase 4 encounter·필드 턴·저장 회귀: 28개, 실패 0개
- 에디터 headless 클래스 스캔에서 `PartyEncounterSandbox`, `PartyGridView`, 세션·인지·시야 스크립트가 모두 로드됐다.

단계 2에서는 횃불 광원·연료, 원정 준비 UI, 어둠 스트레스를 구현하지 않았다. 오버레이는 실제 발각을 보장하는 표시가 아니라 현재 공통 질의에서 계산되는 탐지 가능 영역이다.
