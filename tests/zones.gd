extends SceneTree
## Four zones of three floors: which theme a floor wears, which element it
## leans to, where its boss lives, and the twelfth floor that ends the run.
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Zones = preload("res://expedition/level/zones.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	table()
	elements()
	themes()
	zoned_species()
	floors()
	victory()
	await victory_card()
	print("Zones: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func table() -> void:
	var zones: Array = range(1,13).map(func(d): return Zones.zone_of(d))
	check(zones == [1,1,1,2,2,2,3,3,3,4,4,4],"three floors a zone (%s)" % [zones])
	check(Zones.zone_of(0) == 1 and Zones.zone_of(15) == 4,"out-of-range floors clamp to the first and last zone")
	check(Zones.theme_id(1) == "F1_RUINS" and Zones.theme_id(5) == "F2_MINES" and Zones.theme_id(8) == "F3_TEMPLE" and Zones.theme_id(12) == "F4_CRYPT","each zone wears its own theme")
	check(range(1,13).filter(func(d): return Zones.is_boss_floor(d)) == [3,6,9,12],"a boss on every third floor")
	check(Zones.FINAL_DEPTH == 12 and Zones.FLOORS_PER_ZONE == 3,"twelve floors, three a zone")
	check(Zones.first_floor(3) == 7 and Zones.last_floor(3) == 9,"zone three spans floors seven to nine")
	check([1,2,3,4].map(func(z): return Zones.boss_template(z)) == ["throne_room","foundry","binding_altar","crypt_heart"],"each zone has its boss room")
	check(Zones.zone_name(2) == "불타는 폐광" and Zones.zone_name(4) == "망자의 묘역","zones are named")

func elements() -> void:
	check(Zones.elements(1) == ["poison"] and Zones.elements(2) == ["fire","air"] and Zones.elements(3) == ["ice","poison"] and Zones.elements(4) == ["will"],"each zone lists its elements")
	var s = Session.new(731)
	check(Zones.floor_element(s,1) == "" and Zones.floor_element(s,2) == "","the first two floors lean to nothing")
	check(Zones.floor_element(s,3) == "poison","the third floor leans to poison")
	var seen: Dictionary = {}
	for seed_value in range(40):
		var t = Session.new(seed_value)
		for depth in range(3,13):
			var element: String = Zones.floor_element(t,depth)
			check(element in Zones.elements(Zones.zone_of(depth)),"floor %d leans to its zone's element (seed %d)" % [depth,seed_value])
			check(element == Zones.floor_element(t,depth),"the element is deterministic")
			if depth in [4,5,6]: seen[element] = true
	check(seen.has("fire") and seen.has("air"),"both of the mines' elements turn up (%s)" % [seen.keys()])
func themes() -> void:
	for depth in range(1,13):
		var theme: Dictionary = Floor.theme_for(depth)
		check(theme.id == Zones.theme_id(depth) and int(theme.zone) == Zones.zone_of(depth),"floor %d wears its zone's theme" % depth)
		check(not theme.has("deep"),"floor %d carries no deep scaling" % depth)
		check(bool(theme.boss) == Zones.is_boss_floor(depth),"floor %d is a boss floor exactly on the third" % depth)
		if theme.boss:
			check(str(theme.boss_template) == Zones.boss_template(Zones.zone_of(depth)) and theme.boss_template in theme.templates.required,"floor %d requires its zone's boss room" % depth)
			check("descent" not in theme.templates.required,"a boss room brings its own stairs on floor %d" % depth)
		for seed_value in range(2):
			var layout: Dictionary = Generator.generate(theme,seed_value,depth)
			check(Generator.validate(layout,theme).is_empty(),"floor %d seed %d generates a valid layout" % [depth,seed_value])
	for id in ["F3_TEMPLE","F4_CRYPT"]:
		var theme: Dictionary = Generator.theme(id)
		check(theme.size == 80 and theme.rooms.count == [13,16] and theme.corridor.width == 2,"%s keeps the floor shape" % id)
	check(Floor.theme_for(1).templates.fight_pool.has("guard_post") and Floor.theme_for(4).templates.fight_pool.has("smelter"),"zones fight in their own rooms")
	check(Floor.theme_for(7).templates.fight_pool.has("flooded_hall") and Floor.theme_for(10).templates.fight_pool.has("grave_garden"),"the deeper zones too")
	var s = Session.new_run(731)
	s.depth = 11
	var member := {"species_id":"dcss_orc","display_name":"오크","max_health":70,"pos":Vector2i(1,1),"role":"MELEE"}
	var deep: Dictionary = Floor.mint_enemy(s,member,"T11","early",false)
	check(int(deep.attack_percent) == int(Bestiary.monster_stats("dcss_orc",11).attack_percent),"depth uses the zone-floor monster formula")
	check(not FileAccess.get_file_as_string("res://expedition/level/continuous_floor.gd").contains("deep_scale"),"the deep scaling is gone")

func zoned_species() -> void:
	var row := {"species_id":"test","rarity":100,"zone":3,"min_depth":1,"max_depth":1,"curve":"FLAT"}
	check(Encounters.weight(row,8) == 100.0 and Encounters.weight(row,6) == 0.0 and Encounters.weight(row,10) == 0.0,"a zoned species lives only in its zone")
	var legacy := {"species_id":"test_legacy","rarity":100,"min_depth":1,"max_depth":6,"curve":"FLAT"}
	check(Encounters.weight(legacy,11) == Encounters.weight(legacy,6),"an unzoned legacy species reads the last catalog floor")

func floors() -> void:
	for seed_value in range(1,6):
		for depth in [1,2,3,5,8,11]:
			var s = Session.new_run(seed_value)
			s.depth = depth; s.floor_state.build(s)
			var element: String = str(s.floor_state.element)
			check(element == Zones.floor_element(s,depth),"floor %d leans to the zone's pick (seed %d)" % [depth,seed_value])
			var variants: Array = s.enemies.filter(func(e): return not str(e.get("variant_element","")).is_empty())
			if depth <= 2: check(variants.is_empty(),"floor %d has base species only (seed %d)" % [depth,seed_value])
			var outside: Array = variants.filter(func(e): return e.variant_element not in Zones.elements(Zones.zone_of(depth)))
			check(outside.size()*2 <= variants.size(),"most variants on floor %d wear the zone's elements (seed %d)" % [depth,seed_value])

func victory() -> void:
	var s = Session.new_run(731)
	s.depth = 12; s.floor_state.build(s); s.NpcRoster.place(s)
	var boss: Dictionary = s.npcs.filter(func(n): return n.get("fallen",false))[0]
	for e in s.enemies: if not e.get("boss",false): e.hp = 0
	var score: int = s.score
	s.damage(boss,99999,int(s.party[0].id),"physical")
	if boss.hp > 0: s.damage(boss,99999,int(s.party[0].id),"physical")
	check(boss.hp <= 0 and s.phase == "VICTORY","the twelfth floor's boss ends the run in victory")
	check(s.score >= score+500,"victory is worth five hundred")
	var after: int = s.score
	s.victory()
	check(s.phase == "VICTORY" and s.score == after,"victory counts once")
	check(s.log_lines.any(func(l): return l.contains("원정 성공")),"victory is logged")
	check(not s.on_floor(),"the run is off the floor once it is won")
	var t = Session.new_run(731)
	t.depth = 12; t.floor_state.build(t)
	for e in t.enemies: e.hp = 0
	t.phase = "EXPLORE"
	var stairs: Vector2i = t.floor_state.layout.stairs
	t.party[0].pos = stairs+Vector2i.RIGHT if t.is_free(stairs+Vector2i.RIGHT) else stairs+Vector2i.LEFT
	t.floor_state.observe(t)
	check(not t.descend() and t.depth == 12,"there is no thirteenth floor")
	var u = Session.new_run(731)
	u.depth = 9; u.floor_state.build(u)
	var ninth: Dictionary = u.enemies.filter(func(e): return e.get("boss",false))[0]
	u.damage(ninth,99999,int(u.party[0].id),"physical")
	check(u.phase != "VICTORY","a zone boss before the last is no victory")

func victory_card() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	s.depth = 12; s.victory()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene)
	for frame in range(3): await process_frame
	scene.refresh()
	for frame in range(2): await process_frame
	var card: Node = scene.find_child("ResultCard",true,false)
	check(card != null,"victory shows the result card")
	check(card != null and card.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("승리")),"the card says 승리")
	scene.queue_free()
