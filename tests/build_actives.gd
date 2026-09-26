extends SceneTree
## Real build actions: permanent stones grant usable, resource-limited skills.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Builds = preload("res://expedition/progression/example_builds.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Summons = preload("res://expedition/spells/summons.gd")
const Parts = preload("res://expedition/ai/parts_candidates.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Lookahead = preload("res://expedition/ai/lookahead.gd")
const Hud = preload("res://expedition/ui/screens/floor_hud.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s = Session.new_run(731); var hero: Dictionary = s.party[0]
	for npc in s.roster:
		for id in Abilities.held(npc):
			check(npc.rules.any(func(r): return r.skill == id),"initial NPC owns its granted action rule: "+str(id))
	Fixture.arena(s,8); s.phase = "CAMP"
	s.grant_part("GRAVEKEEPER/pierced")
	check(s.absorb_essence(0,"GRAVEKEEPER/pierced").is_empty(),"a death stone permanently absorbed")
	check(Abilities.holds(hero,"BONE_CALL") and hero.rules.any(func(r): return r.skill == "BONE_CALL"),"a necromancer owns an actual summon action and AI rule")
	check(not Abilities.holds(hero,"GRAVEKEEPER"),"the monster-only attack is not advertised as a player action")
	s.phase = "BATTLE"; hero.ap = 1
	var summon_choice: Dictionary = s.Tactics.choose(s,hero)
	check(summon_choice.kind == "BONE_CALL","utility AI selects the necromancer summon action")
	var mp: int = hero.mp
	check(Abilities.execute(s,hero,"BONE_CALL",hero.pos),"the summon action executes")
	var pets: Array = Summons.summons_of(s,hero)
	check(pets.size() == 1 and pets[0].summon_kind == "skeleton" and pets[0].summoner == hero.id,"a living allied skeleton is actually created")
	check(hero.mp == mp-6 and Abilities.cooldown(hero,"BONE_CALL") > 0,"summoning costs MP and starts a cooldown")
	hero.cooldowns.clear()
	check(not Abilities.legal(s,hero,"BONE_CALL",hero.pos),"a full summon limit blocks repeated summoning")
	if not pets.is_empty(): pets[0].hp = 0
	hero.mp = 5
	check(not Abilities.execute(s,hero,"BONE_CALL",hero.pos) and hero.mp == 5,"insufficient MP changes nothing")
	hero.mp = mp; hero.ap = 1
	var cells: Array = Summons.summon_cells(s,hero)
	for cell in cells: s.tile(cell).terrain = "wall"
	check(not Abilities.execute(s,hero,"BONE_CALL",hero.pos) and hero.mp == mp,"no placement spends no MP")
	for cell in cells: s.tile(cell).terrain = "stone"
	s.phase = "CAMP"; s.gain_level_xp(hero,65)
	s.grant_part("WATER_WAVE/pierced")
	check(s.absorb_essence(0,"WATER_WAVE/pierced").is_empty() and Abilities.holds(hero,"SOUL_MEND"),"a healing stone grants a usable healing action")
	s.phase = "BATTLE"; hero.ap = 1; hero.hp = 10; hero.mp = mp
	var healing: Array = Parts.candidates(s,hero).filter(func(o): return o.kind == "SOUL_MEND" and o.cell == hero.pos)
	check(healing.size() == 1,"utility AI receives a legal self-healing candidate")
	check(not healing.is_empty() and Rules.matches(s,hero,healing[0],Abilities.default_rule("SOUL_MEND")),"the healing rule recognizes its own low HP")
	var chosen: Dictionary = s.Tactics.choose(s,hero)
	check(chosen.kind == "SOUL_MEND","a critically injured AI member selects its actual healing skill")
	var before: int = hero.hp
	check(Abilities.execute(s,hero,"SOUL_MEND",hero.pos) and hero.hp > before and hero.mp == mp-5,"healing actually restores HP and spends MP")
	hero.cooldowns.clear(); hero.hp = hero.max_hp
	check(not Abilities.legal(s,hero,"SOUL_MEND",hero.pos),"a full-health target cannot waste the action")
	var ally: Dictionary = s.make_actor(888,"동료",false)
	ally.pos = hero.pos+Vector2i.RIGHT; ally.hp = 8; ally.max_hp = 40
	s.party.append(ally); hero.mp = mp
	healing = Parts.candidates(s,hero).filter(func(o): return o.kind == "SOUL_MEND" and o.cell == ally.pos)
	check(healing.size() == 1,"utility AI also receives the injured ally")
	check(Abilities.execute(s,hero,"SOUL_MEND",ally.pos) and ally.hp > 8 and hero.hp == hero.max_hp,"the selected ally is healed, not the caster")
	hero.cooldowns.clear(); hero.mp = mp
	ally.pos = hero.pos+Vector2i(4,0)
	check(not Abilities.legal(s,hero,"SOUL_MEND",ally.pos),"a distant ally is out of reach")
	# No unowned extra skill; temporary seals revoke the action as well as its passive.
	var stranger: Dictionary = s.make_actor(999,"무능력",false)
	check(not Abilities.holds(stranger,"BONE_CALL") and not Abilities.holds(stranger,"SOUL_MEND"),"basic actions are not granted to everybody")
	hero.sealed = {Essences.canonical("WATER_WAVE/pierced"):9999}
	check(not Abilities.holds(hero,"SOUL_MEND"),"sealed stone loses its associated skill")
	hero.sealed = {}
	for b in ["lord_of_dead","elementalist","hexer","water_priest"]:
		check(Builds.apply(s,hero,b),"example applies: "+b)
		if b == "lord_of_dead":
			check(hero.prepared.any(func(id): return Essences.combat.spells[id].shape == "summon"),"summoning build keeps a real summon rather than a maintenance buff")
		elif b in ["elementalist","hexer"]:
			check(not hero.prepared.is_empty() and hero.prepared.all(func(id): return Essences.combat.spells[id].shape != "self"),"caster build keeps a usable combat spell: "+b)
		else: check(Abilities.holds(hero,"SOUL_MEND"),"healer example has an active heal")
	# The menu exposes actual actions and their resource costs.
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(4): await process_frame
	s.grant_part("GRAVEKEEPER/pierced")
	scene.show_supplies(); scene.show_item_detail(Essences.canonical("GRAVEKEEPER/pierced"))
	for _i in range(3): await process_frame
	check(scene.item_detail.find_children("*","Label",true,false).any(func(l): return l.text.contains("해골 하나 소환") and l.text.contains("MP 6")),"inventory previews the real skill before permanent absorption")
	scene.item_popup.hide()
	s.phase = "BATTLE"; hero.ap = 1; hero.hp = hero.max_hp/2
	Hud.show_manual_skills(scene)
	for _i in range(3): await process_frame
	var heal_button: Button = scene.modal_content.find_child("Part_SOUL_MEND",true,false)
	check(heal_button != null and heal_button.text.contains("MP 5"),"skill menu exposes the actual heal and its MP cost")
	check(not scene.modal_content.find_children("Part_*","Button",true,false).any(func(b): return b.name == "Part_GRAVEKEEPER"),"unusable monster techniques stay out of the menu")
	scene.queue_free(); await process_frame
	print("Build actives: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
