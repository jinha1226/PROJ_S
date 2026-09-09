# Pixel24 base-body fit audit

Read-only measurement of the current 24×24 base sprites under
`assets/pixel24_v3/runtime/actors/base/`. Coordinates are zero-based and
rectangles are inclusive. This is an overlay authoring guide; it does not
authorize changing the base sprites.

## Recommended anchors

| Species | Torso overlay rect | Shoulder row | Waist row | Head/neck foreground mask | Hand/grip pixels |
|---|---:|---:|---:|---|---|
| human | x5–17, y12–19 | y13 | y18 | preserve base head x4–18, y2–12; always exclude neck/face x8–15, y10–12 from armor | L (5,18), R (17,18) |
| elf | x5–17, y12–19 | y13 | y18 | preserve x2–20, y2–12 because the ears reach x2/x20; exclude neck/face x7–16, y10–12 | L x5–6/y18, R x16–17/y18 |
| dwarf | x3–20, y13–19 | y14 | y18 | preserve head x4–19, y2–9 and beard x4–19, y9–18; central beard exclusion x5–18, y9–17 must composite above chest armor | L (4,17), R (19,17) |
| orc | x5–17, y12–19 | y13 | y18 | preserve x4–18, y2–12; the wide ear/jaw row is y9, and neck exclusion is x7–15, y10–12 | L (5,18), R (17,18) |
| beastkin | x5–17, y13–19 | y14 | y18 | preserve ears/head x4–18, y2–13; exclude muzzle/neck x7–15, y10–13 | L (5,18), R (17,18) |

The torso rectangle is the maximum useful fitting envelope, not a solid fill.
Armor must retain transparent pixels outside the species silhouette. Shoulder
pixels may begin on the listed row, but any overlap with the foreground mask
must render behind the original head/neck pixels.

## Composition contract

Use this order for a fitted actor:

1. base body;
2. armor torso and shoulder layer, clipped to the torso envelope;
3. original species head/neck foreground mask (including elf ears, beastkin
   muzzle, and the full dwarf beard);
4. weapon layer aligned to the measured palm/grip pixels.

Do not use one shared opaque shoulder bar. Human/elf/orc shoulders can share a
y13 template only after applying their distinct head exclusions. Dwarf and
beastkin shoulders should start one row lower at y14. The dwarf beard is not a
small chin patch: it occupies the center of the chest through y17 and must be
restored over armor.

For one-pixel weapon handles, place the grip center on the listed palm pixel.
For the elf's two-pixel palms, either inner pixel is valid, but use x6 on the
left and x16 on the right for the least lateral silhouette growth. Weapons
should not move the hands themselves.

## Pixel evidence

Current nontransparent scan-line extents around the fit boundary:

- human: y12 x6–16; y13–15 x5–17; y16–18 x4–18; y19 x5–17.
- elf: y12–15 x5–17; y16–17 x4–17; y18 x5–17; y19 x6–17.
- dwarf: y12 x4–20; y13–17 x3–20; y18 x4–19; y19 x5–18.
- orc y12–14 x5–17; y15 x5–18; y16–18 x4–18; y19 x5–17.
- beastkin: y12 x4–18; y13–16 x5–17; y17–18 x4–18; y19 x5–17.

Whole-sprite alpha bounds are human/orc/beastkin 15×21 at +4,+2, elf 19×21
at +2,+2, and dwarf 18×21 at +3,+2. These bounds explain why a globally
centered equipment overlay can look numerically centered but still collide
with species-specific ears, beard, or shoulders.
