# Slime Automation

직접 가르쳐 숙련시키고, 분열로 늘리고, 합성으로 행동을 조합하는 모바일 자동화 게임.

현재 상태: M0~M2 플레이 구현 완료. 교육, 자동 벌목, 코칭, 숙련 성장이 동작한다.

[브라우저에서 플레이](https://jinha1226.github.io/PROJ_S/)

구현된 범위:

- Godot 4.6 모바일 Web 프로젝트 설정
- GameState, SlimeState, SkillProgress, InventoryState
- 정적 Definition 기본 클래스와 BalanceDefinition
- 10Hz 고정 틱 Simulation과 GameSession
- JSON 직렬화 왕복과 canonical SHA-256 상태 해시
- 초기 상태·ID·결정론 검증용 헤드리스 테스트
- 슬라임 선택 → 숲 터치 방식의 벌목 교육
- 시설 작업 슬롯, 이동, 5초 벌목, 자동 반복 생산
- 사이클당 한 번의 일반·정확 코칭
- 벌목 숙련 Lv.1~5와 작업 속도 반영
- 모바일 터치용 작업장 UI와 진행 피드백
- 전체 시설과 이동 경로를 한눈에 보는 탑다운 작업장
- 자동 진행 오버뷰와 슬라임 선택형 집중 코칭 모드
- 코칭 타이밍 원형 신호와 고정 틱 사이 렌더 보간
- 코칭 성공 시 충격파·점프·파편·진동 피드백

테스트:

    godot --headless --path . --script res://tests/test_runner.gd

구현을 시작할 때 다음 문서를 순서대로 읽는다.

1. [문서 인덱스](docs/README.md)
2. [설계·구현 가이드](docs/IMPLEMENTATION_GUIDE.md)
3. [기술 명세](docs/TECHNICAL_SPEC.md)
4. [테스트 계획](docs/TEST_PLAN.md)

기존 PROJ_G 낚시 프로젝트와 코드를 공유하지 않는다. Web export와 GitHub Actions 구성 방식만 필요할 때 참고한다.
