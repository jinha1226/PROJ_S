# 잿빛 원정

Godot 4.6으로 만든 모바일 세로 화면용 로그라이크 프로토타입입니다. `godot --path .`로 실행합니다.

현재 기본 플레이는 **한 번의 하강 Run**입니다. 주인공 한 명과 식량 2개로 1층에서 시작해, 절차 생성 층의 계단을 찾아 계속 내려갑니다. 주인공이 죽으면 도달 층, 처치 수, 실수 횟수를 결과 화면에 표시합니다. 마을·상점·유물 회수·귀환은 현재 플레이 흐름에 없습니다. 전투 시험은 시작 화면에서 따로 열 수 있습니다. [Run 설계](docs/superpowers/specs/2026-09-25-run-camp-npc-design.md) · [구현 계획](docs/superpowers/plans/2026-09-25-descent-run.md).

층은 80×80 타일, 방 13~16개와 폭 2칸 복도로 생성됩니다. 시야는 반경 5칸으로 고정되어 있고, 발견한 지형은 시야 밖에서 어둡게 남습니다. 발견한 타일을 탭하면 경로를 따라 한 칸씩 이동하며, 적이 보이거나 조사물·계단에 다가가면 멈춥니다. 미니맵을 탭하면 전체 지도를 볼 수 있고, 핀치 또는 휠로 카메라 범위를 조절할 수 있습니다.

식량은 **야영할 때만** 인원수만큼 소비합니다. 안전한 곳에서 야영하면 HP가 최대치의 절반만큼, 스트레스가 30 회복되고 파츠 쿨다운이 초기화됩니다. 파츠 장착·교체·해제는 야영 중에만 가능합니다. 버려진 보급 상자, 버섯 군락, 죽은 모험가, 부서진 궤짝을 조사해 식량·소모품·파츠를 얻을 수 있습니다. 짐승형 몬스터도 일정 확률로 식량을 남깁니다. 소모품은 치유 물약, 정신 안정제, 활력 물약, 화염 두루마리, 물 두루마리의 5종입니다.

3층마다 보스가 계단을 지킵니다. 수렁 포식자, 폭탄 암살자, 과부하 거인이 순서대로 등장하며 공격 예고가 일반 몬스터와 같은 전술 표시로 나타납니다. 보스를 쓰러뜨리면 봉인된 계단이 열리고 파츠를 얻습니다. 내려간 뒤에는 이전 층으로 돌아갈 수 없습니다.

전투에서 주인공은 이동·공격·파츠·준비한 주문을 한 행동씩 직접 고릅니다. 행동 시간에 따라 몬스터와 동료·NPC가 자율 행동하고, 적이 시야에 들어오면 자동탐험이 멈춥니다. 무기 5종과 마법 5종의 숙련은 사용 경험으로 오르며, 야영에서 장비와 준비 주문을 바꿉니다. 전투 시험도 수동 조작입니다. [전투 이식 설계](docs/superpowers/specs/2026-09-25-model-b-combat-port-design.md) · [첫 밸런스 기준선](docs/balance/model-b-gates.md).

캐릭터의 HP·스트레스, 성격, 중요한 기억과 성장 데이터는 Run 중 유지됩니다. 앱 종료 후 저장·불러오기는 아직 없습니다. [판타지 메카 컨셉](docs/fantasy-mecha-concept.md)은 기획 방향이며 현재 게임의 자산·용어 전환에는 적용되지 않았습니다.

## 검증

CI는 Godot 헤드리스 임포트, 테스트, 웹 내보내기를 실행합니다. 핵심 Run 테스트를 로컬에서 돌리려면:

```bash
godot --headless --path . --editor --import --quit
for suite in run_start camping floor_descent boss_floor integration playthrough solo_floor solo_balance floor_generator mobile_hud; do
  godot --headless --path . --script "res://tests/${suite}.gd"
done
```

`integration`과 `solo_floor`는 각각 100개 시드에서 층과 계단 배치를 검사합니다. `solo_balance`는 8개 시드의 1층 하강을 공개 행동으로 시험합니다. 측정값은 [Run 게이트](docs/balance/run-gates.md)에, 전체 CI 목록은 [.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml)에 있습니다.
