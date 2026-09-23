extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var s = Session.new(901,false,false,true,1)
	s.depart(); Fixture.arena(s,10); s.manual_mode = true
	var hero: Dictionary = s.party[0]
	for id in ["bolt","blast","blink","confuse","mend"]: check(s.learn_spell(0,id),"learn "+id)
	s.phase = "CAMP"
	check(s.prepare_spell(0,"bolt",true) and s.prepare_spell(0,"mend",true) and s.prepare_spell(0,"blink",true),"prepare three spells")
	check(not s.prepare_spell(0,"blast",true),"fourth spell refused")
	s.phase = "EXPLORE"
	var foe: Dictionary = s.enemies[0]
	foe.hp = 100; foe.max_hp = 100; foe.pos = hero.pos+Vector2i(2,0); foe.alert = true; foe.ready_at = 1000
	s.floor_state.observe(s)
	var before: int = foe.hp
	check(s.cast("bolt",foe.pos),"bolt cast")
	check(foe.hp < before or hero.mp == 15,"bolt damages or fails after spending 3 MP")
	hero.hp = 20; hero.mp = 18
	check(s.cast("mend",hero.pos),"mend cast")
	check(hero.hp > 20 or hero.mp == 12,"mend heals or fails after spending 6 MP")
	s.phase = "CAMP"
	s.grant_gear({"type":"bow"}); s.grant_gear({"type":"shield"})
	check(s.equip_gear(0,{"type":"bow"}),"equip bow at camp")
	check(not s.equip_gear(0,{"type":"shield"}),"two-handed bow rejects shield")
	check(s.unequip_gear(0,"weapon"),"unequip bow")
	check(s.equip_gear(0,{"type":"shield"}),"equip shield after bow removed")
	s.phase = "EXPLORE"
	check(not s.unequip_gear(0,"shield"),"gear change unavailable outside camp")
	print("Model B spells and gear: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
