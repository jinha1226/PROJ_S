extends SceneTree
## The three build axes: weapon × role combo × element set. Element sets ride
## on every hit, bleeding is an element tag, and the old role set triggers
## are replaced by the 2·4·6 role combos.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Passives = preload("res://expedition/combat/passives.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	bleed_tag(); extras(); procs(); roles()
	print("Build axes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0; foe.ac = 0
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func bleed_tag() -> void:
	check(Essences.ELEMENTS.has("bleed") and Essences.ELEMENTS.bleed == "출혈","bleeding is the sixth element tag")
	check(Essences.has("GOBLIN_SHIV@bleed") and Essences.element("GOBLIN_SHIV@bleed") == "bleed","a bleed variant is an essence")
	check(not (Essences.row("GOBLIN_SHIV@bleed").stats as Dictionary).keys().any(func(k): return str(k).begins_with("res_")),"bleeding has no resistance to add")
	check(TagSets.TEXT.has("bleed") and TagSets.TEXT.bleed.has(2) and TagSets.TEXT.bleed.has(3),"the bleed set is described")
	var bleeder := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_SHIV@bleed","RAT_GNAW@bleed"]}
	check(TagSets.level(bleeder,"bleed") == 2 and not TagSets.stat_bonus(bleeder).keys().any(func(k): return str(k).begins_with("res_")),"a bleed set grants no resistance")
	for element in ["fire","ice","air","poison","will"]:
		var pair := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_SHIV@"+element,"RAT_GNAW@"+element]}
		check(int(TagSets.stat_bonus(pair).get("res_"+element,0)) == 20,"%s 2 gives twenty resistance" % element)
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV@bleed","RAT_GNAW@bleed"])
	d.foe.hp = 30
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"출혈 2 needs a bleeding target")
	d.foe.statuses["bleed"] = s.time+200
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 12,"출혈 2: a bleeding target takes a fifth more")

func extras() -> void:
	# 화염 2 puts three more fire on every hit: a sword, an active, a spell.
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@fire","HOB_TAUNT@fire"])
	var landed := false
	for attempt in range(30):
		d.foe.hp = 40; d.foe.statuses = {}
		Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.hero,d.foe)
		if not bool(out.hit): continue
		landed = true
		check(40-int(d.foe.hp) == int(out.damage)+Reactions.EXTRA_DAMAGE,"a sword blow carries three fire")
		break
	check(landed,"the sword lands within thirty tries")
	d.foe.hp = 40
	s.damage(d.foe,10,int(d.hero.id),"IMPACT")
	check(int(d.foe.hp) == 40-10-3,"an active's blow carries it")
	d.foe.hp = 40
	Spells.strike(s,d.hero,d.foe,{"school":"ice","element":"ice"},10,0,0)
	check(int(d.foe.hp) == 40-10-3,"an ice spell carries three fire too")
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"fire")
	check(int(d.foe.hp) == 40-12-3,"a fire hit is a fifth stronger and still carries three")
	d.foe.hp = 40; d.foe.statuses = {"burn":s.time+100}; d.foe.get_or_add("status_power",{})["burn"] = 4
	Statuses.tick(s)
	check(int(d.foe.hp) == 36,"a burn ticking carries nothing: it is no hit")
	d.foe.hp = 40
	Reactions.react_damage(s,d.hero,d.foe,5,"poison")
	check(int(d.foe.hp) == 35,"reaction damage carries nothing")
	d.foe.hp = 40; d.foe.res = {"fire":50}
	Rules.damage(s,d.hero,d.foe,10,"physical")
	check(int(d.foe.hp) == 40-10-1,"the extra fire meets the target's fire resistance")
	d.foe.res = {}
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER"])
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"physical")
	check(int(d.foe.hp) == 30,"의지 2 carries no extra damage")

func procs() -> void:
	var table := {"fire":["burn",["LIZARD_TAIL@fire","HOB_TAUNT@fire","RAT_GNAW@fire"]],
		"ice":["freeze",["LIZARD_TAIL@ice","HOB_TAUNT@ice","RAT_GNAW@ice"]],
		"poison":["poison",["LIZARD_TAIL@poison","HOB_TAUNT@poison","RAT_GNAW@poison"]],
		"will":["confuse",["GOBLIN_HEXER","GNOLL_SUMMONER","RAT_GNAW@will"]],
		"bleed":["bleed",["GOBLIN_SHIV@bleed","RAT_GNAW@bleed","HOB_TAUNT@bleed"]]}
	for element in table:
		var d := duo(); var s = d.s
		slot(d.hero,table[element][1])
		var status: String = table[element][0]
		var landed := 0
		for i in range(120):
			d.foe.hp = 40; d.foe.statuses = {}
			Reactions.begin_action(s)
			Reactions.on_hit(s,d.hero,d.foe,"physical",5,"HIT")
			if d.foe.statuses.has(status): landed += 1
		check(landed > 0 and landed < 60,"%s 3: some hits hang %s (%d of 120)" % [element,status,landed])
		var from_extras := 0
		for i in range(60):
			d.foe.hp = 40; d.foe.statuses = {}
			Reactions.begin_action(s)
			Reactions.on_hit(s,d.hero,d.foe,"physical",5,"EXTRA")
			if d.foe.statuses.has(status): from_extras += 1
		check(from_extras == 0,"%s 3: an extra hit carries no proc" % element)
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@air","HOB_TAUNT@air","RAT_GNAW@air"])
	d.foe.hp = 39
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"전기 3 needs a wet target")
	d.foe.statuses["wet"] = s.time+200
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"전기 3: a wet target takes thirty percent more")

func roles() -> void:
	StoneEffects.force = 99
	# 기습: a critical chance now; a dodge readies nothing.
	var d := duo(); var s = d.s
	slot(d.hero,["SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice"])
	check(not TagSets.stat_bonus(d.hero).has("ev"),"기습 3 lends no evasion any more")
	var dodged := false
	for attempt in range(80):
		d.hero.hp = int(d.hero.max_hp); d.hero.statuses = {}
		Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.foe,d.hero)
		if bool(out.evaded): dodged = not d.hero.statuses.has("poised"); break
	check(dodged,"a real dodge readies nothing any more")
	d.foe.hp = 30
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 10,"기습 3 is the two bracket: ten percent critical")
	check(Passives.outgoing(s,d.hero,d.foe,10) == 10,"and the next blow carries no stored critical")
	slot(d.hero,["SPIDER_WEB","SPIDER_WEB@fire","SPIDER_WEB@ice","SPIDER_WEB@air"])
	check(StoneEffects.crit_percent(d.hero) == 200,"기습 4: critical damage +50%p")
	# 수호: armour and block by bracket; a block strikes nothing back.
	d = duo(); s = d.s
	slot(d.hero,["HOB_TAUNT","HOB_TAUNT@fire","HOB_TAUNT@ice"])
	d.hero.gear.shield = {"type":"shield"}
	var blocked := false
	for attempt in range(80):
		d.hero.hp = int(d.hero.max_hp)
		Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.foe,d.hero)
		if bool(out.blocked): blocked = int(d.foe.hp) == 40; break
	check(blocked,"a real block no longer strikes back")
	check(int(TagSets.stat_bonus(d.hero).ac) == 3,"수호 3 is the two bracket: armour three")
	check(StatSheet.sheet(s,d.ally).ac.parts.all(func(p): return p.from != "수호 세트" and p.from != "세트"),"수호 lends the ally no armour")
	slot(d.hero,["HOB_TAUNT","HOB_TAUNT@fire","HOB_TAUNT@ice","HOB_TAUNT@air"])
	check(int(TagSets.stat_bonus(d.hero).ac) == 6 and int(TagSets.stat_bonus(d.hero).sh) == 10,"수호 4: armour six, block ten")
	slot(d.hero,["HOB_TAUNT","HOB_TAUNT@fire","HOB_TAUNT@ice","HOB_TAUNT@air","HOB_TAUNT@poison","HOB_TAUNT@bleed"])
	check(Passives.incoming(s,d.ally,20) == 17,"수호 6: the ally beside takes fifteen percent less")
	# 광폭 3: no heal on a kill, and no family takes a cooldown off.
	d = duo(); s = d.s
	slot(d.hero,["ORC_CLEAVER","GNOLL_SPEAR","ORC_CLEAVER@fire"])
	d.hero.hp = 20; d.hero.cooldowns = {"X":3}; d.foe.hp = 1
	s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(int(d.hero.hp) == 20 and int(d.hero.cooldowns.X) == 3,"광폭 3 heals nothing on a kill and cuts no cooldown")
	# 사수 3: no bonus for a statused target; only 코볼트's own +25% at range.
	d = duo(); s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	slot(d.hero,["KOBOLD_SLING","KOBOLD_SLING@ice","KOBOLD_SLING@fire"])
	d.foe.pos = d.c+Vector2i(3,0); d.foe.hp = 30
	check(Passives.outgoing(s,d.hero,d.foe,20) == 25,"사수 3 adds nothing at range: only 코볼트's +25%")
	d.foe.statuses["wet"] = s.time+200
	check(Passives.outgoing(s,d.hero,d.foe,20) == 25,"being wet changes nothing")
	d.foe.statuses["slow"] = s.time+200
	check(Passives.outgoing(s,d.hero,d.foe,20) == 25,"nor does a slowed target")
	d.foe.pos = d.c+Vector2i(1,0)
	check(Passives.outgoing(s,d.hero,d.foe,20) == 20,"and point-blank it is plain")
	# 술사 3: reactions bite as hard as ever.
	d = duo(); s = d.s
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER","FIRE_CALLER"])
	check(Reactions.reaction_damage(d.hero,10) == 10 and Reactions.reaction_damage(d.ally,10) == 10,"술사 3 no longer strengthens reactions")
	# 무리 3: no rally; the whole party hits a tenth harder instead.
	d = duo(); s = d.s
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH","RAT_GNAW@ice"])
	check(TagSets.incoming(s,d.hero,5) == 5,"무리 3 no longer takes one less")
	s.tile(d.foe.pos).wet = 50
	Reactions.begin_action(s)
	Reactions.tile_react(s,d.foe.pos,"ice",5,d.hero)
	check(not d.ally.statuses.has("rally") and not d.hero.statuses.has("rally"),"a reaction rallies nobody any more")
	d.foe.hp = 30
	check(Passives.outgoing(s,d.ally,d.foe,10) == 11,"무리 2's party-wide attack replaces the rally")
	var source: String = FileAccess.get_file_as_string("res://expedition/progression/tag_sets.gd")
	check(not ["func on_dodge","func on_block","func on_reaction","func on_kill","func attack_delay","poised","rally"].any(func(word): return source.contains(word)),"the old role triggers are gone")
	StoneEffects.force = -1
