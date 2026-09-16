# 2D top-down gameplay concepts v1

These nine images are visual targets, not runtime textures. They were generated
with the built-in image-generation tool to choose a production direction before
splitting the look into tiles, props, actors, effects, and Godot UI components.

## Concepts

1. `01_painterly_portrait.png` — premium painterly 2D, true top-down room with
   readable three-quarter-overhead actors. Highest content-production cost.
2. `02_graphic_portrait.png` — limited-tone illustrated 2D with thick silhouettes,
   reusable tiles, and cutout-friendly actors. Best match for the current rig and
   the safest non-pixel production option.
3. `03_pixel_hybrid_portrait.png` — 48 px tile-grid target with 64 x 80 logical
   actor sprites. Lowest animation and content-production risk.
4. `04_painterly_desktop_ui.png` — 16:9 Steam layout based on concept 1: central
   map, 270 px-class party rail, 300 px-class target/log rail, compact top status
   bar, minimap, and eight-slot bottom hotbar.
5. `05_zoomedout_party_graphic_desktop.png` — recommended wide-map direction.
   Roughly 22 x 13 visible tiles, four 44-54 px party sprites, role colors and
   weapon silhouettes, compact HUD, and more than 80 percent gameplay coverage.
6. `06_zoomedout_party_iconic_desktop.png` — extreme readability test. Roughly
   26 x 15 visible tiles and 36-44 px actors reduced to three values, one role
   color, one large weapon/profile cue, and a small ground chevron.
7. `07_zoomedout_party_graphic_portrait_ui.png` — portrait counterpart to concept
   5. Roughly 11-12 x 20-22 visible tiles and 40-48 px party sprites, with compact
   two-row party bars and mobile-safe controls instead of permanent side rails.
8. `08_zoomedout_party_portrait_15wide.png` — practical portrait target with about
   15 tiles visible across. It preserves distinct heads, bodies, limbs, role colors,
   and oversized equipment while showing a substantially wider encounter area.
9. `09_zoomedout_party_portrait_20wide.png` — maximum portrait zoom-out test with
   about 20 tiles across and 29-32 vertically. Actors are reduced to 24-32 px-class
   tactical silhouettes; equipment and color carry almost all role recognition.

## Implementation limits

- The images must not be sliced directly into final game assets. Perspective and
  lighting consistency need to be rebuilt as a small authored asset kit.
- The desktop mockup is intentionally limited to standard Godot Controls:
  `MarginContainer`, `HBoxContainer`, `VBoxContainer`, `PanelContainer`, `Label`,
  `TextureRect`, `ProgressBar`, `ScrollContainer`, and `Button`.
- Its frames use one rectangular nine-slice panel, a thin brass border, one dark
  fill, an 8 px spacing rhythm, and two main font sizes. No bespoke curved panels
  or overlapping modal geometry are required.
- Generated Korean copy is illustrative only. Runtime text must come from the
  existing UI/localization layer.

## Prompt contract

All concepts requested a real in-engine gameplay screenshot rather than key art:
a true 90-degree top-down rectangular dungeon map with no isometric diamond or
horizon, plus mild three-quarter-overhead actor sprites whose heads, torsos, arms,
legs, boots, and weapons remain readable. The three portrait prompts varied only
the production style: restrained painterly art, limited-tone graphic illustration,
and a 48 px modern pixel-art hybrid. The desktop prompt preserved the painterly
world while constraining every HUD region to straightforward reusable Godot UI.

The two zoomed-out prompts added a four-person formation and fixed role grammar:
ochre sword-and-round-shield leader, broad blue tank with a rectangular shield,
narrow green scout with a long diagonal bow, and an ivory/teal healer with a ring
staff. The first keeps enough illustrated anatomy for character animation; the
second deliberately tests the lower limit where characters behave almost like
tactical icons. Both remove costume seams, material grain, facial detail, and
small accessories before reducing the actor size.

The portrait conversion keeps the balanced graphic treatment and the same role
silhouettes. It uses a shallow top status strip, a 2 x 2 party summary, a small
collapsible minimap, and a bottom safe-area layout with a movement pad, two item
slots, and four 48 px-class action buttons. It does not add a target inspector or
combat-log panel that would consume the narrow gameplay width.

The last two portrait prompts test explicit camera-density targets rather than a
vague zoom level. Concept 8 requests roughly 15 logical tiles across with 36-44 px
actors. Concept 9 requests roughly 20 tiles across and 29-32 vertically with
24-32 px actors, only two or three value levels per sprite, strong colored role
blocks, oversized signature equipment, and sparse modular scenery. Both reserve
no more than 12-14 percent of screen height for bottom touch controls and constrain
the HUD to standard Godot `Control` nodes.
