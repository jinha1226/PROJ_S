# 화면 밖 NPC 장비 로그 수정 결과

상태: 완료

- 필드에서 파티 시야 밖에 있는 비파티 NPC의 장착·해제 사건을 최근 로그와 전투 기록에서 제외했다.
- 파티원 장비 로그와 마을 장비 로그는 유지한다.
- 종족 선택 모바일 터치 및 모든 종족 던전 진입 검증을 통과했다.
- 무작위 NPC의 능력치에 맞는 시작 무기를 지급해 던전 출발 롤백을 방지했다.

검증: `species_picker_start_regression`, `town_departure_randomized_acceptance`, `field_turn_ui_acceptance` 통과.
