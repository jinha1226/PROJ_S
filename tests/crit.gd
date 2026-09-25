extends SceneTree
## Critical hits (2026-09-26 spec §2.1): the chance adds up from the headline
## effect and the 기습 combo, a critical is ×1.5 plus fifty points from each of
## 해골 궁수 and 기습 4·6, and only weapon attacks and actives can be one.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Spells = preload("res://expedition/spells/spells.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	chances(); multipliers(); damage(); not_spells(); not_secondary(); monsters()
	StoneEffects.force = -1
	print("Crit: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	StoneEffects.force = -1
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 399; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	d_ally_away(s,c)
	s.floor_state.observe(s)
	s.effects.clear()
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func d_ally_away(s, c: Vector2i) -> void:
	s.party[1].pos = c+Vector2i(-4,0)

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func hit(s, from: Dictionary, to: Dictionary, amount: int, form: String = "SLASH") -> int:
	var before: int = int(to.hp)
	s.Reactions.begin_action(s)
	s.damage(to,amount,int(from.id),form)
	return before-int(to.hp)

func crits(s) -> int:
	return s.effects.filter(func(e): return str(e.get("kind","")) == "PROC" and str(e.get("text","")) == "치명타!").size()

func chances() -> void:
	var d := duo(); var s = d.s
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 0,"no stone, no critical")
	slot(d.hero,["SKELETON_VOLLEY"])
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 15,"해골 궁수 alone: 15")
	slot(d.hero,["SKELETON_VOLLEY","SPIDER_WEB","SPIDER_WEB@fire"])
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 25,"with 기습 2: 25")
	slot(d.hero,["SKELETON_VOLLEY","SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice","SPIDER_WEB@air"])
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 35,"with 기습 4: 35")
	slot(d.hero,["SKELETON_VOLLEY","SKELETON_VOLLEY@fire"])
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 15,"two 해골 궁수 stones are one effect")

func multipliers() -> void:
	var d := duo()
	slot(d.hero,["SPIDER_WEB","SPIDER_WEB@fire"])
	check(StoneEffects.crit_percent(d.hero) == 150,"a plain critical is ×1.5")
	slot(d.hero,["SKELETON_VOLLEY"])
	check(StoneEffects.crit_percent(d.hero) == 200,"해골 궁수: +50%p")
	slot(d.hero,["SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice","SPIDER_WEB@air"])
	check(StoneEffects.crit_percent(d.hero) == 200,"기습 4: +50%p")
	slot(d.hero,["SKELETON_VOLLEY","SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice","SPIDER_WEB@air"])
	check(StoneEffects.crit_percent(d.hero) == 250,"both: +100%p")

func damage() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SKELETON_VOLLEY"])
	StoneEffects.force = 99
	check(hit(s,d.hero,d.foe,10) == 10 and crits(s) == 0,"a failed roll is a plain blow")
	StoneEffects.force = 0
	check(hit(s,d.hero,d.foe,10) == 20 and crits(s) == 1,"a weapon blow crits")
	check(s.log_lines.filter(func(l): return str(l).contains("치명타")).size() == 1,"one line in the log")
	check(hit(s,d.hero,d.foe,10,"IMPACT") == 20,"an active crits too")
	check(hit(s,d.hero,d.foe,10,"physical") == 20,"so does a landed weapon hit")
	slot(d.hero,["SKELETON_VOLLEY","SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice","SPIDER_WEB@air"])
	check(hit(s,d.hero,d.foe,10) == 25,"the multipliers add up")
	slot(d.hero,[])
	check(hit(s,d.hero,d.foe,10) == 10,"no chance, no critical however the roll falls")

func not_spells() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SKELETON_VOLLEY"])
	StoneEffects.force = 0
	var before: int = int(d.foe.hp)
	Spells.strike(s,d.hero,d.foe,{"school":"fire","element":"fire","status":""},10,0,0)
	check(before-int(d.foe.hp) == 10 and crits(s) == 0,"a spell never crits")
	before = int(d.foe.hp)
	Spells.strike(s,d.hero,d.foe,{"school":"hex","element":"physical","status":""},10,0,0)
	check(before-int(d.foe.hp) == 10,"not even a physical one")
	check(int(s.casting) == 0,"the spell flag is down again")

func not_secondary() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SKELETON_VOLLEY"])
	StoneEffects.force = 0
	for form in ["REACTION","COUNTER","RETALIATE","EXTRA"]:
		check(hit(s,d.hero,d.foe,10,form) == 10,"%s damage never crits" % form)
	check(crits(s) == 0,"and raises no notice")
	var before: int = int(d.foe.hp)
	s.Reactions.react_damage(s,d.hero,d.foe,10,"physical")
	check(before-int(d.foe.hp) == 10,"a reaction's damage stays plain")

func monsters() -> void:
	var d := duo(); var s = d.s
	d.foe.part_id = "SKELETON_VOLLEY"
	check(StoneEffects.crit_chance(s,d.foe,d.hero) == 15 and StoneEffects.crit_percent(d.foe) == 200,"a skeleton archer crits like its stone")
	StoneEffects.force = 0
	check(hit(s,d.foe,d.hero,10) == 20,"and hits that hard")
	d.foe.part_id = "SPIDER_WEB"
	check(StoneEffects.crit_chance(s,d.foe,d.hero) == 0,"a monster has no 기습 combo")
