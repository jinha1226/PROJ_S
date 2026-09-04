# Top-down cutout character rig v1

These atlases contain modular painted 2D body parts. They are not full-character
animation frames. `playtest/low_poly_pawn_3d.gd` slices each 1024 px runtime atlas
into sixteen 256 px cells, scales each cell to the matching joint length, and
attaches it to a `Node3D` bone laid out in the XZ gameplay plane.

## Runtime files

- `runtime/hero_cutout_atlas_4x4_1024.png`
- `runtime/goblin_cutout_atlas_4x4_1024_v2.png`

Both files have real alpha transparency. The source images are retained in
`source/`; the 1254 px built-in generation output is normalized to 1024 px with
Lanczos resampling for deterministic 256 px atlas cells.

## Cell layout

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| 1 | head south | head north | torso south | torso north |
| 2 | upper arm | forearm + hand | thigh | shin + foot |
| 3 | armor south | armor north | pauldron | helmet |
| 4 | blade | shield | belt / pelvis | cape / back cloth |

Left and right limbs share art and are mirrored in-engine. South/north changes
replace only the relevant head, torso, and armor cells. East/west changes mirror
the same articulated rig; no baked whole-character sprite is used.

## Projection contract

- World camera: true vertical orthographic top-down.
- Ground, walls, props, and effects: unshaded flat `Sprite3D` art in the XZ plane.
- Character art: gentle three-quarter overhead perspective baked into each part so
  the head, torso, arms, and legs remain legible from the vertical game camera.
- Runtime structure: spatial root and articulated `Node3D` joints only; zero
  `MeshInstance3D` nodes in the visible pawn or prototype room.

