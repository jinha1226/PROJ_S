extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s = Session.new(21,false,true,true,2); s.depart(); var c: Vector2i = Fixture.arena(s,8)
	Fixture.equip_basics(s)
	s.supplies = [2,1,1,1,1]
	check(not s.use_supply(0) and s.supplies[0] == 2,"full HP potion stays in bag")
	s.party[0].hp = 30
	check(s.use_supply(0) and s.party[0].hp == 50 and s.supplies[0] == 1,"healing potion")
	s.selected = 1; s.party[1].hp = 30
	check(s.use_supply(0) and s.supplies[0] == 0,"shared potion stack")
	check(not s.use_supply(0),"empty stack")
	s.selected = 0; s.party[0].ap = 2
	var before: int = s.party[0].ap
	check(not s.use_supply(3,c+Vector2i(7,7)) and s.supplies[3] == 1 and s.party[0].ap == before,"invalid scroll does not consume")
	s.tile(c+Vector2i.DOWN).terrain = "wood"
	check(s.use_supply(3,c+Vector2i.DOWN) and s.supplies[3] == 0,"scroll burns wood")
	var foe: Dictionary = s.enemies[0]
	foe.hp = 10; foe.pos = c+Vector2i.UP
	s.party[0].ap = 2; s.party[1].pos = c+Vector2i.RIGHT; s.floor_state.observe(s)
	check(s.act("GUARD",s.party[1].pos),"guard activation")
	var hp: int = s.party[0].hp
	s.damage(s.party[0],10,100,"IMPACT")
	check(s.party[0].hp == hp-5,"guard halves damage")
	s.end_round()
	check(not s.party[0].guarded,"guard expires")
	s.phase = "CAMP"; s.supplies[1] = 1; s.party[0].stress = 40
	check(s.use_supply(1) and s.party[0].stress == 15,"calming potion at camp")
	print("Mobile actions: %d failures" % failures); quit(1 if failures else 0)
