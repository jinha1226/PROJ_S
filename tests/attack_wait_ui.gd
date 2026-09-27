extends SceneTree
const Scene = preload("res://expedition/ui/main.tscn")
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func run() -> void:
	var ui = Scene.instantiate(); root.add_child(ui); await process_frame
	ui.new_run(); await process_frame
	var s = ui.session
	s.MobileEffects.enable(s,Session.MobileEffects.PROFILE)
	Fixture.arena(s,8); s.party[0].level = 10
	for stone in ["FIRE_CALLER/cut","FIRE_CALLER/broken","FIRE_CALLER/pierced","SHIELD_STANCE/cut","WATER_WAVE/cut","GRAVEKEEPER/cut"]:
		if s.Essences.has(stone): s.Essences.bind(s.party[0],stone)
	ui.refresh(); await process_frame
	check(ui.find_child("SpellBar",true,false) == null,"automatic profile removes selectable spell bar")
	check(ui.find_child("AutoEffectBar",true,false) != null,"automatic profile shows trigger icon bar")
	check(not str(ui.find_child("HeroHP",true,false).text).contains("MP"),"automatic profile HP line omits MP")
	check(ui.find_child("BottomActions",true,false).get_child_count() == 5,"mobile controls keep exactly five actions")
	for dimensions in [Vector2i(320,568),Vector2i(390,844),Vector2i(430,932)]:
		root.size = dimensions; ui.size = Vector2(dimensions)
		ui.refresh(); await process_frame; await process_frame
		var nav: Control = ui.find_child("BottomActions",true,false)
		check(nav.get_global_rect().end.x <= ui.size.x+1,"bottom controls fit width "+str(dimensions))
		check(nav.get_global_rect().end.y <= ui.size.y+1,"bottom controls fit height "+str(dimensions))
		ui.show_character(0,"영혼석"); await process_frame
		var summary: Label = ui.find_child("EssenceSummaryPassives",true,false)
		check(summary != null and str(summary.text).contains("대기"),"summary reads real automatic effects")
		ui.details_popup.hide()
	ui.session.party.append(ui.session.make_actor(1,"브란",false)); ui.session.party.append(ui.session.make_actor(2,"세라",false))
	ui.session.companions = true; ui.refresh(); await process_frame
	var portrait: Control = ui.find_child("PortraitRow",true,false)
	check(portrait.get_global_rect().end.x <= ui.size.x+1,"three-person portrait row fits mobile width")
	ui.arena_config.profile = Session.MobileEffects.PROFILE; ui.show_arena_setup(); await process_frame
	check(ui.find_child("CombatProfile",true,false) != null and ui.find_child("AutoStone_0_5",true,false) != null,"arena exposes profile and all six slots")
	ui.queue_free(); await process_frame
	print("Attack/wait UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
