# Item and building art integration — 2026-09-09

## Selected sources and prompts

- Items: `source/items-generated-v1.png`; final prompt and background correction
  in `source/ITEMS_PROMPT.md`.
- Buildings: `source/buildings-generated-v2.png`; final prompt and perspective
  correction in `source/BUILDINGS_PROMPT.md`. The v1 source is retained for comparison.
- Sources were created with the built-in image-generation tool, using the approved
  character/equipment and floor review sheets as style references.

## Runtime assets

- Fifteen item/resource/presentation icons and one transparent reserved cell:
  `runtime/items/`, 24×24 with centered silhouettes inside a 20×20 safe region.
- Eighteen buildings: `runtime/buildings/`, six types × camp/timber/stone art.
  STORAGE/CLINIC/GATE are 72×72; LODGE/MARKET/ARMORY are 72×48.
- Reserved key/blank artwork does not register new gameplay items. Unavailable
  building upgrades are not unlocked by the existence of stage artwork.
- Existing equipment sprites, building footprints, collision, progression,
  inventory quantities, construction progress and interaction rules are unchanged.

## Rebuild and review

Use the existing Godot extraction tool with either manifest:

```sh
godot --headless --path . --script tools/art/build_pixel24_assets.gd -- res://tools/art/pixel24_items_manifest.json
godot --headless --path . --script tools/art/build_pixel24_assets.gd -- res://tools/art/pixel24_buildings_manifest.json
```

Explicit per-subject crops prevent adjacent-row bleed. Background keying happens
before nearest-neighbor resizing and palette reduction. Building-only hue cleanup
removes magenta fringes without affecting the purple potion. Generated source
grids are not treated as exact tile geometry.

- Item review: `review/items-v1/actual-size-contact.png` and `nearest-contact-8x.png`.
- Building review: `review/buildings-v2/actual-size-contact.png` and `nearest-contact-4x.png`.

## Consumers and scope

- `playtest/pixel24_item_assets.gd` shares icon lookup across inventory and visible
  ground items; `base_resource_icon.gd` uses the same resource sprites.
- `playtest/pixel24_building_assets.gd` supplies stage textures to
  `base_settlement_view.gd`, used by the town and base maps.
- Empty inventory slots and construction/selection overlays remain code-drawn.
- Fogged ground items remain hidden. No new gameplay definitions or save fields
  are introduced by this art integration.
- Focused regression: `tests/pixel24_item_building_acceptance.gd`.

Native review sheets have been visually inspected. Final mobile-device appearance
still requires checking at the player's actual screen size and zoom setting.
