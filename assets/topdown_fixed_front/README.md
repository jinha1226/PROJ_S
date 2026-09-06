# Fixed-front top-down runtime art

These are the shipping 96x96 RGBA layers. The five body bases and resized torso
armor come from `assets/generated/topdown_fixed_front_v2/runtime`; unchanged
headgear and weapon layers retain the approved v1 art. They live outside the
generated source tree because the Web export intentionally excludes generated
concepts and review sheets.

All body, armor and weapon PNGs share one canvas and foot anchor. Compose them in
that order without directional swapping, mirroring or per-layer repositioning.
The five body bases deliberately use smaller featureless faces and larger,
broader torsos. Species readability at mobile zoom comes from head shape, ears,
hair/fur, body proportion and color, while equipment remains a separate aligned
silhouette layer.

`terrain/floor1_atlas_16x1_128.png` and `floor2_atlas_16x1_128.png` are the
shipping, gutter-free 128px cells selected from the generated 4x4 sheets. The
flat camera chooses deterministic variants for terrain and portal state. Road and
rail fragments that require neighbor-aware autotiling are excluded from ordinary
terrain selection, so isolated straight/L-shaped paths cannot appear. This is
presentation-only and never changes pathing, FOV, occupancy or pointer mapping.
The larger source sheets and review concepts remain in the generated asset folder
and are not runtime dependencies.
