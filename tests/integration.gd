extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/map_fixture.gd")
var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1; push_error(description)

func _initialize() -> void:
	var graphs: Dictionary = {}
	for seed_value in range(100):
		var generated: Array = Session.Dungeon.generate(seed_value)
		check(generated == Session.Dungeon.generate(seed_value),"same seed reproduces map")
		var seen: Array = [0]
		var cursor := 0
		var signature := ""
		while cursor < seen.size():
			for next in generated[seen[cursor]].links:
				if next not in seen: seen.append(next)
			cursor += 1
		check(seen.size() == 9,"all nine rooms reachable")
		for row in generated:
			check(row.tiles.size() == 100,"every room owns 100 tiles")
			for next in row.links:
				check(row.id in generated[next].links and next in Session.Dungeon.neighbors(row.id),"bidirectional cardinal link")
			signature += str(row.links)
		graphs[signature] = true
		check(generated.filter(func(r): return r.kind == "camp").size() == 2,"recovery rooms guaranteed")
		check(generated.filter(func(r): return r.kind == "loot").size() == 2,"loot rooms guaranteed")
	check(graphs.size() > 20,"random generation varies topology")
	var s = Session.new(731)
	check(s.depart() and s.tiles.size() == 100,"entry has an 10x10 room")
	var original_map: Array = s.rooms.duplicate(true)
	check(not s.travel(8) and not s.travel(-1) and s.food == 27,"invalid travel has no side effects")
	var battle := Fixture.kind_id(s,"battle")
	check(Fixture.reach(s,battle) and s.phase == "BATTLE","map enters battle")
	check(not s.travel(s.rooms[s.room].links[0]),"battle blocks map travel")
	for i in range(3): s.party[i].pos = Vector2i(1,2+i)
	s.plan_enemies()
	var ap: int = s.party[0].ap
	check(not s.act("MOVE",Vector2i(7,7)) and s.party[0].ap == ap,"invalid move preserves AP")
	check(not s.act("ATTACK",s.enemies[0].pos),"melee range validation")
	check(s.act("MOVE",Vector2i(2,2)),"pathfinder move")
	s.enemies[0].pos = Vector2i(2,4)
	var hp: int = s.party[0].hp
	check(s.end_round() and s.party[0].hp == hp,"enemy attacks reachable front-line target")
	check(s.party.any(func(a): return a.body.revision > 0),"damage updates body state")
	check(s.party.all(func(a): return a.memory.records.all(func(record): return record.salience >= 700)),"only significant injuries become persistent memories")
	# Isolate the push landing from other enemies' eight-way pursuit.
	for i in range(1,s.enemies.size()): s.enemies[i].pos = Vector2i(7,i)
	s.enemies[0].pos = Vector2i(3,3); s.party[0].pos = Vector2i(2,3); s.party[0].ap = 2
	check(s.act("PUSH",Vector2i(3,3)) and s.enemies[0].pos == Vector2i(4,3),"push moves enemy")
	check(s.intents.all(func(row): return row.id != s.enemies[0].id),"push cancels intent")
	s.party[0].pos = Vector2i(5,3); s.enemies[0].pos = Vector2i(5,4); s.party[0].ap = 2
	for point in [Vector2i(5,3),Vector2i(5,4)]: s.tile(point).terrain = "water"; s.tile(point).wet = 70
	var enemy_hp: int = s.enemies[0].hp
	hp = s.party[0].hp
	check(s.act("ELECTRIC",Vector2i(5,4)),"electric action")
	check(s.enemies[0].hp < enemy_hp and s.party[0].hp < hp,"conducted friendly fire")
	s.tile(Vector2i(0,3)).fire = 35; s.tile(Vector2i(0,3)).wet = 70
	s.end_round()
	check(s.tile(Vector2i(0,3)).fire == 0,"water suppresses fire")
	Fixture.clear_battle(s)
	var rewards: int = s.loot
	var memory_before: Dictionary = s.party[2].memory.to_dict()
	var body_before: Dictionary = s.party[2].body.to_dict()
	s.tile(Vector2i(0,0)).wet = 41
	var neighbor: int = s.rooms[s.room].links[0]
	check(s.travel(neighbor),"return through bidirectional link")
	check(s.party[2].memory.to_dict() == memory_before and s.party[2].body.to_dict() == body_before,"room travel preserves persistent actors")
	Fixture.clear_battle(s)
	rewards = s.loot
	check(s.travel(battle) and s.phase == "EXPLORE","cleared battle does not respawn")
	check(s.loot == rewards and s.tile(Vector2i(0,0)).wet == 41,"revisit preserves terrain and does not duplicate reward")
	check(Fixture.reach(s,Fixture.kind_id(s,"camp")),"reach recovery room")
	var camp_room: int = s.room
	check(s.interact_room(Vector2i(4,4)) and not s.camp(),"click recovery only once")
	neighbor = s.rooms[s.room].links[0]
	s.travel(neighbor); Fixture.clear_battle(s); s.travel(camp_room)
	check(not s.camp(),"revisiting cannot reset recovery")
	check(Fixture.reach(s,Fixture.kind_id(s,"loot")),"reach loot room")
	var loot_room: int = s.room
	rewards = s.loot
	check(s.interact_room(Vector2i(4,4)) and s.loot == rewards + 30,"chest interaction")
	check(not s.interact_room(Vector2i(4,4)),"chest reward cannot repeat")
	neighbor = s.rooms[s.room].links[0]
	s.travel(neighbor); Fixture.clear_battle(s); s.travel(loot_room)
	check(not s.event_choice(true),"revisited chest stays empty")
	check(Fixture.reach(s,8) and s.enemies.size() == 3,"boss room at bottom right")
	Fixture.clear_battle(s)
	rewards = s.loot
	check(s.retreat() and s.bank == rewards,"loot settled once")
	check(not s.retreat(),"no duplicate settlement")
	memory_before = s.party[2].memory.to_dict()
	check(s.rest_town() and s.party[2].memory.to_dict() == memory_before,"rest retains memory")
	check(s.depart() and s.party[2].memory.to_dict() == memory_before,"next expedition retains memory")
	check(s.rooms != original_map and s.rooms.all(func(r): return not r.used),"new expedition regenerates rooms")
	Fixture.reach(s,Fixture.kind_id(s,"battle"))
	s.loot = 31; rewards = s.bank
	check(s.retreat() and s.bank == rewards + 15,"combat retreat penalty")
	var dead = Session.new()
	dead.depart(); Fixture.reach(dead,Fixture.kind_id(dead,"battle"))
	for actor in dead.party: dead.damage(actor,1000,100,"IMPACT")
	dead.check_battle_end()
	check(dead.phase == "DEFEAT" and not dead.depart(),"party wipe")
	var memories = Session.new()
	var member: Dictionary = memories.party[0]
	memories.damage(member,1,100,"IMPACT")
	check(member.memory.records.is_empty(),"ordinary hit does not become a persistent memory")
	member.hp = 15
	memories.damage(member,2,100,"IMPACT")
	check(member.memory.records.size() == 1 and member.memory.records[0].salience >= 700,"crossing into critical health creates an important memory")
	member.hp = 15
	memories.damage(member,2,100,"IMPACT")
	check(member.memory.records.size() == 1,"repeated critical injury is not recorded again in the same expedition")
	memories.damage(memories.party[1],999,100,"IMPACT")
	check(member.memory.records.any(func(record): return record.kind == "ALLY_LOST"),"ally loss remains an important memory")
	print("Integration: %d checks, %d failures; 100 dungeon seeds" % [checks,failures])
	quit(1 if failures else 0)
