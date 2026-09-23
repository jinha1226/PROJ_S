extends SceneTree
## Public run flow: start, gather food, camp, descend, and end on death.
const Session = preload("res://expedition/session.gd")
const Curios = preload("res://expedition/curios.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var s = Session.new_run(731)
	check(s.depth == 1 and s.party.size() == 1 and s.food == 2,"solo starts at floor one with food")
	var first_layout: Dictionary = s.floor_state.layout
	check(first_layout.size == 80 and first_layout.stairs.x >= 0,"first floor has stairs")
	for enemy in s.enemies: enemy.hp = 0
	var caches: Array = s.floor_state.features.keys().filter(func(p): return s.floor_state.features[p].get("curio_id","") == "SUPPLY_CACHE")
	check(not caches.is_empty(),"a food cache is generated")
	if not caches.is_empty():
		var cache: Vector2i = caches[0]
		s.party[0].pos = cache+Vector2i.LEFT; s.floor_state.observe(s)
		var food_before: int = s.food
		check(Curios.resolve(s,cache,"SEARCH") and s.food >= food_before+2,"searching adds food")
		check(not Curios.resolve(s,cache,"SEARCH"),"the cache cannot pay twice")
	s.party[0].hp = 20; s.party[0].stress = 55
	var food_before_camp: int = s.food
	check(s.camp() and s.food == food_before_camp-1,"camp spends one food")
	check(s.party[0].hp > 20 and s.party[0].stress == 25,"camp recovers HP and stress")
	check(s.end_camp(),"camp ends")
	s.party[0].pos = first_layout.stairs; s.floor_state.observe(s)
	check(s.descend() and s.depth == 2,"stairs descend once")
	check(s.food == food_before_camp-1 and s.party[0].stress == 25,"resources and condition persist")
	check(s.floor_state.layout.theme_id == "F2_MINES" and s.floor_state.layout.stairs.x >= 0,"next floor is a new mine layout")
	s.damage(s.party[0],1000,100,"IMPACT")
	s.check_battle_end()
	check(s.phase == "DEFEAT" and not s.descend(),"hero death ends the run")
	print("Descent playthrough: %d failures" % failures)
	quit(1 if failures else 0)
