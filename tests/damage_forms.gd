extends SceneTree
## Damage forms (2026-09-26 damage forms spec §4): which form a blow has, the
## skin and bone steps a species carries, the ±25% they make, and where the
## killing blow's form is written.
const Forms = preload("res://expedition/combat/forms.gd")
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")

var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	lookups(); body_steps(); scaling(); parts(); words()
	attacks(); kill_forms(); no_leak(); preview(); cleave(); real_spell(); cover()
	Forms.force = -1; StoneEffects.force = -1
	print("Damage forms: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func member(weapon: String) -> Dictionary:
	return {"enemy":false,"gear":{"weapon":{} if weapon.is_empty() else {"type":weapon}}}

func lookups() -> void:
	for pair in [["sword","SLASH"],["axe","SLASH"],["mace","IMPACT"],["staff","IMPACT"],["spear","PIERCE"],["dagger","PIERCE"],["bow","PIERCE"],["","IMPACT"]]:
		check(Forms.of_actor(member(pair[0])) == pair[1],"%s swings %s" % [pair[0],pair[1]])
	check(Forms.of_actor({"enemy":true,"species_id":"dcss_orc"}) == "SLASH","an orc cleaves")
	check(Forms.of_actor({"enemy":true,"species_id":"ore_golem"}) == "IMPACT","a golem slams")
	check(Forms.of_actor({"enemy":true,"species_id":"dcss_rat"}) == "PIERCE","a rat bites")
	check(Forms.of_actor({"enemy":true,"species_id":""}) == "IMPACT","a monster with no row slams")
	check(Forms.of_actor({"enemy":true,"species_id":"no_such"}) == "IMPACT","an unknown species slams")
	check(Forms.of_actor({"enemy":false,"summoned":true,"summon_kind":"hound"}) == "PIERCE","a hound bites")
	check(Forms.of_actor({"enemy":false,"summoned":true,"summon_kind":"no_such"}) == "IMPACT","an unknown summon slams")
	check(Forms.of_part({"species":"kobold"}) == "PIERCE","a part follows its species")
	check(Forms.of_part({"species":"kobold","form":"IMPACT"}) == "IMPACT","a part's own form wins")
	check(Forms.of_part({"species":""}) == "IMPACT","a basic part slams")
	for pair in [["bolt","PIERCE"],["line","PIERCE"],["burst","IMPACT"],["cone","IMPACT"],["wall","IMPACT"],["mark",""],["self",""],["summon",""],["",""]]:
		check(Forms.of_spell({"shape":pair[0]}) == pair[1],"spell shape %s is %s" % [pair[0],pair[1]])
	for pair in [["bleed","SLASH"],["poison","PIERCE"],["burn","IMPACT"],["freeze",""]]:
		check(Forms.of_dot(pair[0]) == pair[1],"%s ticks as %s" % [pair[0],pair[1]])

func body_steps() -> void:
	var beetle := {"enemy":true,"species_id":"rock_beetle"}
	var skeleton := {"enemy":true,"species_id":"skeleton_soldier"}
	check(Forms.skin(beetle) == 1 and Forms.bone(beetle) == 1,"a beetle is tough and hard")
	check(Forms.skin(skeleton) == -1 and Forms.bone(skeleton) == -1,"a skeleton is soft and brittle")
	check(Forms.skin(member("sword")) == 0 and Forms.bone(member("sword")) == 0,"a member is ordinary")
	check(Forms.skin({"enemy":true,"species_id":""}) == 0,"no row is ordinary")
	check(Forms.skin({"enemy":true,"summoned":true,"species_id":"dcss_rat"}) == 0 and Forms.bone({"enemy":true,"summoned":true,"species_id":"dcss_rat"}) == 0,"summons use neutral body steps on either side")
	for row in Forms.species_rows():
		check(str(row.get("form","")) in Forms.FORMS,"%s has a form" % row.species_id)
		check(int(row.get("skin",9)) in [-1,0,1] and int(row.get("bone",9)) in [-1,0,1],"%s has skin and bone steps" % row.species_id)

func scaling() -> void:
	var beetle := {"enemy":true,"species_id":"rock_beetle"}
	var skeleton := {"enemy":true,"species_id":"skeleton_soldier"}
	check(Forms.scale(100,"SLASH",beetle) == 75,"slash loses a quarter on tough skin")
	check(Forms.scale(100,"SLASH",skeleton) == 125,"slash gains a quarter on soft skin")
	check(Forms.scale(100,"IMPACT",beetle) == 75,"impact loses a quarter on hard bone")
	check(Forms.scale(100,"IMPACT",skeleton) == 125,"impact gains a quarter on brittle bone")
	check(Forms.scale(100,"PIERCE",beetle) == 100 and Forms.scale(100,"PIERCE",skeleton) == 100,"pierce ignores the body")
	check(Forms.scale(100,"",beetle) == 100,"no form, no change")
	check(Forms.scale(1,"SLASH",beetle) == 1,"never below one")
	check(Forms.wound_chance("SLASH",beetle) == 10 and Forms.wound_chance("SLASH",skeleton) == 30,"slash wounds by skin")
	check(Forms.wound_chance("IMPACT",beetle) == 10 and Forms.wound_chance("IMPACT",skeleton) == 30,"impact wounds by bone")
	check(Forms.wound_chance("PIERCE",beetle) == 20 and Forms.wound_chance("",beetle) == 0,"pierce is flat, nothing is nothing")
	check(Forms.fracture_percent({}) == 25 and Forms.fracture_percent({"boss":true}) == 12,"a boss limps half")

func parts() -> void:
	for form in ["SLASH","IMPACT","PIERCE",""]:
		var counts := {"cut":0,"broken":0,"pierced":0}
		for roll in range(100): counts[Forms.pick_part(form,roll)] += 1
		match form:
			"SLASH": check(counts.cut == 50 and counts.broken == 25 and counts.pierced == 25,"slash drops cut 50/25/25")
			"IMPACT": check(counts.broken == 50 and counts.pierced == 25 and counts.cut == 25,"impact drops broken 50/25/25")
			"PIERCE": check(counts.pierced == 50 and counts.cut == 25 and counts.broken == 25,"pierce drops pierced 50/25/25")
			"": check(counts.cut == 34 and counts.broken == 33 and counts.pierced == 33,"no form is even")

func words() -> void:
	check(Forms.form_name("SLASH") == "베기" and Forms.form_name("IMPACT") == "타격" and Forms.form_name("PIERCE") == "찌르기","form names")
	check(Forms.body_line({"enemy":true,"species_id":"rock_beetle"}) == "공격 타격 · 피부 질김 · 뼈 단단함","body line")
	check(Forms.weapon_label("장검","sword") == "장검 · 베기","weapon name carries its form")
	check(Forms.weapon_label("알 수 없음","no_such") == "알 수 없음","unknown weapon keeps its name")
	check(Forms.armour(10,"IMPACT") == 5 and Forms.armour(10,"PIERCE") == 10,"only impact halves armour")

## Hero at c with `weapon`, a foe of `species` at c+(1,0), nothing else awake.
func duel(weapon: String, species: String) -> Dictionary:
	StoneEffects.force = 99; Forms.force = 99  # no crits, no wounds
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.gear.weapon = {"type":weapon,"enchant":0}
	s.party[1].pos = c+Vector2i(-4,0)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = species
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0; foe.ac = 0
	# Isolate body scaling from the species' independent soul-stone passives.
	foe.boss = true
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":hero,"foe":foe}

## Mean damage of `tries` swings (dodge can miss: misses are skipped).
func swing(d: Dictionary, tries: int = 40) -> float:
	var s = d.s; var total := 0; var landed := 0
	for i in range(tries):
		d.foe.hp = 400
		s.Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.hero,d.foe)
		if out.hit: total += int(out.damage); landed += 1
	return float(total)/maxf(1.0,float(landed))

func attacks() -> void:
	var soft := swing(duel("sword","skeleton_soldier"))
	var tough := swing(duel("sword","rock_beetle"))
	check(soft > tough*1.4,"a sword bites a skeleton harder than a beetle (%.1f vs %.1f)" % [soft,tough])
	var brittle := swing(duel("mace","skeleton_soldier"))
	var hard := swing(duel("mace","rock_beetle"))
	check(brittle > hard*1.4,"a mace breaks a skeleton harder than a beetle (%.1f vs %.1f)" % [brittle,hard])
	var a := swing(duel("spear","skeleton_soldier")); var b := swing(duel("spear","rock_beetle"))
	check(absf(a-b) < 1.5,"a spear does not care (%.1f vs %.1f)" % [a,b])
	# Impact halves armour: a mace against AC 10 loses less than a sword does.
	var armoured := duel("mace","")
	armoured.foe.ac = 10
	var mace_ac := swing(armoured)
	var sword_ac_d := duel("sword",""); sword_ac_d.foe.ac = 10
	var sword_ac := swing(sword_ac_d)
	var mace_bare_d := duel("mace",""); var mace_bare := swing(mace_bare_d)
	var sword_bare_d := duel("sword",""); var sword_bare := swing(sword_bare_d)
	check(mace_bare-mace_ac < sword_bare-sword_ac,"impact loses less to armour (%.1f vs %.1f)" % [mace_bare-mace_ac,sword_bare-sword_ac])

func kill_forms() -> void:
	# A weapon kill writes the weapon's form.
	var d := duel("spear","dcss_rat")
	d.foe.hp = 1
	d.s.Reactions.begin_action(d.s)
	var out: Dictionary = Rules.attack(d.s,d.hero,d.foe)
	check(out.hit and d.foe.hp <= 0 and d.foe.last_form == "PIERCE","a spear kill is a pierce kill")
	# A blow after death changes nothing.
	d.s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(d.foe.last_form == "PIERCE","a corpse keeps its killing form")
	# A part writes its own species' form.
	var p := duel("sword","dcss_rat")
	p.foe.hp = 1
	Abilities.strike_victim(p.s,p.hero,p.foe,5,"IMPACT",Abilities.definition("KOBOLD_SLING"))
	check(p.foe.last_form == "PIERCE","a sling kill is a pierce kill")
	# Secondary damage writes none, even inside a blow.
	var r := duel("sword","dcss_rat")
	var was: String = Forms.begin(r.s,"SLASH")
	r.s.damage(r.foe,3,int(r.hero.id),"COUNTER")
	Forms.end(r.s,was)
	check(r.foe.last_form == "","a counter is no form")
	# Damage over time writes its status's form.
	var t := duel("sword","dcss_rat")
	t.foe.hp = 2; t.foe.statuses = {"bleed":t.s.time+300}
	for i in range(3): Statuses.tick(t.s)
	check(t.foe.hp <= 0 and t.foe.last_form == "SLASH","a bleed kill is a slash kill")
	# A spell writes its shape's form.
	var m := duel("staff","dcss_rat")
	m.foe.hp = 1
	var was_spell: String = Forms.begin(m.s,Forms.of_spell({"shape":"bolt"}))
	Spells.hurt(m.s,m.hero,m.foe,10,"fire")
	Forms.end(m.s,was_spell)
	check(m.foe.last_form == "PIERCE","a bolt kill is a pierce kill")
	# A covered hit writes on whoever took it.
	var g := duel("sword","dcss_rat")
	var ally: Dictionary = g.s.party[1]
	ally.pos = g.c+Vector2i(0,1)
	g.hero["protected_by"] = int(ally.id); ally["guarded"] = true
	var was_cover: String = Forms.begin(g.s,"IMPACT")
	g.s.damage(g.hero,3,int(g.foe.id),"physical")
	Forms.end(g.s,was_cover)
	var taker: Dictionary = ally if int(ally.hp) < int(ally.max_hp) else g.hero
	check(str(taker.get("last_form","")) == "IMPACT","the one who took the hit carries its form")

func no_leak() -> void:
	var d := duel("sword","dcss_rat")
	d.s.Reactions.begin_action(d.s)
	Rules.attack(d.s,d.hero,d.foe)
	check(d.s.blow_form == "","an attack leaves no form behind")
	d.foe.hp = 1
	Rules.attack(d.s,d.hero,d.foe)
	check(d.s.blow_form == "","a killing attack leaves no form behind")
	var p := duel("sword","dcss_rat")
	Abilities.strike_victim(p.s,p.hero,p.foe,5,"IMPACT",Abilities.definition("KOBOLD_SLING"))
	check(p.s.blow_form == "","a part leaves no form behind")
	var t := duel("sword","dcss_rat")
	t.foe.statuses = {"poison":t.s.time+300}
	Statuses.tick(t.s)
	check(t.s.blow_form == "","a tick leaves no form behind")

func preview() -> void:
	var d := duel("sword","rock_beetle")
	var tough: Dictionary = d.s.attack_preview(d.foe.pos)
	var e := duel("sword","skeleton_soldier")
	var soft: Dictionary = e.s.attack_preview(e.foe.pos)
	check(tough.form == "SLASH" and soft.form == "SLASH","the preview names the form")
	check(int(soft.damage_max) > int(tough.damage_max),"the preview scales by skin")

func cleave() -> void:
	for main_species in ["rock_beetle","skeleton_soldier"]:
		var d := duel("axe",main_species)
		var other: Dictionary = d.s.enemies[1]
		other.pos = d.c+Vector2i(0,1); other.hp = 400; other.max_hp = 400
		other.species_id = "skeleton_soldier"; other.boss = true; other.ac = 0; other.statuses = {}; other.res = {}
		var raw: int = int(d.s.CombatStats.stats(d.s,d.hero).damage)
		var expected: int = Forms.scale(raw/2,"SLASH",other)
		for _try in range(8):
			d.s.Reactions.begin_action(d.s)
			if Rules.attack(d.s,d.hero,d.foe).hit: break
		check(400-int(other.hp) == expected,"cleave scales each neighbour independently of "+main_species)
		check(str(other.get("last_form","")) == "SLASH" and d.s.blow_form == "","cleave keeps its form without leaking")

func real_spell() -> void:
	var d := duel("staff","dcss_rat")
	d.hero.essences = {"FIRE_CALLER":1}; d.hero.equipped_abilities = ["FIRE_CALLER"]
	d.hero.essence_spells = {"FIRE_CALLER":"fire_1"}
	d.s.Essences.sync_spells(d.hero)
	d.hero.mp = 100; d.foe.hp = 1
	for _try in range(16):
		if d.foe.hp <= 0: break
		check(Spells.cast(d.s,d.hero,"fire_1",d.foe.pos),"a real bolt cast is accepted")
		check(d.s.blow_form == "" and d.s.casting == 0,"a real cast restores damage context")
	check(d.foe.hp <= 0 and str(d.foe.get("last_form","")) == "PIERCE","the actual cast records the bolt's killing form")

func cover() -> void:
	var d := duel("sword","dcss_rat")
	var ally: Dictionary = d.s.party[1]
	ally.pos = d.c+Vector2i(0,1); ally.hp = ally.max_hp
	d.hero.protected_by = ally.id; ally.guarded = true
	ally.statuses["exposed"] = d.s.time+200
	var was: String = Forms.begin(d.s,"PIERCE")
	d.s.damage(d.hero,8,int(d.foe.id),"physical")
	Forms.end(d.s,was)
	check(not ally.statuses.has("exposed"),"the real recipient spends exposed vitals")
	check(not d.hero.has("last_form") and ally.last_form == "PIERCE","only the real recipient records the hit")
