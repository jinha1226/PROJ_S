extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Tactics = preload("res://expedition/ai/tactical_action_selector.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func arena(skill: String) -> Dictionary:
	var s = Session.new(731,true,false,true,1); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities = [skill,"GUARD"]; hero.rules = [Abilities.default_rule(skill),Abilities.default_rule("GUARD")]; hero.cooldowns = {}
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true
	foe.pos = c+Vector2i(1,0); s.floor_state.observe(s)
	hero.ap = 2 # two actions, so one skill use does not end the round
	s.mistake_override[hero.id] = false   # the parts and their rules are what is under test
	return {"s":s,"hero":hero,"foe":foe,"c":c}

func run() -> void:
	for id in ["ORE_SLAM","KOBOLD_SLING","SERPENT_SHED","GOBLIN_SHIV","BOMB","SHOCKWAVE","IRON_HIDE"]:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(def.has("effect") and def.has("axis") and def.has("rule_when"),"%s carries effect/axis/rule_when" % id)
		check(Rules.catalog().has(id) and Rules.valid(Abilities.default_rule(id)),"%s has a valid default rule" % id)
	check(Abilities.DEFINITIONS.BOMB.axis == "RANGED" and Abilities.DEFINITIONS.SHOCKWAVE.axis == "MAGIC" and Abilities.DEFINITIONS.IRON_HIDE.rule_when == "DANGER","legacy skills keep their axis and rule")
	check(Abilities.default_rule("SERPENT_SHED").when == "HP" and Abilities.default_rule("SERPENT_SHED").subject == "SELF","shed rule is self HP")
	# 내려찍기: adjacent only, fourteen plus strength, cooldown 3.
	var f := arena("ORE_SLAM"); var s = f.s
	var hp: int = f.foe.hp
	check(s.act("ORE_SLAM",f.foe.pos),"slam on an adjacent foe")
	check(hp-f.foe.hp >= Abilities.power(s,f.hero,Abilities.DEFINITIONS.ORE_SLAM,"ORE_SLAM") and f.hero.cooldowns.ORE_SLAM == 4,"slam deals its power and cools down 3 rounds")
	f = arena("ORE_SLAM"); s = f.s; f.foe.pos = f.c+Vector2i(2,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"ORE_SLAM",f.foe.pos),"slam needs adjacency")
	f = arena("ORE_SLAM"); s = f.s; f.foe.pos = f.c+Vector2i(1,1); s.floor_state.observe(s)
	check(Abilities.legal(s,f.hero,"ORE_SLAM",f.foe.pos),"slam reaches a diagonal neighbour")
	# 투석: range 4, line of sight, cooldown 2.
	f = arena("KOBOLD_SLING"); s = f.s; f.foe.pos = f.c+Vector2i(4,0); s.floor_state.observe(s)
	hp = f.foe.hp
	check(s.act("KOBOLD_SLING",f.foe.pos) and f.foe.hp < hp and f.hero.cooldowns.KOBOLD_SLING == 3,"sling hits at range four")
	f = arena("KOBOLD_SLING"); s = f.s; f.foe.pos = f.c+Vector2i(5,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"KOBOLD_SLING",f.foe.pos),"sling range is four")
	f = arena("KOBOLD_SLING"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.tile(f.c+Vector2i(2,0)).terrain = "wall"; s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"KOBOLD_SLING",f.foe.pos),"sling needs line of sight")
	# 허물 벗기: self only, sheds statuses, cooldown 4.
	f = arena("SERPENT_SHED"); s = f.s; f.hero.cooldowns = {"SERPENT_SHED":2}
	check(not Abilities.legal(s,f.hero,"SERPENT_SHED",f.hero.pos),"shed refused on cooldown")
	f = arena("SERPENT_SHED"); s = f.s; f.hero.statuses = {"poison":s.time+300}
	check(s.act("SERPENT_SHED",f.hero.pos) and not f.hero.statuses.has("poison") and f.hero.cooldowns.SERPENT_SHED == 5,"shed clears poison")
	f = arena("SERPENT_SHED"); s = f.s
	check(s.act("SERPENT_SHED",f.hero.pos) and f.hero.statuses.has("immune"),"shed leaves a round of immunity")
	# 기습 (lunge): move beside a foe within three, then strike.
	f = arena("GOBLIN_SHIV"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.floor_state.observe(s)
	var start: Vector2i = f.hero.pos; hp = f.foe.hp
	check(Abilities.lunge_cell(s,f.hero,"GOBLIN_SHIV",f.foe.pos) == f.c+Vector2i(2,-1),"lunge picks the nearest adjacent cell")
	check(s.act("GOBLIN_SHIV",f.foe.pos),"lunge accepted at range three")
	check(f.hero.pos != start and s.melee_reach(f.hero.pos,f.foe.pos) and f.foe.hp < hp and f.hero.cooldowns.GOBLIN_SHIV == 4,"lunge moves adjacent and strikes")
	f = arena("GOBLIN_SHIV"); s = f.s; f.foe.pos = f.c+Vector2i(4,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"GOBLIN_SHIV",f.foe.pos),"lunge range is three")
	f = arena("GOBLIN_SHIV"); s = f.s; f.foe.pos = f.c+Vector2i(3,0)
	for d in s.DIRECTIONS: s.tile(f.foe.pos+d).terrain = "wall"
	s.tile(f.foe.pos).terrain = "stone"; s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"GOBLIN_SHIV",f.foe.pos),"lunge needs a free adjacent cell")
	# Legacy skills unchanged until the old bosses go (plan 4/4).
	f = arena("BOMB"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.floor_state.observe(s); hp = f.foe.hp
	check(s.act("BOMB",f.foe.pos) and hp-f.foe.hp >= 16,"bomb still deals sixteen at range")
	f = arena("IRON_HIDE"); s = f.s
	check(s.act("IRON_HIDE",f.hero.pos) and f.hero.iron_guard,"iron hide still guards")
	# Default rules through the session paths.
	var s2 = Session.new(5,true,false,true,1); s2.depart()
	s2.phase = "CAMP"; s2.parts_bag["SERPENT_SHED"] = 1
	check(s2.equip_part(0,0,"SERPENT_SHED") and s2.party[0].rules.back().when == "HP" and s2.party[0].rules.back().subject == "SELF","equip_part uses the default rule")
	# Tactics offers every equipped skill as a candidate when legal.
	for id in ["ORE_SLAM","KOBOLD_SLING","GOBLIN_SHIV","BOMB"]:
		# A bomb beside the hero would catch the hero, so it is thrown from afar,
		# and a sling is not drawn in contact either: `contact_penalty` holsters a
		# RANGED part of range 3+ while a foe is in melee reach.
		f = arena(id); s = f.s; f.foe.pos = f.c+Vector2i(3 if id in ["BOMB","KOBOLD_SLING"] else 1,0); s.floor_state.observe(s)
		f.hero.rules = [Rules.make_rule(id,"NEAREST","ALWAYS")]
		check(Tactics.choose(s,f.hero).kind == id,"rule engine picks %s when its rule is first" % id)
	f = arena("SERPENT_SHED"); s = f.s; f.hero.hp = 10; f.hero.rules = [Abilities.default_rule("SERPENT_SHED")]
	check(Tactics.choose(s,f.hero).kind == "SERPENT_SHED","rule engine sheds below half health")
	f.hero.hp = f.hero.max_hp
	check(Tactics.choose(s,f.hero).kind != "SERPENT_SHED","rule engine does not shed at full health")
	print("Skill archetypes: %d failures" % failures); quit(1 if failures else 0)
