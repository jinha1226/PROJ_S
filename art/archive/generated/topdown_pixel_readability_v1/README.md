# Native pixel readability pass v1

This pass does not use image generation. It deterministically derives compact
runtime art from the already approved fixed-front designs and terrain atlases.

- Actors: box-filter to 24x24, slightly raise brightness/contrast, threshold
  alpha to fully transparent/opaque, then reduce to at most 18 colors.
- Monsters: the same 24x24 pipeline with at most 16 colors and a slightly
  stronger brightness lift.
- Terrain: split each 128px atlas cell, reduce to 16x16, and limit each tile to
  6-10 colors. Quiet ground and water first become 8x8 and are nearest-neighbor
  doubled so they use broad 2x2 clusters. Routes, walls, props, and portals keep
  direct 16x16 silhouettes.
- Runtime rendering: nearest-neighbor sampling plus one screen-pixel dark rim.

`runtime/` contains the derived files copied into the shipping asset registry.
`review/` contains enlarged nearest-neighbor sheets for visual inspection. The
96px actor/monster originals remain in their prior versioned folders. The 128px
terrain atlases are archived in `source/terrain`, so this pass is reversible.
