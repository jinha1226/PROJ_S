# 마을 건물 스타일 검토 — 미적용

내장 image_gen, 2026-09-09.
파일: town-woodcut-review.png. 3열 2행, 왼쪽부터 여관/시장/치유소, 대장간/창고/탐험대 거점.

먹색·뼈색·녹슨 주황의 캐릭터 후보와 같은 팔레트를 사용했다. 실제 출력은 캐릭터보다 재질 잔무늬가 많고 일부 측면이 남아 있어 단순화와 시점 정리가 필요하다. 각 셀 절단/배경 제거/충돌 영역/모바일 가시성 검증 전이며 런타임에는 등록하지 않았다. 투명 배경 없이 검토용 원본으로 보관한다.

## 프롬프트

Use case: stylized-concept. Asset type: six town-building art assets, one square 3-column by 2-row evenly spaced review sheet for a mobile dark-fantasy TOP-DOWN settlement game.
Visual language: austere medieval woodcut and angular hand-cut paper theatre. Large solid cut-paper shapes, hand-cut angular irregularities, no cute rounded stickers, no smooth 3D rendering, no gradients, no bevels, no glossy lighting, no fine texture or decorative noise. Restrained soot-black #202527, warm bone #D9C9A6, oxidized rust #AF5639 and subdued slate #596767. A faint small turquoise accent is allowed ONLY on healing water. Background uniform slate. All buildings completely separated and wholly visible, generous margins, no text/labels/gridlines/UI.
Camera: strictly vertical straight-down roof plan like a playable top-down tile map, axis-aligned square or rectangular footprints, NO isometric or perspective rotation, NO front facade view. Define function by roof shape, broad functional fixtures and small open courtyards, not lettering. Low buildings 3x3 to 4x4 game tiles, readable at 80-120 screen pixels.
Row1: INN rectangular warm rust split roof with central dark chimney, pale little open courtyard holding one simple communal table and benches; MARKET L-shaped dark building with three large bone-colored cloth awnings over simple crates in its forecourt; HEALING HOUSE pale octagonal roof surrounding an open square turquoise healing basin and two plainly drawn bed rectangles viewed directly overhead.
Row2: SMITHY black forge shed with a broad rust chimney opening and a side open workshop containing one large recognizable anvil viewed overhead, restrained orange furnace aperture; STOREHOUSE broad dark rectangular roof interrupted by a rust loading porch and three large pale crates; EXPEDITION LODGE angular bone gable roof around an open planning courtyard with a single broad map table and rolled canvas shelter, rust triangular banner lying visible on roof.
Each structure uses few broad polygonal forms, distinctive overall footprint, clean dark boundary. No people, no little shingles, no thousands of bricks, no floating signboards, no crosses or readable emblems, no surrounding scenery, no cast shadow. Architecture feels old and inhabited, spare and functional rather than cartoon toy buildings. Consistent graphic ink-paper art across all six. Review sheet with opaque slate background, no checkerboard or fake alpha.

