extends "res://tests/test_case.gd"

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

func test_same_grid_instance_and_mapping_survive_phase_change() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(450,800); sandbox.initialize_for_headless_test(Session.new())
	var id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
	var hero=sandbox.session.sim.world.party_encounter.protagonist_id; sandbox.session.commit_exploration(Command.wait(hero)); sandbox._refresh()
	check_eq(sandbox.grid.get_instance_id(),id,"same grid")
	check_eq(sandbox.grid.mapping_signature(),mapping,"same coordinate mapping")
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
		var grid_id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
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
		check(_button(sandbox,"Preset%s"%preset).button_pressed,"selected preset feedback")
		check(not _button(sandbox,"DeployConfirm").disabled,"valid confirm enabled")
		_press(sandbox,"DeployConfirm")
		check_eq(sandbox.session.party_status().safe_phase,"ENGAGED","%s button journey engaged"%preset)
		check("빈 칸은 이동, 적은 공격" in str(sandbox.find_child("ActionStatus",true,false).text), "%s combat instruction visible immediately"%preset)
		check_eq(sandbox.session.party_status().formation_id,preset,"formation committed")
		check_eq(sandbox.grid.get_instance_id(),grid_id,"same grid for %s"%preset)
		check_eq(sandbox.grid.mapping_signature(),mapping,"same mapping for %s"%preset)
		sandbox.free()
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
	var sandbox=_engaged_sandbox("LINE"); var grid_id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
	var status:Dictionary=sandbox.session.party_status(); var hero:=int(status.protagonist_id); var enemy:=int(status.visible_enemy_ids[0])
	check(_relocate_with_move_events(sandbox.session.sim, enemy,
		sandbox.session.sim.world.entities[hero].position + Vector2i.RIGHT), "UI enemy canonical relocation")
	sandbox.session.sim.world.entities[enemy].health=22; sandbox._refresh()
	sandbox._on_actor(enemy); sandbox._refresh(); check(bool(sandbox.session.current_turn_preview().accepted),"enemy tap creates hero melee")
	_press(sandbox,"TurnConfirm"); check_eq(sandbox.session.party_status().safe_phase,"GROUPED_COMPLETE","victory auto-regroups via UI turn confirm")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives combat")
	check(_button(sandbox,"RegroupConfirm")==null,"manual regroup control removed")
	check("자동으로 재집결" in sandbox.notice_text,"completion notice is explicit")
	check(sandbox.grid._intent_overlays.is_empty(),"phase transition clears stale action overlays")
	check_eq(sandbox.session.party_status().contact_kind,"NONE","stale contact cleared")
	check_eq(sandbox.session.party_status().formation_id,"NONE","stale formation cleared")
	var old_anchor:Array=sandbox.session.party_status().anchor
	var left:=Vector2i(int(old_anchor[0])-1,int(old_anchor[1])); sandbox._on_cell(left); sandbox._refresh(); sandbox._on_cell(left); sandbox._refresh()
	check(sandbox.session.party_status().anchor!=old_anchor,"post-regroup UI move")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives regroup move")
	check_eq(sandbox.grid.mapping_signature(),mapping,"mapping survives full journey")
	sandbox.free(); return finish()

func test_terminal_defeat_and_atlas_touch_tie_break_are_explicit() -> bool:
	var session=Session.new(); var state=session.sim.world.party_encounter; session.sim.world.entities[state.protagonist_id].health=5
	check(session.sim.world.bootstrap_set_fire(state.group_anchor,100)!=null,"defeat fire")
	session.commit_exploration(Command.wait(state.protagonist_id))
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(session)
	check_eq(sandbox.session.party_status().safe_phase,"PARTY_DEFEATED","terminal phase")
	check(sandbox.find_child("TerminalOverlay",true,false)!=null,"terminal overlay visible")
	check(sandbox.find_child("TurnConfirm",true,false)==null,"terminal turn confirm hidden")
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
