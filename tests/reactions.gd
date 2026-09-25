extends SceneTree
## Element reactions: the forms damage takes, the guards against loops, the
## ground reactions, the status reactions and what the board shows.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	forms()
	ground()
	statuses()
	await board()
	print("Reactions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally at c+(0,1), a fresh foe at c+(1,0) and a second foe at
## c+(2,0), both with no part, no resistance, no armour.
func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	var other: Dictionary = s.enemies[1]
	for enemy in [foe,other]:
		enemy.hp = 40; enemy.max_hp = 40; enemy.part_id = ""; enemy.species_id = ""
		enemy.res = {}; enemy.statuses = {}; enemy.sh = 0; enemy.ev = 0; enemy.ac = 0
	foe.pos = c+Vector2i(1,0); other.pos = c+Vector2i(2,0)
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe,"other":other}

func forms() -> void:
	var d := duo(); var s = d.s
	check(Reactions.element_of("ELECTRIC") == "air" and Reactions.element_of("FIRE") == "fire" and Reactions.element_of("SLASH") == "physical" and Reactions.element_of("bleed") == "bleed","damage forms map to elements")
	var before: int = d.foe.hp
	Rules.damage(s,d.hero,d.foe,5,"poison",0,Reactions.REACTION_FORM)
	check(int(d.foe.hp) == before-5,"reaction damage lands as it is")
	check(int(d.foe.get("last_hit",-1)) == -1,"reaction damage is not a hit")
	Rules.damage(s,d.hero,d.foe,4,"physical")
	check(int(d.foe.last_hit) == 4,"a hit leaves its amount on the target")
	s.effects.clear()
	s.damage(d.foe,3,int(d.hero.id),"REACTION")
	check(s.effects.any(func(e): return str(e.get("form","")) == "REACTION"),"the session keeps the form of a secondary hit")
	Reactions.begin_action(s)
	check(Reactions.once(s,d.hero,"GUARD") and not Reactions.once(s,d.hero,"GUARD"),"a trigger fires once in an action")
	check(Reactions.once(s,d.ally,"GUARD"),"another member keeps their own")
	Reactions.begin_action(s)
	check(Reactions.once(s,d.hero,"GUARD"),"the next action fires it again")
	check(Reactions.fresh_reaction(s,d.foe,"shatter") and not Reactions.fresh_reaction(s,d.foe,"shatter"),"a reaction once a round on a target")
	s.time += 100
	check(Reactions.fresh_reaction(s,d.foe,"shatter"),"and again the next round")
	var serial: int = s.action_serial
	s.act_as(d.hero,"WAIT",d.hero.pos,false)
	check(int(s.action_serial) > serial,"every action opens a new action")
	d.foe.statuses["stun"] = s.time+100
	check(Statuses.blocks(d.foe,"MOVE") and Statuses.blocks(d.foe,"ATTACK") and Statuses.blocks(d.foe,"CAST"),"a stun stops everything")
	s.tile(d.hero.pos).wet = 50
	check(Reactions.wet_ground(s,d.hero.pos) and Reactions.is_wet(s,d.hero),"standing in water is wet")
	Reactions.refresh_wet(s)
	check(int(d.hero.statuses.get("wet",0)) == int(s.time)+Reactions.DRY_TICKS,"the wet status dries two rounds after leaving")
	s.tile(d.hero.pos).wet = 0
	check(Reactions.is_wet(s,d.hero),"still wet just after stepping out")
	s.tile(d.ally.pos)["deep_water"] = true
	check(Reactions.wet_ground(s,d.ally.pos),"deep water counts as wet ground")

func ground() -> void:
	# Fire on wet ground: steam over the cell and its four neighbours.
	var d := duo(); var s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"fire",10,d.hero)
	check(int(s.tile(d.foe.pos).get("steam_until",0)) == int(s.time)+Reactions.STEAM_TICKS,"fire on wet ground raises steam")
	check(int(s.tile(d.foe.pos+Vector2i(0,1)).get("steam_until",0)) > int(s.time),"the steam spreads to the neighbours")
	check(int(s.tile(d.foe.pos).wet) == 20,"the fire boils thirty of the water away")
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION" and e.text == "증기"),"the board shows the steam")
	check(s.events.any(func(e): return e.get("kind","") == "REACTION" and e.name == "증기"),"the event queue carries it")
	check(Reactions.blocks_sight(s,d.foe.pos) and not MonsterAI.line(s,d.c,d.c+Vector2i(4,0),6),"steam blocks sight")
	var hp: int = d.foe.hp
	Scheduler.environment_tick(s)
	check(int(d.foe.hp) == hp-Reactions.STEAM_DAMAGE,"standing in steam scalds")
	s.time += Reactions.STEAM_TICKS+1
	Scheduler.environment_tick(s)
	check(not s.tile(d.foe.pos).has("steam_until") and MonsterAI.line(s,d.c,d.c+Vector2i(4,0),6),"the steam clears")
	# Burning wet ground boils on its own.
	d = duo(); s = d.s
	s.tile(d.other.pos).fire = 40; s.tile(d.other.pos).wet = 40
	Scheduler.environment_tick(s)
	check(int(s.tile(d.other.pos).get("steam_until",0)) > int(s.time),"fire meeting water in the tick raises steam")
	# Frost on wet ground: ice, and whoever stands on it freezes.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"ice",5,d.hero)
	check(bool(s.tile(d.foe.pos).get("ice",false)) and int(s.tile(d.foe.pos).wet) == 0,"frost turns the water to ice")
	check(d.foe.statuses.has("freeze"),"whoever stands on it freezes")
	var dry: int = Rules.move_time(s,d.hero,d.hero.pos+Vector2i(0,-1))
	s.tile(d.hero.pos+Vector2i(0,-1))["ice"] = true
	check(Rules.move_time(s,d.hero,d.hero.pos+Vector2i(0,-1)) == dry*3/2,"ice is slow to cross")
	Reactions.tile_react(s,d.foe.pos,"fire",5,d.hero)
	check(not bool(s.tile(d.foe.pos).ice) and int(s.tile(d.foe.pos).wet) == 50,"fire melts it back to water")
	s.tile(d.other.pos).wet = 0
	Reactions.tile_react(s,d.other.pos,"ice",5,d.hero)
	check(not bool(s.tile(d.other.pos).get("ice",false)),"dry ground does not freeze")
	# Lightning on conductive ground discharges at thirty percent.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50; s.tile(d.other.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"air",30,d.hero)
	check(int(d.foe.hp) == 40-9 and int(d.other.hp) == 40-3,"a discharge starts at thirty percent and weakens by six a cell")
	check(int(d.hero.hp) == int(d.hero.max_hp),"dry ground does not carry it")
	Reactions.tile_react(s,d.foe.pos,"air",30,d.hero)
	check(int(d.foe.hp) == 40-9,"the same cell discharges once a round")
	# Poison on wet ground: a pool that poisons until it dries.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"poison",5,d.hero)
	check(bool(s.tile(d.foe.pos).get("poison_pool",false)),"poison on water makes a pool")
	Scheduler.environment_tick(s)
	check(d.foe.statuses.has("poison"),"the pool poisons who stands in it")
	s.tile(d.foe.pos).wet = 0
	Scheduler.environment_tick(s)
	check(not bool(s.tile(d.foe.pos).poison_pool),"a dry pool is gone")
	# A landed hit reacts with the ground under its target.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Rules.damage(s,d.hero,d.foe,5,"ice")
	check(bool(s.tile(d.foe.pos).get("ice",false)),"an ice hit freezes the target's wet ground")
	s.tile(d.other.pos).wet = 50
	Rules.damage(s,d.hero,d.other,5,"ice",0,Reactions.REACTION_FORM)
	check(not bool(s.tile(d.other.pos).get("ice",false)),"reaction damage never reacts")

func statuses() -> void:
	# 화상 + 중독: a blast around the target, both statuses spent.
	var d := duo(); var s = d.s
	d.foe.statuses = {"burn":s.time+300,"poison":s.time+300}
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(not d.foe.statuses.has("burn") and not d.foe.statuses.has("poison"),"the blast spends both statuses")
	check(int(d.foe.hp) == 40-Reactions.BLAST_DAMAGE and int(d.other.hp) == 40-Reactions.BLAST_DAMAGE,"the blast hits the target and its neighbour")
	check(d.other.statuses.has("poison"),"and poisons the neighbour")
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION" and e.text == "독 폭발!"),"the blast is named")
	d.foe.statuses = {"burn":s.time+300,"poison":s.time+300}
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(d.foe.statuses.has("burn") and int(d.foe.hp) == 40-Reactions.BLAST_DAMAGE,"one blast a round on the same target")
	s.time += 100
	d.foe.statuses = {"burn":s.time+300,"poison":s.time+300}
	Statuses.apply(s,d.foe,"poison",300,d.hero)
	check(not d.foe.statuses.has("burn"),"hanging the second status sets the blast off too")
	# 빙결 + 물리 피해: the ice breaks for half again.
	d = duo(); s = d.s
	d.foe.statuses = {"freeze":s.time+100}
	Rules.damage(s,d.hero,d.foe,10,"physical")
	check(not d.foe.statuses.has("freeze") and int(d.foe.hp) == 40-10-5,"a physical hit shatters the ice for fifty percent more")
	d.other.statuses = {"freeze":s.time+100}
	Rules.damage(s,d.hero,d.other,10,"fire")
	check(d.other.statuses.has("freeze"),"a fire hit does not shatter")
	# 출혈 + 화상: the bleeding still to come lands at once, as fire.
	d = duo(); s = d.s
	d.foe.statuses = {"bleed":s.time+300,"burn":s.time+300}
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(not d.foe.statuses.has("bleed") and int(d.foe.hp) == 40-4*2,"the blood boils: four rounds of bleeding at once")
	# 젖음 + 전기: stunned.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.status_react(s,d.foe,d.hero,"air","HIT")
	check(d.foe.statuses.has("stun") and Statuses.blocks(d.foe,"ATTACK"),"lightning on a wet target stuns it")
	Reactions.status_react(s,d.other,d.hero,"air","HIT")
	check(not d.other.statuses.has("stun"),"a dry one is not")
	# 혼란 + 도발: the confused one turns on its own side.
	d = duo(); s = d.s
	d.foe.statuses = {"confuse":s.time+200,"taunt":s.time+200}
	d.foe.get_or_add("status_power",{})["taunt"] = int(d.hero.id)
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION" and e.text == "배신!"),"the taunted, confused foe betrays its side")
	d.other.pos = d.c+Vector2i(6,6)
	d.foe.statuses = {"confuse":s.time+200,"taunt":s.time+200}
	s.time += 100; s.effects.clear()
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(not s.effects.any(func(e): return e.get("kind","") == "REACTION"),"with nobody of its own side beside it, nothing happens")
	# Reaction damage is not a hit: it neither reacts nor chains.
	d = duo(); s = d.s
	d.other.statuses = {"freeze":s.time+100}
	Reactions.react_damage(s,d.hero,d.other,5,"physical")
	check(d.other.statuses.has("freeze"),"reaction damage never shatters")

func board() -> void:
	var source: String = FileAccess.get_file_as_string("res://expedition/ui/board.gd")
	check(source.contains("func draw_reaction") and source.contains("kind == \"REACTION\": draw_reaction"),"the board draws reaction names")
	check(source.contains("steam_until") and source.contains("poison_pool") and source.contains("\"ice\""),"the board draws steam, ice and poison pools")
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var d := duo(); var s = d.s
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"fire",10,d.hero)
	Reactions.tile_react(s,d.other.pos,"ice",5,d.hero)
	scene.refresh()
	for frame in range(3): await process_frame
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION"),"a reaction reaches the board without an error")
	scene.queue_free()
