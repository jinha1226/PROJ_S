# 64픽셀 HTML 적용

`preview.html`은 새 픽셀 스타일 원본을 사용하며, 이전 고밀도 HTML은 `preview-detailed.html`로 보존했다. 게임 엔진 코드나 실제 지형 데이터는 변경하지 않았다.

- 내장 image_gen / imagegen 스킬로 새 타일 시트 생성. 원본 파일은 `fantasy-terrain-pixel64-source.png`.
- 생성 파일 자체는 고해상도다. HTML에서 각 타일을 **64×64 Canvas 버퍼**, 발판 **64×32**로 래스터화한 다음 nearest-neighbor 방식으로 표시한다. 원본 PNG를 직접 수정하지 않는다.
- 바닥 4종은 좌표 기반 해시로 고정 배치. 목표 비중은 기본 50%, 균열 20%, 대체 패턴 20%, 자갈 10%; 작은 방의 실제 비율은 다를 수 있다.
- 바닥 변형은 장식일 뿐 통행·전투 규칙을 바꾸지 않는다. 물과 차단물은 별도 열을 사용한다.
- 테마별 타일은 최초 사용 시 캐시하므로 화면을 다시 그릴 때마다 원본을 축소하지 않는다.
- 생성 이미지의 수작업 픽셀 격자·엄격한 색상 수는 보장하지 않는다. 최종 HTML의 64픽셀 버퍼 크기는 코드로 보장한다.

검증: `node tests/handcrafted_preview_acceptance.mjs` PASS (JSON 일치, 세 테마, 64칸, 64×64 캐시, 바닥 4종, 표시 토글, 로딩 실패 처리).
실제 Chromium에서 세 테마 로딩 확인 및 스크린샷 검토. 390px 모바일 viewport에서 scrollWidth=390으로 가로 넘침 없음.
Godot는 실행하지 않았다.

## 실제 생성 프롬프트

Create a game terrain sprite atlas with EXACTLY 6 columns and 3 rows, 18 isolated tiles on genuine transparent alpha. Image intended for a chunky LOW RESOLUTION 64-pixel fantasy tactics game. Each sprite must look like a hand drawn 64x64 pixel sprite enlarged with nearest neighbor: very large clean square pixel clusters, 12 colors per biome maximum, NO antialiasing, NO smooth gradients, NO micro texture, NO photorealism, NO painterly rendering. Fixed equal square cells, all sprites centered horizontally, consistent isometric 2:1 diamond top footprint, same diamond location and height in every cell, generous gutters. Floor diamonds only with very shallow 3-pixel sides, not tall cubes. Lighting upper-left. Six columns EXACT: 1 plain floor, 2 subtly cracked floor, 3 sparse pebble/moss floor, 4 alternative floor slab/earth pattern, 5 same floor with single tall obstacle, 6 shallow water floor flush with floor surface (not a raised pool). Row one DUNGEON: quiet cool grey large masonry blocks, chunky stout square pillar in column5. Row two CAVE: muted brown slate and earth, chunky angular rock in column5. Row three FOREST: dark olive moss and earth, compact chunky tree in column5. No text or headings, no frames, no characters, no objects other than specified. All four floor variants remain clearly WALKABLE and visually quiet. Background truly transparent. Matching footprints and baselines across ALL cells. Prefer simplified retro handheld-game graphics over richly shaded illustration.
