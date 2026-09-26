extends SceneTree
const Essences = preload("res://expedition/progression/essences.gd")
## Battle test mode: a throwaway session dropped straight into an arena with
## freely chosen parts and stances; the town session is never touched.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	session()
	await scene()
	await custom()
	print("Arena mode: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func session() -> void:
	check(Session.ARENA_PRESETS.size() == 7 and Session.ARENA_PRESETS.has("early_hob") and Session.ARENA_PRESETS.has("custom"),"six presets plus custom")
	var members := [{"stance":"CHARGER","parts":["ORE_SLAM","GUARD"]},{"stance":"SKIRMISHER","parts":["KOBOLD_SLING",""]},{"stance":"GUARDIAN","parts":["PUSH","GUARD"]}]
	var t = Session.arena_test(42,3,Session.ARENA_PRESETS.opt_archers,members)
	check(t.phase == "BATTLE" and t.party.size() == 3 and t.in_combat(),"arena session is a floor battle")
	check(t.enemies.size() == 3 and t.enemies.all(func(e): return e.hp > 0),"opt_archers roster spawned")
	check(t.party[0].stance == "CHARGER" and t.party[0].equipped_abilities == [Essences.canonical("ORE_SLAM"),"GUARD"] and t.party[0].rules.any(func(r): return r.skill == "ORE_SLAM"),"member setup applied with default rules")
	check(t.party[1].equipped_abilities == [Essences.canonical("KOBOLD_SLING"),""],"empty slot allowed")
	check(t.party.all(func(a): return a.hp == a.max_hp),"full health")
	check(t.auto_stop_reason() == "BATTLE_START","starts stopped at battle start")
	var rounds := 0
	while t.in_combat() and rounds < 60: t.auto_step(); rounds += 1
	check(rounds > 0 and rounds < 60,"the fight resolves")
	var custom := {"members":[["dcss_rat","MELEE"],["goblin","CASTER"]]}
	var c = Session.arena_test(7,1,custom,[{"stance":"CHARGER","parts":["PUSH",""]}])
	check(c.enemies.size() == 2 and c.party.size() == 1,"custom roster, light and party size")
	check(Session.arena_test(42,3,Session.ARENA_PRESETS.opt_archers,members).enemies[0].pos == t.enemies[0].pos,"same seed, same layout")
	# Solo guardian is coerced to charger.
	var g = Session.arena_test(1,1,Session.ARENA_PRESETS.early_hob,[{"stance":"GUARDIAN","parts":["",""]}])
	check(g.party[0].stance == "CHARGER","solo cannot test as a guardian")

func scene() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(3): await process_frame
	var button: Button = scene.find_child("ArenaButton",true,false)
	check(button != null and button.text == "전투 시험","start offers the battle test")
	button.pressed.emit()
	for frame in range(3): await process_frame
	var setup = scene.find_child("ArenaSetup",true,false)
	check(setup != null,"setup screen")
	check(scene.find_child("ArenaPick",true,false).item_count == 7 and scene.find_child("ArenaSize",true,false) != null,"arena picker and party size")
	check(scene.find_children("ArenaMember*","Control",true,false).size() == 1,"arena starts with one hero")
	scene.find_child("ArenaSize",true,false).item_selected.emit(2)
	for frame in range(3): await process_frame
	check(scene.find_children("ArenaMember*","Control",true,false).size() == 3,"three member test is selectable")
	var part0 = scene.find_child("ArenaPart_0_0",true,false)
	check(part0 != null and part0.item_count == Abilities.DEFINITIONS.size()+1,"part picker lists every catalog part plus empty")
	# One part, one slot: the pair of pickers cannot both land on the same part.
	var club: int = Abilities.DEFINITIONS.keys().find("ORE_SLAM")+1
	part0.item_selected.emit(club)
	for frame in range(3): await process_frame
	check(scene.arena_config.members[0].parts[0] == "ORE_SLAM","the part choice is recorded")
	check(scene.find_child("ArenaPart_0_1",true,false).is_item_disabled(club),"the other slot greys the part out")
	check(not scene.find_child("ArenaPart_1_1",true,false).is_item_disabled(club),"another member may still take it")
	check(scene.find_child("ArenaStance_0_SKIRMISHER",true,false) == null,"the manually controlled hero has no stance picker")
	scene.find_child("ArenaStance_1_SKIRMISHER",true,false).pressed.emit(); await process_frame
	check(scene.arena_config.members[1].stance == "SKIRMISHER","companion stance choice recorded")
	scene.find_child("ArenaStart",true,false).pressed.emit()
	for frame in range(4): await process_frame
	check(scene.session != null and scene.session.in_combat(),"start swaps in an arena session")
	check(scene.find_child("AutoToggle",true,false) == null and scene.find_child("HeroStatus",true,false) != null,"manual arena HUD")
	var guard := 0
	while scene.session.in_combat() and guard < 80:
		var hero: Dictionary = scene.session.party[0]
		hero.ap = 1
		var choice: Dictionary = scene.session.Tactics.choose(scene.session,hero)
		if not scene.session.submit(str(choice.get("kind","WAIT")),choice.get("cell",hero.pos)):
			scene.session.submit("WAIT",hero.pos)
		guard += 1
	scene.report_battle()
	for frame in range(4): await process_frame
	var report = scene.find_child("BattleReport",true,false)
	check(report != null and report.visible,"report at the end")
	var buttons: Array = report.find_children("*","Button",true,false).map(func(b): return b.text)
	check("설정으로" in buttons and "다시" in buttons,"report offers setup and retry")
	scene.leave_arena()
	for frame in range(3): await process_frame
	check(scene.session == null and scene.find_child("StartScreen",true,false) != null,"returns to start screen")
	scene.queue_free(); await process_frame

## The setup screen's own controls: party size, the hand-made roster, and a
## wipe that ends in the report card instead of the town.
func custom() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for frame in range(4): await process_frame
	scene.find_child("ArenaButton",true,false).pressed.emit()
	for frame in range(3): await process_frame
	scene.find_child("ArenaSize",true,false).item_selected.emit(0)
	for frame in range(3): await process_frame
	check(scene.find_children("ArenaMember*","Control",true,false).size() == 1,"one card at a party size of one")
	check(scene.find_child("ArenaStance_0_GUARDIAN",true,false) == null,"solo hero has no auto-battle stance picker")
	scene.find_child("ArenaPick",true,false).item_selected.emit(Session.ARENA_PRESETS.keys().find("custom"))
	for frame in range(3): await process_frame
	var foes: Array = scene.find_children("ArenaFoe*","Control",true,false)
	check(foes.size() == 3 and foes[0].item_count == 1+Session.Encounters.table().size()*3,"three foe slots cover the full species catalog")
	check(scene.find_child("ArenaStart",true,false).disabled,"an empty hand-made roster is not a fight")
	foes[0].item_selected.emit(1)
	for frame in range(3): await process_frame
	check(scene.arena_config.custom[0] == ["dcss_rat","MELEE"],"the foe choice is recorded as a species and a role")
	check(not scene.find_child("ArenaStart",true,false).disabled,"one foe is enough to start")
	scene.find_child("ArenaStart",true,false).pressed.emit()
	for frame in range(4): await process_frame
	check(scene.session.enemies.size() == 1 and scene.session.party.size() == 1,"the hand-made roster is what spawns")
	# A wipe is the test's own business: no town screen, no result card.
	for actor in scene.session.party: actor.hp = 0
	scene.session.check_battle_end(); scene.refresh()
	for frame in range(3): await process_frame
	check(scene.session.phase == "DEFEAT" and scene.find_child("SettlementHub",true,false) == null,"a wiped test party never lands in town")
	scene.report_battle()
	for frame in range(3): await process_frame
	var buttons: Array = scene.find_child("BattleReport",true,false).find_children("*","Button",true,false)
	buttons.filter(func(b): return b.text == "설정으로")[0].pressed.emit()
	for frame in range(3): await process_frame
	check(scene.find_child("ArenaSetup",true,false) != null and str(scene.arena_config.arena) == "custom","the report returns to the setup screen with the same settings")
	scene.find_child("ArenaBack",true,false).pressed.emit()
	for frame in range(3): await process_frame
	check(scene.session == null and scene.find_child("StartScreen",true,false) != null,"back returns to start screen")
	scene.queue_free(); await process_frame
