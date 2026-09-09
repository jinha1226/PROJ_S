# 화면 하나 전투 구현 계획

스펙: `docs/superpowers/specs/2026-09-10-single-screen-combat-design.md`

1. 시뮬 조우 규칙: `party_encounter_state` `legacy_contact_rule`(스키마 버전 상승), 코디네이터
   `_nearest_contact_enemy`/`_detect_contact` 경계 기반, `first_strike_contact(enemy_id)`,
   `world_state` 검증 분기. 테스트 `tests/awareness_contact_regression.gd`.
2. 세션 API: `strike_enemy(target_id)`(조우 전 선공/전투 중 인접 공격), `party_retreat()`,
   `skill_reach_cells(actor_id, skill_id)`, 조우 자동 배치 `settle_contact()`.
3. 샌드박스: 타임라인 바·컨트롤러·모드 토글·유틸리티 삭제, 독 5개, 스킬 줄, 피드 위치,
   붉은 칸, 적 탭·초상화 탭·퇴각, 조우 자동 처리.
4. 테스트 정리·신규 인수 테스트, 문서, 푸시.

## 구현 메모 (2026-09-10)

- 조우 규칙은 원정(DUO) 시나리오에서만 켠다(`legacy_contact_rule = not duo`). 단독 픽스처·쇼케이스
  시나리오와 스키마 23 이하 저장본은 시야 규칙 유지. 회귀: `tests/awareness_contact_regression.gd`.
- 지시(`issue_actor_command`)는 살아 있는 배치 인원이면 쿨다운 중에도 받는다(주인공 차례 대기 중 공격 지시).
- 삭제: `battle_timeline_bar/controller`, `hero_turn_combat_acceptance`, 타임라인 UI 테스트.
  `battle_timeline_presenter`는 세션 조회(`battle_timeline_state`)용으로 남는다.
- 새 인수 테스트: `tests/single_screen_combat_acceptance.gd`.
