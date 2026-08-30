extends "res://tests/test_case.gd"

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

func test_companion_roster_controls_relayout_cards_and_keep_44px_touch_contract() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=Sandbox.new();sandbox.size=viewport_size
		sandbox.initialize_for_headless_test(Session.new(44,20260828,"SHOWCASE_V1"))
		var status:Dictionary=sandbox.session.party_status();var hero:=int(status.protagonist_id)
		var companion:=int(status.party_member_ids[1]);sandbox.selected_member_id=companion
		var legacy_candidate:=int(status.recruitable_member_ids[0])
		var candidate:=int(status.rescue_candidate_ids[0])
		sandbox._open_member_detail(companion)
		check(sandbox.member_detail_dismiss.visible,"%s companion detail exposes dismiss"%viewport_size)
		check(sandbox.member_detail_dismiss.custom_minimum_size.y>=44.0,"dismiss touch target >=44")
		sandbox._on_member_detail_dismiss();sandbox._refresh()
		check_eq([sandbox.cards.get_child_count(),sandbox.selected_member_id],[2,hero],
			"%s dismiss immediately relayouts and clears selection"%viewport_size)
		check(sandbox.deck.find_child("RecruitCandidate%d"%companion,true,false)==null,
			"exiled companion never returns as a candidate")
		check(sandbox.deck.find_child("RecruitCandidate%d"%legacy_candidate,true,false)==null,
			"legacy direct recruit fixture is hidden from product controls")
		var candidate_row:Node=sandbox.deck.find_child("RecruitCandidate%d"%candidate,true,false)
		var stabilize:=sandbox.deck.find_child("StabilizeMember%d"%candidate,true,false) as Button
		check(candidate_row!=null and stabilize!=null,"relationship-gated rescue candidate rendered")
		check(stabilize.custom_minimum_size.y>=44.0 and stabilize.get_parent()==candidate_row,
			"rescue touch target remains inside its candidate row")
		sandbox._open_member_detail(hero)
		check(not sandbox.member_detail_dismiss.visible,"hero detail never exposes dismiss")
		sandbox._close_member_detail();sandbox.free()
	var unsafe=Sandbox.new();unsafe.size=Vector2(360,640);unsafe.initialize_for_headless_test(Session.new())
	var unsafe_state=unsafe.session.sim.world.party_encounter
	unsafe.session.commit_exploration(Command.wait(unsafe_state.protagonist_id));unsafe._refresh()
	unsafe._open_member_detail(int(unsafe_state.party_member_ids[1]))
	check(unsafe.member_detail_dismiss.visible and unsafe.member_detail_dismiss.disabled,
		"contact detail explains roster lock without allowing input")
	check("편성" in unsafe.member_detail_dismiss.tooltip_text,"unsafe roster reason is Korean")
	unsafe.free();return finish()


func test_mobile_downed_rescue_and_stable_recruitment_refusal_use_actual_touch_facade() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=Sandbox.new();sandbox.size=viewport_size
		sandbox.initialize_for_headless_test(Session.new(7,20260828,"SHOWCASE_V1"))
		sandbox.grid.size=sandbox.grid.custom_minimum_size
		var status:Dictionary=sandbox.session.party_status()
		var target:=int(status.rescue_candidate_ids[0])
		var title:=sandbox.deck.find_child("RosterManagementTitle",true,false) as Label
		var stabilize:=sandbox.deck.find_child("StabilizeMember%d"%target,true,false) as Button
		var candidate_row:Node=sandbox.deck.find_child("RecruitCandidate%d"%target,true,false)
		var candidate_label:=candidate_row.find_child("RecruitCandidateLabel",true,false) as Label if candidate_row!=null else null
		check(title!=null and "3/3" in title.text,"%s one-glance roster capacity visible"%viewport_size)
		check(stabilize!=null and stabilize.custom_minimum_size.y>=44.0 and not stabilize.disabled,
			"%s DOWNED candidate has enabled 44px stabilize touch action"%viewport_size)
		check(candidate_label!=null and "쓰러짐" in candidate_label.text and "사망 아님" in candidate_label.text,
			"%s card clearly separates DOWNED from death"%viewport_size)
		var hit:Rect2=sandbox.grid.actor_hit_rect(target)
		check(hit.size.x>=44.0 and hit.size.y>=44.0,"%s rescue NPC map hit target >=44"%viewport_size)
		var press:=InputEventScreenTouch.new();press.pressed=true;press.position=hit.get_center()
		var release:=InputEventScreenTouch.new();release.pressed=false;release.position=hit.get_center()
		sandbox.grid._gui_input(press);sandbox.grid._gui_input(release)
		check(sandbox.member_detail_modal.visible and sandbox.member_detail_candidate_action.visible \
			and "안정화" in sandbox.member_detail_candidate_action.text,
			"%s actual grid touch opens rescue detail action"%viewport_size)
		sandbox._close_member_detail();sandbox._on_stabilize_candidate(target);sandbox._refresh()
		var recruit:=sandbox.deck.find_child("RecruitMember%d"%target,true,false) as Button
		candidate_row=sandbox.deck.find_child("RecruitCandidate%d"%target,true,false)
		candidate_label=candidate_row.find_child("RecruitCandidateLabel",true,false) as Label if candidate_row!=null else null
		check(recruit!=null and recruit.disabled,"%s full party keeps offer visible but gated"%viewport_size)
		check(candidate_label!=null and "수락" in candidate_label.text \
			and "종족" in candidate_label.text,
			"%s probability and Korean reason visible after stabilization"%viewport_size)
		var companion:=int(sandbox.session.party_status().party_member_ids[1])
		sandbox._on_quick_dismiss_companion(companion);sandbox._refresh()
		recruit=sandbox.deck.find_child("RecruitMember%d"%target,true,false) as Button
		check(recruit!=null and not recruit.disabled and recruit.custom_minimum_size.y>=44.0,
			"%s vacancy enables 44px recruitment offer"%viewport_size)
		sandbox._on_recruit_companion(target);sandbox._refresh()
		check("거절" in sandbox.notice_text and sandbox.cards.get_child_count()==2,
			"%s deterministic refusal remains visible and does not add card"%viewport_size)
		check("영입 제안을 거절" in sandbox.log_label.text,
			"%s actual refusal remains in Korean event log"%viewport_size)
		sandbox.free()
	return finish()

func test_party_card_layout_specs_and_detached_render_support_one_two_three_members() -> bool:
	for viewport_width in [360.0,450.0]:
		var sandbox=Sandbox.new();sandbox.size=Vector2(viewport_width,640 if viewport_width==360.0 else 800)
		sandbox.initialize_for_headless_test(Session.new())
		var all_rows:Array=sandbox.session.party_cards()
		for count in [1,2,3]:
			var rows:Array=[]
			for index in range(count):rows.append(all_rows[index].duplicate(true))
			var speeches:Array=[]
			if count>=2:
				speeches.append({"actor_id":int(rows[1].entity_id),"source":"SUGGESTED",
					"headline":"이동할게.","reason_summary":"길이 열려서","reason":"목표에 접근할 길을 골랐습니다."})
			var spec:Dictionary=sandbox.render_party_cards_for_headless_test(rows,speeches)
			check_eq([str(spec.layout_id),int(spec.effective_count)],
				[["SPOTLIGHT","DUAL","COMPACT"][count-1],count],
				"%s width count %d layout"%[viewport_width,count])
			check(int(spec.font_size)==14 and bool(spec.get("portrait_removed",false)) \
				and spec.get("portrait_min_size",[])==[0,0],
				"card layout reserves no portrait area and uses compact Korean auxiliary type")
			check_eq(sandbox.cards.get_child_count(),count,"renderer uses DTO row count")
			for index in range(count):
				var card:=sandbox.cards.get_child(index) as Button
				check(card.custom_minimum_size.x>=float(spec.card_min_width),"card deterministic minimum width")
				check(card.find_child("Portrait",true,false)==null,
					"count %d card leaves the full dossier width to text"%count)
				var speech:=card.find_child("CompanionSpeechStrip",true,false)
				if index==0:check(speech==null,"hero never receives speech strip")
				elif index==1:check(speech!=null,"companion owns compact speech strip")
			if count==1:
				var hero_card:=sandbox.cards.get_child(0) as Button
				check(hero_card.find_child("SpotlightDetails",true,false)!=null,"single member uses horizontal spotlight")
				check("/" in str((hero_card.find_child("MemberState",true,false) as Label).text),
					"spotlight shows exact HP maximum")
		var detached:=sandbox.party_card_layout_spec(2,viewport_width);detached.portrait_removed=false
		check(bool(sandbox.party_card_layout_spec(2,viewport_width).portrait_removed),
			"layout spec is deeply detached")
		check_eq(int(sandbox.party_card_layout_spec(0,viewport_width).effective_count),0,"zero rows safely empty")
		check_eq(int(sandbox.party_card_layout_spec(9,viewport_width).effective_count),3,"over-cap rows safely clamp")
		var companion_detail:Dictionary=sandbox.session.inspect_party_member(int(all_rows[1].entity_id))
		check(str(companion_detail.personality_archetype.label) in sandbox._member_detail_text(companion_detail),
			"detail modal exposes short Korean archetype")
		var log_text:=sandbox._combat_log_text(sandbox.session.combat_log())
		check("이번 원정 성향" in log_text and "나래:" in log_text,"new expedition log identifies rerolled archetypes")
		sandbox.free()
	return finish()

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
		check(actor_events.is_empty() and world_events.is_empty(),"%s press alone cannot select or move"%viewport_size)
		var near_release:=InputEventScreenTouch.new();near_release.pressed=false
		near_release.position=sandbox.grid.world_to_pixel_center(hero_position+Vector2i.RIGHT)
		sandbox.grid._gui_input(near_release)
		check_eq(actor_events,[hero],"%s press-time actor target stays immutable through <=14px release movement"%viewport_size)
		check(world_events.is_empty(),"%s actor slop is not misrouted as movement"%viewport_size)
		sandbox._clear_move_preview();actor_events.clear();world_events.clear()
		var adjacent:=hero_position+Vector2i.RIGHT
		var exact_empty:=InputEventScreenTouch.new();exact_empty.pressed=true
		exact_empty.position=sandbox.grid.world_to_pixel_center(adjacent)
		sandbox.grid._gui_input(exact_empty)
		check(actor_events.is_empty() and world_events.is_empty(),"%s empty-cell press alone is pure"%viewport_size)
		var empty_release:=InputEventScreenTouch.new();empty_release.pressed=false;empty_release.position=exact_empty.position
		sandbox.grid._gui_input(empty_release)
		check(actor_events.is_empty(),"%s adjacent empty center is not stolen by hero slop"%viewport_size)
		check_eq(world_events,[adjacent],"%s adjacent center routes exact world cell"%viewport_size)
		actor_events.clear();world_events.clear()
		var outside:=InputEventScreenTouch.new();outside.pressed=true
		outside.position=sandbox.grid.grid_rect().position+Vector2(-1,sandbox.grid.cell_size_px()*0.5)
		sandbox.grid._gui_input(outside);outside.pressed=false;sandbox.grid._gui_input(outside)
		check(actor_events.is_empty() and world_events.is_empty(),"%s outside grid emits no route"%viewport_size)
		sandbox.free()
	return finish()

func test_grid_gesture_rejects_wrong_release_cancel_modal_and_emulated_mouse_duplicate() -> bool:
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(Session.new())
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	var status:Dictionary=sandbox.session.party_status();var origin:=Vector2i(int(status.anchor[0]),int(status.anchor[1]))
	var destination:=origin+Vector2i.RIGHT;var pointer:Vector2=sandbox.grid.world_to_pixel_center(destination)
	var routed:Array=[];sandbox.grid.world_cell_pressed.connect(func(cell):routed.append(cell))
	var press:=InputEventScreenTouch.new();press.index=21;press.pressed=true;press.position=pointer
	sandbox.grid._gui_input(press)
	var wrong_release:=InputEventScreenTouch.new();wrong_release.index=22;wrong_release.pressed=false;wrong_release.position=pointer
	sandbox.grid._gui_input(wrong_release)
	check(routed.is_empty() and bool(sandbox.grid.pointer_gesture_state().active),"wrong touch index cannot finish another gesture")
	var correct_release:=InputEventScreenTouch.new();correct_release.index=21;correct_release.pressed=false;correct_release.position=pointer
	sandbox.grid._gui_input(correct_release)
	check_eq(routed,[destination],"matching release emits the stored target once")
	var mouse_press:=InputEventMouseButton.new();mouse_press.button_index=MOUSE_BUTTON_LEFT;mouse_press.pressed=true;mouse_press.position=pointer
	var mouse_release:=InputEventMouseButton.new();mouse_release.button_index=MOUSE_BUTTON_LEFT;mouse_release.pressed=false;mouse_release.position=pointer
	sandbox.grid._gui_input(mouse_press);sandbox.grid._gui_input(mouse_release)
	check_eq(routed,[destination],"immediate touch-emulated mouse pair is suppressed")
	routed.clear();press.index=23;sandbox.grid._gui_input(press)
	var os_cancel:=InputEventScreenTouch.new();os_cancel.index=23;os_cancel.pressed=false;os_cancel.canceled=true;os_cancel.position=pointer
	sandbox.grid._gui_input(os_cancel)
	check(routed.is_empty() and not bool(sandbox.grid.pointer_gesture_state().active),"OS-cancelled touch emits nothing and clears pending target")
	press.index=24;sandbox.grid._gui_input(press);sandbox.grid.modal_open=true
	var modal_release:=InputEventScreenTouch.new();modal_release.index=24;modal_release.pressed=false;modal_release.position=pointer
	sandbox.grid._gui_input(modal_release)
	check(routed.is_empty() and not bool(sandbox.grid.pointer_gesture_state().active),"modal gate cancels a pending grid gesture")
	sandbox.grid.modal_open=false;press.index=25;sandbox.grid._gui_input(press)
	sandbox.grid.set_view_window(15,[origin]);correct_release.index=25;sandbox.grid._gui_input(correct_release)
	check(routed.is_empty(),"camera refresh cancels stale press target before release")
	press.index=26;sandbox.grid._gui_input(press)
	var drag:=InputEventScreenDrag.new();drag.index=26;drag.position=pointer+Vector2(20,0);drag.relative=Vector2(20,0)
	sandbox.grid._gui_input(drag)
	var dragged_state:Dictionary=sandbox.grid.pointer_gesture_state()
	check(bool(dragged_state.active) and bool(dragged_state.cancelled),"drag slop cancels target but retains pointer ownership until release")
	check(routed.is_empty(),"drag cancellation emits no target before release")
	var drag_release:=InputEventScreenTouch.new();drag_release.index=26;drag_release.pressed=false;drag_release.position=pointer+Vector2(20,0)
	sandbox.grid._gui_input(drag_release)
	check(routed.is_empty() and not bool(sandbox.grid.pointer_gesture_state().active),"drag release emits nothing and ends ownership")
	sandbox.free();return finish()

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
		{"effect_id":"43:death","event_id":43,"order":2,"kind":"DEATH","world_position":[7,7],"damage_type":"physical","text":""},
		{"effect_id":"44:miss","event_id":44,"order":3,"kind":"MISS","world_position":[7,7],"damage_type":"physical","text":"빗나감"}]
	check_eq(sandbox.grid.play_effects(rows),4,"all distinct effects render even when two share one event")
	check(sandbox.grid.has_played_effect_event(42),"source event is remembered for replay diagnostics")
	check(sandbox.grid.has_played_effect("42:hit_flash") and sandbox.grid.has_played_effect("42:floating_amount"),"effect ids are deduplicated independently")
	check_eq(sandbox.grid.play_effects(rows),0,"replayed result cannot duplicate visual effects")
	check_eq(sandbox.grid._active_visual_effects.size(),4,"replay leaves one copy of each visual effect")
	var flash:Dictionary=sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[0])
	var amount:Dictionary=sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[1])
	var miss:Dictionary=sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[3])
	check_eq(flash.primitive,"FLASH_RING","hit flash draw spec is testable")
	check_eq(flash.color_hex,"#ff7a55","damage type drives deterministic effect color")
	check_eq(amount.primitive,"TEXT","floating amount draw spec is text")
	check_eq(amount.text,"-22","floating amount preserves session-projected text")
	check_eq([miss.primitive,miss.text,miss.color_hex,miss.font_size],
		["TEXT","빗나감","#b8e9ff",16],"MISS has a distinct readable text draw spec")
	flash.primitive="CORRUPTED"
	check_eq(sandbox.grid.visual_effect_draw_spec(sandbox.grid._active_visual_effects[0]).primitive,"FLASH_RING","effect draw spec is detached")
	sandbox.free();return finish()

func test_route_overlay_draw_spec_preserves_each_step_and_is_detached() -> bool:
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(Session.new())
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	var path:Array=[[7,7],[6,7],[5,7],[4,7]]
	sandbox.grid.set_route_overlay(path,1,true)
	var spec:Dictionary=sandbox.grid.route_draw_spec()
	check_eq(spec.path,path,"route draw spec preserves authoritative path")
	check_eq(spec.segments.size(),3,"route draws every edge instead of destination shortcut")
	check_eq(spec.tiles.size(),path.size(),"every route cell gets a translucent highlight")
	check_eq(spec.direction_cues.size(),spec.segments.size(),"every route edge gets a directional cue without step numbers")
	check(float(spec.tiles[2].fill_alpha)>=0.18 and bool(spec.tiles[2].visible),"future route tiles remain visibly highlighted")
	check_eq(spec.direction_cues[1].points.size(),3,"direction cue is a compact chevron")
	check(bool(spec.segments[0].completed) and not bool(spec.segments[1].completed),"completed and next segments are distinct")
	check_eq(spec.markers[0].kind,"START","route start marker")
	check_eq(spec.markers[2].kind,"NEXT","route next-step marker")
	check_eq(spec.markers[3].kind,"GOAL","route goal marker")
	spec.path[0][0]=-99;spec.segments[0].from_position[0]=-99;spec.tiles[0].position[0]=-99
	spec.direction_cues[0].points[0]=Vector2(-99,-99)
	var fresh:Dictionary=sandbox.grid.route_draw_spec()
	check_eq(fresh.path[0],[7,7],"route path DTO is detached")
	check_eq(fresh.segments[0].from_position,[7,7],"route segment DTO is detached")
	check_eq(fresh.tiles[0].position,[7,7],"route tile highlight DTO is detached")
	check(fresh.direction_cues[0].points[0]!=Vector2(-99,-99),"route direction DTO is detached")
	sandbox.grid.clear_route_overlay();check(sandbox.grid.route_draw_spec().path.is_empty(),"route overlay clears explicitly")
	sandbox.free();return finish()

func test_exploration_grid_one_tap_starts_route_invalid_is_pure_and_contact_clears() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(Session.new()); sandbox.grid.size=sandbox.grid.custom_minimum_size
	for button_name in ["ExploreN","ExploreNE","ExploreE","ExploreSE","ExploreS","ExploreSW","ExploreW","ExploreNW","ExploreHold"]:
		check(_button(sandbox,button_name)==null,"legacy D-pad absent: %s"%button_name)
	var exploration_notice:=str((sandbox.find_child("ActionStatus",true,false) as Label).text)
	check("한 번" in exploration_notice and not "다시" in exploration_notice,
		"exploration guidance advertises one-tap long route")
	var status:Dictionary=sandbox.session.party_status(); var origin:=Vector2i(int(status.anchor[0]),int(status.anchor[1])); var destination:=origin+Vector2i.RIGHT
	var hero:=int(status.protagonist_id);var companion:=int(status.party_member_ids[1])
	_press(sandbox,"MemberCard%d"%companion)
	check_eq(sandbox.selected_member_id,companion,"companion dossier remains available for details in exploration")
	var before:Dictionary=sandbox.session.sim.snapshot(); sandbox._on_cell(destination); sandbox._refresh()
	check_eq(sandbox.session.party_status().safe_phase,"CONTACT","one tap commits one move and contact")
	check_eq(sandbox.session.sim.world.step_index,int(before.step_index)+1,"exactly one exploration step")
	check_eq(sandbox.session.sim.world.world_time,int(before.world_time)+100,"exactly one movement cost")
	check_eq(sandbox.session.command_journal[-1].command.actor_id,str(hero),"committed exploration command belongs exactly to hero")
	check_eq(sandbox.session.party_status().anchor,[destination.x,destination.y],"group anchor follows representative move")
	for row in sandbox.session.party_cards():
		if int(row.entity_id)!=hero:check_eq(row.logical_position,[destination.x,destination.y],"grouped companion logical anchor stays synchronized")
	check(sandbox.pending_move_mode.is_empty() and sandbox.grid.cursor_cell==Vector2i(-1,-1),"contact clears stale exploration preview")
	var invalid=Sandbox.new(); invalid.size=Vector2(360,640); invalid.initialize_for_headless_test(Session.new())
	check(invalid.session.sim.world.bootstrap_set_terrain(origin+Vector2i.LEFT,"wall"),"wall preview fixture")
	var wall_before:Dictionary=invalid.session.sim.snapshot()
	var wall_journal:Array=invalid.session.command_journal.duplicate(true)
	var wall_draft:Dictionary=invalid.session.exploration_route_draft()
	var wall_state:Dictionary=invalid.session.exploration_route_state()
	invalid._on_cell(origin+Vector2i.LEFT); invalid._refresh()
	check_eq(invalid.session.sim.snapshot(),wall_before,"wall preview is no-op")
	check_eq([invalid.session.command_journal,invalid.session.exploration_route_draft(),
		invalid.session.exploration_route_state()],[wall_journal,wall_draft,wall_state],
		"invalid one-tap destination preserves journal, draft, and active state")
	check(str(invalid.route_preview.reason_code)!="ok","wall rejection keeps facade reason")
	check_eq(invalid.notice_text,invalid.route_preview.message,"wall rejection shows facade Korean message")
	check(not invalid.tile_popover.visible,"ordinary invalid tap shows feedback but never opens risk popover")
	invalid._on_tile_long_pressed(origin+Vector2i.LEFT)
	check(invalid.tile_popover.visible and str(invalid.route_preview.message) in invalid.tile_popover_label.text,"explicit long inspection includes rejected route message")
	var far=Sandbox.new();far.size=Vector2(360,640);far.initialize_for_headless_test(Session.new());far.grid.size=far.grid.custom_minimum_size
	var far_goal:=Vector2i(-1,-1)
	for candidate in [origin+Vector2i(-3,0),origin+Vector2i(0,3),origin+Vector2i(0,-3)]:
		var probe:Dictionary=far.session.preview_exploration_route(candidate)
		if bool(probe.get("accepted",false)) and int(probe.get("total_steps",0))>=3:far_goal=candidate
		far.session.cancel_exploration_route()
		if far_goal!=Vector2i(-1,-1):break
	check(far_goal!=Vector2i(-1,-1),"far route fixture exists")
	var far_before:Dictionary=far.session.sim.snapshot();far._on_cell(far_goal);far._refresh()
	check_eq(far.session.sim.world.step_index,int(far_before.step_index)+1,"far one tap starts exactly one hop")
	check(bool(far.route_preview.get("accepted",false)) and int(far.route_preview.total_steps)>=3,"far route retains full plan")
	check_eq(far.grid.route_draw_spec().segments.size(),int(far.route_preview.total_steps),"full far path is drawn")
	var first_hop:Array=far.route_preview.path[1]
	check_eq(far.session.party_status().anchor,first_hop,"route start stops at first hop instead of teleporting")
	check(bool(far.session.exploration_route_state().active),"unfinished far route remains active for frame continuation")
	var same_goal_step:=int(far.session.sim.world.step_index)
	var same_goal_journal:Array=far.session.command_journal.duplicate(true)
	far._on_cell(far_goal);far._refresh()
	check_eq([far.session.sim.world.step_index,far.session.command_journal],
		[same_goal_step,same_goal_journal],"active same-goal tap adds no hop or commit")
	check("이동 중" in far.action_feedback_text,"active same-goal no-op is explicit")
	far._on_cell(origin);far._refresh()
	check_eq(far.session.sim.world.step_index,same_goal_step+1,
		"different valid goal cancels and starts its first hop exactly once")
	check_eq(far.session.party_status().anchor,[origin.x,origin.y],"replacement route reaches valid origin")
	var wait=Sandbox.new(); wait.size=Vector2(360,640); wait.initialize_for_headless_test(Session.new()); var wait_before=wait.session.sim.snapshot()
	wait._on_actor(int(wait.session.party_status().protagonist_id)); wait._refresh()
	check_eq(wait.session.sim.snapshot(),wait_before,"hero-cell first tap previews wait without mutation")
	check(wait.pending_exploration_wait and "대기" in wait.notice_text,"occupied hero cell is consumed as clear wait preview")
	wait.free();far.free();invalid.free();sandbox.free();return finish()

func test_each_formation_uses_visible_button_preview_ghosts_and_confirm_to_engaged() -> bool:
	for preset in ["WEDGE","LINE","COLUMN"]:
		var sandbox=Sandbox.new(); sandbox.size=Vector2(450,800); sandbox.initialize_for_headless_test(Session.new())
		sandbox.grid.size=sandbox.grid.custom_minimum_size
		var grid_id=sandbox.grid.get_instance_id(); var full_mapping=sandbox.grid.mapping_signature()
		var actor_count:=0; for cell in sandbox.session.observe_party_world().cells: actor_count += cell.actors.size()
		check_eq(actor_count,3,"%s party presentation actors visible before contact"%preset)
		_explore_wait(sandbox)
		check_eq(sandbox.session.party_status().safe_phase,"CONTACT","%s contact"%preset)
		actor_count=0; for cell in sandbox.session.observe_party_world().cells: actor_count += cell.actors.size()
		check_eq(actor_count,4,"%s enemy joins three party presentation actors at contact"%preset)
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
		check("빈 칸 이동 · 적 공격" in str(sandbox.find_child("ActionStatus",true,false).text), "%s combat instruction visible immediately"%preset)
		check_eq(sandbox.session.party_status().formation_id,preset,"formation committed")
		check_eq(sandbox.grid.get_instance_id(),grid_id,"same grid for %s"%preset)
		check_eq(sandbox.grid.visible_cell_count,15,"%s combat remains full 15x15"%preset)
		check_eq(sandbox.grid.mapping_signature(),full_mapping,"%s combat keeps exploration mapping and scale"%preset)
		for cell in sandbox.session.observe_party_world().cells:
			if cell.actors.is_empty():continue
			var actor_position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
			check(sandbox.grid.is_world_cell_visible(actor_position),"%s combat cluster remains visible"%preset)
		check_eq(sandbox.phase_label.text,"전투","%s coarse combat situation"%preset)
		check(sandbox.combat_action_area.visible,"%s fixed action area shown"%preset)
		check_eq(sandbox.combat_action_area.get_parent(),sandbox.root_layout,"%s action area is PartyLayout sibling"%preset)
		check_eq(sandbox.root_layout.get_child(sandbox.root_layout.get_child_count()-1),sandbox.bottom_navigation,
			"%s fixed bottom navigation is final PartyLayout sibling"%preset)
		check_eq(sandbox.combat_action_dock.get_parent(),sandbox.combat_action_area,"%s dock is inside fixed action area"%preset)
		check_eq(sandbox.action_feedback_label.get_parent(),sandbox.combat_action_area,"%s feedback is inside fixed action area"%preset)
		check(not _inside_ancestor(sandbox.combat_action_area,ScrollContainer),"%s action area is independent from information scroll"%preset)
		check(sandbox.action_feedback_label.get_theme_font_size("font_size")==14,"%s fixed feedback font"%preset)
		check_eq(_button(sandbox,"ActorHold").text,"[R 방어]","%s DOS dock hold command"%preset)
		check_eq(_button(sandbox,"OverrideClear").text,"[A 자동]","%s DOS dock restore command"%preset)
		check_eq(_button(sandbox,"TurnConfirm").text,"[E 실행]","%s DOS dock execute command"%preset)
		sandbox.free()
	return finish()

func test_combat_product_view_is_full_while_low_level_crop_mapping_remains_authoritative() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=_engaged_sandbox("WEDGE",viewport_size)
		var grid=sandbox.grid; grid.size=grid.custom_minimum_size
		check_eq(grid.visible_cell_count,15,"%s engaged product view is 15x15"%viewport_size)
		var bounds:Rect2i=grid.view_bounds()
		for world_position in [bounds.position,bounds.position+bounds.size-Vector2i.ONE]:
			var pixel:Vector2=grid.world_to_pixel_center(world_position)
			check_eq(grid.pixel_to_world_cell(pixel),world_position,"%s crop edge roundtrip %s"%[viewport_size,world_position])
		check(grid.is_world_cell_visible(Vector2i.ZERO) and grid.is_world_cell_visible(Vector2i(14,14)),
			"%s combat exposes both world edges"%viewport_size)
		var visible_cells:Array=[]
		for y in range(15):
			for x in range(15):
				visible_cells.append({"position":[x,y],"terrain_id":"floor",
					"visibility_state":"VISIBLE","actors":[]})
		grid.set_observation({"width":15,"height":15,"cells":visible_cells})
		grid.set_view_window(9,[Vector2i(7,7)])
		var routed:Array=[]; grid.world_cell_pressed.connect(func(position):routed.append(position))
		bounds=grid.view_bounds()
		for world_position in [bounds.position,bounds.position+bounds.size-Vector2i.ONE]:
			_grid_screen_touch(grid,grid.world_to_pixel_center(world_position))
		check_eq(routed,[bounds.position,bounds.position+bounds.size-Vector2i.ONE],"%s real edge touches emit cropped world cells"%viewport_size)
		var offwindow:=Vector2i.ZERO if not grid.is_world_cell_visible(Vector2i.ZERO) else Vector2i(14,14)
		_grid_screen_touch(grid,grid.world_to_pixel_center(offwindow))
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

func test_screen_touch_routes_exact_world_cells_at_both_viewport_sizes() -> bool:
	for viewport_size in [Vector2(360,640), Vector2(450,800)]:
		var sandbox = _engaged_sandbox("COLUMN", viewport_size)
		# This synchronous unit runner does not enter the scene tree, so containers do
		# not perform a layout pass. Give the real grid its viewport-budgeted extent;
		# the viewport smoke exercises the same routing after a live layout pass.
		sandbox.grid.size = sandbox.grid.custom_minimum_size
		var status: Dictionary = sandbox.session.party_status(); var hero := int(status.protagonist_id)
		_press(sandbox, "MemberCard%d" % hero)
		var hero_position := _card_position(sandbox, hero); var legal_count := 0
		var invalid_before:Dictionary=_session_surface_snapshot(sandbox.session)
		sandbox._on_cell(hero_position+Vector2i(3,0)); sandbox._refresh()
		check(sandbox.pending_move_mode!="COMBAT","%s invalid far cell creates no combat retap state"%viewport_size)
		check("한 칸" in sandbox.notice_text or "이동할 수" in sandbox.notice_text,"%s invalid move reason is immediate Korean"%viewport_size)
		check_eq(_session_surface_snapshot(sandbox.session),invalid_before,
			"%s invalid one-tap move preserves world/draft/journal"%viewport_size)
		sandbox._on_actor(hero); sandbox._refresh()
		for direction in [Vector2i.UP,Vector2i(1,-1),Vector2i.RIGHT,Vector2i(1,1),Vector2i.DOWN,Vector2i(-1,1),Vector2i.LEFT,Vector2i(-1,-1)]:
			var destination: Vector2i = hero_position + direction
			if not sandbox.session.sim.assess_move(hero, destination).accepted: continue
			legal_count += 1; _screen_touch(sandbox, destination); sandbox._refresh()
			var preview: Dictionary = sandbox.session.current_turn_preview()
			check(bool(preview.get("accepted", false)), "%s one empty-cell touch creates accepted MOVE (%s)" % [viewport_size, preview.get("reason", "missing")])
			check(sandbox.pending_move_mode!="COMBAT" and sandbox.find_child("MovePreviewSummary",true,false)==null,
				"%s combat MOVE creates no second-tap preview"%viewport_size)
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
		sandbox.grid._gui_input(outside);outside.pressed=false;sandbox.grid._gui_input(outside)
		check(routed.is_empty(), "%s touch outside grid never routes edge actor" % viewport_size)
		sandbox.free()
	return finish()

func test_party_hud_shows_three_full_width_dossiers_vitals_readiness_and_emotion() -> bool:
	var custom_session=Session.new();var initial_status:Dictionary=custom_session.party_status()
	var initial_position:=Vector2i(int(initial_status.anchor[0]),int(initial_status.anchor[1]))
	check(custom_session.sim.world.bootstrap_set_fire(initial_position,100)!=null,"member exposure fixture")
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(custom_session)
	check_eq(sandbox.cards.get_child_count(),3,"all three HUD dossiers present together")
	for member_id in sandbox.session.party_status().party_member_ids:
		var card := _button(sandbox,"MemberCard%d"%int(member_id))
		check(card.find_child("Portrait",true,false)==null,
			"member card does not duplicate the map actor as a portrait")
		check(card.find_child("MemberName", true, false) != null, "card has controlled name row")
		check(card.find_child("MemberState", true, false) != null, "card has HP/status/presence row")
		var hp_gauge:=card.find_child("MemberState",true,false)
		check(hp_gauge!=null and hp_gauge.has_method("gauge_spec") \
			and str(hp_gauge.call("gauge_spec").primitive)=="DOS_TEXT_GAUGE", "card has compact DOS HP gauge")
		check(card.find_child("StressState", true, false) != null, "card has compact ST state")
		check(card.find_child("Readiness", true, false) != null, "card has real readiness state")
		check(card.find_child("EmotionState", true, false) != null, "card has derived emotion icon and text")
	var interaction_member:=int(sandbox.session.party_status().party_member_ids[1])
	var interaction_name:=str((_button(sandbox,"MemberCard%d"%interaction_member).find_child(
		"MemberName",true,false) as Label).text)
	sandbox._activate_member_card(interaction_member,interaction_name,
		{"time_msec":1000,"global_position":Vector2(20,20),"native_double":false})
	check_eq(sandbox.selected_member_id,interaction_member,"full card tap still selects its member")
	sandbox._activate_member_card(interaction_member,interaction_name,
		{"time_msec":1100,"global_position":Vector2(20,20),"native_double":true})
	check(sandbox.member_detail_modal.visible,"full card double tap still opens member detail")
	sandbox._close_member_detail()
	var hero:=int(sandbox.session.party_status().protagonist_id); var calm:=str((_button(sandbox,"MemberCard%d"%hero).find_child("EmotionState",true,false) as Label).text)
	sandbox._on_actor(hero);sandbox._refresh()
	check(sandbox.find_child("MemberElements",true,false)==null,"static member element row is removed")
	check(not sandbox.tile_popover.visible,"ordinary actor tap never opens terrain risk popover")
	sandbox._on_tile_long_pressed(initial_position)
	check(sandbox.tile_popover.visible,"actor-tile long inspection opens floating terrain risk popover")
	check("짧게 누르면 경로 확인 후 이동합니다" in sandbox.tile_popover_label.text and not "다시" in sandbox.tile_popover_label.text,
		"inspection without matching route preview describes the actual next short tap")
	for component in ["불","물","전기","독"]:check(component in sandbox.tile_popover_label.text,"tile popover shows %s risk"%component)
	var member_detail:Dictionary=sandbox.session.inspect_party_member(hero)
	var exposure_fire:=int(member_detail.current_exposure.risk.fire)
	check(exposure_fire>0,"member detail fixture has real fire exposure")
	var detail_text:=sandbox._member_detail_text(member_detail)
	check("현재 노출 · 불 %d"%exposure_fire in detail_text,"detail reads nested current_exposure.risk")
	check("원소 내성" in detail_text,"member modal keeps meaningful species affinity")
	check("관계" not in detail_text and "없음" not in detail_text,
		"hero supplemental detail hides relations and empty placeholders")
	sandbox.session.sim.world.entities[hero].health=20; sandbox._refresh()
	var threatened:=str((_button(sandbox,"MemberCard%d"%hero).find_child("EmotionState",true,false) as Label).text)
	check(calm!=threatened and "겁먹음" in threatened,"low HP deterministically exposes survival emotion")
	sandbox.free(); return finish()

func test_companion_speech_is_card_local_one_line_phase_gated_and_refreshes() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=_engaged_sandbox("LINE",viewport_size)
		var status:Dictionary=sandbox.session.party_status();var hero:=int(status.protagonist_id)
		check(sandbox.session.prepare_auto_combat_plan().active,
			"%s placeholder plan prepared"%viewport_size);sandbox._refresh()
		check(not sandbox.grid.has_method("speech_bubble_draw_specs"),
			"%s grid owns no speech-bubble API"%viewport_size)
		var hero_card:=_button(sandbox,"MemberCard%d"%hero)
		check(hero_card.find_child("CompanionSpeechStrip",true,false)==null,
			"%s protagonist card never speaks"%viewport_size)
		var bubbles:Array=sandbox.session.companion_speech_bubbles()
		check_eq(bubbles.size(),2,"%s two companion speeches"%viewport_size)
		for bubble in bubbles:
			var card:=_button(sandbox,"MemberCard%d"%int(bubble.actor_id))
			var strip:=card.find_child("CompanionSpeechStrip",true,false) as PanelContainer
			var text:=card.find_child("CompanionSpeechText",true,false) as Label
			check(strip!=null and text!=null,"%s companion owns its card speech"%viewport_size)
			if strip==null or text==null:continue
			check("\n" not in text.text and text.max_lines_visible==1,
				"%s card speech is exactly one compact line"%viewport_size)
			check_eq(text.text,"%s · %s"%[str(bubble.headline),str(bubble.reason_summary)],
				"%s card binds only its own headline and reason"%viewport_size)
			check(str(bubble.headline) in ["공격할게.","이동할게.","방어할게."],
				"%s fixed headline vocabulary"%viewport_size)
			check(str(bubble.reason_summary).length()<=14,"%s compact reason stays on one line"%viewport_size)
			check_eq(str(strip.get_meta("full_reason","")),str(bubble.reason),
				"%s full Korean reason remains available off-strip"%viewport_size)
			check(text.get_theme_font_size("font_size")==11,
				"%s compact speech uses micro type"%viewport_size)
			check(strip.mouse_filter==Control.MOUSE_FILTER_IGNORE \
				and text.mouse_filter==Control.MOUSE_FILTER_IGNORE,
				"%s speech cannot intercept dossier-card input"%viewport_size)
		var companion:=int(bubbles[0].actor_id)
		check(sandbox.session.override_companion(companion,Action.hold(companion)).accepted,
			"%s companion override accepted"%viewport_size);sandbox._refresh()
		var overridden:=_button(sandbox,"MemberCard%d"%companion).find_child(
			"CompanionSpeechText",true,false) as Label
		check_eq(overridden.text,"방어할게. · 지시를 따라서",
			"%s override refreshes the same card strip"%viewport_size)
		check_eq(sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).size(),2,
			"%s secondary suggestion creates no extra strip"%viewport_size)
		check(sandbox.session.clear_companion_override(companion).accepted,
			"%s companion override clears"%viewport_size);sandbox._refresh()
		var cleared:=_button(sandbox,"MemberCard%d"%companion).find_child(
			"CompanionSpeechText",true,false) as Label
		check(cleared.text!="방어할게. · 지시를 따라서",
			"%s clear restores automatic card speech"%viewport_size)
		check(sandbox.session.replace_auto_combat_protagonist_action(Action.hold(hero)).accepted,
			"%s hero finalizes plan"%viewport_size)
		check(sandbox.session.commit_turn().accepted,"%s plan commits"%viewport_size);sandbox._refresh()
		check(sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).is_empty(),
			"%s no stale strip survives between plans"%viewport_size)
		if sandbox.session.party_status().safe_phase=="ENGAGED":
			check(sandbox.session.prepare_auto_combat_plan().active,
				"%s next plan prepares"%viewport_size);sandbox._refresh()
			check_eq(sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).size(),2,
				"%s next turn immediately refreshes both cards"%viewport_size)
		sandbox.free()
	var exploration=Sandbox.new();exploration.size=Vector2(360,640)
	exploration.initialize_for_headless_test(Session.new())
	check(exploration.find_children("CompanionSpeechStrip","PanelContainer",true,false).is_empty(),
		"exploration hides companion speech")
	var hero:=int(exploration.session.party_status().protagonist_id)
	check(exploration.session.commit_exploration(Command.wait(hero)).accepted,"contact fixture")
	exploration._refresh()
	check(exploration.find_children("CompanionSpeechStrip","PanelContainer",true,false).is_empty(),
		"contact hides companion speech")
	exploration.free();return finish()

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
	var overridden:Dictionary
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check(overridden.expected_action is Dictionary and overridden.expected_action.source=="OVERRIDE",
		"one companion tile tap creates move override")
	check(sandbox.pending_move_mode!="COMBAT" and sandbox.find_child("MovePreviewSummary",true,false)==null,
		"companion override has no combat retap state")
	check("덮어쓰기" in str(overridden.expected_action.text),"override Korean label")
	check(overridden.expected_action.automatic_suggestion is Dictionary,"override preserves original automatic suggestion")
	var party_intents:Array=sandbox.grid._intent_overlays.filter(func(row):
		return str(row.get("source",""))!="ENEMY_FORECAST")
	check_eq(party_intents.size(),3,"hero and companion intents overlaid alongside enemy forecast")
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


func test_combat_defense_attack_preview_is_readable_without_enemy_forecast_leak() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var sandbox=_engaged_sandbox("LINE",viewport_size)
		var status:Dictionary=sandbox.session.party_status();var hero:=int(status.protagonist_id)
		var enemy:=int(status.visible_enemy_ids[0])
		check(_relocate_with_move_events(sandbox.session.sim,enemy,
			sandbox.session.sim.world.entities[hero].position+Vector2i.RIGHT),
			"%s enemy intent fixture adjacent"%viewport_size)
		sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
		var hold:=_button(sandbox,"ActorHold")
		check(hold!=null and "방어" in hold.text and hold.custom_minimum_size.y>=44.0,
			"%s defense is a named 44px action"%viewport_size)
		check(hold!=null and "25%" in hold.tooltip_text and "200 시간" in hold.tooltip_text,
			"%s defense tooltip exposes effect and duration"%viewport_size)
		var enemy_summary:=sandbox.find_child("EnemyIntentSummary",true,false) as Label
		check(enemy_summary==null,"%s product UI has no enemy forecast summary"%viewport_size)
		var enemy_overlay:Dictionary={}
		for overlay in sandbox.grid._intent_overlays:
			if str(overlay.get("source",""))=="ENEMY_FORECAST":enemy_overlay=overlay;break
		check(enemy_overlay.is_empty(),
			"%s product grid omits enemy destination and target overlays"%viewport_size)
		var hero_hit:Rect2=sandbox.grid.actor_hit_rect(hero)
		check_eq(sandbox.grid.actor_at_pointer(hero_hit.get_center()),hero,
			"%s presentation overlays do not intercept actor hit testing"%viewport_size)
		sandbox._on_actor(enemy);sandbox._refresh()
		var summary:=sandbox.find_child("TurnSummary",true,false) as Label
		check(summary!=null and "명중 95%" in summary.text and "적중 시 22 피해" in summary.text,
			"%s target selection exposes hit chance and on-hit damage"%viewport_size)
		var refreshed_hold:=_button(sandbox,"ActorHold")
		check(sandbox.combat_action_dock.visible and refreshed_hold!=null,
			"%s combat controls remain present after target selection"%viewport_size)
		sandbox.free()
	return finish()


func test_solo_combat_mobile_hides_party_management_and_enters_without_formation() -> bool:
	var manual_session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	check(manual_session.commit_exploration_direction(Vector2i.RIGHT).accepted,
		"solo manual fixture reaches contact")
	check_eq(manual_session.party_status().safe_phase,"CONTACT","solo manual contact")
	var manual=Sandbox.new();manual.size=Vector2(360,640)
	manual.initialize_for_headless_test(manual_session,false)
	var start:Button=_button(manual,"SoloCombatStart")
	check(start!=null and start.custom_minimum_size.y>=44.0,
		"manual solo contact has a 44px retry/start path")
	check(manual.find_child("FormationControls",true,false)==null \
		and manual.find_child("PresetWEDGE",true,false)==null \
		and manual.grid._ghosts.is_empty(),"manual solo contact never exposes formations or ghosts")
	_press(manual,"SoloCombatStart")
	check_eq(manual.session.party_status().safe_phase,"ENGAGED","manual solo start enters combat")
	manual.free()

	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
		check(session.commit_exploration_direction(Vector2i.RIGHT).accepted,
			"%s solo auto fixture reaches contact"%viewport_size)
		var sandbox=Sandbox.new();sandbox.size=viewport_size
		sandbox.initialize_for_headless_test(session,true)
		# An unattached Control resets to its minimum size while the headless UI is built.
		# Restore the simulated viewport before checking the responsive spotlight layout.
		sandbox.size=viewport_size;sandbox._refresh()
		check_eq(session.party_status().safe_phase,"ENGAGED",
			"%s CONTACT converges to ENGAGED in initial refresh"%viewport_size)
		var deployed_step:int=int(session.sim.world.step_index)
		var deployed_journal:int=session.command_journal.size()
		sandbox._refresh();sandbox._refresh()
		check_eq([session.sim.world.step_index,session.command_journal.size()],
			[deployed_step,deployed_journal],"%s repeated refresh deploys exactly once"%viewport_size)
		check(session.is_solo_combat() and session.party_cards().size()==1,
			"%s solo fixture has one authoritative member dossier"%viewport_size)
		check(not sandbox.duel_lab_button.visible \
			and sandbox.find_child("RosterManagement",true,false)==null \
			and sandbox.find_child("RosterManagementTitle",true,false)==null,
			"%s solo hides LAB rescue recruit exile management"%viewport_size)
		check(sandbox.find_child("FormationControls",true,false)==null \
			and sandbox.find_child("DeployConfirm",true,false)==null \
			and sandbox.grid._ghosts.is_empty(),
			"%s solo combat has no formation controls or ghost"%viewport_size)
		check(sandbox.find_children("CompanionSpeechStrip","PanelContainer",true,false).is_empty(),
			"%s solo has no companion speech"%viewport_size)
		var hero:=int(session.party_status().protagonist_id)
		var card:Button=_button(sandbox,"MemberCard%d"%hero)
		var hp:=card.find_child("MemberState",true,false) as Label
		var emotion:=card.find_child("EmotionState",true,false) as Label
		check(card.custom_minimum_size.x>=viewport_size.x-12.0 \
			and card.find_child("Portrait",true,false)==null \
			and card.find_child("SoloIdentity",true,false)!=null,
			"%s solo dossier gives its horizontal width to identity and gauges"%viewport_size)
		check(hp.get_theme_font_size("font_size")==14 \
			and emotion.get_theme_font_size("font_size")==14,
			"%s solo HP and state use compact auxiliary type"%viewport_size)
		var hold:Button=_button(sandbox,"ActorHold")
		check(hold!=null and hold.custom_minimum_size.y>=44.0 \
			and "방어" in hold.text and "25%" in sandbox.action_feedback_label.text,
			"%s solo defense is visible and explained"%viewport_size)
		var enemy_summary:=sandbox.find_child("EnemyIntentSummary",true,false) as Label
		check(enemy_summary==null,
			"%s solo fixture does not reveal enemy target or direction"%viewport_size)
		var enemy:=int(session.party_status().visible_enemy_ids[0])
		var hero_position:Vector2i=session.sim.world.entities[hero].position
		var enemy_position:Vector2i=session.sim.world.entities[enemy].position
		var opening_distance:=maxi(absi(hero_position.x-enemy_position.x),
			absi(hero_position.y-enemy_position.y))
		check(opening_distance>=2 and opening_distance<=4,
			"%s deterministic nearby enemy still requires an approach"%viewport_size)
		var before_tap_step:=int(session.party_status().step_index)
		sandbox._on_actor(enemy)
		check(int(session.party_status().step_index)==before_tap_step \
			and not bool(sandbox.auto_flow_state().get("combat_pending",false)),
			"%s distant enemy tap cannot fabricate a melee turn or plan"%viewport_size)
		check(sandbox.grid._intent_overlays.is_empty() and sandbox.grid._route_path.is_empty() \
			and sandbox.grid.cursor_cell==Vector2i(-1,-1),
			"%s rejected distant tap leaves no intent, route, or cursor marks"%viewport_size)
		sandbox.free()
	return finish()


func test_pixel_product_hud_bottom_navigation_modals_and_map_are_fog_safe() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
		var sandbox=Sandbox.new();sandbox.size=viewport_size
		sandbox.initialize_for_headless_test(session,false)
		check(not sandbox.phase_panel.visible and not sandbox.top_hud_actions.visible \
			and not sandbox.ascii_3d_lab_button.visible,
			"%s obsolete product top rail and 3D entry are unreachable"%viewport_size)
		check(sandbox.cards.visible and sandbox.grid.visible and sandbox.event_surface.visible \
			and sandbox.bottom_navigation.visible and not sandbox.info_scroll.visible,
			"%s product surfaces replace the duplicate context stack"%viewport_size)
		check_eq(int(sandbox.cards.custom_minimum_size.y),68,
			"%s solo status strip uses the 68px budget"%viewport_size)
		for contract in [[sandbox.map_nav_button,"[지도]"],[sandbox.person_nav_button,"[인물]"],
				[sandbox.skill_nav_button,"[숙련]"],[sandbox.equipment_nav_button,"[장비]"],
				[sandbox.history_nav_button,"[기록]"]]:
			var button:Button=contract[0]
			check(button.text==str(contract[1]) and button.custom_minimum_size.y>=44.0,
				"%s bottom navigation keeps honest 44px actions"%viewport_size)
		var event_before:String=sandbox.event_label.text
		sandbox.map_nav_button.pressed.emit()
		var hero_position:Array=session.party_status().protagonist_position
		var hero_spec:Dictionary=sandbox.map_overlay.cell_draw_spec(
			Vector2i(int(hero_position[0]),int(hero_position[1])))
		var source_minimap:Dictionary=session.observe_party_ui(15).get("minimap",{})
		var overlay_layout:Dictionary=sandbox.map_overlay.layout_spec(viewport_size)
		var overlay_contract:Dictionary=sandbox.map_overlay.overlay_spec()
		check(sandbox.map_overlay.visible and sandbox.map_nav_button.button_pressed \
			and sandbox.grid.modal_open and str(hero_spec.role)=="HERO",
			"%s first map open seeds the current observation before opening"%viewport_size)
		check_eq([int(overlay_layout.world_width),int(overlay_layout.world_height)],
			[int(source_minimap.get("width",0)),int(source_minimap.get("height",0))],
			"%s map folio dimensions exactly match the source minimap DTO"%viewport_size)
		check(bool(overlay_contract.uses_world_coordinates) \
			and not bool(overlay_contract.uses_sector_folding),
			"%s map folio preserves full absolute coordinates without sector folding"%viewport_size)
		check(bool(overlay_contract.stores_compact_scalars_only) \
			and not bool(overlay_contract.leaks_hazard) and not bool(overlay_contract.leaks_target) \
			and not bool(overlay_contract.leaks_direction),
			"%s full map keeps fog-safe compact scalar authority"%viewport_size)
		sandbox.map_nav_button.pressed.emit()
		check(not sandbox.map_overlay.visible and not sandbox.map_nav_button.button_pressed,
			"%s map toggle closes and synchronizes its navigation state"%viewport_size)
		sandbox.history_nav_button.pressed.emit()
		check(sandbox.record_modal.visible and sandbox.history_nav_button.button_pressed \
			and not sandbox.record_body.text.is_empty() and sandbox.event_label.text==event_before,
			"%s record opens full history without replacing compact events"%viewport_size)
		sandbox.history_nav_button.pressed.emit()
		sandbox.person_nav_button.pressed.emit()
		check(sandbox.member_detail_modal.visible and sandbox.member_detail_current_tab=="STATUS",
			"%s person navigation opens hero STATUS directly"%viewport_size)
		sandbox._close_member_detail();sandbox.skill_nav_button.pressed.emit()
		check(sandbox.member_detail_current_tab=="SKILL",
			"%s skill navigation opens hero SKILL directly"%viewport_size)
		sandbox._close_member_detail();sandbox.equipment_nav_button.pressed.emit()
		check(sandbox.member_detail_current_tab=="ITEM",
			"%s equipment navigation opens hero ITEM directly"%viewport_size)
		sandbox.free()
	return finish()


func test_solo_camera_stays_hero_centered_continuous_and_padding_is_void() -> bool:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
		var sandbox=Sandbox.new();sandbox.size=viewport_size
		sandbox.initialize_for_headless_test(session,false)
		sandbox.size=viewport_size;sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
		var grid_id:int=sandbox.grid.get_instance_id()
		var initial_cell:float=sandbox.grid.cell_size_px()
		_assert_hero_centered(sandbox,"%s initial edge"%viewport_size)
		var padding_position:Vector2i=sandbox.grid.view_origin
		var padding:Dictionary=sandbox.grid.void_padding_draw_spec(padding_position)
		var padding_rect:Rect2=padding.rect
		check(bool(padding.visible) and str(padding.color_hex)=="#010203" \
			and not bool(padding.accepts_input),"%s edge padding is explicit void"%viewport_size)
		check_eq(sandbox.grid.pixel_to_world_cell(padding_rect.get_center()),
			Vector2i(-1,-1),"%s padding pixel rejects world mapping"%viewport_size)
		var routed:Array=[];sandbox.grid.world_cell_pressed.connect(func(position):routed.append(position))
		_grid_screen_touch(sandbox.grid,padding_rect.get_center())
		check(routed.is_empty(),"%s padding touch emits no action"%viewport_size)
		var snapshot_before:Dictionary=session.sim.snapshot()
		var journal_before:Array=session.command_journal.duplicate(true)
		sandbox._refresh();_assert_hero_centered(sandbox,"%s pure refresh"%viewport_size)
		check_eq([session.sim.snapshot(),session.command_journal],
			[snapshot_before,journal_before],"%s camera refresh is presentation-only"%viewport_size)

		check(session.commit_exploration_direction(Vector2i.RIGHT).accepted,
			"%s hero move reaches contact"%viewport_size)
		var moved_snapshot:Dictionary=session.sim.snapshot()
		var moved_journal:Array=session.command_journal.duplicate(true)
		sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
		_assert_hero_centered(sandbox,"%s after move"%viewport_size)
		check_eq([session.sim.snapshot(),session.command_journal],[moved_snapshot,moved_journal],
			"%s camera settle is presentation-only"%viewport_size)
		check_eq(sandbox.grid.get_instance_id(),grid_id,"%s move keeps grid instance"%viewport_size)
		check(absf(sandbox.grid.cell_size_px()-initial_cell)<0.001,
			"%s move keeps cell scale"%viewport_size)
		var contact_mapping:Array=sandbox.grid.mapping_signature()
		check(session.enter_solo_combat().accepted,"%s enters solo combat"%viewport_size)
		sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
		_assert_hero_centered(sandbox,"%s combat"%viewport_size)
		check_eq(sandbox.grid.mapping_signature(),contact_mapping,
			"%s combat entry does not recenter or zoom the map"%viewport_size)
		check(not sandbox.grid.combat_emphasis and sandbox.grid._neutral_phase_map \
			and not bool(sandbox.grid._presentation_style.get("vignette",true)),
			"%s combat map stays visually neutral"%viewport_size)
		check(absf(sandbox.grid.cell_size_px()-initial_cell)<0.001,
			"%s combat keeps exploration cell scale"%viewport_size)

		var status:Dictionary=session.party_status();var hero:=int(status.protagonist_id)
		var enemy:=int(status.visible_enemy_ids[0])
		check(_relocate_with_move_events(session.sim,enemy,
			session.sim.world.entities[hero].position+Vector2i.RIGHT),
			"%s adjacent enemy fixture"%viewport_size)
		session.sim.world.entities[enemy].health=22
		sandbox._refresh();var before_hit_origin:Vector2i=sandbox.grid.view_origin
		for _attempt in range(4):
			if session.party_status().safe_phase!="ENGAGED":break
			check(session.set_actor_action(hero,"MELEE",[],enemy).accepted,
				"%s melee preview"%viewport_size)
			check(session.commit_turn().accepted,"%s melee commit"%viewport_size)
		sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
		check_eq(session.party_status().safe_phase,"GROUPED_COMPLETE",
			"%s fixture reaches victory"%viewport_size)
		_assert_hero_centered(sandbox,"%s victory"%viewport_size)
		check_eq(sandbox.grid.view_origin,before_hit_origin,
			"%s enemy hit and victory never steal camera focus"%viewport_size)
		check_eq(sandbox.grid.get_instance_id(),grid_id,"%s victory keeps same grid"%viewport_size)
		check(absf(sandbox.grid.cell_size_px()-initial_cell)<0.001,
			"%s victory keeps continuous cell scale"%viewport_size)
		sandbox.free()
	return finish()

func test_same_grid_survives_combat_regroup_complete_and_post_regroup_move() -> bool:
	var sandbox=Sandbox.new();sandbox.size=Vector2(450,800);sandbox.initialize_for_headless_test(Session.new())
	sandbox.grid.size=sandbox.grid.custom_minimum_size
	var grid_id=sandbox.grid.get_instance_id();var exploration_mapping=sandbox.grid.mapping_signature()
	_explore_wait(sandbox);_press(sandbox,"PresetLINE");_press(sandbox,"DeployConfirm");sandbox.grid.size=sandbox.grid.custom_minimum_size
	check_eq(sandbox.grid.visible_cell_count,15,"combat keeps full 15x15 view")
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
	for kind in ["FLOATING_AMOUNT","DEATH"]:check(kind in effect_kinds,"combat commit renders %s effect"%kind)
	check(sandbox.grid.melee_vfx!=null and sandbox.grid.melee_vfx.active_effect_count()==1,
		"committed melee hit routes once to the separate line overlay")
	check("SLASH" not in effect_kinds,
		"melee commit leaves no inline slash row; secondary damage may keep particles")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives combat")
	check_eq(sandbox.grid.visible_cell_count,15,"victory immediately restores full 15x15 view")
	check_eq(sandbox.grid.view_origin,Vector2i.ZERO,"victory clears combat camera origin")
	check_eq(sandbox.grid.mapping_signature(),exploration_mapping,"zoom-out restores exact exploration mapping")
	check(_button(sandbox,"RegroupConfirm")==null,"manual regroup control removed")
	check("자동으로 재집결" in sandbox.notice_text,"completion notice is explicit")
	check_eq(sandbox.phase_label.text,"승리","victory situation is explicit")
	check(not sandbox.combat_action_dock.is_visible_in_tree(),"combat dock hides after victory")
	check(sandbox.grid._intent_overlays.is_empty(),"phase transition clears stale action overlays")
	check_eq(sandbox.session.party_status().contact_kind,"NONE","stale contact cleared")
	check_eq(sandbox.session.party_status().formation_id,"NONE","stale formation cleared")
	var old_anchor:Array=sandbox.session.party_status().anchor
	var left:=Vector2i(int(old_anchor[0])-1,int(old_anchor[1])); sandbox._on_cell(left); sandbox._refresh()
	check(sandbox.session.party_status().anchor!=old_anchor,"post-regroup UI move")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives regroup move")
	check_eq(sandbox.grid.mapping_signature(),exploration_mapping,"post-regroup full mapping remains restored")
	sandbox.free(); return finish()

func test_restored_grouped_complete_keeps_victory_banner_style_without_effect_replay() -> bool:
	var source_session=Session.new();check(_play_full_journey(source_session,"LINE"),"restored victory canonical journey")
	check_eq(source_session.party_status().safe_phase,"GROUPED_COMPLETE","restored victory source phase")
	var direct=Sandbox.new();direct.size=Vector2(360,640);direct.initialize_for_headless_test(source_session);direct.grid.size=direct.grid.custom_minimum_size
	check(direct.notice_text.is_empty(),"direct fresh completed sandbox has no transient victory notice")
	check_eq(direct.phase_label.text,"승리","direct fresh completed sandbox renders persistent victory")
	check_eq(direct.grid._presentation_style.style_id,"VICTORY","direct fresh completed sandbox consumes victory style")
	check(direct.grid._active_visual_effects.is_empty(),"direct fresh completed sandbox does not replay effects")
	var encoded:=source_session.save_session_json();var restored=Session.new(1,2)
	check(bool(restored.load_session_json(encoded).accepted),"restored victory session load")
	var fresh=Sandbox.new();fresh.size=Vector2(360,640);fresh.initialize_for_headless_test(restored);fresh.grid.size=fresh.grid.custom_minimum_size
	check(fresh.notice_text.is_empty(),"fresh restored sandbox has no transient victory notice")
	check_eq(fresh.phase_label.text,"승리","fresh restored sandbox renders persistent victory title")
	check_eq(fresh.session.presentation_state().banner.tone,"VICTORY","fresh restored victory tone")
	check_eq(fresh.grid._presentation_style.style_id,"VICTORY","fresh restored victory grid style")
	check_eq(fresh.grid._presentation_style.border_hex,"#62d98b","fresh restored victory green grid border")
	var panel_style:=fresh.phase_panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(panel_style!=null and panel_style.get_border_width(SIDE_LEFT)==0 \
		and panel_style.get_border_width(SIDE_TOP)==0 \
		and panel_style.get_border_width(SIDE_RIGHT)==0 \
		and panel_style.get_border_width(SIDE_BOTTOM)==1 \
		and panel_style.border_color==Color("#4f9aa3"),
		"fresh restored banner keeps only the oxidized-cyan bottom rail")
	check(fresh.minimap_frame!=null and fresh.minimap_frame.frame_color==Color("#5f8a66") \
		and str(fresh.minimap_frame.get_meta("state_tone",""))=="VICTORY" \
		and str(fresh.minimap_frame.frame_spec().primitive)=="FIXED_CELL_GLYPHS",
		"fresh restored victory consumes jade through the glyph-backed HUD frame")
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
	check_eq(sandbox.phase_label.text,"위험","terminal danger situation")
	check_eq(sandbox.grid._presentation_style.style_id,"DEFEAT","terminal grid presentation style")
	check_eq(sandbox.grid._presentation_style.border_hex,"#8f5367","terminal grid presentation border")
	var terminal_panel:=sandbox.phase_panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(terminal_panel!=null and terminal_panel.get_border_width(SIDE_LEFT)==0 \
		and terminal_panel.get_border_width(SIDE_TOP)==0 \
		and terminal_panel.get_border_width(SIDE_RIGHT)==0 \
		and terminal_panel.get_border_width(SIDE_BOTTOM)==1 \
		and terminal_panel.border_color==Color("#4f9aa3"),
		"terminal panel keeps only the oxidized-cyan bottom rail")
	check(sandbox.minimap_frame!=null and sandbox.minimap_frame.frame_color==Color("#a74343") \
		and sandbox.minimap_frame.danger_edge \
		and str(sandbox.minimap_frame.get_meta("state_tone",""))=="DEFEAT" \
		and str(sandbox.minimap_frame.frame_spec().primitive)=="FIXED_CELL_GLYPHS",
		"terminal defeat consumes vermilion through the glyph-backed HUD frame")
	var grid_source:=FileAccess.get_file_as_string("res://playtest/party_grid_view.gd")
	check("CHARACTER_ATLAS" not in grid_source,
		"product party grid has no stale character texture/atlas path")
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
	_grid_screen_touch(sandbox.grid,sandbox.grid.world_to_pixel_center(position))

func _grid_screen_touch(grid,position:Vector2,touch_index:int=0)->void:
	var event:=InputEventScreenTouch.new();event.index=touch_index;event.pressed=true;event.position=position
	grid._gui_input(event)
	var release:=InputEventScreenTouch.new();release.index=touch_index;release.pressed=false;release.position=position
	grid._gui_input(release)

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

func _assert_hero_centered(sandbox,label:String)->void:
	var status:Dictionary=sandbox.session.party_status();var hero:=int(status.protagonist_id)
	var hero_position:Vector2i=sandbox.session.sim.world.entities[hero].position
	check_eq(sandbox.grid.view_origin,hero_position-Vector2i(7,7),
		"%s origin follows hero-(7,7)"%label)
	check(sandbox.grid.world_to_pixel_center(hero_position).distance_to(
		sandbox.grid.grid_rect().get_center())<0.01,"%s hero is pixel-centered"%label)
	check_eq(sandbox.grid.pixel_to_world_cell(sandbox.grid.grid_rect().get_center()),
		hero_position,"%s center pixel round-trips to hero"%label)
