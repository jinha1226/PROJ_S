# 24px eight-way actors and world props

Runtime directions: `S, SW, W, NW, N, NE, E, SE`.

- Human: existing `../pixel24_v3/human_8way/` frames, unchanged.
- Elf, dwarf, orc, beastkin, kobold, slime, beetle: `actors/<species>/atlas.png`, eight 24×24 regions in one 192×24 strip. Individual PNGs are also provided.
- Goblin: **not generated**. The built-in generator rejected two attempts. Its existing south-facing sprite remains connected; there is no claim of eight-way coverage for goblins.
- `features.png`: 16 24×24 world props/effects in a 96×96 atlas.
- `props.png`: 8 additional 24×24 props/effects in a 96×48 atlas.

Generation used the built-in image generator with the project's existing art as reference, not an external game's sprites. See [PROMPTS.md](PROMPTS.md). Full-size generated sheets are in `source/`; `.gdignore` excludes them from runtime import/export.

## Export and identity constraints

Run `godot --headless --path . --script tools/art/import_eight_way_assets.gd`.

This exporter splits equal atlas cells, measures alpha ≥ 0.5 to ignore nearly invisible background specks, resizes with nearest-neighbor sampling, and anchors each sprite to the original species' foot baseline. It retains alpha within the crop. **South-facing images are copied from the original project asset**, preserving the original front-facing appearance. The original source directories are untouched.

All rendered body textures are exactly 24×24. Generated sheets themselves are larger, not falsely described as native 24px images. Equipment remains the existing paper-doll layer system with its discrete direction projection; this is not newly hand-authored eight-direction equipment art. Random NPC instances use species bodies plus their equipment, not a separate unique portrait painting per NPC.

`tests/eight_way_visual_acceptance.gd` checks all 64 connected direction frames, direction indexing, distinct frame data, native sizes, transparent margins, and solo resource meter bounds. `--capture` with an X11 renderer produces `/tmp/eight-way-runtime-preview.png`.
