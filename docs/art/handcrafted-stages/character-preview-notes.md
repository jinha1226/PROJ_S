# 벽 픽셀 밀도·캐릭터 HTML 시연

## 결과와 확인 위치

- `preview.html`: 굵은 벽돌 4단의 새 벽면, 뒤쪽 돌출 기둥·두꺼운 기둥머리, 기본/장비 모험가 전환.
- `character-lab.html`: 4방향, 기본 자세/이동/공격, 재생·정지·한 단계, 속도, 발 기준점 표시, 기본/전투장비 비교.
- 이미지 생성 스킬 `imagegen`과 내장 image_gen 사용. 생성 원본 PNG는 보존하고 HTML Canvas에서만 64픽셀 프레임으로 사용한다.
- Godot·실제 게임 캐릭터나 전투 수치는 변경하지 않았다.

## 벽 규격

기존에는 벽 선분의 화면 가로 폭이 발판의 절반인데도 64개 픽셀을 꽉 채워 바닥보다 촘촘해 보였다.
새 벽면은 **32×48 유효 샘플 → 64×64 버퍼 → 기울어진 경계면** 순서로 표시한다. 발판 64픽셀의 절반 폭을 한 벽면이 차지하는 규격이다.
뒤쪽 높이 69px는 원근 없는 표시 배율 92/64에서 48픽셀에 해당한다. 앞쪽은 18px 단면을 유지한다.
새 원본 `dungeon-wall-faces-coarse64.png`는 4단 대형 석재·굵은 명암으로 다시 생성했다. 이전 원본도 삭제하지 않았다.

## 캐릭터 규격과 남은 한계

- 기본/장비 각각 16포즈: 4방향 × (정지 1 + 보행 2 + 타격 1). 합계 32포즈.
- 프레임 64×64, 발 기준점 (32,56), 몸체 높이는 약 40px로 맞춘다. 원본 열 중심과 행별 발 높이를 수동 측정했다.
- 행 순서 NE/SE/SW/NW. 이미지 자체의 대각선 각도는 엄격한 모델 회전이 아니라 생성 시안이다.
- 이동은 보행 A→정지→보행 B→정지. 공격은 정지→타격→정지의 간단한 시연이다. 중간 타격 프레임, 무기 궤적, 적중 판정은 미구현.
- **갑옷/검/방패는 한 세트 완성형 시트**다. 개별 장비 레이어나 모든 장비 조합을 구현한 것이 아니다.
- 첫 장비 편집 결과에는 체크무늬 배경과 검 중복이 있어 폐기. 채택한 재생성본은 실제 RGBA이지만 기본과 얼굴·체형이 완전히 동일하지 않다.
- 장비 시트 일부 방향/공격 포즈에서 검·방패 손 배치가 달라지는 문제가 남아 있다. 승인된 인게임 자산이 아닌 검수 시안이며 대량 확장 전에 기준 포즈를 정리해야 한다.
- 캐릭터를 갑옷별로 독립 재생성하면 이런 차이가 생긴다. 다음 단계는 기준 몸체 위 장비 분리 및 손 앵커/가림 순서 고정이다.
- 몬스터 시트는 이번에 생성하지 않았다.

## 검증

- `tests/character_preview_acceptance.mjs`: RGBA 파일, 32개 64×64 캐시, 원본 crop 범위·유한 좌표, 동작 시퀀스 PASS.
- 기존 지형·소품 검사 PASS.
- Chromium: 4방향×3동작, 두 시트 로딩, 재생 진행, 일시정지 유지, 한 단계 이동, 390px 가로 넘침 없음, 런타임 예외 없음 PASS.
- 최초 브라우저 검사는 다른 페이지 캡처가 같은 탭으로 이동해 중단. 단독 재실행에서 PASS.
- 실제 기본/장비·공격 스크린샷 확인. 시각 검토는 위에 기록한 외형·손 배치의 한계를 없앤다는 의미가 아니다.

## 기본 캐릭터 생성 프롬프트

Create a production sprite sheet of ONE original young adult human fantasy adventurer, tousled dark brown hair, simple dark teal tunic, brown belt, dark trousers and boots, bare head, empty hands, no cape, no weapon, no shield. Coarse clean low resolution 64x64 pixel character art with a slightly large readable head and stout compact proportions, only broad 3-tone color clusters, no gradients, no painterly detail. EXACT 4 columns by 4 rows on genuine TRANSPARENT ALPHA background; no checkerboard drawing, no ground, no shadows, no text, no frames. 16 separate full-body frames, all same size within equal square cells, all feet share SAME row baseline, same center anchor, ample transparent gutters. Orthographic elevated isometric camera. Row1 faces screen upper-right (NE), showing back/side. Row2 faces screen lower-right (SE), showing front/side. Row3 faces screen lower-left (SW), showing front/side. Row4 faces screen upper-left (NW), showing back/side. Within EVERY row, columns are: 1 neutral idle, 2 walk left leg forward right leg back, 3 walk right leg forward left leg back, 4 forward one-handed striking/punching pose. Keep the torso facing that row's direction during ALL four poses. Same exact character identity, hair silhouette, head size, clothing, palette, light upper-left and scale throughout. No duplicates of a different character. This sheet will be sliced into 64x64 frame buffers for actual playback, so strong pose differences but no shifting the entire character within the cell. Full figure always fits, no cutoffs.

## 채택 장비 시트 생성 프롬프트

TRANSPARENT RGBA character sprite atlas, actual invisible alpha background, NO CHECKERBOARD and NO background picture. Exactly 4x4 evenly spaced full-body frames of ONE identical chibi young adult adventurer with tousled dark brown hair, dark teal tunic, dark pants, brown boots, STEEL BREASTPLATE and small shoulder guards. ONE short steel sword held ONLY in anatomical right hand; ONE small brown round buckler worn ONLY on anatomical left forearm. No helmet. Coarse 64-pixel fantasy game style, large pixel clusters, restricted muted palette, upper-left light. Same feet baseline and same fixed body scale in every cell. Row1 NE back-three-quarter; row2 SE front-three-quarter; row3 SW front-three-quarter; row4 NW back-three-quarter. Columns each row: neutral idle, walk left leg forward, walk right leg forward, one-handed sword thrust in facing direction. The attack frame MUST contain exactly ONE sword total and ONE shield total. The original sword-hand arm moves forward to thrust; do NOT add an extra attacking arm or retain a second sword in idle position. Shield remains on opposite forearm across all frames. Hair/head shape, armor, blade length, clothing and hand assignment identical in all frames. Stand upright compact silhouette, head about one third body height, character feet centered around 80 percent cell height with ample margin. No grounds, no shadows, no text, no gridlines, no halos. 16 clean isolated cutout sprites, not a screenshot, designed for slicing and direct animation.

## 새 벽면 생성 프롬프트

One opaque horizontal texture strip of exactly FOUR equal touching square panels, no gutters, dead straight FRONT ELEVATION 2D wall textures for a chunky 64-pixel fantasy dungeon. Panel1 solid ancient blue-grey masonry; panel2 SAME masonry with centered open arch of dark navy interior; panel3 SAME arch with closed dark wood door and broad bronze latch; panel4 SAME masonry with one small crack and muted moss along bottom. Exactly FOUR LARGE BLOCK COURSES in height per panel, just two or three large stones per course. Each panel must look like 32x48 logical pixels enlarged nearest-neighbor: very coarse confident pixel clusters, flat 3-tone blocks, NO fine cracks, NO tiny speckles, NO detailed texture, NO gradients. Corners slightly chipped with a few large steps. Strong shapes, dark charcoal blue shadows, slate highlights, restrained antique gold door hardware, worn but dignified fortress. Same block row heights in all panels. Door opens from bottom to 85 percent panel height, 65 percent panel width; broad chunky stone voussoirs. NO perspective, no side faces, no floor, no top faces, no labels, no UI, no transparency. Fill whole strip. It will be projected onto isometric wall planes by code so DO NOT render isometric yourself.
