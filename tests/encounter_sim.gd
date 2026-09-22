extends SceneTree
const Session = preload("res://expedition/session.gd")
const Builder = preload("res://expedition/encounter_builder.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r

func run() -> void:
	var started := Time.get_ticks_msec()
	await rules_and_party()
	await arena_layout()
	await runner()
	await rules_policy()
	print("Encounter sim: %d failures (%d ms)" % [failures,Time.get_ticks_msec()-started]); quit(1 if failures else 0)

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
	# Dark arena: apply()'s ambush gives the monster a free turn before the hero acts,
	# which it now spends announcing its signature part.
	var dark: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	dark.light = 20; dark.members = [{"species_id":"dcss_hobgoblin","role":"MELEE","pos":[9,6]}]
	var ambush_seen := {"acted":false}
	var ambushed: Dictionary = Runner.run_one({"arena":dark,"party_size":1,"build":"melee_1","policy":"tactical",
		"rules":Session.DEFAULT_RULES,"supplies":[1,0,0,0,0,1],"max_rounds":60,
		"probe":func(s,round_number): if round_number == 1 and not s.intents.is_empty(): ambush_seen.acted = true},7)
	check(ambushed.damage_before_first_action > 0 or ambush_seen.acted,"the ambusher strikes or announces before the first action")
	check(ambushed.enemy_skill_uses is Dictionary and ambushed.interrupts is int,"run_one reports enemy part uses and interrupts")
	var many: Dictionary = Runner.run_many(config(hob,1,"tactical",Session.DEFAULT_RULES),range(100,120))
	check(many.samples == 20 and many.results.has("WIN") and many.win_rate >= 0.0 and many.win_ci.size() == 2,"run_many aggregates")
	check(many.has("damage_wins_per_member") and many.has("guards") and many.has("before_first"),"run_many reports per-member win damage, guards and before_first")
	check(many.damage.has("mean") and many.damage.has("p95") and many.rounds.has("median"),"run_many statistics")
	check(many.has("distinct_outcomes") and many.distinct_outcomes >= 1 and many.distinct_outcomes <= many.samples,"run_many counts distinct outcomes")
	check(many.has("enemy_skill_uses_mean") and many.has("interrupts_mean") and many.interrupts_mean >= 0.0,"run_many averages enemy part uses and interrupts")
	# Hits no longer cancel a part charge, so announced parts actually land.
	var part_mean: float = many.enemy_skill_uses_mean.values().reduce(func(a,b): return a+b,0.0)
	check(part_mean > 0.0,"monsters land their signature parts over twenty runs")

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
	# The roster cap lives in the arena now; fill() itself is uncapped.
	var seen_three := false
	for seed_value in range(60):
		if Builder.fill(rng(seed_value),1,9,false).size() >= 3: seen_three = true
	check(seen_three,"fill can draw three members")

func arena_layout() -> void:
	var theme: Dictionary = Generator.theme("F1_RUINS")
	var spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	spec.members = [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"}]
	var layout: Dictionary = Arena.layout(spec,theme)
	for key in ["size","seed","theme_id","depth","terrain","rooms","edges","entry","relic","features","encounters","stats"]:
		check(layout.has(key),"arena layout carries %s" % key)
	check(layout.size == 20 and layout.terrain.size() == 400,"arena is 20x20")
	check(layout.terrain[4*20+9] == "stone" and layout.terrain[5*20+9] == "stone","door and entry are floor")
	check(layout.terrain[8*20+8] == "wall" and layout.terrain[10*20+10] == "wall","pillars are wall")
	check(layout.rooms.size() == 1 and layout.rooms[0].doors == [Vector2i(9,4)],"one room, one door")
	check(layout.encounters.size() == 1 and layout.encounters[0].members.size() == 2,"one encounter with the given members")
	for m in layout.encounters[0].members:
		check(m.has("pos") and m.has("max_health") and m.has("display_name") and Rect2i(5,5,9,9).has_point(m.pos),"member placed inside the room")
		check(maxi(absi(m.pos.x-9),absi(m.pos.y-4)) >= 3,"member three cells from the door")
	check(layout.relic == Vector2i(-1,-1) and layout.entry == Vector2i(9,5) and layout.features.is_empty(),"no relic or features")
	var s = Session.new(5,true,false,true,1)
	Floor.apply(s,theme,layout)
	check(s.BOARD_SIDE == 20 and s.tiles.size() == 400 and s.phase == "BATTLE","apply consumes the arena")
	check(s.enemies.size() == 2 and s.enemies[0].role == "MELEE" and s.enemies[1].role == "RANGED","enemies configured with their roles")
	check(s.party[0].pos == Vector2i(9,5) and s.objective.is_empty(),"party at entry, no objective")
	check(s.floor_state.visible.has(s.party[0].pos),"observation ran")
	var same = Session.new(5,true,false,true,1); Floor.apply(same,theme,Arena.layout(spec,theme,1))
	check(same.enemies.map(func(e): return e.pos) == s.enemies.map(func(e): return e.pos),"arena placement deterministic for one seed")
	# Different seeds must move the roster: the seed is what the confidence interval samples over.
	var trio_spec: Dictionary = Arena.DEFAULT_SPEC.duplicate(true)
	trio_spec.members = [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"},{"species_id":"kobold","role":"MELEE"}]
	var seen: Dictionary = {}
	for seed_value in range(1,21):
		seen[str(Arena.layout(trio_spec,theme,seed_value).encounters[0].members.map(func(m): return m.pos))] = true
	check(seen.size() > 1,"different seeds place the roster differently")
	var spotted := false
	for _i in range(6):
		var _kind: String = Policy.step(s,"simple")
		if not s.combat_enemies().is_empty(): spotted = true; break
	check(spotted,"approach step brings the enemy into view")
	# The normal floor still builds through apply.
	var normal = Session.new(731,true,false,true,1); normal.depart()
	check(normal.BOARD_SIDE == 64 and not normal.objective.is_empty(),"build() still generates the real floor")

func rules_policy() -> void:
	var hob := [{"species_id":"dcss_hobgoblin","role":"MELEE"}]
	var cfg: Dictionary = config(hob,1,"rules",Session.DEFAULT_RULES); cfg.build = "b_strike"; cfg.supplies = [0,0,0,0,0,0]
	var one: Dictionary = Runner.run_one(cfg,11)
	check(one.result == "WIN" and one.skill_uses.get("HEAVY_STRIKE",0) >= 1,"rules policy uses the equipped strike (%s)" % [one.skill_uses])
	check(one == Runner.run_one(cfg,11),"rules policy deterministic")
	# cfg stays on b_strike: cfg2 below carries the dressing build, and run_many(cfg) averages strikes.
	var mixed := [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"},{"species_id":"kobold","role":"MELEE"}]
	var cfg2: Dictionary = config(mixed,1,"rules",Session.DEFAULT_RULES); cfg2.build = "b_dressing"; cfg2.supplies = [0,0,0,0,0,0]
	var two: Dictionary = Runner.run_one(cfg2,11)
	check(two.skill_uses.get("FIELD_DRESSING",0) >= 1,"dressing build heals at least once in a long fight (%s)" % [two.skill_uses])
	var many: Dictionary = Runner.run_many(cfg,range(1,11))
	check(many.skill_uses_mean.has("HEAVY_STRIKE") and many.skill_uses_mean.HEAVY_STRIKE >= 1.0,"run_many averages skill uses")
	for id in ["b_knife","b_lunge","b_bomb","b_shockwave","b_iron","melee_1"]:
		cfg.build = id
		check(Runner.run_one(cfg,3).result != "TIMEOUT","%s finishes a solo fight" % id)
