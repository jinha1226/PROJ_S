# 신규 원정 출발 실패 수정

기준: `6f076bc`. 사용자에게 종족 선택 후 `town_departure_failed`가 표시됨.

## 원인과 재현

실제 시작 경로는 종족 선택 → 무작위 NPC 생성 → 마을 START → 던전 DEPART이다.
`dungeon_visitors_service.gd`가 빈손 NPC에게 단검을 무조건 지급·장착했다.
단검에는 DEX 4 요구치가 있으므로 무작위 NPC의 종족/재능에 따라 장착이 실패했다.
NPC 준비 실패가 전체 출발 트랜잭션을 롤백했고, 내부 `dungeon_visitors_failed`가
일반적인 `town_departure_failed`로 덮여 화면에 표시됐다.

world seed 40 / personality seed 20260828 / 인간·생활 시스템·솔로 시작에서
NPC 16의 `item_requirements_not_met`를 재현했다. 렌더링/타일 문제는 아니다.
이전 검증의 9방 테스트는 던전에 이미 들어간 fixture로 시작하여 실제 종족 선택 경로를 놓쳤다.

## 수정

- NPC의 실제 능력치로 단검 요구치를 검사하고 불가능하면 몽둥이를 검사한다.
- 둘 다 사용할 수 없으면 무기를 지급하지 않고 맨손으로 시작한다. 요구치를 무시하거나
  NPC 능력치를 강제로 올리지 않는다. 기존 장착 무기는 그대로 유지한다.
- 지급/장착의 진짜 내부 오류는 여전히 실패·롤백한다.
- DEPART가 내부 진입 실패 사유를 보존하도록 수정했다.
- 종족 선택 UI 테스트의 성격 난수 입력을 고정해 재현 가능하게 했다.

## 검증

Godot 4.6.2, 기존 Linux 검증본에 현재 수정 파일을 동기화하여 실행.
`town_departure_randomized_acceptance.gd` PASS: seed 40/41/44 실제 START/DEPART,
모든 장비 요구치 및 world audit, seed 40의 몽둥이 지급, 저장 저널 재생 상태 일치.
추가 seed 40~54의 15개 시작 경로 모두 PASS.
`species_picker_start_regression.gd`도 고정 난수 입력으로 PASS: 실제 viewport 터치,
5종족 진입·지도 잠금 해제·장비 요구치·중복 입력 방지, 실패 0건.
실제 모바일/웹 배포 검사는 별도이며 이번 수정으로 캐시나 기존 저장을 삭제하지 않는다.
