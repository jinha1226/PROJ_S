extends SceneTree
## The codex screen (codex spec §3): three tabs, unknown monsters as
## silhouettes, locked parts with their form hint, a build family filter, and
## opening it mid-run lets no time pass.
const Session = preload("res://expedition/run/session.gd")
const Codex = preload("res://expedition/progression/codex.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func node(scene, name: String) -> Node:
	return scene.modal_content.find_child(name,true,false)

func run() -> void:
	Codex.path = "user://test_codex_ui.json"
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	s.codex = Codex.empty()
	s.codex.monsters["dcss_rat"] = {"seen":true,"kills":2,"variants":[]}
	s.codex.stones["RAT_GNAW/cut"] = {"found":1,"absorbed":true,"variants":[]}
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(4): await process_frame
	var before: int = int(s.time)
	scene.show_codex()
	for _i in range(3): await process_frame
	check(scene.details_popup.visible and node(scene,"CodexScreen") != null,"the codex opens")
	check(node(scene,"CodexCompletion") != null,"completion is shown")
	check(node(scene,"CodexSpecies_dcss_rat") != null and node(scene,"CodexSpecies_cave_spider") != null,"seen and unseen monsters are listed")
	check(node(scene,"CodexSpecies_cave_spider").get_meta("known",true) == false,"an unseen monster is a silhouette")
	scene.show_codex("monsters","dcss_rat")
	for _i in range(3): await process_frame
	check(node(scene,"CodexMonsterDetail") != null and str(node(scene,"CodexMonsterDetail").get_meta("key","")) == "dcss_rat","focus opens the rat")
	scene.show_codex("stones")
	for _i in range(3): await process_frame
	check(node(scene,"CodexEntry_RAT_GNAW_cut") != null and node(scene,"CodexEntry_RAT_GNAW_broken") != null,"found and locked parts are listed")
	check(node(scene,"CodexGroup_MELEE") != null,"a build family filter exists")
	(node(scene,"CodexGroup_SUPPORT") as Button).pressed.emit()
	for _i in range(3): await process_frame
	check(node(scene,"CodexEntry_RAT_GNAW_cut") != null,"the support filter keeps the rat's tail")
	check(node(scene,"CodexFilter_BOOST") != null and node(scene,"CodexFilter_HEAL") != null,"group reveals its subtype filters")
	(node(scene,"CodexFilter_BOOST") as Button).pressed.emit()
	for _i in range(3): await process_frame
	check(node(scene,"CodexEntry_RAT_GNAW_cut") != null and node(scene,"CodexEntry_RAT_GNAW_broken") == null,"subtype filter narrows individual parts")
	check(node(scene,"CodexTab_items") == null or FileAccess.file_exists("res://data/content/unrands.json"),"the gear tab hides until unrands exist")
	check(int(s.time) == before,"no time passes in the codex")
	check(node(scene,"CodexTab_items") != null,"implemented artifacts enable the gear tab")
	scene.show_codex("unrands")
	for _i in range(3): await process_frame
	check(node(scene,"CodexEntry_AXE") != null,"artifact rows populate the gear tab")
	# Test a running timer rather than only disabling processing in the test.
	s.manual_mode = false; s.auto.running = true
	scene.set_process(true); scene._process(2.0)
	check(int(s.time) == before,"visible codex pauses the running auto battle")
	scene.set_process(false); s.manual_mode = true
	for screen in [Vector2i(320,568),Vector2i(360,640),Vector2i(390,844)]:
		root.size = screen
		for tab in ["stones","items","builds"]:
			scene.show_codex(tab)
			for _i in range(6): await process_frame
			check(scene.details_popup.size.x <= screen.x and scene.details_popup.size.y <= screen.y,"%s codex fits %s" % [tab,screen])
		check(node(scene,"CodexScroll").horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"codex has no horizontal scrolling")
	scene.details_popup.hide()
	root.size = Vector2i(320,568)
	# Three full report rows exercise the maximum contribution summary on a small phone.
	for i in range(1,3): s.party.append(s.make_actor(i,"동료%d" % i,false))
	s.reset_battle_stats()
	for actor in s.party:
		for id in ["GHOUL_CLAW","THORN_ARMOUR","GHOUL_JAW","WATER_WAVE","TOAD_SPIT","LIZARD_TAIL"]:
			s.EffectReport.note(s,int(actor.id),id,"procs",12)
			s.EffectReport.note(s,int(actor.id),id,"damage",70)
	scene.show_battle_report()
	for _i in range(6): await process_frame
	check(node(scene,"ReportEffects_0") != null,"battle report shows effect contributions")
	check(node(scene,"ReportScroll") != null and scene.details_popup.size.x <= 320 and scene.details_popup.size.y <= 568,"full three-member report fits a short phone")
	scene.details_popup.hide()
	scene.show_codex(); scene.details_popup.hide()
	for _i in range(6): await process_frame
	check(not scene.details_popup.visible,"closing immediately is not undone by deferred popup fitting")
	scene.show_codex("builds")
	for _i in range(4): await process_frame
	check(node(scene,"CodexBuild_wall") != null and node(scene,"CodexParty_classic") != null,"build and party examples are listed")
	(node(scene,"CodexBuild_wall") as Button).pressed.emit()
	for _i in range(4): await process_frame
	check(node(scene,"CodexBuildDetail") != null and scene.modal_content.find_children("CodexBuildStone_*","Control",true,false).size() == 6,"build detail has all six stones")
	s.records_codex = true; Codex.note_affix(s,"GEAR_AMP_1")
	(node(scene,"CodexTryBuild") as Button).pressed.emit()
	for _i in range(4): await process_frame
	check(scene.mode_arena_setup and scene.arena_config.size == 1 and scene.arena_config.members[0].build == "wall","codex routes wall to arena setup")
	check(scene.find_child("ArenaBuild_0",true,false) != null and scene.find_child("ArenaPart_0_0",true,false) == null,"selected build replaces two part pickers")
	scene.start_arena()
	for _i in range(4): await process_frame
	check(scene.session.party[0].equipped_abilities.size() == 6 and scene.session.party[0].gear.offhand.type == "shield","starting equips the actual wall loadout")
	check(not scene.session.records_codex,"arena examples never record collection")
	scene._notification(scene.NOTIFICATION_APPLICATION_PAUSED)
	check(int(Codex.read().affixes.get("GEAR_AMP_1",{}).get("found",0)) > 0 and not s.codex_dirty,"pausing in an arena flushes the parked run's codex")
	scene.show_codex("builds","classic")
	for _i in range(4): await process_frame
	check(node(scene,"CodexTryParty") != null,"party detail offers an arena trial")
	(node(scene,"CodexTryParty") as Button).pressed.emit()
	for _i in range(4): await process_frame
	check(scene.arena_config.size == 3 and scene.arena_config.members.map(func(m): return m.build) == ["wall","blood_hunter","elementalist"],"party trial selects all three builds")
	scene.start_arena()
	for _i in range(4): await process_frame
	check(scene.session.party.size() == 3 and scene.session.party.all(func(a): return a.equipped_abilities.size() == 6),"all three members wear full example builds")
	scene.leave_arena()
	check(scene.session == s and int(s.time) == before,"trying builds restores the original run without advancing time")
	scene.queue_free(); await process_frame
	if FileAccess.file_exists(Codex.path): DirAccess.remove_absolute(ProjectSettings.globalize_path(Codex.path))
	print("Codex UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
