extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/map_fixture.gd")
var failures := 0

func check(value: bool, reason: String) -> void:
	if not value: failures += 1; push_error(reason)

func _initialize() -> void:
	var s = Session.new(); s.depart()
	check(not s.use_supply(0) and s.supplies[0] == 2,"full HP potion must not be consumed")
	s.party[0].hp = 30
	check(s.use_supply(0) and s.party[0].hp == 50 and s.supplies[0] == 1,"shared healing potion")
	s.selected = 1; s.party[1].hp = 30
	check(s.use_supply(0) and s.supplies[0] == 0,"second character uses same stack")
	check(not s.use_supply(0),"empty stack cannot be used")
	Fixture.reach(s,Fixture.kind_id(s,"battle"))
	s.selected = 0
	var before: int = s.party[0].ap
	check(not s.use_supply(3,Vector2i(7,7)) and s.supplies[3] == 1 and s.party[0].ap == before,"invalid scroll target unchanged")
	s.party[0].pos = Vector2i(1,2)
	s.tile(Vector2i(1,3)).terrain = "wood"; s.tile(Vector2i(1,3)).wet = 0
	check(s.use_supply(3,Vector2i(1,3)) and s.supplies[3] == 0 and s.party[0].ap == before-1,"scroll applies fire and consumes one AP")
	# 엄호 covers an adjacent ally; the protector still halves what reaches it.
	s.party[1].pos = Vector2i(2,2)
	check(s.act("GUARD",s.party[1].pos),"guard activation")
	var hp: int = s.party[0].hp
	s.damage(s.party[0],10,100,"IMPACT")
	check(s.party[0].hp == hp-5,"guard reduces damage")
	s.end_round()
	check(not s.party[0].guarded,"guard expires")
	print("Mobile actions: %d failures" % failures)
	quit(1 if failures else 0)
