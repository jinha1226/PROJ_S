# Essence Content Implementation Plan (Plan 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the essence system with content: five caster species, boss essences of their own, block and resistance values on every monster, element variants with a per-floor main element, and deep-floor monster scaling.

**Architecture:** Variant parts are not new catalog rows. An id `"<BASE_ID>@<element>"` resolves to the base part plus an element through two new helpers in `abilities.gd` (`has`, `definition`), and every reader of the parts catalog goes through them. A new `expedition/level/variants.gd` decides a floor's main element and which minted monsters become variants. Monster data (block, resistances, allowed variants, caster species) lives in `data/content/floor_monsters.json`; boss essences are rows in `data/content/essences.json`.

**Tech Stack:** Godot 4.6 GDScript, JSON content files, Python 3 + Pillow art scripts (`tools/art/`), headless Godot test suites.

**Spec:** `docs/superpowers/specs/2026-09-25-bestiary-progression-design.md` (§2.4, §3.6, §3.7, §5). Plan 1 (the essence rules engine, in `docs/superpowers/plans/`) must be fully merged before this plan starts. Plan 3 (UI, NPC choice, difficulty gate) follows this one.

## Global Constraints

- Plan 1 is done: `expedition/progression/essences.gd`, `expedition/progression/stat_sheet.gd`, `data/content/essences.json`, `Session.essence_seen`, `Session.absorb_essence` exist with the interfaces listed below. Do not redefine them.
- Elements are exactly `fire, ice, air, poison, will` (화염, 냉기, 전기, 독, 의지). Opposites: `fire ↔ ice` only.
- Variant essence id format: `"<BASE_ID>@<element>"`. `Essences.row(id)` (Plan 1) already resolves it to the base row + that element tag + its resistance +10.
- Variant monster: resistance 50 to its own element, −25 to the opposite element.
- Floor 1 spawns base species only. On deeper floors at least half of the variants use the floor's main element. The floor's element is announced on entry.
- Variants are only made for elements that suit the species: two or three per species, never all five. Caster species have no variants.
- Deep floors: past the deepest catalogued `max_depth`, each floor adds monster HP +12% and attack +8%.
- Bosses carry their own essence and it always drops.
- Caster species' monster attacks are `monster_only`: a party member who holds the essence never gets that part as an action (its active is the chosen spell from Plan 1).
- Test command: `godot --headless --path . --script res://tests/<suite>.gd` from `/mnt/d/SS/new`. Import after art changes: `godot --headless --path . --editor --import --quit`.
- Several sessions work in this repo. Stage and commit only this plan's files with explicit paths (`git commit -m "..." -- <paths>`). End every commit message with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

### Plan 1 interfaces this plan uses

- `expedition/progression/essences.gd`: `const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}`, `static func has(id: String) -> bool`, `static func row(id: String) -> Dictionary` (`{"name","stats","role","element","school","species"}`), `static func drop_chance(s, species_id: String) -> int`.
- `data/content/essences.json`: `{"version":1,"rows":{ID:{"name","stats","role","element","school","species"}}}`, already holding the eight species parts and `FIRE_CALLER`, `FROST_IMP`, `STORM_BAT`, `GOBLIN_HEXER`, `GNOLL_SUMMONER` with species ids `kobold_firecaller`, `frost_imp`, `storm_bat`, `goblin_hexer`, `gnoll_summoner`.
- `expedition/progression/stat_sheet.gd`: `const RES := ["fire","ice","air","poison","will"]`, `const RES_CAP := 80`. For enemies it reads the actor fields `ac`, `ev`, `sh`, `res`.
- `expedition/items/gear.gd` `roll_part` calls `Essences.drop_chance(s, <species key>)`.

## File Structure

| File | Responsibility |
| --- | --- |
| `expedition/items/abilities.gd` (modify) | Variant id helpers (`base_id`, `element_of`, `has`, `definition`, `usable_by`, `kind_key`, `scaled`), element effects of parts, caster monster attacks, `monster_only` in `holds` |
| `expedition/ai/tactic_rules.gd` (modify) | `skill(id)` resolves variant ids |
| every other reader of `Abilities.DEFINITIONS` (modify) | Read through `Abilities.has` / `Abilities.definition` |
| `data/content/floor_monsters.json` (modify) | `sh`, full `res`, `variants` on every species; five caster species |
| `expedition/level/continuous_floor.gd` (modify) | Copy `sh` on spawn, call variant assignment, floor `element`, `deep_scale` |
| `expedition/level/variants.gd` (create) | Floor main element, which monsters become variants, applying a variant |
| `expedition/combat/combat_rules.gd` (modify) | Negative resistance is a weakness |
| `expedition/actors/boss_ai.gd` (modify) | Boss essence and species per pattern, deep scaling |
| `expedition/actors/monster_ai.gd` (modify) | Attack scaling on strikes, intents and role spells |
| `data/content/essences.json` (modify) | Boss essence rows |
| `tools/art/build_monsters.py`, `tools/art/build_game_sprites.py` (modify) | Five caster sprites |
| `expedition/art/mobile_art.gd`, `expedition/ui/battle_actor_visual.gd` (modify) | Caster sprites, element tint and mark on variants |
| `tests/variants.gd` (create) | Variant ids, monster data, element effects, weakness, floors |
| `tests/caster_species.gd` (create) | Caster species, boss essences, deep scaling |
| `tests/encounter_builder.gd`, `tests/mobile_hud.gd` (modify) | Species count, sprite checks |

---

### Task 1: Variant part ids resolve everywhere

**Files:**
- Modify: `expedition/items/abilities.gd`
- Modify: `expedition/ai/tactic_rules.gd:27-28`
- Modify: every file listed by the grep in Step 3
- Test: `tests/variants.gd` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces (all static in `expedition/items/abilities.gd`):
  - `const ELEMENT_NAMES := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}`
  - `const ELEMENT_FORMS := {"fire":"FIRE","ice":"ICE","air":"AIR","poison":"POISON","will":"WILL"}`
  - `const OPPOSITE := {"fire":"ice","ice":"fire"}`
  - `base_id(id: String) -> String`, `element_of(id: String) -> String`
  - `has(id: String) -> bool`, `definition(id: String) -> Dictionary` (`{}` when unknown; a variant is the base copy with `element`, prefixed `name`/`item`, extended `description`)
  - `usable_by(actor: Dictionary, id: String) -> bool` (false for `monster_only` parts on non-enemies)
  - `kind_key(enemy: Dictionary) -> String` (`"goblin"` or `"goblin@fire"`)

- [ ] **Step 1: Write the failing test**

Create `tests/variants.gd`:

```gdscript
extends SceneTree
## Element variants (spec §3.7): part ids "<BASE>@<element>", the element an
## active carries, monster block and resistances, and the floors' main element.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	resolution()
	print("Variants: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func resolution() -> void:
	check(Abilities.base_id("GOBLIN_SHIV@fire") == "GOBLIN_SHIV" and Abilities.base_id("GOBLIN_SHIV") == "GOBLIN_SHIV","base id strips the element")
	check(Abilities.element_of("GOBLIN_SHIV@fire") == "fire" and Abilities.element_of("GOBLIN_SHIV") == "","element is read from the id")
	check(Abilities.has("GOBLIN_SHIV@fire") and Abilities.has("GOBLIN_SHIV"),"base and variant ids resolve")
	check(not Abilities.has("GOBLIN_SHIV@lava") and not Abilities.has("NOPE@fire") and not Abilities.has("NOPE"),"unknown bases and elements do not resolve")
	var def: Dictionary = Abilities.definition("GOBLIN_SHIV@fire")
	check(str(def.get("element","")) == "fire","the variant carries its element")
	check(str(def.name).begins_with("화염 ") and str(def.item).begins_with("화염 "),"the variant is named for its element")
	check(int(def.damage) == int(Abilities.DEFINITIONS.GOBLIN_SHIV.damage) and int(def.range) == int(Abilities.DEFINITIONS.GOBLIN_SHIV.range),"the variant keeps the base numbers")
	check(not Abilities.DEFINITIONS.GOBLIN_SHIV.has("element"),"the base definition is left untouched")
	check(Abilities.definition("GOBLIN_SHIV@fire") == def,"the variant definition is stable between calls")
	check(Abilities.definition("NOPE").is_empty() and Abilities.definition("GOBLIN_SHIV@lava").is_empty(),"unknown ids give an empty definition")
	check(Abilities.definition("GOBLIN_SHIV") == Abilities.DEFINITIONS.GOBLIN_SHIV,"a base id gives the catalog row")
	check(str(Rules.skill("GOBLIN_SHIV@fire").get("name","")).begins_with("화염 "),"rules resolve a variant skill")
	check(Rules.valid(Abilities.default_rule("GOBLIN_SHIV@fire")),"a variant's default rule is valid")
	check(Abilities.badge("GOBLIN_SHIV@fire") == str(Abilities.DEFINITIONS.GOBLIN_SHIV.short),"a variant keeps the base badge")
	check(Abilities.kind_key({"species_id":"goblin","variant_element":"fire"}) == "goblin@fire","a variant kill is keyed by species and element")
	check(Abilities.kind_key({"species_id":"goblin"}) == "goblin","a base kill is keyed by species")
	check(Abilities.usable_by({"enemy":false},"GOBLIN_SHIV@fire") and not Abilities.usable_by({"enemy":false},"NOPE"),"a party member may use a known variant")
	var s = Session.new_run(731)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities[0] = "GOBLIN_SHIV@fire"
	check(Abilities.holds(hero,"GOBLIN_SHIV@fire"),"a party member holds an equipped variant")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/variants.gd`
Expected: FAIL with a parse error such as `Invalid call. Nonexistent function 'base_id'`.

- [ ] **Step 3: Route every catalog read through the helpers**

The catalog is read in about 70 places. Rewrite them mechanically (the legacy DCSS registry has its own unrelated `DEFINITIONS` and is excluded):

```bash
cd /mnt/d/SS/new && python3 - <<'EOF'
import pathlib, re
root = pathlib.Path("expedition")
changed = []
for path in root.rglob("*.gd"):
    if "legacy" in path.parts or path.name == "tactic_rules.gd":
        continue
    text = path.read_text(encoding="utf-8")
    new = re.sub(r'DEFINITIONS\.has\(', 'has(', text)
    new = re.sub(r'DEFINITIONS\.get\(([^,()]+),\s*\{\}\)', r'definition(\1)', new)
    new = re.sub(r'DEFINITIONS\[([^\]]+)\]', r'definition(\1)', new)
    if new != text:
        path.write_text(new, encoding="utf-8")
        changed.append(str(path))
print("\n".join(sorted(changed)))
EOF
grep -rn "DEFINITIONS" expedition --include=*.gd | grep -v "legacy/"
```

Expected from the final grep: only lines that iterate or list base ids remain, namely `const DEFINITIONS = {` and the `for id in DEFINITIONS:` loops in `abilities.gd`, `Abilities.DEFINITIONS.keys()` in `ui/screens/arena_setup.gd`, `for id in Abilities.DEFINITIONS:` in `items/gear.gd` (test loadout), and `load("res://expedition/items/abilities.gd").DEFINITIONS` in `ai/tactic_rules.gd`. If any other `DEFINITIONS[`, `DEFINITIONS.has(` or `DEFINITIONS.get(` remains, rewrite it by hand the same way.

Inside `abilities.gd` the rewrite turns bare `DEFINITIONS.has(id)` into `has(id)` and `DEFINITIONS[id]` into `definition(id)`; both are the static functions added in the next step.

- [ ] **Step 4: Add the helpers to `abilities.gd`**

Insert directly after the line `const BASIC_BADGES := {"ATTACK":"공격","MOVE":"이동","WAIT":"대기"}`:

```gdscript

## Element variants (spec §3.7). "<BASE_ID>@<element>" is the base part with an
## element: same numbers, its element's damage and mark. Every reader of the
## catalog goes through `has` and `definition`, so a variant id works anywhere
## a base id does.
const ELEMENT_NAMES := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}
const ELEMENT_FORMS := {"fire":"FIRE","ice":"ICE","air":"AIR","poison":"POISON","will":"WILL"}
const ELEMENT_NOTES := {"fire":"화염: 맞은 칸에 불이 붙음","ice":"냉기: 둔화","air":"전기: 젖은 대상에게 피해 +4","poison":"독: 중독","will":"의지: 혼란"}
const OPPOSITE := {"fire":"ice","ice":"fire"}
static var variant_cache: Dictionary = {}

static func base_id(id: String) -> String:
	var at := id.find("@")
	return id if at < 0 else id.substr(0,at)

static func element_of(id: String) -> String:
	var at := id.find("@")
	return "" if at < 0 else id.substr(at+1)

static func has(id: String) -> bool:
	var element := element_of(id)
	return DEFINITIONS.has(base_id(id)) and (element.is_empty() or ELEMENT_NAMES.has(element))

## The catalog row for `id`; a variant is a copy of its base with the element.
static func definition(id: String) -> Dictionary:
	if not has(id): return {}
	var element := element_of(id)
	if element.is_empty(): return DEFINITIONS[id]
	if not variant_cache.has(id):
		var def: Dictionary = DEFINITIONS[base_id(id)].duplicate(true)
		def["element"] = element
		def.name = "%s %s" % [ELEMENT_NAMES[element],def.name]
		def.item = "%s %s" % [ELEMENT_NAMES[element],def.item]
		def.description = "%s · %s" % [def.description,ELEMENT_NOTES[element]]
		variant_cache[id] = def
	return variant_cache[id]

## Whether `actor` may use `id` as an action: a caster species' own attack is
## the monster's, never a party member's.
static func usable_by(actor: Dictionary, id: String) -> bool:
	if not has(id): return false
	return bool(actor.get("enemy",false)) or not bool(definition(id).get("monster_only",false))

## The kill key of a monster: its species, and its element for a variant.
static func kind_key(enemy: Dictionary) -> String:
	var element: String = str(enemy.get("variant_element",""))
	return str(enemy.get("species_id","")) if element.is_empty() else "%s@%s" % [enemy.get("species_id",""),element]
```

Replace the body of `holds` (it now reads, after Step 3, `return str(actor.get("part_id","")) == id if actor.enemy else id in actor.equipped_abilities`) with:

```gdscript
static func holds(actor: Dictionary, id: String) -> bool:
	if actor.enemy: return str(actor.get("part_id","")) == id
	return id in actor.equipped_abilities and usable_by(actor,id)
```

- [ ] **Step 5: Let the rule catalog resolve variants**

In `expedition/ai/tactic_rules.gd` replace

```gdscript
static func skill(id: String) -> Dictionary:
	return catalog().get(id,{})
```

with

```gdscript
static func skill(id: String) -> Dictionary:
	var at := id.find("@")
	if at < 0: return catalog().get(id,{})
	var base: Dictionary = catalog().get(id.substr(0,at),{})
	if base.is_empty(): return {}
	var def: Dictionary = load("res://expedition/items/abilities.gd").definition(id)
	if def.is_empty(): return {}
	var row: Dictionary = base.duplicate(true)
	row.name = str(def.name); row.description = str(def.description)
	return row
```

- [ ] **Step 6: Keep caster attacks out of party menus and AI**

After Step 3 these loops read `Abilities.definition(...)` / `Abilities.has(...)`. Change them to skip `monster_only` parts for party members:

In `expedition/ai/stances.gd` `ranged_part`, replace `if def.is_empty(): continue` with:

```gdscript
		if def.is_empty() or bool(def.get("monster_only",false)): continue
```

In `expedition/ai/parts_candidates.gd` `part_options`, replace the line starting `if not Abilities.has(id) or Abilities.definition(id).effect in ["PUSH","GUARD"]: continue` with:

```gdscript
		if not Abilities.usable_by(actor,id) or Abilities.definition(id).effect in ["PUSH","GUARD"]: continue
```

In `expedition/ui/screens/floor_hud.gd`, replace

```gdscript
		if part_id.is_empty() or not Session.Abilities.has(part_id): continue
```

with

```gdscript
		if part_id.is_empty() or not Session.Abilities.usable_by(actor,part_id): continue
```

and replace

```gdscript
		if str(id).is_empty() or not Session.Abilities.has(id): continue
```

with

```gdscript
		if str(id).is_empty() or not Session.Abilities.usable_by(actor,str(id)): continue
```

- [ ] **Step 7: Run the new test and the suites that read the catalog**

Run:

```bash
cd /mnt/d/SS/new && for t in variants parts companion_tactics model_b_combat mobile_actions skill_rule_conditions skill_archetypes stances; do godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -1; done
```

Expected: every line ends in `0 failures` (or the suite's own passing summary). `variants` prints `Variants: 18 checks, 0 failures`.

- [ ] **Step 8: Commit**

```bash
cd /mnt/d/SS/new && git add tests/variants.gd && git commit -F - -- $(git diff --name-only -- expedition) tests/variants.gd <<'EOF'
Resolve element variant part ids through the parts catalog

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

Before committing, run `git diff --name-only -- expedition` and confirm every listed file was touched by Steps 3-6 of this task only. If another session has uncommitted edits in one of those files, stage only this task's hunks (`git add -p <file>`) and commit with `git commit` without the path list.

---

### Task 2: Every monster species has block, full resistances and its variants

**Files:**
- Modify: `data/content/floor_monsters.json`
- Modify: `expedition/level/continuous_floor.gd` (`mint_enemy`)
- Test: `tests/variants.gd`

**Interfaces:**
- Consumes: `Abilities.ELEMENT_NAMES` (Task 1).
- Produces: every species row has `"sh": int`, `"res": {"fire","ice","air","poison","will"}` and `"variants": Array[String]`; every minted enemy has `sh` and a `res` with all five keys.

- [ ] **Step 1: Write the failing test**

In `tests/variants.gd` add `const Encounters = preload("res://expedition/level/encounter_builder.gd")` under the other constants, add the caster list constant, call `data()` from `run()` after `resolution()`, and add the function:

```gdscript
const CASTERS := ["kobold_firecaller","frost_imp","storm_bat","goblin_hexer","gnoll_summoner"]
```

```gdscript
func data() -> void:
	for row in Encounters.table():
		var id: String = str(row.species_id)
		check(row.has("sh") and int(row.sh) >= 0,"%s has a block value" % id)
		for key in ["fire","ice","air","poison","will"]:
			check(row.get("res",{}).has(key),"%s lists %s resistance" % [id,key])
		var options: Array = row.get("variants",[])
		check(options.all(func(e): return Abilities.ELEMENT_NAMES.has(e)),"%s variants are known elements" % id)
		if id in CASTERS: check(options.is_empty(),"%s casts its own element and has no variants" % id)
		else: check(options.size() >= 2 and options.size() <= 3,"%s has two or three variants" % id)
	var s = Session.new_run(731)
	check(not s.enemies.is_empty(),"the first floor has monsters")
	for enemy in s.enemies:
		var row: Dictionary = Encounters.species(str(enemy.species_id))
		check(int(enemy.get("sh",-1)) == int(row.sh),"%s spawns with its block" % enemy.name)
		check(enemy.res.has("will") and enemy.res.has("poison"),"%s spawns with every resistance" % enemy.name)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/variants.gd`
Expected: FAIL with errors such as `dcss_rat has a block value` and `dcss_rat lists fire resistance`.

- [ ] **Step 3: Add block, resistances and variants to the data**

```bash
cd /mnt/d/SS/new && python3 - <<'EOF'
import json, pathlib
path = pathlib.Path("data/content/floor_monsters.json")
data = json.loads(path.read_text(encoding="utf-8"))
values = {
    # species: (block, resistances beyond zero, variants)
    "dcss_rat": (0, {}, ["poison", "ice"]),
    "dcss_frilled_lizard": (0, {"poison": 25}, ["poison", "fire"]),
    "kobold": (0, {}, ["fire", "air"]),
    "goblin": (0, {}, ["fire", "poison"]),
    "dcss_hobgoblin": (10, {}, ["ice", "will"]),
    "dcss_orc": (0, {}, ["fire", "ice"]),
    "dcss_gnoll": (0, {"will": 10}, ["poison", "air"]),
    "dcss_river_rat": (0, {"air": 25}, ["air", "ice"]),
}
for row in data["species"]:
    block, extra, variants = values[row["species_id"]]
    res = {key: 0 for key in ("fire", "ice", "air", "poison", "will")}
    res.update(row.get("res", {}))
    res.update(extra)
    row["sh"] = block
    row["res"] = res
    row["variants"] = variants
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
EOF
```

- [ ] **Step 4: Copy block onto spawned monsters**

In `expedition/level/continuous_floor.gd` `mint_enemy`, replace

```gdscript
	enemy.ac = int(species.get("ac",0)); enemy.ev = int(species.get("ev",3))
```

with

```gdscript
	enemy.ac = int(species.get("ac",0)); enemy.ev = int(species.get("ev",3)); enemy.sh = int(species.get("sh",0))
```

(`enemy.res = species.get("res",{}).duplicate(true)` on the next line already copies the full resistance table.)

- [ ] **Step 5: Run the tests**

Run: `godot --headless --path . --script res://tests/variants.gd && godot --headless --path . --script res://tests/encounter_builder.gd && godot --headless --path . --script res://tests/model_b_combat.gd`
Expected: all pass. The hobgoblin now blocks 10% of blows; if `model_b_combat` fails on a hobgoblin hit that is now blocked, confirm with `git stash` that it passed before Step 3, then set that test's hobgoblin `sh` to 0 at the start of the scenario (`foe.sh = 0`) so the scenario still measures what it was written for.

- [ ] **Step 6: Commit**

```bash
cd /mnt/d/SS/new && git commit -F - -- data/content/floor_monsters.json expedition/level/continuous_floor.gd tests/variants.gd <<'EOF'
Give every monster species block, five resistances and its variants

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

(Add `tests/model_b_combat.gd` to the path list only if Step 5 changed it.)

---

### Task 3: Five caster species with monster-only attacks

**Files:**
- Modify: `data/content/floor_monsters.json`
- Modify: `expedition/items/abilities.gd` (`DEFINITIONS`)
- Modify: `tests/encounter_builder.gd:12,79`
- Test: `tests/caster_species.gd` (create)

**Interfaces:**
- Consumes: `Abilities.usable_by`, `Abilities.definition` (Task 1); `Essences.has`, `Essences.row` (Plan 1).
- Produces: species rows `kobold_firecaller`, `frost_imp`, `storm_bat`, `goblin_hexer`, `gnoll_summoner`; catalog parts `FIRE_CALLER`, `FROST_IMP`, `STORM_BAT`, `GOBLIN_HEXER`, `GNOLL_SUMMONER`, each with `"monster_only": true` and `"element"`.

- [ ] **Step 1: Write the failing test**

Create `tests/caster_species.gd`:

```gdscript
extends SceneTree
## Caster species (spec §3.6), boss essences and deep-floor scaling (spec §5).
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Passives = preload("res://expedition/combat/passives.gd")
## species: [part, element, min depth, max depth]
const CASTERS := {
	"kobold_firecaller":["FIRE_CALLER","fire",1,4],
	"frost_imp":["FROST_IMP","ice",2,5],
	"storm_bat":["STORM_BAT","air",2,6],
	"goblin_hexer":["GOBLIN_HEXER","will",1,5],
	"gnoll_summoner":["GNOLL_SUMMONER","will",3,8]}
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	casters()
	print("Caster species: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func casters() -> void:
	for species_id in CASTERS:
		var entry: Array = CASTERS[species_id]
		var row: Dictionary = Encounters.species(species_id)
		check(not row.is_empty(),"%s is in the monster table" % species_id)
		if row.is_empty(): continue
		check(int(row.min_depth) == int(entry[2]) and int(row.max_depth) == int(entry[3]),"%s appears on floors %d-%d" % [species_id,entry[2],entry[3]])
		check("CASTER" in row.roles,"%s can take the caster role" % species_id)
		var part: String = Abilities.species_part(species_id)
		check(part == str(entry[0]),"%s signature part is %s" % [species_id,entry[0]])
		var def: Dictionary = Abilities.definition(part)
		check(bool(def.get("monster_only",false)),"%s is a monster-only attack" % part)
		check(str(def.get("element","")) == str(entry[1]),"%s carries %s" % [part,entry[1]])
		check(str(def.passive.get("kind","")) in Passives.KINDS,"%s has a known passive" % part)
		check(int(def.damage) <= 14 and int(def.enemy.prep) == 1,"%s stays within floor-1 numbers" % part)
		check(Essences.has(part) and str(Essences.row(part).get("species","")) == species_id,"%s is the essence of %s" % [part,species_id])
	var s = Session.new_run(731)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities[0] = "FIRE_CALLER"
	check(not Abilities.holds(hero,"FIRE_CALLER") and not Abilities.usable_by(hero,"FIRE_CALLER"),"a party member never fires a caster's monster attack")
	var foe: Dictionary = s.enemies[0]
	foe.part_id = "FIRE_CALLER"
	check(Abilities.holds(foe,"FIRE_CALLER") and Abilities.usable_by(foe,"FIRE_CALLER"),"the monster fires it")
	var met: Dictionary = {}
	for seed_value in range(1,11):
		for depth in range(1,5):
			var run = Session.new_run(seed_value)
			run.depth = depth; run.floor_state.build(run)
			for enemy in run.enemies:
				if CASTERS.has(str(enemy.species_id)): met[str(enemy.species_id)] = true
	check(met.size() >= 3,"caster species turn up on the first floors (%d of 5 met)" % met.size())
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/caster_species.gd`
Expected: FAIL with `kobold_firecaller is in the monster table` and the following checks.

- [ ] **Step 3: Add the caster species rows**

```bash
cd /mnt/d/SS/new && python3 - <<'EOF'
import json, pathlib
path = pathlib.Path("data/content/floor_monsters.json")
data = json.loads(path.read_text(encoding="utf-8"))
zero = {key: 0 for key in ("fire", "ice", "air", "poison", "will")}
def res(**extra):
    table = dict(zero); table.update(extra); return table
casters = [
    {"species_id": "kobold_firecaller", "display_name": "코볼트 화염술사", "max_health": 26, "min_depth": 1, "max_depth": 4,
     "rarity": 500, "curve": "FLAT", "threat": 2, "roles": ["RANGED", "CASTER"], "band": None,
     "speed": 100, "ac": 0, "ev": 5, "sh": 0, "res": res(fire=50, ice=-25), "variants": []},
    {"species_id": "frost_imp", "display_name": "서리 도깨비", "max_health": 30, "min_depth": 2, "max_depth": 5,
     "rarity": 400, "curve": "PEAK", "threat": 3, "roles": ["RANGED", "CASTER"], "band": None,
     "speed": 105, "ac": 1, "ev": 4, "sh": 0, "res": res(ice=50, fire=-25), "variants": []},
    {"species_id": "storm_bat", "display_name": "폭풍 박쥐", "max_health": 24, "min_depth": 2, "max_depth": 6,
     "rarity": 400, "curve": "PEAK", "threat": 3, "roles": ["RANGED", "CASTER"], "band": None, "beast": True,
     "speed": 120, "ac": 0, "ev": 7, "sh": 0, "res": res(air=50), "variants": []},
    {"species_id": "goblin_hexer", "display_name": "고블린 주술사", "max_health": 30, "min_depth": 1, "max_depth": 5,
     "rarity": 500, "curve": "FLAT", "threat": 3, "roles": ["RANGED", "CASTER"], "band": None,
     "speed": 100, "ac": 1, "ev": 4, "sh": 0, "res": res(will=50), "variants": []},
    {"species_id": "gnoll_summoner", "display_name": "놀 소환사", "max_health": 90, "min_depth": 3, "max_depth": 8,
     "rarity": 200, "curve": "RISE", "threat": 5, "roles": ["RANGED", "CASTER"], "band": None,
     "speed": 105, "ac": 2, "ev": 3, "sh": 0, "res": res(will=25), "variants": []},
]
known = {row["species_id"] for row in data["species"]}
data["species"] += [row for row in casters if row["species_id"] not in known]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
EOF
```

- [ ] **Step 4: Add the caster attacks to the parts catalog**

In `expedition/items/abilities.gd`, the last entry of `DEFINITIONS` is `"RIVER_RAT_SPLASH":{...,"tile_wet":70}}`. Replace its closing `"tile_wet":70}}` with `"tile_wet":70},` and append, before the dictionary's closing `}`:

```gdscript
	"FIRE_CALLER":{"name":"화염 화살","item":"화염술사의 불씨","description":"궁지: 자신 체력 절반 미만이면 피해 +2 · 화염 화살: 사거리 4 피해 9 · 맞은 칸에 불 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":9,"cooldown":2,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"화염","shape":"SQUARE","self_hit":false,"icon":4,"species":"kobold_firecaller","passive":{"kind":"BLOODLUST","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"fire","monster_only":true},
	"FROST_IMP":{"name":"서리 숨결","item":"서리 도깨비의 뿔","description":"서리 가죽: 받는 피해 -1 · 서리 숨결: 사거리 3 · 3×3 피해 6 · 둔화 · 재사용 3턴","target":"ENEMY","range":3,"radius":1,"damage":6,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"서리","shape":"SQUARE","self_hit":false,"icon":4,"species":"frost_imp","passive":{"kind":"THICK_HIDE","value":1},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"ice","monster_only":true},
	"STORM_BAT":{"name":"번개 화살","item":"폭풍 박쥐의 날개막","description":"물갈퀴: 젖은 칸에서 피해 +2 · 번개 화살: 사거리 4 피해 8 · 젖은 대상 피해 +4 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":8,"cooldown":2,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"번개","shape":"SQUARE","self_hit":false,"icon":4,"species":"storm_bat","passive":{"kind":"AMPHIBIOUS","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"air","monster_only":true},
	"GOBLIN_HEXER":{"name":"혼란의 저주","item":"고블린 주술 부적","description":"비열: 체력 절반 미만 대상에 피해 +2 · 혼란의 저주: 사거리 4 피해 4 · 혼란 · 재사용 3턴","target":"ENEMY","range":4,"radius":0,"damage":4,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"저주","shape":"SQUARE","self_hit":false,"icon":4,"species":"goblin_hexer","passive":{"kind":"DIRTY","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"will","monster_only":true},
	"GNOLL_SUMMONER":{"name":"영혼 채찍","item":"놀 소환사의 사슬","description":"재생: 라운드마다 체력 +1 · 영혼 채찍: 사거리 3 피해 10 · 혼란 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":10,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"채찍","shape":"SQUARE","self_hit":false,"icon":4,"species":"gnoll_summoner","passive":{"kind":"REGEN","value":1},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"will","monster_only":true}}
```

The element effects on hit arrive in Task 4; until then these attacks deal plain damage.

- [ ] **Step 5: Update the species count in the builder test**

In `tests/encounter_builder.gd` replace both occurrences:

```gdscript
	check(Builder.table().size() == 8,"eight species loaded")
```
→
```gdscript
	check(Builder.table().size() == 13,"thirteen species loaded")
```

and

```gdscript
	check(Builder.table().size() == 8,"the species table is restored")
```
→
```gdscript
	check(Builder.table().size() == 13,"the species table is restored")
```

- [ ] **Step 6: Run the tests**

Run:

```bash
cd /mnt/d/SS/new && for t in caster_species encounter_builder parts floor_generator floor_descent; do godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -1; done
```

Expected: all pass. `parts` iterates the monster table and now also checks the five caster parts (passive kinds, prep 1, damage ≤ 14).

- [ ] **Step 7: Commit**

```bash
cd /mnt/d/SS/new && git add tests/caster_species.gd && git commit -F - -- data/content/floor_monsters.json expedition/items/abilities.gd tests/encounter_builder.gd tests/caster_species.gd <<'EOF'
Add five caster species whose essences carry their school

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Element parts burn, chill, shock, poison and confuse; weakness is real

**Files:**
- Modify: `expedition/items/abilities.gd` (`resolve`)
- Modify: `expedition/combat/combat_rules.gd` (`damage`)
- Modify: `expedition/progression/stat_sheet.gd` (only if it clamps resistances at 0)
- Test: `tests/variants.gd`

**Interfaces:**
- Consumes: `Abilities.definition`, `ELEMENT_FORMS` (Task 1).
- Produces: `Abilities.strike_victim(s, actor: Dictionary, victim: Dictionary, amount: int, form: String, def: Dictionary) -> void`, `Abilities.element_mark(s, victim: Dictionary, element: String) -> void`, `const SHOCK_BONUS := 4`, `const FIRE_TILE_ADD := 35`, `const ELEMENT_TICKS := 200`. Negative resistance raises damage.

- [ ] **Step 1: Write the failing test**

In `tests/variants.gd` add `const CombatRules = preload("res://expedition/combat/combat_rules.gd")`, call `effects()` and `weakness()` from `run()` after `data()`, and add:

```gdscript
func effects() -> void:
	var s = Session.new_run(731)
	var hero: Dictionary = s.party[0]
	hero.stress = 0
	var foe: Dictionary = s.enemies[0]
	foe.pos = hero.pos+Vector2i(3,0)
	var cell: Dictionary = s.tile(hero.pos)
	cell.wet = 0; cell.fire = 0
	var before: int = hero.hp
	Abilities.resolve(s,foe,"KOBOLD_SLING@fire",hero.pos)
	check(hero.hp < before,"a fire part hurts")
	check(int(s.tile(hero.pos).fire) > 0,"a fire part sets its victim's cell alight")
	hero.hp = hero.max_hp; s.tile(hero.pos).fire = 0
	Abilities.resolve(s,foe,"KOBOLD_SLING@ice",hero.pos)
	check(hero.statuses.has("slow"),"an ice part slows")
	hero.hp = hero.max_hp
	Abilities.resolve(s,foe,"KOBOLD_SLING@poison",hero.pos)
	check(hero.statuses.has("poison"),"a poison part poisons")
	hero.hp = hero.max_hp
	Abilities.resolve(s,foe,"KOBOLD_SLING@will",hero.pos)
	check(hero.statuses.has("confuse"),"a will part confuses")
	hero.hp = hero.max_hp; hero.stress = 0
	Abilities.resolve(s,foe,"KOBOLD_SLING@air",hero.pos)
	var dry_loss: int = hero.max_hp-hero.hp
	hero.hp = hero.max_hp; hero.stress = 0; s.tile(hero.pos).wet = 70
	Abilities.resolve(s,foe,"KOBOLD_SLING@air",hero.pos)
	check(hero.max_hp-hero.hp > dry_loss,"an air part shocks a wet victim harder")
	hero.hp = hero.max_hp; hero.statuses.clear(); s.tile(hero.pos).wet = 0
	Abilities.resolve(s,foe,"KOBOLD_SLING",hero.pos)
	check(hero.statuses.is_empty() and int(s.tile(hero.pos).fire) == 0,"a base part leaves no element mark")

func weakness() -> void:
	var s = Session.new_run(731)
	var foe: Dictionary = s.enemies[0]
	foe.part_id = ""; foe.statuses.clear()
	foe.res = {"fire":-25}; foe.hp = 100; foe.max_hp = 100
	CombatRules.damage(s,{},foe,20,"fire")
	check(foe.hp == 75,"a weakness of 25 turns 20 fire into 25")
	foe.res = {"fire":50}; foe.hp = 100
	CombatRules.damage(s,{},foe,20,"fire")
	check(foe.hp == 90,"resistance 50 halves fire")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/variants.gd`
Expected: FAIL with `a fire part sets its victim's cell alight`, `an ice part slows`, … and `a weakness of 25 turns 20 fire into 25`.

- [ ] **Step 3: Add the element strike to `abilities.gd`**

Append at the end of `expedition/items/abilities.gd`:

```gdscript

const SHOCK_BONUS := 4
const FIRE_TILE_ADD := 35
const ELEMENT_TICKS := 200

## One victim of a part. A part with an element deals that element (so the
## victim's resistance and weakness apply) and leaves the element's mark.
static func strike_victim(s, actor: Dictionary, victim: Dictionary, amount: int, form: String, def: Dictionary) -> void:
	var element: String = str(def.get("element",""))
	if element.is_empty():
		s.damage(victim,amount,actor.id,form)
		return
	if element == "air" and int(s.tile(victim.pos).wet) > 0: amount += SHOCK_BONUS
	s.damage(victim,amount,actor.id,ELEMENT_FORMS[element])
	element_mark(s,victim,element)

## What an element leaves behind on whoever it hit.
static func element_mark(s, victim: Dictionary, element: String) -> void:
	match element:
		"fire":
			var tile: Dictionary = s.tile(victim.pos)
			if int(tile.wet) <= 0 and str(tile.terrain) != "water": tile.fire = mini(100,int(tile.fire)+FIRE_TILE_ADD)
		"ice":
			if victim.hp > 0: s.Statuses.apply(s,victim,"slow",ELEMENT_TICKS)
		"poison":
			if victim.hp > 0 and int(victim.get("res",{}).get("poison",0)) < 100: victim.statuses["poison"] = s.time+ELEMENT_TICKS+100
		"will":
			if victim.hp > 0: s.Statuses.apply(s,victim,"confuse",ELEMENT_TICKS)
```

- [ ] **Step 4: Route `resolve`'s hits through it**

In `resolve` (`expedition/items/abilities.gd`), the `"LUNGE"` branch ends with

```gdscript
				s.damage(victim,power(s,actor,def),actor.id,"SLASH")
```

Replace that line with:

```gdscript
				strike_victim(s,actor,victim,power(s,actor,def),"SLASH",def)
```

In the `"DAMAGE"` branch replace

```gdscript
				s.damage(other,amount,actor.id,"IMPACT"); hit += 1
```

with

```gdscript
				strike_victim(s,actor,other,amount,"IMPACT",def); hit += 1
```

(If Plan 1 renamed `power(s,actor,def)` in these lines, keep whatever expression computes the amount there and only replace the `s.damage(...)` call around it.) The bomb's self-hit line `if def.self_hit and actor.pos in affected: s.damage(actor,amount,actor.id,"IMPACT"); hit += 1` stays as it is.

- [ ] **Step 5: Let a negative resistance raise damage**

In `expedition/combat/combat_rules.gd` `damage`, the resistance line reads `var resistance: int = maxi(0,<resistance lookup>-penetration)`. Replace that single line with:

```gdscript
		var listed: int = int(Stats.stats(s, target).res.get(element.to_lower(), 0))
		var resistance: int = listed if listed <= 0 else maxi(0,listed-penetration)
```

If Plan 1 changed the lookup (for example to read `StatSheet`), keep its lookup expression as the right-hand side of `listed` and apply only the sign rule shown.

Then open `expedition/progression/stat_sheet.gd` and search for the resistance clamp (`grep -n "RES_CAP" expedition/progression/stat_sheet.gd`). If it clamps with a lower bound of `0` (for example `clampi(value,0,RES_CAP)`), change the lower bound to `-100` so a monster's weakness reaches the damage rule: `clampi(value,-100,RES_CAP)`.

- [ ] **Step 6: Run the tests**

Run:

```bash
cd /mnt/d/SS/new && for t in variants caster_species parts model_b_combat model_b_spells enemy_turns; do godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -1; done
```

Expected: all pass. `variants` reports 0 failures.

- [ ] **Step 7: Commit**

```bash
cd /mnt/d/SS/new && git commit -F - -- expedition/items/abilities.gd expedition/combat/combat_rules.gd tests/variants.gd <<'EOF'
Let element parts leave their mark and weaknesses raise damage

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

Add `expedition/progression/stat_sheet.gd` to the path list if Step 5 changed it.

---

### Task 5: Variant monsters and a main element per floor

**Files:**
- Create: `expedition/level/variants.gd`
- Modify: `expedition/level/continuous_floor.gd` (`var element`, `apply`)
- Modify: `expedition/items/gear.gd` (`roll_part`)
- Test: `tests/variants.gd`

**Interfaces:**
- Consumes: `Abilities.ELEMENT_NAMES`, `Abilities.OPPOSITE`, `Abilities.kind_key` (Task 1); `Essences.drop_chance` (Plan 1).
- Produces:
  - `expedition/level/variants.gd`: `const VARIANT_PERCENT := 40`, `const OWN_RESIST := 50`, `const OPPOSITE_WEAKNESS := 25`, `allowed(species_id: String) -> Array`, `floor_element(seed_value: int, depth: int, enemies: Array) -> String`, `apply(enemy: Dictionary, element: String) -> void`, `assign(s, enemies: Array) -> String`.
  - Enemy field `variant_element: String` (absent on base monsters); floor field `s.floor_state.element: String`.

- [ ] **Step 1: Write the failing test**

In `tests/variants.gd` add `const Variants = preload("res://expedition/level/variants.gd")`, call `floors()` from `run()` after `weakness()`, and add:

```gdscript
func floors() -> void:
	var start = Session.new_run(731)
	check(str(start.floor_state.element) == "","the first floor has no main element")
	check(start.enemies.all(func(e): return str(e.get("variant_element","")).is_empty()),"the first floor has base species only")
	var total := 0
	for seed_value in range(1,9):
		for depth in range(2,8):
			var s = Session.new_run(seed_value)
			s.depth = depth; s.floor_state.build(s)
			var element: String = str(s.floor_state.element)
			var variants: Array = s.enemies.filter(func(e): return not str(e.get("variant_element","")).is_empty())
			total += variants.size()
			if variants.is_empty(): continue
			check(not element.is_empty(),"a floor with variants has a main element (seed %d, floor %d)" % [seed_value,depth])
			check(s.log_lines.any(func(line): return line == "이 층의 기운 · "+str(Abilities.ELEMENT_NAMES.get(element,""))),"the floor announces its element (seed %d, floor %d)" % [seed_value,depth])
			var main: int = variants.filter(func(e): return e.variant_element == element).size()
			check(main*2 >= variants.size(),"at least half the variants wear the floor's element (seed %d, floor %d)" % [seed_value,depth])
			for e in variants:
				var own: String = e.variant_element
				check(own in Variants.allowed(str(e.species_id)),"%s wears an element that suits it" % e.name)
				check(int(e.res.get(own,0)) >= Variants.OWN_RESIST,"%s resists its own element" % e.name)
				check(str(e.part_id).ends_with("@"+own),"%s carries the variant part" % e.name)
				check(str(e.name).begins_with(str(Abilities.ELEMENT_NAMES[own])),"%s is named for its element" % e.name)
				check(Abilities.kind_key(e) == "%s@%s" % [e.species_id,own],"%s is keyed as a variant" % e.name)
				if Abilities.OPPOSITE.has(own):
					check(int(e.res.get(Abilities.OPPOSITE[own],0)) < 0,"%s is weak to the opposite element" % e.name)
	check(total >= 20,"variants appear below the first floor (%d met)" % total)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/variants.gd`
Expected: FAIL with a parse error for the missing `res://expedition/level/variants.gd`.

- [ ] **Step 3: Create `expedition/level/variants.gd`**

```gdscript
extends RefCounted
## Element variants of floor monsters (spec §3.7): the element a floor leans
## to, which of its monsters wear an element, and what wearing one changes.
## Deterministic: every roll is a Hexaco sample of the run seed.
const Abilities = preload("res://expedition/items/abilities.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
## Chance that a monster whose species has variants is drawn as one.
const VARIANT_PERCENT := 40
const OWN_RESIST := 50
const OPPOSITE_WEAKNESS := 25

## The elements that suit a species, from `floor_monsters.json` `variants`.
static func allowed(species_id: String) -> Array:
	return Encounters.species(species_id).get("variants",[])

## The floor's main element: one that suits at least one monster on it. The
## first floor has none.
static func floor_element(seed_value: int, depth: int, enemies: Array) -> String:
	if depth <= 1: return ""
	var pool: Array = []
	for enemy in enemies:
		if enemy.get("boss",false): continue
		for element in allowed(str(enemy.get("species_id",""))):
			if element not in pool: pool.append(element)
	if pool.is_empty(): return ""
	pool.sort()
	return str(pool[Hexaco.sample(seed_value,depth,"floor_element",pool.size())])

## Turns a minted monster into its `element` variant.
static func apply(enemy: Dictionary, element: String) -> void:
	enemy["variant_element"] = element
	enemy.name = "%s %s" % [Abilities.ELEMENT_NAMES[element],enemy.name]
	var res: Dictionary = enemy.get("res",{}).duplicate(true)
	res[element] = maxi(int(res.get(element,0)),OWN_RESIST)
	if Abilities.OPPOSITE.has(element):
		var other: String = Abilities.OPPOSITE[element]
		res[other] = int(res.get(other,0))-OPPOSITE_WEAKNESS
	enemy.res = res
	if not str(enemy.get("part_id","")).is_empty(): enemy.part_id = "%s@%s" % [enemy.part_id,element]

## Picks the floor's element and makes variants of some of `enemies`, in id
## order. A monster whose species suits the floor's element takes it; one that
## does not may take another of its elements only while those stay fewer than
## the floor's own, so at least half the variants wear the floor's element.
## Returns the floor's element ("" on the first floor).
static func assign(s, enemies: Array) -> String:
	var element := floor_element(int(s.seed_value),int(s.depth),enemies)
	if element.is_empty(): return ""
	var ordered: Array = enemies.duplicate()
	ordered.sort_custom(func(a,b): return int(a.id) < int(b.id))
	var on_floor := 0
	var off_floor := 0
	for enemy in ordered:
		if enemy.get("boss",false): continue
		var options: Array = allowed(str(enemy.get("species_id","")))
		if options.is_empty(): continue
		var key: int = int(s.depth)*1000+int(enemy.id)
		if Hexaco.sample(int(s.seed_value),key,"variant",100) >= VARIANT_PERCENT: continue
		if element in options:
			apply(enemy,element); on_floor += 1
		elif off_floor < on_floor:
			apply(enemy,str(options[Hexaco.sample(int(s.seed_value),key,"variant_element",options.size())]))
			off_floor += 1
	return element
```

- [ ] **Step 4: Call it from the floor**

In `expedition/level/continuous_floor.gd`:

Add under the other `preload` constants:

```gdscript
const Variants = preload("res://expedition/level/variants.gd")
```

Add under `var seen_enemies: Dictionary = {}`:

```gdscript
## The floor's main element (spec §3.7); "" on the first floor.
var element := ""
```

In `apply`, replace

```gdscript
	for p in layout.features: state.features[p] = layout.features[p].duplicate(true)
```

with

```gdscript
	state.element = Variants.assign(s,s.enemies)
	if not state.element.is_empty(): s.message("이 층의 기운 · "+str(Abilities.ELEMENT_NAMES[state.element]))
	for p in layout.features: state.features[p] = layout.features[p].duplicate(true)
```

- [ ] **Step 5: Key first-kill drops by variant**

A fire goblin is its own kind of monster: its first kill is a guaranteed drop even after base goblins were killed. Plan 1's `roll_part` in `expedition/items/gear.gd` keys both the chance and the "seen" mark by one variable:

```gdscript
	var species: String = str(enemy.get("species_id",""))
	var chance: int = Essences.drop_chance(s,species)
	s.essence_seen[species] = true
```

Change only the first of those three lines, so the chance and the mark share the variant key:

```gdscript
	var species: String = Abilities.kind_key(enemy)
```

- [ ] **Step 6: Run the tests**

Run:

```bash
cd /mnt/d/SS/new && for t in variants caster_species floor_descent floor_generator continuous_floor boss_floor npc_roster; do godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -1; done
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /mnt/d/SS/new && git add expedition/level/variants.gd && git commit -F - -- expedition/level/variants.gd expedition/level/continuous_floor.gd expedition/items/gear.gd tests/variants.gd <<'EOF'
Spawn element variants under a main element per floor

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Bosses carry their own essence

**Files:**
- Modify: `expedition/actors/boss_ai.gd` (`spawn`)
- Modify: `data/content/essences.json`
- Test: `tests/caster_species.gd`

**Interfaces:**
- Consumes: `Essences.has`, `Essences.row` (Plan 1).
- Produces: `BossAI.BOSS_PARTS := ["SHOCKWAVE","BOMB","IRON_HIDE"]`, `BossAI.BOSS_SPECIES := ["boss_mire","boss_bomber","boss_giant"]` (both indexed by `pattern`); essence rows `SHOCKWAVE`, `BOMB`, `IRON_HIDE`.

- [ ] **Step 1: Write the failing test**

In `tests/caster_species.gd` add `const BossAI = preload("res://expedition/actors/boss_ai.gd")`, call `bosses()` from `run()` after `casters()`, and add:

```gdscript
func bosses() -> void:
	check(BossAI.BOSS_PARTS == ["SHOCKWAVE","BOMB","IRON_HIDE"],"one essence per boss pattern")
	check(BossAI.BOSS_SPECIES == ["boss_mire","boss_bomber","boss_giant"],"one species per boss pattern")
	for i in range(3):
		var part: String = BossAI.BOSS_PARTS[i]
		check(Essences.has(part),"%s is an essence" % part)
		check(str(Essences.row(part).get("species","")) == BossAI.BOSS_SPECIES[i],"%s belongs to %s" % [part,BossAI.BOSS_SPECIES[i]])
		check(not Essences.row(part).get("stats",{}).is_empty(),"%s gives stats" % part)
	var s = Session.new_run(731)
	s.depth = 3; s.floor_state.build(s)
	var bosses: Array = s.enemies.filter(func(e): return e.get("boss",false))
	check(bosses.size() == 1,"the third floor has its boss")
	if bosses.is_empty(): return
	var boss: Dictionary = bosses[0]
	check(boss.part_id == "SHOCKWAVE" and boss.species_id == "boss_mire","the mire boss carries the mire essence")
	var count: int = int(s.parts_bag.get("SHOCKWAVE",0))
	boss.hp = 1
	s.damage(boss,5,s.party[0].id,"physical")
	check(boss.hp <= 0 and int(s.parts_bag.get("SHOCKWAVE",0)) == count+1,"a boss always leaves its essence")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/caster_species.gd`
Expected: FAIL with `Invalid access to property or key 'BOSS_PARTS'`.

- [ ] **Step 3: Give each boss pattern its essence**

In `expedition/actors/boss_ai.gd`, add after the `HINTS` constant:

```gdscript
## Each pattern's own essence and species (spec §3.6): the boss drops its
## essence every time, and passives only ever read a species' own part.
const BOSS_PARTS := ["SHOCKWAVE","BOMB","IRON_HIDE"]
const BOSS_SPECIES := ["boss_mire","boss_bomber","boss_giant"]
```

In `spawn`, replace

```gdscript
	var drops: Array = Abilities.droppable()
	boss.part_id = drops[pattern % drops.size()] if not drops.is_empty() else ""
```

with

```gdscript
	boss.part_id = BOSS_PARTS[pattern]
	boss.species_id = BOSS_SPECIES[pattern]
```

The session's kill path already grants a dead boss's `part_id` to the party unconditionally (`grant_part(str(target.part_id))`).

- [ ] **Step 4: Add the boss essence rows**

```bash
cd /mnt/d/SS/new && python3 - <<'EOF'
import json, pathlib
path = pathlib.Path("data/content/essences.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["rows"]["SHOCKWAVE"] = {"name": "수렁의 핵", "stats": {"con": 3, "res_poison": 20}, "role": "BERSERK", "element": "poison", "school": "", "species": "boss_mire"}
data["rows"]["BOMB"] = {"name": "암살자의 화약낭", "stats": {"dex": 3, "ev": 2}, "role": "AMBUSH", "element": "fire", "school": "", "species": "boss_bomber"}
data["rows"]["IRON_HIDE"] = {"name": "거인의 철갑핵", "stats": {"con": 2, "ac": 3}, "role": "GUARD", "element": "air", "school": "", "species": "boss_giant"}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
EOF
```

- [ ] **Step 5: Run the tests**

Run:

```bash
cd /mnt/d/SS/new && for t in caster_species boss_floor parts playthrough; do godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -1; done
```

Expected: all pass. If `boss_floor` or `parts` asserted the old borrowed part (`Abilities.droppable()[pattern]`), change that expectation to `BossAI.BOSS_PARTS[pattern]` and note it in the commit.

- [ ] **Step 6: Commit**

```bash
cd /mnt/d/SS/new && git commit -F - -- expedition/actors/boss_ai.gd data/content/essences.json tests/caster_species.gd <<'EOF'
Give each boss its own essence and a guaranteed drop

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

Add any test file Step 5 changed to the path list.

---

### Task 7: Deep floors scale monster health and attack

**Files:**
- Modify: `expedition/level/continuous_floor.gd` (`theme_for`, `mint_enemy`, new `last_catalog_depth`, `deep_scale`)
- Modify: `expedition/items/abilities.gd` (`power`, new `scaled`)
- Modify: `expedition/actors/monster_ai.gd` (`plan`, `resolve_spell`, `strike`)
- Modify: `expedition/actors/boss_ai.gd` (`spawn`, boss intents)
- Test: `tests/caster_species.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Floor.last_catalog_depth() -> int`, `Floor.deep_scale(depth: int) -> Dictionary` (`{"hp": percent, "attack": percent}`), `theme.deep`, enemy field `attack_percent: int`, `Abilities.scaled(actor: Dictionary, amount: int) -> int`.

- [ ] **Step 1: Write the failing test**

In `tests/caster_species.gd` add `const Floor = preload("res://expedition/level/continuous_floor.gd")`, call `deep()` from `run()` after `bosses()`, and add:

```gdscript
func deep() -> void:
	check(Floor.last_catalog_depth() == 8,"the monster catalog ends on floor eight")
	check(Floor.deep_scale(8) == {"hp":100,"attack":100},"no scaling inside the catalog")
	check(Floor.deep_scale(9) == {"hp":112,"attack":108},"one floor past: +12% health, +8% attack")
	check(Floor.deep_scale(11) == {"hp":136,"attack":124},"three floors past: +36% health, +24% attack")
	check(Floor.theme_for(10).deep == Floor.deep_scale(10),"the theme carries the scaling")
	var s = Session.new_run(731)
	var member := {"species_id":"goblin","display_name":"고블린","max_health":28,"pos":Vector2i(1,1),"role":"MELEE"}
	s.depth = 8
	var shallow: Dictionary = Floor.mint_enemy(s,member,"T8","early",false)
	s.depth = 9
	var deeper: Dictionary = Floor.mint_enemy(s,member,"T9","early",false)
	check(int(shallow.get("attack_percent",100)) == 100 and int(deeper.attack_percent) == 108,"monsters past the catalog hit harder")
	check(int(deeper.max_hp) == int(shallow.max_hp)*112/100 and int(deeper.hp) == int(deeper.max_hp),"monsters past the catalog have more health")
	check(Abilities.scaled(deeper,50) == 54 and Abilities.scaled(shallow,50) == 50,"attack scaling applies to any amount")
	check(Abilities.power(s,deeper,Abilities.definition("GOBLIN_SHIV")) == int(Abilities.DEFINITIONS.GOBLIN_SHIV.damage)*108/100,"a deep monster's part hits harder")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/caster_species.gd`
Expected: FAIL with `Invalid call. Nonexistent function 'last_catalog_depth'`.

- [ ] **Step 3: Add the scaling to the floor**

In `expedition/level/continuous_floor.gd`, add after `SOLO_HP_MAX`:

```gdscript
## Past the deepest floor the monster catalog covers, every floor adds this
## much monster health and attack, in percent (spec §5).
const DEEP_HP_STEP := 12
const DEEP_ATTACK_STEP := 8
```

Add after `theme_for`:

```gdscript
## The deepest floor any catalogued species still appears on.
static func last_catalog_depth() -> int:
	var deepest := 1
	for row in Generator.Encounters.table(): deepest = maxi(deepest,int(row.max_depth))
	return deepest

static func deep_scale(depth: int) -> Dictionary:
	var past: int = maxi(0,depth-last_catalog_depth())
	return {"hp":100+DEEP_HP_STEP*past,"attack":100+DEEP_ATTACK_STEP*past}
```

In `theme_for`, replace `	theme.depth = depth` with:

```gdscript
	theme.depth = depth
	theme.deep = deep_scale(depth)
```

In `mint_enemy`, replace

```gdscript
	if s.party.size() == 1: enemy.hp = clampi(enemy.hp*SOLO_HP_PERCENT/100,SOLO_HP_MIN,SOLO_HP_MAX)
	enemy.max_hp = enemy.hp
```

with

```gdscript
	if s.party.size() == 1: enemy.hp = clampi(enemy.hp*SOLO_HP_PERCENT/100,SOLO_HP_MIN,SOLO_HP_MAX)
	var deep: Dictionary = deep_scale(int(s.depth))
	enemy.hp = enemy.hp*int(deep.hp)/100
	enemy.max_hp = enemy.hp
	enemy.attack_percent = int(deep.attack)
```

- [ ] **Step 4: Apply the attack percent to every monster hit**

In `expedition/items/abilities.gd`, add next to `strike_victim`:

```gdscript
## A monster's damage after deep-floor scaling (`attack_percent`, default 100).
static func scaled(actor: Dictionary, amount: int) -> int:
	return amount*int(actor.get("attack_percent",100))/100
```

In `power`, replace the enemy line `if actor.enemy: return int(def.damage)` with:

```gdscript
	if actor.enemy: return scaled(actor,int(def.damage))
```

In `expedition/actors/monster_ai.gd`:

- In `plan`, replace `var amount: int = int(Abilities.definition(id).damage) if Abilities.has(id) else SPELL_DAMAGE` with
  ```gdscript
		var amount: int = Abilities.scaled(enemy,int(Abilities.definition(id).damage) if Abilities.has(id) else SPELL_DAMAGE)
  ```
- In `resolve_spell`, replace `s.damage(victim,SPELL_DAMAGE,enemy.id,"ELECTRIC")` with `s.damage(victim,Abilities.scaled(enemy,SPELL_DAMAGE),enemy.id,"ELECTRIC")`.
- In `strike`, add as the first line of the body:
  ```gdscript
	amount = Abilities.scaled(enemy,amount)
  ```

- [ ] **Step 5: Scale bosses past the catalog**

In `expedition/actors/boss_ai.gd` `spawn`, replace

```gdscript
	boss.hp = 64+8*(int(depth/3)-1); boss.max_hp = boss.hp
```

with

```gdscript
	var deep: Dictionary = s.Floor.deep_scale(depth)
	boss.hp = (64+8*(int(depth/3)-1))*int(deep.hp)/100; boss.max_hp = boss.hp
	boss.attack_percent = int(deep.attack)
```

Then scale the boss's announced hits:

```bash
cd /mnt/d/SS/new && sed -i 's/"damage":16,/"damage":Abilities.scaled(boss,16),/g' expedition/actors/boss_ai.gd && grep -n '"damage":' expedition/actors/boss_ai.gd
```

Expected: every `"damage":` in `boss_ai.gd` now reads `Abilities.scaled(boss,…)`. If a line shows another literal (not 16), wrap it the same way by hand.

- [ ] **Step 6: Run the tests**

Run:

```bash
cd /mnt/d/SS/new && for t in caster_species variants boss_floor floor_descent enemy_turns model_b_combat solo_balance; do godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -1; done
```

Expected: all pass. Floors 1-8 are unchanged by construction (scale 100%).

- [ ] **Step 7: Commit**

```bash
cd /mnt/d/SS/new && git commit -F - -- expedition/level/continuous_floor.gd expedition/items/abilities.gd expedition/actors/monster_ai.gd expedition/actors/boss_ai.gd tests/caster_species.gd <<'EOF'
Scale monster health and attack on floors past the catalog

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: Caster sprites and element-tinted variants

**Files:**
- Modify: `tools/art/build_monsters.py` (new `bat`, marks, `MONSTERS`)
- Modify: `tools/art/build_game_sprites.py` (`MONSTERS`)
- Modify: `expedition/art/mobile_art.gd` (`MONSTER_SPRITES`, `MONSTER_IDS`, element tint and mark, `paint_monster`)
- Modify: `expedition/ui/battle_actor_visual.gd`
- Create (generated): `assets/monsters-v1/svg|png/<id>_<facing>.*`, `assets/sprites-v1/monsters/<id>.png` and `.svg` for the five casters, `docs/art/monsters-v1/monster-sheet.png`
- Test: `tests/mobile_hud.gd`

**Interfaces:**
- Consumes: enemy field `variant_element` (Task 5).
- Produces: `Art.ELEMENT_TINTS`, `Art.ELEMENT_MARKS` (keys: the five elements), `Art.paint_monster(canvas, species_id: String, rect: Rect2, tint: Color = Color.WHITE, element: String = "")`.

- [ ] **Step 1: Write the failing test**

In `tests/mobile_hud.gd`, directly after the existing check `"unknown species fall back to the kobold"`, add:

```gdscript
	for caster in ["kobold_firecaller","frost_imp","storm_bat","goblin_hexer","gnoll_summoner"]:
		check(Art.MONSTER_IDS.has(caster) and Art.enemy_sprite(caster).atlas.resource_path.ends_with("monsters/"+caster+".png"),"%s has its own sprite" % caster)
	check(["fire","ice","air","poison","will"].all(func(e): return Art.ELEMENT_TINTS.has(e) and Art.ELEMENT_MARKS.has(e)),"every element has a tint and a mark colour")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/mobile_hud.gd`
Expected: FAIL with `kobold_firecaller has its own sprite`.

- [ ] **Step 3: Draw the five casters**

In `tools/art/build_monsters.py`, add after the `giant` function:

```python
def bat(uid, facing, fur, wing, glow="#ffe14a"):
    """폭풍 박쥐: a round body between two ribbed wings, ears up, spark eyes."""
    turn = {"east": 1, "west": -1}.get(facing, 0)
    cx, cy = 32 + 2 * turn, 38
    parts = [shadow(14, 59)]
    spans = {"south": (-1, 1), "north": (-1, 1), "east": (-1,), "west": (1,)}[facing]
    for i, side in enumerate(spans):
        tip = cx + side * 26
        wing_path = (f"M{cx + side * 6} {cy - 6} Q{cx + side * 18} {cy - 20} {tip} {cy - 10} "
                     f"L{cx + side * 20} {cy + 2} L{cx + side * 14} {cy - 2} L{cx + side * 8} {cy + 6} Z")
        parts.append(shaded(f"{uid}w{i}", wing_path, *wing, 2.0, 1.6))
    parts.append(shaded(uid + "b", ellipse(cx, cy, 11, 12), *fur, 2.6, 2.2))
    for i, side in enumerate((-1, 1)):
        ear = poly([(cx + side * 3, cy - 10), (cx + side * 8, cy - 21), (cx + side * 9, cy - 8)])
        parts.append(shaded(f"{uid}e{i}", ear, *fur, 1.2, 1.0))
    parts.append(pills(cx, cy - 2, facing, glow, gap=3.4, h=5.2))
    return wrap("".join(parts))


# Chest marks for the caster humanoids, drawn over the torso.
FLAME = f'<path d="M32 52 Q27.5 48 30.5 42.5 Q32 46 33.5 43.5 Q37 48.5 32 52 Z" fill="#ffb13a" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>'
RUNE = f'<circle cx="32" cy="48" r="3.4" fill="none" stroke="#e7d36a" stroke-width="1.8"/>'
CHAIN = '<path d="M24 46 L40 50" stroke="#c9c9c9" stroke-width="2.4" stroke-linecap="round" stroke-dasharray="3 2"/>'
```

In the `MONSTERS` dictionary, add these entries before `"boss_mire"`:

```python
    "kobold_firecaller": ("코볼트 화염술사", lambda f: humanoid("kfc" + f, f, (8.5, 7.5, 0.5, 34, 10.0), ("#d0763c", "#b0602c"), ("#b8412e", "#963223"),
                                                   snout=("#d0763c", "#b0602c"), horns=True, mark=FLAME), 2),
    "frost_imp": ("서리 도깨비", lambda f: humanoid("imp" + f, f, (7.5, 6.5, 0.5, 35, 9.5), ("#9fd3ec", "#7ab5d2"), ("#4d6f9c", "#3c5a80"),
                                         ears="pointy", horns=True, eye="#1d3a5c"), 2),
    "storm_bat": ("폭풍 박쥐", lambda f: bat("sbat" + f, f, ("#4a4f6e", "#3a3e58"), ("#6a6f94", "#555a7a")), 2),
    "goblin_hexer": ("고블린 주술사", lambda f: humanoid("ghx" + f, f, (9.5, 8.5, 0.5, 33, 10.5), GOBLIN_SKIN, ("#6a4a9c", "#553a80"),
                                              ears="pointy", mark=RUNE), 2),
    "gnoll_summoner": ("놀 소환사", lambda f: humanoid("gsm" + f, f, (13.5, 11.5, 1.0, 31, 11.5), ("#d2a95e", "#b58c48"), ("#3f6b5a", "#31554a"),
                                              ears="round", snout=("#6a5040", "#553f32"), spots=[(-5, -4, 1.8), (4, -6, 1.5)], mark=CHAIN), 2),
```

In `tools/art/build_game_sprites.py`, replace the `MONSTERS` list with:

```python
MONSTERS = ["dcss_rat", "dcss_frilled_lizard", "kobold", "goblin", "dcss_hobgoblin", "dcss_orc", "dcss_gnoll", "dcss_river_rat",
            "kobold_firecaller", "frost_imp", "storm_bat", "goblin_hexer", "gnoll_summoner"]
```

- [ ] **Step 4: Render and import**

Run:

```bash
cd /mnt/d/SS/new && python3 tools/art/build_monsters.py && python3 tools/art/build_game_sprites.py && godot --headless --path . --editor --import --quit >/dev/null 2>&1; ls assets/sprites-v1/monsters/
```

Expected: the listing shows `kobold_firecaller.png`, `frost_imp.png`, `storm_bat.png`, `goblin_hexer.png`, `gnoll_summoner.png` next to the eight existing sprites. Open `docs/art/monsters-v1/monster-sheet.png` and confirm the five new rows read clearly: ink outline, flat fills, eyes visible in south view, the bat's wings not merging into one black shape. If a figure reads as a dark blob, lighten its `wing` or `cloth` colours and rerun this step.

- [ ] **Step 5: Wire the sprites and the element tint**

In `expedition/art/mobile_art.gd`, replace the `MONSTER_SPRITES` constant with:

```gdscript
const MONSTER_SPRITES := [preload("res://assets/sprites-v1/monsters/dcss_rat.png"),preload("res://assets/sprites-v1/monsters/dcss_frilled_lizard.png"),
	preload("res://assets/sprites-v1/monsters/kobold.png"),preload("res://assets/sprites-v1/monsters/goblin.png"),
	preload("res://assets/sprites-v1/monsters/dcss_hobgoblin.png"),preload("res://assets/sprites-v1/monsters/dcss_orc.png"),
	preload("res://assets/sprites-v1/monsters/dcss_gnoll.png"),preload("res://assets/sprites-v1/monsters/dcss_river_rat.png"),
	preload("res://assets/sprites-v1/monsters/kobold_firecaller.png"),preload("res://assets/sprites-v1/monsters/frost_imp.png"),
	preload("res://assets/sprites-v1/monsters/storm_bat.png"),preload("res://assets/sprites-v1/monsters/goblin_hexer.png"),
	preload("res://assets/sprites-v1/monsters/gnoll_summoner.png")]
```

Replace the `MONSTER_IDS` constant with:

```gdscript
const MONSTER_IDS := ["dcss_rat","dcss_frilled_lizard","kobold","goblin","dcss_hobgoblin","dcss_orc","dcss_gnoll","dcss_river_rat",
	"kobold_firecaller","frost_imp","storm_bat","goblin_hexer","gnoll_summoner"]
## An element variant is its base sprite washed in the element's colour, with
## a small disc of that colour by its head (spec §3.7).
const ELEMENT_TINTS := {"fire":Color(1.0,0.72,0.62),"ice":Color(0.7,0.86,1.0),"air":Color(1.0,0.96,0.6),"poison":Color(0.72,1.0,0.62),"will":Color(0.86,0.72,1.0)}
const ELEMENT_MARKS := {"fire":Color("ff7a3a"),"ice":Color("7fc8ff"),"air":Color("ffe14a"),"poison":Color("7bd35a"),"will":Color("b889ff")}
```

Replace `paint_monster` with:

```gdscript
static func paint_monster(canvas: CanvasItem, species_id: String, rect: Rect2, tint: Color = Color.WHITE, element: String = "") -> void:
	var wash: Color = tint*ELEMENT_TINTS[element] if ELEMENT_TINTS.has(element) else tint
	paint_standing(canvas,enemy_sprite(species_id),rect,2.2,wash)
	if not ELEMENT_MARKS.has(element): return
	var centre := Vector2(rect.end.x-rect.size.x*0.12,rect.position.y-rect.size.y*0.9)
	var radius: float = rect.size.x*0.13
	canvas.draw_circle(centre,radius+1.5,Color(0.1,0.08,0.07,tint.a))
	canvas.draw_circle(centre,radius,Color(ELEMENT_MARKS[element],tint.a))
```

In `expedition/ui/battle_actor_visual.gd`, replace

```gdscript
		else: Art.paint_monster(self,str(actor.get("species_id","kobold")),rect,tint)
```

with

```gdscript
		else: Art.paint_monster(self,str(actor.get("species_id","kobold")),rect,tint,str(actor.get("variant_element","")))
```

- [ ] **Step 6: Run the tests and look at a variant in game**

Run: `godot --headless --path . --script res://tests/mobile_hud.gd && godot --headless --path . --script res://tests/battle_presentation.gd && godot --headless --path . --script res://tests/ui_smoke.gd`
Expected: `mobile_hud` and `battle_presentation` pass. `ui_smoke` has a known pre-existing failure on `main`; confirm any failure also occurs on the commit before this task (`git stash`, rerun, `git stash pop`) before treating it as unrelated.

Then take a screenshot of a floor with variants to check the tint and mark are legible: run the scratch screenshot script used for earlier art checks (`DISPLAY=:0 godot --path . --script <scratchpad>/shot/<script>.gd`) with `s.depth = 3; s.floor_state.build(s)` before capture, and confirm a tinted monster shows its coloured disc above the head without covering the face.

- [ ] **Step 7: Commit**

```bash
cd /mnt/d/SS/new && git add assets/monsters-v1 assets/sprites-v1/monsters docs/art/monsters-v1/monster-sheet.png && git commit -F - -- tools/art/build_monsters.py tools/art/build_game_sprites.py expedition/art/mobile_art.gd expedition/ui/battle_actor_visual.gd tests/mobile_hud.gd assets/monsters-v1 assets/sprites-v1/monsters docs/art/monsters-v1/monster-sheet.png <<'EOF'
Draw the five caster species and tint element variants

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

Do not stage the untracked `*.png.import` files that other work left in `assets/` and `docs/art/`; only the caster files this task generated (their `.import` files included) belong in this commit. Check with `git status --short assets/sprites-v1/monsters assets/monsters-v1` before committing.

---

### Task 9: Whole-suite regression

**Files:**
- Modify: only tests whose fixed expectations depended on the old monster roster (see Step 2).

- [ ] **Step 1: Run every suite**

```bash
cd /mnt/d/SS/new && for f in $(grep -l "^extends SceneTree" tests/*.gd); do printf "%-40s " "$f"; godot --headless --path . --script res://$f 2>&1 | tail -1; done
```

Expected: every suite reports 0 failures, except failures that already occurred on `main` before Task 1.

- [ ] **Step 2: Sort out any failure**

For each failing suite:

1. Check it out at the commit before Task 1 in a scratch worktree and run it there:
   ```bash
   cd /mnt/d/SS/new && git worktree add /tmp/claude-0/pre-content <commit-before-task-1> && cd /tmp/claude-0/pre-content && godot --headless --path . --script res://tests/<suite>.gd 2>&1 | tail -3; cd /mnt/d/SS/new && git worktree remove --force /tmp/claude-0/pre-content
   ```
2. If it failed there too, it is pre-existing: leave it and list it in the report.
3. If it passed there and the failing check compares a literal that comes from floor contents for a fixed seed (enemy count, a named species on seed 731, a total of threat or health), the five new species changed what that seed generates. Replace the literal with the value the new code produces, and name the suite and check in the commit message.
4. Any other new failure is a defect in Tasks 1-8: fix the code, not the test.

- [ ] **Step 3: Commit any test updates from Step 2**

```bash
cd /mnt/d/SS/new && git commit -F - -- <each test file changed in Step 2> <<'EOF'
Update seed-bound test expectations for the new monster roster

<suite: check — old value → new value, one line each>

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

Skip this step if Step 2 changed nothing.

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
| --- | --- |
| §2.4 monsters carry block and resistances | 2 |
| §3.6 five caster species, their depths, school essences | 3 (data, attacks), 8 (art) |
| §3.6 bosses have their own essence, always dropped | 6 |
| §3.6 variants have their own essence | 1 (ids), 5 (spawn, first-kill key) |
| §3.7 active gains the element effect | 4 |
| §3.7 own resistance 50, opposite −25 | 4 (weakness rule), 5 (apply) |
| §3.7 only suitable elements, 2-3 per species | 2 |
| §3.7 tinted sprite with element mark | 8 |
| §3.7 floor main element, ≥50% of variants, announced, floor 1 base only | 5 |
| §3.7 variant essence = base id + element | 1 (`definition`), Plan 1 (`Essences.row`) |
| §5 deep floors +12% HP / +8% attack per floor | 7 |
| §7 `tests/variants.gd` | 1, 2, 4, 5 |

Not in this plan: the essence screen, banners, character stat sheet, monster long-press view, NPC essence choice and the difficulty gate (Plan 3); the rules engine (Plan 1); species beyond these thirteen (spec §8).

**Type consistency:** `variant_element` (enemy field), `s.floor_state.element`, `attack_percent`, `Abilities.has/definition/usable_by/kind_key/scaled/strike_victim/element_mark`, `Variants.allowed/floor_element/apply/assign`, `Floor.last_catalog_depth/deep_scale`, `BossAI.BOSS_PARTS/BOSS_SPECIES`, `Art.ELEMENT_TINTS/ELEMENT_MARKS` are spelled the same in every task and test.
