extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Curios = preload("res://expedition/curios.gd")
const Generator = preload("res://expedition/floor_generator.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func setup(seed: int, id: String):
	var s = Session.new(seed,false,false,true,1); s.depart(); Fixture.arena(s,8)
	for enemy in s.enemies: enemy.hp = 0
	var p: Vector2i = s.party[0].pos+Vector2i.RIGHT
	s.floor_state.features[p] = {"kind":"curio","curio_id":id,"label":Curios.content.curios[id].name,"used":false}
	s.floor_state.observe(s); s.party[0].ap = 1
	return {"s":s,"p":p}
func run() -> void:
	check(Curios.content.curios.keys() == ["SUPPLY_CACHE","MUSHROOMS","DEAD_ADVENTURER","BROKEN_CHEST"],"four kinds")
	var f = setup(5,"SUPPLY_CACHE"); var s = f.s; var p: Vector2i = f.p; var before: int = s.food
	check(Curios.resolve(s,p,"SEARCH"),"cache")
	check(s.food-before in [2,3] and s.floor_state.features[p].used,"cache yields food once")
	check(Curios.error(s,p,"SEARCH") == "조사 완료","spent")
	var poisoned := 0; var parts := 0; var supplies := 0
	for seed in range(30):
		f = setup(seed,"MUSHROOMS"); s = f.s; p = f.p; before = s.food; var hp: int = s.party[0].hp
		check(Curios.resolve(s,p,"SEARCH") and s.food-before in [1,2],"mushrooms feed")
		if s.party[0].hp < hp: poisoned += 1
		f = setup(seed,"DEAD_ADVENTURER"); s = f.s; p = f.p; var bag: int = s.parts_bag.values().reduce(func(a,b): return a+b,0); var items: int = s.supplies.reduce(func(a,b): return a+b,0)
		check(Curios.resolve(s,p,"SEARCH") and s.food == 3,"adventurer food")
		if s.parts_bag.values().reduce(func(a,b): return a+b,0) > bag: parts += 1
		if s.supplies.reduce(func(a,b): return a+b,0) > items: supplies += 1
	check(poisoned > 0 and poisoned < 20 and parts > 0 and supplies > 0,"outcomes vary")
	for seed in range(10):
		f = setup(seed,"BROKEN_CHEST"); s = f.s; p = f.p
		before = s.parts_bag.values().reduce(func(a,b): return a+b,0)+s.supplies.reduce(func(a,b): return a+b,0)
		check(Curios.resolve(s,p,"SEARCH"),"chest")
		check(s.parts_bag.values().reduce(func(a,b): return a+b,0)+s.supplies.reduce(func(a,b): return a+b,0) == before+1,"one item")
	var theme: Dictionary = Generator.theme("F1_RUINS")
	for seed in range(5):
		var layout: Dictionary = Generator.generate(theme,seed,1)
		for id in theme.curios:
			var n: int = layout.features.values().filter(func(row): return row.get("curio_id","") == id.to_upper()).size()
			check(n >= theme.curios[id][0] and n <= theme.curios[id][1],"%s count" % id)
	print("Curios: %d failures" % failures); quit(1 if failures else 0)
