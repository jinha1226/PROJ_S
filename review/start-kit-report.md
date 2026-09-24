# Starting kit — implementation report

Branch `feat/start-kit`, on top of `b849194`.

## What was built

**Data** — `data/content/combat.json` gains an ordered `kits` array of ten rows
(`id`, `axis`, `name`, `weapon`, `spell`, `blurb`), one per `Mastery.AXES`: five
weapons, five staves. `CombatStats.kits()` and `CombatStats.kit(id)` read it.

**The run** — `Session.kit_id` (default `"sword"`),
`Session.new_run(seed, kit_id := "sword")`; the one-argument call still departs
with the sword. `depart()` checks the kit before it touches any run state, so an
unknown id refuses and leaves the session IDLE; `new_run` returns `null` for one.
A departure sets `gear.weapon` from the kit, a robe, `skill_xp[axis] = 25`
(rank 1), and for a magic kit `spells = prepared = [spell]`.

**Start screen** — `build_start_screen` now carries a `KitPick` column of two
`KitRow` lines with five `Kit_<id>` buttons each. Each button is 48px tall (two
rows fit a 390px width at five per row), font 11, `clip_text`, and shows the kit
name over a data-built line: `피해 %d · 속도 %d · 사거리 %d` for a weapon,
the spell's name plus the kit blurb for a staff. The full line is also the
tooltip, since 78px clips it. The chosen kit wears the same gold `e9c575`
border a selected member card does; `main.kit_choice` holds it and `NewRun`
spends it. The result card's `NewRun` now returns to the start screen (the
duplicate `시작 화면` button below it was folded into it) so the picker shows
again after a defeat.

**Spells** — `IMPLEMENTED` gains `cone`, `cloud`, `hound`.
- `cone` (ice): the aimed cell and the two square across the caster→target line
  (`cone_cells`), `power` as `ice` to each foe, `slow` until `s.time + 200`.
- `cloud` (air): the aimed cell and its eight neighbours, `power` as `air` to
  foes only, no lingering cloud.
- `hound` (summon): `Spells.summon` mints an npc-shaped actor via
  `s.make_actor(2000 + s.time % 1000, "사냥개", false)`, `npc/awake/summoned`
  true, `expires_at = s.time + 300`, hp 20, stance CHARGER, empty gear, on the
  first free cell the caster can reach with an arm, appended to `s.npcs`. It
  fights through the existing wanderer branch and `friends()` already counts it.
  `Scheduler.environment_tick` drops summons whose `expires_at <= s.time`
  (hp 0, out of `npcs`).
- `can_cast`: `hound` needs a free adjacent cell and ignores the target;
  `cone`/`cloud` join `bolt`/`confuse` in needing a visible foe in range and in
  line. `cells` answers `[]` for `hound`.

**Summons are not people** — `Recruit.can_aid`, `Recruit.propose` and
`Recruit.recruit` refuse a `summoned` actor, and `Session.offer` never lets one
ask to join. They are never on the roster, so `companion_rows` never sees them.

No AI file was touched.

## Behaviour changes that moved existing expectations

Departing at rank 1 in the kit's axis shifts three numbers that three suites
pinned at rank 0. No check was removed; the expectation was corrected in place.

| file | checks before | checks after | change |
|---|---|---|---|
| `tests/model_b_combat.gd` | 11 | 11 | starting sword is now damage 13 / delay 116 (rank 1) |
| `tests/model_b_scheduler.gd` | 11 | 11 | `field()` clears `skill_xp` so the suite measures catalog weapon delays |
| `tests/integration.gd` | 5328 | 5328 | the wall-shove carries `+rank(sword)`, as `Abilities.power` has always done in manual mode |
| `tests/start_kit.gd` | — | 168 | new suite |

## Verification

Import check clean (no `SCRIPT ERROR:` / `ERROR:`). The full CI list plus
`start_kit`: 46/46 suites green.

## Concerns

- `cloud`'s school in `combat.json` is `hex`, not `air`, so the 폭풍 지팡이 kit
  grants its 25 xp in `air` while casting `cloud` trains `hex` and its power
  scales off the `hex` rank. The damage element is `air` as specified. The kit
  table and the spell table disagree; a later pass may want an `air` `cloud` row
  or a `bolt`-style storm spell.
- A summoned hound's id is `2000 + s.time % 1000`: two hounds summoned exactly
  1000 ticks apart would share an id. Nothing in the run depends on summon ids
  today, but it is not a guarantee.
- `Mastery.weapon_axis("staff")` still answers `mace`, so a staff's melee swings
  train 둔기술 while the kit's own axis is the school. Unchanged by this work.
- `NpcRoster.place` resets `s.npcs`, so a hound does not survive a descent —
  which is right, but it is incidental rather than stated.
