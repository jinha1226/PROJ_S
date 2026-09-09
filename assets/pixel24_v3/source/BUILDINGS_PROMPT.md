# Base building atlas — source prompt (drafted 2026-09-09, not yet generated)

Purpose: top-down structures for the base settlement (sim/base_settlement_rules.gd).
Footprints are tile-aligned: STORAGE 3x3, LODGE 3x2, CLINIC 3x3, MARKET 3x2,
ARMORY 3x2, GATE 3x3 tiles at 24px per tile → 72x72 or 72x48 runtime sprites.
Three construction levels: camp (canvas + rope), timber (planks), stone (masonry).
Buildings must sit ON the existing floor atlases (TERRAIN_FLOOR1_PROMPT.md) and
match their wall-top style: dark solid mass with a lighter top rim, no front faces.
Runtime today draws buildings procedurally (playtest/base_settlement_view.gd);
adopting sprites is a separate integration step, not authority to change footprints.

Cell map: 3 rows (level: camp, timber, stone) x 6 columns (STORAGE, LODGE, CLINIC, MARKET, ARMORY, GATE).
Every cell is 3x3 tiles square; 3x2 buildings occupy the top two tile rows of their cell and leave the bottom tile row transparent.

## Prompt

Use case: style-transfer. Input images are STYLE references only: the approved 24x24 pixel terrain atlases (moss/earth/flagstone floors, dark solid wall tops with a lighter rim) and the miniature pixel characters. Create a NEW top-down building atlas in the same restrained pixel style.
Camera absolutely vertical straight-down TOP VIEW, NOT isometric, no front wall faces, no visible doors as 3D openings — a doorway is a lighter gap in the wall rim on the tile edge facing DOWN. Output precisely 6 columns x 3 rows of eighteen equal square cells on a genuinely transparent background (or uniform saturated magenta RGB(255,0,255) key), no gutters, no labels, no text, no grid lines, no characters.
Each cell is a 3x3-tile plot; a building either fills the whole 3x3 plot or exactly the TOP 3x2 tiles of it with the bottom tile row left fully transparent. Structures snap to tile edges: outer walls are exactly one tile thick, corners square. Crisp coarse square pixel clusters like enlarged native 24px tiles, 1 logical-pixel charcoal contour, 2-3 flat tones per material, at most 12 colors per building, no gradients, no antialiasing, no drop shadows, no glow.
Walls: dark solid masses with a clearly lighter top rim exactly like the reference wall tiles. Roofs are NOT drawn as sloped roofs; interiors are seen from above as floor with a few readable props.
Columns LEFT TO RIGHT, each column one building type: STORAGE (3x3), LODGE (3x2), CLINIC (3x3), MARKET (3x2), ARMORY (3x2), GATE (3x3).
Row1 CAMP level: rope-and-stake fences with a muted canvas tarp corner instead of walls. STORAGE: open yard with two crates and a barrel. LODGE: two bedrolls beside a small dark fire ring. CLINIC: one cot and a low table with a dull red flask. MARKET: one plank counter on trestles with a small pale awning strip. ARMORY: an anvil stump beside a small orange coal pit. GATE: two wooden stake posts with a gap between them and a rope line.
Row2 TIMBER level: dark weathered plank walls with a lighter rim. STORAGE: plank walls, crates and sacks inside, wide doorway gap at the bottom. LODGE: plank walls, three bunks inside. CLINIC: plank walls, two cots, a shelf with two flasks. MARKET: plank stall with counter and hanging goods dots. ARMORY: plank walls, anvil, coal pit, weapon rack of three vertical lines. GATE: a plank palisade across the plot with a central gap and a small watch platform.
Row3 STONE level: mossy stone walls matching the reference wall tiles. STORAGE: stone walls, barrels, a locked chest. LODGE: stone walls, bunks and a hearth. CLINIC: stone walls, cots, a shelf of flasks, a dull teal sigil on the floor. MARKET: stone stall with two counters. ARMORY: stone smithy with anvil, quench barrel, glowing coal pit. GATE: a stone gatehouse with a wide central gap and two small square towers at the top corners.
Forest ruin biome palette: dark moss, slate, earth, weathered brown wood, dull iron, one muted orange accent for fire. Buildings must be recognisable at 72px wide and read as darker than the floor beneath. All structures fit exactly inside their plots.
