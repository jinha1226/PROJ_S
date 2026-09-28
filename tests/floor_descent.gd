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
	check(Floor.theme_for(1).id == "F1_RUINS" and Floor.theme_for(2).id == "F1_RUINS" and Floor.theme_for(3).id == "F1_RUINS" and Floor.theme_for(4).id == "F2_MINES","three floors share a zone theme")
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
	check(s.descend() and s.depth == 2 and s.floor_state.layout.theme_id == "F1_RUINS","descent stays in the zone theme")
	check(s.food == 4 and s.party[1].hp == 12 and s.party[2].stress == 60,"state persists")
	for boss_floor in [3,6,9]:
		s.depth = boss_floor; s.phase = "EXPLORE"
		for e in s.enemies: e.hp = 0
		var next_stairs: Vector2i = s.floor_state.layout.stairs
		s.party[0].pos = next_stairs
		s.party[1].hp = 0; s.party[1].downed = true; s.party[1].bleedout_turns = 2
		s.party[2].stress = 65
		var before_food: int = s.food
		s.pending_stone_drops = [{"token":boss_floor,"stone":"RAT_GNAW/cut"}]
		check(not s.descend(),"pending boss drop blocks rest on floor %d" % boss_floor)
		s.pending_stone_drops.clear()
		check(s.descend() and s.phase == "REST" and s.depth == boss_floor,"boss floor %d enters rest before generating next floor" % boss_floor)
		check(s.party[1].hp == s.party[1].max_hp and not s.party[1].downed and s.party[2].stress == 35 and s.food == before_food,"rest restores without food or turns")
		check(s.leave_rest() and s.depth == boss_floor+1 and s.phase in ["EXPLORE","BATTLE"],"rest exits into next zone")
	print("Floor descent: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
