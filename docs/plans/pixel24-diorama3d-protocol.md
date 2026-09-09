# LW-D3D-01 실행 protocol — Pixel24 실제 3D 탑뷰 디오라마

작성일: 2026-09-09 KST. 상태: 실행 승인됨.

## 실행 계약

- 작업 폴더: `/mnt/d/STARTU/living-world-sim-diorama3d`
- 브랜치: `feat/pixel24-diorama3d`
- 원 부모 소스: `29fcc26c42c427fa7de580603b94fe46e4c0afdb`
- 실행 시작 HEAD: `e90f468cdfbe86821d66b36c8ba3e281867c1b14`
- 실험 질문과 종료 범위는 `docs/plans/pixel24-diorama3d-plan.md`의 `LW-D3D-01`을 따른다.
- 본편 scene, simulation, 저장/session, 원본 Pixel24 PNG 및 runtime registry는 변경하지 않는다.
- main 병합, 원격 push, 배포, 후속 양산은 하지 않는다.

## 구현 구조

1. `playtest/pixel24_diorama3d_factory.gd`
   - BoxMesh, CylinderMesh, SphereMesh와 필요한 저폴리 ArrayMesh만으로 재사용 가능한 실제 부피 에셋을 만든다.
   - 인간·드워프·고블린, 분리 가능한 인간 검, 창고 3×3, 대장간 3×2, 나무, 상자·통·화로·벽 부품을 제공한다.
   - 대표 mesh/triangle 수와 원본에서 가져온 팔레트·형태의 대응 정보를 조회 가능하게 둔다.
   - Sprite3D, QuadMesh, 평면 캐릭터 이미지를 가시 3D 대체물로 사용하지 않는다.
2. `playtest/pixel24_diorama3d_lab.gd`와 `.tscn`
   - 18×18 fixture를 432×432 고정 SubViewport에 렌더한다.
   - Camera3D는 기본·초기화·이동 후 모두 수직 하향, 직교 투영, `size=18`을 유지한다.
   - 별도 HUD에서 좌표, 이동 차단, 검 장착 상태를 표시한다.
   - 방향키/WASD와 칸 클릭으로 인간을 한 칸 이동시키며, fixture occupancy가 경계·벽·건물·나무 줄기 차단을 결정한다.
   - 나무 수관은 줄기보다 넓게 보이되 줄기 칸만 막는다. 인간이 수관 아래의 인접 walkable 칸에 들어가면 수관을 반투명하게 만들고 선택 표식을 유지한다.
3. `tests/test_pixel24_diorama3d.gd`와 runner
   - 실제 MeshInstance3D/부피, Sprite3D 부재, footprint와 fixture 크기, 고정 카메라를 검사한다.
   - X/Z 인접 칸의 투영 간격 24px, 화면↔칸 왕복, 경계·벽·건물·줄기 차단, 이동, 검 토글, 수관 가림 처리를 검사한다.
   - 본편 session 비접근과 reset/move 뒤 카메라 계약을 검사한다.
4. `tools/capture_pixel24_diorama3d.gd`
   - 기본 432×432, 3× nearest 확대, 원본/3D 비교, 경사 부피 증거, 건물 및 수관 가림 사례를 저장한다.
   - 렌더러, mesh/triangle, draw call과 bounded frame-time 표본을 JSON으로 기록한다.
   - 캡처가 끝나기 전과 끝난 뒤 기본 카메라를 수직 탑뷰로 복원한다.
5. 문서
   - `docs/results/pixel24-diorama3d/`에 검증 JSON과 PNG를 둔다.
   - `docs/results/pixel24-diorama3d-result.md`에 수치 사실, 시각 판정, 원본→3D 대응표, 실행법, 한계를 구분해 기록한다.

## 고정 fixture

- 좌표 범위: `(0,0)`부터 `(17,17)`.
- 창고: origin `(2,2)`, footprint `3×3`.
- 대장간: origin `(11,3)`, footprint `3×2`.
- 낮은 벽, 물, 돌길은 고정 좌표 집합으로 만든다.
- 나무 줄기는 한 칸만 점유하고 수관은 인접 walkable 칸까지 시각적으로 확장한다.
- 인간은 이동·선택·검 토글 대상이며 드워프와 고블린은 종족 판독용 고정 표본이다.

## 검증 명령과 합격 조건

순차 실행한다. 같은 프로젝트에서 Godot 프로세스를 병렬 실행하지 않는다.

```bash
godot --headless --path . --script res://tests/run_pixel24_diorama3d_tests.gd
godot --headless --path . --script res://tests/pixel24_asset_acceptance.gd
godot --headless --path . --script res://tests/pixel24_equipment_fit_acceptance.gd
godot --headless --path . --script res://tests/pixel24_item_building_acceptance.gd
godot --display-driver x11 --rendering-driver opengl3 --path . \
  --script res://tools/capture_pixel24_diorama3d.gd
```

- 새 focused test와 관련 Pixel24 회귀 세 개가 exit 0이어야 한다.
- scene import/parse 오류와 런타임 오류가 없어야 한다.
- 기본·reset·이동 후 카메라가 orthographic, 수직 하향, 축 정렬이어야 한다.
- 실제 투영에서 인접 X/Z 칸 중심 간격이 각각 `24.0 ± 0.05px`여야 한다.
- 클릭 왕복과 이동/차단/경계/검 토글/수관 가림 계약이 자동 검사되어야 한다.
- 원본 audit 7개 파일의 SHA-256이 계획의 JSON과 일치해야 한다.
- 캡처 PNG를 직접 열어 1× 종족·장비·건물·길·장애물 판독성과 팔레트 연속성을 평가한다.
- 캡처는 실제 viewport readback이 필요하므로 dummy renderer만 제공하는
  `--headless`가 아니라 사용 가능한 X11/OpenGL display driver에서 실행한다.
- `render_metrics.json`의 환경을 명시하며 측정치를 실제 모바일 성능으로 일반화하지 않는다.

## 중단 및 보고

- 시각 기준이 미달이어도 숨기지 않고 결과 문서에 미달로 기록한다.
- 원본 변경, 본편 상태 변경, 수직 탑뷰 위반으로만 성립하는 결과는 검증 실패로 처리한다.
- 구현·검증·결과 문서를 결과 commit에 포함하고 사용자에게 직접 보고한다.
