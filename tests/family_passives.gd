extends SceneTree
## The family passives are gone (2026-09-26 soul stone spec §5): no step, first
## action, status, armour, regeneration, mana, undying or echo bonus from a
## family any more — the headline effects took their place. The family field
## stays on every stone for its emblem.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Hazards = preload("res://expedition/level/hazards.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog(); movement(); status(); offence(); sustain(); defence(); vision(); monsters()
	StoneEffects.force = -1
	print("Family passives: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	StoneEffects.force = 99
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""; foe.res = {}; foe.statuses = {}
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func catalog() -> void:
	check(not FileAccess.file_exists("res://expedition/combat/families.gd"),"the family passive module is deleted")
	var families: Array = []
	for id in Essences.content.rows: families.append(Essences.family(str(id)))
	for family in ["rat","goblin","reptile","kobold","orc","elemental","insect","gnoll","undead","bat"]:
		check(family in families,"%s still marks its stones' emblem" % family)
	check(Essences.family("RAT_GNAW") == "rat","a stone keeps its family field")
	check(Essences.family("RAT_GNAW@fire") == "rat","and so does its variant")

func movement() -> void:
	var d := duo(); var s = d.s
	var cell: Vector2i = d.c+Vector2i(-1,0)
	var plain: int = Rules.move_time(s,d.hero,cell)
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH"])
	check(Rules.move_time(s,d.hero,cell) == plain,"날랜 발 is gone: a rat stone takes nothing off a step")
	slot(d.hero,["GOBLIN_SHIV"])
	var cost: int = int(s.action_cost(d.hero,"WAIT",d.hero.pos))
	s.start_battle()
	check(int(s.action_cost(d.hero,"WAIT",d.hero.pos)) == cost,"선수 is gone: no head start in a fight")
	check(not d.hero.has("first_acted"),"nobody keeps a first-action flag")

func status() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL"])
	Statuses.apply(s,d.hero,"slow",100)
	check(int(d.hero.statuses.slow) == int(s.time)+100,"탈피 is gone: a reptile stone shortens no status")

func offence() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["KOBOLD_SLING"])
	d.foe.hp = 19
	check(Passives.outgoing(s,d.hero,d.foe,20) == 20,"비열 is gone: a wounded foe beside takes it plain")
	slot(d.hero,["ORC_CLEAVER"])
	check(Passives.outgoing(s,d.hero,d.foe,20) == 24,"an orc stone's attack comes from its headline effect")
	d.hero.cooldowns = {"ORC_CLEAVER":3}
	d.foe.hp = 1
	s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(int(d.hero.cooldowns.ORC_CLEAVER) == 3,"전투 광기 is gone: a kill keeps the cooldowns")

func sustain() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["ORE_SLAM"])
	d.hero.mp = 5
	Passives.round_start(s,d.hero)
	check(int(d.hero.mp) == 5,"마력 샘 is gone: no MP a round")
	slot(d.hero,["GNOLL_SPEAR"])
	d.hero.hp = 20
	Passives.round_start(s,d.hero)
	check(int(d.hero.hp) == 20,"재생 is gone: no HP a round")
	slot(d.hero,["WATER_WAVE"])
	Passives.round_start(s,d.hero)
	check(int(d.hero.hp) == 20+maxi(1,int(d.hero.max_hp)*3/100),"the round's healing is 물의 정령's now")

func defence() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SPIDER_WEB"])
	check(not StatSheet.sheet(s,d.hero).ac.parts.any(func(p): return p.from == "계열"),"껍질 is gone: no family armour")
	slot(d.hero,["GHOUL_CLAW"])
	s.start_battle()
	d.hero.hp = 10
	s.damage(d.hero,50,int(d.foe.id),"IMPACT")
	check(int(d.hero.hp) <= 0,"불사 is gone: an undead stone stands nothing")
	d.hero.hp = 10
	slot(d.hero,["GRAVEKEEPER"])
	s.start_battle()
	s.damage(d.hero,50,int(d.foe.id),"IMPACT")
	check(int(d.hero.hp) == int(d.hero.max_hp)*30/100,"the stand is 묘지기's now, at thirty percent")

func vision() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["STORM_BAT"])
	s.tile(d.hero.pos).fog = true
	check(Hazards.sight_radius(s,d.hero,5.0) < 5.0,"초음파 is gone: fog blinds a bat stone too")
	s.tile(d.hero.pos).fog = false
	check(Hazards.sight_radius(s,d.hero,5.0) == 5.0,"and it lends no extra sight")

func monsters() -> void:
	var d := duo(); var s = d.s
	d.foe.species_id = "dcss_gnoll"; d.foe.hp = 20
	Passives.round_start(s,d.foe)
	check(int(d.foe.hp) == 20,"a gnoll monster no longer regenerates")
	d.foe.species_id = "rock_beetle"
	check(not StatSheet.sheet(s,d.foe).ac.parts.any(func(p): return p.from == "계열") and Passives.incoming(s,d.foe,20) == 17,"a beetle monster has its stone's 껍질 instead: fifteen percent less")
	d.foe.species_id = "ghoul"; d.foe.hp = 5
	s.start_battle()
	s.damage(d.foe,50,int(d.hero.id),"SLASH")
	check(int(d.foe.hp) <= 0,"an undead monster no longer stands once")
