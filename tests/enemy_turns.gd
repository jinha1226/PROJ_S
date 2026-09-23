extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func setup(role: String, offset: Vector2i) -> Dictionary:
	var s = Session.new_run(41)
	var center: Vector2i = Fixture.arena(s,12)
	var enemy: Dictionary = s.make_actor(900,"시험 적",true)
	MonsterAI.configure(enemy,role)
	enemy.hp = 100; enemy.max_hp = 100; enemy.pos = center+offset
	enemy.home = enemy.pos; enemy.alert = true; enemy.part_id = ""
	s.enemies = [enemy]; s.floor_state.observe(s)
	return {"s":s,"enemy":enemy,"center":center}

func run() -> void:
	var f: Dictionary = setup("MELEE",Vector2i(3,0))
	var s = f.s; var enemy: Dictionary = f.enemy
	s.plan_enemies()
	check(s.intents.is_empty(),"ordinary melee movement has no marked strike")
	var before: int = MonsterAI.distance(enemy.pos,f.center)
	s.enemy_attack_turn(enemy)
	check(MonsterAI.distance(enemy.pos,f.center) < before,"melee enemy closes the gap")
	f = setup("RANGED",Vector2i(4,0)); s = f.s; enemy = f.enemy
	var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp < hp and enemy.pos == f.center+Vector2i(4,0),"archer attacks from range")
	hp = s.party[0].hp; s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"archer reloads before the next shot")
	f = setup("CASTER",Vector2i(4,0)); s = f.s; enemy = f.enemy
	s.enemy_attack_turn(enemy)
	check(s.intents.is_empty(),"caster first lowers its cooldown")
	s.enemy_attack_turn(enemy)
	check(s.intents.is_empty(),"caster second action is still cooling down")
	s.enemy_attack_turn(enemy)
	check(enemy.charging and s.intents.any(func(i): return i.id == enemy.id),"caster telegraphs the target cell")
	hp = s.party[0].hp; s.party[0].pos = f.center+Vector2i(0,1); s.floor_state.observe(s)
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp and s.intents.is_empty(),"moving off the marked cell dodges the spell")
	f = setup("MELEE",Vector2i(1,0)); s = f.s; enemy = f.enemy
	enemy.hp = 0; hp = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"dead enemies never act")
	print("Enemy turns: %d failures" % failures)
	quit(1 if failures else 0)
