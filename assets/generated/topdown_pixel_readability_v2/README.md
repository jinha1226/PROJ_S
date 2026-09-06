# Pixel Dungeon scale readability pass v2

This deterministic pass reduces the approved fixed-front characters and monsters
to a native 16x16 canvas, matching the information density of classic compact
dungeon sprites. It does not use image generation.

- Playable species use at most 10 requested palette entries; the resulting PNGs
  contain 7-9 visible/transparent colors.
- Goblin and kobold use at most 9 requested palette entries.
- Alpha is binary, so no soft fringe survives at mobile zoom.
- Head shape, ears, skin/fur color, beard, torso, short legs, and both feet are
  retained; facial and clothing detail is intentionally subordinate.
- Players render at 1.15 world cells and monsters at 1.0 cell. A one-screen-pixel
  dark rim remains presentation-only and does not affect occupancy or input.
- The v1 24px actors and the original 96px sources remain versioned for rollback.

The 16x16 terrain atlases from v1 already match this scale and remain unchanged.
