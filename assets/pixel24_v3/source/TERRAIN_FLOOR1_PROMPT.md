# Floor 1 pixel terrain source

Built-in imagegen. 4x4 row-major: earth,moss,stoneA,stoneB; wood,metal,rubble,water; wallStudy,solidWall,tree,mossB; inactivePortal,activePortal,campfire,well.
Use cell9 (zero-based) as actual solid wall; cell8 looks hollow like a pit and is NOT a good wall candidate. No automatic use of cell8 as blocking-wall appearance.
Source texture is not yet exact24; mechanical cell extraction/downsample/palette limits required. Source has more detail than requested; review tiled contact sheet at native scale for noise/seams.

One square 4x4 atlas of SIXTEEN equal seamless ground tiles for a tiny 24x24-pixel-per-tile top-down dungeon game, shown enlarged. Exactly four columns and four rows, no gutters, no labels, no borders or framing. Crisp low-resolution pixel art, broad 2x2 pixel clusters and few colors per tile. Dark muted moss, slate, earth, pale rock; no photoreal textures or gradients.
Camera absolutely vertical straight-down TOP VIEW, NOT isometric. Every tile fills its equal square cell completely. Walkable ground is quiet with very low contrast, never a path or a vignette; edges should repeat naturally without grid outlines. Walls are dark SOLID blocking masses with a clear lighter top rim, noticeably different from walkable tiles.
Row1: quiet dark earth; sparse moss ground; broad pale gray flagstone floor; second quiet flagstone variation.
Row2: dark weathered horizontal wood planks; simple dull iron plate floor; sparse pale rubble on earth; calm dark teal shallow water with two simple ripples.
Row3: solid mossy stone WALL TOP with dark filled center and bright broken rim; second solid WALL TOP variation with no holes; dense dark tree canopy TOP with chunky rounded leaves; quiet deep green ground variation.
Row4: inactive small circular stone portal embedded in flagstone; active muted cyan circular portal on same flagstone; small overhead orange campfire on earth with few stones; old round well opening viewed directly overhead on earth.
All structures fit exactly inside tiles. No front wall faces, no 3D blocks, no roofs, no characters, no UI, no text. At most8colors per normal ground tile and12 for objects. Forest ruin biome. Characters on top will be much brighter than these backgrounds.

