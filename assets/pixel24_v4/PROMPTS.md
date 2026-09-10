# Built-in image generation prompt set

Mode: built-in `image_gen`, no CLI/API fallback used.

Reference for humanoids: `assets/pixel24_v3/source/actors-keyed.png` (existing project art). References for slime/beetle: their existing `assets/pixel24_v3/runtime/monsters/<species>.png`.

## Elf

```text
Use case: identity-preserve. Asset type: game sprite direction atlas. Use ONLY the blonde elf (second character from left) in reference as identity. Create eight directions of this EXACT short, big-headed elf, same teal tunic, blonde hair, ears, tiny limbs and dark outline. One 4-column by 2-row sheet, equal square cells, no gaps. Reading order S facing viewer, SW facing down-left, W left profile, NW away-left, N back, NE away-right, E right profile, SE down-right. Orthographic slightly top-down RPG, same camera all frames, upright neutral pose. Each cell is a 24x24 logical pixel sprite shown enlarged, character 18-20 logical pixels tall, aligned feet at logical y=22, center x=12. Strict nearest-neighbor pixel clusters, about 12 colors; no painting, texture, antialiasing, labels, letters, shadows on floor or borders. Transparent background true alpha. Preserve short reference proportions, never long arms or legs. Output atlas 4:2 aspect ratio. Only elf, no other species.
```

## Dwarf, orc, beastkin

Substitute `{subject}` with:

- Dwarf: `third character, stout bald dwarf with orange beard, mustard tunic`
- Orc: `fourth character, olive green orc with black topknot and dark maroon tunic`
- Beastkin: `fifth character, brown fur cat ears beastkin with blue grey tunic`

```text
Use case: identity-preserve. Asset type: eight-direction game sprite atlas. Use ONLY {subject} from reference. Preserve EXACT identity, palette, very short tiny limbs and large head. One 4 columns x 2 rows atlas, equal square cells no gaps. Reading order S (face viewer), SW (down-left), W (left profile), NW (back-left), N (back), NE (back-right), E (right profile), SE (down-right). Identical orthographic slightly top-down RPG camera, neutral standing pose. Each cell 24x24 LOGICAL pixel grid enlarged, character 18-20 logical pixels tall, center x12 feet y22, same anchor and height throughout. Deliberately coarse pixel clusters, dark outline, 12 colors. True transparent alpha background. No labels, text, grid lines, floor shadows, textures, antialiasing, long limbs or detailed illustration. Output 2:1 aspect ratio. Only this one character repeated eight directions.
```

The same template with `sixth character, olive goblin with wide pointy ears, dark green tunic` failed at output generation; no resulting asset was saved.

## Kobold, slime, beetle

Substitute `{subject}` with:

- Kobold: `small orange kobold, small dark horns, dark grey tunic, seventh character`
- Slime: `small turquoise gelatinous slime with eyes`
- Beetle: `small blue-grey armored beetle with legs and mandibles`

```text
Use case: stylized-concept. Game sprite direction atlas of {subject} matching reference. Exactly 4 columns and 2 rows, one character per equal square cell. Read left-right top-bottom: face South toward viewer, Southwest, West left profile, Northwest away-left, North away, Northeast away-right, East right profile, Southeast. Orthographic slightly top-down RPG, consistent camera and size, 24x24 logical pixel grid per cell shown enlarged. Tiny compact proportions, chunky low resolution pixel clusters, dark outline, limited palette. Genuinely transparent alpha background. No letters, borders, gridlines, floor shadows or scenery. Keep reference colors and appearance. Atlas aspect ratio 2:1. Each character centered with feet at same baseline.
```

Retry using `small olive green goblin, wide pointed ears, dark green tunic, sixth character` also failed at output generation. No further retry or paid fallback was used.

## World features

```text
Use case: stylized-concept. Asset type: a single 4 by 4 texture atlas for a 24x24 pixel dark fantasy dungeon game. Exactly sixteen equal square cells, no gaps, no borders. Transparent background true alpha, objects fit inside cells. Logical pixel art resolution 24x24 per cell shown enlarged, crisp chunky square pixel clusters, muted slate stone, rust, moss and restrained elemental colors, no painterly textures, no letters or text. Reading order row1: stone descending staircase, stone ascending staircase, dormant stone portal ring, glowing cyan stone portal ring. Row2: small burning campfire logs, lit iron brazier torch, dark red blood puddle, small bone remains. Row3: black iridescent oil puddle, pale cyan ice patch, white steam puff, dark grey smoke puff. Row4: green toxic gas puff, yellow electrical spark branching, small golden loot pouch, closed worn wooden chest. Orthographic slightly overhead RPG view, clear low resolution silhouettes, consistent style across all 16 cells, no ground background outside each object, no grids labels shadows or watermark.
```

## Additional props

```text
Use case: stylized-concept. Single 4-column 2-row atlas of eight 24x24 logical pixel dungeon props, enlarged display, orthographic slightly top-down dark fantasy RPG. Equal square cells, no gaps, transparent alpha background, no labels/text/gridlines. Coarse pixel blocks, dark outlines, about 12 colors each, no smoothing or painterly texture. Reading order: (1) open wooden door in stone doorway, (2) low round stone water well seen from above, (3) purple crystal relic on stone plinth, (4) small blue shallow water puddle. Bottom row: (5) isolated orange flame, NO logs or brazier, (6) small dull grey ash pile, (7) small white curved wind puff, (8) small bright gold impact spark. Each object centered and wholly contained with two logical pixels padding. Atlas aspect 2:1. Transparent background genuine alpha.
```
