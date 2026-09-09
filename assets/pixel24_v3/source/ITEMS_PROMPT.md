# Item icon atlas — source prompt (generated 2026-09-09)

Purpose: ground/inventory icons for the game's real item and resource IDs. Same
pipeline as EQUIPMENT_PROMPT.md: generated source is not native24; extract each
cell by explicit crop in tools/art/pixel24_manifest.json, nearest-downsample to
24x24, palette-limit, threshold alpha. Do not add gameplay definitions from art.

Cell map (4x4 row-major, zero-based) → content ID:
0 POTION_HEALING · 1 FOOD_RATION · 2 SCROLL_UNSPECIFIED · 3 ACCESSORY_BRASS_CHARM
4 MAGIC_STONE (마석) · 5 MATERIAL_UNSPECIFIED (generic pouch) · 6 resource TIMBER · 7 resource STONE
8 resource HERBS · 9 gold coins (town gold) · 10 POTION_UNSPECIFIED (unknown flask) · 11 ACCESSORY_UNSPECIFIED (ring)
12 dropped-item marker (flat cloth bundle) · 13 loot sack (battle loot) · 14 key (reserved) · 15 blank reserved cell

Integration notes: empty slot borders stay code-drawn UI, not raster art. Cell 15
is fully empty. Preserve existing IDs and item rules; the reserved key creates no
new item. Crop and center each icon deterministically after generation; generated
cell positions are not trusted as pixel-exact. Keep silhouette padding at native24.

## Prompt

Use case: style-transfer. Input image is a STYLE AND PROPORTION reference only: approved miniature 24x24 pixel-game characters and equipment. Create a NEW item-icon atlas in the same modest restrained pixel aesthetic, not characters.
Output precisely 4 columns x 4 rows of sixteen equal square cells on a genuinely transparent background (alternatively a perfectly uniform saturated magenta RGB(255,0,255) backdrop for color keying). Each icon isolated and centered with wide padding, no cell border, no labels, no text. Coarse crisp square pixel clusters like enlarged native 24x24 sprites: 1 logical-pixel charcoal contour, 2-3 flat tones per material, muted dark-fantasy palette with one clearly readable light midtone per icon. No smooth gradients or antialiasing, no texture noise, no glow, no drop shadow, no floor, no 3D inventory render, no checkerboard printed into the image.
Icons read as small objects lying on the ground seen slightly from above (three-quarter top), all roughly the same visual mass so none dominates a 24px tile.
Row1 LEFT TO RIGHT: small round glass healing flask with a dull red liquid and a cork; a wrapped ration — a brown cloth bundle tied with twine showing a pale bread end; a rolled parchment scroll with a dark wax seal; a small brass charm on a short chain, a single warm brass disc.
Row2: a small faceted magic stone — a rough dark crystal chunk with one muted violet-blue facet catching light, no glow; a plain small drawstring pouch in gray-brown cloth (generic material); three short stacked timber logs, cut ends visible; two rough gray stone chunks.
Row3: a small bundle of dark green herbs tied at the stem; a small stack of three dull gold coins; an unknown potion — a squat dark flask with a muted purple liquid and no label; a simple dull metal ring.
Row4: a low horizontal gray cloth parcel with a visible cross-tie (dropped-item marker), distinctly rectangular rather than a pouch; a tall ochre-brown loot sack with a wide open black mouth, distinctly larger in silhouette than the closed gray material pouch; an old iron key; a completely blank transparent cell, no outline or object.
Every object fits fully inside its cell with clearance. Match the reference's restrained colors and extremely clear tiny silhouettes; a 24px viewer must tell flask, ration, scroll, charm, magic stone, pouch, timber, stone, herbs, coins, ring, key apart at a glance.

## Generation record

Built-in image generation, style reference: `../review/nearest-contact-6x.png`.
Selected source: `items-generated-v1.png`. The first output contained a baked
checkerboard; the selected output uses the following background-only correction:

> Use case: background-extraction. Edit target: this 4x4 item atlas. Change ONLY its checkerboard background to perfectly uniform saturated magenta RGB(255,0,255). The checkerboard is mistakenly painted into the image and MUST ALL disappear. Magenta must replace the entire background, including the blank bottom-right cell, every gap between sprites, ring hole and chain openings. Keep all fifteen item icons, colors, black outlines, silhouettes, pixel clusters, scale, positions, spacing and row/column layout unchanged. Do not add any text, grids, border, new icon, or shadows. Background must be one exact flat color, with no checker pattern, gradient or texture.
