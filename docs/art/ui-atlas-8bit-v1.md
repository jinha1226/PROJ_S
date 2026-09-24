# UI atlas 8-bit v1

This atlas supplies the updated mobile HUD with a consistent pixel-art language: charcoal and navy panels, brass edges, cream highlights, and small red/cyan accents. It is a transparent 6×4 sheet; each cell is 256×256 pixels.

The first two rows are action and supply icons. The third row contains button frames; these are extracted into `assets/ui/button-frames-8bit-v1.png` as six 48×48 images for nine-slice buttons. The fourth row contains compact utility symbols for map, camp, retreat, log, add, and close actions.

The sheet was generated with this prompt:

> Create a single transparent PNG sprite atlas for a dark fantasy dungeon game's mobile UI. Authentic old-school 8-bit pixel art, hard square pixels, no anti-aliasing, no gradients, limited palette matching charcoal/navy panels, muted brass borders, cream highlights, red HP and cyan magic. Arrange a strict 6 columns by 4 rows grid, every cell exactly 64x64 pixels, with generous transparent padding and no overlap. Row 1: crossed sword, shield, wait hourglass, auto-explore compass, tactics crossed swords, backpack. Row 2: red healing potion, blue mana potion, green antidote potion, scroll, torch, food ration. Row 3: normal button frame, hover button frame, pressed button frame, disabled button frame, square panel frame, selected gold frame. Row 4: tiny map pin, campfire, retreat flag, log parchment, plus sign, close X. No letters, no numbers, no UI mockup, no scenery, no shadows outside cells. Pixel-art sprite sheet intended for Godot AtlasTexture and nine-patch style button frames.

The generated sheet is 1536×1024 with six 256px columns, but the artwork does not respect the nominal row boundaries. `expedition/art/mobile_art.gd` crops icons at the actual transparent row gaps and reads the six extracted PNG button frames. `expedition/ui/main.gd` uses those frames with 10px nine-slice margins. Floor action and supply buttons use the cropped atlas icons in `expedition/ui/screens/floor_hud.gd`.

The playable UI uses Galmuri11 for Korean pixel lettering, square bordered panels, square meters, and nearest-filtered icon and frame textures. Galmuri11 is distributed under SIL OFL 1.1; its license is in `assets/fonts/Galmuri11.LICENSE.txt`.
