extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Randart = preload("res://expedition/items/randart.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func wear(actor: Dictionary, id: String) -> void:
	var row: Dictionary = Randart.artifacts.filter(func(r): return r.id == id)[0]
	var item: Dictionary = row.duplicate(true); item.tier = "unrand"
	Equipment.worn(actor)[Equipment.slot(item)] = item
func run() -> void:
	var d := Fixture.reset(); var s = d.s
	check(Randart.artifacts.size() == 12,"twelve fixed artifacts")
	var seen: Array = []
	for i in range(12):
		var item := Randart.make(s,7000+i,"sword","unrand")
		check(item.tier == "unrand" and item.unrand not in seen,"artifact types appear once per run")
		check(item.affix in s.StoneEffects.effects({"gear":{Equipment.slot(item):item}}),"fixed effect is collected by runtime")
		check(not Equipment.description(item).is_empty(),"effect and price are visible immediately")
		seen.append(item.unrand)
	d = Fixture.reset(s); wear(d.hero,"AXE"); d.hero.hp = 40
	check(s.StoneEffects.heal(s,d.hero,20,d.ally) == 10,"axe halves external healing")
	d.foe.hp = 0; s.StoneEffects.on_kill(s,d.hero,d.foe,{"victim_statuses":{"bleed":300}})
	check(d.hero.hp == 55,"axe heals on bleeding kills without halving its own heal")
	d = Fixture.reset(s); wear(d.hero,"CHAIN"); d.hero.hp = 30
	check(s.StoneEffects.modifier(s,"attack_percent",d.hero) == 40 and s.StoneEffects.modifier(s,"taken_percent",d.hero) == 0,"chain rewards low HP")
	d.hero.hp = 31; check(s.StoneEffects.modifier(s,"taken_percent",d.hero) == 10,"chain penalty switches above threshold")
	d = Fixture.reset(s); wear(d.ally,"OATH"); s.StoneEffects.force = 99
	s.CombatRules.damage(s,d.foe,d.hero,20,"physical")
	check(d.hero.hp == 84 and d.ally.hp == 96,"oath transfers exactly twenty percent once")
	d = Fixture.reset(s); wear(d.hero,"BOW"); d.hero.effect_moved_round = 0
	check(not s.act_as(d.hero,"ATTACK",d.foe.pos,false),"bow rejects attacks in a moved round")
	s.time = 100; check(s.StoneEffects.modifier(s,"no_attack_after_move",d.hero) == 1,"bow still carries its restriction after the round")
	d = Fixture.reset(s); wear(d.hero,"ORB"); s.StoneEffects.force = 0
	s.Reactions.announce(s,d.foe.pos,"shatter",d.hero)
	var lost: int = s.Reactions.react_damage(s,d.hero,d.foe,10,"physical")
	check(lost == 20,"orb repeats reaction damage once without repeating the event")
	s.Reactions.announce(s,d.foe.pos,"steam",d.hero)
	check(s.Reactions.reaction_damage(d.hero,10,s) == 10,"a later non-damage reaction cannot inherit an earlier repeat")
	d = Fixture.reset(s); wear(d.hero,"HORN")
	check(s.StoneEffects.summon_extra(d.hero,s) == 2,"horn increases the shared summon limit")
	var pet: Dictionary = s.Spells.Summons.summon(s,d.hero,Vector2i(2,3),"skeleton")
	check(pet.expires_at == 150,"horn halves summon lifetime")
	d = Fixture.reset(s); wear(d.hero,"MASK")
	check(s.Forms.pick_part("PIERCE",79,s.StoneEffects.modifier(s,"part_own_percent",d.hero)) == "pierced","mask gives eighty-percent preferred part chance")
	d = Fixture.reset(s); wear(d.hero,"PLAGUE"); d.foe.hp = 0
	s.StoneEffects.on_kill(s,d.hero,d.foe,{"victim_statuses":{"poison":300}})
	check(s.StoneEffects.modifier(s,"res.poison",d.hero) == -50,"plague pouch pays poison resistance")
	d = Fixture.reset(s); wear(d.hero,"DEAD"); d.foe.hp = 0
	s.StoneEffects.on_kill(s,d.hero,d.foe,{"victim_statuses":{}})
	check(s.npcs.size() == 1 and s.npcs[0].summon_kind == "skeleton" and s.npcs[0].expires_at == 100,"dead ring raises a short-lived skeleton")
	d = Fixture.reset(s); wear(d.hero,"DAGGER"); d.foe.statuses.exposed = 300
	check(s.StoneEffects.crit_chance(s,d.hero,d.foe) == 100,"needle dagger guarantees exposed criticals")
	check(s.StoneEffects.modifier(s,"noncrit_percent",d.hero) == -25,"needle dagger retains noncritical cost")
	d = Fixture.reset(s); wear(d.hero,"HEX"); d.foe.statuses = {"bleed":300,"poison":300,"weak":300,"fracture":300}
	check(s.StoneEffects.modifier(s,"attack_percent",d.hero,{"target":d.foe}) == 100,"grudge ring doubles at four harmful statuses")
	d = Fixture.reset(s); wear(d.hero,"SHIELD")
	check(s.CombatStats.stats(s,d.hero).sh == 30 and s.StoneEffects.modifier(s,"move_delay_percent",d.hero) == 15,"shield has both block and movement price")
	s.StoneEffects.force = -1
	print("Unrands: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
