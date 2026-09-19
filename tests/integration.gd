extends SceneTree
const Session = preload("res://expedition/session.gd")
var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	var s = Session.new(731)
	check(s.depart(), "departure")
	check(not s.travel(6) and s.food == 9, "invalid travel has no resource effect")
	check(s.travel(1) and s.tiles.size() == 64 and s.phase == "BATTLE", "8x8 battle entry")
	check(not s.travel(3), "cannot skip unresolved battle")
	var ap: int = s.party[0].ap
	check(not s.act("MOVE",Vector2i(7,7)) and s.party[0].ap == ap, "invalid move preserves AP")
	check(not s.act("ATTACK",s.enemies[0].pos), "melee range validation")
	check(s.act("MOVE",Vector2i(2,2)), "shared pathfinder moves actor")
	var hp: int = s.party[0].hp
	check(s.end_round() and s.party[0].hp == hp, "cell-locked intent can be dodged")
	check(not s.party[2].memory.records.is_empty(), "actual enemy damage creates memory")
	check(s.party[2].body.revision > 0, "damage updates imported body state")
	s.enemies[0].pos = Vector2i(3,3); s.party[0].pos = Vector2i(2,3)
	s.party[0].ap = 2
	check(s.act("PUSH",Vector2i(3,3)), "push action")
	check(s.enemies[0].pos == Vector2i(4,3), "push changes position")
	check(s.intents.all(func(row): return row.id != s.enemies[0].id), "push cancels intent")
	# Both teams occupy the same connected conductor; verify friendly fire.
	s.party[0].pos = Vector2i(5,3); s.enemies[0].pos = Vector2i(5,4)
	s.party[0].ap = 2
	var enemy_hp: int = s.enemies[0].hp
	hp = s.party[0].hp
	check(s.act("ELECTRIC",Vector2i(5,4)), "electric action")
	check(s.enemies[0].hp < enemy_hp and s.party[0].hp < hp, "conducted electricity affects both teams")
	s.tile(Vector2i(0,3)).fire = 35; s.tile(Vector2i(0,3)).wet = 70
	s.end_round()
	check(s.tile(Vector2i(0,3)).fire == 0, "imported water/fire suppression")
	for enemy in s.enemies: s.damage(enemy,1000,0,"SLASH")
	s.check_battle_end()
	check(s.phase == "EXPLORE" and s.loot == 35, "victory unlocks route and rewards")
	var memory_before: Dictionary = s.party[1].memory.to_dict()
	var body_before: Dictionary = s.party[1].body.to_dict()
	check(s.travel(3), "travel to camp")
	check(s.party[1].memory.to_dict() == memory_before and s.party[1].body.to_dict() == body_before, "body and memory survive room transition")
	check(s.camp() and not s.camp(), "camp supplies consumed exactly once")
	check(s.travel(5) and s.phase == "EVENT", "branch to curio")
	check(s.event_choice(false) and not s.event_choice(true), "curio cannot be farmed")
	check(s.travel(6) and s.enemies.size() == 3, "boss encounter")
	for enemy in s.enemies: s.damage(enemy,1000,0,"SLASH")
	s.check_battle_end()
	check(s.retreat() and s.bank == 135 and s.phase == "TOWN", "completed expedition settles loot")
	memory_before = s.party[1].memory.to_dict()
	check(s.rest_town() and s.party[1].memory.to_dict() == memory_before, "town rest retains memory")
	check(s.depart() and s.party[1].memory.to_dict() == memory_before, "next expedition retains memory")
	s.stress(s.party[0],1000)
	check(s.action_budget(s.party[0]) == 1, "breakdown affects tactical AP")
	check(s.travel(1), "second expedition encounter")
	s.loot = 31
	check(s.retreat() and s.bank == 130, "combat retreat halves loot with integer rounding")
	check(not s.retreat() and s.bank == 130, "no repeated settlement")
	var dead = Session.new()
	dead.depart(); dead.travel(1)
	for actor in dead.party: dead.damage(actor,1000,100,"IMPACT")
	dead.check_battle_end()
	check(dead.phase == "DEFEAT" and not dead.depart(), "party wipe terminates expedition")
	print("Integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
