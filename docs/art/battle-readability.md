# 전투 가독성 · 순차 재생

현재 체크아웃의 오토배틀은 설계 단계다. 자동 진행 버튼이나 전투 규칙을 추가하지 않고, 층 모드의 기존 run_action에 공용 표시 경로를 연결했다.

- battle_presentation은 UI에서만 활성화한다. 아군 행동 종료·적 행동 종료·남은 환경 효과 뒤에 위치·HP·시야와 효과를 복사한다. 원본 액터와 RNG를 수정하지 않는다.
- board는 행동마다 준비 0.18초 → 타격/HP 갱신 → 마무리를 재생한다. 피해가 있는 행동은 0.68초, 나머지는 0.32초다. 전투 종료 화면은 마지막 연출 뒤에 갱신한다.
- 재생 중에는 새 run_action과 보드 행동 입력, 자동 탐색 진행을 막는다. 선택·설정에 의한 refresh도 마지막 연출까지 보류한다. HUD 요약은 재생 후 갱신하고, 보드의 HP는 각 타격 때 갱신한다.
- 외곽선은 캐릭터 전용 셰이더로 실제 투명 경계에 밝은 한 픽셀 선을 넣는다. 아군 원형 / 적 마름모 받침으로 위치·소속을 구분한다. 전투 효과와 HP는 별도 전경 레이어에 표시한다.
- 선택한 캐릭터만 실제 companion_choice의 다음 대상과 짧은 reason을 표시한다. 현재 수동 전투에서는 AI 판단 미리보기이며 플레이어 행동을 강제하지 않는다. 진행 중에는 미리보기를 숨긴다.

## 오토배틀 구현 연결

자동 루프는 board.is_presenting()이면 다음 auto_step을 호출하지 않는다. 배속 변경은 board.playback_speed에 1.0 또는 2.0을 넣는다. run_action(session.auto_step)을 통하면 캡처·재생 경로가 공통이다.

act를 act_as로 분리할 때는 각 아군의 원자적 행동이 끝난 뒤 presentation.capture(session, actor.id)를 유지해야 한다. 현재 위치는 finish_player_action 진입부다. 이 훅을 제거하면 한 라운드가 한 프레임으로 합쳐진다. 적 턴 훅은 enemy_attack_turn에 있다.

command_choice가 도입되면 다음 행동 미리보기도 실제 실행과 동일하게 command_choice 우선 → Tactics.choose 순으로 연결한다. 현재는 그 역할의 companion_choice를 호출한다.

tests/battle_presentation.gd가 기록 유무 전투 상태 동일성, 아군/적 순서, 준비 중 기존 HP 유지, 타격 시 HP 반영, 중복 실행 차단, 실제 AI와 미리보기 일치를 검증한다.
