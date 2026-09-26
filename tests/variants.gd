extends SceneTree
## Element variants (spec §3.7): part ids "<BASE>@<element>", the element an
## active carries, monster block and resistances, and the floors' main element.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Variants = preload("res://expedition/level/variants.gd")
const CombatRules = preload("res://expedition/combat/combat_rules.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const CASTERS := ["kobold_firecaller","frost_imp","storm_bat","goblin_hexer","gnoll_summoner"]
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Forms.force = 99 # Element checks isolate variant effects from random wounds.
	resolution()
	data()
	effects()
	weakness()
	floors()
	Forms.force = -1
	print("Variants: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func resolution() -> void:
	check(Abilities.base_id("GOBLIN_SHIV@fire") == "GOBLIN_SHIV" and Abilities.base_id("GOBLIN_SHIV") == "GOBLIN_SHIV","base id strips the element")
	check(Abilities.element_of("GOBLIN_SHIV@fire") == "fire" and Abilities.element_of("GOBLIN_SHIV") == "","element is read from the id")
	check(Abilities.has("GOBLIN_SHIV@fire") and Abilities.has("GOBLIN_SHIV"),"base and variant ids resolve")
	check(not Abilities.has("GOBLIN_SHIV@lava") and not Abilities.has("NOPE@fire") and not Abilities.has("NOPE"),"unknown bases and elements do not resolve")
	var def: Dictionary = Abilities.definition("GOBLIN_SHIV@fire")
	check(str(def.get("element","")) == "fire","the variant carries its element")
	check(str(def.name).begins_with("화염 ") and str(def.item).begins_with("화염 "),"the variant is named for its element")
	check(int(def.damage) == int(Abilities.DEFINITIONS.GOBLIN_SHIV.damage) and int(def.range) == int(Abilities.DEFINITIONS.GOBLIN_SHIV.range),"the variant keeps the base numbers")
	check(not Abilities.DEFINITIONS.GOBLIN_SHIV.has("element"),"the base definition is left untouched")
	check(Abilities.definition("GOBLIN_SHIV@fire") == def,"the variant definition is stable between calls")
	check(Abilities.definition("NOPE").is_empty() and Abilities.definition("GOBLIN_SHIV@lava").is_empty(),"unknown ids give an empty definition")
	check(Abilities.definition("GOBLIN_SHIV") == Abilities.DEFINITIONS.GOBLIN_SHIV,"a base id gives the catalog row")
	check(str(Rules.skill("GOBLIN_SHIV@fire").get("name","")).begins_with("화염 "),"rules resolve a variant skill")
	check(Rules.valid(Abilities.default_rule("GOBLIN_SHIV@fire")),"a variant's default rule is valid")
	check(Abilities.badge("GOBLIN_SHIV@fire") == str(Abilities.DEFINITIONS.GOBLIN_SHIV.short),"a variant keeps the base badge")
	check(Abilities.kind_key({"species_id":"goblin","variant_element":"fire"}) == "goblin@fire","a variant kill is keyed by species and element")
	check(Abilities.kind_key({"species_id":"goblin"}) == "goblin","a base kill is keyed by species")
	check(Abilities.usable_by({"enemy":false},"GOBLIN_SHIV@fire") and not Abilities.usable_by({"enemy":false},"NOPE"),"a party member may use a known variant")
	var s = Session.new_run(731)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities[0] = "GOBLIN_SHIV@fire"
	check(Abilities.holds(hero,"GOBLIN_SHIV@fire"),"a party member holds an equipped variant")

func data() -> void:
	for row in Encounters.table():
		var id: String = str(row.species_id)
		check(row.has("sh") and int(row.sh) >= 0,"%s has a block value" % id)
		for key in ["fire","ice","air","poison","will"]:
			check(row.get("res",{}).has(key),"%s lists %s resistance" % [id,key])
		var options: Array = row.get("variants",[])
		check(options.all(func(e): return Abilities.ELEMENT_NAMES.has(e)),"%s variants are known elements" % id)
		check(options.size() <= 3,"%s has at most three variants" % id)
	var s = Session.new_run(731)
	check(not s.enemies.is_empty(),"the first floor has monsters")
	for enemy in s.enemies:
		var row: Dictionary = Encounters.species(str(enemy.species_id))
		check(int(enemy.get("sh",-1)) >= 0,"%s spawns with a valid block value" % enemy.name)
		check(enemy.res.has("will") and enemy.res.has("poison"),"%s spawns with every resistance" % enemy.name)

func effects() -> void:
	var s = Session.new_run(731)
	var hero: Dictionary = s.party[0]
	hero.stress = 0
	var foe: Dictionary = s.enemies[0]
	foe.pos = hero.pos+Vector2i(3,0)
	var cell: Dictionary = s.tile(hero.pos)
	cell.wet = 0; cell.fire = 0
	var before: int = hero.hp
	Abilities.resolve(s,foe,"KOBOLD_SLING@fire",hero.pos)
	check(hero.hp < before,"a fire part hurts")
	check(int(s.tile(hero.pos).fire) > 0,"a fire part sets its victim's cell alight")
	hero.hp = hero.max_hp; s.tile(hero.pos).fire = 0
	Abilities.resolve(s,foe,"KOBOLD_SLING@ice",hero.pos)
	check(hero.statuses.has("slow"),"an ice part slows")
	hero.hp = hero.max_hp
	Abilities.resolve(s,foe,"KOBOLD_SLING@poison",hero.pos)
	check(hero.statuses.has("poison"),"a poison part poisons")
	hero.hp = hero.max_hp
	Abilities.resolve(s,foe,"KOBOLD_SLING@will",hero.pos)
	check(hero.statuses.has("confuse"),"a will part confuses")
	hero.hp = hero.max_hp; hero.stress = 0
	Abilities.resolve(s,foe,"KOBOLD_SLING@air",hero.pos)
	var dry_loss: int = hero.max_hp-hero.hp
	hero.hp = hero.max_hp; hero.stress = 0; s.tile(hero.pos).wet = 70
	Abilities.resolve(s,foe,"KOBOLD_SLING@air",hero.pos)
	check(hero.max_hp-hero.hp > dry_loss,"an air part shocks a wet victim harder")
	hero.hp = hero.max_hp; hero.statuses.clear(); s.tile(hero.pos).wet = 0
	Abilities.resolve(s,foe,"KOBOLD_SLING",hero.pos)
	check(hero.statuses.is_empty() and int(s.tile(hero.pos).fire) == 0,"a base part leaves no element mark")

func weakness() -> void:
	var s = Session.new_run(731)
	var foe: Dictionary = s.enemies[0]
	foe.part_id = ""; foe.statuses.clear()
	foe.res = {"fire":-25}; foe.hp = 100; foe.max_hp = 100
	CombatRules.damage(s,{},foe,20,"fire")
	check(foe.hp == 75,"a weakness of 25 turns 20 fire into 25")
	foe.res = {"fire":50}; foe.hp = 100
	CombatRules.damage(s,{},foe,20,"fire")
	check(foe.hp == 90,"resistance 50 halves fire")

func floors() -> void:
	var start = Session.new_run(731)
	check(str(start.floor_state.element) == "","the first floor has no main element")
	check(start.enemies.all(func(e): return str(e.get("variant_element","")).is_empty()),"the first floor has base species only")
	var total := 0
	for seed_value in range(1,9):
		for depth in range(2,8):
			var s = Session.new_run(seed_value)
			s.depth = depth; s.floor_state.build(s)
			var element: String = str(s.floor_state.element)
			var variants: Array = s.enemies.filter(func(e): return not str(e.get("variant_element","")).is_empty())
			total += variants.size()
			if variants.is_empty(): continue
			check(not element.is_empty(),"a floor with variants has a main element (seed %d, floor %d)" % [seed_value,depth])
			check(s.log_lines.any(func(line): return line == "이 층의 기운 · "+str(Abilities.ELEMENT_NAMES.get(element,""))),"the floor announces its element (seed %d, floor %d)" % [seed_value,depth])
			var main: int = variants.filter(func(e): return e.variant_element == element).size()
			check(main*2 >= variants.size(),"at least half the variants wear the floor's element (seed %d, floor %d)" % [seed_value,depth])
			for e in variants:
				var own: String = e.variant_element
				check(own in Variants.allowed(str(e.species_id)),"%s wears an element that suits it" % e.name)
				if own != "bleed": check(int(e.res.get(own,0)) >= Variants.OWN_RESIST,"%s resists its own element" % e.name)
				check(str(e.part_id).ends_with("@"+own),"%s carries the variant part" % e.name)
				check(str(e.name).begins_with(str(Abilities.ELEMENT_NAMES[own])),"%s is named for its element" % e.name)
				check(Abilities.kind_key(e) == "%s@%s" % [e.species_id,own],"%s is keyed as a variant" % e.name)
				if Abilities.OPPOSITE.has(own):
					check(int(e.res.get(Abilities.OPPOSITE[own],0)) < 0,"%s is weak to the opposite element" % e.name)
	check(total >= 20,"variants appear below the first floor (%d met)" % total)
