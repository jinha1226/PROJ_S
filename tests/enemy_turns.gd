extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
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
	# Casters no longer telegraph a spell (2026-09-28 unified utility): they
	# pick a basic attack, move or wait like everyone else.
	f = setup("CASTER",Vector2i(4,0)); s = f.s; enemy = f.enemy
	hp = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.intents.is_empty() and not bool(enemy.get("charging",false)),"caster marks no target cell")
	check(s.party[0].hp < hp,"caster strikes from its reach at once")
	check(enemy.pos == f.center+Vector2i(4,0),"caster in reach does not step closer")
	enemy.charging = true; enemy.cast_id = ""; enemy.resolve_at = s.time
	s.intents.append({"id":enemy.id,"cell":s.party[0].pos,"damage":14,"kind":"","resolve_at":s.time})
	s.enemy_attack_turn(enemy)
	check(not bool(enemy.charging) and not s.intents.any(func(i): return i.id == enemy.id),"a cast queued in an older save is discarded, not fired")
	f = setup("MELEE",Vector2i(1,0)); s = f.s; enemy = f.enemy
	enemy.hp = 0; hp = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"dead enemies never act")
	walls()
	unseen()
	dead_caster()
	print("Enemy turns: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## A wall between the two is a wall: the chase stops at it and lands nothing.
func walls() -> void:
	var f: Dictionary = setup("MELEE",Vector2i(3,0))
	var s = f.s; var enemy: Dictionary = f.enemy
	var wall_x: int = f.center.x+2
	for y in range(s.BOARD_SIDE): s.tile(Vector2i(wall_x,y)).terrain = "wall"
	s.floor_state.observe(s)
	var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"a wall between them blocks the attack")
	check(enemy.pos.x > wall_x,"the chase never crosses the wall")

## An enemy outside the hero's sight patrols without attacking or leaving its spawn.
func unseen() -> void:
	var f: Dictionary = setup("MELEE",Vector2i(6,0))
	var s = f.s; var enemy: Dictionary = f.enemy
	enemy.alert = false; enemy.pos = f.center+Vector2i(20,0); enemy.home = enemy.pos
	s.floor_state.observe(s)
	var was: Vector2i = enemy.pos; var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"an enemy that cannot see the party lands nothing")
	check(MonsterAI.distance(enemy.pos,was) == 1 and not enemy.alert,"unseen enemy patrols one cell without becoming alert")
	for i in range(12): s.enemy_attack_turn(enemy)
	check(MonsterAI.distance(enemy.pos,enemy.home) <= 3,"patrol remains near its encounter")
	enemy.pos = was; enemy.alert = false; enemy.ready_at = s.time
	s.phase = "EXPLORE"; s.floor_state.observe(s)
	check(s.act("WAIT",s.party[0].pos),"hero waits on an otherwise quiet floor")
	check(enemy.pos != was,"scheduled unseen enemy acts during exploration")

## A telegraph left in an older save dies with its caster: the marked cell goes with it.
func dead_caster() -> void:
	var f: Dictionary = setup("CASTER",Vector2i(4,0))
	var s = f.s; var enemy: Dictionary = f.enemy
	enemy.charging = true; enemy.cast_id = ""; enemy.resolve_at = s.time
	s.intents.append({"id":enemy.id,"cell":s.party[0].pos,"damage":14,"kind":"","resolve_at":s.time})
	check(enemy.charging and not s.intents.is_empty(),"the caster is charging")
	enemy.hp = 0
	var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"a dead caster cannot resolve its telegraph")
