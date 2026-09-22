extends SceneTree
## Every catalog skill must be configurable through the same rule schema: the
## catalog agrees with the UI pickers, and the rule engine honours each
## condition it advertises.
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const REACH = {"PUSH":1,"HEAVY_STRIKE":1,"THROWING_KNIFE":4,"LUNGE":3,"BOMB":3}
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func configurable() -> Array:
	return Abilities.DEFINITIONS.keys()

## Arena with one hero carrying `skill` and up to two revived foes.
func arena(skill: String, distance: int, second: int = 0) -> Dictionary:
	var s = Session.new(731,true,false,true,1); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities = [skill,"GUARD"]
	hero.rules = [Abilities.default_rule(skill),Abilities.default_rule("GUARD")]
	hero.cooldowns = {}; hero.ap = 2; hero.iron_guard = false
	s.intents.clear()
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false
	foe.pos = c+Vector2i(distance,0)
	var other: Dictionary = {}
	if second > 0:
		other = s.enemies[1]
		other.hp = 30; other.max_hp = 30; other.role = "MELEE"; other.alert = true; other.charging = false
		other.pos = c+Vector2i(0,second)
	s.floor_state.observe(s)
	return {"s":s,"hero":hero,"foe":foe,"other":other,"c":c}

func picks(scene) -> Array:
	return scene.item_detail.find_children("*","OptionButton",true,false)

func texts(pick) -> Array:
	var result: Array = []
	for i in range(pick.item_count): result.append(pick.get_item_text(i))
	return result

func run() -> void:
	catalog()
	await user_interface()
	semantics()
	guard_conditions()
	print("Skill rule conditions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## 1. Every configurable skill is in the rule catalog and every advertised
## target/condition pair builds a valid rule.
func catalog() -> void:
	for id in configurable():
		check(Rules.catalog().has(id),"%s is in the rule catalog" % id)
		if not Rules.catalog().has(id): continue
		var def: Dictionary = Rules.skill(id)
		check(not def.targets.is_empty() and not def.conditions.is_empty(),"%s advertises targets and conditions" % id)
		for target in def.targets:
			check(Rules.TARGET_NAMES.has(target),"%s target %s has a display name" % [id,target])
			for when in def.conditions:
				check(Rules.WHEN_NAMES.has(when),"%s condition %s has a display name" % [id,when])
				var rule: Dictionary = Rules.make_rule(id,target,when)
				check(Rules.valid(rule),"%s/%s/%s makes a valid rule" % [id,target,when])
				check(Rules.summary(rule) != "","%s/%s/%s renders a summary" % [id,target,when])
		if not Abilities.DEFINITIONS.has(id): continue
		var rule: Dictionary = Abilities.default_rule(id)
		check(Rules.valid(rule),"%s default rule is valid" % id)
		check(rule.when == Abilities.DEFINITIONS[id].rule_when,"%s default rule uses its rule_when" % id)
	# Drops follow the species that owns the part; no species owns one yet.
	check(Abilities.droppable().is_empty(),"only species parts drop")
	check(Abilities.species_part("nobody").is_empty(),"an unknown species owns no part")
	for id in Abilities.DEFINITIONS:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(def.has("short") and def.has("shape") and def.has("self_hit") and def.has("icon"),"%s carries the presentation fields" % id)
		check(Abilities.badge(id) == def.short,"%s badge comes from the catalog" % id)
	for kind in Abilities.BASIC_BADGES:
		check(Abilities.badge(kind) == Abilities.BASIC_BADGES[kind],"%s keeps its basic badge" % kind)
	check(Abilities.badge("NOPE") == "NOPE","unknown kinds fall back to the id")

## 2. The rule editor offers exactly the advertised targets and conditions and
## every condition can be selected from the UI.
func user_interface() -> void:
	var scene = load("res://expedition/main.gd").new()
	scene.session = scene.Session.new(731,true,false,true,1)
	root.add_child(scene)
	await process_frame
	var hero: Dictionary = scene.session.party[0]
	for id in configurable():
		var index := 0
		hero.cooldowns = {}
		hero.equipped_abilities = [id,"GUARD"]
		hero.rules = Rules.defaults(); hero.rules.append(Abilities.default_rule(id))
		index = hero.rules.size()-1
		scene.show_character(0,"파츠")
		await process_frame
		var policies: Array = scene.modal_content.find_children("*","Button",true,false).filter(func(b): return b.text.begins_with("사용 방침"))
		check(policies.any(func(b): return b.text.contains(Rules.summary(hero.rules[index]))),"%s has a policy button" % id)
		scene.open_rule(index)
		await process_frame
		var options: Array = picks(scene)
		check(options.size() >= 3,"%s rule editor builds its pickers" % id)
		if options.size() < 3: continue
		var def: Dictionary = Rules.skill(id)
		check(texts(options[0]) == def.targets.map(func(t): return Rules.TARGET_NAMES[t]),"%s offers exactly its targets" % id)
		check(texts(options[1]) == def.conditions.map(func(w): return Rules.WHEN_NAMES[w]),"%s offers exactly its conditions" % id)
		for when in def.conditions:
			scene.change_tactic_rule(index,"when",when)
			await process_frame
			check(hero.rules[index].when == when,"%s can be set to %s" % [id,when])
			check(Rules.summary(hero.rules[index]) != "","%s/%s renders a summary" % [id,when])
			if when == "HP":
				check(not scene.item_detail.find_children("*","HSlider",true,false).is_empty(),"%s exposes the health slider" % id)
				check(scene.session.update_rule(0,index,"threshold",30) and hero.rules[index].threshold == 30,"%s threshold is adjustable" % id)
				scene.session.update_rule(0,index,"threshold",50)
			if when == "STATUS":
				var names: Array = Rules.STATUS_NAMES.keys().map(func(k): return Rules.STATUS_NAMES[k])
				check(picks(scene).any(func(p): return texts(p) == names),"%s exposes the status picker" % id)
		scene.item_popup.hide()
	scene.queue_free()
	await process_frame

## 3. The rule engine honours each condition in a live arena.
func semantics() -> void:
	for id in Abilities.DEFINITIONS:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		# 엄호 is the only ALLY part and has its own section below.
		if def.target == "ALLY": continue
		if def.target == "ENEMY": enemy_conditions(id,int(REACH[id]))
		else: self_conditions(id)

func enemy_conditions(id: String, reach: int) -> void:
	# CHARGING: only a foe that is winding up an attack qualifies.
	var f := arena(id,reach)
	f.hero.rules = [Rules.make_rule(id,"NEAREST","CHARGING")]
	f.foe.charging = true
	f.s.intents.append({"id":f.foe.id,"cell":f.c+Vector2i(0,4),"damage":16})
	check(Tactics.choose(f.s,f.hero).kind == id,"%s fires on a charging foe" % id)
	f = arena(id,reach)
	f.hero.rules = [Rules.make_rule(id,"NEAREST","CHARGING")]
	check(Tactics.choose(f.s,f.hero).kind != id,"%s holds against a calm foe" % id)
	# LOWEST_HP: of two legal foes the weaker one is chosen.
	f = arena(id,reach,reach)
	f.other.hp = 12
	f.hero.rules = [Rules.make_rule(id,"LOWEST_HP","ALWAYS")]
	var choice: Dictionary = Tactics.choose(f.s,f.hero)
	check(choice.kind == id and choice.cell == f.other.pos,"%s targets the weaker foe" % id)
	f = arena(id,reach,reach)
	f.foe.hp = 12
	f.hero.rules = [Rules.make_rule(id,"LOWEST_HP","ALWAYS")]
	choice = Tactics.choose(f.s,f.hero)
	check(choice.kind == id and choice.cell == f.foe.pos,"%s follows the wound, not the order" % id)
	# HP on the target: only below the threshold.
	f = arena(id,reach)
	f.foe.hp = 12
	var rule: Dictionary = Rules.make_rule(id,"NEAREST","HP")
	rule.subject = "TARGET"; rule.threshold = 50; rule.comparison = "BELOW"
	check(Rules.valid(rule),"%s target-health rule is valid" % id)
	f.hero.rules = [rule]
	check(Tactics.choose(f.s,f.hero).kind == id,"%s fires on a wounded foe" % id)
	f = arena(id,reach)
	f.hero.rules = [rule]
	check(Tactics.choose(f.s,f.hero).kind != id,"%s spares a healthy foe" % id)

func self_conditions(id: String) -> void:
	var def: Dictionary = Abilities.DEFINITIONS[id]
	# HP on the caster: only below the threshold.
	var f := arena(id,1)
	f.hero.hp = 10
	f.hero.rules = [Rules.make_rule(id,"SELF","HP")]
	check(Tactics.choose(f.s,f.hero).kind == id,"%s fires when the hero is hurt" % id)
	f = arena(id,1)
	f.hero.hp = f.hero.max_hp-1 if def.effect == "HEAL" else f.hero.max_hp
	f.hero.rules = [Rules.make_rule(id,"SELF","HP")]
	check(Tactics.choose(f.s,f.hero).kind != id,"%s waits while the hero is healthy" % id)
	# DANGER: an adjacent alert melee foe threatens the hero's cell.
	f = arena(id,1)
	if def.effect == "HEAL": f.hero.hp = 40
	f.hero.rules = [Rules.make_rule(id,"SELF","DANGER")]
	check(Tactics.threat(f.s,f.foe,f.hero.pos,f.foe.pos) > 0,"%s case: adjacent foe threatens the hero" % id)
	check(Tactics.choose(f.s,f.hero).kind == id,"%s fires under threat" % id)
	# The same foe two cells away cannot reach, so the rule stays silent while
	# the skill itself is still a legal option.
	f = arena(id,2)
	if def.effect == "HEAL": f.hero.hp = 40
	f.hero.rules = [Rules.make_rule(id,"SELF","DANGER")]
	check(Tactics.threat(f.s,f.foe,f.hero.pos,f.foe.pos) == 0,"%s case: distant foe is no threat" % id)
	check(Abilities.legal(f.s,f.hero,id,f.hero.pos),"%s stays legal without danger" % id)
	check(Tactics.choose(f.s,f.hero).kind != id,"%s holds while unthreatened" % id)

## Party arena: `size` members in a straight line with `foes` revived foes the
## caller then places. Mates start far enough back that nothing is adjacent.
func party_arena(skill: String, size: int, foes: int) -> Dictionary:
	var s = Session.new(731,true,size > 1,true,size); s.depart()
	var c := Fixture.arena(s,8)
	for i in range(s.party.size()): s.party[i].pos = c+Vector2i(0,2*i)
	var hero: Dictionary = s.party[0]
	for actor in s.party:
		actor.equipped_abilities = [skill,"GUARD"]
		actor.rules = [Abilities.default_rule(skill),Abilities.default_rule("GUARD")]
		actor.cooldowns = {}; actor.ap = 2; actor.iron_guard = false
	s.intents.clear()
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false
		foe.pos = c+Vector2i(1,2*i)
		revived.append(foe)
	s.floor_state.observe(s)
	return {"s":s,"hero":hero,"foes":revived,"c":c}

## 4. 엄호 (GUARD/ALLY/ALLY_LETHAL): the only condition the skill advertises.
func guard_conditions() -> void:
	check(Rules.defaults().is_empty(),"an empty slot carries no rule")
	check(Rules.skill("GUARD").targets == ["ALLY"] and Rules.skill("GUARD").conditions == ["ALLY_LETHAL"],"엄호 advertises one target and one condition")
	check(Abilities.default_rule("IRON_HIDE").when == "DANGER","IRON_HIDE defaults back to danger")
	# Positive: an adjacent alert melee foe would finish the wounded ally.
	var p := cover_arena(5)
	var ally: Dictionary = p.s.party[1]
	check(Rules.lethal_threat(p.s,ally) >= ally.hp,"a melee foe in contact can finish the ally")
	var choice: Dictionary = Tactics.choose(p.s,p.hero)
	check(choice.kind == "GUARD" and choice.cell == ally.pos,"엄호 fires on the ally that would die")
	# Negative: the same foe cannot kill a healthy ally.
	p = cover_arena(30)
	ally = p.s.party[1]
	check(Rules.lethal_threat(p.s,ally) < ally.hp,"a healthy ally survives the same hit")
	check(Tactics.choose(p.s,p.hero).kind != "GUARD","엄호 holds while the ally can take the hit")
	# Positive: a cell-locked caster wind-up on the ally's cell counts as one hit.
	p = cover_arena(10,6)
	ally = p.s.party[1]
	p.s.intents = [{"id":p.foes[0].id,"cell":ally.pos,"damage":14}]
	check(Rules.lethal_threat(p.s,ally) >= 14,"the announced wind-up is the largest hit")
	choice = Tactics.choose(p.s,p.hero)
	check(choice.kind == "GUARD" and choice.cell == ally.pos,"엄호 answers a telegraphed strike on the ally")
	# Negative: with nobody adjacent there is no 엄호 at all.
	var f := arena("PUSH",1)
	f.hero.rules = [Rules.make_rule("GUARD","ALLY","ALLY_LETHAL")]
	f.hero.hp = 3
	check(Tactics.choose(f.s,f.hero).kind != "GUARD","엄호 never fires for a lone hero")
	check(not f.s.act("GUARD",f.hero.pos),"a lone hero cannot guard their own cell")

## Hero, one ally in contact with the hero, and one melee foe in contact with
## the ally at `foe_gap` cells from the hero.
func cover_arena(ally_hp: int, foe_gap: int = 2) -> Dictionary:
	var p := party_arena("PUSH",3,1)
	p.s.party[1].pos = p.c+Vector2i(1,0)
	p.s.party[2].pos = p.c+Vector2i(0,5)
	p.foes[0].pos = p.c+Vector2i(foe_gap,0)
	p.s.party[1].hp = ally_hp
	for actor in p.s.party: actor.rules = [Rules.make_rule("GUARD","ALLY","ALLY_LETHAL")]
	p.s.floor_state.observe(p.s)
	return p
