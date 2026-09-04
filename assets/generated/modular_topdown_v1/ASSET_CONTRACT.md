# Modular top-down 2D rig contract

This pack is a pure 2D paper-doll asset kit. Runtime characters are composed from
`Node2D` / `Sprite2D` layers; no 3D camera, skeleton, mesh, or `Sprite3D` is part
of the product renderer.

## Direction contract

Runtime direction IDs and authored views are fixed to this order:

1. `south` — actor faces screen bottom
2. `north` — actor faces screen top
3. `west` — actor faces screen left
4. `east` — actor faces screen right

No runtime view may be synthesized by rotating a completed character. Left and
right are authored independently. Direction changes swap textures without
changing simulation position.

## Species body sheets

One 2 x 2 transparent atlas is authored per species:

```text
south | north
west  | east
```

Each cell contains one complete unarmed base body with a readable head, torso,
two arms, two hands, two legs, and two feet. Species sheets contain no armor,
weapon, shield, backpack, jewelry, or role color. All cells use the same canvas,
center registration, contact scale, foot position, and neutral light.

Required species: `human`, `elf`, `dwarf`, `orc`, `beastkin`, `goblin`.

## Equipment sheets

Every visible equippable item owns a separate 2 x 2 transparent atlas:

```text
south | north
west  | east
```

Every item uses the same full-character canvas as the body sheet. Weapons include
only the weapon and the minimum hand-contact overlap needed for registration.
The shield contains only the shield. Armor is a body-aligned clothing overlay and
must not contain skin, a head, hands, legs, weapons, or shadows. Runtime selects
the same direction ID for body and every equipped layer.

Required equipment IDs:

- `WEAPON_SHORT_SWORD`
- `WEAPON_THRUSTING_SWORD`
- `WEAPON_HAND_AXE`
- `WEAPON_MACE`
- `WEAPON_SPEAR`
- `WEAPON_BOW`
- `WEAPON_CROSSBOW`
- `ARMOR_LEATHER`
- `ARMOR_PADDED`
- `SHIELD_WOOD`

## Runtime layer order

Each direction has an explicit item order instead of relying on node insertion
order. Back-facing weapons/shields may render behind the body; front-facing
weapons/shields render above armor. The contact shadow is always below every body
and equipment layer. A short movement bob and squash are 2D presentation only.

Generated source images are preserved under `source/`. Normalized runtime atlases
use transparent pixels and power-of-two dimensions under `runtime/`.
