extends "res://tests/first_floor_stages_acceptance.gd"
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
func tap(b:Control):
	var p:=b.get_global_rect().get_center()
	for down in [true,false]:
		var e:=InputEventScreenTouch.new();e.index=0;e.pressed=down;e.position=p
		root.push_input(e,true)
		await process_frame
	for i in range(3):await process_frame
func run():
	root.size=Vector2i(360,800);root.content_scale_size=Vector2i(360,800)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Sandbox.new();ui.size=Vector2(360,800);ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	check(ui.stage_context_bar.is_visible_in_tree(),"exploration footer shown")
	var hero:int=s.sim.world.party_control_actor_id()
	var before:int=s.sim.world.world_time
	await tap(ui.stage_context_bar.get_node("StagePortrait%d"%hero))
	check(ui.member_detail_modal.visible,"portrait touch opens existing status/skills/inventory window")
	check(s.sim.world.world_time==before,"inspection consumes no turn")
	ui._close_member_detail()
	check(walk(s,Vector2i(11,14)),"walk to combat")
	check(s.request_room_exit(hero,"F1_R4_R7",s.sim.world.party_encounter.nine_room_floor.revision).accepted,"enter combat")
	ui._request_refresh()
	for i in range(4):await process_frame
	check(ui.stage_context_bar.get_child_count()==4,"four combat controls")
	check(not ui.round_order_bar.visible and not ui.combat_action_area.visible,"old timeline and dock stay hidden")
	var journal:int=s.command_journal.size();before=s.sim.world.world_time
	await tap(ui.stage_context_bar.get_node("StageProceed"))
	check(s.command_journal.size()==journal+1,"touch confirms deployment exactly once")
	check(s.sim.world.world_time==before,"placement does not spend a round")
	check(s.round_status().phase=="PLANNING","enemy setup completes before our response")
	check(ui.stage_context_bar.get_node("StageProceed").text=="진행 ▶","proceed label changes after placement")
	journal=s.command_journal.size();before=s.sim.world.world_time
	await tap(ui.stage_context_bar.get_node("StageProceed"))
	check(s.command_journal.size()==journal+1 and s.sim.world.world_time==before+100,"one touch executes exactly one response")
	for b in ui.stage_context_bar.get_children():
		check(b.size.x>=44 and b.get_global_rect().end.x<=361 and b.get_global_rect().end.y<=801,"controls remain touch sized and on screen")
	check(ui.event_label.max_lines_visible==3 and ui.phase_label.visible,"three logs and floor/countdown HUD visible")
	check(s.sim.world.world_state_error().is_empty(),"UI actions leave valid world")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/stage-context-runtime.png")==OK,"capture")
	ui.queue_free();await process_frame
	print("STAGE_CONTEXT_UI ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
