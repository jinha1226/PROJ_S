# Backview Duel Prototype

보스의 움직임을 읽고 거리 조절, 받아치기, 회피로 자세를 무너뜨리는 세로형 2D 백뷰 결투 프로토타입.

[브라우저에서 플레이](https://jinha1226.github.io/PROJ_S/)

현재 플레이 범위:

- 원근 투영을 적용한 앞뒤좌우 이동
- 보스를 향한 상시 록온과 백뷰 구도
- 수동 공격, 방향 회피, 타이밍 받아치기
- 플레이어와 보스의 별도 체력·자세 게이지
- 자세 붕괴 후 결정타
- 베기, 찌르기, 연속 베기, 휩쓸기 패턴
- 찌르기는 측면 이동, 휩쓸기는 회피로 대응
- 보스 예고 동작 중 슬로모션 집중 구간
- 모바일 터치와 PC 키보드 조작

조작:

- 모바일: 왼쪽 패드 이동, `ATTACK`, `DEFLECT`, `DODGE`
- PC: WASD/방향키 이동, J 공격, K/F 받아치기, Space 회피
- 빈 경기장 영역을 터치해도 받아치기를 실행한다.
- 방향 입력 없이 회피하면 자동으로 뒤로 빠진다.

세부 규칙은 [백뷰 결투 설계 문서](docs/BOSS_PROTOTYPE.md), 생성 에셋 기준은 [아트 에셋 문서](docs/ART_ASSETS.md)를 참고한다.

테스트:

    godot --headless --path . --script res://tests/test_runner.gd

이전 슬라임 자동화와 탑다운 보스전은 비교 및 Git 이력 보존 목적으로 남겨두었다. 현재 메인 씬은 `presentation/views/backview_duel_view.gd`를 사용한다.
