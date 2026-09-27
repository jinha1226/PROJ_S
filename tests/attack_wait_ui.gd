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
	ui.set_process(false)
	var spawn: Vector2 = Session.Free.position(s.party[0])
	var spawn_time: int = s.time
	ui.free_navigation_process(0.5)
	check(ui.auto_explore_paused and Session.Free.position(s.party[0]).is_equal_approx(spawn) and s.time == spawn_time,"new run waits for input without automatic motion or time consumption")
	check(s.free_movement,"normal run uses real continuous coordinates")
	check(s.combat_profile == Session.MobileEffects.PROFILE,"normal new run enables attack/wait without an arena toggle")
	check(s.roster.all(func(n): return s.MobileEffects.active(n)),"dungeon NPCs inherit normal run profile")
	Fixture.arena(s,8); s.party[0].level = 10
	s.npcs.clear(); s.phase = "EXPLORE"; s.floor_state.observe(s)
	ui.refresh(); await process_frame
	var start: Vector2 = Session.Free.position(s.party[0])
	var before_time: int = s.time
	var controls_id: int = ui.find_child("BottomActions",true,false).get_instance_id()
	var hp_label: Label = ui.find_child("HeroHP",true,false)
	var touch := InputEventScreenTouch.new(); touch.index = 3; touch.position = Vector2(110,260); touch.pressed = true
	ui.board._gui_input(touch)
	check(ui.board.joystick_active and ui.board.joystick_origin == touch.position,"touch anchors a floating joystick exactly under the finger")
	var drag := InputEventScreenDrag.new(); drag.index = 3; drag.position = touch.position+Vector2(34,17)
	ui.board._gui_input(drag)
	ui.free_navigation_process(ui.JOYSTICK_STEP_SECONDS+0.01)
	var target: Vector2 = start+Vector2(34,17).normalized()
	check(Session.Free.position(s.party[0]).is_equal_approx(target) and s.time > before_time,"joystick commits arbitrary-angle movement through the turn scheduler")
	check(ui.board.world_walks.has(int(s.party[0].id)),"camera and sprite interpolate from actual world positions")
	check(ui.find_child("BottomActions",true,false).get_instance_id() == controls_id and ui.find_child("HeroHP",true,false) == hp_label,"movement retains HUD controls and their layout")
	check(ui.navigation_clock > 0,"movement scheduling preserves the frame remainder")
	ui.board._process(ui.JOYSTICK_STEP_SECONDS*0.6)
	check(not ui.board.movement_vfx.dust.is_empty() and ui.board.movement_vfx.body_offset(int(s.party[0].id),ui.board.half_width).y < 0,"walking leaves ground dust and lifts only the body")
	var visual_before: Vector2 = ui.board.display_world_position(s.party[0])
	var camera_before: Vector2 = ui.board.camera_origin()
	var turn_before: int = s.turn_serial
	s.party[0].hp -= 1; s.message("이동 기록")
	ui.navigation_clock = ui.JOYSTICK_STEP_SECONDS-0.02
	ui.free_navigation_process(0.025)
	check(s.turn_serial == turn_before+1,"held joystick schedules the next turn without waiting for the previous visual to disappear")
	check(ui.board.display_world_position(s.party[0]).is_equal_approx(visual_before) and ui.board.camera_origin().is_equal_approx(camera_before),"overlapping movement starts from the displayed position without a sprite or camera jump")
	check(ui.find_child("HeroHP",true,false) == hp_label and hp_label.text == "HP %d/%d" % [s.party[0].hp,s.party[0].max_hp] and ui.find_child("RecentLog",true,false).text.contains("이동 기록") and ui.find_child("TurnCount",true,false).text == "%d턴" % s.turn_serial,"retained HUD refreshes health, log and turn values")
	turn_before = s.turn_serial
	ui.free_navigation_process(10)
	check(s.turn_serial == turn_before+1,"one stalled frame never replays a backlog of movement turns")
	touch.pressed = false; touch.position = drag.position; ui.board._input(touch)
	before_time = s.time
	ui.board.world_walks.clear(); ui.free_navigation_process(0.5)
	check(not ui.board.joystick_active and s.time == before_time,"release stops manual movement and further turn consumption")
	ui.board._process(0.5)
	check(ui.board.movement_vfx.dust.is_empty() and ui.board.movement_vfx.body_offset(int(s.party[0].id),ui.board.half_width) == Vector2.ZERO and s.time == before_time,"walking feedback fades and settles without advancing world time")
	touch.pressed = true; touch.position = Vector2(120,270); ui.board._gui_input(touch)
	drag.position = touch.position+Vector2(5,3); ui.board._gui_input(drag)
	ui.free_navigation_process(0.5)
	check(s.time == before_time,"joystick deadzone does not spend a turn")
	var other := InputEventScreenTouch.new(); other.index = 4; other.position = Vector2(200,310); other.pressed = true
	ui.board._gui_input(other)
	check(ui.board.joystick_pointer == 3 and ui.board.joystick_origin == touch.position,"second touch cannot steal the movement stick")
	touch.pressed = false; touch.canceled = true; ui.board._gui_input(touch)
	check(not ui.board.joystick_active and s.time == before_time,"canceled touch clears the stick without tapping a target")
	ui.on_world(Session.Free.position(s.party[0])+Vector2(2,0))
	check(s.time == before_time,"ground tap does not start destination movement")
	ui.board.suppress_mouse_until = 0
	var mouse := InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.position = Vector2(90,240); mouse.pressed = true
	ui.board._gui_input(mouse)
	check(ui.board.joystick_active and ui.board.joystick_pointer == -1,"desktop mouse also anchors a floating joystick")
	var motion := InputEventMouseMotion.new(); motion.position = mouse.position+Vector2(26,-14); ui.board._input(motion)
	check(ui.board.joystick_direction().is_equal_approx(Vector2(26,-14).normalized()),"mouse drag uses the same arbitrary-angle control")
	mouse.pressed = false; mouse.position = motion.position; ui.board._gui_input(mouse)
	check(not ui.board.joystick_active,"mouse release clears the joystick")
	# An encounter consumes the current gesture, then returns control explicitly.
	var encounter_start: Vector2 = Session.Free.center(Vector2i(s.BOARD_SIDE/2,s.BOARD_SIDE/2))
	s.Free.place(s.party[0],encounter_start)
	var enemy: Dictionary = s.make_actor(101,"조우",true)
	s.Floor.MonsterAI.configure(enemy,"MELEE"); enemy.hp = 100; enemy.max_hp = 100; enemy.ready_at = s.time+10000
	s.Free.place(enemy,encounter_start+Vector2(7,0)); s.enemies.append(enemy); s.floor_state.observe(s)
	check(s.party_enemies().is_empty(),"encounter fixture begins outside sight")
	touch.canceled = false
	touch.pressed = true; touch.position = Vector2(120,270); ui.board._gui_input(touch)
	drag.position = touch.position+Vector2(34,0); ui.board._gui_input(drag)
	ui.free_navigation_process(ui.JOYSTICK_STEP_SECONDS+0.01)
	check(not ui.board.joystick_active and ui.auto_explore_paused and not s.party_enemies().is_empty(),"first enemy sight brakes exploration and the held joystick")
	before_time = s.time; ui.board._gui_input(drag); ui.free_navigation_process(0.5)
	check(s.time == before_time and not ui.board.joystick_active,"continuing the old drag cannot rush into the enemy")
	touch.pressed = false; ui.board._gui_input(touch)
	touch.pressed = true; ui.board._gui_input(touch)
	check(ui.board.joystick_active,"fresh press restores deliberate movement during combat")
	ui.stop_navigation(); enemy.hp = 0; s.floor_state.observe(s)
	await process_frame
	for stone in ["FIRE_CALLER/cut","FIRE_CALLER/broken","FIRE_CALLER/pierced","SHIELD_STANCE/cut","WATER_WAVE/cut","GRAVEKEEPER/cut"]:
		if s.Essences.has(stone): s.Essences.bind(s.party[0],stone)
	ui.refresh(); await process_frame
	check(ui.find_child("SpellBar",true,false) == null,"automatic profile removes selectable spell bar")
	check(ui.find_child("AutoEffectBar",true,false) != null,"automatic profile shows trigger icon bar")
	check(not str(ui.find_child("HeroHP",true,false).text).contains("MP"),"automatic profile HP line omits MP")
	check(ui.find_child("BottomActions",true,false).get_child_count() == 3,"normal free movement exposes attack/wait/retreat")
	ui.show_tactics(); await process_frame
	check(ui.find_child("TacticSkills",true,false) == null,"normal tactics has no manual skill button")
	ui.details_popup.hide()
	ui.show_character(0,"능력치"); await process_frame
	check(ui.find_child("Stat_mp",true,false) == null and ui.find_child("Stat_spell",true,false) == null,"normal character sheet omits unused MP and spell stats")
	ui.details_popup.hide()
	for dimensions in [Vector2i(320,568),Vector2i(390,844),Vector2i(430,932)]:
		root.size = dimensions; ui.size = Vector2(dimensions)
		ui.refresh(); await process_frame; await process_frame
		check(ui.board.get_global_rect().size.is_equal_approx(ui.size),"map fills portrait viewport "+str(dimensions))
		var world: Vector2 = Session.Free.position(s.party[0])+Vector2(0.217,0.391)
		check(ui.board.world_at(ui.board.project(world)).is_equal_approx(world),"touch projection preserves fractional coordinates")
		var nav: Control = ui.find_child("BottomActions",true,false)
		check(nav.get_global_rect().end.x <= ui.size.x+1,"bottom controls fit width "+str(dimensions))
		check(nav.get_global_rect().end.y <= ui.size.y+1,"bottom controls fit height "+str(dimensions))
		ui.show_character(0,"영혼석"); await process_frame
		var summary: Label = ui.find_child("EssenceSummaryPassives",true,false)
		check(summary != null and str(summary.text).contains("대기"),"summary reads real automatic effects")
		var rewards: Label = ui.find_child("EssenceSummaryStats",true,false)
		check(rewards != null and not rewards.text.contains("MP") and not rewards.text.contains("주문력") and rewards.text.contains("공격력"),"summary shows usable automatic rewards")
		ui.details_popup.hide()
	s.grant_part("FIRE_CALLER/pierced"); ui.show_supplies(); ui.show_item_detail("FIRE_CALLER/pierced"); await process_frame
	var preview: Array = ui.item_detail.find_children("*","Label",true,false).map(func(l): return l.text)
	check(preview.any(func(t): return t.contains("공격력 +2") and t.contains("최대 HP +12") and not t.contains("MP") and not t.contains("주문력")),"inventory preview uses the same automatic reward as absorption")
	ui.item_popup.hide(); ui.details_popup.hide()
	ui.session.party.append(ui.session.make_actor(1,"브란",false)); ui.session.party.append(ui.session.make_actor(2,"세라",false))
	ui.session.companions = true; ui.refresh(); await process_frame
	var portrait: Control = ui.find_child("PortraitRow",true,false)
	check(portrait.get_global_rect().end.x <= ui.size.x+1,"three-person portrait row fits mobile width")
	ui.arena_config.profile = Session.MobileEffects.PROFILE; ui.show_arena_setup(); await process_frame
	check(ui.find_child("CombatProfile",true,false) != null and ui.find_child("AutoStone_0_5",true,false) != null,"arena exposes profile and all six slots")
	ui.queue_free(); await process_frame
	print("Attack/wait UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
