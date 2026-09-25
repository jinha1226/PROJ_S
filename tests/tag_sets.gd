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
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 11,"무리 3 keeps the adjacent ally bonus")
	check(Passives.outgoing(s,d.hero,d.foe,10) == 11,"the passive hook reads the set")
	check(TagSets.incoming(s,d.hero,5) == 5 and Passives.incoming(s,d.hero,5) == 5,"the set no longer cuts incoming damage")
	check(TagSets.outgoing(s,d.foe,d.hero,10) == 10,"a monster wears no set")

func ambush() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"기습 2: a fresh foe takes thirty percent more")
	d.foe.hp = 39
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"a wounded foe does not")
	check(not d.hero.statuses.has("poised"),"기습 2 has no prepared critical")
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"])
	TagSets.on_dodge(s,d.hero,d.foe)
	check(d.hero.statuses.has("poised"),"기습 3 readies a critical after dodging")
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 15 and not d.hero.statuses.has("poised"),"the next blow spends the critical")

func elements() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@fire","HOB_TAUNT@fire"])
	Rules.damage(s,d.hero,d.foe,10,"fire")
	check(int(d.foe.hp) == 25,"화염 2: fire gets its damage bonus and the set's extra fire")
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"ice")
	check(int(d.foe.hp) == 27,"another element keeps its base damage but still adds set fire")
	slot(d.hero,["LIZARD_TAIL@fire","HOB_TAUNT@fire","RAT_GNAW@fire"])
	check(TagSets.level(d.hero,"fire") == 3,"화염 3 enables the on-hit burn reaction")
	slot(d.hero,["LIZARD_TAIL@air","HOB_TAUNT@air","RAT_GNAW@air"])
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
	slot(d.hero,["HOB_TAUNT","SHIELD_STANCE","HOB_TAUNT@fire"])
	check(int(TagSets.stat_bonus(d.hero).ac) == 2 and int(TagSets.stat_bonus(d.hero).sh) == 5,"수호 3 keeps its armour and block")
	check(not TagSets.stat_bonus(d.ally).has("ac"),"the set belongs to the wearer")
	d.ally.pos = d.c+Vector2i(0,4)
	check(not TagSets.stat_bonus(d.ally).has("ac"),"distance does not lend the set to an ally")
