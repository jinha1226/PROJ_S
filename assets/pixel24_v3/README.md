# Pixel24 v3 runtime assets

`source/` holds immutable generated source atlases. `runtime/` contains only
deterministic 24px normalization products. `review/` contains nearest-neighbor
contact sheets and actual-size composites.

The extraction contract is `tools/art/pixel24_manifest.json`; the build tool is
`tools/art/build_pixel24_assets.gd`. The normalized sheets were visually
approved and the runtime registries now use this directory. Current gameplay
maps padded/leather armor, seven weapons, the wooden off-hand shield, four
monsters, and both terrain floors. Steel, mithril, hood, helmet, and steel-shield
images remain art-only because no matching gameplay item definitions exist.

Known limitation: a few tiny arm-edge pixels retain source-key color. Review
accepted them for this first playable pass; the pipeline deliberately avoids a
more destructive matte that could remove skin, scarf, or plum-cloth pixels.
