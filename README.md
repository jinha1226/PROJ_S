# Slime Automation

직접 가르쳐 숙련시키고, 분열로 늘리고, 합성으로 행동을 조합하는 모바일 자동화 게임.

현재 상태: M0 기반 구현 완료. 교육과 자동 벌목(M1) 구현 준비 상태.

구현된 범위:

- Godot 4.6 모바일 Web 프로젝트 설정
- GameState, SlimeState, SkillProgress, InventoryState
- 정적 Definition 기본 클래스와 BalanceDefinition
- 10Hz 고정 틱 Simulation과 GameSession
- JSON 직렬화 왕복과 canonical SHA-256 상태 해시
- 초기 상태·ID·결정론 검증용 헤드리스 테스트

테스트:

    godot --headless --path . --script res://tests/test_runner.gd

구현을 시작할 때 다음 문서를 순서대로 읽는다.

1. [문서 인덱스](docs/README.md)
2. [설계·구현 가이드](docs/IMPLEMENTATION_GUIDE.md)
3. [기술 명세](docs/TECHNICAL_SPEC.md)
4. [테스트 계획](docs/TEST_PLAN.md)

기존 PROJ_G 낚시 프로젝트와 코드를 공유하지 않는다. Web export와 GitHub Actions 구성 방식만 필요할 때 참고한다.
