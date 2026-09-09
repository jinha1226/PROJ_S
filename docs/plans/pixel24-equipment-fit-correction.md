# Pixel24 equipment fit correction

Status: visual approval withdrawn after user review. Do not publish the current
composites as a final fitted set. Keep the approved base bodies unchanged.

## Cause

The base silhouettes were recentered after the initial armor placements were
chosen. Equipment still uses fixed destination rectangles. Weapons were fitted
by their outer bounding box, not by their grip. The dwarf's entire upper area was
protected, compressing armor into a belly strip rather than layering it behind
the beard. Passing image-size tests does not establish a correct anatomical fit.

## Bounded implementation (Sol medium)

1. Freeze the latest centered bodies. Record their hashes. Measure each species'
   neck/shoulder line, torso rectangle, waist, main-hand grip, offhand grip, and
   head/beard/hand foreground regions in the actual 24px source coordinates.
   Add this explicit fit metadata beside the existing art manifest. Do not infer
   anatomy from the whole silhouette bounding box.
2. First produce a human-only comparison: unequipped, padded armor, leather
   armor, short sword, spear, bow, crossbow, and armor + sword + shield. Show both
   actual size and nearest enlargement with labels. Obtain root visual review
   before propagating to the other species.
3. Armor must reach the shoulder line and waist without covering face, beard,
   hands, or feet. Use native compositor foreground regions for the unchanged
   head/beard/hands when armor belongs behind them. Do not solve beard overlap
   by crushing the entire armor into three rows. Do not stretch a garment to
   fill arbitrary width and height independently.
4. Record grip coordinates for each existing weapon source, then align the grip
   to the species hand after uniform scaling. Sword/axe/mace grips are below
   their heads; spear grip is on the shaft; bow grip is at its central riser;
   crossbow grip is on its stock. Keep the hand visible over the grip. Keep
   weapons alongside the body, away from the face; use a compact carried pose
   for two-handed weapons rather than floating them beside the shoulder.
5. Do not introduce new item definitions. Support the two existing armor IDs,
   seven existing weapon IDs, and wooden shield. Unused steel/mithril/helmet
   candidates are not runtime equipment and must be clearly separated in review.
6. Only after the human fit is approved, measure and fit elf, dwarf, orc, and
   beastkin. Inspect all five armor variants and each supported grip family.

## Rendering and validation

- One shared interpolated actor root and 24px coordinate system for body, armor,
  equipment, foreground regions, and the two-phase foot animation.
- No changes to simulation, equipment stats, facing, tile occupancy, or movement.
- Native nearest filtering; no body recentering during equipment changes.
- Head/torso remain stable during walking; only feet animate.
- Empty slots draw the unchanged base. Portraits and world use identical fitted
  layer metadata, with walking disabled for portraits.
- Regression tests: fit metadata in bounds; grips coincide after transforms;
  protected regions preserved; equipped/unequipped anchor invariant; all species
  supported; deterministic rebuild; pixel24 and movement focused suites.
- Visual approval is separate from test success. Do not claim actual-phone
  validation without a device test. Push corrected asset previews once reviewed,
  but do not mix unfinished system code into an asset-only commit.
