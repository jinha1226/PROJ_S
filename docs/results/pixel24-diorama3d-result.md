# LW-D3D-01 결과 — Pixel24 실제 3D 탑뷰 디오라마

작성일: 2026-09-09 KST. 상태: **PASS**.

## 결론

현재 Pixel24의 색과 대표 실루엣을 실제 부피가 있는 저폴리 메시로 옮긴 독립
Godot 실험실을 구현했다. 기본 수직 직교 탑뷰의 한 칸 24픽셀 조건에서 인간,
드워프, 고블린은 각각 갈색 둥근 머리, 구리색 넓은 수염, 올리브색 긴 귀로
구별된다. 인간의 검 on/off, 창고와 대장간, 길과 점유 장애물도 1× 캡처에서
판독 가능했다. 따라서 승인된 첫 fixture 범위의 질문에는 긍정적인 결과다.

- protocol commit: `2604af2`
- 구현·검증 산출물 commit: `cec25ede8a74505e56986fb897f2dacd5927023e`
- 결과 문서 commit: 이 문서를 포함한 최종 결과 commit
- 부모 소스: `29fcc26c42c427fa7de580603b94fe46e4c0afdb`

## 실행과 조작

저장소 루트에서 다음과 같이 독립 scene을 실행한다.

```bash
godot --path . res://playtest/pixel24_diorama3d_lab.tscn
```

- 방향키 또는 WASD: 인간을 한 칸 이동
- 지상 칸 클릭/터치: 대상 방향으로 한 칸 이동
- `G` 또는 `검 ON/OFF` 버튼: 검 장착 토글
- `초기화`: 시작 위치·검 장착·수직 카메라 복원

최초 실험 결과 commit까지는 본편 `run/main_scene`을 유지했다. 이후 사용자의
명시적 main/모바일 배포 요청에 따라 Pages 진입 scene만
`pixel24_diorama3d_lab.tscn`으로 전환했다. 기존 본편 scene 파일은 보존되며,
이 실험실은 저장/session 또는 본편 simulation 상태를 읽거나 쓰지 않는다.

## 구현 사실

- `Node3D`, `MeshInstance3D`, `Camera3D`와 Box/Cylinder/Sphere/Torus 메시로
  캐릭터·건물·나무·상자·통·벽에 실제 두께와 부피를 만들었다.
- 가시 fixture에는 `117`개 MeshInstance3D와 `2,304`개 모델 삼각형이 있고,
  캐릭터/건물 대체용 `Sprite3D`와 `QuadMesh`는 각각 `0`개다.
- 렌더 영역은 고정 `18×18`칸, `432×432`픽셀이다. Camera3D는
  orthographic `size=18`이며 기본·reset·이동 후 수직 하향을 유지한다.
- 실제 투영 측정은 X 인접 칸 `24.0px`, Z 인접 칸 `24.0px`였다.
  3×/6× 파일은 nearest 검토 확대본이며 1× 밀도 계약에 포함하지 않는다.
- 창고는 `3×3`, 대장간은 `3×2` occupancy를 사용한다. 물·벽·건물·상자와
  나무 줄기 한 칸이 이동을 막고, 메시의 시각 크기는 게임 규칙을 대신하지 않는다.
- 수관은 줄기보다 넓지만 인접 수관 칸은 걸을 수 있다. 인간이 아래로 들어가면
  수관 alpha가 `0.94 → 0.30`으로 바뀌며 depth-safe 선택 링은 유지된다.

## 원본 → 3D 대응

| 대표 에셋 | 원본 | 계승한 단서 | 추정·신규 면과 모델 |
|---|---|---|---|
| 인간 | `runtime/actors/base/human.png` | 둥근 갈색 머리, 따뜻한 피부, 회색 옷 | 뒤통수와 짧은 블록 몸통; `build_actor(human)` |
| 드워프 | `runtime/actors/base/dwarf.png` | 넓은 구리색 수염, 민머리, 황토색 앞치마 | 턱을 감싸는 수염과 짧은 몸; `build_actor(dwarf)` |
| 고블린 | `runtime/monsters/goblin.png` | 올리브 피부, 긴 옆 귀, 짙은 옷 | 두께 있는 귀와 단순 뒷면; `build_actor(goblin)` |
| 인간 검 | `fit_v2/equipment/weapons/short_sword.png` | 짧고 밝은 칼날, 어두운 손잡이 | 직육면체 칼날·가드·그립; `SwordEquipment` |
| 창고 | `runtime/buildings/storage_timber.png` | 열린 목재 데크, 상자, 자루, 통 | 기둥·바닥·용기의 깊이; `build_storage` |
| 대장간 | `runtime/buildings/armory_timber.png` | 열린 데크, 모루, 화로, 무기 걸이 | 화로·굴뚝·후면 기둥의 깊이; `build_armory` |
| 나무 | 원본 없음 | 기존 이끼/목재/흙 팔레트만 계승 | 6각 줄기와 군집 수관인 신규 파생 디자인; `build_tree` |

전체 기계 판독 대응표는
`docs/results/pixel24-diorama3d/source_mapping.json`에 있다.

## 캡처와 시각 판정

| 판정 항목 | 결과 | 근거 |
|---|---|---|
| 인간/드워프/고블린 구별 | PASS | 갈색 머리, 구리 수염, 긴 올리브 귀의 색·실루엣이 서로 다름 |
| 검 on/off | PASS | 인간 오른쪽의 밝은 칼날 유무가 1×에서 보임 |
| 창고/대장간 기능 구별 | PASS | 상자·통·자루와 모루·발광 화로·무기 걸이가 분리됨 |
| 길/막힌 칸 | PASS | 밝은 돌길, 연속 낮은 벽, 청록 물, 건물 footprint가 읽힘 |
| 기존 팔레트 연속성 | PASS | 어두운 흙, 이끼 녹색, 목재 갈색, 회색 광물 계열을 유지함 |

주요 증거:

- `docs/results/pixel24-diorama3d/topview_432.png`: 기본 1× 탑뷰
- `docs/results/pixel24-diorama3d/topview_nearest_3x.png`: nearest 3× 검토본
- `docs/results/pixel24-diorama3d/actors_2d3d_native24.png`: 원본/3D 동일 24px 비교
- `docs/results/pixel24-diorama3d/topview_sword_off_432.png`: 검 해제 비교
- `docs/results/pixel24-diorama3d/buildings_topview.png`: 두 건물 비교
- `docs/results/pixel24-diorama3d/canopy_occlusion_432.png`: 수관 가림 처리
- `docs/results/pixel24-diorama3d/pitched_volume_evidence.png`: 실제 부피 경사 증거

## 자동 검증

다음 검사는 순차 실행하여 모두 exit `0`과 PASS를 확인했다.

```text
godot --headless --path . --script res://tests/run_pixel24_diorama3d_tests.gd
  PASS LW-D3D-01 focused tests
godot --headless --path . --script res://tests/pixel24_asset_acceptance.gd
  PASS pixel24 asset acceptance
godot --headless --path . --script res://tests/pixel24_equipment_fit_acceptance.gd
  Pixel24 equipment fit acceptance: PASS
godot --headless --path . --script res://tests/pixel24_item_building_acceptance.gd
  PASS pixel24 item/building acceptance
```

Focused test는 실제 메시/삼각형, Sprite3D 부재, 카메라와 24px 투영,
화면↔칸 왕복, footprint, 이동·경계·장애물 차단, 검 토글, 수관 fade와 선택 표시,
본편 격리 및 원본 hash를 검사한다. 계획 audit의 원본 7개 SHA-256은 모두
일치했고 기존 PNG·registry에는 변경이 없다. 최초 실험 범위 이후의 명시적 배포
요청으로 `project.godot`의 main scene 한 줄만 디오라마 진입점으로 변경했다.

## 렌더 측정과 한계

실제 X11/OpenGL Compatibility 캡처에서 Mesa llvmpipe 소프트웨어 렌더러를
사용했다. 한 프레임의 RenderingServer 수치는 object `431`, primitive `8,918`,
draw call `386`이었다. 60개 process-frame 벽시계 간격은 평균 `18.285ms`,
p95 `21.257ms`, 최소 `16.057ms`, 최대 `22.999ms`였다. 이는 GPU time이 아니고
capture/UI를 포함한 소프트웨어 렌더 환경의 표본이므로 실제 휴대폰 성능이나
지속 가능한 FPS로 일반화할 수 없다. 원시 값은 `render_metrics.json`에 있다.

진짜 수직 탑뷰에서는 원본 정면 스프라이트보다 얼굴과 몸통이 덜 보이고,
종족 판독은 주로 머리색·수염·귀의 상부 실루엣에 의존한다. 캐릭터는 정적 저폴리
표본이며 애니메이션, 자유 회전, 본편 FOV/renderer 연결, 전체 종족·장비 양산은
이번 범위에 없다. 다음 단계에서는 본편에 즉시 통합하기보다 실제 목표 기기에서
성능을 측정하고, 다양한 지형 위 1× 식별성과 애니메이션 중 실루엣을 먼저 검증하는
것이 안전하다.

## 후속 모바일 Pages 배포 검증

사용자의 후속 지시로 GitHub Pages 진입점을 이 scene으로 전환했다. 변경 후 focused
test가 다시 PASS했고 Godot 4.6.2 Web release export가 완료됐다. 생성된 산출물은
`index.html` 5.4KB, `index.wasm` 36MB, `index.pck` 11MB였으며, checkout 파일이
없는 상태를 흉내 낸 PCK 단독 headless 시작도 script/resource 오류 없이 exit `0`이었다.
실제 모바일 브라우저 성능과 터치 동작의 최종 판정은 Pages 배포 후 기기에서 한다.
