# 조우 시뮬레이터 · 행동 경제 실험 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고정 아레나에서 조우 구성·파티 인원·빌드·봇 정책·행동 규칙을 같은 시드로 비교하는 시뮬레이터를 만들고, 행동 경제 세 안(현행/A/B)의 비교 보고서를 생성한다.

**Architecture:** 세션에 `rules_config`와 `party_size`를 추가하고 `continuous_floor.build()`를 `apply(layout)`로 분리해, 시뮬레이터가 만든 아레나 레이아웃을 실제 전투 경로에 그대로 흘려 넣는다. 아레나 생성(`expedition/sim/encounter_arena.gd`), 봇 정책(`expedition/sim/bot_policy.gd`), 실행·통계(`expedition/sim/encounter_runner.gd`)는 순수 정적 모듈. 실험 정의는 JSON, 보고서는 마크다운+JSON.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 SceneTree 테스트, JSON 콘텐츠.

**Spec:** `docs/superpowers/specs/2026-09-22-encounter-sim-design.md` — 구현자는 스펙을 먼저 읽는다. 결정 규칙(§6)은 이 계획에서 바꾸지 않는다.

## Global Constraints

- 헤드리스만 사용. `godot` 창을 절대 띄우지 않는다.
- `rules_config` 기본값(`{"solo_actions":1,"solo_max_members":0}`)과 `p_party_size=0`인 세션은 현행과 동일하게 동작해야 한다. 기존 24개 스위트(`tests/*.gd`, `map_fixture`·`floor_fixture` 제외)가 전부 통과해야 하며, 알려진 사전 실패 2개(`curios.gd` "new discovery stops auto exploration after one step", `companion_tactics.gd` 보스 HUD)만 예외.
- 전투 규칙을 시뮬레이터에 복제하지 않는다. `Session`·`MonsterAI`·`EncounterBuilder`·`continuous_floor`의 공개 함수만 호출한다.
- 모든 난수는 `Session.new(seed, …)`의 시드와 `RandomNumberGenerator`로만. 같은 `(config, seed)` → 같은 결과.
- 밸런스 데이터(`floor_themes.json` 예산, `SOLO_HP_*`, 봇 임계값 14/10)를 바꾸지 않는다. 채택된 규칙을 기본값으로 바꾸는 것도 이 계획의 범위 밖.
- 새 파일 위치: 라이브러리 `expedition/sim/*.gd`, 데이터 `data/content/*.json`, 테스트 `tests/*.gd`, 보고서 `docs/balance/*`.
- 커밋: 로컬만, 작성자 `jinha1226 <jinha1226@gmail.com>`, 메시지 끝 `Co-Authored-By` 줄 포함. push 금지.
- 테스트 형식은 기존과 동일(`extends SceneTree`, `check(ok, reason)`, `print("<이름>: %d failures")`, `quit(1 if failures else 0)`).

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `expedition/session.gd` (수정) | `_init` 5번째 인자 `p_party_size`; `rules_config`; `action_budget`·`finish_player_action`의 A안 분기 |
| `expedition/encounter_builder.gd` (수정) | `fill(..., max_members := MAX_MEMBERS)`, `attempt(..., max_members)` |
| `expedition/continuous_floor.gd` (수정) | `build` → `apply(s, theme, layout)` 분리; 솔로 `solo_max_members` 적용 |
| `expedition/sim/encounter_arena.gd` (신규) | 아레나 spec → §7 레이아웃 |
| `expedition/sim/bot_policy.gd` (신규) | `simple`, `tactical` 정책 |
| `expedition/sim/encounter_runner.gd` (신규) | `run_one`, `run_many`, 통계, 빌드 적용 |
| `data/content/reference_builds.json`, `data/content/balance_experiments.json` (신규) | 빌드 2개, 실험 행렬 |
| `tests/encounter_sim.gd` (신규, CI) | 결정론·규칙·정책·통계 검사 |
| `tests/action_economy.gd` (신규, 수동) | 행렬 실행 → `docs/balance/action-economy.{md,json}` |

---

### Task 1: 세션 규칙과 파티 인원

**Files:**
- Modify: `expedition/session.gd` (`_init`, `action_budget`, `finish_player_action`, 새 `var rules_config`)
- Modify: `expedition/encounter_builder.gd` (`fill`, `attempt`)
- Test: `tests/encounter_sim.gd` (이 Task에서 시작)

**Interfaces:**
- Produces: `Session.new(seed, boss_trial, companions, floor, party_size := 0)`; `s.rules_config: Dictionary`; `Session.DEFAULT_RULES := {"solo_actions":1,"solo_max_members":0}`; `s.solo_rule(key) -> int`(파티 인원이 1이고 floor_mode일 때 값, 아니면 기본값); `EncounterBuilder.fill(rng, depth, budget, ood, max_members := MAX_MEMBERS)`.

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/encounter_sim.gd` 초판

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Builder = preload("res://expedition/encounter_builder.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r

func run() -> void:
	await rules_and_party()
	print("Encounter sim: %d failures" % failures); quit(1 if failures else 0)

func rules_and_party() -> void:
	for size in [1,2,3]:
		var s = Session.new(731,true,size > 1,true,size)
		check(s.party.size() == size and s.companions == (size > 1),"party_size %d builds %d members" % [size,size])
	var legacy = Session.new(731,true,true,true)
	check(legacy.party.size() == 2,"party_size 0 keeps the legacy rule")
	check(Session.new(731,true,false,true).rules_config == Session.DEFAULT_RULES,"default rules")
	var solo = Session.new(731,true,false,true,1); solo.depart()
	check(solo.action_budget(solo.party[0]) == 1,"default solo budget is one action")
	solo.rules_config = {"solo_actions":2,"solo_max_members":0}
	check(solo.action_budget(solo.party[0]) == 2,"solo_actions 2 doubles the budget")
	var duo = Session.new(731,true,true,true,2); duo.rules_config = {"solo_actions":2,"solo_max_members":0}; duo.depart()
	check(duo.action_budget(duo.party[0]) == 1,"solo_actions never applies to a party")
	# Two actions before the round advances.
	var c := Fixture.arena(solo,6)
	solo.party[0].ap = solo.action_budget(solo.party[0])
	var round_before: int = solo.round_number
	check(solo.act("WAIT",c) and solo.round_number == round_before and solo.party[0].ap == 1,"first action leaves the round open")
	check(solo.act("WAIT",c) and solo.round_number == round_before+1 and solo.party[0].ap == 2,"second action ends the round and refills")
	solo.rules_config = Session.DEFAULT_RULES.duplicate(); solo.party[0].ap = 1; round_before = solo.round_number
	check(solo.act("WAIT",c) and solo.round_number == round_before+1,"default rules end the round after one action")
	# max_members cap on fill.
	var seen_three := false; var capped_ok := true
	for seed_value in range(60):
		if Builder.fill(rng(seed_value),1,9,false).size() >= 3: seen_three = true
		if Builder.fill(rng(seed_value),1,9,false,2).size() > 2: capped_ok = false
	check(seen_three and capped_ok,"max_members caps fill at two")
```

- [ ] **Step 2: 실패 확인** — `godot --headless --path . --script res://tests/encounter_sim.gd` → `_init` 인자 수 오류.

- [ ] **Step 3: 구현**

`expedition/session.gd`:
```gdscript
const DEFAULT_RULES := {"solo_actions":1,"solo_max_members":0}
var rules_config: Dictionary = DEFAULT_RULES.duplicate()

func _init(p_seed: int = 731, p_boss_trial: bool = false, p_companions: bool = false, p_floor: bool = false, p_party_size: int = 0) -> void:
	seed_value = p_seed
	boss_trial = p_boss_trial
	companions = (p_party_size > 1) if p_party_size > 0 else (p_companions and boss_trial)
	floor_mode = p_floor
	# ... 기존 floor_mode 블록 그대로 ...
	var count: int = clampi(p_party_size,1,3) if p_party_size > 0 else (2 if companions else 1 if boss_trial else 3)
	for i in range(count):
		party.append(make_actor(i, ["아린", "브란", "세라"][i], false))
	message("부상과 기억은 원정을 마쳐도 남습니다. 준비되면 출정하세요.")

func solo_rule(key: String) -> int:
	if not floor_mode or party.size() != 1: return int(DEFAULT_RULES[key])
	return int(rules_config.get(key,DEFAULT_RULES[key]))

func action_budget(actor: Dictionary) -> int:
	if boss_trial: return solo_rule("solo_actions")
	return 1 if actor.stress >= 150 else 2
```
`finish_player_action()`의 마지막 줄 `if phase == "BATTLE": end_round()`를 다음으로:
```gdscript
	if phase == "BATTLE" and party[selected].ap <= 0: end_round()
```
현행(예산 1)에서는 모든 행동이 `ap`를 0으로 만들어 동작이 같다. 단, `Curios.resolve`·`Objective.pickup`·`use_supply`는 `ap -= 1` 뒤 `finish_player_action`을 부르므로 그대로 둔다. `end_round()`에서 `actor.ap = action_budget(actor)` 재충전은 기존 코드.

`expedition/encounter_builder.gd`: `attempt(rng, depth, budget, ood, max_members := MAX_MEMBERS)`로 바꾸고 본문의 `MAX_MEMBERS` 세 곳(while 조건, band follower break, valid의 "too many"는 그대로 MAX_MEMBERS 유지)을 `max_members`로. `fill(rng, depth, budget, ood, max_members := MAX_MEMBERS)`가 `attempt`에 전달.

- [ ] **Step 4: 통과 확인** — 위 스위트 `0 failures`. 그리고 `tests/solo_floor.gd`, `tests/solo_balance.gd`, `tests/curios.gd`, `tests/encounter_builder.gd`, `tests/companion_tactics.gd`, `tests/torch_tradeoff.gd`가 이전과 같은 결과(알려진 실패 2개 외 녹색).

- [ ] **Step 5: 커밋** — `feat: session rules config and party size`

---

### Task 2: `continuous_floor.apply()` 분리와 아레나 레이아웃

**Files:**
- Modify: `expedition/continuous_floor.gd` (`build` → `build` + `apply`)
- Create: `expedition/sim/encounter_arena.gd`
- Modify: `tests/encounter_sim.gd`

**Interfaces:**
- Produces: `Floor.apply(s, theme: Dictionary, p_layout: Dictionary) -> void`; `EncounterArena.layout(spec: Dictionary, theme: Dictionary) -> Dictionary`(§7 계약); `EncounterArena.DEFAULT_SPEC` (`size 20, room [5,5,9,9], door [9,4], pillars [[8,8],[10,10]], party_entry [9,3], light 90`).
- Consumes: `EncounterBuilder.member(row, role)`, `EncounterBuilder.species(id)`, `EncounterBuilder.place(...)`.

- [ ] **Step 1: 테스트 추가** — `run()`에 `await arena_layout()` 추가

```gdscript
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")

func arena_layout() -> void:
	var theme: Dictionary = Generator.theme("F1_RUINS")
	var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	spec.members = [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"}]
	var layout: Dictionary = Arena.layout(spec,theme)
	for key in ["size","seed","theme_id","depth","terrain","rooms","edges","entry","relic","features","encounters","stats"]:
		check(layout.has(key),"arena layout carries %s" % key)
	check(layout.size == 20 and layout.terrain.size() == 400,"arena is 20x20")
	check(layout.terrain[4*20+9] == "stone" and layout.terrain[3*20+9] == "stone","door and entry corridor are floor")
	check(layout.terrain[8*20+8] == "wall" and layout.terrain[10*20+10] == "wall","pillars are wall")
	check(layout.rooms.size() == 1 and layout.rooms[0].doors == [Vector2i(9,4)],"one room, one door")
	check(layout.encounters.size() == 1 and layout.encounters[0].members.size() == 2,"one encounter with the given members")
	for m in layout.encounters[0].members:
		check(m.has("pos") and m.has("max_health") and m.has("display_name") and Rect2i(5,5,9,9).has_point(m.pos),"member placed inside the room")
		check(maxi(absi(m.pos.x-9),absi(m.pos.y-4)) >= 3,"member three cells from the door")
	check(layout.relic == Vector2i(-1,-1) and layout.entry == Vector2i(9,3) and layout.features.is_empty(),"no relic or features")
	var s = Session.new(5,true,false,true,1)
	Floor.apply(s,theme,layout)
	check(s.BOARD_SIDE == 20 and s.tiles.size() == 400 and s.phase == "BATTLE","apply consumes the arena")
	check(s.enemies.size() == 2 and s.enemies[0].role == "MELEE" and s.enemies[1].role == "RANGED","enemies configured with their roles")
	check(s.party[0].pos == Vector2i(9,3) and s.objective.is_empty(),"party at entry, no objective")
	check(s.floor_state.visible.has(s.party[0].pos),"observation ran")
	var same = Session.new(5,true,false,true,1); Floor.apply(same,theme,Arena.layout(spec,theme))
	check(same.enemies.map(func(e): return e.pos) == s.enemies.map(func(e): return e.pos),"arena placement deterministic")
	# The normal floor still builds through apply.
	var normal = Session.new(731,true,false,true,1); normal.depart()
	check(normal.BOARD_SIDE == 64 and not normal.objective.is_empty(),"build() still generates the real floor")
```

- [ ] **Step 2: 실패 확인** — `apply` 미정의.

- [ ] **Step 3: 구현**

`expedition/continuous_floor.gd`:
```gdscript
func build(s) -> void:
	var theme: Dictionary = Generator.theme(theme_id)
	apply(s,theme,Generator.generate(theme,s.seed_value+s.expedition_number*7919,int(theme.depth)))

## Consumes a §7 layout: tiles, enemies, features, party spawn, objective.
func apply(s, theme: Dictionary, p_layout: Dictionary) -> void:
	layout = p_layout
	assert(not layout.is_empty(),"floor generator returned no layout")
	# ... 기존 build 본문 그대로 (size, epoch, tiles, enemies, features, party) ...
	var cap: int = s.solo_rule("solo_max_members")
	# 기존 enemies 루프에서 encounter.members 대신:
	#   var members: Array = encounter.members if cap <= 0 or s.party.size() != 1 else encounter.members.slice(0,cap)
	if layout.relic.x >= 0: Objective.register(s,layout.relic)
	else: s.objective = {}
	# ... rooms, phase, observe(s); ambush(s) 그대로 ...
```
`s.rooms[0].name`은 `"1층 · "+str(theme.label)` 유지.

`expedition/sim/encounter_arena.gd`:
```gdscript
extends RefCounted
## Fixed fight room as a §7 layout so the real floor/session code runs unchanged.
const Builder = preload("res://expedition/encounter_builder.gd")
const DEFAULT_SPEC := {"size":20,"room":[5,5,9,9],"door":[9,4],"pillars":[[8,8],[10,10]],"party_entry":[9,3],"light":90,"members":[]}

static func layout(spec: Dictionary, theme: Dictionary) -> Dictionary:
	var size: int = spec.size
	var terrain: Array = []; terrain.resize(size*size); terrain.fill("wall")
	var rect := Rect2i(spec.room[0],spec.room[1],spec.room[2],spec.room[3])
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x): terrain[y*size+x] = "stone"
	var door := Vector2i(spec.door[0],spec.door[1]); var entry := Vector2i(spec.party_entry[0],spec.party_entry[1])
	var p := entry
	while p != door:
		terrain[p.y*size+p.x] = "stone"; p += Vector2i(signi(door.x-p.x),signi(door.y-p.y))
	terrain[door.y*size+door.x] = "stone"
	var obstacles: Dictionary = {}
	for pillar in spec.pillars:
		var q := Vector2i(pillar[0],pillar[1]); terrain[q.y*size+q.x] = "wall"; obstacles[q] = true
	var members: Array = []
	for row in spec.members:
		var member: Dictionary = Builder.member(Builder.species(row.species_id),row.role)
		if row.has("pos"): member.pos = Vector2i(row.pos[0],row.pos[1])
		members.append(member)
	var floor_cells: Array = []
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if not obstacles.has(Vector2i(x,y)): floor_cells.append(Vector2i(x,y))
	var unplaced: Array = members.filter(func(m): return not m.has("pos"))
	if not unplaced.is_empty():
		var rng := RandomNumberGenerator.new(); rng.seed = 1
		assert(Builder.place(unplaced,floor_cells,[door],Vector2i(-1,-1),[],obstacles,rng),"arena placement failed")
	var room := {"id":0,"rect":rect,"kind":"fight","template_id":"","rows":[],"parsed":{},"doors":[door],"tier":spec.get("tier","deep"),"spine":true}
	return {"size":size,"seed":0,"theme_id":theme.get("id",""),"depth":int(theme.depth),"terrain":terrain,"rooms":[room],"edges":[],
		"entry":entry,"relic":Vector2i(-1,-1),"features":{},
		"encounters":[{"room":0,"tier":room.tier,"mandatory":true,"budget":0,"members":members}],
		"stats":{"regenerations":0,"relic_distance":0,"max_distance":0}}
```

- [ ] **Step 4: 통과 확인** — `tests/encounter_sim.gd`, `tests/continuous_floor.gd`, `tests/solo_floor.gd` 녹색.
- [ ] **Step 5: 커밋** — `feat: split floor apply and add the encounter arena`

---

### Task 3: 봇 정책, 실행기, 통계

**Files:**
- Create: `expedition/sim/bot_policy.gd`, `expedition/sim/encounter_runner.gd`, `data/content/reference_builds.json`
- Modify: `tests/encounter_sim.gd`

**Interfaces:**
- Produces: `BotPolicy.step(s, policy: String) -> bool`; `EncounterRunner.run_one(config, seed) -> Dictionary`; `EncounterRunner.run_many(config, seeds: Array) -> Dictionary`; `EncounterRunner.apply_build(s, build_id)`; `EncounterRunner.wilson(wins, n) -> Array[float]`; `EncounterRunner.percentile(values: Array, p: float) -> float`.

- [ ] **Step 1: 데이터** — `data/content/reference_builds.json`을 스펙 §5.1 그대로.

- [ ] **Step 2: 테스트 추가** — `run()`에 `await runner()` 추가

```gdscript
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")

func config(members: Array, size: int, policy: String, rules: Dictionary) -> Dictionary:
	var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true); spec.members = members
	return {"arena":spec,"party_size":size,"build":"melee_1","policy":policy,"rules":rules,"supplies":[1,0,0,0,0,1],"max_rounds":60}

func runner() -> void:
	check(Runner.wilson(0,10)[0] == 0.0 and absf(Runner.wilson(5,10)[0]-0.237) < 0.01 and absf(Runner.wilson(5,10)[1]-0.763) < 0.01,"wilson interval")
	check(Runner.percentile([1,2,3,4,5],0.5) == 3.0 and Runner.percentile([1,2,3,4,5],0.9) == 5.0,"percentiles")
	var hob := [{"species_id":"dcss_hobgoblin","role":"MELEE"}]
	var one: Dictionary = Runner.run_one(config(hob,1,"tactical",Session.DEFAULT_RULES),11)
	check(one.result in ["WIN","DEFEAT","TIMEOUT"] and one.rounds >= 1 and one.damage_taken.size() == 1,"run_one returns a result")
	check(one == Runner.run_one(config(hob,1,"tactical",Session.DEFAULT_RULES),11),"run_one deterministic")
	check(Runner.run_one(config(hob,1,"simple",Session.DEFAULT_RULES),11).result != "TIMEOUT","simple policy finishes a solo fight")
	var trio: Dictionary = Runner.run_one(config(hob,3,"tactical",Session.DEFAULT_RULES),11)
	check(trio.damage_taken.size() == 3 and trio.result == "WIN","a trio beats a lone hobgoblin")
	var mixed := [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"},{"species_id":"kobold","role":"MELEE"}]
	var capped: Dictionary = Runner.run_one(config(mixed,1,"tactical",{"solo_actions":1,"solo_max_members":2}),3)
	check(capped.enemy_count == 2,"solo_max_members trims the arena roster")
	var doubled: Dictionary = Runner.run_one(config(mixed,1,"tactical",{"solo_actions":2,"solo_max_members":0}),3)
	check(doubled.enemy_count == 3 and doubled.player_actions >= doubled.rounds,"solo_actions 2 grants at least one action per round")
	var many: Dictionary = Runner.run_many(config(hob,1,"tactical",Session.DEFAULT_RULES),range(100,120))
	check(many.samples == 20 and many.results.has("WIN") and many.win_rate >= 0.0 and many.win_ci.size() == 2,"run_many aggregates")
	check(many.damage.has("mean") and many.damage.has("p95") and many.rounds.has("median"),"run_many statistics")
```

- [ ] **Step 3: 실패 확인** — `bot_policy.gd` 없음.

- [ ] **Step 4: 구현**

`expedition/sim/bot_policy.gd`:
```gdscript
extends RefCounted
## One player action per call through the public session API. No combat math here.
static func step(s, policy: String) -> bool:
	var hero: Dictionary = s.party[s.selected]
	if hero.hp <= 0 or hero.ap <= 0: return false
	if policy == "tactical":
		if hero.hp < 14 and s.supplies[0] > 0 and s.use_supply(0): return true
		if hero.hp < 10 and s.supplies[5] > 0 and s.use_supply(5): return true
		var adjacent := 0
		for e in s.combat_enemies():
			if maxi(absi(e.pos.x-hero.pos.x),absi(e.pos.y-hero.pos.y)) == 1: adjacent += 1
		if adjacent >= 2 and not hero.get("guarded",false) and s.act("GUARD",hero.pos): return true
	if s.auto_attack(): return true
	return s.act("WAIT",hero.pos)
```

`expedition/sim/encounter_runner.gd`:
```gdscript
extends RefCounted
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")
static var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/reference_builds.json"))

static func build(id: String) -> Dictionary:
	for row in builds.builds:
		if row.id == id: return row
	return {}

static func apply_build(s, id: String) -> void:
	var row := build(id)
	for actor in s.party:
		for axis in row.get("ranks",{}): actor.growth.ranks[axis] = int(row.ranks[axis])
		for stat in row.get("stats",{}): actor.growth.stats[stat] = int(row.stats[stat])
		for ability in row.get("learned",[]):
			if ability not in actor.learned_abilities: actor.learned_abilities.append(ability)
		actor.equipped_abilities = row.equipped.duplicate()

static func run_one(config: Dictionary, seed: int) -> Dictionary:
	var size: int = config.party_size
	var s = Session.new(seed,true,size > 1,true,size)
	s.rules_config = config.rules.duplicate()
	apply_build(s,config.build)
	var theme: Dictionary = Generator.theme("F1_RUINS")
	Floor.apply(s,theme,Arena.layout(config.arena,theme))
	s.light = int(config.arena.get("light",90)); s.supplies = config.supplies.duplicate()
	var taken: Array = []; for _a in s.party: taken.append(0)
	var dealt: Dictionary = {}
	var first_death := -1; var heals := 0; var guards := 0; var actions := 0; var before_first := 0; var acted := false
	var idle := 0
	var result := "TIMEOUT"
	while s.phase == "BATTLE" and s.round_number <= int(config.max_rounds):
		var supplies_before: int = s.supplies[0]+s.supplies[5]
		var guarded_before: bool = s.party[s.selected].get("guarded",false)
		var ok: bool = Policy.step(s,config.policy)
		if ok: actions += 1; acted = true; idle = 0
		else:
			idle += 1
			if idle >= 2: s.act("WAIT",s.party[s.selected].pos); idle = 0
		if s.supplies[0]+s.supplies[5] < supplies_before: heals += 1
		if not guarded_before and s.party[s.selected].get("guarded",false): guards += 1
		for effect in s.effects:
			if effect.get("kind","") == "ENEMY_ATTACK" or not effect.has("amount"): continue
			var victim := s.at(effect.cell)
			if victim.is_empty() or victim.enemy: continue
			taken[victim.id] += int(effect.amount)
			if not acted: before_first += int(effect.amount)
			dealt[effect.from] = int(dealt.get(effect.from,0))+int(effect.amount)
		s.effects.clear()
		if first_death < 0 and s.party.any(func(a): return a.hp <= 0): first_death = s.round_number
		if s.enemies.all(func(e): return e.hp <= 0): result = "WIN"; break
	if s.phase != "BATTLE" and result != "WIN": result = "DEFEAT"
	return {"result":result,"rounds":s.round_number,"damage_taken":taken,"hp_end":s.party.map(func(a): return a.hp),
		"deaths":s.party.filter(func(a): return a.hp <= 0).map(func(a): return a.id),"first_death_round":first_death,
		"heals_used":heals,"guards_used":guards,"player_actions":actions,"damage_before_first_action":before_first,
		"enemy_count":s.enemies.size(),"enemy_damage_dealt":dealt}
```
주의: `damage()`는 `effects`에 `{"from","cell","amount","form"}`를 남기고 `run_action`이 없는 헤드리스에서는 아무도 비우지 않으므로 루프마다 수거·정리한다. `effect.from`은 공격자 위치(적 id가 아님)이므로 `enemy_damage_dealt`는 위치 키로 저장하고 보고서에서는 합계만 쓴다.

```gdscript
static func wilson(wins: int, n: int) -> Array:
	if n == 0: return [0.0,0.0]
	var z := 1.96; var p := float(wins)/n
	var denom := 1.0+z*z/n
	var centre := (p+z*z/(2*n))/denom
	var half := z*sqrt(p*(1-p)/n+z*z/(4.0*n*n))/denom
	return [maxf(0.0,centre-half),minf(1.0,centre+half)]

static func percentile(values: Array, p: float) -> float:
	if values.is_empty(): return 0.0
	var sorted: Array = values.duplicate(); sorted.sort()
	var index: int = clampi(int(ceil(p*sorted.size()))-1,0,sorted.size()-1)
	return float(sorted[index])

static func summary(values: Array) -> Dictionary:
	if values.is_empty(): return {"mean":0.0,"sd":0.0,"median":0.0,"p90":0.0,"p95":0.0}
	var mean := 0.0
	for v in values: mean += v
	mean /= values.size()
	var variance := 0.0
	for v in values: variance += (v-mean)*(v-mean)
	return {"mean":mean,"sd":sqrt(variance/values.size()),"median":percentile(values,0.5),"p90":percentile(values,0.9),"p95":percentile(values,0.95)}

static func run_many(config: Dictionary, seeds: Array) -> Dictionary:
	var runs: Array = []
	for seed in seeds: runs.append(run_one(config,seed))
	var results: Dictionary = {}
	for r in runs: results[r.result] = int(results.get(r.result,0))+1
	var wins: int = int(results.get("WIN",0))
	var per_member: Array = []
	for r in runs:
		for value in r.damage_taken: per_member.append(value)
	return {"samples":runs.size(),"results":results,"win_rate":float(wins)/runs.size(),"win_ci":wilson(wins,runs.size()),
		"damage":summary(per_member),"damage_wins":summary(runs.filter(func(r): return r.result == "WIN").map(func(r): return r.damage_taken.reduce(func(a,b): return a+b,0))),
		"rounds":summary(runs.map(func(r): return r.rounds)),
		"first_death":summary(runs.filter(func(r): return r.first_death_round > 0).map(func(r): return r.first_death_round)),
		"heals":summary(runs.map(func(r): return r.heals_used)),"deaths":runs.reduce(func(acc,r): return acc+r.deaths.size(),0),"runs":runs}
```

- [ ] **Step 5: 통과 확인** — `tests/encounter_sim.gd` 0 failures, 30초 이내(시간 출력 추가: `print("Encounter sim: %d failures (%d ms)" % [...])`).
- [ ] **Step 6: 커밋** — `feat: encounter simulator runner and bot policies`

---

### Task 4: 행동 경제 실험 도구와 보고서

**Files:**
- Create: `data/content/balance_experiments.json` (스펙 §5.2 그대로), `tests/action_economy.gd`, `docs/balance/action-economy.md`, `docs/balance/action-economy.json`
- Modify: `docs/balance-method.ko.md` §8-1 (실행 결과 링크), `README.md` 검증 절(수동 도구 안내), `.github/workflows/deploy-pages.yml` (`encounter_sim` 추가; `action_economy`는 추가하지 않음)

**Interfaces:**
- Consumes: Task 3 `Runner.run_many`, `Arena.DEFAULT_SPEC`.
- Produces: `docs/balance/action-economy.md` (표 1·표 2·판정), `docs/balance/action-economy.json` (`run_many` 결과 전체, `runs` 제외).

- [ ] **Step 1: 실험 데이터** — 스펙 §5.2의 JSON을 `data/content/balance_experiments.json`에 그대로 작성. 각 아레나에 `DEFAULT_SPEC`을 병합해 spec을 만들고 `members`는 `[species_id, role]` 쌍을 딕셔너리로 변환한다.

- [ ] **Step 2: 도구 작성** — `tests/action_economy.gd`

```gdscript
extends SceneTree
## Manual tool: runs the action-economy matrix and writes docs/balance/action-economy.{md,json}.
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Session = preload("res://expedition/session.gd")
static var experiments: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var started := Time.get_ticks_msec()
	var ex: Dictionary = experiments.experiments.action_economy
	var seeds: Array = range(int(ex.seed_set.start),int(ex.seed_set.start)+int(ex.seed_set.count))
	var quick: bool = "--quick" in OS.get_cmdline_user_args()
	if quick: seeds = seeds.slice(0,20)
	var table: Array = []
	for rule_id in ex.rules:
		for size in ex.party_sizes:
			for build_id in ex.builds:
				for arena_id in ex.arenas:
					var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
					spec.tier = ex.arenas[arena_id].tier
					spec.members = ex.arenas[arena_id].members.map(func(pair): return {"species_id":pair[0],"role":pair[1]})
					var config := {"arena":spec,"party_size":size,"build":build_id,"policy":ex.policies[0],"rules":ex.rules[rule_id],"supplies":ex.supplies,"max_rounds":60}
					var stats: Dictionary = Runner.run_many(config,seeds)
					stats.erase("runs")
					table.append({"rule":rule_id,"party":size,"build":build_id,"arena":arena_id,"tier":spec.tier,"stats":stats})
					print("%s p%d %s %s: win %.2f [%.2f,%.2f] dmg %.1f p95 %.1f rounds %.1f" % [rule_id,size,build_id,arena_id,stats.win_rate,stats.win_ci[0],stats.win_ci[1],stats.damage.mean,stats.damage.p95,stats.rounds.mean])
	var verdicts: Dictionary = decide(table,ex)
	write_report(table,verdicts,ex,seeds,Time.get_ticks_msec()-started,quick)
	quit(0)
```

판정(스펙 §6 그대로):
```gdscript
func row(table: Array, rule: String, party: int, build: String, arena: String) -> Dictionary:
	for r in table:
		if r.rule == rule and r.party == party and r.build == build and r.arena == arena: return r.stats
	return {}
func decide(table: Array, ex: Dictionary) -> Dictionary:
	var deep: Array = ex.arenas.keys().filter(func(id): return ex.arenas[id].tier == "deep")
	var out: Dictionary = {}
	for rule_id in ex.rules:
		var a: bool = deep.all(func(id): return row(table,rule_id,1,"melee_1",id).win_rate >= 0.70)
		var b: bool = deep.all(func(id): return row(table,rule_id,2,"melee_1",id).damage.mean < row(table,rule_id,1,"melee_1",id).damage.mean)
		var c: bool = deep.all(func(id): return row(table,rule_id,3,"melee_1",id).win_rate >= 0.90)
		out[rule_id] = {"a":a,"b":b,"c":c,"pass":a and b and c}
	var order := ["current","B","A"]
	out.candidate = ""
	for rule_id in order:
		if out[rule_id].pass: out.candidate = rule_id; break
	return out
```

보고서(`write_report`): 머리말(커밋 해시는 `git rev-parse --short HEAD`를 `OS.execute`로 읽되 실패 시 "unknown", 날짜, 시드 묶음, `SOLO_HP_PERCENT/MIN/MAX` 값, 정책 이름, 아레나 spec, 실행 시간, `--quick` 여부), 표 1(규칙·인원·빌드·아레나·티어·승률[CI]·평균 피해·p95·평균 라운드·첫 사망 중앙값·회복 평균), 표 2(규칙별 a/b/c/pass), "채택 후보: X" 또는 "보류" + 심부 아레나의 첫 사망 라운드·p95 요약 문장. JSON은 `{"generated":..., "seed_set":..., "table":table, "verdicts":verdicts}`. 도구는 **후보를 출력할 뿐 확정하지 않는다**는 문장을 보고서에 포함한다.

- [ ] **Step 3: 빠른 실행으로 형식 확인** — `godot --headless --path . --script res://tests/action_economy.gd -- --quick` (20시드). 표가 두 파일에 써지고 형식이 스펙 §6과 맞는지 확인.

- [ ] **Step 4: 전체 실행** — `--quick` 없이 200시드. 실행 시간을 기록. 5분을 넘기면 `size`를 16으로 줄이지 말고(지형 조건이 바뀜) 결과 시간을 그대로 보고서에 남긴다.

- [ ] **Step 5: 문서** — `docs/balance-method.ko.md` §8-1 종료 조건 아래에 `실행 결과: docs/balance/action-economy.md (YYYY-MM-DD, 후보: X | 보류)` 한 줄. README 검증 절에 `tests/encounter_sim.gd`(CI) 명령과 `tests/action_economy.gd -- [--quick]`(수동) 안내 두 줄. 워크플로 suite 목록에 ` encounter_sim` 추가.

- [ ] **Step 6: 전체 스위트** — 기존 24개 + `encounter_sim` 녹색(알려진 실패 2개 제외), 임포트 검사 무출력.

- [ ] **Step 7: 커밋** — `feat: action-economy experiment tool and report`

---

## 자체 점검

- 스펙 §2 → Task 1·2, §3 → Task 2, §4·§5 → Task 3, §5.1·§5.2·§6 → Task 4, §7 → 각 Task의 테스트, §8(채택안 기본값화 제외) 준수.
- 시그니처 일치: `Floor.apply(s, theme, layout)`은 Task 2 정의·Task 3 호출 동일; `Runner.run_one` 반환 키(`result, rounds, damage_taken, hp_end, deaths, first_death_round, heals_used, guards_used, player_actions, damage_before_first_action, enemy_count, enemy_damage_dealt`)는 Task 3 테스트와 Task 4 표 생성이 같은 이름을 쓴다; `run_many` 키(`samples, results, win_rate, win_ci, damage, damage_wins, rounds, first_death, heals, deaths`) 동일.
- 결정 규칙의 순서 `current > B > A`는 스펙 §6 "변경 폭이 작은 순"과 같다.
