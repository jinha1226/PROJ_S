extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	call_deferred("exercise")

func exercise() -> void:
	var s = Session.new(731,true)
	s.depart()
	check(s.party.size() == 1 and s.phase == "BATTLE","solo begins with boss")
	for id in range(9):
		s.room = id; s.enter_room()
		check(s.enemies.size() == 1 and s.rooms[id].kind == "boss","one boss in every room")
		var boss: Dictionary = s.enemies[0]
		if id % 3 in [0,1]:
			s.round_number = 3; s.plan_enemies()
			check(not s.intents.is_empty(),"special attack telegraphed")
			s.party[0].pos = s.intents[0].cell
			var hp: int = s.party[0].hp
			s.enemy_attack_turn(boss)
			check(s.party[0].hp == hp-16,"marked cells resolve once")
			s.party[0].hp = s.party[0].max_hp
		else:
			boss.hp = 32; s.plan_enemies()
			check(s.rooms[id].shield,"half health activates shield")
			s.damage(boss,10,0,"SLASH")
			check(boss.hp == 32,"shield blocks damage")
			s.party[0].pos = s.rooms[id].pylon+Vector2i.LEFT
			check(s.act("PYLON",s.rooms[id].pylon),"adjacent hero disables pylon")
			check(not s.rooms[id].shield,"pylon releases shield")
		s.damage(boss,1000,0,"SLASH"); s.check_battle_end()
		check(s.phase == "EXPLORE" and s.party[0].hp == s.party[0].max_hp,"win clears and heals")
		s.enter_room()
		check(s.phase == "EXPLORE" and s.enemies.size() == 1,"cleared boss never respawns")
	var scene = load("res://expedition/main.tscn").instantiate()
	root.add_child(scene); scene.depart()
	await process_frame
	check(scene.portrait_buttons.size() == 1 and scene.skill_buttons.size() == 2,"solo UI")
	scene.queue_free(); await process_frame
	print("Boss trial: %d failures" % failures)
	quit(1 if failures else 0)
