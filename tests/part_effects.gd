extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Effects = preload("res://expedition/progression/effect_engine.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var d := Fixture.reset(); var s = d.s
	Forms.force = 99; s.StoneEffects.force = 99
	# Independent expected effects: flat/conditional modifiers must be owned by the right part.
	for spec in [["RAT_INCISOR","wound_chance.SLASH",10],["HOB_JAW","wound_chance.IMPACT",10],["ARCHER_EYE","attack_percent",20],["HEXER_SKULL","will_save",20],["GOLEM_VEIN","impact_armour_percent",-50],["LEECH_SEGMENT","bleed_tick",2],["SERPENT_SCALE","res.poison",50],["SUMMONER_BONE","summon_hp",50],["FROST_HORN","status_ticks.freeze",50],["SKELETON_ARM","status_ticks.bleed",50]]:
		d = Fixture.reset(s); Fixture.slot(d.hero,[spec[0]]); d.foe.pos = Vector2i(7,3)
		var ctx := {"target":d.foe,"form":"SLASH","school":"hex"}
		check(Effects.modifier(s,spec[1],d.hero,ctx) == spec[2],str(spec[0])+" contributes its documented modifier")
		check(Effects.modifier(s,spec[1],d.ally,ctx) == 0,"effect does not leak to an unrelated ally")
	for spec in [["ORC_HEART","taken_percent",-25,"hp"],["SPIDER_SHELL","attack_percent",30,"harmful"],["GOLEM_CORE","attack_percent",30,"fracture"],["FIRECALLER_HAND","attack_percent",20,"burn"],["SERPENT_FANG","attack_percent",15,"poison"],["BOWMAN_FINGER","attack_percent",20,"fracture"],["VAMPIRE_WING","attack_percent",20,"move"]]:
		d = Fixture.reset(s); Fixture.slot(d.hero,[spec[0]])
		var ctx := {"target":d.foe}
		check(Effects.modifier(s,spec[1],d.hero,ctx) == 0,str(spec[0])+" inactive before its condition")
		match str(spec[3]):
			"hp": d.hero.hp = 30
			"harmful": d.foe.statuses = {"bleed":300,"weak":300,"fracture":300}
			"move": d.hero.moved_since_attack = true
			_: d.foe.statuses[spec[3]] = 300
		check(Effects.modifier(s,spec[1],d.hero,ctx) == spec[2],str(spec[0])+" activates only with its condition")
	# Stacks change actual damage/stat queries and disappear on their defined boundary.
	for spec in [["RAT_HEART","ALLY_KILL","attack_percent",20],["LIZARD_FRILL","STRUCK","attack_percent",5],["LIZARD_EYE","DODGE","crit_chance",30],["BEETLE_CORE","STRUCK","armour",1],["SPIDER_LEG","CRIT","speed",30]]:
		d = Fixture.reset(s); Fixture.slot(d.hero,[spec[0]])
		var ctx := {"source":d.ally,"attacker":d.foe,"target":d.hero}
		if spec[1] == "ALLY_KILL": ctx.source = d.ally; ctx.attacker = d.ally; ctx.target = d.foe
		if spec[1] == "CRIT": ctx.source = d.hero; ctx.attacker = d.hero; ctx.target = d.foe
		s.StoneEffects.fire(s,spec[1],ctx)
		check(Effects.modifier(s,spec[2],d.hero,{"target":d.foe}) == spec[3],str(spec[0])+" gains its stack after the correct event")
	# Aim holds and resets on real movement, never grows after a move in the same round.
	d = Fixture.reset(s); Fixture.slot(d.hero,["KOBOLD_HEART"])
	s.time = 100; s.StoneEffects.round_start(s,d.hero)
	check(Effects.modifier(s,"attack_percent",d.hero,{"ranged":true}) == 10,"stationary round builds aim")
	s.StoneEffects.fire(s,"MOVED",{"actor":d.hero})
	check(Effects.modifier(s,"attack_percent",d.hero,{"ranged":true}) == 0,"moving removes aim immediately")
	# Debuffs, poison growth, and recovery use actual status events.
	d = Fixture.reset(s); Fixture.slot(d.hero,["GOBLIN_TOOTH","WRAITH_BONE"]); d.hero.hp = 40; d.foe.ac = 10
	for i in range(7): s.Reactions.begin_action(s); s.Statuses.apply(s,d.foe,"weak",300,d.hero)
	check(Stats.stats(s,d.foe).ac == 5,"corrosion is capped at five before combat clamps armour")
	check(d.hero.hp == 54,"harmful applications heal their owner")
	d = Fixture.reset(s); Fixture.slot(d.hero,["TOAD_TONGUE"])
	for i in range(7): s.Reactions.begin_action(s); s.Statuses.apply(s,d.foe,"poison",300,d.hero)
	check(int(d.foe.status_power.poison_bonus) == 4,"repeated poison has a four-point cap")
	d = Fixture.reset(s); Fixture.slot(d.hero,["SERPENT_SCALE"])
	check(not s.Statuses.apply(s,d.hero,"poison",300,d.foe),"serpent scale prevents poison")
	d = Fixture.reset(s); Fixture.slot(d.hero,["GNOLL_BONE"]); d.hero.hp = 40
	check(s.StoneEffects.heal(s,d.hero,20,d.ally) == 0,"gnoll bone refuses external healing")
	s.StoneEffects.round_start(s,d.hero); check(d.hero.hp == 44,"gnoll regeneration still heals itself")
	# A corpse explosion is delayed exactly one round and cannot repeat.
	d = Fixture.reset(s); Fixture.slot(d.hero,["GHOUL_JAW"]); d.foe.hp = 0
	var other: Dictionary = s.make_actor(101,"다른 적",true); other.pos = Vector2i(5,3); other.hp = 100; other.max_hp = 100; other.part_id = ""; s.enemies.append(other)
	s.StoneEffects.on_kill(s,d.hero,d.foe,{"victim_statuses":{}})
	Effects.Code.delayed(s); check(other.hp == 100,"corpse does not explode before the next boundary")
	s.time = 100; Effects.Code.delayed(s); check(other.hp == 50,"corpse explosion uses victim maximum HP")
	Effects.Code.delayed(s); check(other.hp == 50,"delayed explosion resolves once")
	# Lifesteal overflow protects against the next blow before lethal/downed handling.
	d = Fixture.reset(s); Fixture.slot(d.hero,["VAMPIRE_HEART"])
	s.StoneEffects.heal(s,d.hero,25,d.hero,true)
	check(int(d.hero.get("blood_ward",0)) == 20,"overflow ward caps at twenty percent")
	var before: int = d.hero.hp
	s.CombatRules.damage(s,d.foe,d.hero,25,"physical",0,s.Reactions.EXTRA_FORM)
	check(d.hero.hp == before-5,"overflow ward actually absorbs damage")

	# Runtime integration: incoming source, actual hit callbacks, summon targeting, round history.
	d = Fixture.reset(s); Fixture.slot(d.hero,["TOAD_BONE"]); d.foe.statuses.poison = 300
	check(s.StoneEffects.incoming(s,d.hero,20,d.foe) == 17,"poison defense reads the attacking enemy")
	d = Fixture.reset(s); Fixture.slot(d.hero,["HOB_HIDE"])
	check(s.StoneEffects.outgoing(s,d.hero,d.foe,10,"physical") == 13 and d.hero.hp == 98,"hob hide pays HP once and scales the real attack")
	d = Fixture.reset(s); Fixture.slot(d.hero,["ARCHER_KNUCKLE"]); s.StoneEffects.force = 0
	var behind: Dictionary = d.foe.duplicate(true); behind.id = 101; behind.pos = Vector2i(5,3); s.enemies.append(behind)
	s.StoneEffects.fire(s,"HIT",{"source":d.hero,"target":d.foe,"ranged":true,"lost":10,"phase":"proc"})
	check(behind.hp == 495 and behind.last_form == "","piercing arrow hits behind once with secondary damage")
	d = Fixture.reset(s); Fixture.slot(d.hero,["SUMMONER_HIDE","SUMMONER_BONE"])
	var first: Dictionary = s.Spells.Summons.summon(s,d.hero,Vector2i(2,3),"skeleton")
	var second: Dictionary = s.Spells.Summons.summon(s,d.hero,Vector2i(2,4),"skeleton")
	first.effect_target = int(d.foe.id); first.effect_hit_round = 0
	check(first.max_hp == 27,"summoner bone changes actual pet HP")
	check(Effects.modifier(s,"summon_power",second,{"source":second,"target":d.foe}) == 15,"the second pet striking a shared target gets the bonus immediately")
	d = Fixture.reset(s); Fixture.slot(d.hero,["KOBOLD_HEART"]); d.hero.effect_moved_round = 0; s.time = 100
	s.StoneEffects.round_start(s,d.hero)
	check(s.StoneEffects.Stacks.count(d.hero,"aim",s.time) == 0,"a completed moving round never builds aim at the next boundary")
	s.time = 200; s.Reactions.begin_action(s); s.StoneEffects.round_start(s,d.hero)
	check(s.StoneEffects.Stacks.count(d.hero,"aim",s.time) == 1,"a completed stationary round builds aim")
	d = Fixture.reset(s); Fixture.slot(d.hero,["TOAD_TONGUE","GOBLIN_TOOTH"])
	s.Abilities.element_mark(s,d.foe,"poison",d.hero); s.Reactions.begin_action(s); s.Abilities.element_mark(s,d.foe,"poison",d.hero)
	check(d.foe.status_power.poison_bonus == 1,"elemental part poison uses the same reapplication hook")
	d.foe.statuses.poison = -1; var hp_before: int = d.foe.hp; s.Statuses.tick(s)
	check(d.foe.hp == hp_before and not d.foe.status_power.has("poison_bonus"),"expired poison never deals an extra tick and clears its stack")
	# Every authored effect is resolvable; existing headline suite verifies the original 30.
	var count := 0
	for id in s.Essences.catalog():
		var row: Dictionary = s.Essences.row(id)
		if str(row.get("effect","")).is_empty(): continue
		count += 1; check(Effects.content.effects.has(row.effect),"part effect resolves: "+id)
	check(count == 90,"all thirty species have three active passive effects")
	Forms.force = -1; s.StoneEffects.force = -1
	print("Part effects: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
