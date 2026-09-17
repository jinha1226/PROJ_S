# Model B 구현 가이드

기준 legacy `d685c33`, 설계 `c08e338`, DCSS 분석 기준 `2bd8e06e6e5614a6f4917c1c24e04a8922319476`. 이 구현은 DCSS C++ 포트가 아니라 기존 Godot 코드 위에 설계 원리를 적용한 독립 프로토타입이다.

## 현재 범위

Model B를 먼저 완성한다. **신체 손상, 성격/동료 관계, 몬스터 흡수 이능은 신규 런에 연결하지 않는다.** 기존 코드와 legacy 저장/실행은 보존한다. 신앙 수호령은 성격 동료가 아니라 전술 소환수다.

## 실행 구조

`entry_router` → `game/crawl/game.tscn` → `game.gd` (입력/세로 UI/파일 저장) → `world.gd` (입력 검증/턴/전투/성장/영속 상태). `board.gd`는 기존 rebuilt 보드의 카메라·좌표·애니메이션을 상속하고 기존 타일/캐릭터 자산을 그린다. UI는 `submit()` 또는 안전 자동 동작을 통해서만 시간을 진행한다.

| 재사용 | 사용 목적 |
|---|---|
| `playtest/deterministic_dungeon_map.gd` | 시드 기반 방·복도 원형. 신규 런에서 교차 연결과 기둥/침수 vault 추가 |
| `sim/combat_kernel.gd` | 시야, 모서리 통과, 결정적 이벤트 순서 |
| `sim/turn_engine.gd` | 물리 방어, 가중 A* |
| `game/rebuilt/navigation.gd` | 추적 거리장, 안전 경로 |
| `game/rebuilt/board.gd` | 보드 좌표/카메라/이동 애니메이션 |
| `playtest/topdown_tile_assets.gd`, `fantasy_pawn_assets.gd`, 폰트·UI theme | 기존 승인 자산 |
| `sim/json_content_loader.gd` | JSON 데이터·정수 정규화 |

## 규칙과 데이터

`data/content/crawl.json`: 3종족, 10훈련축, 24적 원형, 12주문, 3신 계약, 7무기/4방어구/6반지, 8층 그래프. 방패는 단일 buckler. 정수 시간 100=보통 이동 1회. 공격 지연/장비 부담/종족 적성/저항을 같은 전투 계산에서 사용한다. RNG는 맵별 독립 seed와 저장되는 전투 stream을 분리한다.

상태는 런(레벨/훈련/인벤토리/신앙/룬/오브), 층(지형/발견/위험/물건/계단), actor(소속 층/HP/MP/행동시간/상태/AI)로 나뉜다. 층 재진입은 재생성이 아니므로 적·물건을 재생하지 않는다. 오브 귀환의 추격자만 층별 한 번 추가하며 XP 재료로 반복 생성되지 않는다.

HP·MP·AC·EV·SH와 중요한 상태는 상시 표시하고, 장비 부담·주문 실패·AI/저항은 상세 창으로 옮긴다. 아이템 식별과 잡동사니 수집은 제거/통합했다. 식량·횃불 수명·마을·기존 4축 성장도 신규 런에서 제외했다.

## 저장

`model_b_run_v1.json`: schema, seed/RNG string, clock, floors, actors, build state. 저장 전과 복원 전에 범위·참조·점유·장비·콘텐츠 ID를 검증한다. 복원 거절은 현재 런을 변경하지 않는다. JSON 숫자는 정규화해 좌표 문자열 키가 `615.0`으로 바뀌지 않게 한다. UI가 임시 파일→이전본 백업→rename으로 저장한다. legacy journal은 읽거나 덮어쓰지 않는다.

## 후속 모듈 경계

`integration_event`는 이동, 피해, 죽음, XP, 주문, 아이템, 층 진입, 목표·승리를 알린다. 이번 런은 이 신호의 구독자가 없다. 다음 단계에서 신체 손상/관계/흡수 adapter와 해당 보존 검증을 추가한다. 이 세 모듈의 이름만 신규 통계로 흉내 내지 않는다.

## 검증/CI

`tests/crawl/acceptance.gd`: 16 seeds × 8층의 연결/저장, 전투·훈련·저항·12주문·3계약, 안전 자동화, RNG 연속성, 잘못된 저장 거절, 두 룬→오브→귀환, 추격자, 사망 저장.

`tests/crawl/ui_smoke.gd`: 360×800, 450×800, 390×844, 800×450에서 보드/패널 생성과 저장. 이는 GUI 동작 smoke이며 픽셀 수준 가독성의 증명은 아니다. 실제 세로 웹 화면은 별도 브라우저에서 확인했다.

`model-b-tests.yml`: push/PR/수동 실행, 위 검증 + 공유 턴 엔진 + Web/Windows export + checkout 없는 pack 실행. 로그와 두 플레이 빌드 artifact를 14일 보관한다. Pages 권한/배포 job이 없다. 기존 main Pages 배포 workflow에도 Model B 검증 gate를 추가했다.
