extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s = Session.new(11,true,true,true,3); s.depart(); Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 10; foe.pos = s.party[0].pos+Vector2i.RIGHT
	s.floor_state.observe(s)
	check(s.phase == "BATTLE" and not s.can_camp().is_empty(),"visible enemy enters battle phase and blocks camp")
	foe.hp = 0; s.floor_state.observe(s)
	check(s.can_camp() == "식량 3 필요","three food required")
	s.food = 3
	for e in s.enemies: e.hp = 0
	s.floor_state.observe(s)
	check(s.phase == "EXPLORE","cleared encounter returns to exploration")
	check(s.can_camp().is_empty(),"safe floor allows camp")
	for actor in s.party: actor.hp = 10; actor.stress = 80; actor.cooldowns = {"PUSH":2}
	check(s.camp() and s.food == 0 and s.phase == "CAMP","camp costs one food per survivor")
	check(s.party.all(func(a): return a.hp == 10+ceili(a.max_hp*0.5) and a.stress == 50 and a.cooldowns.PUSH == 0),"camp heals and clears cooldown")
	s.parts_bag["RAT_GNAW"] = 1
	check(s.equip_part(0,0,"RAT_GNAW") and s.unequip_part(0,0),"part changes at camp")
	check(s.end_camp() and s.phase == "EXPLORE" and s.equip_part(0,0,"RAT_GNAW"),"essences can be changed in a safe explored area")
	print("Camping: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
