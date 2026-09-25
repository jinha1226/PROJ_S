extends SceneTree
## Family passives (zones spec §2.1): one per family, weapon-neutral, counted
## once however many stones of a family are worn, and monsters have theirs.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Families = preload("res://expedition/combat/families.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog(); movement(); status(); offence(); sustain(); defence(); vision(); monsters()
	print("Family passives: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
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
	check(Families.PASSIVES.size() == 10,"ten family passives")
	for family in ["rat","goblin","reptile","kobold","orc","elemental","insect","gnoll","undead","bat"]:
		check(Families.PASSIVES.has(family) and not str(Families.PASSIVES[family].name).is_empty(),"%s has a named passive" % family)
	var actor := {"level":3,"essences":{},"equipped_abilities":["RAT_GNAW","RIVER_RAT_SPLASH","GOBLIN_SHIV"]}
	check(Families.of(actor) == ["rat","goblin"],"a member's families, each once")
	check(Families.of({"enemy":true,"species_id":"goblin_shield"}) == ["goblin"],"a monster has its species' family")

func movement() -> void:
	var d := duo(); var s = d.s
	var cell: Vector2i = d.c+Vector2i(-1,0)
	var plain: int = Rules.move_time(s,d.hero,cell)
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH"])
	check(Rules.move_time(s,d.hero,cell) == plain-10,"날랜 발: ten off a step, not twenty for two rat stones")
	slot(d.hero,["GOBLIN_SHIV"])
	Families.battle_start(s)
	check(Families.first_action_delay(d.hero,100) == 70 and Families.first_action_delay(d.hero,100) == 100,"선수: the first action of a fight is thirty quicker, only the first")
	slot(d.ally,[])
	check(Families.first_action_delay(d.ally,100) == 100,"no goblin, no head start")

func status() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL"])
	Statuses.apply(s,d.hero,"slow",100)
	check(int(d.hero.statuses.slow) == int(s.time)+70,"탈피: a status lasts thirty percent shorter")

func offence() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["KOBOLD_SLING"])
	check(Families.outgoing(s,d.hero,d.foe,20) == 20,"비열 waits for a wounded target")
	d.foe.hp = 19
	check(Families.outgoing(s,d.hero,d.foe,20) == 22 and Passives.outgoing(s,d.hero,d.foe,20) == 22,"비열: ten percent more under half, through the hook")
	slot(d.hero,["ORC_CLEAVER"])
	d.hero.cooldowns = {"ORC_CLEAVER":3}
	d.foe.hp = 1
	s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(int(d.hero.cooldowns.ORC_CLEAVER) == 2,"전투 광기: a kill takes a round off every cooldown")

func sustain() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["ORE_SLAM"])
	d.hero.mp = 5
	Passives.round_start(s,d.hero)
	check(int(d.hero.mp) == 6,"마력 샘: one MP a round")
	slot(d.hero,["GNOLL_SPEAR"])
	d.hero.hp = 20
	Passives.round_start(s,d.hero)
	check(int(d.hero.hp) == 22,"재생: two HP a round")
	d.hero.hp = int(d.hero.max_hp)-1
	Passives.round_start(s,d.hero)
	check(int(d.hero.hp) == int(d.hero.max_hp),"never past the maximum")

func defence() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SPIDER_WEB"])
	check(StatSheet.sheet(s,d.hero).ac.parts.any(func(p): return p.from == "계열" and int(p.value) == 2),"껍질: armour two, under 계열")
	slot(d.hero,["GHOUL_CLAW"])
	Families.battle_start(s)
	d.hero.hp = 10
	s.damage(d.hero,50,int(d.foe.id),"IMPACT")
	check(int(d.hero.hp) == 1,"불사: the first killing blow leaves one")
	s.damage(d.hero,50,int(d.foe.id),"IMPACT")
	check(int(d.hero.hp) <= 0,"the second one does not")

func vision() -> void:
	var d := duo()
	slot(d.hero,["STORM_BAT"])
	check(Families.vision_bonus(d.hero) == 2 and Families.ignores_fog(d.hero),"초음파: two more sight, and fog does not blind")
	slot(d.hero,[])
	check(Families.vision_bonus(d.hero) == 0 and not Families.ignores_fog(d.hero),"no bat, no echo")

func monsters() -> void:
	var d := duo(); var s = d.s
	d.foe.species_id = "dcss_gnoll"; d.foe.hp = 20
	Passives.round_start(s,d.foe)
	check(int(d.foe.hp) == 22,"a gnoll monster regenerates")
	d.foe.species_id = "rock_beetle"
	check(StatSheet.sheet(s,d.foe).ac.parts.any(func(p): return p.from == "계열"),"a beetle monster has its shell")
	d.foe.species_id = "ghoul"; d.foe.hp = 5
	Families.battle_start(s)
	s.damage(d.foe,50,int(d.hero.id),"SLASH")
	check(int(d.foe.hp) == 1,"an undead monster stands once")
