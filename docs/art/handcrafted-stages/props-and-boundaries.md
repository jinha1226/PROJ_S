# 소품·방 경계 HTML 적용 기록

## 범위

- `preview.html`, `stage-decor.js`: 64픽셀 HTML 아트 검토 전용. 게임 엔진·실제 전투·장비·저장에는 미연결.
- 횃불 2종과 열림/닫힘 상자, 테마별 연결부, 3×3 시연용 구역 이동.
- 시연의 3×3 연결은 모든 인접 칸을 연결한 고정 그래프다. 실제 게임의 시드별 구역 그래프가 아니다.
- 횃불은 정적 장식. 연료·시야·실시간 동적 광원 시스템을 되살리지 않았다.
- 상자는 방별 열림 상태만 유지하며 보상을 만들지 않는다. 브라우저 새로고침 시 초기화.
- 문 버튼은 해당 시연 방의 문 상태를 함께 바꾼다. 실제 포털별 공유 문 상태 구현은 아니다.

## 사용자의 외곽·문 방향 피드백 반영

초기 독립 아치 스프라이트는 지형에 붙는 축과 맞지 않고, 낮은 띠 외곽도 부자연스러웠다. 이를 최종 방식으로 채택하지 않았다.

- 던전: 별도 아치를 바깥 타일에 세우는 방식을 제거. **정면 벽 텍스처를 실제 타일 경계 선분의 기울기에 투영**한다. 벽과 문이 같은 평면·높이·두께를 공유한다.
- 뒤쪽 N/W 벽: 높이 76px의 벽과 문. 앞쪽 S/E 벽: 18px 단면만 남기고 문 위쪽을 생략. 앞쪽 열린 문은 양옆 낮은 문설주와 빈 문턱만 남긴다.
- 문은 이미지 위쪽을 눌러도 반응하도록 투영된 벽면 자체에도 히트 영역을 부여했다.
- 동굴/숲: 동일 높이의 외곽 띠를 제거. 불규칙한 흙·풀 바닥, 암반·나무로 장식 가장자리를 확장한다.
- 바깥 장식은 8×8 전투 셀을 늘리지 않는다. 표시 옵션을 켜면 전투 격자와 실제로 연결된 입구가 보인다.
- 통로는 경계 밖 장식 바닥으로 연결한다. 문이 닫혔으면 첫 터치는 문만 열고 두 번째에 이동한다.
- `문과 통로` 강제 옵션은 모든 테마에서 벽면 연결을 비교하기 위한 모드다. 기본값은 던전만 벽, 동굴/숲은 개방 경계다.

## 아트 원본

- `fantasy-props-pixel64-source.png`: 1536×1024 RGBA, 원본 좌상단 alpha=0 확인. 실제 표시에서는 측정한 소품 영역을 64×64 버퍼로 옮긴다.
- `dungeon-wall-faces-pixel64.png`: 정면 벽/열린 문/닫힌 문/변형 벽의 불투명 시트. 열림 문 내부는 어두운 통로 텍스처이며 실제로 뚫린 3D 지오메트리가 아니다.
- 처음 생성된 소품 두 시트는 배경에 체크무늬가 그려져 폐기. 세 번째 생성의 실제 alpha 결과만 사용한다.
- 소품 시트의 독립 아치는 원본에 남아 있으나 최종 경계 렌더링에는 사용하지 않는다.
- 생성 방식: imagegen 스킬, 내장 image_gen. 별도 API/CLI 미사용. 채택 프롬프트는 아래에 보존.

## 검증

- `node tests/handcrafted_preview_acceptance.mjs`: PASS.
- `node tests/stage_decor_acceptance.mjs`: PASS. 상자 상태 복귀, 닫힌 문 2단계, 양방향 이동, 3×3 경계 제한, 문 벽면/입구 히트, 테마·연결 모드, 실패 처리.
- Chromium에서 세 테마의 지형/소품 로딩 및 스크린샷 확인. 390px viewport의 scrollWidth=390.
- Godot 미실행. 최종 엔진 연동·전투 가독성·장시간 모바일 성능 검증은 별도 작업.

## 채택 소품 프롬프트

A transparent-background PNG sprite sheet, actual RGBA cutouts with alpha=0 background. NO checkerboard pattern, NO white background. Eight low-resolution chunky pixel-art fantasy props in an exact evenly spaced 4-column 2-row grid. No floor tiles, no labels, no text. Top row left to right: standing lit torch; short stone post with lit torch; closed wooden treasure chest; same chest open. Bottom row: open stone door arch facing down-left; open stone door arch facing down-right; same first arch with closed wooden door; same second arch with closed wooden door. Transparent pixels inside open door openings. Isometric orthographic camera, each prop suited to a 64x64 pixel cell, simple coarse blocky pixels and dark grey/brown restricted palette with small gold flames, shared upper-left light. All objects separated with wide empty transparent gutters, feet at equal row baseline. Asset cutouts for layering on an existing dark game board. Background must be invisible when composited, not a picture of a transparency checker.

## 채택 벽면 프롬프트

Create ONE horizontal wall texture strip for a low-resolution pixel-art dungeon. Four equal RECTANGULAR panels touching edge to edge, NO margins and NO gutters. Straight FRONT ELEVATION, perfectly flat 2D view, NOT isometric, NO perspective. All four panel tops/bottoms exactly aligned and same dimensions. Overall 4:1 strip composition if possible. Each panel designed as a 64x64 pixel low-resolution texture enlarged with nearest neighbor: chunky blue-grey masonry blocks, broad 3-tone shading, dark mortar lines, crisp pixel clusters, no gradients, no glow. Panel1: solid stone block wall. Panel2: SAME stone wall with a centered open arched doorway; recess pure very dark navy, no door leaf. Panel3: SAME arch in the SAME position and size but filled by closed dark brown wooden planks with iron strap. Panel4: same solid stone wall with minor cracks and moss at bottom. Doors begin at the BOTTOM edge and extend to 85 percent of panel height, width about 70 percent panel width. Wall block rows continue at the exact same heights across all four panels. Fill the entire image opaque with these four square texture panels, no alpha, no checker, no bevels, NO ground, NO side faces, NO top faces, NO labels, no frame, no characters. Intended to be mapped onto mathematically projected isometric wall faces in a game; camera orientation will be applied by code, so this source MUST be dead straight frontal.
