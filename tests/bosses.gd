extends SceneTree
## Four bosses, one a zone (spec §7): the goblin chief's orders, the furnace
## golem's heat, the soul eater's hunger and seals, and the fallen adventurer.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const Chief = preload("res://expedition/actors/bosses/goblin_chief.gd")
const Golem = preload("res://expedition/actors/bosses/furnace_golem.gd")
const Eater = preload("res://expedition/actors/bosses/soul_eater.gd")
const Fallen = preload("res://expedition/actors/bosses/fallen_adventurer.gd")
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Templates = preload("res://expedition/level/floor_templates.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	frame()
	chief()
	golem()
	eater()
	fallen()
	rewards()
	boss_actives()
	print("Bosses: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## A boss floor at `depth` with only the boss and its own retinue standing,
## and the party inside the boss room `gap` cells from the boss.
func arena(depth: int, gap: int, party_size: int = 1, seed_value: int = 5) -> Dictionary:
	var s = Session.new(seed_value,false,party_size > 1,true,party_size)
	s.depart(); s.manual_mode = true
	s.depth = depth; s.floor_state.build(s); s.NpcRoster.place(s)
	var boss: Dictionary = {}
	for e in s.enemies:
		if e.get("boss",false): boss = e
	for n in s.npcs:
		if n.get("fallen",false): boss = n
	for e in s.enemies:
		if e.get("boss",false): continue
		if int(e.get("chief",-1)) == int(boss.get("id",-2)) or int(e.get("bound_to",-1)) == int(boss.get("id",-2)): continue
		e.hp = 0
	var room: Dictionary = BossAI.room_of(s,boss)
	var cells: Array = Generator.floor_cells(s.floor_state.layout.terrain,s.floor_state.layout.size,room.rect).filter(func(p): return s.is_free(p) and Common.reach(p,boss.pos) == gap)
	cells.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	for i in range(s.party.size()): s.party[i].pos = cells[i]
	boss.alert = true; s.phase = "BATTLE"; s.floor_state.observe(s)
	return {"s":s,"boss":boss,"hero":s.party[0],"room":room}

func frame() -> void:
	var glyphs: Dictionary = Templates.parse(["#1a#","#B.#"]).features
	check(glyphs[Vector2i(1,0)].kind == "lever" and int(glyphs[Vector2i(1,0)].channel) == 1,"1 is lever one")
	check(glyphs[Vector2i(2,0)].kind == "channel" and int(glyphs[Vector2i(2,0)].channel) == 1,"a is channel one")
	check(glyphs[Vector2i(1,1)].kind == "binding","B is a binding chain")
	check(not Templates.GLYPH_FEATURE.has("Y"),"the pylon glyph is gone")
	check(Common.boss_hp(3) == 180 and Common.boss_hp(6) == 420 and Common.boss_hp(9) == 660 and Common.boss_hp(12) == 960,"boss health is the zone base times six")
	check(Common.boss_attack(3) == 8 and Common.boss_attack(12) == 26,"boss blows follow the zone base")
	check(Common.reach(Vector2i(0,0),Vector2i(3,-2)) == 3,"reach is eight-way distance")
	for depth in [3,6,9]:
		var d := arena(depth,2); var s = d.s; var boss: Dictionary = d.boss
		var kind: String = BossAI.KINDS[depth/3-1]
		check(boss.boss_kind == kind and boss.name == BossAI.NAMES[kind],"floor %d holds the %s" % [depth,kind])
		check(int(boss.max_hp) == Common.boss_hp(depth) and int(boss.hp) == int(boss.max_hp),"%s health" % kind)
		check(boss.species_id == BossAI.SPECIES[kind] and boss.part_id == BossAI.ESSENCES[kind],"%s species and essence" % kind)
		check(str(boss.family) == BossAI.FAMILIES[kind] and str(boss.sprite_species) == BossAI.SPRITES[kind],"%s family and picture" % kind)
		check(not d.room.is_empty() and d.room.rect.has_point(boss.pos),"%s stands in its room" % kind)
		check(s.stairs_sealed(),"%s seals the stairs" % kind)
		s.events.clear()
		BossAI.turn(s,boss)
		check(bool(boss.room_sealed),"%s: the fight closes the room" % kind)
		check(d.room.doors.all(func(p): return s.tile(p).terrain == "wall" or not s.at(p).is_empty()),"%s: every free door is shut" % kind)
		check(s.events.any(func(e): return str(e.get("kind","")) == "BOSS" and str(e.get("hint","")) == BossAI.HINTS[kind]),"%s: its banner is raised" % kind)
	var outside := arena(3,2)
	outside.hero.pos = outside.s.floor_state.layout.entry
	var throne: Vector2i = outside.boss.pos
	BossAI.turn(outside.s,outside.boss)
	check(not bool(outside.boss.room_sealed),"the room stays open while nobody is inside")
	check(outside.boss.pos == throne,"a boss waits in its room until the fight begins")

func rewards() -> void:
	for depth in [3,6,9]:
		var d := arena(depth,2); var s = d.s; var boss: Dictionary = d.boss
		var id: String = str(boss.part_id)
		check(Essences.has(id) and str(Essences.content.rows[id].get("family","")) == str(boss.family),"%s is an essence row of its family" % id)
		check(not Essences.content.rows.values().any(func(r): return str(r.get("species","")).begins_with("boss_")),"no row of the old bosses is left")
		var count: int = int(s.parts_bag.get(id,0))
		BossAI.turn(s,boss)
		boss.hp = 1
		s.damage(boss,999,int(d.hero.id),"physical")
		check(boss.hp <= 0 and int(s.parts_bag.get(id,0)) == count+1,"%s always leaves its essence" % boss.name)
		check(d.room.doors.all(func(p): return s.tile(p).terrain != "wall"),"%s: the room opens when it falls" % boss.name)
		check(not s.stairs_sealed(),"%s: the stairs open" % boss.name)

func chief() -> void:
	var d := arena(3,2); var s = d.s; var boss: Dictionary = d.boss; var hero: Dictionary = d.hero
	var guard: Array = Chief.minions(s,boss)
	check(guard.size() == 4,"the chief keeps four minions")
	check(guard.map(func(m): return str(m.species_id)) == ["goblin","goblin_archer","goblin_shield","goblin_hexer"],"a goblin, an archer, a shield and a hexer")
	check(guard.map(func(m): return str(m.order)) == Chief.ORDERS,"each minion owns one order")
	var throne: Vector2i = boss.pos
	hero.hp = 999; hero.max_hp = 999
	BossAI.turn(s,boss)
	check(boss.order == "FOCUS" and int(boss.order_target) == int(hero.id),"the first order is 집중, on the weakest")
	s.intents.clear(); BossAI.plan(s,boss)
	check(s.intents.any(func(i): return str(i.kind) == "CHIEF_FOCUS" and i.cell == hero.pos),"the order is announced on the floor")
	BossAI.turn(s,boss)
	check(guard.all(func(m): return BossAI.focus_of(s,m) == hero),"집중: every minion hunts the marked member")
	check(str(boss.telegraph.get("kind","")) == "CHIEF_VOLLEY" and hero.pos in boss.telegraph.cells,"the next order is 화살비 around the marked member")
	var hp: int = hero.hp
	BossAI.turn(s,boss)
	check(hero.hp < hp,"화살비 lands")
	check(boss.pos == throne,"with minions standing the chief keeps its throne")
	check(boss.order == "WALL","then 방진")
	BossAI.turn(s,boss)
	var shield: Dictionary = Chief.owner(s,boss,"WALL")
	check(Common.reach(shield.pos,boss.pos) == 1,"방진: the shield stands beside the chief")
	check(boss.order == "CURSE","then 저주")
	BossAI.turn(s,boss)
	check(hero.statuses.has("weak"),"저주 weakens the marked member")
	var archer: Dictionary = Chief.owner(s,boss,"VOLLEY")
	archer.hp = 0
	check("VOLLEY" not in Chief.available(s,boss),"an order dies with the minion that owns it")
	for turn in range(4):
		BossAI.turn(s,boss)
		check(boss.order != "VOLLEY","no more 화살비 without the archer")
	for m in Chief.minions(s,boss): m.hp = 0
	BossAI.turn(s,boss)
	check(bool(boss.morale_broken),"with every minion down the chief's nerve breaks")
	var before: int = boss.hp
	s.damage(boss,10,int(hero.id),"physical")
	check(boss.hp == before-13,"a broken chief takes thirty percent more")
	hero.pos = Fixture.beside(s,boss.pos); s.floor_state.observe(s)
	hp = hero.hp
	for turn in range(4): BossAI.turn(s,boss)
	check(hero.hp < hp,"a broken chief fights for itself")

func golem() -> void:
	var d := arena(6,4); var s = d.s; var boss: Dictionary = d.boss
	var levers: Array = s.floor_state.features.keys().filter(func(p): return str(s.floor_state.features[p].get("kind","")) == "lever")
	check(levers.size() == 3,"three levers in the foundry")
	for lever in levers:
		var channel: int = int(s.floor_state.features[lever].channel)
		check(s.floor_state.features.values().any(func(f): return str(f.get("kind","")) == "channel" and int(f.get("channel",0)) == channel),"lever %d has its channel" % channel)
	check(int(boss.heat) == 0,"the golem starts cold")
	var was: Vector2i = boss.pos
	BossAI.turn(s,boss)
	check(boss.pos != was and int(boss.heat) == 15,"a round and a step: heat 15")
	check(int(s.tile(was).fire) >= 50,"the cell it left burns")
	# The blast: announced at the top of the gauge, landing two turns later.
	d = arena(6,2); s = d.s; boss = d.boss
	var hero: Dictionary = d.hero
	hero.hp = 999; hero.max_hp = 999; boss.heat = 99
	BossAI.turn(s,boss)
	check(bool(boss.blasting) and str(boss.telegraph.kind) == "GOLEM_BLAST" and hero.pos in boss.telegraph.cells,"at a hundred it announces a radius-3 blast")
	var hp: int = hero.hp
	BossAI.turn(s,boss)
	check(hero.hp == hp and bool(boss.blasting),"it waits one turn")
	BossAI.turn(s,boss)
	check(hero.hp == hp-24 and int(boss.heat) == 30 and not bool(boss.blasting),"the blast hits for 24 and the heat falls to 30")
	check(int(s.tile(hero.pos).fire) >= 60,"the blast sets the floor alight")
	# A lever floods its own channel.
	d = arena(6,4); s = d.s; boss = d.boss; hero = d.hero
	levers = s.floor_state.features.keys().filter(func(p): return str(s.floor_state.features[p].get("kind","")) == "lever")
	levers.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	var lever: Vector2i = levers[0]
	hero.pos = Fixture.beside(s,lever); s.floor_state.observe(s)
	var number: int = int(s.floor_state.features[lever].channel)
	check(s.act("LEVER",lever),"a lever is pulled")
	var channel_cells: Array = s.floor_state.features.keys().filter(func(p): return str(s.floor_state.features[p].get("kind","")) == "channel" and int(s.floor_state.features[p].channel) == number)
	check(not channel_cells.is_empty() and channel_cells.all(func(p): return int(s.tile(p).wet) >= 90),"its channel runs wet")
	check(not s.act("LEVER",lever),"the same lever needs a while before it works again")
	# Water cools it and cracks its plates.
	d = arena(6,4); s = d.s; boss = d.boss
	boss.statuses["bind"] = int(s.time)+10000
	s.tile(boss.pos).wet = 100; boss.heat = 60
	BossAI.turn(s,boss)
	check(int(boss.heat) == 35 and boss.statuses.has("cracked"),"standing in water: heat −30, then +5, and the plates crack")
	check(int(Stats.stats(s,boss).ac) == 0,"cracked plates give no armour")
	var before: int = boss.hp
	s.damage(boss,10,int(d.hero.id),"physical")
	check(boss.hp == before-13,"a cracked golem takes thirty percent more from blows")
	s.tile(boss.pos).wet = 0
	BossAI.turn(s,boss)
	check(boss.statuses.has("cracked"),"the crack holds a second turn")
	BossAI.turn(s,boss)
	check(not boss.statuses.has("cracked"),"and closes after two")
	# Ice cools it too.
	d = arena(6,4); s = d.s; boss = d.boss; boss.heat = 60
	s.damage(boss,5,int(d.hero.id),"ice")
	check(int(boss.heat) == 30 and boss.statuses.has("cracked"),"ice damage cools the golem")

func eater() -> void:
	var d := arena(9,3); var s = d.s; var boss: Dictionary = d.boss; var hero: Dictionary = d.hero
	hero.hp = 999; hero.max_hp = 999
	var bound: Array = s.enemies.filter(func(e): return int(e.get("bound_to",-1)) == int(boss.id))
	check(bound.size() == 4 and bound.all(func(e): return str(e.species_id) in Eater.ZONE3),"four zone-3 monsters wait in chains")
	check(bound.all(func(e): return int(e.sleep_until) > int(s.time)),"they do not stir before the fight")
	BossAI.turn(s,boss)
	check(bound.all(func(e): return int(e.sleep_until) == 0 and bool(e.alert)),"the fight breaks their chains")
	var near: Dictionary = bound[0]
	boss.hp = 100
	s.damage(near,9999,int(hero.id),"physical")
	check(int(boss.hp) == mini(int(boss.max_hp),100+int(near.max_hp)),"a monster dying close by feeds it its health")
	check(not Abilities.has(str(near.part_id)) or str(near.part_id) in boss.stolen,"and its technique")
	var far: Dictionary = bound[1]
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var cell := Vector2i(x,y)
			if Common.reach(cell,boss.pos) > Eater.ABSORB_REACH and s.is_free(cell): far.pos = cell
	var hp: int = boss.hp
	s.damage(far,9999,int(hero.id),"physical")
	check(boss.hp == hp,"what dies far away is out of its reach")
	boss.stolen = []
	var parts: Array = Abilities.droppable().slice(0,4)
	for part in parts: Eater.absorb(s,boss,{"pos":boss.pos,"max_hp":1,"part_id":part,"name":"시험"})
	check(boss.stolen == parts.slice(1,4),"three techniques at most, the oldest pushed out")
	# The seal: every fourth turn, one essence of one member, for three turns.
	d = arena(9,3); s = d.s; boss = d.boss; hero = d.hero
	hero.hp = 999; hero.max_hp = 999
	hero.level = 2; Essences.sync_slots(hero)
	hero.essences = {"ORC_CLEAVER":1,"GOBLIN_SHIV":1}; hero.equipped_abilities = ["ORC_CLEAVER","GOBLIN_SHIV"]
	StatSheet.refresh_pools(s,hero)
	var attack: int = StatSheet.value(s,hero,"atk")
	boss.turns = 3
	BossAI.turn(s,boss)
	check(str(boss.telegraph.get("kind","")) == "SEAL" and hero.pos in boss.telegraph.cells,"the fourth turn announces a seal")
	BossAI.turn(s,boss)
	check(hero.get("sealed",{}).has("ORC_CLEAVER"),"the first slotted stone is sealed (no tiers to rank)")
	check("ORC_CLEAVER" not in Essences.equipped(hero) and StatSheet.value(s,hero,"atk") < attack,"a sealed essence leaves the stat sheet")
	check(not Abilities.holds(hero,"ORC_CLEAVER"),"and its technique")
	for turn in range(3): BossAI.turn(s,boss)
	check(not hero.get("sealed",{}).has("ORC_CLEAVER") and "ORC_CLEAVER" in Essences.equipped(hero),"three turns later it is free")
	boss.turns = 7; BossAI.turn(s,boss); BossAI.turn(s,boss)
	check(not hero.get("sealed",{}).is_empty(),"sealed again")
	boss.hp = 1; s.damage(boss,999,int(hero.id),"physical")
	check(hero.get("sealed",{}).is_empty(),"its fall frees every seal")

func fallen() -> void:
	# Who falls: the dead first, by how strongly they felt about the hero.
	var s = Session.new_run(11,"sword")
	var hero_id: int = int(s.party[0].id)
	for n in s.roster: n.state = "MET"; n.opinions[hero_id] = 0
	s.roster[2].state = "DEAD"; s.roster[2].opinions[hero_id] = -50
	s.roster[5].state = "DEAD"; s.roster[5].opinions[hero_id] = 20
	check(int(Fallen.pick(s).id) == int(s.roster[2].id),"of the dead, the one who felt most strongly")
	for n in s.roster: n.state = "MET"
	s.roster[4].opinions[hero_id] = -80
	check(int(Fallen.pick(s).id) == int(s.roster[4].id),"with nobody dead, the one outside the party who likes the hero least")
	s.roster = []
	check(not Fallen.pick(s).is_empty() and not s.roster.is_empty(),"with no roster, a new one is made")
	# The fight.
	var d := arena(12,2,2); s = d.s
	var boss: Dictionary = d.boss
	check(bool(boss.get("fallen",false)) and bool(boss.hostile) and bool(boss.npc) and not bool(boss.enemy),"the last boss is a hostile NPC")
	check(int(boss.level) == 10 and Essences.equipped(boss).size() == 10,"level ten, ten essences worn")
	check(int(boss.max_hp) >= 160*6,"at least the zone-4 base times six")
	check(s.stairs_sealed(),"while it lives the stairs stay shut")
	var ally: Dictionary = s.party[1]
	ally.opinions[int(boss.roster_id)] = 40
	var stress: int = int(ally.stress)
	BossAI.turn(s,boss)
	check(int(ally.stress) >= mini(200,stress+40),"a friend of the fallen is shaken")
	check(s.log_lines.any(func(l): return str(l).begins_with(str(boss.name)+": ")),"it speaks when the fight begins")
	check(TagSets.level({"equipped_abilities":["GOBLIN_SHIV","GOBLIN_SHIV@fire"],"essences":{},"set_boost":true},"AMBUSH") == 4,"a boosted two-combo reads as four")
	check(TagSets.level({"equipped_abilities":["GOBLIN_SHIV","GOBLIN_SHIV@fire"],"essences":{}},"AMBUSH") == 2,"an ordinary two-combo stays two")
	boss.hp = int(boss.max_hp)/2-1
	BossAI.turn(s,boss)
	check(bool(boss.set_boost),"below half its sets rise a step")
	var best: String = str(Essences.equipped(boss)[0])
	var count: int = int(s.parts_bag.get(best,0))
	boss.hp = 1
	s.damage(boss,99999,int(d.hero.id),"physical")
	if boss.hp > 0: s.damage(boss,99999,int(d.hero.id),"physical")
	check(int(s.parts_bag.get(best,0)) == count+1,"it leaves its first slotted essence")
	check(s.phase == "VICTORY","its fall wins the run")

func boss_actives() -> void:
	for id in ["GOBLIN_CHIEF","FURNACE_HEART","SOUL_EATER"]:
		check(Abilities.has(id) and not str(Abilities.definition(id).description).is_empty(),"%s has an active" % id)
	var d := arena(3,1); var s = d.s; var hero: Dictionary = d.hero
	var foe: Dictionary = Chief.minions(s,d.boss)[0]
	foe.pos = Fixture.beside(s,hero.pos); s.floor_state.observe(s)
	hero.essences = {"GOBLIN_CHIEF":1}; hero.equipped_abilities = ["GOBLIN_CHIEF"]; hero.cooldowns = {}; hero.ap = 1
	check(Abilities.execute(s,hero,"GOBLIN_CHIEF",foe.pos) and foe.statuses.has("marked"),"지휘 marks a foe")
	var hp: int = foe.hp
	s.damage(foe,10,int(hero.id),"physical")
	check(foe.hp == hp-12,"a marked foe takes twenty percent more")
	hero.essences = {"FURNACE_HEART":1}; hero.equipped_abilities = ["FURNACE_HEART"]; hero.cooldowns = {}; hero.ap = 1
	check(Abilities.execute(s,hero,"FURNACE_HEART",hero.pos) and hero.statuses.has("furnace"),"과열 장갑 goes up")
	check(Abilities.reduction(hero) >= 40,"과열 장갑 turns forty percent aside")
	var burned: int = foe.hp
	hero.statuses.furnace = int(s.time)-1
	s.Statuses.tick(s)
	check(not hero.statuses.has("furnace") and foe.hp < burned,"when it ends it bursts into the cells around")
	hero.essences = {"SOUL_EATER":1}; hero.equipped_abilities = ["SOUL_EATER"]; hero.cooldowns = {}; hero.ap = 1
	check(Abilities.execute(s,hero,"SOUL_EATER",hero.pos) and bool(hero.devour_ready),"영혼 먹기 readies the mouth")
	var part: String = str(foe.part_id)
	s.damage(foe,9999,int(hero.id),"physical")
	check(not Abilities.has(part) or str(hero.borrowed) == part,"the next kill lends its technique")
	check(not Abilities.has(part) or part in Abilities.held(hero),"which the member can use")
	check(not bool(hero.get("devour_ready",false)),"once")
	hero.borrowed = "FROST_IMP"
	check(Abilities.usable_by(hero,"FROST_IMP") and Abilities.holds(hero,"FROST_IMP"),"a borrowed monster-only technique can be used")
