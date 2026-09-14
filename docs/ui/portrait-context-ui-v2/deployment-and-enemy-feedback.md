# Deployment and enemy feedback fix

## Cause and changes

- Placement edited a round plan but the grid still rendered authoritative (old) actor positions; it had no deployment-zone indicator. The detached grid observation now renders party members at planned destinations, with valid entry-zone cells highlighted. Confirmation still commits once with zero world time. Placement uses a setup budget (12 path/cost units), not the injured actor's first-turn movement budget. Paths stay inside the entry radius; duplicate allied destinations are rejected. Doorway taps cannot accidentally exit during deployment.
- Round feedback omitted movement event IDs. Existing animation only supported a one-cell displacement, making multi-cell enemy setup jump directly to its final state. Round results now expose their committed event IDs. Stage enemy movement paths are replayed visually in event order, 160 ms per cell plus 80 ms between actors. Shared movement sampling follows every path segment rather than cutting diagonally across corners. Simulation remains deterministic and synchronous; animation does not mutate the simulation.
- Progress, skill buttons and board commands are gated while that presentation runs; attack overlays appear when it finishes. This is a presentation gate, not a new save-game phase.
- First enemy tap selects/inspects; second tap on the same enemy stages melee. Explicit attack targeting still stages melee directly. The selected enemy's published attack tile has a red fill and stronger diamond outline. Preview uses the existing fixed target cell, not a new forecast.

## Validation

Godot 4.6.2, Linux validation copy:

- `tests/stage_context_ui_acceptance.gd`: native 360×800 touch dispatch to a deployment tile, immediate visual placement, authoritative position unchanged until confirmation, sequential non-overlapping enemy movement, waiting/ending motion samples, duplicate-progress prevention, first-tap inspection and second-tap attack, zero-time deployment and one-round execution. PASS.
- `tests/nine_room_ui.gd`: 360×800 / 390×844 layout and room UI checks. PASS.
- `tests/stage_counterplay_acceptance.gd`: deployment, fixed attack plans, deterministic replay, reinforcements and world audit. PASS.
- Selected attack screenshot: `selected-attack-runtime.png`.

No physical phone verification or full historical test-suite claim. HP, damage and injury formulas are unchanged. Placement still requires a traversable path and cannot swap occupied starting tiles atomically.
