extends "res://tests/test_case.gd"

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

func test_same_grid_keeps_full_mapping_through_contact() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(450,800); sandbox.initialize_for_headless_test(Session.new())
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	var id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
	check_eq(sandbox.grid.visible_cell_count,15,"exploration shows full 15x15 world")
	check_eq(sandbox.grid.view_origin,Vector2i.ZERO,"full view starts at world origin")
	var hero=sandbox.session.sim.world.party_encounter.protagonist_id; sandbox.session.commit_exploration(Command.wait(hero)); sandbox._refresh()
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	check_eq(sandbox.grid.get_instance_id(),id,"same grid")
	check_eq(sandbox.grid.visible_cell_count,15,"contact keeps full 15x15 view")
	check_eq(sandbox.grid.mapping_signature(),mapping,"contact keeps exact full-view mapping")
	sandbox.free(); return finish()

func test_actor_hit_rect_is_at_least_28_and_outside_input_has_no_actor() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(Session.new())
	var hero=sandbox.session.sim.world.party_encounter.protagonist_id; var rect=sandbox.grid.actor_hit_rect(hero)
	check(rect.size.x>=44 and rect.size.y>=44,"actor hit target")
	check_eq(sandbox.grid.actor_at_pointer(Vector2(-100,-100)),-1,"outside no actor")
	sandbox.grid.modal_open=true; check(sandbox.grid.modal_open,"modal gate")
	sandbox.free(); return finish()

func test_gui_input_routes_actor_slop_without_stealing_adjacent_cell_centers() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(Session.new())
		sandbox.grid.size=sandbox.grid.custom_minimum_size
		var status:Dictionary=sandbox.session.party_status(); var hero:=int(status.protagonist_id)
		var hero_position:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
		var actor_events:Array=[];var world_events:Array=[]
		sandbox.grid.actor_pressed.connect(func(id):actor_events.append(id))
		sandbox.grid.world_cell_pressed.connect(func(position):world_events.append(position))
		var near_actor:=InputEventScreenTouch.new();near_actor.pressed=true
		near_actor.position=sandbox.grid.world_to_pixel_center(hero_position)+Vector2(15,0)
		sandbox.grid._gui_input(near_actor)
		check_eq(actor_events,[hero],"%s actor center +15 routes through 44px actor hit helper"%viewport_size)
		check(world_events.is_empty(),"%s actor slop is not misrouted as movement"%viewport_size)
		sandbox._clear_move_preview();actor_events.clear();world_events.clear()
		var adjacent:=hero_position+Vector2i.RIGHT
		var exact_empty:=InputEventScreenTouch.new();exact_empty.pressed=true
		exact_empty.position=sandbox.grid.world_to_pixel_center(adjacent)
		sandbox.grid._gui_input(exact_empty)
		check(actor_events.is_empty(),"%s adjacent empty center is not stolen by hero slop"%viewport_size)
		check_eq(world_events,[adjacent],"%s adjacent center routes exact world cell"%viewport_size)
		actor_events.clear();world_events.clear()
		var outside:=InputEventScreenTouch.new();outside.pressed=true
		outside.position=sandbox.grid.grid_rect().position+Vector2(-1,sandbox.grid.cell_size_px()*0.5)
		sandbox.grid._gui_input(outside)
		check(actor_events.is_empty() and world_events.is_empty(),"%s outside grid emits no route"%viewport_size)
		sandbox.free()
	return finish()

func test_hold_draw_spec_drives_dashed_secondary_and_solid_override_primitives() -> bool:
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(Session.new())
	var origin:=[7,7]
	var suggested_hold:={"source":"SUGGESTED","source_color":"#75c8ff","type":"HOLD",
		"from_position":origin,"line_style":"DASHED_THIN","marker_style":"CIRCLE"}
	var override_hold:={"actor_id":1,"source":"OVERRIDE","source_color":"#ff9f68","type":"HOLD",
		"from_position":origin,"line_style":"SOLID_THICK","marker_style":"SQUARE",
		"automatic_suggestion":suggested_hold}
	sandbox.grid.set_intent_overlays([override_hold])
	check_eq(sandbox.grid._intent_overlays.size(),1,"primary HOLD overlay stored")
	check_eq(sandbox.grid._secondary_intent_overlays.size(),1,"secondary HOLD overlay stored")
	var secondary_spec:Dictionary=sandbox.grid.intent_draw_spec(sandbox.grid._secondary_intent_overlays[0])
	var primary_spec:Dictionary=sandbox.grid.intent_draw_spec(sandbox.grid._intent_overlays[0])
	check_eq(secondary_spec.primitive,"RING","secondary HOLD projects ring primitive")
	check(secondary_spec.dashed and secondary_spec.dash_segments==8,"secondary HOLD projects deterministic dashed segments")
	check_eq(secondary_spec.line_width,2.0,"secondary HOLD is thin")
	check_eq(secondary_spec.marker_style,"CIRCLE","secondary HOLD uses circle marker")
	check_eq(primary_spec.primitive,"RING","override HOLD projects ring primitive")
	check(not primary_spec.dashed and primary_spec.dash_segments==0,"override HOLD projects solid ring")
	check_eq(primary_spec.line_width,4.5,"override HOLD is thick")
	check_eq(primary_spec.marker_style,"SQUARE","override HOLD uses square marker")
	secondary_spec.marker_style="CORRUPTED"
	check_eq(sandbox.grid.intent_draw_spec(sandbox.grid._secondary_intent_overlays[0]).marker_style,"CIRCLE","draw spec is detached")
	sandbox.free();return finish()

func test_visual_effect_rows_render_once_per_effect_and_share_event_without_loss() -> bool:
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(Session.new())
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	var rows:Array=[
		{"effect_id":"42:hit_flash","event_id":42,"order":0,"kind":"HIT_FLASH","world_position":[7,7],"damage_type":"fire","text":""},
		{"effect_id":"42:floating_amount","event_id":42,"order":1,"kind":"FLOATING_AMOUNT","world_position":[7,7],"damage_type":"fire","text":"-22"},
		{"effect_id":"43:death","event_id":43,"order":2,"kind":"DEATH","world_position":[7,7],"damage_type":"physical","text":""}]
	check_eq(sandbox.grid.play_effects(rows),3,"all distinct effects render even when two share one event")
	check(sandbox.grid.has_played_effect_event(42),"source event is remembered for replay diagnostics")
	check(sandbox.grid.has_played_effect("42:hit_flash") and sandbox.grid.has_played_effect("42:floating_amount"),"effect ids are deduplicated independently")
	check_eq(sandbox.grid.play_effects(rows),0,"replayed result cannot duplicate visual effects")
	check_eq(sandbox.grid._active_visual_effects.size(),3,"replay leaves one copy of each visual effect")
	var flash:Dictionary=sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[0])
	var amount:Dictionary=sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[1])
	check_eq(flash.primitive,"FLASH_RING","hit flash draw spec is testable")
	check_eq(flash.color_hex,"#ff7a55","damage type drives deterministic effect color")
	check_eq(amount.primitive,"TEXT","floating amount draw spec is text")
	check_eq(amount.text,"-22","floating amount preserves session-projected text")
	flash.primitive="CORRUPTED"
	check_eq(sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[0]).primitive,"FLASH_RING","effect draw spec is detached")
	sandbox.free();return finish()

func test_exploration_grid_first_tap_is_pure_second_tap_moves_and_clears_on_contact() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(Session.new()); sandbox.grid.size=sandbox.grid.custom_minimum_size
	for button_name in ["ExploreN","ExploreNE","ExploreE","ExploreSE","ExploreS","ExploreSW","ExploreW","ExploreNW","ExploreHold"]:
		check(_button(sandbox,button_name)==null,"legacy D-pad absent: %s"%button_name)
	var status:Dictionary=sandbox.session.party_status(); var origin:=Vector2i(int(status.anchor[0]),int(status.anchor[1])); var destination:=origin+Vector2i.RIGHT
	var hero:=int(status.protagonist_id);var companion:=int(status.party_member_ids[1])
	_press(sandbox,"MemberCard%d"%companion)
	check_eq(sandbox.selected_member_id,companion,"companion portrait remains available for details in exploration")
	var before:Dictionary=sandbox.session.sim.snapshot(); sandbox._on_cell(destination); sandbox._refresh()
	check_eq(sandbox.session.sim.snapshot(),before,"first exploration tap is pure")
	check(sandbox.pending_move_valid and sandbox.pending_move_mode=="EXPLORATION","first tap stores strong preview")
	check_eq(sandbox.grid.cursor_cell,destination,"preview highlights exact destination")
	var move_summary:=str((sandbox.find_child("MovePreviewSummary",true,false) as Label).text)
	check("한 번 더" in move_summary,"second-tap guidance visible")
	check_eq(sandbox.pending_move_actor_id,hero,"exploration grid preview always belongs to representative hero")
	check("대표 이동: 주인공" in move_summary and not "나래 이동 예정" in move_summary,"summary actor matches hero execution despite companion detail selection")
	sandbox._on_cell(destination); sandbox._refresh()
	check_eq(sandbox.session.party_status().safe_phase,"CONTACT","exact second tap commits one move and contact")
	check_eq(sandbox.session.sim.world.step_index,int(before.step_index)+1,"exactly one exploration step")
	check_eq(sandbox.session.sim.world.world_time,int(before.world_time)+100,"exactly one movement cost")
	check_eq(sandbox.session.command_journal[-1].command.actor_id,str(hero),"committed exploration command belongs exactly to hero")
	check_eq(sandbox.session.party_status().anchor,[destination.x,destination.y],"group anchor follows representative move")
	for row in sandbox.session.party_cards():
		if int(row.entity_id)!=hero:check_eq(row.logical_position,[destination.x,destination.y],"grouped companion logical anchor stays synchronized")
	check(sandbox.pending_move_mode.is_empty() and sandbox.grid.cursor_cell==Vector2i(-1,-1),"contact clears stale exploration preview")
	var invalid=Sandbox.new(); invalid.size=Vector2(360,640); invalid.initialize_for_headless_test(Session.new())
	check(invalid.session.sim.world.bootstrap_set_terrain(origin+Vector2i.LEFT,"wall"),"wall preview fixture")
	var wall_before=invalid.session.sim.snapshot(); invalid._on_cell(origin+Vector2i.LEFT); invalid._refresh()
	check_eq(invalid.session.sim.snapshot(),wall_before,"wall preview is no-op")
	check("지형" in invalid.notice_text,"wall rejection is immediate Korean")
	var invalid_before=invalid.session.sim.snapshot()
	invalid._on_cell(origin+Vector2i(3,0)); invalid._refresh()
	check_eq(invalid.session.sim.snapshot(),invalid_before,"nonadjacent preview is no-op")
	check("장거리 이동은 아직 지원하지 않습니다" in invalid.notice_text,"nonadjacent reason is honest Korean")
	var wait=Sandbox.new(); wait.size=Vector2(360,640); wait.initialize_for_headless_test(Session.new()); var wait_before=wait.session.sim.snapshot()
	wait._on_actor(int(wait.session.party_status().protagonist_id)); wait._refresh()
	check_eq(wait.session.sim.snapshot(),wait_before,"hero-cell first tap previews wait without mutation")
	check(wait.pending_exploration_wait and "대기" in wait.notice_text,"occupied hero cell is consumed as clear wait preview")
	wait.free(); invalid.free(); sandbox.free(); return finish()

func test_each_formation_uses_visible_button_preview_ghosts_and_confirm_to_engaged() -> bool:
	for preset in ["WEDGE","LINE","COLUMN"]:
		var sandbox=Sandbox.new(); sandbox.size=Vector2(450,800); sandbox.initialize_for_headless_test(Session.new())
		sandbox.grid.size=sandbox.grid.custom_minimum_size
		var grid_id=sandbox.grid.get_instance_id(); var full_mapping=sandbox.grid.mapping_signature()
		var actor_count:=0; for cell in sandbox.session.observe_party_world().cells: actor_count += cell.actors.size()
		check_eq(actor_count,1,"%s enemies hidden before contact"%preset)
		_explore_wait(sandbox)
		check_eq(sandbox.session.party_status().safe_phase,"CONTACT","%s contact"%preset)
		actor_count=0; for cell in sandbox.session.observe_party_world().cells: actor_count += cell.actors.size()
		check_eq(actor_count,2,"%s enemy revealed at contact"%preset)
		var initial_confirm:Button=_button(sandbox,"DeployConfirm"); check(initial_confirm.disabled,"confirm disabled before preset")
		sandbox._on_deploy_confirm(); sandbox._refresh(); check("먼저" in str(sandbox.find_child("ActionStatus",true,false).text),"visible confirm rejection")
		_press(sandbox,"Preset%s"%preset)
		check_eq(sandbox.session.deployment_draft().preset_id,preset,"preset selection stored")
		check_eq(sandbox.grid._ghosts.size(),2,"companion ghost tokens")
		check_eq(sandbox.grid.visible_cell_count,15,"%s preview remains full 15x15"%preset)
		for ghost in sandbox.grid._ghosts:
			var ghost_position:=Vector2i(int(ghost.position[0]),int(ghost.position[1]))
			check(sandbox.grid.is_world_cell_visible(ghost_position),"%s deployment ghost is inside full preview"%preset)
		check(_button(sandbox,"Preset%s"%preset).button_pressed,"selected preset feedback")
		check(not _button(sandbox,"DeployConfirm").disabled,"valid confirm enabled")
		_press(sandbox,"DeployConfirm")
		sandbox.grid.size=sandbox.grid.custom_minimum_size
		check_eq(sandbox.session.party_status().safe_phase,"ENGAGED","%s button journey engaged"%preset)
		check("빈 칸은 이동, 적은 공격" in str(sandbox.find_child("ActionStatus",true,false).text), "%s combat instruction visible immediately"%preset)
		check_eq(sandbox.session.party_status().formation_id,preset,"formation committed")
		check_eq(sandbox.grid.get_instance_id(),grid_id,"same grid for %s"%preset)
		check_eq(sandbox.grid.visible_cell_count,9,"%s combat zoom is 9x9"%preset)
		check(sandbox.grid.mapping_signature()!=full_mapping,"%s combat mapping intentionally uses crop"%preset)
		for cell in sandbox.session.observe_party_world().cells:
			if cell.actors.is_empty():continue
			var actor_position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
			check(sandbox.grid.is_world_cell_visible(actor_position),"%s combat cluster remains visible"%preset)
		check("⚔ 전투 중" in sandbox.phase_label.text,"%s persistent combat banner"%preset)
		check(sandbox.combat_action_area.visible,"%s fixed action area shown"%preset)
		check_eq(sandbox.combat_action_area.get_parent(),sandbox.root_layout,"%s action area is PartyLayout sibling"%preset)
		check_eq(sandbox.root_layout.get_child(sandbox.root_layout.get_child_count()-1),sandbox.combat_action_area,"%s action area is final PartyLayout sibling"%preset)
		check_eq(sandbox.combat_action_dock.get_parent(),sandbox.combat_action_area,"%s dock is inside fixed action area"%preset)
		check_eq(sandbox.action_feedback_label.get_parent(),sandbox.combat_action_area,"%s feedback is inside fixed action area"%preset)
		check(not _inside_ancestor(sandbox.combat_action_area,ScrollContainer),"%s action area is independent from information scroll"%preset)
		check(sandbox.action_feedback_label.get_theme_font_size("font_size")>=16,"%s fixed feedback font"%preset)
		check_eq(_button(sandbox,"ActorHold").text,"선택 대기","%s dock hold label"%preset)
		check_eq(_button(sandbox,"OverrideClear").text,"자동 제안 복원","%s dock restore label"%preset)
		check_eq(_button(sandbox,"TurnConfirm").text,"턴 확정","%s dock confirm label"%preset)
		sandbox.free()
	return finish()

func test_combat_crop_roundtrip_recenter_and_offwindow_touch_are_authoritative() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=_engaged_sandbox("WEDGE",viewport_size)
		var grid=sandbox.grid; grid.size=grid.custom_minimum_size
		check_eq(grid.visible_cell_count,9,"%s engaged view is 9x9"%viewport_size)
		var bounds:Rect2i=grid.view_bounds()
		for world_position in [bounds.position,bounds.position+bounds.size-Vector2i.ONE]:
			var pixel:Vector2=grid.world_to_pixel_center(world_position)
			check_eq(grid.pixel_to_world_cell(pixel),world_position,"%s crop edge roundtrip %s"%[viewport_size,world_position])
		var offwindow:=Vector2i.ZERO if not grid.is_world_cell_visible(Vector2i.ZERO) else Vector2i(14,14)
		check(not grid.is_world_cell_visible(offwindow),"%s fixture has an off-window cell"%viewport_size)
		check_eq(grid.world_to_pixel_center(offwindow),Vector2(-1,-1),"%s off-window cell has no pixel projection"%viewport_size)
		check_eq(grid.world_cell_rect(offwindow),Rect2(),"%s off-window cell has no hit rectangle"%viewport_size)
		grid.set_observation({"width":15,"height":15,"cells":[]})
		grid.set_view_window(9,[Vector2i(7,7)])
		var routed:Array=[]; grid.world_cell_pressed.connect(func(position):routed.append(position))
		bounds=grid.view_bounds()
		for world_position in [bounds.position,bounds.position+bounds.size-Vector2i.ONE]:
			var touch:=InputEventScreenTouch.new();touch.pressed=true;touch.position=grid.world_to_pixel_center(world_position)
			grid._gui_input(touch)
		check_eq(routed,[bounds.position,bounds.position+bounds.size-Vector2i.ONE],"%s real edge touches emit cropped world cells"%viewport_size)
		var off_touch:=InputEventScreenTouch.new();off_touch.pressed=true;off_touch.position=grid.world_to_pixel_center(offwindow)
		grid._gui_input(off_touch)
		check_eq(routed.size(),2,"%s off-window projection cannot emit input"%viewport_size)
		grid.set_view_window(9,[Vector2i(7,7)],[Vector2i(14,14)])
		check(grid.is_world_cell_visible(Vector2i(14,14)),"%s priority target recenters into view"%viewport_size)
		check_eq(grid.view_origin,Vector2i(6,6),"%s target recenter clamps deterministically"%viewport_size)
		grid.set_view_window(9,[Vector2i(7,7)],[Vector2i.ZERO])
		check(grid.is_world_cell_visible(Vector2i.ZERO),"%s priority actor recenters into view"%viewport_size)
		check_eq(grid.view_origin,Vector2i.ZERO,"%s actor recenter clamps at world edge"%viewport_size)
		grid.set_view_window(9,[Vector2i.ZERO,Vector2i(14,14)],[Vector2i(7,7)])
		check_eq(grid.visible_cell_count,15,"%s required bounds wider than 9 fall back to full world"%viewport_size)
		check_eq(grid.view_origin,Vector2i.ZERO,"%s wide fallback uses full-view origin"%viewport_size)
		check(grid.is_world_cell_visible(Vector2i.ZERO) and grid.is_world_cell_visible(Vector2i(14,14)),"%s wide fallback keeps both required edges"%viewport_size)
		for world_position in [Vector2i.ZERO,Vector2i(14,14)]:
			check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(world_position)),world_position,"%s full fallback roundtrip %s"%[viewport_size,world_position])
		sandbox.free()
	return finish()

func test_wide_combat_actor_bounds_fall_back_to_full_same_grid_and_keep_input() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=_engaged_sandbox("LINE",viewport_size);var grid_id:int=sandbox.grid.get_instance_id()
		var status:Dictionary=sandbox.session.party_status();var party_ids:Array=status.party_member_ids
		var enemy:=int(status.visible_enemy_ids[0]);var positions:Dictionary={
			int(party_ids[0]):Vector2i(14,14),int(party_ids[1]):Vector2i(13,14),
			int(party_ids[2]):Vector2i(14,13),enemy:Vector2i.ZERO}
		for entity_id in positions:sandbox.session.sim.world.entities[int(entity_id)].position=positions[entity_id]
		sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
		check_eq(sandbox.grid.get_instance_id(),grid_id,"%s wide fallback keeps same grid"%viewport_size)
		check_eq(sandbox.grid.visible_cell_count,15,"%s >9 actor bounds use full window"%viewport_size)
		check_eq(sandbox.grid.view_origin,Vector2i.ZERO,"%s wide actor fallback origin"%viewport_size)
		for cell in sandbox.session.observe_party_world().cells:
			for actor in cell.actors:
				var actor_position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
				check(sandbox.grid.is_world_cell_visible(actor_position),"%s actor %s remains visible in fallback"%[viewport_size,actor.entity_id])
		var routed:Array=[];sandbox.grid.world_cell_pressed.connect(func(position):routed.append(position))
		var empty:=Vector2i(7,7);_screen_touch(sandbox,empty)
		check_eq(routed,[empty],"%s full fallback ScreenTouch maps authoritative world cell"%viewport_size)
		check_eq(sandbox.grid.pixel_to_world_cell(sandbox.grid.world_to_pixel_center(Vector2i(14,14))),Vector2i(14,14),"%s fallback edge roundtrip"%viewport_size)
		sandbox.free()
	return finish()

func test_fixed_action_feedback_uses_facade_messages_for_seven_production_rejections() -> bool:
	var draft=_engaged_sandbox("WEDGE");var draft_status:Dictionary=draft.session.party_status()
	var draft_companion:=int(draft_status.party_member_ids[1]);var draft_rejection:Dictionary=draft.session.preview_actor_action(draft_companion,"HOLD")
	check_eq(draft_rejection.reason_code,"turn_draft_required","draft-required fixture reason");var draft_expected:=str(draft_rejection.message)
	var draft_snapshot:Dictionary=_session_surface_snapshot(draft.session);_press(draft,"MemberCard%d"%draft_companion);_press(draft,"ActorHold")
	_assert_fixed_feedback(draft,draft_expected,"draft-required")
	check_eq(_session_surface_snapshot(draft.session),draft_snapshot,"draft-required UI rejection is world/draft/journal no-op")
	draft.free()

	var busy=_engaged_with_slots([1]);var busy_status:Dictionary=busy.session.party_status();var busy_hero:=int(busy_status.protagonist_id)
	var busy_companion:=int(busy_status.party_member_ids[1]);busy.session.sim.world.party_encounter.member(busy_companion).busy_until=busy.session.sim.world.world_time+37
	busy._refresh();_press(busy,"MemberCard%d"%busy_hero);_press(busy,"ActorHold");_press(busy,"MemberCard%d"%busy_companion)
	var busy_rejection:Dictionary=busy.session.preview_actor_action(busy_companion,"HOLD");check_eq(busy_rejection.reason_code,"party_actor_busy","busy fixture reason")
	var busy_expected:=str(busy_rejection.message);var busy_snapshot:Dictionary=_session_surface_snapshot(busy.session)
	_press(busy,"ActorHold");_assert_fixed_feedback(busy,busy_expected,"busy")
	check("37 시간 남음" in busy.action_feedback_label.text,"busy fixed feedback preserves structured remaining time")
	check_eq(_session_surface_snapshot(busy.session),busy_snapshot,"busy UI rejection is world/draft/journal no-op");busy.free()

	var wall_session=Session.new();var wall_state=wall_session.sim.world.party_encounter;var wall_destination:=Vector2i(5,6)
	check(wall_session.sim.world.bootstrap_set_terrain(wall_destination,"wall"),"wall fixture")
	var wall=_engaged_from_session(wall_session,[1,2]);var wall_companion:=int(wall_state.party_member_ids[1]);wall.grid.size=wall.grid.custom_minimum_size
	_press(wall,"ActorHold");_press(wall,"MemberCard%d"%wall_companion)
	check_eq(_card_position(wall,wall_companion),Vector2i(6,6),"wall companion production position")
	var wall_rejection:Dictionary=wall.session.preview_actor_action(wall_companion,"MOVE",[wall_destination.x,wall_destination.y]);check_eq(wall_rejection.reason_code,"move_terrain_blocked","wall fixture reason")
	var wall_expected:=str(wall_rejection.message);var wall_snapshot:Dictionary=_session_surface_snapshot(wall.session)
	_screen_touch(wall,wall_destination);wall._refresh();_assert_fixed_feedback(wall,wall_expected,"wall")
	check_eq(_session_surface_snapshot(wall.session),wall_snapshot,"wall UI rejection is world/draft/journal no-op");wall.free()

	var occupied_session=Session.new();var occupied_state=occupied_session.sim.world.party_encounter;var occupied_destination:=Vector2i(5,6)
	var occupied=_engaged_from_session(occupied_session,[1,2]);var occupied_companion:=int(occupied_state.party_member_ids[1]);occupied.grid.size=occupied.grid.custom_minimum_size
	_press(occupied,"MemberCard%d"%occupied_companion)
	# The rendered observation is intentionally one frame stale: the real grid still
	# routes this visually empty cell while the facade remains authoritative.
	var blocker=occupied.session.sim.world.add_entity("obstacle","상자",occupied_destination,100,[],"human","neutral");check(blocker!=null,"occupied fixture")
	check(bool(occupied.session.set_actor_action(int(occupied_state.protagonist_id),"HOLD").accepted),"occupied fixture current hero draft")
	var occupied_rejection:Dictionary=occupied.session.preview_actor_action(occupied_companion,"MOVE",[occupied_destination.x,occupied_destination.y]);check_eq(occupied_rejection.reason_code,"move_destination_occupied","occupied fixture reason")
	var occupied_expected:=str(occupied_rejection.message);var occupied_snapshot:Dictionary=_session_surface_snapshot(occupied.session)
	_screen_touch(occupied,occupied_destination);occupied._refresh();_assert_fixed_feedback(occupied,occupied_expected,"occupied")
	check_eq(_session_surface_snapshot(occupied.session),occupied_snapshot,"occupied UI rejection is world/draft/journal no-op");occupied.free()

	var distant=_engaged_sandbox("WEDGE");var distant_status:Dictionary=distant.session.party_status();var distant_hero:=int(distant_status.protagonist_id)
	var distant_companion:=int(distant_status.party_member_ids[1]);distant.grid.size=distant.grid.custom_minimum_size
	_press(distant,"MemberCard%d"%distant_hero);_press(distant,"ActorHold");_press(distant,"MemberCard%d"%distant_companion)
	var distant_origin:=_card_position(distant,distant_companion);var distant_destination:=distant_origin+Vector2i(3,0)
	var distant_rejection:Dictionary=distant.session.preview_actor_action(distant_companion,"MOVE",[distant_destination.x,distant_destination.y]);check_eq(distant_rejection.reason_code,"move_not_adjacent","nonadjacent fixture reason")
	var distant_expected:=str(distant_rejection.message);var distant_snapshot:Dictionary=_session_surface_snapshot(distant.session)
	_screen_touch(distant,distant_destination);distant._refresh();_assert_fixed_feedback(distant,distant_expected,"nonadjacent")
	check_eq(_session_surface_snapshot(distant.session),distant_snapshot,"nonadjacent UI rejection is world/draft/journal no-op");distant.free()

	var conflict=_engaged_with_slots([1]);var conflict_status:Dictionary=conflict.session.party_status();var conflict_hero:=int(conflict_status.protagonist_id)
	var conflict_companion:=int(conflict_status.party_member_ids[1]);var conflict_destination:=Vector2i(8,7)
	check(_relocate_with_move_events(conflict.session.sim,conflict_companion,Vector2i(9,7)),"conflict fixture canonical companion relocation")
	check(bool(conflict.session.set_actor_action(conflict_hero,"MOVE",[conflict_destination.x,conflict_destination.y]).accepted),"conflict fixture hero draft");conflict._refresh();conflict.grid.size=conflict.grid.custom_minimum_size
	_press(conflict,"MemberCard%d"%conflict_companion)
	var conflict_rejection:Dictionary=conflict.session.preview_actor_action(conflict_companion,"MOVE",[conflict_destination.x,conflict_destination.y]);check_eq(conflict_rejection.reason_code,"destination_conflict","conflict fixture reason")
	var conflict_expected:=str(conflict_rejection.message);var conflict_snapshot:Dictionary=_session_surface_snapshot(conflict.session)
	_screen_touch(conflict,conflict_destination);conflict._refresh();_assert_fixed_feedback(conflict,conflict_expected,"conflict")
	check_eq(_session_surface_snapshot(conflict.session),conflict_snapshot,"conflict UI rejection is world/draft/journal no-op");conflict.free()

	var dormant=_engaged_with_slots([]);var dormant_status:Dictionary=dormant.session.party_status();var dormant_hero:=int(dormant_status.protagonist_id)
	var dormant_companion:=int(dormant_status.party_member_ids[1]);_press(dormant,"MemberCard%d"%dormant_hero);_press(dormant,"ActorHold");_press(dormant,"MemberCard%d"%dormant_companion)
	var dormant_rejection:Dictionary=dormant.session.preview_actor_action(dormant_companion,"HOLD");check_eq(dormant_rejection.reason_code,"override_actor_not_deployed","dormant fixture reason")
	var dormant_expected:=str(dormant_rejection.message);var dormant_snapshot:Dictionary=_session_surface_snapshot(dormant.session)
	_press(dormant,"ActorHold");_assert_fixed_feedback(dormant,dormant_expected,"dormant")
	check_eq(_session_surface_snapshot(dormant.session),dormant_snapshot,"dormant UI rejection is world/draft/journal no-op");dormant.free()
	return finish()

func test_screen_touch_routes_exact_world_cells_at_both_portrait_sizes() -> bool:
	for viewport_size in [Vector2(360,640), Vector2(450,800)]:
		var sandbox = _engaged_sandbox("COLUMN", viewport_size)
		# This synchronous unit runner does not enter the scene tree, so containers do
		# not perform a layout pass. Give the real grid its portrait-budgeted extent;
		# the viewport smoke exercises the same routing after a live layout pass.
		sandbox.grid.size = sandbox.grid.custom_minimum_size
		var status: Dictionary = sandbox.session.party_status(); var hero := int(status.protagonist_id)
		_press(sandbox, "MemberCard%d" % hero)
		var hero_position := _card_position(sandbox, hero); var legal_count := 0
		sandbox._on_cell(hero_position+Vector2i(3,0)); sandbox._refresh()
		check(not sandbox.pending_move_valid,"%s invalid far cell stays preview-only"%viewport_size)
		check("한 칸" in sandbox.notice_text or "이동할 수" in sandbox.notice_text,"%s invalid move reason is immediate Korean"%viewport_size)
		sandbox._on_actor(hero); sandbox._refresh()
		for direction in [Vector2i.UP,Vector2i(1,-1),Vector2i.RIGHT,Vector2i(1,1),Vector2i.DOWN,Vector2i(-1,1),Vector2i.LEFT,Vector2i(-1,-1)]:
			var destination: Vector2i = hero_position + direction
			if not sandbox.session.sim.assess_move(hero, destination).accepted: continue
			legal_count += 1; _screen_touch(sandbox, destination); sandbox._refresh()
			check_eq(sandbox.pending_move_destination,destination,"%s first tap previews exact destination"%viewport_size)
			check(sandbox.find_child("MovePreviewSummary",true,false)!=null,"%s large move preview visible"%viewport_size)
			_screen_touch(sandbox, destination); sandbox._refresh()
			var preview: Dictionary = sandbox.session.current_turn_preview()
			check(bool(preview.get("accepted", false)), "%s empty-cell touch creates accepted MOVE (%s)" % [viewport_size, preview.get("reason", "missing")])
			var rows: Array = preview.get("actor_rows", [])
			if not rows.is_empty():
				check_eq(rows[0].action.type, "MOVE", "%s exact empty cell is not stolen by 44px hero slop" % viewport_size)
				check_eq(rows[0].action.destination, [destination.x,destination.y], "%s touch MOVE destination exact" % viewport_size)
		check(legal_count > 0, "%s has legal adjacent touch regression cells" % viewport_size)
		var companion := int(status.party_member_ids[1]); _screen_touch(sandbox, _card_position(sandbox, companion)); sandbox._refresh()
		check_eq(sandbox.selected_member_id, companion, "%s party-cell touch selects member" % viewport_size)
		_screen_touch(sandbox, hero_position); sandbox._refresh()
		check_eq(sandbox.selected_member_id, hero, "%s protagonist cell reselects hero" % viewport_size)
		var enemy := int(status.visible_enemy_ids[0]); var enemy_position := Vector2i.ZERO
		for target in sandbox.session.enemy_targets():
			if int(target.entity_id) == enemy: enemy_position = Vector2i(int(target.position[0]),int(target.position[1])); break
		_screen_touch(sandbox, enemy_position); sandbox._refresh()
		check_eq(sandbox.selected_member_id, hero, "%s enemy-cell touch does not select enemy" % viewport_size)
		check_eq(sandbox.selected_target_id, enemy, "%s enemy-cell touch selects target" % viewport_size)
		var routed: Array = []; sandbox.grid.actor_pressed.connect(func(id): routed.append(id))
		var outside := InputEventScreenTouch.new(); outside.pressed = true
		outside.position = sandbox.grid.grid_rect().position + Vector2(-1.0, sandbox.grid.cell_size_px() * 0.5)
		sandbox.grid._gui_input(outside)
		check(routed.is_empty(), "%s touch outside grid never routes edge actor" % viewport_size)
		sandbox.free()
	return finish()

func test_party_hud_shows_three_cropped_portraits_vitals_readiness_and_emotion() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(Session.new())
	check_eq(sandbox.cards.get_child_count(),3,"all three HUD portraits present together")
	for member_id in sandbox.session.party_status().party_member_ids:
		var card := _button(sandbox,"MemberCard%d"%int(member_id))
		var portrait := card.find_child("Portrait", true, false) as TextureRect
		check(portrait != null and portrait.texture is AtlasTexture, "member card has AtlasTexture portrait")
		check(portrait.custom_minimum_size.x>=52 and portrait.custom_minimum_size.y>=54,"portrait is enlarged")
		var region:Vector2=(portrait.texture as AtlasTexture).region.size
		check(region.x<36 and region.y<44,"portrait crops face and upper body")
		check(card.find_child("MemberName", true, false) != null, "card has controlled name row")
		check(card.find_child("MemberState", true, false) != null, "card has HP/status/presence row")
		check(card.find_child("HealthBar", true, false) != null, "card has HP bar")
		check(card.find_child("StressBar", true, false) != null, "card has stress bar")
		check(card.find_child("Readiness", true, false) != null, "card has real readiness state")
		check(card.find_child("EmotionState", true, false) != null, "card has derived emotion icon and text")
	var detail:=sandbox.find_child("MemberElements",true,false) as Label
	for component in ["불","물","전","독"]:check(detail!=null and component in detail.text,"selected detail shows %s"%component)
	var hero:=int(sandbox.session.party_status().protagonist_id); var calm:=str((_button(sandbox,"MemberCard%d"%hero).find_child("EmotionState",true,false) as Label).text)
	sandbox.session.sim.world.entities[hero].health=20; sandbox._refresh()
	var threatened:=str((_button(sandbox,"MemberCard%d"%hero).find_child("EmotionState",true,false) as Label).text)
	check(calm!=threatened and "겁먹음" in threatened,"low HP deterministically exposes survival emotion")
	sandbox.free(); return finish()

func test_enemy_tap_targets_without_selecting_enemy_and_rejections_are_visible() -> bool:
	var sandbox=_engaged_sandbox("WEDGE"); var status:Dictionary=sandbox.session.party_status()
	var hero:=int(status.protagonist_id); var enemy:=int(status.visible_enemy_ids[0])
	check_eq(sandbox.selected_member_id,hero,"hero initially selected")
	sandbox._on_actor(enemy)
	sandbox._refresh()
	check_eq(sandbox.selected_member_id,hero,"enemy tap never selects enemy")
	check_eq(sandbox.selected_target_id,enemy,"enemy target highlighted")
	check(_button(sandbox,"OverrideClear").disabled,"enemy tap does not expose companion override")
	check("공격" in str(sandbox.find_child("ActionStatus",true,false).text),"illegal enemy tap reason visible")
	_press(sandbox,"ActorHold"); check(bool(sandbox.session.current_turn_preview().accepted),"hero draft via hold")
	var companion:=int(status.party_member_ids[1]); _press(sandbox,"MemberCard%d"%companion)
	var companion_row:Dictionary
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: companion_row=row
	var destination:=[int(companion_row.logical_position[0])+1,int(companion_row.logical_position[1])]
	sandbox._on_cell(Vector2i(destination[0],destination[1])); sandbox._refresh()
	check(sandbox.pending_move_actor_id==companion,"first companion tap is preview only")
	sandbox._on_cell(Vector2i(destination[0],destination[1]))
	sandbox._refresh()
	var overridden:Dictionary
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check(overridden.expected_action is Dictionary and overridden.expected_action.source=="OVERRIDE","companion move override")
	check("덮어쓰기" in str(overridden.expected_action.text),"override Korean label")
	check(overridden.expected_action.automatic_suggestion is Dictionary,"override preserves original automatic suggestion")
	check(sandbox.grid._intent_overlays.size()==3,"hero and companion intents overlaid")
	check_eq(sandbox.grid._secondary_intent_overlays.size(),1,"grid renders original suggestion as secondary overlay")
	var actual_overlay:Dictionary;var secondary:Dictionary=sandbox.grid._secondary_intent_overlays[0]
	for row in sandbox.grid._intent_overlays:if int(row.actor_id)==companion:actual_overlay=row
	check_eq(actual_overlay.source,"OVERRIDE","actual overlay remains orange override")
	check_eq(actual_overlay.line_style,"SOLID_THICK","actual override uses solid thick line")
	check_eq(actual_overlay.marker_style,"SQUARE","actual override uses square marker")
	check_eq(secondary.source,"SUGGESTED","secondary overlay is original suggestion")
	check_eq(secondary.line_style,"DASHED_THIN","secondary overlay uses thin dashed line")
	check_eq(secondary.marker_style,"CIRCLE","secondary overlay uses circle marker")
	check_eq(secondary.from_position,actual_overlay.from_position,"secondary overlay origin is complete")
	var turn_summary:=sandbox.find_child("TurnSummary",true,false) as Label
	var selected_detail:=sandbox.find_child("ExpectedAction",true,false) as Label
	check(turn_summary!=null and "개별 덮어쓰기" in turn_summary.text and "원래 제안" in turn_summary.text,"turn summary simultaneously renders actual and original")
	check(selected_detail!=null and "개별 지시:" in selected_detail.text and "원래 제안:" in selected_detail.text,"selected detail simultaneously renders actual and original")
	check(sandbox.find_child("IntentLegend",true,false)!=null,"dual overlay has non-color legend")
	_press(sandbox,"ActorHold")
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check_eq(overridden.expected_action.type,"HOLD","selected companion HOLD override")
	_press(sandbox,"OverrideClear")
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check_eq(overridden.expected_action.source,"SUGGESTED","clear restores automatic suggestion")
	check(sandbox.grid._secondary_intent_overlays.is_empty(),"clear removes original secondary overlay")
	turn_summary=sandbox.find_child("TurnSummary",true,false) as Label
	selected_detail=sandbox.find_child("ExpectedAction",true,false) as Label
	check(turn_summary!=null and not "원래 제안" in turn_summary.text,"clear removes dual turn summary")
	check(selected_detail!=null and not "원래 제안" in selected_detail.text,"clear restores one automatic action detail")
	sandbox.free(); return finish()

func test_same_grid_survives_combat_regroup_complete_and_post_regroup_move() -> bool:
	var sandbox=Sandbox.new();sandbox.size=Vector2(450,800);sandbox.initialize_for_headless_test(Session.new())
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	var grid_id=sandbox.grid.get_instance_id();var exploration_mapping=sandbox.grid.mapping_signature()
	_explore_wait(sandbox);_press(sandbox,"PresetLINE");_press(sandbox,"DeployConfirm");sandbox.grid.size=sandbox.grid.custom_minimum_size
	check_eq(sandbox.grid.visible_cell_count,9,"combat uses 9x9 crop")
	var status:Dictionary=sandbox.session.party_status(); var hero:=int(status.protagonist_id); var enemy:=int(status.visible_enemy_ids[0])
	check(_relocate_with_move_events(sandbox.session.sim, enemy,
		sandbox.session.sim.world.entities[hero].position + Vector2i.RIGHT), "UI enemy canonical relocation")
	sandbox.session.sim.world.entities[enemy].health=22; sandbox._refresh()
	check(sandbox.grid._active_visual_effects.is_empty(),"combat setup has no commit effects")
	sandbox._on_actor(enemy); sandbox._refresh(); check(bool(sandbox.session.current_turn_preview().accepted),"enemy tap creates hero melee")
	check(sandbox.grid._active_visual_effects.is_empty(),"accepted melee preview never plays commit effects")
	_press(sandbox,"TurnConfirm"); check_eq(sandbox.session.party_status().safe_phase,"GROUPED_COMPLETE","victory auto-regroups via UI turn confirm")
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	check(not sandbox.grid._active_visual_effects.is_empty(),"accepted combat commit consumes projected visual effects")
	var effect_kinds:Array=[]
	for effect in sandbox.grid._active_visual_effects:effect_kinds.append(str(effect.kind))
	for kind in ["SLASH","HIT_FLASH","FLOATING_AMOUNT","DEATH"]:check(kind in effect_kinds,"combat commit renders %s effect"%kind)
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives combat")
	check_eq(sandbox.grid.visible_cell_count,15,"victory immediately restores full 15x15 view")
	check_eq(sandbox.grid.view_origin,Vector2i.ZERO,"victory clears combat camera origin")
	check_eq(sandbox.grid.mapping_signature(),exploration_mapping,"zoom-out restores exact exploration mapping")
	check(_button(sandbox,"RegroupConfirm")==null,"manual regroup control removed")
	check("자동으로 재집결" in sandbox.notice_text,"completion notice is explicit")
	check("승리 · 자동 재집결" in sandbox.phase_label.text,"victory banner is explicit")
	check(not sandbox.combat_action_dock.is_visible_in_tree(),"combat dock hides after victory")
	check(sandbox.grid._intent_overlays.is_empty(),"phase transition clears stale action overlays")
	check_eq(sandbox.session.party_status().contact_kind,"NONE","stale contact cleared")
	check_eq(sandbox.session.party_status().formation_id,"NONE","stale formation cleared")
	var old_anchor:Array=sandbox.session.party_status().anchor
	var left:=Vector2i(int(old_anchor[0])-1,int(old_anchor[1])); sandbox._on_cell(left); sandbox._refresh(); sandbox._on_cell(left); sandbox._refresh()
	check(sandbox.session.party_status().anchor!=old_anchor,"post-regroup UI move")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives regroup move")
	check_eq(sandbox.grid.mapping_signature(),exploration_mapping,"post-regroup full mapping remains restored")
	sandbox.free(); return finish()

func test_restored_grouped_complete_keeps_victory_banner_style_without_effect_replay() -> bool:
	var source_session=Session.new();check(_play_full_journey(source_session,"LINE"),"restored victory canonical journey")
	check_eq(source_session.party_status().safe_phase,"GROUPED_COMPLETE","restored victory source phase")
	var direct=Sandbox.new();direct.size=Vector2(360,640);direct.initialize_for_headless_test(source_session);direct.grid.size=direct.grid.custom_minimum_size
	check(direct.notice_text.is_empty(),"direct fresh completed sandbox has no transient victory notice")
	check("승리 · 자동 재집결" in direct.phase_label.text,"direct fresh completed sandbox renders persistent victory")
	check_eq(direct.grid._presentation_style.style_id,"VICTORY","direct fresh completed sandbox consumes victory style")
	check(direct.grid._active_visual_effects.is_empty(),"direct fresh completed sandbox does not replay effects")
	var encoded:=source_session.save_session_json();var restored=Session.new(1,2)
	check(bool(restored.load_session_json(encoded).accepted),"restored victory session load")
	var fresh=Sandbox.new();fresh.size=Vector2(360,640);fresh.initialize_for_headless_test(restored);fresh.grid.size=fresh.grid.custom_minimum_size
	check(fresh.notice_text.is_empty(),"fresh restored sandbox has no transient victory notice")
	check("승리 · 자동 재집결" in fresh.phase_label.text,"fresh restored sandbox renders persistent victory title")
	check_eq(fresh.session.presentation_state().banner.tone,"VICTORY","fresh restored victory tone")
	check_eq(fresh.grid._presentation_style.style_id,"VICTORY","fresh restored victory grid style")
	check_eq(fresh.grid._presentation_style.border_hex,"#62d98b","fresh restored victory green grid border")
	var panel_style:=fresh.phase_panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(panel_style!=null and panel_style.border_color==Color("#62d98b"),"fresh restored banner consumes green presentation border")
	check(fresh.grid._active_visual_effects.is_empty(),"restoring victory does not replay commit effects")
	check_eq(fresh.grid.visible_cell_count,15,"restored victory uses full 15x15 camera")
	check(not fresh.combat_action_area.visible,"restored victory hides combat action area")
	fresh.free();direct.free();return finish()

func test_terminal_defeat_and_atlas_touch_tie_break_are_explicit() -> bool:
	var session=Session.new(); var state=session.sim.world.party_encounter; session.sim.world.entities[state.protagonist_id].health=5
	check(session.sim.world.bootstrap_set_fire(state.group_anchor,100)!=null,"defeat fire")
	session.commit_exploration(Command.wait(state.protagonist_id))
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(session)
	check_eq(sandbox.session.party_status().safe_phase,"PARTY_DEFEATED","terminal phase")
	check(sandbox.find_child("TerminalOverlay",true,false)!=null,"terminal overlay visible")
	check(sandbox.find_child("TurnConfirm",true,false)==null,"terminal turn confirm hidden")
	check("패배" in sandbox.phase_label.text,"terminal phase banner")
	check_eq(sandbox.grid._presentation_style.style_id,"DEFEAT","terminal grid presentation style")
	check_eq(sandbox.grid._presentation_style.border_hex,"#8f5367","terminal grid presentation border")
	var terminal_panel:=sandbox.phase_panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(terminal_panel!=null and terminal_panel.border_color==Color("#8f5367"),"terminal panel consumes defeat border")
	check(sandbox.grid.CHARACTER_ATLAS!=null,"existing character atlas loaded")
	var observation={"cells":[{"position":[7,7],"terrain_id":"floor","actors":[
		{"entity_id":10,"is_protagonist":false,"roster_slot":1,"faction_id":"party","sprite_frame":4},
		{"entity_id":11,"is_protagonist":true,"roster_slot":0,"faction_id":"party","sprite_frame":0}]}]}
	sandbox.grid.set_observation(observation); var center=sandbox.grid.world_to_pixel_center(Vector2i(7,7))
	check_eq(sandbox.grid.actor_at_pointer(center),11,"overlap tie favors protagonist")
	check_eq(sandbox.grid.actor_hit_rect(11).size,Vector2(44,44),"44 square actor hit target")
	sandbox.free(); return finish()

func _engaged_sandbox(preset:String, viewport_size: Vector2 = Vector2(450,800)):
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(Session.new())
	_explore_wait(sandbox); _press(sandbox,"Preset%s"%preset); _press(sandbox,"DeployConfirm")
	return sandbox

func _engaged_with_slots(roster_slots:Array,viewport_size:Vector2=Vector2(450,800)):
	return _engaged_from_session(Session.new(),roster_slots,viewport_size,"LINE")

func _engaged_from_session(custom_session,roster_slots:Array,viewport_size:Vector2=Vector2(450,800),preset:String="WEDGE"):
	var state=custom_session.sim.world.party_encounter;var selected:Array=[]
	for slot in roster_slots:selected.append(state.party_member_ids[int(slot)])
	custom_session.commit_exploration(Command.wait(state.protagonist_id))
	custom_session.preview_deployment(preset,selected);custom_session.commit_deployment()
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(custom_session)
	return sandbox

func _play_full_journey(custom_session,formation:String)->bool:
	if not custom_session.commit_exploration_direction(Vector2i.ZERO).accepted:return false
	if not custom_session.preview_deployment(formation,custom_session.available_companion_ids()).accepted:return false
	if not custom_session.commit_deployment().accepted:return false
	for index in range(20):
		var status:Dictionary=custom_session.party_status()
		if status.safe_phase=="GROUPED_COMPLETE":break
		if status.safe_phase!="ENGAGED":return false
		var hero:=int(status.protagonist_id);var hero_position:=Vector2i.ZERO
		for card in custom_session.party_cards():
			if int(card.entity_id)==hero:hero_position=Vector2i(int(card.logical_position[0]),int(card.logical_position[1]));break
		var targets:Array=custom_session.enemy_targets()
		if targets.is_empty():return false
		var enemy:Dictionary=targets[0];var enemy_position:=Vector2i(int(enemy.position[0]),int(enemy.position[1]))
		var preview:Dictionary
		if maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))==1:
			preview=custom_session.set_actor_action(hero,"MELEE",[],int(enemy.entity_id))
		else:
			preview={"accepted":false}
			for direction in [Vector2i(signi(enemy_position.x-hero_position.x),signi(enemy_position.y-hero_position.y)),
					Vector2i(signi(enemy_position.x-hero_position.x),0),Vector2i(0,signi(enemy_position.y-hero_position.y))]:
				if direction==Vector2i.ZERO:continue
				preview=custom_session.set_actor_action(hero,"MOVE",[hero_position.x+direction.x,hero_position.y+direction.y])
				if bool(preview.accepted):break
			if not bool(preview.get("accepted",false)):preview=custom_session.set_actor_action(hero,"HOLD")
		if not bool(preview.get("accepted",false)) or not custom_session.commit_turn().accepted:return false
	return custom_session.party_status().safe_phase=="GROUPED_COMPLETE"

func _assert_fixed_feedback(sandbox,expected_message:String,label:String)->void:
	check(sandbox.combat_action_area.visible,"%s fixed action area visible"%label)
	check(sandbox.action_feedback_label.visible,"%s fixed feedback visible"%label)
	check(not _inside_ancestor(sandbox.action_feedback_label,ScrollContainer),"%s fixed feedback has no scroll ancestor"%label)
	check(expected_message in sandbox.action_feedback_label.text,"%s consumes facade message verbatim: %s"%[label,sandbox.action_feedback_label.text])
	for raw_reason in ["turn_draft_required","party_actor_busy","move_terrain_blocked","move_destination_occupied","move_not_adjacent","destination_conflict","override_actor_not_deployed"]:
		check(not raw_reason in sandbox.action_feedback_label.text,"%s hides raw reason token %s"%[label,raw_reason])

func _session_surface_snapshot(custom_session)->Dictionary:
	return {"world":custom_session.sim.snapshot(),"journal":custom_session.command_journal.duplicate(true),
		"turn":custom_session.current_turn_preview(),"deployment":custom_session.deployment_draft()}.duplicate(true)

func _first_empty_adjacent(sandbox,entity_id:int)->Vector2i:
	var origin:=_card_position(sandbox,entity_id)
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		var destination:Vector2i=origin+direction
		if sandbox.grid.is_world_cell_visible(destination) and sandbox.grid.actor_in_world_cell(destination)==-1 \
				and sandbox.session.sim.assess_move(entity_id,destination).accepted:return destination
	return Vector2i(-1,-1)

func _button(root:Node,node_name:String)->Button:
	return root.find_child(node_name,true,false) as Button

func _press(root, node_name:String) -> void:
	_button(root,node_name).pressed.emit(); root._refresh()

func _screen_touch(sandbox, position: Vector2i) -> void:
	var event := InputEventScreenTouch.new(); event.pressed = true; event.position = sandbox.grid.world_to_pixel_center(position)
	sandbox.grid._gui_input(event)

func _explore_wait(sandbox) -> void:
	var hero:=int(sandbox.session.party_status().protagonist_id)
	sandbox._on_actor(hero); sandbox._refresh(); sandbox._on_actor(hero); sandbox._refresh()

func _card_position(sandbox, entity_id: int) -> Vector2i:
	for row in sandbox.session.party_cards():
		if int(row.entity_id) == entity_id: return Vector2i(int(row.logical_position[0]),int(row.logical_position[1]))
	return Vector2i(-1,-1)

func _inside_ancestor(node:Node,type)->bool:
	var ancestor:=node.get_parent()
	while ancestor!=null:
		if is_instance_of(ancestor,type):return true
		ancestor=ancestor.get_parent()
	return false

func _relocate_with_move_events(sim, entity_id: int, target: Vector2i) -> bool:
	for attempt in range(64):
		var current: Vector2i = sim.world.entities[entity_id].position
		if current == target:
			return true
		var delta := target - current
		var directions: Array[Vector2i] = [
			Vector2i(signi(delta.x), signi(delta.y)),
			Vector2i(signi(delta.x), 0),
			Vector2i(0, signi(delta.y)),
		]
		var moved := false
		for direction in directions:
			if direction == Vector2i.ZERO:
				continue
			var destination := current + direction
			if maxi(absi(destination.x-target.x),absi(destination.y-target.y)) \
					>= maxi(absi(current.x-target.x),absi(current.y-target.y)):
				continue
			var assessment = sim.movement.assess_move(entity_id, destination)
			if not assessment.accepted:
				continue
			var definition: Dictionary = TerrainRegistry.definition(str(assessment.terrain_id))
			if sim.movement.commit_preflighted_move(entity_id, destination,
					str(assessment.terrain_id), int(definition.move_time_cost)) == null:
				return false
			moved = true
			break
		if not moved:
			return false
	return false
