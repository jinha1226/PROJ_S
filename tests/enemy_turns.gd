extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/map_fixture.gd")
var failures := 0

func check(value: bool, reason: String) -> void:
	if not value: failures += 1; push_error(reason)

func setup():
	var s = Session.new(); s.depart(); Fixture.reach(s,8)
	for cell in s.tiles: cell.terrain = "stone"; cell.fire = 0; cell.wet = 0
	for i in range(1,3): s.party[i].hp = 0
	for i in range(2): s.enemies[i].hp = 0
	s.party[0].pos = Vector2i(2,2)
	s.enemies[2].pos = Vector2i(5,2)
	return s

func _initialize() -> void:
	var s = setup()
	var enemy: Dictionary = s.enemies[2]
	s.plan_enemies()
	check(s.intents.is_empty(),"ordinary attacks have no cell warning")
	s.party[0].pos = Vector2i(3,2)
	var hp: int = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp-10 and s.distance(enemy.pos,s.party[0].pos) == 1,"chase current position then attack")
	s = setup(); enemy = s.enemies[2]
	enemy.pos = Vector2i(7,7); hp = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp and s.distance(Vector2i(7,7),enemy.pos) == 2,"distant enemy moves without ranged damage")
	s = setup(); enemy = s.enemies[2]
	for y in range(8): s.tile(Vector2i(4,y)).terrain = "wall"
	hp = s.party[0].hp; s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp and enemy.pos == Vector2i(5,2),"walls block pursuit")
	s = setup(); enemy = s.enemies[2]
	s.round_number = 3; s.plan_enemies()
	check(s.intents.size() == 1 and enemy.charging,"heavy skill telegraphed every third round")
	s.party[0].pos = Vector2i(2,3); hp = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp and enemy.pos == Vector2i(5,2),"heavy attack can be dodged without fallback melee")
	s = setup(); enemy = s.enemies[2]
	s.round_number = 3; s.plan_enemies(); hp = s.party[0].hp
	s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp-16,"heavy attack hits marked cell")
	s = setup(); enemy = s.enemies[2]
	enemy.pos = Vector2i(3,2); s.round_number = 3; s.plan_enemies()
	check(s.act("PUSH",enemy.pos),"player interrupts charge with push")
	hp = s.party[0].hp; s.enemy_attack_turn(enemy)
	check(s.intents.is_empty() and s.party[0].hp == hp,"interrupted charge loses its attack")
	s = setup(); enemy = s.enemies[2]
	s.round_number = 3; s.plan_enemies(); enemy.hp = 0
	hp = s.party[0].hp; s.enemy_attack_turn(enemy)
	check(s.party[0].hp == hp,"dead enemy cannot resolve a telegraph")
	print("Enemy turns: %d failures" % failures)
	quit(1 if failures else 0)
