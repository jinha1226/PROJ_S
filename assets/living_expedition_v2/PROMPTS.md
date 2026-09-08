# 검토용 에셋 — 게임 미적용

생성: 2026-09-09, 내장 image_gen. 사용자 승인 전 런타임 등록 금지.

- actors.png: 3×3, 인간/엘프/드워프, 오크/수인/고블린, 코볼트/슬라임/딱정벌레.
- forest-review.png: 4×4, 1층 숲/유적 타일 후보.
- foundry-review.png: 4×4, 2층 주조장 타일 후보.

검토 사항: 캐릭터는 머리/몸통형이며 팔다리 없음. 장비 레이어 미제작.
타일은 아직 최종 seamless 검증 전이며 벽에 정면 면이 남아 있으므로 완전 탑뷰 방향으로 수정 필요.
슬라임/딱정벌레에 의복처럼 보이는 하단이 있어 몬스터 형태도 승인 전 점검 필요.
원본 그대로 보관하며, 24~36 화면 픽셀에서의 실게임 가시성은 승인 후 적용 단계에서 확인한다.

## Actors

Use case: stylized-concept. Asset type: production transparent 3-by-3 sprite atlas for a portrait mobile dark-fantasy top-down RPG. Create ONE square atlas with precisely nine evenly spaced equal square cells, no lines or labels. Read left to right, top to bottom: human adventurer, elf adventurer, dwarf adventurer; orc adventurer, wolf beastkin adventurer, goblin; kobold lizard, turquoise slime, dark beetle. Each sprite centered within its cell with ample transparent padding, isolated genuine alpha background, identical foot/bottom baseline at 85% cell height. Characters are compact head-and-torso pawns: NO arms, NO legs, NO feet, NO weapons. Large distinctive head occupying 45% silhouette height above a simple cloak-like torso, slightly overhead but front-facing upright character symbols for a strictly flat top-down world, NOT isometric. Human charcoal hair and muted blue torso; elf angular pale hair pointed ears and deep moss torso; dwarf huge copper beard and wide amber-brown torso; orc broad olive head with two pale tusks and burgundy torso; wolf beastkin pointed ears silver fur and deep violet torso. The three humanoid monsters have easily distinct body shapes. No eyes or mouth detail except characteristic tusks/snout, no facial expression. Strong bold near-black outside contour and three large flat color values per material, light top edge, muted jewel accent, no gradients or grain, no tiny accessories. Sophisticated restrained dark fantasy storybook-cutout game art, not generic cheerful chibi stickers. Must read at 28-36 screen pixels. All nine silhouettes completely separate, no ground shadows outside sprite, no environment, no text, no watermark. Final output atlas 1536x1536 if possible.

## Forest

Use case: stylized-concept. Asset type: one production 4x4 terrain sprite atlas, square image, exactly sixteen equal square tiles, no gaps, no lines, no labels, mobile dark fantasy top-down game. Perfect orthographic TOP VIEW, never isometric or tilted, all ground tiles fill their cell edge to edge with quiet tileable edges. Cohesive restrained illustrated flat-cutout style with large simplified shapes, 3 values per material, dark desaturated background behind bright pawn characters, no tiny noisy texture. Ancient overgrown forest ruin biome. Row 1: quiet blue-gray flagstone floor; plain dark earth floor; soft moss-green grass ground; broken warm-brown wooden planks. Row 2: dark shallow turquoise water with a few soft ripples; pale-gray scattered rubble on earth; BLOCKING mossy stone wall top, very dark mass with bright rim; BLOCKING dense tree canopy top, near-black center and clear leafy outer silhouette. Row 3: inactive circular ancient stone portal on dark flagstone; active circular cyan ancient portal on dark flagstone; small warm orange campfire with ring of stones viewed straight overhead on earth; ancient turquoise rune pedestal viewed directly from above on stone. Row 4: calm sparse pale flagstone variation; worn stone bridge floor; old stone circular well viewed from above on earth; a simple abandoned crate cluster viewed straight from above on earth. IMPORTANT wall/tree tiles must clearly contrast with walkable floor: darker filled mass, crisp rim. All equal cells align exactly to a 4x4 grid, no borders between ordinary ground tiles, no perspective showing a front wall face, no text, no logos.

## Foundry

Use case: stylized-concept. Asset type: one production square 4x4 terrain atlas, exactly sixteen equal square cells without gaps, no labels. Flat orthographic directly overhead TOP VIEW for a mobile dark fantasy game, NEVER isometric or tilted. Quiet seamless ground edges, large simplified shapes, dark desaturated materials and limited luminous accents, strong distinction between passable ground and blocking dark wall masses. Collapsed ancient civilization foundry biome, consistent illustrated game art. Reading left to right: Row1 dark basalt flagstones; quiet charcoal ash earth; blackened packed ground; rust-brown metal grating floor. Row2 shallow cold blue drainage water; pale slag rubble on ash; blocking charcoal stone wall top with crisp silver rim; blocking massive rusted machinery top with dark center. Row3 inactive round ancient stone portal; active amber circular portal; small warm campfire overhead surrounded by slate stones; large circular cold turquoise energy core pedestal overhead. Row4 quiet basalt slab floor variation; worn brass walkway floor; circular ventilation shaft directly overhead; abandoned iron crates overhead. All sixteen aligned to strict 4x4 equally sized tiles. No front-facing walls, no fake grid seams on floor textures, no characters, no text, no watermark. Readable when each tile is just 24 screen pixels.


