# Equipment source atlas

Built-in image_gen, 2026-09-09. Source only; not runtime sprite dimensions.
4x4 row-major mapping: cloth, leather, steel, mithril; hood, helmet, wooden_shield, steel_shield; short_sword, thrusting_sword, hand_axe, mace; spear, bow, crossbow, staff.
Game content IDs must be checked before mapping. Staff/shields are art candidates, not authority to add new gameplay definitions.
Background/alpha and exact cell bounds require inspection before import. Preserve source; normalize in reproducible asset pipeline.

## Prompt

Use case: style-transfer. Input image is a STYLE AND PROPORTION reference only: approved miniature 24x24 pixel-game characters. Create a NEW equipment-only sprite atlas to dress these squat characters, not another character sheet.
Output precisely 4 columns x 4 rows of sixteen equal square cells on a genuinely transparent background. Each item isolated and centered with wide padding, no cell border, no labels. Coarse crisp square pixel clusters, like enlarged native 24x24 sprites, 1 logical-pixel charcoal contour, 2-3 flat tones per material, muted dark-fantasy palette. No smooth gradients or antialiasing, no texture noise. Not 3D inventory renders.
Row1 LEFT TO RIGHT: ash padded cloth short tunic; warm dark brown leather vest; dull steel short breastplate with two small shoulder caps; pale desaturated cyan mithril short breastplate with two shoulder caps.
These FOUR torso garments are flat FRONT-facing paper-doll overlays for the exact short broad torso proportions of the reference. Wide and squat, open neck top, no head/skin/arms/hands/legs/feet, no mannequin, no character, no cape. No underwear showing under armor. Roughly width:height 1.5:1, garment silhouette ends at waist/hips. Simple big material planes.
Row2: empty charcoal cloth hood ring with face opening truly transparent; empty dull steel helmet with face opening transparent; round brown wooden shield with one dull steel boss; compact dark steel kite shield.
Row3: short straight steel sword with rusty hilt pointing UP; thin thrusting sword pointing UP; one-handed axe pointing UP; simple blunt iron mace pointing UP.
Row4: wood spear with steel tip pointing UP; plain wood recurve bow with taut string vertical; compact wood-and-steel crossbow pointing UP; simple ash wooden staff with a tiny dull teal stone pointing UP.
Weapons separate with no hands and no character; tips stay fully inside cells; no diagonal poses. This atlas is for mechanical extraction and fitting to a shared logical24 body canvas. Boots and faces remain from separate base. Match the reference's modest restrained pixel aesthetic and extremely clear small silhouettes. No glow or dropped shadows, no floor, no decorative sparks, no checkerboard printed into image, no text.

