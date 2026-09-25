extends SceneTree
const Builder = preload("res://expedition/level/encounter_builder.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r
func row(id: String) -> Dictionary:
	return Builder.species(id)
func run() -> void:
	check(Builder.table().size() == 13,"thirteen species loaded")
	check(is_equal_approx(Builder.curve(row("kobold"),1),1.0) and is_equal_approx(Builder.curve(row("kobold"),4),1.0),"FLAT is one across range")
	check(is_equal_approx(Builder.curve(row("dcss_orc"),1),0.15) and is_equal_approx(Builder.curve(row("dcss_orc"),6),1.0),"RISE ramps 0.15 to 1")
	check(is_equal_approx(Builder.curve(row("dcss_rat"),1),1.0) and is_equal_approx(Builder.curve(row("dcss_rat"),3),0.15),"FALL ramps 1 to 0.15")
	check(is_equal_approx(Builder.curve(row("dcss_hobgoblin"),3),1.0) and is_equal_approx(Builder.curve(row("dcss_hobgoblin"),1),0.2),"PEAK is one at the middle, 0.2 at the ends")
	check(Builder.curve(row("dcss_rat"),4) == 0.0 and Builder.curve(row("dcss_river_rat"),1) == 0.0,"outside the range is zero")
	check(is_equal_approx(Builder.weight(row("dcss_orc"),1),150.0),"orc weight at depth one is 150")
	check(Builder.threat({"species_id":"goblin","role":"CASTER"}) == 4 and Builder.threat({"species_id":"kobold","role":"RANGED"}) == 3,"role bonus adds to threat")
	# Candidates respect depth and threat ceiling.
	var early: Array = Builder.candidates(1,3+1).map(func(r): return r.species_id)
	check("dcss_river_rat" not in early and "dcss_gnoll" not in early and "dcss_hobgoblin" in early,"early candidates exclude heavy species")
	# Fill: budget respected, guardrails hold, deterministic.
	var seen_backline := false; var seen_gnoll_band := false
	for seed_value in range(200):
		for budget in [3,5,6,9]:
			var members: Array = Builder.fill(rng(seed_value),1,budget,budget >= 9)
			check(members.size() >= 1 and members.size() <= 4,"one to four members (seed %d budget %d)" % [seed_value,budget])
			check(Builder.valid(members,budget) == "","fill output is valid: %s (seed %d budget %d)" % [Builder.valid(members,budget),seed_value,budget])
			var total := 0
			for m in members: total += m.threat
			check(total >= budget-1 and total <= budget+1,"threat within budget ±1 (%d for %d)" % [total,budget])
			if members.size() >= 3: seen_backline = true
			if members.any(func(m): return m.species_id == "dcss_gnoll"):
				seen_gnoll_band = true
				check(members.size() <= 4 and members.filter(func(m): return m.species_id in ["dcss_rat","dcss_frilled_lizard"]).size() >= 2,"gnoll brings two small followers")
			for m in members:
				check(m.has("display_name") and m.max_health > 0 and m.role in ["MELEE","RANGED","CASTER"],"member carries name, health and role")
			check(members == Builder.fill(rng(seed_value),1,budget,budget >= 9),"fill is deterministic per seed")
	# A threat budget alone does not bound the enemy action count.
	for seed_value in range(200):
		for budget in [3,5,6]:
			var capped: Array = Builder.fill(rng(seed_value),1,budget,true,2)
			check(capped.size() <= 2 and Builder.valid(capped,budget,2).is_empty(),"F1 count cap and threat budget both hold")
	var trio := [Builder.member(row("kobold"),"MELEE"),Builder.member(row("dcss_rat"),"MELEE"),Builder.member(row("goblin"),"RANGED")]
	check(Builder.valid(trio,6).is_empty() and Builder.valid(trio,6,2) == "too many","count cap rejects an otherwise legal budget-six trio")
	var band := [Builder.member(row("dcss_gnoll"),"MELEE"),Builder.member(row("dcss_rat"),"MELEE"),Builder.member(row("dcss_frilled_lizard"),"MELEE")]
	check(Builder.valid(band,7).is_empty(),"gnoll band is the deliberate all-melee exception")
	check(seen_backline and seen_gnoll_band,"large encounters and gnoll bands both occur")
	check(Builder.valid([{"species_id":"kobold","role":"MELEE","threat":2},{"species_id":"kobold","role":"MELEE","threat":2},{"species_id":"dcss_rat","role":"MELEE","threat":1}],5) != "","three melee without backline is rejected")
	check(Builder.valid([{"species_id":"goblin","role":"CASTER","threat":4},{"species_id":"goblin","role":"CASTER","threat":4}],9) != "","two casters rejected")
	check(Builder.valid([{"species_id":"dcss_rat","role":"MELEE","threat":1}],6) != "","far below budget rejected")
	# Depth 3 sees more orcs than depth 1 over the same seeds.
	var orcs := {1:0,3:0}
	for depth in [1,3]:
		for seed_value in range(300):
			for m in Builder.fill(rng(seed_value),depth,6,false):
				if m.species_id == "dcss_orc": orcs[depth] += 1
	check(orcs[3] > orcs[1]*2,"orcs become common by depth three (%s)" % [orcs])
	# Placement inside a 9x9 open room with one door on the north wall.
	var cells: Array = []
	for y in range(1,10):
		for x in range(1,10): cells.append(Vector2i(x,y))
	var door := Vector2i(5,0)
	var members: Array = [{"species_id":"dcss_hobgoblin","role":"MELEE","threat":3},{"species_id":"goblin","role":"RANGED","threat":3},{"species_id":"kobold","role":"MELEE","threat":2}]
	check(Builder.place(members,cells,[door],Vector2i(-1,-1),[],{},rng(1)),"placement succeeds in an open room")
	var positions: Array = members.map(func(m): return m.pos)
	check(positions.size() == 3 and positions[0] != positions[1] and positions[1] != positions[2] and positions[0] != positions[2],"members occupy distinct cells")
	for m in members: check(maxi(absi(m.pos.x-door.x),absi(m.pos.y-door.y)) >= 3,"every member at least three cells from the door")
	check(members[0].pos.y == 9,"leader anchors on the wall farthest from the door")
	var tiny: Array = []
	for y in range(1,3):
		for x in range(1,4): tiny.append(Vector2i(x,y))
	check(not Builder.place(members,tiny,[Vector2i(2,0)],Vector2i(-1,-1),[],{},rng(1)),"a 3x2 room cannot keep members three cells from the door")
	# Starvation: a one-row table whose guardrails saturate must still terminate.
	var original_table: Array = Builder.content.species
	Builder.content.species = [{"species_id":"goblin","display_name":"고블린","max_health":28,"min_depth":1,"max_depth":4,"rarity":1000,"curve":"FLAT","threat":2,"roles":["CASTER"],"band":null}]
	var starved: Array = Builder.fill(rng(1),1,9,false)
	Builder.content.species = original_table
	check(starved.size() >= 1 and starved.size() <= 4,"a saturated single-role table still returns a bounded group")
	check(Builder.table().size() == 13,"the species table is restored")
	print("Encounter builder: %d failures" % failures); quit(1 if failures else 0)
