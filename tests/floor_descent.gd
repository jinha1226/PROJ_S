extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	# Deep floors: the scaled budget stays within what the catalog can fill, so every depth generates.
	for depth in range(7,13):
		var deep: Dictionary = Floor.theme_for(depth)
		var cap: int = Floor.strongest_pack(6,int(deep.monsters.max_members))*4/5
		check(deep.monsters.budget.values().all(func(b): return int(b) <= cap),"depth %d budgets capped at 80%% of the strongest legal pack" % depth)
		for seed in range(3):
			var layout: Dictionary = Generator.generate(deep,seed,depth)
			check(Generator.validate(layout,deep).is_empty() and int(layout.stats.regenerations) < Generator.MAX_REGENERATIONS,"depth %d seed %d generates a valid floor" % [depth,seed])
	check(Floor.theme_for(1).id == "F1_RUINS" and Floor.theme_for(2).id == "F2_MINES" and Floor.theme_for(3).id == "F1_RUINS","alternating themes")
	for id in ["F1_RUINS","F2_MINES"]:
		var theme: Dictionary = Generator.theme(id)
		check(theme.size == 80 and theme.corridor.width == 2 and theme.rooms.count == [13,16],"larger %s layout" % id)
		for seed in range(20):
			var layout: Dictionary = Generator.generate(theme,seed,int(theme.depth))
			check(Generator.validate(layout,theme).is_empty(),"%s seed %d valid" % [id,seed])
			check(layout.npc_rooms.size() >= 3 and layout.npc_rooms.size() <= 5,"NPC rooms reserved")
	var s = Session.new(21,true,true,true,3); s.depart()
	check(not s.descend(),"stairs require adjacency")
	var stairs: Vector2i = s.floor_state.layout.stairs
	for e in s.enemies: e.hp = 0
	s.party[0].pos = stairs; s.party[1].pos = stairs+Vector2i.RIGHT; s.party[2].pos = stairs+Vector2i.DOWN
	s.floor_state.observe(s)
	s.food = 4; s.party[1].hp = 12; s.party[2].stress = 60
	check(s.descend() and s.depth == 2 and s.floor_state.layout.theme_id == "F2_MINES","descent builds next theme")
	check(s.food == 4 and s.party[1].hp == 12 and s.party[2].stress == 60,"state persists")
	print("Floor descent: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
