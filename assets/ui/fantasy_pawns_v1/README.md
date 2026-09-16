# Fantasy pawn UI icons

Style reference: `art/references/fantasy-pawns/01-simple-fantasy-pawns.png`.
Generated with built-in image_gen, followed by built-in transparent-background editing. Original references are preserved.

4×4 atlas order: attack, wait, explore, tactics; bag, food, noise, menu; stealth, suspicious, detected, strike; shield, heal, fire, ability.

Prompt: Production 4×4 equally spaced UI icon sheet. Simple fantasy pawn style, bold charcoal outlines, restrained solid colors, large readable silhouettes, no pixel art, no text. Sword, clock, compass, formation flag, leather backpack, ration, speaker, menu, three awareness eyes, strike, shield, healing plus, flame, magic orb. Transparent alpha background. Follow-up edit removes checkerboard while preserving all icons and positions.

Native UI uses linear filtering, flat charcoal panels, subtle smooth borders, and NanumSquare Korean text. Command semantics and world simulation are unchanged.

Validation: `gameplay_mobile_ui_acceptance.gd -- --capture` PASS at 320×640, 390×844 and 450×800. Native UI screenshots are saved in `docs/art/fantasy-ui-v1/`. Layout preserves minimum 44px command touch targets and does not advance the simulation.

Bottom command buttons use cached pale-gray silhouette textures with dark details as transparent cutouts so clock hands and compass needles remain readable. Only attack/wait/explore/tactics/bag use this treatment. Hover and pressed borders are neutral gray; top status and skill icons retain their colors.
