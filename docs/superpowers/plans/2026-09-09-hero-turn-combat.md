# Hero-Turn Combat Implementation Plan (simplified 2026-09-09)

> **대체됨 (2026-09-10)**: `2026-09-10-single-screen-combat.md` 참고.


Superseded the four-task plan: the user asked for the minimal version. No new
journal kind, no scheduler change. Implemented directly in one commit:

- `playtest/autonomous_battle_clock.gd`: `advance(delta, world_time, blocked, units_per_second, hold_at)`.
- `playtest/individual_battle_session.gd`: `hero_turn_pending()`.
- `playtest/party_encounter_sandbox.gd`: `battle_mode` (`HERO_TURN` default / `AUTO`), `_hero_turn_holds()`,
  `hero_turn_waiting()`, `_release_hero_turn()`, `_on_battle_mode_toggle()`; cell/enemy/skill inputs and
  `[진행]` release the turn; the tick loop stops before the protagonist's event while holding.
- `playtest/battle_command_flow.gd`: danger pause only in `AUTO`; `내 차례` notice; `진행` label.
- Tests: `tests/hero_turn_combat_acceptance.gd`; free-running suites pin `ui.battle_mode="AUTO"`.

Spec: `docs/superpowers/specs/2026-09-09-hero-turn-combat-design.md` (sections 2–3 rewritten).
