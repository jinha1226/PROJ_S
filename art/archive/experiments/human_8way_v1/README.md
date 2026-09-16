# Human eight-direction idle prototype

Experimental artwork only. Does not replace the live 24×24 human or equipment.

Reference: `assets/pixel24_v3/runtime/actors/base/human.png`.
Generation: `imagegen` skill, built-in image-generation tool, reference-based generation.

Requested sheet layout: four columns, two rows, read left to right:

| Row | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Top | S / front | SW / front-left | W / left | NW / back-left |
| Bottom | N / back | NE / back-right | E / right | SE / front-right |

The directions describe the character's facing in game space, not camera motion.
Camera elevation, neutral pose, scale, and foot anchor must remain consistent.
The requested runtime cell is 24×24; a generated enlarged sheet is not itself a
validated native-pixel runtime atlas. It requires a separate native-size review.

## Prompt

Use case: identity-preserve. Asset type: a single production-oriented eight-direction human idle sprite sheet for a 24x24-pixel dark-fantasy top-down game. Input image 1 is the existing human base sprite, a style/identity reference, not a background to copy. Keep its oversized brown-haired head, warm light skin, compact proportions and muted brown/tan palette. Plain tan undershirt, dark brown trousers and boots, bare hands; no armor, weapons, hat, cape, props, or ground shadow. Generate exactly EIGHT full-body views of this same human standing still, as one perfectly regular FOUR-column TWO-row sprite sheet with equal-sized cells. Reading order: TOP ROW 1 south/front looking toward viewer, 2 southwest/front three-quarter looking down-left, 3 west/true left profile facing screen-left, 4 northwest/back three-quarter looking up-left; BOTTOM ROW 1 north/back with no face visible, 2 northeast/back three-quarter looking up-right, 3 east/true right profile facing screen-right, 4 southeast/front three-quarter looking down-right. All eight directions must be distinct. Rotate ONLY the character around a vertical axis in 45-degree steps; keep the camera at the same slightly elevated top-down angle in every cell, including profiles. Never rotate the image plane. Neutral standing pose, arms relaxed at sides, feet at rest, not walking. Identical body scale, head size, footing and lighting across all cells. Each equal cell represents exactly a 24x24 logical pixel canvas: sprite about 19-21 logical pixels tall, feet aligned to logical row 22, centered at logical x12. Use very coarse deliberate pixel clusters and a limited palette, not detailed high-resolution pixel illustration. Hard nearest-neighbor pixel edges, no smoothing, no antialiasing, no gradients. Transparent background with genuine alpha, no checkerboard drawn into pixels, no text or labels, no grid lines or decorations. Show all eight characters completely with clear transparent gaps and no cropping. This is a prototype to assess directional readability; the original human asset must remain recognizable.

## First-pass inspection

`human_8way_source_v1.png`: 1774×887 RGB PNG. All eight requested views are
present and readable at preview scale. Side profiles narrow and hide the far arm;
rear three-quarter views expose only a small face/ear edge. The original muted
brown palette and oversized head are retained, with more detailed clothing.

The model did not satisfy the native-pixel/transparent-output contract: the
checkerboard is baked into RGB pixels, and this is not a native 96×48 atlas.
Do not use it as a drop-in runtime asset or claim native 24×24 readability yet.

## Background correction

Use case: background-extraction. Edit the provided eight-direction human sprite sheet ONLY to remove the entire gray-and-white checkerboard background and all background artifacts. Output a PNG with a genuinely transparent alpha channel around and between the eight characters, NOT a painted checkerboard or a white background. Preserve all eight characters exactly: same facing directions, face, hair, clothing, colors, silhouette, pixel clusters, scale, positions, and the same four-column two-row layout. Do not redraw or restyle the characters. No shadows, no text, no borders. The checkerboard is unwanted image content, not transparency; remove it.

`human_8way_source_v2.png` is the selected preview: 1774×887 RGBA PNG with
non-opaque alpha, verified using `file` and ImageMagick `identify` (read-only).
The checkerboard has been removed and all eight views remain present. Minor
edge/shape drift from generative editing still needs native-size cleanup.
The raw dimensions are not divisible by four columns, so do not assume integer
equal-cell atlas coordinates. A production pass must align each sprite to a
24×24 cell, unify the foot anchor, and check palette and silhouette at 1×.

No runtime assets, game logic or equipment layers were replaced. No remote push
or deployment was performed for this prototype.
