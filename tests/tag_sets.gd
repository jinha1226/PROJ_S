extends SceneTree
## What the sets do in a fight: every role and element step, wired into the
## hooks the fight already runs.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Spells = preload("res://expedition/spells/spells.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	pack(); ambush(); elements(); berserk(); archer(); casters(); guard()
	print("Tag sets: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally beside at c+(0,1), a fresh foe at c+(1,0) with no part.
func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func pack() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 11,"무리 2: one more per adjacent ally")
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH","RAT_GNAW@ice"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 12,"무리 3: two more per adjacent ally")
	check(Passives.outgoing(s,d.hero,d.foe,10) == 13,"the passives run the set too (rat passive +1, set +2)")
	check(TagSets.incoming(s,d.hero,5) == 4 and Passives.incoming(s,d.hero,5) == 4,"무리 3: one less taken")
	check(TagSets.outgoing(s,d.foe,d.hero,10) == 10,"a monster wears no set")

func ambush() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"기습 2: a fresh foe takes thirty percent more")
	d.foe.hp = 39
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"a wounded foe does not")
	check(not TagSets.sure_hit(d.hero,d.foe),"기습 2 is no sure hit")
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"])
	check(int(StatSheet.value(s,d.hero,"ev")) >= 5 and StatSheet.sheet(s,d.hero).ev.parts.any(func(p): return p.from == "세트" and int(p.value) == 5),"기습 3 lends evasion")
	d.foe.sh = 100
	var clean := true
	for i in range(20):
		d.foe.hp = 40; d.foe.statuses = {}
		var out: Dictionary = Rules.attack(s,d.hero,d.foe)
		if bool(out.get("evaded",false)) or bool(out.get("blocked",false)): clean = false
	check(clean,"기습 3: the first blow on a fresh foe always lands")

func elements() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@fire","HOB_CLUB@fire"])
	Rules.damage(s,d.hero,d.foe,10,"fire")
	check(int(d.foe.hp) == 28,"화염 2: fire hits a fifth harder")
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"ice")
	check(int(d.foe.hp) == 30,"and only fire")
	slot(d.hero,["LIZARD_TAIL@fire","HOB_CLUB@fire","RAT_GNAW@fire"])
	var burns := 0
	for i in range(80):
		d.foe.hp = 40; d.foe.statuses = {}
		TagSets.on_hit(s,d.hero,d.foe)
		if d.foe.statuses.has("burn"): burns += 1
	check(burns > 0 and burns < 80,"화염 3: some blows set a burn (%d of 80)" % burns)
	slot(d.hero,["LIZARD_TAIL@air","HOB_CLUB@air","RAT_GNAW@air"])
	d.foe.hp = 39
	s.tile(d.foe.pos).wet = 50
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"전기 3: a wet foe takes thirty percent more")
	s.tile(d.foe.pos).wet = 0
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"a dry one does not")
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER"])
	check(TagSets.status_ticks(d.hero,"confuse",100) == 130 and TagSets.status_ticks(d.hero,"burn",100) == 100,"의지 2 lengthens the hex statuses only")
	d.foe.statuses = {}
	Spells.strike(s,d.hero,d.foe,{"school":"hex","status":"confuse","element":"physical"},0,0,100)
	check(int(d.foe.statuses.get("confuse",0)) == int(s.time)+130,"and a spell carries it")

func berserk() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["ORC_CLEAVER","GNOLL_SPEAR"])
	check(TagSets.attack_delay(d.hero,120,false) == 120,"광폭 2 waits for the wound")
	d.hero.hp = int(d.hero.max_hp)/2-1
	check(TagSets.attack_delay(d.hero,120,false) == 105,"광폭 2: a wounded swing is quicker")
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == int(Stats.stats(s,d.hero).delay)-15,"the session's attack cost reads it")
	slot(d.hero,["ORC_CLEAVER","GNOLL_SPEAR","ORC_CLEAVER@fire"])
	d.hero.hp = 20; d.foe.hp = 1
	s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(int(d.foe.hp) <= 0 and int(d.hero.hp) == 25,"광폭 3: a kill heals five")

func archer() -> void:
	var d := duo(); var s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	var bow: Dictionary = Stats.content.weapons.bow
	slot(d.hero,["KOBOLD_SLING","KOBOLD_SLING@ice"])
	check(int(Stats.stats(s,d.hero).range) == int(bow.range)+1,"사수 2: a bow reaches one farther")
	slot(d.hero,["KOBOLD_SLING","KOBOLD_SLING@ice","KOBOLD_SLING@fire"])
	check(TagSets.attack_delay(d.hero,int(bow.delay),true) == int(bow.delay)-15,"사수 3: a quicker draw")
	check(TagSets.attack_delay(d.hero,120,false) == 120,"but not for a sword")
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == int(bow.delay)-15,"the session's attack cost reads it")

func casters() -> void:
	var d := duo(); var s = d.s
	var mp: int = d.hero.max_mp
	slot(d.hero,["FIRE_CALLER","FROST_IMP"]); StatSheet.refresh_pools(s,d.hero)
	check(int(d.hero.max_mp) == mp+2+2+5,"술사 2: five more MP on top of the mind")

func guard() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL","HOB_CLUB","LIZARD_TAIL@fire"])
	check(StatSheet.sheet(s,d.ally).ac.parts.any(func(p): return p.from == "수호 세트" and int(p.value) == 2),"수호 3 covers the adjacent ally")
	check(not StatSheet.sheet(s,d.hero).ac.parts.any(func(p): return p.from == "수호 세트"),"but not the wearer")
	d.ally.pos = d.c+Vector2i(0,4)
	check(not StatSheet.sheet(s,d.ally).ac.parts.any(func(p): return p.from == "수호 세트"),"nor an ally out of reach")
