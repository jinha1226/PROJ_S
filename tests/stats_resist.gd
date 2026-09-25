extends SceneTree
## Every number a fight reads, where it came from, and the caps on it.
const Session = preload("res://expedition/run/session.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	attributes()
	defence()
	resistance()
	monsters()
	print("Stats and resistance: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func hero_run():
	var s = Session.new_run(731,"sword")
	return s

func slot(actor: Dictionary, ids: Array, tier: int = 1) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate()
	actor.essences = {}
	for id in ids: actor.essences[id] = tier

func attributes() -> void:
	var s = hero_run(); var hero: Dictionary = s.party[0]
	var sheet: Dictionary = StatSheet.sheet(s,hero)
	for key in StatSheet.KEYS: check(sheet.has(key) and StatSheet.NAMES.has(key),"sheet and names carry "+key)
	check(int(sheet.str.total) == 12 and sheet.str.parts[0].from == "종족","a human's strength is the species' twelve")
	check(int(sheet.con.total) == 10,"constitution starts at ten")
	var sword: Dictionary = Stats.content.weapons.sword
	check(int(Stats.stats(s,hero).damage) == int(sword.damage)+12/6,"a sword hits for its damage plus strength / 6")
	check(int(Stats.stats(s,hero).delay) == int(sword.delay),"no mastery shortens the swing")
	var hp: int = hero.max_hp; var mp: int = hero.max_mp
	slot(hero,["ORC_CLEAVER"]); StatSheet.refresh_pools(s,hero)
	sheet = StatSheet.sheet(s,hero)
	check(int(sheet.str.total) == 14 and sheet.str.parts.any(func(p): return p.from == Essences.title("ORC_CLEAVER") and int(p.value) == 2),"an essence adds strength under its own name")
	check(int(hero.max_hp) == hp+3 and int(hero.hp) == hp+3,"one constitution is three more HP")
	check(int(Stats.stats(s,hero).damage) == int(sword.damage)+14/6,"strength feeds the sword")
	slot(hero,["ORC_CLEAVER"],3); StatSheet.refresh_pools(s,hero)
	check(int(StatSheet.value(s,hero,"str")) == 18 and int(hero.max_hp) == hp+9,"tier three triples the essence")
	slot(hero,[""]); StatSheet.refresh_pools(s,hero)
	check(int(hero.max_hp) == hp and int(hero.hp) <= hp,"taking it off returns the HP")
	slot(hero,["FIRE_CALLER"]); StatSheet.refresh_pools(s,hero)
	check(int(hero.max_mp) == mp+2,"two mind is two more MP")
	check(int(hero.pool_bonus.mp) == 2 and int(hero.pool_bonus.hp) == 0,"the pools remember what they were given")
	slot(hero,["GOBLIN_SHIV"],3)
	check(int(StatSheet.value(s,hero,"ev")) == 18/3+3,"evasion is one per three dexterity plus the stone's own")
	check(StatSheet.legacy_power(hero,"RANGED",10) == 10+2*6,"the old auto path reads essence dexterity")

func defence() -> void:
	var s = hero_run(); var hero: Dictionary = s.party[0]
	check(int(Stats.stats(s,hero).ac) == int(Stats.content.armours.robe.ac),"the robe's armour")
	slot(hero,["HOB_TAUNT"])
	check(int(Stats.stats(s,hero).sh) == 2,"block without a shield is halved")
	hero.gear.shield = {"type":"shield"}
	check(int(Stats.stats(s,hero).sh) == StatSheet.SHIELD_BLOCK+5,"a shield adds its fifteen")
	slot(hero,["HOB_TAUNT","HOB_TAUNT@fire","HOB_TAUNT@ice"],3)
	check(int(Stats.stats(s,hero).sh) == StatSheet.BLOCK_CAP,"block stops at fifty")

func resistance() -> void:
	var s = hero_run(); var hero: Dictionary = s.party[0]
	check(Stats.stats(s,hero).res.has("will"),"the will is a resistance")
	check(int(Stats.content.rings.poison.value) == 80,"the poison ring stops at eighty")
	hero.gear.ring = {"type":"fire"}
	slot(hero,["FIRE_CALLER"],3)
	check(int(Stats.stats(s,hero).res.fire) == StatSheet.RES_CAP,"sixty and thirty stop at eighty")
	var hp: int = hero.hp
	Rules.damage(s,{},hero,100,"fire")
	check(int(hero.hp) == hp-20,"eighty percent of a fire hit is turned")
	slot(hero,["GOBLIN_HEXER"],3)
	Statuses.apply(s,hero,"confuse",1000)
	check(int(hero.statuses.confuse) == int(s.time)+700,"thirty will shortens confusion by thirty percent")
	Statuses.apply(s,hero,"burn",1000)
	check(int(hero.statuses.burn) == int(s.time)+1000,"a burn is not the will's business")
	check(Statuses.resisted_ticks(s,hero,"dominate",100) == 70,"domination is shortened too")

func monsters() -> void:
	var s = hero_run()
	var foe: Dictionary = s.enemies[0]
	foe.ac = 3; foe.ev = 5; foe.sh = 90; foe.res = {"fire":50}
	var values: Dictionary = Stats.stats(s,foe)
	check(int(values.ac) == 3 and int(values.ev) == 5,"a monster's armour and evasion are its own")
	check(int(values.sh) == StatSheet.BLOCK_CAP,"a monster's block stops at fifty too")
	check(int(values.res.fire) == 50 and int(values.res.will) == 0,"a monster's resistances are its own")
	check(StatSheet.sheet(s,foe).ac.parts[0].from == "몬스터","a monster's numbers say so")
