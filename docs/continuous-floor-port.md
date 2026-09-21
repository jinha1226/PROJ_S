# 연속 1층 이식 기록

## 적용 범위

기본 실행은 `Session.new(seed, true, true, true)`로 연속 층 모드를 사용한다.
원본은 100×100이 아니라 48×48이다. 원본 생성 결과의 각 칸을 2×2로
확대하고 외곽 2칸을 추가해 100×100을 구성한다. 분기 통로, 지형,
보급 위치, 5개 적 무리(총 9마리), 입구와 심부 출구 배치를 유지한다.
이전 3×3 탐험과 보스 모드는 테스트 호환용으로 남아 있지만 기본 UI에서는 쓰지 않는다.

## 가져온 원본

| 원본 (`../` 기준) | 프로젝트 내부 | 변경 범위 |
|---|---|---|
| `playtest/four_zone_floor.gd` | `expedition/legacy/four_zone_floor.gd` | 의존 경로 변경, 사용하지 않는 preload 제거 |
| `playtest/tactical_terrain_layout.gd` | `expedition/legacy/tactical_terrain_layout.gd` | 원본 그대로 |
| `playtest/party_minimap.gd` | `expedition/legacy/party_minimap.gd` | 전역 클래스명 제거, 스타일 의존 경로 변경 |
| `sim/dcss_enemy_registry.gd` | `expedition/legacy/dcss_enemy_registry.gd` | 원본 그대로 |
| `data/content/dcss_enemies.json` | 동일 경로 | 원본 그대로 |
| `sim/abilities/tactical_action_selector.gd` | `expedition/legacy/tactical_action_selector.gd` | 원본 그대로 |

`continuous_floor.gd`는 현재 세션과 원본 층 데이터를 연결한다.
`floor_tactics_adapter.gd`는 현재 전투 상태를 원본 선택기의 모델 계약으로 변환한다.
이번 적 배치에서는 이동·일반 공격을 연결했으며, 원본 전투 엔진 전체나
원본 몬스터의 모든 특수 능력을 이식한 것은 아니다. 동료의 기존 스킬 방침,
기본 공격 타겟 설정, 사용자 행동 예약은 유지한다.

미니맵은 원본의 발견 기록/현재 시야/실시간 마커 캐시를 사용한다.
작은 미니맵은 원본 렌더러, 확대 지도는 같은 캐시의 타일 표현으로 전체 층을 그린다.
미발견 적은 지도와 자동 공격 대상에 나타나지 않는다.
카메라와 터치 좌표는 주인공 주변 10×10 표시 영역에 맞게 변환한다.

## 창 배경 수정

상태창에 쓰던 투명 PopupPanel 테마가 가방·상세창으로 상속되는 경로를 제거했다.
상태창도 불투명 패널을 사용하고 일반 팝업을 재구성할 때 기본 테마를 복원한다.
전체 화면 상태창의 패널 그림자는 제거해 모바일 화면 밖으로 창이 커지지 않게 했다.

## 검증

`tests/continuous_floor.gd`: 크기/배치, 탐험 시야, 숨은 적 공격 방지,
동료 추종, 원본 전술 선택기의 인접 공격, 카메라 터치 좌표,
안전 지역 횃불 사용, 상태→가방→아이템 상세 반복 전환 및 불투명 배경,
상태창 화면 크기, 미니맵 최초 표시를 검사한다.
기존 10개 테스트와 함께 CI에 등록했다. 실제 기기에서의 시각 확인은 별도로 필요하다.
