extends SceneTree
## What the sets do in a fight: every role combo bracket and element step,
## wired into the hooks the fight already runs (2026-09-26 soul stone spec §3).
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
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
	StoneEffects.force = -1
	print("Tag sets: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally beside at c+(0,1), a fresh foe at c+(1,0) with no part.
func duo() -> Dictionary:
	StoneEffects.force = 99
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
	slot(d.hero,["RIVER_RAT_SPLASH","RIVER_RAT_SPLASH@ice"])
	check(Passives.outgoing(s,d.hero,d.foe,10) == 11,"무리 2: attack +10%")
	slot(d.hero,["RIVER_RAT_SPLASH","RIVER_RAT_SPLASH@ice","RIVER_RAT_SPLASH@fire"])
	check(Passives.outgoing(s,d.hero,d.foe,10) == 11,"무리 3 is still the two bracket")
	check(Passives.outgoing(s,d.ally,d.foe,10) == 11,"the whole party reads it through the hook")
	check(TagSets.incoming(s,d.hero,5) == 5 and Passives.incoming(s,d.hero,5) == 5,"the combo does not cut incoming damage")
	check(Passives.outgoing(s,d.foe,d.hero,10) == 10,"a monster wears no combo")

func ambush() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SPIDER_WEB","SPIDER_WEB@fire"])
	check(Passives.outgoing(s,d.hero,d.foe,10) == 10,"기습 2 no longer adds thirty percent to a fresh foe")
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 10,"기습 2: ten percent critical instead")
	check(not d.hero.statuses.has("poised"),"기습 has no prepared critical")
	slot(d.hero,["SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice"])
	Rules.attack(s,d.foe,d.hero)
	check(not d.hero.statuses.has("poised"),"a dodge readies nothing any more")
	d.foe.hp = 39
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 10 and Passives.outgoing(s,d.hero,d.foe,10) == 10,"three stones are the two bracket")

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
	slot(d.hero,["LIZARD_TAIL@air","HOB_TAUNT@air","SPIDER_WEB@air"])
	d.foe.hp = 39
	s.tile(d.foe.pos).wet = 50
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"전기 3: a wet foe takes thirty percent more")
	s.tile(d.foe.pos).wet = 0
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"a dry one does not")
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER"])
	check(TagSets.status_ticks(d.hero,"confuse",100) == 130 and TagSets.status_ticks(d.hero,"burn",100) == 100,"의지 2 lengthens the hex statuses only")
	d.foe.statuses = {}
	Spells.strike(s,d.hero,d.foe,{"school":"hex","status":"confuse","element":"physical"},0,0,100)
	check(int(d.foe.statuses.get("confuse",0)) == int(s.time)+195,"and a spell carries it, with the hexer's half again on top")

func berserk() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL","GHOUL_CLAW"])
	var cost: int = int(s.action_cost(d.hero,"ATTACK",d.foe.pos))
	check(cost == int(Stats.stats(s,d.hero).delay),"광폭 2 cuts no delay any more")
	d.hero.hp = int(d.hero.max_hp)/2-1
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == cost,"not even wounded")
	check(Passives.outgoing(s,d.hero,d.foe,20) == 23,"광폭 2: attack +15%")
	slot(d.hero,["LIZARD_TAIL","LIZARD_TAIL@fire","LIZARD_TAIL@ice","LIZARD_TAIL@air"])
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == cost*80/100,"광폭 4: wounded, a fifth quicker")

func archer() -> void:
	var d := duo(); var s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	var bow: Dictionary = Stats.content.weapons.bow
	slot(d.hero,["TOAD_SPIT","TOAD_SPIT@ice"])
	check(int(Stats.stats(s,d.hero).range) == int(bow.range)+1,"사수 2: a bow reaches one farther")
	slot(d.hero,["TOAD_SPIT","TOAD_SPIT@ice","TOAD_SPIT@fire"])
	var speed: int = StatSheet.value(s,d.hero,"speed")
	check(speed == 15,"three archer stones: fifteen percent speed from their base stats")
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == int(bow.delay)*(100-speed)/100,"사수 3's quicker draw is gone; only the speed remains")
	d.foe.pos = d.c+Vector2i(3,0)
	check(Passives.outgoing(s,d.hero,d.foe,20) == 20,"사수 2·3 add no ranged damage")

func casters() -> void:
	var d := duo(); var s = d.s
	var mp: int = d.hero.max_mp
	slot(d.hero,["FIRE_CALLER","FROST_IMP"]); StatSheet.refresh_pools(s,d.hero)
	check(int(d.hero.max_mp) == mp+8+8,"two caster stones: eight MP each, no set MP any more")

func guard() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["HOB_TAUNT","SHIELD_STANCE","HOB_TAUNT@fire"])
	check(int(TagSets.stat_bonus(d.hero).ac) == 3 and not TagSets.stat_bonus(d.hero).has("sh"),"수호 3 is the two bracket: armour three, no block")
	check(not TagSets.stat_bonus(d.ally).has("ac"),"the combo belongs to the wearer")
	d.ally.pos = d.c+Vector2i(0,4)
	check(not TagSets.stat_bonus(d.ally).has("ac"),"distance does not lend it to an ally")
