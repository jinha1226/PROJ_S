extends SceneTree
## Zone hazards: lava that never cools, deep water and bog that never dry, gas
## that goes up in fire, ceilings that fall a round after they shake, and fog.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Hazards = preload("res://expedition/level/hazards.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Templates = preload("res://expedition/level/floor_templates.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	terrains(); gas(); collapse(); fog(); placement()
	print("Hazards: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## An open arena with the hero in the middle and every monster gone.
func arena() -> Dictionary:
	var s = Session.new_run(731)
	var c: Vector2i = Fixture.arena(s,8)
	for n in s.npcs: n.hp = 0
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0]}

func terrains() -> void:
	check(Hazards.initial("lava") == {"fire":100,"wet":0} and Hazards.initial("bog") == {"fire":0,"wet":100},"hazard terrains start hot or soaked")
	check(Hazards.initial("water").wet == 70 and Hazards.initial("stone") == {"fire":0,"wet":0},"old terrains start as before")
	var d := arena(); var s = d.s
	var lava: Vector2i = d.c+Vector2i(1,0)
	s.tile(lava).terrain = "lava"; s.tile(lava).fire = 30
	d.hero.pos = lava
	var hp: int = d.hero.hp
	Scheduler.environment_tick(s)
	check(int(s.tile(lava).fire) >= 95,"lava is back at full heat after a tick")
	check(int(d.hero.hp) < hp,"standing in lava burns")
	var deep: Vector2i = d.c+Vector2i(-2,0)
	s.tile(deep).terrain = "deep_water"; s.tile(deep).wet = 0
	d.hero.pos = d.c
	Scheduler.environment_tick(s)
	check(int(s.tile(deep).wet) >= 98,"deep water never dries")
	s.tile(deep).wet = 0
	check(s.conductive(deep),"deep water always carries a charge")
	check(Rules.move_time(s,d.hero,deep) == 150,"wading deep water is slow")
	var bog: Vector2i = d.c+Vector2i(0,2)
	s.tile(bog).terrain = "bog"
	d.hero.pos = bog; d.hero.statuses.erase("poison")
	Scheduler.environment_tick(s)
	check(d.hero.statuses.has("poison"),"standing in bog poisons")
	check(int(s.tile(bog).wet) >= 98,"bog never dries")
	check(Rules.move_time(s,d.hero,bog) == 120,"bog drags the feet")

func gas() -> void:
	var d := arena(); var s = d.s
	var pocket: Vector2i = d.c+Vector2i(2,0)
	s.tile(pocket).gas = true
	Scheduler.environment_tick(s)
	check(bool(s.tile(pocket).get("gas",false)),"a cold gas pocket waits")
	var hp: int = d.hero.hp
	s.tile(pocket).fire = 10
	Scheduler.environment_tick(s)
	check(not s.tile(pocket).has("gas"),"fire sets the pocket off")
	check(hp-int(d.hero.hp) >= Hazards.GAS_DAMAGE,"the blast reaches two cells")
	check(int(s.tile(d.c+Vector2i(3,0)).fire) >= Hazards.GAS_FIRE-10,"the blast sets the ground alight")
	check(s.log_lines.any(func(l): return l.contains("가스 폭발")),"the blast is logged")
	var far := arena(); var t = far.s
	var away: Vector2i = far.c+Vector2i(5,0)
	t.tile(away).gas = true; t.tile(away).fire = 10
	var whole: int = far.hero.hp
	Scheduler.environment_tick(t)
	check(int(far.hero.hp) == whole,"a blast five cells off does not reach")

func collapse() -> void:
	var d := arena(); var s = d.s
	var roof: Vector2i = d.c+Vector2i(2,2)
	s.tile(roof).collapse = {"armed":false,"at":0}
	Scheduler.environment_tick(s)
	check(bool(s.tile(roof).collapse.armed) and int(s.tile(roof).collapse.at) == int(s.time)+100,"the ceiling shakes when the party comes near")
	check(s.log_lines.any(func(l): return l.contains("천장이 흔들린다")),"the shaking is logged")
	var ally_free_hp: int = d.hero.hp
	s.time += 100
	Scheduler.environment_tick(s)
	check(s.tile(roof).terrain == "wall" and not s.tile(roof).has("collapse"),"an empty cell fills with stone")
	check(int(d.hero.hp) == ally_free_hp,"nobody under it, nobody hurt")
	var under := arena(); var u = under.s
	var spot: Vector2i = under.c+Vector2i(1,1)
	u.tile(spot).collapse = {"armed":true,"at":int(u.time)}
	under.hero.pos = spot
	var hp: int = under.hero.hp
	Scheduler.environment_tick(u)
	check(hp-int(under.hero.hp) >= Hazards.COLLAPSE_DAMAGE and u.tile(spot).terrain == "rubble","whoever stands under it is hit and the cell becomes rubble")
	var distant := arena(); var v = distant.s
	var high: Vector2i = distant.c+Vector2i(5,5)
	v.tile(high).collapse = {"armed":false,"at":0}
	Scheduler.environment_tick(v)
	check(not bool(v.tile(high).collapse.armed),"a ceiling far off stays still")

func fog() -> void:
	var d := arena(); var s = d.s
	var seen: Vector2i = d.c+Vector2i(5,0)
	s.floor_state.observe(s)
	check(s.floor_state.visible.has(seen),"five cells off is in sight on clear ground")
	s.tile(d.c).fog = true
	s.floor_state.observe(s)
	check(not s.floor_state.visible.has(seen),"fog cuts the sight radius")
	check(s.floor_state.visible.has(d.c+Vector2i(1,0)),"the next cell is still in sight")
	check(is_equal_approx(Hazards.sight_radius(s,d.hero,6.0),3.0),"three less in fog")
	s.tile(d.c).erase("fog")
	check(is_equal_approx(Hazards.sight_radius(s,d.hero,6.0),6.0),"clear ground keeps the radius")

func placement() -> void:
	check(Templates.parse(Templates.definition("smelter").rows).hazards.size() == 2,"template glyphs carry their hazards")
	var expected := {1:"collapse",4:"gas",10:"fog"}
	for depth in expected:
		var theme: Dictionary = Floor.theme_for(depth)
		for seed_value in range(3):
			var layout: Dictionary = Generator.generate(theme,seed_value,depth)
			var flag: String = expected[depth]
			var cells: Array = layout.hazards.keys().filter(func(p): return layout.hazards[p].has(flag))
			check(not cells.is_empty(),"floor %d places %s (seed %d)" % [depth,flag,seed_value])
			check(cells.all(func(p): return layout.terrain[p.y*layout.size+p.x] != "wall"),"hazards sit on open ground (floor %d)" % depth)
			if flag == "collapse":
				for p in cells:
					var open := true
					for dy in [-1,0,1]:
						for dx in [-1,0,1]:
							if layout.terrain[(p.y+dy)*layout.size+p.x+dx] == "wall": open = false
					check(open,"a ceiling falls only where it cannot cut a room (%s)" % p)
			for p in layout.features:
				check(layout.terrain[p.y*layout.size+p.x] not in Hazards.TERRAINS,"no curio or item on hazard ground (floor %d)" % depth)
	check(range(5).any(func(sd): return Generator.generate(Floor.theme_for(5),sd,5).terrain.has("lava")),"the mines carry lava")
	check(range(5).any(func(sd): return Generator.generate(Floor.theme_for(8),sd,8).terrain.any(func(x): return x in ["deep_water","bog"])),"the temple carries deep water or bog")
	var s = Session.new_run(4)
	s.depth = 4; s.floor_state.build(s)
	var gassy: int = 0
	for cell in s.tiles: if bool(cell.get("gas",false)): gassy += 1
	check(gassy == s.floor_state.layout.hazards.values().filter(func(h): return h.has("gas")).size(),"the floor copies its gas onto the tiles")
	check(s.tiles.all(func(c): return c.terrain != "lava" or int(c.fire) == 100),"lava tiles start at full heat")
	for depth in [5,8]:
		var t = Session.new_run(9)
		t.depth = depth; t.floor_state.build(t); t.NpcRoster.place(t)
		check(t.npcs.filter(func(n): return n.hp > 0).all(func(n): return t.tile(n.pos).terrain not in Hazards.TERRAINS),"no NPC stands on hazard ground (floor %d)" % depth)
