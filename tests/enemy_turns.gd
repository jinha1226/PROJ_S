extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
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
	f = setup("CASTER",Vector2i(4,0)); s = f.s; enemy = f.enemy
	s.enemy_attack_turn(enemy)
	check(s.intents.is_empty(),"caster first lowers its cooldown")
	s.enemy_attack_turn(enemy)
	check(s.intents.is_empty(),"caster second action is still cooling down")
	s.enemy_attack_turn(enemy)
	check(enemy.charging and s.intents.any(func(i): return i.id == enemy.id),"caster telegraphs the target cell")
	hp = s.party[0].hp; s.party[0].pos = f.center+Vector2i(0,1); s.floor_state.observe(s)
	s.time = int(enemy.resolve_at)
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp and s.intents.is_empty(),"moving off the marked cell dodges the spell")
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

## An enemy that has not been roused stays where it was put.
func unseen() -> void:
	var f: Dictionary = setup("MELEE",Vector2i(6,0))
	var s = f.s; var enemy: Dictionary = f.enemy
	enemy.alert = false; enemy.pos = f.center+Vector2i(20,0); enemy.home = enemy.pos
	s.floor_state.observe(s)
	var was: Vector2i = enemy.pos; var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"an enemy that cannot see the party lands nothing")
	check(MonsterAI.distance(enemy.pos,was) <= 1,"it holds its ground instead of charging across the floor")

## A telegraphed spell dies with its caster: the marked cell goes with it.
func dead_caster() -> void:
	var f: Dictionary = setup("CASTER",Vector2i(4,0))
	var s = f.s; var enemy: Dictionary = f.enemy
	for i in range(3): s.enemy_attack_turn(enemy)
	check(enemy.charging and not s.intents.is_empty(),"the caster is charging")
	enemy.hp = 0
	var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"a dead caster cannot resolve its telegraph")
