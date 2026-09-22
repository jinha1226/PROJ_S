# 연속 1층 이식 기록

**2026-09-22 이후**: 고정 4구역 층은 절차 생성기(`expedition/floor_generator.gd`)로 대체되었다. 아래 기록은 이식 이력용이다.

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

## 모바일 탐험 조작 추가 이식

- `../playtest/fog_frontier_search.gd` → `expedition/legacy/fog_frontier_search.gd`:
  원본 탐색 알고리즘을 복사했다. MovementSystem 전체 의존 대신 동일한 8방향 상수만 분리했다.
  packed 배열 플래그, 힙 기반 거리 탐색, 가장 가까운 경계에서의 조기 종료를 유지한다.
- `../playtest/party_auto_explore.gd`, `party_exploration_route.gd`:
  현재 세션과 계약이 다른 전체 호스트는 복사하지 않았다. 경로 보존, 다음 칸 검증,
  이미 확인한 경계 재탐색 방지 방식은 `exploration_navigation.gd`에 맞춰 적용했다.
  최초 계획 이후 정상 이동에서는 A*나 전체 발견 타일 DTO를 매 턴 다시 생성하지 않는다.
- `../playtest/portrait_gesture.gd` → `expedition/legacy/portrait_gesture.gd`:
  입력 소유권을 일시적인 버튼 밖에 유지하는 원본 제스처를 복사했다.
  모달 검사와 호스트 콜백만 현 UI에 맞게 변경했다. 600ms 길게 누르기,
  드래그 취소, 터치 후 에뮬레이션 마우스 중복 방지를 유지한다.
- `../playtest/base_map_camera.gd` → `expedition/legacy/base_map_camera.gd`:
  원본 핀치 접점·거리 비율 누적 코드를 복사했다. 확대 투영만 현 6~24칸 카메라에 맞췄다.
  여기서는 주인공 추종을 유지하므로 원본 정착지 지도처럼 자유 팬은 하지 않는다.
- 원본 로그는 이벤트 DTO 기반이라 현재 문자열 로그에 그대로 연결되지 않는다.
  최근 세 줄/전체 기록 모달 구조를 참고하고, 현재 세션의 로그를 그대로 표시한다.

화면 갱신 때 보드와 미니맵 노드를 재사용해 미니맵의 증분 캐시를 보존한다.
`mobile_exploration.gd`는 경로 재사용, 적 접촉 정지, 핀치 후 오작동 방지,
줌별 좌표 변환, 길게/짧게 누르기 구분, 로그 보존 및 모바일 배치를 검증한다.

## 원형 횃불 조명

`radial_light.gd`는 `../playtest/party_grid_view.gd`의
`radial_darkness_sample`과 `_build_radial_darkness_mesh`를 현재 보드에 맞게 축소 이식했다.
smoothstep 명암 보간과 극좌표 정점 공유를 사용하며 위치·화면 크기·타일 크기·반경이
같으면 메시를 재사용한다. 원본의 다중 광원/층별 테마는 가져오지 않았다.
밝기 60 이상에서는 암막 메시를 그리지 않는다. 그 아래에서 원형 암막 강도를 연속적으로 높인다.
시야 반경은 밝기 0~60에서 7~18칸이며, 기존 최대 반경 7칸을 이제 최소 밝기의 범위로 사용한다.
원형 가시 범위와 벽 차폐는 실제 적 표시 및 공격 대상 선정에도 적용한다.
동료가 멀리 있어도 별개의 밝은 원을 만들지 않는다.
