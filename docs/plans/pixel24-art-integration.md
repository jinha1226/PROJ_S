# Pixel24 art integration checklist

Status: approved first playable pass deployed to the runtime registries.

## Contract

- Fixed-front only. Facing data never selects, mirrors, or offsets a texture.
- Actor, equipment, and monster runtime images are true 24x24 RGBA canvases.
- All layers share the same canvas center and foot anchor. Empty equipment slots
  render the base alone.
- Terrain is two distinct 4x4 atlases, each 96x96 pixels with 24x24 cells.
- Rendering is presentation-only: no terrain mapping, FOV, collision, occupancy,
  health, inventory, or simulation state is changed by the art registry.
- Generated source sheets are retained verbatim under
  `assets/pixel24_v3/source/`. They are never advertised as native pixel art.
- Every extraction uses an explicit integer source-cell crop in
  `tools/art/pixel24_manifest.json`. A keyed cell may use deterministic
  alpha-bounds trimming inside that declared crop; final fit size and placement
  on the 24px canvas remain explicit in the manifest.
- Alpha removal is explicit per entry. If an opaque generated background touches
  or contaminates a silhouette, reject that crop and request a transparent or
  flat-key source instead of erasing pixels heuristically.

## Source acceptance gate

- [x] Record source dimensions in the manifest and retain source files.
- [x] Fill every source-cell crop rectangle from the actual source dimensions.
- [x] Confirm each crop contains one complete subject with clearance around it.
- [x] Confirm equipment layers contain no baked body, face, beard, or feet.
- [x] Confirm armor fit is authored for the declared body-fit class: `slender`,
  `standard`, or `broad`.
- [x] Confirm terrain sheets contain exactly 16 isolated cells per floor and no
  random road painted into ordinary floor variants.
- [x] Select alpha policy explicitly: source alpha or saturated-magenta key.
- [x] Reject the checkerboard equipment source and rejected monster candidates.

## Deterministic build

- [x] Run `godot --headless --path . --script tools/art/build_pixel24_assets.gd`.
- [x] Crop using manifest coordinates, resize with nearest-neighbor, apply
  the declared palette limit, and threshold alpha to 0/255.
- [x] Normalize the approved keyed seven-character strip into native24 bases.
- [x] Write actors/equipment/monsters as individual 24x24 PNGs.
- [x] Assemble each terrain floor as a row-major 4x4 96x96 PNG atlas.
- [x] Generate an enlarged nearest-neighbor contact sheet and an actual-size
  layered composite review.
- [ ] Re-run the build and verify byte-identical output hashes.

## Required mappings

- Bodies: human, elf, dwarf, orc, beastkin.
- Armor/body layers: cloth/padded, leather, steel, mythril/mithril; hood and
  helmet are separate head layers when present in the item definition mapping.
- Weapons: short sword, thrusting sword, hand axe, mace, spear, bow, crossbow.
- Monsters: goblin, kobold, slime, beetle. Missing optional source art must fall
  back safely and must not change the actor species or faction presentation.
- Terrain semantics on both floors: quiet floor, stone floor, wood, metal,
  rubble, shallow water, blocking wall, inactive portal, active portal.

## Visual approval gate

- [x] Review five unequipped bases at 1x and nearest-enlarged scale.
- [x] Review every armor and weapon on standard, slender, and broad
  torsos; nothing may cover the face, beard, or feet.
- [x] Review empty equipment as base-only.
- [x] Review goblin/kobold as both hostile and friendly/neutral presentation.
- [x] Review slime and beetle output.
- [x] Review floor 1 (moss/forest/ruins) and floor 2 (ash/foundry) side by side.
- [ ] Review an 18x18-cell portrait viewport at actual mobile sampling scale.
- [x] Obtain explicit approval of normalized review sheets before changing the
  live registries.

## Runtime cutover

- [x] Point `FixedFrontTopdownAssets` to `assets/pixel24_v3/runtime`.
- [x] Enable equipment layers and map only existing item-definition IDs.
- [x] Use a 24x24 source canvas, common zero center offset, and common foot pivot.
- [x] Point `TopdownTileAssets` to distinct 96x96 floor atlases with 24px cells.
- [x] Keep nearest filtering through import and runtime presentation settings.
- [x] Add motion-only two-phase biped feet with no idle loop, flip, or body bob.
- [x] Do not add direction transforms, random animation, or simulation mutations.

## Acceptance

- [x] Every actor/equipment/monster PNG is 24x24 RGBA with binary alpha.
- [x] Both terrain PNGs are 96x96 (4x4 cells) and resolve distinct textures.
- [x] Every active manifest crop is integer-valued and in source bounds.
- [x] Empty gear yields no overlay; equipped known IDs resolve the expected layer.
- [x] Five base silhouettes share center and foot-anchor invariants.
- [x] West/east/north/south DTOs produce identical texture references.
- [x] Both floors map all declared semantics; portals have inactive/active art.
- [x] Render-spec calls do not mutate their actor/cell inputs.
- [x] Godot editor parses the project and the focused pixel24 acceptance suite
  exits successfully.

Actual physical-device testing of an 18x18 viewport is not yet performed. The
actual-size composite exists for desktop inspection; device validation remains
an explicit follow-up rather than a claimed result.
