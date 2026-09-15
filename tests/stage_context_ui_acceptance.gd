extends "res://tests/first_floor_stages_acceptance.gd"
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const RoundFixture=preload("res://tests/round_combat_fixture.gd")
var test_ui
var sequence_seen:=false
func tap(b:Control):
	var p:=b.get_global_rect().get_center()
	for down in [true,false]:
		var e:=InputEventScreenTouch.new();e.index=0;e.pressed=down;e.position=p
		root.push_input(e,true)
		await process_frame
	for i in range(3):await process_frame
	var grid=test_ui.grid
	if grid!=null and grid.stage_motion_busy():
		if "--capture" in OS.get_cmdline_user_args() and not grid._played_effect_ids.is_empty():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("/tmp/stage-impact-runtime.png")==OK,"impact capture")
		sequence_seen=true
		var finish:=0
		for motion in grid.actor_motion_state().values():
			if not motion.has("path"):continue
			check(int(motion.started_at_ms)>=finish,"enemy movements never overlap")
			finish=int(motion.started_at_ms)+int(motion.duration_ms)
			var sample=preload("res://playtest/stage_motion_sequence.gd").sample(motion,int(motion.started_at_ms)-1)
			check(sample.world_position==motion.path.front(),"waiting enemy stays at its starting tile")
			var end=preload("res://playtest/stage_motion_sequence.gd").sample(motion,finish)
			check(end.world_position==motion.path.back(),"path animation reaches final tile")
		var journal_size:int=test_ui.session.command_journal.size()
		test_ui._on_product_execute()
		check(test_ui.session.command_journal.size()==journal_size,"animation blocks duplicate progress")
		await create_timer(float(maxi(0,grid._stage_motion_until-Time.get_ticks_msec())+100)/1000.0).timeout
		for i in range(3):await process_frame
func run():
	root.size=Vector2i(360,800);root.content_scale_size=Vector2i(360,800)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Sandbox.new();ui.size=Vector2(360,800);ui.initialize_for_headless_test(s,true)
	test_ui=ui
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
	check(ui.stage_context_bar.get_node("StagePortrait%d"%hero)!=null,"deployment actor control")
	check(not ui.round_order_bar.visible and not ui.combat_action_area.visible,"placement keeps timeline hidden")
	check(Vector2i(10,17) in ui.grid.deployment_cells,"valid deployment cells highlighted")
	var original:Vector2i=s.sim.world.entities[hero].position
	var placement_screen:Vector2=ui.grid.global_position+ui.grid.world_to_pixel_center(Vector2i(10,17))
	for down in [true,false]:
		var e:=InputEventScreenTouch.new();e.index=0;e.pressed=down;e.position=placement_screen
		root.push_input(e,true);await process_frame
	for i in range(4):await process_frame
	check(s.sim.world.entities[hero].position==original,"placement preview does not advance authority")
	check(ui.grid._position_from_actor(ui.grid._actor_by_id(hero))==Vector2i(10,17),"placement preview visibly moves actor")
	check(s.sim.world.party_encounter.round_combat.plans[str(hero)].destination==[10,17],"placement edits selected actor plan")
	var journal:int=s.command_journal.size();before=s.sim.world.world_time
	await tap(ui.stage_context_bar.get_node("StageProceed"))
	check(s.command_journal.size()==journal+1,"touch confirms deployment exactly once")
	check(s.sim.world.world_time==before,"placement does not spend a round")
	check(s.round_status().phase=="PLANNING","placement enters individual planning")
	check(not sequence_seen,"deployment never pre-moves enemies")
	check(ui.round_order_bar.visible,"individual turn order shown")
	check(Vector2i(11,18) in ui.grid.movement_cells and Vector2i(10,18) not in ui.grid.movement_cells,"movement radius marks floor and excludes pillar")
	check(s.sim.world.entities[hero].position==Vector2i(10,17),"confirmation commits placement")
	var enemy:int=s.sim.world.party_encounter.enemy_ids.filter(func(id):return s.FieldRules.visible(s.sim.world,id))[0]
	RoundFixture.relocate(s.sim.world,enemy,Vector2i(11,17))
	var revision:int=s.round_status().plan_revision
	ui._on_actor(enemy)
	for i in range(4):await process_frame
	check(s.round_status().plan_revision==revision+1,"one enemy tap reserves attack")
	check(ui.grid.srpg_attack_target==s.sim.world.entities[enemy].position,"attack icon shown above reserved target")

	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/stage-selected-attack.png")==OK,"selected attack capture")
	ui._on_actor(enemy)
	for i in range(4):await process_frame
	check(s.round_status().plan_revision>=revision,"target click preserves valid revision")
	check(ui.stage_context_bar.get_node("StageProceed").text=="턴 종료","turn end label")
	check(s.stage_round_action(Action.hold(hero)).accepted,"clear attack before movement test")
	ui._on_cell(Vector2i(11,18))
	for i in range(4):await process_frame
	check(s.sim.world.entities[hero].position==Vector2i(10,17),"move selection preserves authority")
	check(not ui.grid._ghosts.is_empty(),"destination silhouette shown")
	check(not ui.grid.srpg_attack_cells.is_empty() and ui.grid.movement_cells.is_empty(),"destination changes movement range to attack range")
	journal=s.command_journal.size();before=s.sim.world.world_time
	await tap(ui.stage_context_bar.get_node("StageProceed"))
	check(s.command_journal.size()==journal+1 and s.sim.world.world_time==before+100,"turn end executes move and cycle once")
	for b in ui.stage_context_bar.get_children():
		check(b.size.x>=44 and b.get_global_rect().end.x<=361 and b.get_global_rect().end.y<=801,"controls remain touch sized and on screen")
	check(ui.event_label.max_lines_visible==3 and ui.phase_label.visible,"three logs and floor/countdown HUD visible")
	check(s.sim.world.world_state_error().is_empty(),"UI actions leave valid world")
	check(sequence_seen,"committed movement reaches sequence renderer")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/stage-context-runtime.png")==OK,"capture")
	ui.queue_free();await process_frame
	print("STAGE_CONTEXT_UI ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
