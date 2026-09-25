extends SceneTree
## End-to-end floor contract and persistent run state across descent.
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var signatures: Dictionary = {}
	var theme: Dictionary = Floor.theme_for(1)
	for seed in range(100):
		var s = Session.new_run(seed)
		var layout: Dictionary = s.floor_state.layout
		check(s.phase == "EXPLORE" and s.depth == 1 and s.party.size() == 1,"seed %d starts solo on floor one" % seed)
		check(layout.size == 80 and layout.terrain.size() == 6400,"seed %d full floor" % seed)
		check(Generator.validate(layout,theme).is_empty(),"seed %d layout validates" % seed)
		check(layout.entry != layout.stairs and layout.stairs.x >= 0,"seed %d has separate entry and stairs" % seed)
		check(s.tile(layout.entry).terrain != "wall" and s.tile(layout.stairs).terrain != "wall","seed %d endpoints walkable" % seed)
		check(layout.npc_rooms.size() >= 3 and layout.npc_rooms.size() <= 5,"seed %d reserved NPC rooms" % seed)
		var ids: Dictionary = {}
		for room in layout.rooms:
			check(not ids.has(room.id),"seed %d unique room id %d" % [seed,room.id])
			ids[room.id] = true
			check(room.rect.position.x >= 1 and room.rect.position.y >= 1 and room.rect.end.x < 80 and room.rect.end.y < 80,"seed %d room %d stays in bounds" % [seed,room.id])
			check(room.doors.size() >= 1 and room.doors.all(func(p): return s.tile(p).terrain != "wall"),"seed %d room %d has walkable doors" % [seed,room.id])
		check(ids.size() == layout.rooms.size(),"seed %d all rooms have ids" % seed)
		check(s.floor_state.features.has(layout.stairs) and s.floor_state.features[layout.stairs].kind == "stairs","seed %d stairs feature registered" % seed)
		check(s.enemies.all(func(e): return s.inside(e.pos) and s.tile(e.pos).terrain != "wall"),"seed %d enemies spawn on walkable tiles" % seed)
		signatures[str(layout.rooms.map(func(r): return r.rect))] = true
	check(signatures.size() > 20,"run seeds vary topology")
	var run_session = Session.new_run(731)
	var actor: Dictionary = run_session.party[0]
	actor.hp = 20; actor.stress = 60
	for enemy in run_session.enemies: enemy.hp = 0
	var food_before: int = run_session.food
	check(run_session.camp() and run_session.food == food_before-1,"safe camp consumes food")
	check(actor.hp > 20 and actor.stress == 30,"camp recovers condition")
	check(run_session.end_camp(),"camp returns to floor")
	var memory_before: Dictionary = actor.memory.to_dict()
	var hp_before: int = actor.hp
	run_session.party[0].pos = run_session.floor_state.layout.stairs
	run_session.floor_state.observe(run_session)
	check(run_session.descend() and run_session.depth == 2,"stairs advance to floor two")
	check(actor.hp == hp_before and actor.memory.to_dict() == memory_before,"descent keeps HP and memories")
	check(run_session.food == food_before-1 and run_session.floor_state.layout.theme_id == "F1_RUINS","food persists within the zone")
	run_session.damage(actor,1000,100,"IMPACT")
	run_session.check_battle_end()
	check(run_session.phase == "DEFEAT" and not run_session.descend(),"hero death ends run")
	determinism()
	floor_actions()
	enemy_round()
	memories()
	wipe()
	print("Integration: %d checks, %d failures; 100 run seeds" % [checks,failures])
	quit(1 if failures else 0)

## The same seed and depth rebuild the same floor; a different one does not.
func determinism() -> void:
	var theme: Dictionary = Floor.theme_for(1)
	var first: Dictionary = Generator.generate(theme,4242,1)
	var again: Dictionary = Generator.generate(theme,4242,1)
	check(first.terrain == again.terrain,"the same seed reproduces the terrain")
	check(str(first.rooms.map(func(r): return r.rect)) == str(again.rooms.map(func(r): return r.rect)),"and the same rooms")
	check(first.stairs == again.stairs and first.entry == again.entry,"and the same endpoints")
	var other: Dictionary = Generator.generate(theme,9999,1)
	check(other.terrain != first.terrain,"a different seed builds a different floor")
	var deeper: Dictionary = Generator.generate(Floor.theme_for(2),4242,2)
	check(deeper.terrain != first.terrain,"the same seed one floor down is a different floor")

## The action contract on an open floor: refusals cost nothing, the legal ones
## land, and the elements behave.
func floor_actions() -> void:
	var s = Session.new_run(731)
	var center: Vector2i = Fixture.arena(s,14)
	Fixture.equip_basics(s)
	var hero: Dictionary = s.party[0]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 60; foe.max_hp = 60; foe.pos = center+Vector2i(3,0); foe.alert = true
	for i in range(1,s.enemies.size()): s.enemies[i].pos = center+Vector2i(20,i)
	s.floor_state.observe(s); s.plan_enemies()
	var ap: int = hero.ap
	check(not s.act("MOVE",center+Vector2i(9,9)) and hero.ap == ap,"an out-of-reach move is refused and costs no action")
	check(not s.act("ATTACK",foe.pos) and hero.ap == ap,"an out-of-reach attack is refused")
	check(s.act("MOVE",center+Vector2i(1,0)) and hero.pos == center+Vector2i(1,0),"a legal step lands")
	hero.ap = 2; hero.pos = center; foe.pos = center+Vector2i(1,0)
	foe.ready_at = s.time+1000
	s.floor_state.observe(s); s.plan_enemies()
	check(s.act("PUSH",foe.pos) and foe.pos == center+Vector2i(2,0),"push shoves the foe one cell away")
	check(s.intents.all(func(row): return row.id != foe.id),"push cancels whatever the foe had planned")
	# 밀 곳이 없으면 피해 8: a foe with its back to a wall takes the shove itself.
	hero.pos = center; hero.ap = 2
	foe.pos = center+Vector2i(1,0); s.tile(center+Vector2i(2,0)).terrain = "wall"
	s.floor_state.observe(s)
	var foe_hp: int = foe.hp
	check(s.act("PUSH",foe.pos),"a shove with nowhere to go still goes off")
	# The shove carries the hero's strength: half of it over ten.
	var shove: int = Session.Abilities.power(s,hero,Session.Abilities.DEFINITIONS.PUSH,"PUSH")
	check(foe.pos == center+Vector2i(1,0) and foe.hp == foe_hp-shove,"it stays put and takes the damage instead")
	s.tile(center+Vector2i(2,0)).terrain = "stone"
	var wet := center+Vector2i(0,5)
	s.tile(wet).terrain = "stone"; s.tile(wet).fire = 35; s.tile(wet).wet = 70
	s.end_round()
	check(s.tile(wet).fire == 0,"water puts the fire out")

## The enemies take their turn at the end of the round, and what it costs the
## party shows up in the body and, when it matters, in the memory.
func enemy_round() -> void:
	var s = Session.new_run(17)
	var center: Vector2i = Fixture.arena(s,12)
	Fixture.equip_basics(s)
	var hero: Dictionary = s.party[0]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 80; foe.max_hp = 80; foe.pos = center+Vector2i(1,0); foe.alert = true; foe.part_id = ""
	s.floor_state.observe(s); s.plan_enemies()
	var hp: int = hero.hp; var round_before: int = s.round_number
	check(s.end_round(),"the round closes")
	check(s.round_number > round_before,"and the next one opens")
	check(hero.hp <= hp,"an adjacent foe gets its swing in")
	var before: int = hero.hp
	s.damage(hero,5,foe.id,"SLASH")
	check(hero.hp == before-5,"a hit takes exactly what it says")
	check(hero.memory.records.all(func(record): return record.salience >= 700),"only the significant injuries persist")

## What a member remembers: nothing ordinary, once for the brush with death,
## and the loss of a companion.
func memories() -> void:
	var s = Session.new(731,false,true,true,3)
	var member: Dictionary = s.party[0]
	s.damage(member,1,100,"IMPACT")
	check(member.memory.records.is_empty(),"an ordinary hit is not worth remembering")
	member.hp = 15
	s.damage(member,2,100,"IMPACT")
	check(member.memory.records.size() == 1 and member.memory.records[0].salience >= 700,"crossing into critical health is")
	member.hp = 15
	s.damage(member,2,100,"IMPACT")
	check(member.memory.records.size() == 1,"and it is not written twice on the same floor")
	s.damage(s.party[1],999,100,"IMPACT")
	check(member.memory.records.any(func(record): return record.kind == "ALLY_LOST"),"losing a companion is remembered")

## A wiped party ends the run, and a finished run accepts nothing more.
func wipe() -> void:
	var s = Session.new_run(3)
	for actor in s.party: s.damage(actor,1000,100,"IMPACT")
	s.check_battle_end()
	check(s.phase == "DEFEAT","the run ends when nobody is left")
	check(not s.descend() and not s.camp(),"a finished run neither descends nor camps")
	check(not s.on_floor(),"and it is no longer on a floor")
