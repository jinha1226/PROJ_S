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
	check(node(scene,"CodexEntry_dcss_rat") != null and node(scene,"CodexEntry_cave_spider") != null,"seen and unseen monsters are listed")
	check(node(scene,"CodexEntry_cave_spider").get_meta("known",true) == false,"an unseen monster is a silhouette")
	scene.show_codex("monsters","dcss_rat")
	for _i in range(3): await process_frame
	check(node(scene,"CodexDetail") != null and str(node(scene,"CodexDetail").get_meta("key","")) == "dcss_rat","focus opens the rat")
	scene.show_codex("stones")
	for _i in range(3): await process_frame
	check(node(scene,"CodexEntry_RAT_GNAW_cut") != null and node(scene,"CodexEntry_RAT_GNAW_broken") != null,"found and locked parts are listed")
	check(node(scene,"CodexFilter_1") != null,"a build family filter exists")
	(node(scene,"CodexFilter_12") as Button).pressed.emit()
	for _i in range(3): await process_frame
	check(node(scene,"CodexEntry_RAT_GNAW_cut") != null,"the support filter keeps the rat's tail")
	check(node(scene,"CodexTab_unrands") == null or FileAccess.file_exists("res://data/content/unrands.json"),"the gear tab hides until unrands exist")
	check(int(s.time) == before,"no time passes in the codex")
	check(node(scene,"CodexTab_unrands") != null,"implemented artifacts enable the gear tab")
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
		for tab in ["monsters","stones","unrands"]:
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
	print("Codex UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
