# Item icons v1

Created with the `imagegen` skill, built-in image generation (not CLI/API fallback).
Original generated PNGs are preserved; the game caches 48 × 48 nearest-neighbour
textures for inventory and ground rendering. These are inventory icons, not
wearable character sprite layers. Potion bottles remain from the existing CC0
0x72 atlas; their per-run colour is independent of their unidentified effect.

## Prompt set (production specification summary)

Shared direction: a single centred fantasy dungeon inventory item, isolated on
a genuinely transparent background, chunky readable pixel-art silhouette,
dark brown outline, restrained palette, no text, no frame, no character or scene.
Keep the subject recognisable when reduced to a small mobile inventory cell.

| File | Subject / variant direction |
|---|---|
| food.png | Brown bread loaf wrapped in cloth, unmistakably food rather than a bottle. |
| armor.png | Brown leather cuirass, empty garment, no wearer. |
| padded.png | Beige quilted gambeson with diamond stitching and brown fastenings. |
| robe.png | Dark blue hooded cloth robe with a brown sash, no wearer. |
| chain.png | Grey chainmail shirt with visible interlocking metal rings. |
| plate.png | Silver steel plate cuirass with a small gold buckle. |
| scroll.png | Warm parchment scroll with a central purple star-like rune. |
| scroll_moon.png | Edit scroll.png: replace only the central rune with a blue crescent moon; preserve parchment, composition and transparent background. |
| stone.png | Faceted cyan magic crystal, distinct from a flask. |
| essence.png | Purple organic magical flame/teardrop, distinct from the angular crystal. |

The food image is a shared category icon for the current rations; essence and
magic-stone subtypes likewise share category art. Armour types have separate art.
This pass does not claim unique art for every material, weapon or essence subtype.

Generation provenance: session `01a08d9a-260c-7d11-856d-98a52ed24ff4` under
the built-in `generated_images` directory. All ten selected images are copied
into this project directory so exported games do not depend on that directory.
