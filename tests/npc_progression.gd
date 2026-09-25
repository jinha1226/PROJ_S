extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Mastery = preload("res://expedition/progression/mastery.gd")
var checks := 0
var failures := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func field() -> Dictionary:
	var s = Session.new(131,true,true,true,3)
	s.depart()
	s.manual_mode = true
	var c := Fixture.arena(s,12)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]
	npc.pos = c+Vector2i(3,0)
	npc.hp = npc.max_hp
	npc.awake = true
	npc.hostile = false
	npc.equipped_abilities = ["",""]
	npc.rules = []
	s.floor_state.observe(s)
	return {"s":s,"c":c,"npc":npc}

func run() -> void:
	solo_hunts()
	legacy_hunt()
	shared_hunt()
	monster_kill()
	print("NPC progression: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func solo_hunts() -> void:
	var f := field(); var s = f.s; var npc: Dictionary = f.npc
	var axis: String = Mastery.weapon_axis(str(npc.gear.weapon.type))
	var bag: Dictionary = s.parts_bag.duplicate(true)
	var score: int = s.score
	check(s.enemies.size() >= 3,"arena has three monsters for a level-up")
	for i in range(3):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 1; foe.max_hp = 1; foe.pos = npc.pos+Vector2i(1,0)
		foe.part_id = ""
		s.floor_state.observe(s)
		for attempt in range(12):
			if foe.hp <= 0: break
			npc.ap = 1
			check(s.act_as(npc,"ATTACK",foe.pos,false),"NPC can make its own attack")
		check(foe.hp <= 0,"NPC kills monster %d" % i)
	check(int(npc.level_xp) == 3*(18+s.depth*8) and int(npc.level) == 2,"roster NPC gains the same level XP and HP/MP level-up as a hero")
	check(int(npc.skill_xp.get(axis,0)) == 3*(18+s.depth*8),"NPC gains weapon mastery from its hunts")
	check(s.roster.any(func(r): return r.id == npc.id and int(r.level) == 2),"progression persists in the roster")
	check(s.party.all(func(a): return int(a.level_xp) == 0) and s.parts_bag == bag and s.score == score,"unwitnessed NPC hunts grant no party XP, loot or score")

func shared_hunt() -> void:
	var f := field(); var s = f.s; var npc: Dictionary = f.npc
	var bystander: Dictionary = s.roster.filter(func(r): return r.id != npc.id)[0]
	bystander.pos = f.c+Vector2i(8,0); bystander.awake = true; bystander.hp = bystander.max_hp
	s.npcs.append(bystander)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = npc.pos+Vector2i(1,0)
	s.party[0].pos = foe.pos+Vector2i(0,-1)
	s.floor_state.observe(s)
	npc.ap = 1; s.party[0].ap = 1
	check(s.act_as(npc,"ATTACK",foe.pos,false),"NPC participates in shared hunt")
	check(s.act_as(s.party[0],"ATTACK",foe.pos,false),"hero participates in shared hunt")
	if foe.hp > 0: s.damage(foe,999,npc.id,"SLASH")
	check(foe.hp <= 0 and s.party.all(func(a): return int(a.level_xp) == 18+s.depth*8),"party shares XP when it joined the fight")
	check(int(npc.level_xp) == 18+s.depth*8 and int(bystander.level_xp) == 0,"participating NPC gains XP; bystander does not")
	check(int(npc.skill_xp.get(Mastery.weapon_axis(str(npc.gear.weapon.type)),0)) > 0,"shared kill grants NPC mastery by contribution")

func legacy_hunt() -> void:
	var f := field(); var s = f.s; var npc: Dictionary = f.npc
	s.manual_mode = false
	var foe: Dictionary = s.enemies[0]
	foe.hp = 1; foe.max_hp = 1; foe.pos = npc.pos+Vector2i(1,0)
	foe.part_id = ""
	s.floor_state.observe(s)
	npc.ap = 1
	check(s.act_as(npc,"ATTACK",foe.pos,false) and foe.hp <= 0,"NPC hunts in legacy turn mode")
	check(int(npc.growth.xp) == 25 and int(npc.skill_xp.get(Mastery.weapon_axis(str(npc.gear.weapon.type)),0)) == 18+s.depth*8,"legacy hunt also grants NPC growth and mastery")
	check(s.party.all(func(a): return int(a.growth.xp) == 0),"legacy NPC hunt gives no party XP")

func monster_kill() -> void:
	var f := field(); var s = f.s
	var victim: Dictionary = s.enemies[0]
	var killer: Dictionary = s.enemies[1]
	victim.hp = 1; victim.pos = f.c+Vector2i(4,0)
	killer.hp = 20; killer.pos = f.c+Vector2i(5,0)
	var score: int = s.score
	var bag: Dictionary = s.parts_bag.duplicate(true)
	s.damage(victim,10,killer.id,"SLASH")
	check(victim.hp <= 0 and s.party.all(func(a): return int(a.level_xp) == 0),"monster versus monster kill gives no party XP")
	check(s.score == score and s.parts_bag == bag,"monster kill gives no party score or loot")
