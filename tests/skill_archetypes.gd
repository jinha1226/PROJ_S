extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func arena(skill: String) -> Dictionary:
	var s = Session.new(731,true,false,true,1); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.learned_abilities = ["PUSH","GUARD",skill]; hero.equipped_abilities = [skill,"GUARD"]; hero.cooldowns = {}
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true
	foe.pos = c+Vector2i(1,0); s.floor_state.observe(s)
	hero.ap = 2 # two actions, so one skill use does not end the round
	return {"s":s,"hero":hero,"foe":foe,"c":c}

func run() -> void:
	for id in ["HEAVY_STRIKE","THROWING_KNIFE","FIELD_DRESSING","LUNGE","BOMB","SHOCKWAVE","IRON_HIDE"]:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(def.has("effect") and def.has("axis") and def.has("rule_when"),"%s carries effect/axis/rule_when" % id)
		check(Rules.SKILLS.has(id) and Rules.valid(Abilities.default_rule(id)),"%s has a valid default rule" % id)
	check(Abilities.DEFINITIONS.BOMB.axis == "RANGED" and Abilities.DEFINITIONS.SHOCKWAVE.axis == "MAGIC" and Abilities.DEFINITIONS.IRON_HIDE.rule_when == "DANGER","legacy skills keep their axis and rule")
	check(Abilities.default_rule("FIELD_DRESSING").when == "HP" and Abilities.default_rule("FIELD_DRESSING").subject == "SELF","dressing rule is self HP")
	# Heavy strike: adjacent only, 28 base, cooldown 3.
	var f := arena("HEAVY_STRIKE"); var s = f.s
	var hp: int = f.foe.hp
	check(s.act("HEAVY_STRIKE",f.foe.pos),"heavy strike on an adjacent foe")
	check(hp-f.foe.hp >= 28 and f.hero.cooldowns.HEAVY_STRIKE == 4,"heavy strike deals at least 28 and cools down 3 rounds")
	f = arena("HEAVY_STRIKE"); s = f.s; f.foe.pos = f.c+Vector2i(2,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"HEAVY_STRIKE",f.foe.pos),"heavy strike needs adjacency")
	f = arena("HEAVY_STRIKE"); s = f.s; f.foe.pos = f.c+Vector2i(1,1); s.floor_state.observe(s)
	check(Abilities.legal(s,f.hero,"HEAVY_STRIKE",f.foe.pos),"heavy strike reaches a diagonal neighbour")
	# Throwing knife: range 4, line of sight, cooldown 1.
	f = arena("THROWING_KNIFE"); s = f.s; f.foe.pos = f.c+Vector2i(4,0); s.floor_state.observe(s)
	hp = f.foe.hp
	check(s.act("THROWING_KNIFE",f.foe.pos) and f.foe.hp < hp and f.hero.cooldowns.THROWING_KNIFE == 2,"knife hits at range four")
	f = arena("THROWING_KNIFE"); s = f.s; f.foe.pos = f.c+Vector2i(5,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"THROWING_KNIFE",f.foe.pos),"knife range is four")
	f = arena("THROWING_KNIFE"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.tile(f.c+Vector2i(2,0)).terrain = "wall"; s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"THROWING_KNIFE",f.foe.pos),"knife needs line of sight")
	# Field dressing: self only, not at full health, +15, cooldown 4.
	f = arena("FIELD_DRESSING"); s = f.s
	check(not Abilities.legal(s,f.hero,"FIELD_DRESSING",f.hero.pos),"dressing refused at full health")
	f.hero.hp = 20
	check(s.act("FIELD_DRESSING",f.hero.pos) and f.hero.hp == 35 and f.hero.cooldowns.FIELD_DRESSING == 5,"dressing heals fifteen")
	f = arena("FIELD_DRESSING"); s = f.s; f.hero.hp = f.hero.max_hp-5
	check(s.act("FIELD_DRESSING",f.hero.pos) and f.hero.hp == f.hero.max_hp,"dressing never overheals")
	# Lunge: move beside a foe within three, then strike.
	f = arena("LUNGE"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.floor_state.observe(s)
	var start: Vector2i = f.hero.pos; hp = f.foe.hp
	check(Abilities.lunge_cell(s,f.hero,f.foe.pos) == f.c+Vector2i(2,-1),"lunge picks the nearest adjacent cell")
	check(s.act("LUNGE",f.foe.pos),"lunge accepted at range three")
	check(f.hero.pos != start and s.melee_reach(f.hero.pos,f.foe.pos) and f.foe.hp < hp and f.hero.cooldowns.LUNGE == 4,"lunge moves adjacent and strikes")
	f = arena("LUNGE"); s = f.s; f.foe.pos = f.c+Vector2i(4,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"LUNGE",f.foe.pos),"lunge range is three")
	f = arena("LUNGE"); s = f.s; f.foe.pos = f.c+Vector2i(3,0)
	for d in s.DIRECTIONS: s.tile(f.foe.pos+d).terrain = "wall"
	s.tile(f.foe.pos).terrain = "stone"; s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"LUNGE",f.foe.pos),"lunge needs a free adjacent cell")
	# Legacy skills unchanged.
	f = arena("BOMB"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.floor_state.observe(s); hp = f.foe.hp
	check(s.act("BOMB",f.foe.pos) and hp-f.foe.hp >= 16,"bomb still deals sixteen at range")
	f = arena("IRON_HIDE"); s = f.s
	check(s.act("IRON_HIDE",f.hero.pos) and f.hero.iron_guard,"iron hide still guards")
	# Default rules through the session paths.
	var s2 = Session.new(5,true,false,true,1); s2.depart()
	s2.essences["FIELD_DRESSING"] = 1
	check(s2.consume_essence(0,"FIELD_DRESSING") and s2.party[0].rules.back().when == "HP" and s2.party[0].rules.back().subject == "SELF","consume_essence uses the default rule")
	s2.reset_rules(0)
	check(s2.party[0].rules.any(func(r): return r.skill == "FIELD_DRESSING" and r.when == "HP"),"reset_rules uses the default rule")
	# Tactics offers every equipped skill as a candidate when legal.
	for id in ["HEAVY_STRIKE","THROWING_KNIFE","LUNGE","BOMB"]:
		# A bomb beside the hero would catch the hero, so it is thrown from afar.
		f = arena(id); s = f.s; f.foe.pos = f.c+Vector2i(3 if id == "BOMB" else 1,0); s.floor_state.observe(s)
		f.hero.rules = [Rules.make_rule(id,"NEAREST","ALWAYS")]
		check(Tactics.choose(s,f.hero).kind == id,"rule engine picks %s when its rule is first" % id)
	f = arena("FIELD_DRESSING"); s = f.s; f.hero.hp = 10; f.hero.rules = [Abilities.default_rule("FIELD_DRESSING")]
	check(Tactics.choose(s,f.hero).kind == "FIELD_DRESSING","rule engine heals below half health")
	f.hero.hp = f.hero.max_hp
	check(Tactics.choose(s,f.hero).kind != "FIELD_DRESSING","rule engine does not heal at full health")
	print("Skill archetypes: %d failures" % failures); quit(1 if failures else 0)
