extends SceneTree
## Battle test mode: a throwaway session dropped straight into an arena with
## freely chosen parts and stances; the town session is never touched.
const Session = preload("res://expedition/session.gd")
const Abilities = preload("res://expedition/abilities.gd")
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
	var members := [{"stance":"CHARGER","parts":["HOB_CLUB","GUARD"]},{"stance":"SKIRMISHER","parts":["KOBOLD_SLING",""]},{"stance":"GUARDIAN","parts":["PUSH","GUARD"]}]
	var t = Session.arena_test(42,3,Session.ARENA_PRESETS.opt_archers,members)
	check(t.floor_mode and t.phase == "BATTLE" and t.party.size() == 3 and t.in_combat(),"arena session is a floor battle")
	check(t.enemies.size() == 3 and t.enemies.all(func(e): return e.hp > 0),"opt_archers roster spawned")
	check(t.party[0].stance == "CHARGER" and t.party[0].equipped_abilities == ["HOB_CLUB","GUARD"] and t.party[0].rules.any(func(r): return r.skill == "HOB_CLUB"),"member setup applied with default rules")
	check(t.party[1].equipped_abilities == ["KOBOLD_SLING",""],"empty slot allowed")
	check(t.party.all(func(a): return a.hp == a.max_hp),"full health")
	check(t.auto_stop_reason() == "BATTLE_START","starts stopped at battle start")
	var rounds := 0
	while t.in_combat() and rounds < 60: t.auto_step(); rounds += 1
	check(rounds > 0 and rounds < 60,"the fight resolves")
	var custom := {"members":[["dcss_rat","MELEE"],["goblin","CASTER"]],"light":40}
	var c = Session.arena_test(7,1,custom,[{"stance":"CHARGER","parts":["PUSH",""]}])
	check(c.enemies.size() == 2 and c.light == 40 and c.party.size() == 1,"custom roster, light and party size")
	check(Session.arena_test(42,3,Session.ARENA_PRESETS.opt_archers,members).enemies[0].pos == t.enemies[0].pos,"same seed, same layout")
	# Solo guardian is coerced to charger.
	var g = Session.arena_test(1,1,Session.ARENA_PRESETS.early_hob,[{"stance":"GUARDIAN","parts":["",""]}])
	check(g.party[0].stance == "CHARGER","solo cannot test as a guardian")

func scene() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var town = Session.new(731,true,true,true,3)
	scene.session = town; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(3): await process_frame
	var bag: Dictionary = town.parts_bag.duplicate(true); var bank: int = town.bank
	var button: Button = scene.find_child("TownArena",true,false)
	check(button != null and button.text == "전투 시험","town offers the battle test")
	button.pressed.emit()
	for frame in range(3): await process_frame
	var setup = scene.find_child("ArenaSetup",true,false)
	check(setup != null,"setup screen")
	check(scene.find_child("ArenaPick",true,false).item_count == 7 and scene.find_child("ArenaSize",true,false) != null,"arena picker and party size")
	check(scene.find_children("ArenaMember*","Control",true,false).size() == 3,"three member cards")
	var part0 = scene.find_child("ArenaPart_0_0",true,false)
	check(part0 != null and part0.item_count == Abilities.DEFINITIONS.size()+1,"part picker lists every catalog part plus empty")
	scene.find_child("ArenaStance_0_SKIRMISHER",true,false).pressed.emit(); await process_frame
	check(scene.arena_config.members[0].stance == "SKIRMISHER","stance choice recorded")
	scene.find_child("ArenaStart",true,false).pressed.emit()
	for frame in range(4): await process_frame
	check(scene.session != town and scene.session.floor_mode and scene.session.in_combat(),"start swaps in an arena session")
	check(scene.find_child("AutoToggle",true,false) != null and scene.find_child("StopBanner",true,false).text.begins_with("전투 시작"),"battle HUD with the start banner")
	scene.session.auto.running = true
	var guard := 0
	while scene.session.in_combat() and guard < 80: scene.auto_tick(); guard += 1
	for frame in range(4): await process_frame
	var report = scene.find_child("BattleReport",true,false)
	check(report != null and report.visible,"report at the end")
	var buttons: Array = report.find_children("*","Button",true,false).map(func(b): return b.text)
	check("설정으로" in buttons and "다시" in buttons,"report offers setup and retry")
	scene.leave_arena()
	for frame in range(3): await process_frame
	check(scene.session == town and town.parts_bag == bag and town.bank == bank and town.phase == "TOWN","town session untouched")
	scene.queue_free(); await process_frame

## The setup screen's own controls: party size, the hand-made roster, and a
## wipe that ends in the report card instead of the town.
func custom() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var town = Session.new(97,true,true,true,3)
	scene.session = town; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for frame in range(4): await process_frame
	scene.find_child("TownArena",true,false).pressed.emit()
	for frame in range(3): await process_frame
	scene.find_child("ArenaSize",true,false).item_selected.emit(0)
	for frame in range(3): await process_frame
	check(scene.find_children("ArenaMember*","Control",true,false).size() == 1,"one card at a party size of one")
	check(scene.find_child("ArenaStance_0_GUARDIAN",true,false).disabled,"solo cannot be set to guardian")
	scene.find_child("ArenaPick",true,false).item_selected.emit(Session.ARENA_PRESETS.keys().find("custom"))
	for frame in range(3): await process_frame
	var foes: Array = scene.find_children("ArenaFoe*","Control",true,false)
	check(foes.size() == 3 and foes[0].item_count == 25,"three foe slots, none plus eight species by three roles")
	foes[0].item_selected.emit(1)
	check(scene.arena_config.custom[0] == ["dcss_rat","MELEE"],"the foe choice is recorded as a species and a role")
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
	check(scene.session == town and town.phase == "TOWN" and scene.find_child("SettlementHub",true,false) != null,"마을로 gives the town session back")
	scene.queue_free(); await process_frame
