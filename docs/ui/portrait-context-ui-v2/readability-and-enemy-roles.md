# Stage readability, impact feedback and enemy roles

Implemented 2026-09-15. No new third-party assets or external source code used.

## Screen

- Room board starts at 1.10×. Stage pinch zoom is restored (1.0–1.7×); it changes projection only, not turn state. The 8×8 logical room stays intact. Default view keeps all 64 tile centers accessible; enlarged views can crop edges and can be pinched back out.
- Room diamond vertical ratio is 0.65 instead of 0.5, with matching inverse touch projection. Terrain, actors and attack marks share the same mapping.
- Floor tint/edge contrast reduced; procedural floor clutter removed; dungeon wall height lowered. Sprite sheets are unchanged.
- Healthy, unselected units no longer carry HP bars. Selected or injured units still do. HOLD marks are hidden. Enemy danger footprints remain visible, but only the selected enemy gets a strong fill and connector.
- Selecting an enemy displays role, current movement allowance and base aim range in the HUD.

## Enemy behavior

Authoritative definitions: `data/content/stage_enemy_roles.json`.

| Species | Role | Base movement | Aim range | Footprint |
|---|---|---:|---|---|
| goblin | Warrior | 2 | 1 | Single tile |
| kobold | Shooter | 2 | 2–4 | Single tile |
| dcss_rat | Runner | 4 | 1 | Single tile |
| dcss_hobgoblin / dcss_orc | Heavy | 1 | 1 | Three front neighbors |
| dcss_frilled_lizard | Spitter | 1 | 2–3 | Center plus four cardinal neighbors |
| dcss_gnoll | Spear | 2 | 1–2 | Single tile |

Existing movement modifiers/injuries apply to base movement. Ranged units find reachable firing positions and back away inside minimum range. Walls block attacks. First-floor rooms now have different compositions: warrior/shooter/runner, warrior/spitter/shooter, two runners/shooter, warrior/heavy/shooter. No extra NPCs.

The same `StageEnemyRules.cells` function defines preview and execution. Attacks do not retarget a dodging unit: they affect current occupants of the announced cells, including other enemies. Each area victim uses a distinct deterministic commitment, existing hit/defense/HP/body-damage computation and normal reactions. Displacement cancels remaining strikes; targets moved out of the area are skipped. These roles currently use existing physical damage, not a new elemental-magic formula or ammunition inventory.

Fixed a related pathfinding mismatch: the search could choose reserved exit cells that movement execution rejected, causing enemies to stand still. The search now honors the same reservation rule.

## Feedback

Round results now feed the existing impact/miss/death/healing renderer instead of returning an empty effects list. Attack groups are spaced 240 ms apart; enemy movement presentation waits behind attack feedback. Ranged hits get a 140 ms projectile followed by impact. Delayed effects are deduplicated and canceled on transient reset. These are presentation timers; simulation and replay remain synchronous and deterministic.

Current limitation: this reconnects impact feedback, not a full frame-by-frame battle replay. Authoritative HP and life state still refresh when the round resolves; synchronizing every HP decrement/death silhouette with individual impact frames is follow-up work. No new directional sprite animation sheets or sound assets were added.

## Saves and validation

Nine-room generator version advanced from 3 to 4 because initial enemy composition and combat behavior changed. Start a new game to test. Old save files are not deleted.

Godot 4.6.2 in Linux validation copy:

- `stage_enemy_roles_acceptance`: movement/range/LOS/footprints; isolated actual sweep dispatch against three occupants including enemy units; distinct commitments; live role-round world audits and VFX production. PASS.
- `stage_counterplay_acceptance`: deployment, announced attacks, deterministic snapshot/journal replay, reinforcements. PASS.
- `stage_context_ui_acceptance`: native 360×800 touch flow and actual renderer receiving combat effects. PASS.
- `nine_room_ui`: 360×800 and 390×844 layout, 64-center projection roundtrip, zoom without advancing time. PASS.
- `first_floor_stages_acceptance`: authored first-floor integration. PASS.
- `settlement_work_unit`: existing CI smoke check. PASS.

Screenshots: `roles-runtime.png`, `impact-runtime.png`. These are actual native captures, not generated mockups. Physical-phone and full historical-suite coverage are not claimed.
