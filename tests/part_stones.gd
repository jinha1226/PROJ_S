extends SceneTree
## Canonical storage, old snapshots, distinct parts and shared species actions.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const Parts = preload("res://expedition/ai/parts_candidates.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	catalog(); aliases(); migration(); shared_actions(); spells(); monster_effects()
	print("Part stones: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func catalog() -> void:
	check(Essences.catalog().size() == 93,"90 concrete parts plus three boss stones")
	var ordinary := 0
	for base in Essences.content.rows:
		var row: Dictionary = Essences.content.rows[base]
		if not row.has("parts"):
			check(base in ["GOBLIN_CHIEF","FURNACE_HEART","SOUL_EATER"],"only boss stones have no parts")
			check(Essences.canonical(base) == base and Essences.part_of(base).is_empty(),"boss id unchanged")
			continue
		ordinary += 1
		check(row.parts.keys() == ["cut","broken","pierced"],str(base)+" defines all three parts")
		var effects := 0
		for part in row.parts:
			var id: String = str(base)+"/"+str(part)
			check(Essences.canonical(id) == id and Essences.part_of(id) == part,"concrete part round trip: "+id)
			check(Essences.title(id) == str(row.parts[part].name) and not Essences.title(id).is_empty(),"part title: "+id)
			check(Essences.stats(id) == Essences.stats(base) and Essences.school(id) == Essences.school(base),"parts inherit stats and school: "+id)
			var effect: String = StoneEffects.effect_of(id)
			if not effect.is_empty(): effects += 1
			check(effect == str(row.parts[part].effect) and StoneEffects.EFFECTS.has(effect),"only headline keeps the original effect: "+id)
			check(Abilities.definition(id) == Abilities.definition(base),"parts inherit their active: "+id)
		check(effects == 3 and StoneEffects.species_effect(str(row.species)) == base,"species keeps exactly its original effect: "+str(base))
	check(ordinary == 30,"thirty ordinary species")
	check(Art.part_icon("GOBLIN_SHIV/cut").atlas == Art.part_icon("GOBLIN_SHIV").atlas,"new ids reuse existing art")

func aliases() -> void:
	check(Essences.canonical("RAT_GNAW") == "RAT_GNAW/cut","bare rat is its headline")
	check(Essences.canonical("KOBOLD_SLING") == "KOBOLD_SLING/broken","headline is not always cut")
	check(Essences.canonical("GOBLIN_SHIV@fire") == "GOBLIN_SHIV/pierced@fire","variant alias preserves element")
	check(Essences.base_of("SPIDER_WEB/broken@poison") == "SPIDER_WEB" and Essences.variant_element("SPIDER_WEB/broken@poison") == "poison","species and variant parse independently")
	check(Essences.title("RAT_GNAW/pierced@poison") == "독 쥐 심장","part and variant named together")
	check(int(Essences.stats("RAT_GNAW/broken@ice").res_ice) == 10,"new parts keep variant resistance")
	for bad in ["","NOPE","RAT_GNAW/","RAT_GNAW/head","RAT_GNAW/cut/x","RAT_GNAW@","RAT_GNAW@lava","RAT_GNAW/cut@ice@fire","RAT_GNAW@ice/cut","GOBLIN_CHIEF/cut"]:
		check(Essences.canonical(bad).is_empty() and not Essences.has(bad) and Essences.row(bad).is_empty(),"reject malformed stone: "+bad)
		check(not Abilities.has(bad),"malformed stone cannot become an action: "+bad)
	check(Abilities.active_id("KOBOLD_SLING/pierced@ice") == "KOBOLD_SLING@ice","action id has no part")
	check(Abilities.default_rule("KOBOLD_SLING/cut").skill == "KOBOLD_SLING","rules store the action id")

func migration() -> void:
	var actor := {"level":4,"essences":{"RAT_GNAW":3,"RAT_GNAW/cut":1,"RAT_GNAW@ice":1},
		"equipped_abilities":["RAT_GNAW","RAT_GNAW/cut","RAT_GNAW/broken@ice",""],
		"sealed":{"RAT_GNAW":8,"RAT_GNAW/cut":4},"cooldowns":{"RAT_GNAW/cut":2,"RAT_GNAW@ice":5},
		"rules":[Abilities.default_rule("RAT_GNAW/cut"),Abilities.default_rule("RAT_GNAW/broken@ice")],
		"reservation":{"kind":"RAT_GNAW/broken@ice","cell":Vector2i(1,1)}}
	Essences.normalize_actor(actor)
	check(actor.essences == {"RAT_GNAW/cut":1,"RAT_GNAW/cut@ice":1},"old tiers collapse to one canonical ownership")
	check(actor.equipped_abilities == ["RAT_GNAW/cut","","RAT_GNAW/broken@ice",""],"duplicate alias slot empties without shifting slots")
	check(actor.sealed == {"RAT_GNAW/cut":8},"seal migration retains the longest expiry")
	check(Essences.equipped(actor) == ["RAT_GNAW/broken@ice"],"sealing one part leaves its other part")
	check(actor.cooldowns == {"RAT_GNAW":5},"cooldown aliases merge by longest remaining time")
	check(actor.rules.size() == 1 and actor.rules[0].skill == "RAT_GNAW@ice","old rule aliases deduplicate and follow the unsealed part")
	check(actor.reservation.kind == "RAT_GNAW@ice","reserved action migrates separately from stones")
	var copy: Dictionary = actor.duplicate(true)
	Essences.normalize_actor(actor)
	check(actor == copy,"actor migration is idempotent")
	var bag: Dictionary = Essences.normalize_keys({"RAT_GNAW":2,"RAT_GNAW/cut":3,"RAT_GNAW@ice":4},true)
	check(bag == {"RAT_GNAW/cut":5,"RAT_GNAW/cut@ice":4},"bag aliases combine copies and preserve variants")
	check(Essences.normalize_keys(bag,true) == bag,"bag migration is idempotent")
	var s = Session.new_run(731)
	s.parts_bag = {"RAT_GNAW":2}; s.battle_stats.drops = {"RAT_GNAW":1}
	s.party[0].essences = {"GOBLIN_SHIV":1}; s.party[0].equipped_abilities = ["GOBLIN_SHIV"]
	s.essence_seen = {"goblin@fire":true}
	Essences.normalize_run(s)
	check(s.parts_bag == {"RAT_GNAW/cut":2} and s.battle_stats.drops == {"RAT_GNAW/cut":1},"run inventory and drop history migrate")
	check(s.party[0].equipped_abilities == ["GOBLIN_SHIV/pierced"] and s.essence_seen == {"goblin@fire":true},"species first-kill keys do not become part ids")
	var stored: Dictionary = JSON.parse_string(JSON.stringify({"essences":s.party[0].essences,"equipped_abilities":s.party[0].equipped_abilities,"cooldowns":{"GOBLIN_SHIV":3}}))
	Essences.normalize_actor(stored)
	check(stored.essences == {"GOBLIN_SHIV/pierced":1} and int(stored.cooldowns.GOBLIN_SHIV) == 3,"canonical snapshot round trip preserves ownership and cooldown")

func shared_actions() -> void:
	var s = Session.new_run(731); s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	hero.level = 3
	s.grant_part("RAT_GNAW"); s.grant_part("RAT_GNAW/broken"); s.grant_part("RAT_GNAW/pierced")
	check(s.parts_bag.size() == 3 and not s.parts_bag.has("RAT_GNAW"),"grants store only concrete ids")
	check(s.equip_part(0,0,"RAT_GNAW") and s.equip_part(0,1,"RAT_GNAW/broken") and s.equip_part(0,2,"RAT_GNAW/pierced"),"three different species parts can be worn together")
	check(not s.equip_part(0,1,"RAT_GNAW/cut"),"same stone cannot be slotted twice through an alias")
	check(hero.rules.size() == 1 and Abilities.held(hero) == ["RAT_GNAW"],"three parts give one action and one rule")
	check(int(TagSets.counts(hero).SUPPORT) == 3,"role counts each distinct part")
	check(StoneEffects.effects(hero) == ["RAT_GNAW","RAT_INCISOR","RAT_HEART"],"unfinished parts do not repeat headline effects")
	hero.rules[0].enabled = false
	check(not s.unequip_part(0,0) and not Essences.take(hero,1),"individual parts cannot be removed")
	check(hero.rules.size() == 1 and not hero.rules[0].enabled,"rejected removal preserves the configured shared rule")
	check(StoneEffects.effects(hero) == ["RAT_GNAW","RAT_INCISOR","RAT_HEART"],"all three distinct effects stay active")
	check(not Essences.put(hero,0,"RAT_GNAW/broken") and hero.essences.size() == 3,"the internal replacement path is refused too")

	Fixture.arena(s,8); s.phase = "CAMP"
	hero.level = 2; hero.essences = {}; hero.equipped_abilities = []; hero.rules = []
	Essences.bind(hero,"KOBOLD_SLING/cut@fire"); Essences.bind(hero,"KOBOLD_SLING/pierced@ice")
	check(Abilities.held(hero) == ["KOBOLD_SLING@fire"],"first unsealed species part determines active element")
	var foe: Dictionary = s.enemies[0]; foe.pos = hero.pos+Vector2i(2,0); foe.hp = 200; foe.max_hp = 200
	s.phase = "BATTLE"; hero.ap = 2; hero.cooldowns = {}
	check(Abilities.execute(s,hero,"KOBOLD_SLING/cut@fire",foe.pos),"canonical stone can invoke its shared active")
	var remaining: int = Abilities.cooldown(hero,"KOBOLD_SLING@fire")
	check(remaining > 0 and hero.cooldowns.keys() == ["KOBOLD_SLING"],"one species cooldown is stored")
	hero.sealed = {"KOBOLD_SLING/cut@fire":8}
	Essences.sync_spells(hero)
	check(Abilities.held(hero) == ["KOBOLD_SLING@ice"],"sealing first part exposes the next variant")
	check(hero.rules.size() == 1 and hero.rules[0].skill == "KOBOLD_SLING@ice","configured AI rule follows unsealed variant")
	check(Abilities.cooldown(hero,"KOBOLD_SLING/pierced@ice") == remaining and not Abilities.legal(s,hero,"KOBOLD_SLING@ice",foe.pos),"alternate part and element cannot bypass cooldown")
	hero.sealed = {}; hero.cooldowns.clear()
	var options: Array = []; Parts.part_options(s,hero,options)
	check(options.filter(func(o): return str(o.kind).begins_with("KOBOLD_SLING")).size() == 1,"AI receives one candidate per target and species")
	foe.part_id = "KOBOLD_SLING@ice"; foe.alert = true; foe.cooldowns = {}; foe.cast_recovery = 0; foe.charging = false
	Abilities.resolve(s,foe,str(foe.part_id),hero.pos)
	remaining = Abilities.cooldown(foe,str(foe.part_id))
	check(remaining > 0 and foe.cooldowns.keys() == ["KOBOLD_SLING@ice"],"intrinsic monster variant retains the turn driver's cooldown key")
	MonsterAI.turn(s,foe)
	check(Abilities.cooldown(foe,str(foe.part_id)) == remaining-1 and not foe.charging,"variant monster cooldown ticks and blocks premature telegraph")

func spells() -> void:
	var s = Session.new_run(731,"fire"); s.phase = "CAMP"
	var hero: Dictionary = s.party[0]; hero.level = 3
	s.grant_part("FIRE_CALLER/cut"); s.grant_part("FIRE_CALLER/broken")
	check(s.equip_part(0,1,"FIRE_CALLER/cut") and s.equip_part(0,2,"FIRE_CALLER/broken"),"three caster parts can be absorbed")
	check(hero.spells == ["fire_1"] and hero.prepared == ["fire_1"],"identical selected spells are not duplicated")
	check(s.choose_essence_spell(0,"FIRE_CALLER/cut","fire_3") and hero.prepared == ["fire_1","fire_3"],"the hand chooses an explosion independently")
	check(s.choose_essence_spell(0,"FIRE_CALLER/broken","fire_2") and hero.prepared == ["fire_1","fire_3","fire_2"],"the bone keeps its own charge")
	check(not s.choose_essence_spell(0,"FIRE_CALLER/broken","fire_3"),"same school does not grant unlinked spells")
	check(not s.unequip_part(0,0) and hero.prepared == ["fire_1","fire_3","fire_2"],"permanent stones cannot be removed")
	hero.level = 4
	s.grant_part("FIRE_CALLER/cut@ice")
	check(s.absorb_essence(0,"FIRE_CALLER/cut@ice").is_empty() and hero.essence_spells["FIRE_CALLER/cut@ice"] == "fire_1" and hero.essence_spells["FIRE_CALLER/cut"] == "fire_3","a variant is an independent choice without overwriting other parts")
	var legacy := {"level":3,"essences":{"FIRE_CALLER":1},"equipped_abilities":["FIRE_CALLER"],"essence_spells":{"FIRE_CALLER":"fire_3"}}
	Essences.sync_spells(legacy)
	check(legacy.prepared == ["fire_1"] and legacy.essence_spells == {"FIRE_CALLER/pierced":"fire_1"},"an old unlinked choice falls back to the stone's own spell")

func monster_effects() -> void:
	check(StoneEffects.effects({"enemy":true,"part_id":"GOBLIN_SHIV/cut","species_id":"goblin"}) == ["GOBLIN_SHIV"],"monster has headline even if supplied another physical part")
	check(StoneEffects.effects({"enemy":true,"part_id":"SPIDER_WEB/broken@poison","species_id":"cave_spider"}) == ["SPIDER_WEB"],"variant monster retains headline")
	check(StoneEffects.effects({"enemy":true,"boss":true,"part_id":"RAT_GNAW/cut"}).is_empty(),"boss has no ordinary stone effects")
