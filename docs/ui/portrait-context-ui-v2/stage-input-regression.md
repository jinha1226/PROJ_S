# Stage input corrections

## Scope

- Deployment uses the existing zero-time validated setup transaction. Hide normal movement overlays, suppress allied walking animation on confirmation, and allow replacing a placement with its original tile (previously intercepted as actor selection). Clear stale skill targeting during deployment.
- Enemy ranged aim must share a row or column. Forecast, firing-position search and dispatched footprints share this check. Player bow/crossbow targeting also rejects diagonals. Area splash remains an area; this does not change healing or movement abilities.
- Restore a contextual pickup button and process a tap on the hero standing over loot before the field-member selection handler. Combat pickup is reserved until Proceed; feedback now says so instead of claiming immediate receipt.
- Use debris art only for rubble, not randomly on normal floor. Reduce dungeon wall elevation from 0.65 to 0.30 half-width so its raised face does not cover the neighboring tile center. Collision rules are unchanged; authored pillars are impassable. This addresses visual ambiguity, not a reproduced wall-collision failure.
- New first-floor rosters: south opening room 7 has one goblin; rooms 0 and 6 have two enemies; room 2 retains three. Generator version 5: verify density with a new run, not an existing generated floor. Existing saves are not rewritten.

## Verification

Godot 4.6.2 headless in an imported Linux runtime mirror `/tmp/handcrafted-runtime-review-ReMPKf`:

- `stage_input_regression.gd`: pickup UI/hero tap, repeated placement including original tile, no authority/time advance on edits, no placement walking request, cardinal aim/LOS, pillar collision and canonical world audit.
- `stage_context_ui_acceptance.gd`: 360x800 touch deployment, sequential enemy presentation, enemy selection and Proceed.
- `stage_counterplay_acceptance.gd`: deployment, rounds and reinforcement/replay contracts.
- `stage_enemy_roles_acceptance.gd`: range, area dispatch, friendly fire and canonical audit. Its isolated three-actor area fixture now uses global enemy IDs rather than assuming the opening room has three enemies.

The direct workspace test initially lacked an imported UI texture and was not accepted as validation. The imported runtime mirror passed the above tests. Physical mobile browser validation and the exact reported pillar tile remain unverified.
