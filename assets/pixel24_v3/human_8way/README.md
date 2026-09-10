# Human eight-way trial — native 24 × 24

Direction order in `sheet.png`: S, SW, W, NW, N, NE, E, SE.
The eight individual runtime PNGs have transparent backgrounds and binary alpha.
`s.png` is pixel-identical to the original `runtime/actors/base/human.png`.
Other directions are a first gameplay trial, not a claim of pixel-identical character reconstruction.
Other species still use their existing front-facing art.

Built-in imagegen was used with the original human PNG as the identity reference.
Generated source: `source/generated.png` (excluded from Web exports).
Conversion: `godot --headless --path . --script tools/art/import_human_8way.gd`.
The reproducible conversion isolates each view, samples to a native 24px canvas,
locks to the original palette, and preserves the original south view unchanged.
Runtime never downsamples the large generated source. No frame uses a rotated flat
front image. Equipment uses a cached discrete paper-doll projection of the original
24px layers; bespoke eight-way weapon/armor artwork remains a possible refinement.
Portraits always remain front-facing.

## Final generation prompt

Use case: identity-preserve. Asset type: production pixel game sprite sheet.
Reference is the exact original human, a tiny squat brown-haired human with beige
face, dark brown tunic, very short limbs, no weapon. Create EIGHT directional views
of THIS SAME character, not a new design. CRITICAL original proportions: actual
sprite fits a 24x24 grid, squat body, huge head and very short feet, head occupies
almost half of body height. Orthographic top-down roguelike pixel sprite, not
illustration or perspective scene. One horizontal row, eight equally-sized 24x24
logical cells, in order SOUTH, SOUTHWEST, WEST, NORTHWEST, NORTH, NORTHEAST, EAST,
SOUTHEAST. South matches reference faithfully. Rear has brown hair, no face.
Profiles show one eye, diagonal views show offset facial features and appropriate
back/side hair. All sprites identical height and foot baseline. Pixels must be
square, crisp and aligned to the same logical 24x24 grid in every cell, no antialias,
no soft shadows. Output may enlarge every logical pixel by integer nearest-neighbor
but each character must contain NO more than 24x24 logical pixels. Transparent RGBA
background, no checkerboard drawn, no labels, no borders, no floor, no equipment.
Keep original brown/tan muted palette and short original limbs; never lengthen
arms or legs.
