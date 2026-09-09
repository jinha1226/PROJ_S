# Living Expedition V2 implementation plan

## Guardrails

- Preserve all inherited town, NPC, inspector, and UI work in the dirty tree.
- Gate new behavior behind the versioned `campaign.living_expedition_initialized`
  event. Legacy snapshots and campaigns must keep their existing terrain,
  visitors, combat, and progression behavior.
- Use canonical movement, melee, damage, body, inventory, event, and replay
  paths. Do not add a parallel damage or inventory model.
- Runtime presentation may use existing project art and native controls/symbols
  only. `assets/living_expedition_v2/` remains review-only.
- Keep simulation mutations in actor ticks and commands, never rendering,
  inspection, or paused UI paths.
- Run one bounded Godot process at a time. Add focused tests only; do not expand
  CI or run the full slow simulation suite.

## Implementation checklist

### 1. Versioning, campaign creation, and species

- [x] Audit the new-run flow so the picker exposes human, elf, dwarf, orc, and
  beastkin and the selected species reaches the canonical party bootstrap.
- [x] Ensure ordinary new campaigns enable living-expedition V2 once, while
  legacy load/reset flows do not silently opt in or reroll existing content.
- [x] Verify fixed species traits remain visible and effective alongside
  personal talents in member summaries, progression DTOs, and growth modifier
  calculations; make only focused compatibility fixes.
- [ ] Keep generated town residents persistent and varied in species and
  personality, without replacing existing residents on load.

### 2. Physical independent explorers

- [ ] Make each visitor one canonical world entity tagged as an independent
  explorer and physically placed on its assigned floor; never auto-add it to
  the player party.
- [ ] Harden all entity scans against deleted/invalid IDs and absent combatant,
  party-member, item, and population rows.
- [ ] Tighten occupancy validation so active physical visitors participate in
  normal duplicate-position invariants. Exempt only explicit inactive states
  such as returned actors, and make `environment_entities_at` agree.
- [ ] Use canonical pathfinding and movement commit results. Route around
  hazards and occupied cells instead of repeatedly rejecting the first A* step.
- [ ] Drive EXPLORE/FIGHT/REST/RETURN decisions from stable personality, HP,
  supplies, fatigue, and distance inputs. Persist activity, coordinates,
  rest timing, downed/dead state, and return state in population events.
- [ ] Make return remove the actor from physical dungeon occupancy without
  deleting its identity/history.

### 3. Combat, aid, and causal history

- [ ] Resolve independent attacks through canonical melee assessment,
  projection, weapon/body damage, and canonical MISS/PARRIED/HIT/FINISHER child
  event families.
- [ ] Let enemies select fairly among adjacent valid player and independent
  targets; share enemy busy clocks so an independent interaction cannot create
  an extra enemy turn or player-first immunity.
- [ ] Persist downed/dead transitions through canonical damage events and show
  those states in activity/history.
- [ ] Restrict player XP/kill credit for enemy deaths caused solely by neutral
  actors, behind the V2 gate, while preserving legacy awards and replay rules.
- [ ] Fix AID as a real inventory transfer: consume the selected player ration,
  add the intended independent NPC ration, emit causally valid data, and update
  its supply/activity state.
- [ ] Validate rest healing against prior health and canonical item use; ensure
  history replay sees the same health bookkeeping.
- [ ] Teach causal position lookup/replay validation that
  `population.arrived` is a physical placement/teleport event.

### 4. Floors, discovery pockets, and presentation

- [ ] Build deterministic V2 entry pockets for floor 1 (forest/ruins) and floor
  2 (foundry), version-gated so old saves retain their maps.
- [ ] Flood-check walkable connectivity among entry, exit, portal/transition,
  supply landmarks, and all physical visitor spawn positions.
- [ ] Do not create fake terrain beneath actors; choose valid, unoccupied,
  reachable spawn cells from the real generated map.
- [ ] Present landmark data with existing art or modest native symbols and keep
  visitor positions synchronized in map translation.
- [ ] Report actual coordinates/species/activity for physically present
  RECRUITABLE visitors in the same actor inspector used elsewhere.
- [ ] Keep UI readable and modest, and verify render, inspect, and pause paths do
  not advance simulation state.
- [ ] Retain prior workplace navigation, supply purchase, and inspector touch
  fixes.

### 5. Focused verification

- [x] Add `tests/living_expedition_acceptance.gd`, split into targeted helpers
  where useful, covering: five-species creation plus personal talent and town
  departure; physical neutral non-party actors; personality behavior choices;
  observed movement/rest/reciprocal combat/aid/return/downed/dead; no faction
  autojoin; real inspector coordinates; pause/inspection immutability; exact
  save/load deterministic replay; legacy non-opt-in; and map flood connectivity.
- [x] Update affected sandbox-launch tests to select species explicitly rather
  than weakening timing/assertions.
- [x] Run focused living-expedition tests, then the inherited NPC inspection,
  town navigation, and battle command flow acceptance tests serially.
- [ ] Run relevant legacy species/progression/save tests and a bounded headless
  editor parse. Capture each log under `/tmp` and report failures honestly.
- [x] Review the final diff for accidental generated assets, CI changes, large
  modules, unrelated reversions, or replay nondeterminism.
