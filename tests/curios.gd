extends SceneTree
## Curios after the tool table: four kinds, food-first outcomes, the three
## refusal reasons, and the beast meat a kill drops (스펙 §2.1).
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Curios = preload("res://expedition/curios.gd")
const Generator = preload("res://expedition/floor_generator.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

## A lone hero on an open floor with one curio within reach and one action left.
func setup(seed: int, id: String, offset: Vector2i = Vector2i.RIGHT) -> Dictionary:
	var s = Session.new(seed,false,false,true,1); s.depart(); Fixture.arena(s,8)
	for enemy in s.enemies: enemy.hp = 0
	var p: Vector2i = s.party[0].pos+offset
	s.floor_state.features[p] = {"kind":"curio","curio_id":id,"label":Curios.content.curios[id].name,"used":false}
	s.floor_state.observe(s); s.party[0].ap = 1
	return {"s":s,"p":p}

func run() -> void:
	kinds()
	supply_cache()
	mushrooms()
	dead_adventurer()
	broken_chest()
	rules()
	beast_drop()
	generator_counts()
	print("Curios: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func kinds() -> void:
	check(Curios.content.curios.keys() == ["SUPPLY_CACHE","MUSHROOMS","DEAD_ADVENTURER","BROKEN_CHEST"],"four kinds, no tool curios")
	check(not Curios.content.has("tools"),"tool table removed")
	for id in Curios.content.curios:
		check(Curios.content.curios[id].options.keys() == ["SEARCH"],"%s offers only SEARCH" % id)

func supply_cache() -> void:
	var f := setup(5,"SUPPLY_CACHE"); var s = f.s; var p: Vector2i = f.p; var before: int = s.food
	check(Curios.error(s,p,"SEARCH").is_empty(),"a reachable cache on a quiet floor has no refusal")
	check(Curios.resolve(s,p,"SEARCH"),"cache searched")
	check(s.food-before in [2,3] and s.floor_state.features[p].used,"cache yields 2-3 food once")
	check(Curios.error(s,p,"SEARCH") == "조사 완료","a spent cache refuses")
	check(not Curios.resolve(s,p,"SEARCH") and s.food-before in [2,3],"a spent cache cannot pay twice")

## 1..2 food every time, poison on roughly a third of the seeds.
func mushrooms() -> void:
	var poisoned := 0; var fed := 0
	for seed in range(40):
		var f := setup(seed,"MUSHROOMS"); var s = f.s; var p: Vector2i = f.p
		var hp: int = s.party[0].hp; var before: int = s.food
		check(Curios.resolve(s,p,"SEARCH") and s.food-before in [1,2],"mushrooms feed (seed %d)" % seed)
		if s.party[0].hp < hp: poisoned += 1
		if s.food > before: fed += 1
	check(fed == 40,"mushrooms always feed")
	check(poisoned >= 4 and poisoned <= 20,"poison on roughly a third of seeds (%d/40)" % poisoned)

## Food 1 always, and sometimes a part or a supply on top.
func dead_adventurer() -> void:
	var parts := 0; var supplies := 0
	for seed in range(40):
		var f := setup(100+seed,"DEAD_ADVENTURER"); var s = f.s; var p: Vector2i = f.p
		var bag: int = s.parts_bag.values().reduce(func(a,b): return a+b,0)
		var items: int = s.supplies.reduce(func(a,b): return a+b,0)
		check(Curios.resolve(s,p,"SEARCH") and s.food == 3,"adventurer gives one food (seed %d)" % seed)
		if s.parts_bag.values().reduce(func(a,b): return a+b,0) > bag: parts += 1
		if s.supplies.reduce(func(a,b): return a+b,0) > items: supplies += 1
	check(parts >= 4 and parts <= 20,"parts on some seeds (%d/40)" % parts)
	check(supplies >= 4 and supplies <= 20,"supplies on some seeds (%d/40)" % supplies)

## A part or a supply, never nothing and never two.
func broken_chest() -> void:
	for seed in range(10):
		var f := setup(200+seed,"BROKEN_CHEST"); var s = f.s; var p: Vector2i = f.p
		var before: int = s.parts_bag.values().reduce(func(a,b): return a+b,0)+s.supplies.reduce(func(a,b): return a+b,0)
		check(Curios.resolve(s,p,"SEARCH"),"chest searched (seed %d)" % seed)
		check(s.parts_bag.values().reduce(func(a,b): return a+b,0)+s.supplies.reduce(func(a,b): return a+b,0) == before+1,"chest gives exactly one item (seed %d)" % seed)

## The three refusals the plan names: out of reach, a foe in sight, no action.
func rules() -> void:
	var far := setup(9,"SUPPLY_CACHE",Vector2i(3,0)); var s = far.s; var p: Vector2i = far.p
	check(s.floor_state.visible.has(p),"the distant curio is still in sight")
	check(Curios.error(s,p,"SEARCH") == "거리 초과","out of reach")
	check(not Curios.resolve(s,p,"SEARCH") and not s.floor_state.features[p].used,"an out-of-reach curio is untouched")
	var near := setup(9,"SUPPLY_CACHE"); s = near.s; p = near.p
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.pos = s.party[0].pos+Vector2i(0,2); s.floor_state.observe(s)
	check(not s.party_enemies().is_empty() and s.on_floor(),"the foe is one the party itself sees")
	# A seen foe turns the floor into a battle, and the phase guard answers first.
	check(Curios.error(s,p,"SEARCH") == "조사 불가","searching is out of the question mid-battle")
	s.phase = "EXPLORE"
	check(Curios.error(s,p,"SEARCH") == "주변에 적 있음","a foe in sight blocks the search")
	var spent := setup(9,"SUPPLY_CACHE"); s = spent.s; p = spent.p
	s.party[0].ap = 0
	check(Curios.error(s,p,"SEARCH") == "행동 불가","no action left, no search")

## A rat's carcass feeds the party a quarter of the time (스펙 §2.1).
func beast_drop() -> void:
	var fed := 0
	for seed in range(40):
		var s = Session.new(300+seed,false,false,true,1); s.depart(); Fixture.arena(s,8)
		var foe: Dictionary = s.enemies[0]
		foe.hp = 1; foe.species_id = "dcss_rat"; foe.pos = s.party[0].pos+Vector2i(1,0)
		s.floor_state.observe(s)
		var before: int = s.food
		s.damage(foe,5,0,"SLASH")
		check(foe.hp <= 0,"the rat dies (seed %d)" % seed)
		if s.food > before: fed += 1
		check(s.food-before in [0,1],"a kill feeds at most one food (seed %d)" % seed)
	check(fed >= 3 and fed <= 20,"a rat drops meat on about a quarter of kills (%d/40)" % fed)
	var quiet := 0
	for seed in range(20):
		var s = Session.new(400+seed,false,false,true,1); s.depart(); Fixture.arena(s,8)
		var foe: Dictionary = s.enemies[0]
		foe.hp = 1; foe.species_id = "dcss_kobold"; foe.pos = s.party[0].pos+Vector2i(1,0)
		s.floor_state.observe(s)
		var before: int = s.food
		s.damage(foe,5,0,"SLASH")
		if s.food == before: quiet += 1
	check(quiet == 20,"a non-beast kill never drops food")

## Every seed of the first theme places the four kinds within its own counts.
func generator_counts() -> void:
	var theme: Dictionary = Generator.theme("F1_RUINS")
	for seed in range(20):
		var layout: Dictionary = Generator.generate(theme,seed,1)
		var counts := {}
		for p in layout.features:
			var feature: Dictionary = layout.features[p]
			if feature.kind == "curio": counts[feature.curio_id] = int(counts.get(feature.curio_id,0))+1
		for id in theme.curios:
			var n: int = int(counts.get(id.to_upper(),0))
			check(n >= theme.curios[id][0] and n <= theme.curios[id][1],"%s count %d within %s (seed %d)" % [id,n,theme.curios[id],seed])
