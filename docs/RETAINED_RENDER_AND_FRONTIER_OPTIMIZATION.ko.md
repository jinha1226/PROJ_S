# 지형·광원·자동탐험 후속 최적화

기준 commit: `4227de3`. 작업일: 2026-09-12. 실제 `party_encounter_sandbox` / `PartyGridView` / `PartyAutoExplore`에 연결했다. 기존 HUD → 게임 화면 → 로그 3줄 → 초상화 → 하단 버튼, 숙련·이능 UI, 전투/부상/시간 계약은 유지한다. 외부 NPC 엔진은 도입하지 않았고 [별도 검토 문서](NPC_SIMULATION_SOURCE_REVIEW.ko.md)에 후보와 연결 범위를 기록했다.

## 구현

### 지형과 움직이는 화면 분리

- `retained_terrain_layer.gd`: 평면 지형의 그리기 명령을 월드 좌표 기준 **4×4 타일 구역**에 보관한다. 카메라 이동/충격은 구역의 위치만 옮긴다.
- 타일 이미지·벽 여부·VISIBLE/MEMORY·크기가 바뀐 구역만 다시 그린다. 시야 경계와 화면 진입/이탈 구역도 갱신하며, 화면 밖 구역은 제거한다. 캐시가 탐험한 전체 맵 크기만큼 무한히 쌓이지 않는다.
- 캐릭터·선택 표시·전투 효과는 기존 동적 경로를 유지한다. 지형과 같은 카메라/충격 오프셋을 적용하고 클릭 좌표는 기존 정수 타일 매핑을 유지한다.
- 관측 변경 시 feature/혈흔/hazard/item/resource 후보를 한 번 모은다. 애니메이션 프레임마다 빈 셀과 시야 밖의 모든 기억 셀을 반복 순회하지 않는다. 아이템은 현재 캐릭터 점유에 따른 작은 구석 표시를 계속 계산한다.
- 옵션인 2.5D 투영에는 기존 지형 그리기 경로를 유지한다. 테스트용 immediate painter 비교 플래그는 메뉴에 노출하지 않는다.

### 안개와 광원 갱신

- 지형·아이템 변경과 안개 변경의 무효화 조건을 분리한다. 관측의 비시각 필드나 아이템만 바뀌면 암흑 mesh는 유지한다.
- 광원마다 영향 범위의 알려진 차폐 지형을 확인해 LOS ray를 재사용한다. 그 광원 주변에 벽/미탐색 지형이 바뀐 경우에만 해당 캐시를 비운다. 시야 밖 광원은 실제 조명 목록에서 제외한다.
- 주인공/카메라/줌/층/장착 횃불 상태가 같으면, 변경된 셀의 가시성·광원에 영향을 받는 암흑 정점만 다시 샘플링한다. 전체 시점이 이동하면 필요한 전체 샘플을 갱신한다.
- 거리 계산용 좌표, 셀 크기, 감쇠곡선 상수, 광원 좌표는 프레임 계산 앞에서 준비한다. 정점마다 관측 DTO와 밝기 Dictionary를 다시 만들지 않는다.
- 기존 원형 그라데이션, 18 rings × 48 segments, 횃불·모닥불 감쇠는 유지한다. **GPU mesh 업로드는 여전히 변경 시 한 surface 전체**다. GPU 부분 업로드나 시뮬레이션 FOV 알고리즘 교체까지 한 것으로 해석하면 안 된다.

### 자동탐험 탐색

- `fog_frontier_search.gd`: 관측된 지도만 입력받는 정수 인덱스 거리 탐색. 이동 안전 조건을 packed flags로 변환하고, 거리/비용/부모를 배열로 관리한다.
- `(걸음 수, 이동 비용, y/x, 순번)` 우선순위 heap을 사용한다. 기존 목표 점수, 대각선 gateway/점유 조건, 경로 유지, 적/위험/상호작용 발견 시 중단 규칙을 유지한다.
- 현재 최선 경계보다 나아질 수 없는 거리에서는 탐색을 종료한다. 알려지지 않았거나 안전하게 진입할 수 없는 열린 출구가 있다는 이유만으로 전체 알려진 구역을 끝까지 검색하지 않는다. 알려진 안전 출구의 도달 우선권은 유지한다.
- 원래 검색 함수는 제품에서 제거하고 `tests/fixtures/reference_frontier_search.gd`에 기준 oracle로만 남겼다. 테스트/문서는 기존 Web export 제외 대상이므로 배포 크기에 들어가지 않는다.

구조 참고: Shattered Pixel Dungeon의 [부분 타일 갱신](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/tiles/DungeonTilemap.java), [안개 갱신 영역 관리](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/tiles/FogOfWar.java), DCSS의 [탐험 거리 검색과 조기 종료](https://github.com/crawl/crawl/blob/master/crawl-ref/source/travel.cc). 해당 Java/C++ 구현을 복사하거나 번역해서 편입하지 않았으며, Godot와 기존 관측 계약에 맞게 작성했다.

## 측정

Godot 4.6.2, 로컬 headless, `tests/waterside_performance_probe.gd`, 390×800, 시드 44, 기본 파티, 좌우 이동 6회. 이전 값은 `4227de3`의 [기록](AUTO_EXPLORE_MASTERY_INTEGRATION.ko.md), 이후는 이번 최종 probe의 단회 값이다. 서로 다른 시점의 표본이며 모바일 FPS/장시간 p95 측정은 아니다.

| 항목 | 이전 | 이후 |
|---|---:|---:|
| 지형 포함 화면 CPU / draw 호출, 건조 | 약 16.8ms | 약 10.8ms |
| 지형 포함 화면 CPU / draw 호출, 물 | 약 17.5ms | 약 11.4ms |
| 암흑 CPU / draw 호출, 건조·물 | 4.2 / 4.3ms | 1.25 / 1.33ms |
| 건조 6회 명령+프레임 대기 총합 | 365ms | 311ms |
| 물 6회 명령+프레임 대기 총합 | 394ms | 337ms |

이후 화면 CPU는 `grid.draw_world`에 새 자식의 `grid.retained_chunks` 및 `grid.retained_background` 시간을 더하고, 부모 draw 12회로 나눴다. 자식으로 옮겨 놓은 계산을 누락해서 개선률을 부풀리지 않는다. 실제 합계는 건조 `128272 + 742 + 18 = 129032µs`, 물 `135445 + 917 + 13 = 136375µs`다. 명령 시간은 건조 29.3ms / 물 32.4ms로, UI 관측·시뮬레이션 등 별도 비용이 남아 있다. 그리기 비용 감소가 전체 턴 시간에 같은 비율로 적용된다고 주장하지 않는다.

자동탐험 순수 검색: 동일 프로세스의 난수 고정 18×18 지도 120개에서 이전 총 295713µs → 새 검색 150799µs. 결과의 목적지·전체 경로·비용이 모두 일치했다. 추가로 245760개의 이웃 이동 안전 판정을 비교했다. 실제 캠페인 80걸음/계획 25회, 명령 중앙값 18.4ms / p95 27.5ms 표본으로 진행 유지도 확인했다. 탐색만의 약 49% 감소를 게임 전체가 2배 빨라진 것으로 해석하지 않는다.

## 검증

- `fog_frontier_equivalence.gd`: 기존 검색과 120개 지도 exact parity, 대각선/점유/위험 조건 비교, 미확인 열린 출구의 조기 종료.
- `auto_explore_progress_acceptance.gd`: 실제 캠페인 탐험 진행과 목표 유지/위험 재계획.
- `run_party_auto_explore_tests.gd`: 기존 9개 모두 통과. 시야 밖 정보 비노출, 한 번에 한 명령, 정지 규칙, 저장 재현 포함.
- `retained_render_acceptance.gd`: 한 타일 수정은 한 구역만 재그리기, idle 재사용, 단일 셀 안개 부분 샘플링, 차폐 변경, 카메라 이동·resize·층 변경·장착 횃불 갱신. CPU 정점 alpha는 기존 계산과 오차 0.00001 미만. GL mesh 색은 8-bit 양자화 범위 내 일치.
- 위 테스트의 X11/OpenGL 실제 이미지 비교: 평균 채널 최대차 `0.0000421`, 채널 차이 0.02 초과 픽셀 비율 `0.0611%`. 구역 경계의 subpixel 겹침/그리기 순서 때문에 비트 단위 동일 이미지는 아니다. 지형·주인공·광원 표시를 직접 확인했다.
- `radial_darkness_acceptance.gd`, `waterside_render_acceptance.gd`, `legacy_shell_engine_acceptance.gd` 통과.
- `travel_smoothness_acceptance.gd`는 처음에 구형 시야 oracle과 현재 field 시야를 비교해 44개 불일치가 났다. 시야 authority는 이번에 변경하지 않았으며, `6ca6859`에서 이미 교체됐는데 테스트는 그 이전 `0f9b977` 상태였다. 테스트를 현재 field kernel/legacy 모드 구분에 맞췄다. 실패를 숨기려고 시야 범위나 차폐 규칙을 변경하지 않았다.

최종 확인: 수정한 `travel_smoothness_acceptance.gd` 통과(미등록 종족 fallback 테스트의 예상 경고만 있음). Web 릴리스 export 성공. `/tmp`에서 소스 트리에 의존하지 않고 `--main-pack .../build/web/index.pck --quit-after 5` 실행도 종료 코드 0, script error 없이 통과했다. GitHub Actions에 새 장시간 테스트를 추가하지 않았다.

## 모바일 확인

배포 후 새 게임으로 복도 자동탐험 → 물가 이동 → 적 발견 정지 → 횃불 장착/해제 → 모닥불/벽 주변 이동 → 줌 변경 → 숙련 UI 접근을 확인한다. 개발 PC의 headless/llvmpipe 결과만으로 모바일 끊김이 완전히 해결됐다고 판단하지 않는다. 원거리 NPC 판단 주기 변경은 이 최적화에 포함하지 않았다.
