extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

var failures:Array[String]=[]

func _init()->void: call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(450,800),Vector2(360,640)]:
		root.size=Vector2i(int(viewport_size.x),int(viewport_size.y));await process_frame
		for preset in ["WEDGE","LINE","COLUMN"]:
			await _journey(viewport_size,preset)
		await _wide_camera_fallback(viewport_size)
		await _terminal(viewport_size)
	await _validate_authoritative_rejection_layouts_360()
	for failure in failures: printerr("FAIL "+failure)
	print("---- party UI layout smoke: %d journeys + %d wide fallbacks, %d failed ----"%[6,2,failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _journey(viewport_size:Vector2,preset:String)->void:
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(Session.new())
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); sandbox.size=viewport_size; root.add_child(sandbox)
	await process_frame; await process_frame
	var grid_id=sandbox.grid.get_instance_id(); var exploration_mapping=sandbox.grid.mapping_signature()
	_validate_layout(sandbox,"%s %s EXPLORATION"%[viewport_size,preset])
	var initial_actors:=0; for cell in sandbox.session.observe_party_world().cells: initial_actors+=cell.actors.size()
	if initial_actors!=1: failures.append("%s %s pre-contact actor visibility"%[viewport_size,preset])
	for button_name in ["ExploreN","ExploreNE","ExploreE","ExploreSE","ExploreS","ExploreSW","ExploreW","ExploreNW","ExploreHold"]:
		if _button(sandbox,button_name)!=null: failures.append("%s %s legacy D-pad remains %s"%[viewport_size,preset,button_name])
	await _explore_wait(sandbox)
	_validate_layout(sandbox,"%s %s CONTACT"%[viewport_size,preset])
	if sandbox.grid.mapping_signature()!=exploration_mapping: failures.append("%s %s contact changed full-view mapping"%[viewport_size,preset])
	var contact_actors:=0; for cell in sandbox.session.observe_party_world().cells: contact_actors+=cell.actors.size()
	if contact_actors!=2: failures.append("%s %s contact enemy reveal"%[viewport_size,preset])
	if not _button(sandbox,"DeployConfirm").disabled: failures.append("%s %s pre-preset confirm enabled"%[viewport_size,preset])
	sandbox._on_deploy_confirm(); await process_frame
	if not "먼저" in str(sandbox.find_child("ActionStatus",true,false).text): failures.append("%s %s rejected confirm invisible"%[viewport_size,preset])
	for preview_preset in ["WEDGE","LINE","COLUMN"]:
		await _press(sandbox,"Preset%s"%preview_preset)
		_validate_layout(sandbox,"%s %s PREVIEW_%s"%[viewport_size,preset,preview_preset])
		if sandbox.grid._ghosts.size()!=2: failures.append("%s %s %s ghost count"%[viewport_size,preset,preview_preset])
		for ghost in sandbox.grid._ghosts:
			var ghost_position:=Vector2i(int(ghost.position[0]),int(ghost.position[1]))
			if not sandbox.grid.is_world_cell_visible(ghost_position):failures.append("%s %s %s ghost outside deployment preview"%[viewport_size,preset,preview_preset])
	await _press(sandbox,"Preset%s"%preset)
	await _press(sandbox,"DeployConfirm")
	if sandbox.session.party_status().safe_phase!="ENGAGED": failures.append("%s %s did not engage"%[viewport_size,preset])
	if sandbox.grid.get_instance_id()!=grid_id:failures.append("%s %s grid replaced on combat zoom"%[viewport_size,preset])
	if sandbox.grid.mapping_signature()==exploration_mapping:failures.append("%s %s combat crop did not change mapping"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_HERO_PENDING"%[viewport_size,preset])
	await _validate_fixed_combat_area(sandbox,"%s %s"%[viewport_size,preset])
	_validate_camera_mapping(sandbox,"%s %s"%[viewport_size,preset])
	var status:Dictionary=sandbox.session.party_status();var hero:=int(status.protagonist_id);var companion:=int(status.party_member_ids[1])
	var draft_required:Dictionary=sandbox.session.preview_actor_action(companion,"HOLD");var draft_snapshot=sandbox.session.sim.snapshot()
	await _press(sandbox,"MemberCard%d"%companion);await _press(sandbox,"ActorHold")
	await _validate_fixed_feedback(sandbox,str(draft_required.message),"%s %s DRAFT_REQUIRED"%[viewport_size,preset])
	if sandbox.session.sim.snapshot()!=draft_snapshot:failures.append("%s %s draft-required button changed world"%[viewport_size,preset])
	await _press(sandbox,"MemberCard%d"%hero)
	await _press(sandbox,"ActorHold")
	if str(draft_required.message) in sandbox.action_feedback_label.text or not "턴 확정" in sandbox.action_feedback_label.text:
		failures.append("%s %s accepted action did not replace stale rejection feedback"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_HERO_DIRECT"%[viewport_size,preset])
	await _press(sandbox,"MemberCard%d"%companion)
	var companion_position:=Vector2i.ZERO
	for row in sandbox.session.party_cards():
		if int(row.entity_id)==companion: companion_position=Vector2i(int(row.logical_position[0]),int(row.logical_position[1])); break
	var far_preview:Dictionary={};var far_destination:=Vector2i(-1,-1)
	for offset in [Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-3),Vector2i(3,3),Vector2i(-3,-3)]:
		var candidate:Vector2i=companion_position+offset
		if not sandbox.grid.is_world_cell_visible(candidate) or sandbox.grid.actor_in_world_cell(candidate)!=-1:continue
		var candidate_preview:Dictionary=sandbox.session.preview_actor_action(companion,"MOVE",[candidate.x,candidate.y])
		if str(candidate_preview.get("reason_code",""))=="move_not_adjacent":far_destination=candidate;far_preview=candidate_preview;break
	if far_destination==Vector2i(-1,-1):failures.append("%s %s no visible nonadjacent companion fixture"%[viewport_size,preset])
	else:
		var far_snapshot=sandbox.session.sim.snapshot();await _touch_cell(sandbox,far_destination)
		await _validate_fixed_feedback(sandbox,str(far_preview.message),"%s %s NONADJACENT"%[viewport_size,preset])
		if sandbox.session.sim.snapshot()!=far_snapshot:failures.append("%s %s nonadjacent ScreenTouch changed world"%[viewport_size,preset])
	for direction in [Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,-1),Vector2i(-1,1)]:
		var destination:Vector2i=companion_position+direction
		if not sandbox.session.sim.assess_move(companion,destination).accepted \
				or sandbox.grid.actor_in_world_cell(destination)!=-1: continue
		await _press(sandbox,"MemberCard%d"%companion)
		await _touch_cell(sandbox,destination)
		if sandbox.find_child("MovePreviewSummary",true,false)==null: failures.append("%s %s move preview summary missing"%[viewport_size,preset])
		await _touch_cell(sandbox,destination)
		var found_override:=false
		for row in sandbox.session.party_cards():
			if int(row.entity_id)==companion and row.expected_action is Dictionary and str(row.expected_action.source)=="OVERRIDE": found_override=true
		if found_override: break
	_validate_layout(sandbox,"%s %s COMBAT_COMPANION_OVERRIDE"%[viewport_size,preset])
	var override_visible:=false
	for row in sandbox.session.party_cards():
		if int(row.entity_id)==companion and row.expected_action is Dictionary and str(row.expected_action.source)=="OVERRIDE": override_visible=true
	if not override_visible: failures.append("%s %s companion override not visible"%[viewport_size,preset])
	if sandbox.grid._secondary_intent_overlays.size()!=1: failures.append("%s %s original suggestion secondary overlay missing"%[viewport_size,preset])
	var summary=sandbox.find_child("TurnSummary",true,false) as Label
	var detail=sandbox.find_child("ExpectedAction",true,false) as Label
	if summary==null or not "원래 제안" in summary.text: failures.append("%s %s original suggestion absent from turn summary"%[viewport_size,preset])
	if detail==null or not "개별 지시:" in detail.text or not "원래 제안:" in detail.text: failures.append("%s %s override/original detail absent"%[viewport_size,preset])
	if sandbox.find_child("IntentLegend",true,false)==null: failures.append("%s %s intent legend missing"%[viewport_size,preset])
	await _press(sandbox,"OverrideClear")
	if not sandbox.grid._secondary_intent_overlays.is_empty(): failures.append("%s %s clear left secondary overlay"%[viewport_size,preset])
	summary=sandbox.find_child("TurnSummary",true,false) as Label
	if summary!=null and "원래 제안" in summary.text: failures.append("%s %s clear left dual summary"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_COMPANION_AUTO"%[viewport_size,preset])
	await _press(sandbox,"MemberCard%d"%hero)
	var enemy:=int(sandbox.session.party_status().visible_enemy_ids[0]); await _touch_entity(sandbox,enemy)
	if sandbox.selected_member_id!=hero: failures.append("%s %s enemy tap selected enemy"%[viewport_size,preset])
	if not _button(sandbox,"OverrideClear").disabled: failures.append("%s %s enemy tap exposed companion controls"%[viewport_size,preset])
	var melee_ready_checked:=false
	for combat_turn in range(12):
		if sandbox.session.party_status().safe_phase=="GROUPED_COMPLETE": break
		var hero_position:=Vector2i.ZERO
		for card in sandbox.session.party_cards():
			if int(card.entity_id)==hero:
				hero_position=Vector2i(int(card.logical_position[0]),int(card.logical_position[1])); break
		var targets:Array=sandbox.session.enemy_targets()
		if targets.is_empty(): break
		enemy=int(targets[0].entity_id)
		var enemy_position:=Vector2i(int(targets[0].position[0]),int(targets[0].position[1]))
		var distance:=maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))
		if distance==1:
			await _touch_entity(sandbox,enemy)
			if not melee_ready_checked:
				_validate_layout(sandbox,"%s %s COMBAT_MELEE_READY"%[viewport_size,preset])
				melee_ready_checked=true
		else:
			var moved_toward_enemy:=false
			var directions:=[Vector2i(signi(enemy_position.x-hero_position.x),signi(enemy_position.y-hero_position.y)),
				Vector2i(signi(enemy_position.x-hero_position.x),0),Vector2i(0,signi(enemy_position.y-hero_position.y))]
			for direction in directions:
				if direction==Vector2i.ZERO: continue
				await _touch_cell(sandbox,hero_position+direction)
				await _touch_cell(sandbox,hero_position+direction)
				var draft:Dictionary=sandbox.session.current_turn_preview()
				if bool(draft.get("accepted",false)) and str(draft.actor_rows[0].action.type)=="MOVE":
					moved_toward_enemy=true; break
			if not moved_toward_enemy: await _press(sandbox,"ActorHold")
		await _press(sandbox,"TurnConfirm")
	if sandbox.session.party_status().safe_phase!="GROUPED_COMPLETE": failures.append("%s %s automatic regroup phase"%[viewport_size,preset])
	if _button(sandbox,"RegroupConfirm")!=null: failures.append("%s %s manual regroup button remains"%[viewport_size,preset])
	if not sandbox.grid._intent_overlays.is_empty(): failures.append("%s %s stale combat overlays"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s GROUPED_COMPLETE"%[viewport_size,preset])
	if sandbox.grid.visible_cell_count!=15 or sandbox.grid.view_origin!=Vector2i.ZERO:failures.append("%s %s victory did not restore full camera"%[viewport_size,preset])
	if sandbox.grid.mapping_signature()!=exploration_mapping:failures.append("%s %s zoom-out did not restore exact exploration mapping"%[viewport_size,preset])
	if sandbox.combat_action_area.visible or sandbox.combat_action_area.is_visible_in_tree():failures.append("%s %s combat action area remains after victory"%[viewport_size,preset])
	if sandbox.combat_action_dock.visible or sandbox.combat_action_dock.is_visible_in_tree():failures.append("%s %s combat dock remains after victory"%[viewport_size,preset])
	if not "승리 · 자동 재집결" in sandbox.phase_label.text:failures.append("%s %s victory banner missing"%[viewport_size,preset])
	var old_anchor:Array=sandbox.session.party_status().anchor
	await _touch_cell(sandbox,Vector2i(int(old_anchor[0])-1,int(old_anchor[1])))
	await _touch_cell(sandbox,Vector2i(int(old_anchor[0])-1,int(old_anchor[1])))
	if sandbox.session.party_status().anchor==old_anchor: failures.append("%s %s grouped-complete anchor stale"%[viewport_size,preset])
	if sandbox.grid.get_instance_id()!=grid_id or sandbox.grid.mapping_signature()!=exploration_mapping: failures.append("%s %s grid identity/restored mapping changed"%[viewport_size,preset])
	if not "승리 · 자동 재집결" in sandbox.phase_label.text:failures.append("%s %s post-regroup move lost persistent victory banner"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s POST_REGROUP_MOVE"%[viewport_size,preset])
	print("PARTY UI %dx%d %s full journey ok grid=%.0f cell=%.1f"%[viewport_size.x,viewport_size.y,preset,sandbox.grid.size.x,sandbox.grid.cell_size_px()])
	sandbox.queue_free(); await process_frame

func _terminal(viewport_size:Vector2)->void:
	var session=Session.new(); var state=session.sim.world.party_encounter; session.sim.world.entities[state.protagonist_id].health=5
	session.sim.world.bootstrap_set_fire(state.group_anchor,100); session.commit_exploration(Command.wait(state.protagonist_id))
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); sandbox.size=viewport_size; root.add_child(sandbox)
	await process_frame; await process_frame
	_validate_layout(sandbox,"%s TERMINAL"%viewport_size)
	if sandbox.find_child("TerminalOverlay",true,false)==null: failures.append("%s terminal overlay missing"%viewport_size)
	if sandbox.find_child("TurnConfirm",true,false)!=null: failures.append("%s terminal confirm visible"%viewport_size)
	if not "패배" in sandbox.phase_label.text:failures.append("%s terminal phase banner missing"%viewport_size)
	if str(sandbox.grid._presentation_style.get("style_id",""))!="DEFEAT" or str(sandbox.grid._presentation_style.get("border_hex",""))!="#8f5367":
		failures.append("%s terminal presentation style missing"%viewport_size)
	var terminal_panel:=sandbox.phase_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if terminal_panel==null or terminal_panel.border_color!=Color("#8f5367"):failures.append("%s terminal panel border missing"%viewport_size)
	if sandbox.log_label.text.is_empty(): failures.append("%s terminal log empty"%viewport_size)
	sandbox.queue_free(); await process_frame

func _wide_camera_fallback(viewport_size:Vector2)->void:
	var session=Session.new();var state=session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE",session.available_companion_ids());session.commit_deployment()
	var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox)
	await process_frame;await process_frame
	var grid_id=sandbox.grid.get_instance_id();var status:Dictionary=session.party_status()
	var actor_ids:Array=[];actor_ids.append_array(status.party_member_ids);actor_ids.append_array(status.visible_enemy_ids)
	var corners:=[Vector2i(0,0),Vector2i(14,14),Vector2i(0,14),Vector2i(14,0)]
	for index in range(mini(actor_ids.size(),corners.size())):
		session.sim.world.entities[int(actor_ids[index])].position=corners[index]
	sandbox._refresh();await process_frame;await process_frame
	var label:="%s WIDE_COMBAT_FALLBACK"%viewport_size
	_validate_layout(sandbox,label,15)
	if sandbox.grid.get_instance_id()!=grid_id:failures.append("%s replaced PartyGridView"%label)
	if sandbox.grid.view_origin!=Vector2i.ZERO:failures.append("%s full fallback origin %s"%[label,sandbox.grid.view_origin])
	for cell in session.observe_party_world().cells:
		for actor in cell.actors:
			var actor_position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
			if not sandbox.grid.is_world_cell_visible(actor_position):failures.append("%s hid required actor %s at %s"%[label,actor.entity_id,actor_position])
	var edge:=Vector2i(14,7);var routed:Array=[];var capture:Callable=func(position):routed.append(position)
	sandbox.grid.world_cell_pressed.connect(capture);await _touch_cell(sandbox,edge)
	if sandbox.grid.world_cell_pressed.is_connected(capture):sandbox.grid.world_cell_pressed.disconnect(capture)
	if routed!=[edge]:failures.append("%s real ScreenTouch routed %s instead of %s"%[label,routed,edge])
	if sandbox.grid.pixel_to_world_cell(sandbox.grid.world_to_pixel_center(Vector2i(14,14)))!=Vector2i(14,14):
		failures.append("%s full fallback edge roundtrip"%label)
	await _validate_fixed_combat_area(sandbox,label)
	sandbox.queue_free();await process_frame

func _validate_authoritative_rejection_layouts_360()->void:
	var viewport_size:=Vector2(360,640);root.size=Vector2i(360,640);await process_frame
	var cases:Array=[]
	var draft_session=_engaged_session([1,2],"WEDGE");var draft_status:Dictionary=draft_session.party_status();var draft_companion:=int(draft_status.party_member_ids[1])
	cases.append({"code":"turn_draft_required","result":draft_session.preview_actor_action(draft_companion,"HOLD"),"prefix":"%s 대기 불가"%_party_name(draft_session,draft_companion)})
	var busy_session=_engaged_session([1],"LINE");var busy_status:Dictionary=busy_session.party_status();var busy_hero:=int(busy_status.protagonist_id);var busy_companion:=int(busy_status.party_member_ids[1])
	busy_session.sim.world.party_encounter.member(busy_companion).busy_until=busy_session.sim.world.world_time+37;busy_session.set_actor_action(busy_hero,"HOLD")
	cases.append({"code":"party_actor_busy","result":busy_session.preview_actor_action(busy_companion,"HOLD"),"prefix":"%s 대기 불가"%_party_name(busy_session,busy_companion)})
	var wall_source=Session.new();var wall_state=wall_source.sim.world.party_encounter;var wall_destination:=Vector2i(5,6)
	if not wall_source.sim.world.bootstrap_set_terrain(wall_destination,"wall"):failures.append("360 rejection layout wall fixture")
	var wall_session=_engaged_session([1,2],"WEDGE",wall_source);var wall_companion:=int(wall_state.party_member_ids[1]);wall_session.set_actor_action(int(wall_state.protagonist_id),"HOLD")
	cases.append({"code":"move_terrain_blocked","result":wall_session.preview_actor_action(wall_companion,"MOVE",[wall_destination.x,wall_destination.y]),"prefix":"%s 이동 불가"%_party_name(wall_session,wall_companion)})
	var occupied_session=_engaged_session([1,2],"WEDGE");var occupied_status:Dictionary=occupied_session.party_status();var occupied_hero:=int(occupied_status.protagonist_id);var occupied_companion:=int(occupied_status.party_member_ids[1])
	var occupied_destination:=Vector2i(5,6);var blocker=occupied_session.sim.world.add_entity("obstacle","상자",occupied_destination,100,[],"human","neutral")
	if blocker==null:failures.append("360 rejection layout occupied fixture")
	if not occupied_session.set_actor_action(occupied_hero,"HOLD").accepted:failures.append("360 rejection layout occupied hero draft")
	cases.append({"code":"move_destination_occupied","result":occupied_session.preview_actor_action(occupied_companion,"MOVE",[occupied_destination.x,occupied_destination.y]),"prefix":"%s 이동 불가"%_party_name(occupied_session,occupied_companion)})
	var distant_session=_engaged_session([1,2],"WEDGE");var distant_status:Dictionary=distant_session.party_status();var distant_hero:=int(distant_status.protagonist_id);var distant_companion:=int(distant_status.party_member_ids[1]);distant_session.set_actor_action(distant_hero,"HOLD")
	var distant_origin:=_party_position(distant_session,distant_companion);var distant_destination:=distant_origin+Vector2i(3,0)
	cases.append({"code":"move_not_adjacent","result":distant_session.preview_actor_action(distant_companion,"MOVE",[distant_destination.x,distant_destination.y]),"prefix":"%s 이동 불가"%_party_name(distant_session,distant_companion)})
	var conflict_session=_engaged_session([1],"LINE");var conflict_status:Dictionary=conflict_session.party_status();var conflict_hero:=int(conflict_status.protagonist_id);var conflict_companion:=int(conflict_status.party_member_ids[1])
	if not _relocate_with_move_events(conflict_session.sim,conflict_companion,Vector2i(9,7)):failures.append("360 rejection layout conflict relocation")
	var conflict_destination:=Vector2i(8,7);var conflict_hero_result:Dictionary=conflict_session.set_actor_action(conflict_hero,"MOVE",[conflict_destination.x,conflict_destination.y])
	if not bool(conflict_hero_result.get("accepted",false)):failures.append("360 rejection layout conflict hero draft")
	cases.append({"code":"destination_conflict","result":conflict_session.preview_actor_action(conflict_companion,"MOVE",[conflict_destination.x,conflict_destination.y]),"prefix":"%s 이동 불가"%_party_name(conflict_session,conflict_companion)})
	var dormant_session=_engaged_session([],"LINE");var dormant_status:Dictionary=dormant_session.party_status();var dormant_hero:=int(dormant_status.protagonist_id);var dormant_companion:=int(dormant_status.party_member_ids[1]);dormant_session.set_actor_action(dormant_hero,"HOLD")
	cases.append({"code":"override_actor_not_deployed","result":dormant_session.preview_actor_action(dormant_companion,"HOLD"),"prefix":"%s 대기 불가"%_party_name(dormant_session,dormant_companion)})
	var live_session=_engaged_session([1,2],"WEDGE");var sandbox=Sandbox.new();sandbox.size=viewport_size;sandbox.initialize_for_headless_test(live_session)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size;root.add_child(sandbox);await process_frame;await process_frame
	for row in cases:
		var result:Dictionary=row.result
		if str(result.get("reason_code",""))!=str(row.code):failures.append("360 rejection layout wrong fixture %s: %s"%[row.code,result.get("reason_code","")]);continue
		sandbox._set_action_rejection(result,str(row.prefix));sandbox._refresh();await process_frame;await process_frame
		if not str(result.message) in sandbox.action_feedback_label.text:failures.append("360 %s facade message missing from fixed feedback"%row.code)
		_validate_feedback_lines(sandbox.action_feedback_label,"360 AUTHORITY_%s"%row.code)
	sandbox.queue_free();await process_frame

func _engaged_session(roster_slots:Array,preset:String="LINE",custom_session=null):
	var result_session=custom_session if custom_session!=null else Session.new();var state=result_session.sim.world.party_encounter;var selected:Array=[]
	for slot in roster_slots:selected.append(state.party_member_ids[int(slot)])
	if not result_session.commit_exploration(Command.wait(state.protagonist_id)).accepted:failures.append("rejection layout contact fixture")
	if not result_session.preview_deployment(preset,selected).accepted:failures.append("rejection layout deployment preview fixture")
	if not result_session.commit_deployment().accepted:failures.append("rejection layout deployment commit fixture")
	return result_session

func _party_name(custom_session,entity_id:int)->String:
	for card in custom_session.party_cards():
		if int(card.entity_id)==entity_id:return str(card.display_name)
	return "파티원"

func _party_position(custom_session,entity_id:int)->Vector2i:
	for card in custom_session.party_cards():
		if int(card.entity_id)==entity_id:return Vector2i(int(card.logical_position[0]),int(card.logical_position[1]))
	return Vector2i(-1,-1)

func _relocate_with_move_events(sim,entity_id:int,target:Vector2i)->bool:
	for attempt in range(64):
		var current:Vector2i=sim.world.entities[entity_id].position
		if current==target:return true
		var delta:=target-current;var directions:Array[Vector2i]=[Vector2i(signi(delta.x),signi(delta.y)),Vector2i(signi(delta.x),0),Vector2i(0,signi(delta.y))]
		var moved:=false
		for direction in directions:
			if direction==Vector2i.ZERO:continue
			var destination:=current+direction
			if maxi(absi(destination.x-target.x),absi(destination.y-target.y))>=maxi(absi(current.x-target.x),absi(current.y-target.y)):continue
			var assessment=sim.movement.assess_move(entity_id,destination)
			if not assessment.accepted:continue
			var definition:Dictionary=TerrainRegistry.definition(str(assessment.terrain_id))
			if sim.movement.commit_preflighted_move(entity_id,destination,str(assessment.terrain_id),int(definition.move_time_cost))==null:return false
			moved=true;break
		if not moved:return false
	return false

func _press(sandbox,node_name:String)->void:
	var button=_button(sandbox,node_name)
	if button==null:
		failures.append("missing button %s in %s"%[node_name,sandbox.session.party_status().safe_phase]); return
	var scroll=_scroll_ancestor(button)
	if scroll!=null:
		scroll.ensure_control_visible(button); await process_frame; await process_frame
	var sandbox_rect:Rect2=sandbox.get_global_rect();var button_rect:Rect2=button.get_global_rect()
	if not button.is_visible_in_tree() or not _rect_contains(sandbox_rect,button_rect):
		failures.append("unreachable button %s phase=%s rect=%s viewport=%s"%[node_name,sandbox.session.party_status().safe_phase,button_rect,sandbox_rect]);return
	if scroll!=null and not _rect_contains(scroll.get_global_rect(),button_rect):
		failures.append("button clipped by scroll %s rect=%s scroll=%s"%[node_name,button_rect,scroll.get_global_rect()]);return
	if button.disabled:
		failures.append("attempted disabled button %s phase=%s"%[node_name,sandbox.session.party_status().safe_phase]);return
	var center:=button_rect.get_center()
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.position=center;press.global_position=center
	root.push_input(press,true);await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	release.button_mask=0;release.position=center;release.global_position=center
	root.push_input(release,true);await process_frame;await process_frame

func _button(root_node:Node,node_name:String)->Button:
	return root_node.find_child(node_name,true,false) as Button

func _touch_cell(sandbox,position:Vector2i)->void:
	var local_position:Vector2=sandbox.grid.world_to_pixel_center(position)
	if local_position==Vector2(-1,-1):failures.append("ScreenTouch target outside camera %s"%position);return
	var global_position:Vector2=sandbox.grid.get_global_rect().position+local_position
	if not sandbox.get_global_rect().has_point(global_position):failures.append("ScreenTouch target outside viewport %s at %s"%[position,global_position]);return
	var event:=InputEventScreenTouch.new();event.index=0;event.pressed=true;event.position=global_position
	root.push_input(event,true);await process_frame
	var release:=InputEventScreenTouch.new();release.index=0;release.pressed=false;release.position=global_position
	root.push_input(release,true);await process_frame;await process_frame

func _touch_entity(sandbox,entity_id:int)->void:
	var position:=Vector2i(-1,-1)
	for cell in sandbox.session.observe_party_world().cells:
		for actor in cell.actors:
			if int(actor.entity_id)==entity_id: position=Vector2i(int(cell.position[0]),int(cell.position[1])); break
		if position!=Vector2i(-1,-1): break
	await _touch_cell(sandbox,position)

func _explore_wait(sandbox)->void:
	var hero:=int(sandbox.session.party_status().protagonist_id)
	await _touch_entity(sandbox,hero); await _touch_entity(sandbox,hero)

func _validate_layout(sandbox,label:String,expected_cells_override:int=-1)->void:
	var viewport_size:Vector2=sandbox.size;var combat_view:=str(sandbox.session.party_status().view_mode)=="COMBAT"
	var expected:float
	if combat_view:expected=360.0 if viewport_size.x>=450 else 300.0
	else:expected=405.0 if viewport_size.x>=450 else 348.0
	if sandbox.grid.size.x+0.1<expected or sandbox.grid.size.y+0.1<expected: failures.append("%s grid below budget"%label)
	var expected_cells:=expected_cells_override if expected_cells_override>0 else (9 if combat_view else 15)
	if sandbox.grid.visible_cell_count!=expected_cells:failures.append("%s wrong camera cell count %d"%[label,sandbox.grid.visible_cell_count])
	var minimum_cell:=expected/float(expected_cells)-0.1
	if sandbox.grid.cell_size_px()<minimum_cell: failures.append("%s cell below phase budget"%label)
	if sandbox.cards.get_child_count()!=3: failures.append("%s card count"%label)
	_validate_card_content(sandbox,label)
	var root_box=sandbox.get_node("PartyLayout"); var prior_end:=-100000.0
	for child in root_box.get_children():
		if not child is Control or not child.is_visible_in_tree(): continue
		var rect:=Rect2(child.position,child.size)
		if rect.position.x<-0.1 or rect.end.x>viewport_size.x+0.1: failures.append("%s horizontal overflow %s"%[label,child.name])
		if rect.position.y<-0.1 or rect.end.y>viewport_size.y+0.1: failures.append("%s vertical overflow %s"%[label,child.name])
		if rect.position.y+0.1<prior_end: failures.append("%s vertical overlap %s"%[label,child.name])
		prior_end=maxf(prior_end,rect.end.y)
	var controls:Array[Node]=[]; _collect_controls(root_box,controls)
	for node in controls:
		var control:=node as Control
		if not control.is_visible_in_tree(): continue
		var global_rect:=control.get_global_rect()
		if not _inside_scroll(control) and (global_rect.position.x<-0.1 or global_rect.end.x>viewport_size.x+0.1 \
				or global_rect.position.y<-0.1 or global_rect.end.y>viewport_size.y+0.1):
			failures.append("%s child bounds %s %s"%[label,control.name,global_rect])
		if control is Button and (control.size.x<43.9 or control.size.y<43.9): failures.append("%s touch target %s %s"%[label,control.name,control.size])
		if control is Label and control.get_theme_font_size("font_size")<16: failures.append("%s font below 16 %s"%[label,control.name])
		if control is Button and control.get_theme_font_size("font_size")<18: failures.append("%s button font below 18 %s"%[label,control.name])
	var deck_prior:=-100000.0
	for child in sandbox.deck.get_children():
		if child is Control and child.is_visible_in_tree():
			if child.position.y+0.1<deck_prior: failures.append("%s deck overlap %s"%[label,child.name])
			deck_prior=maxf(deck_prior,child.position.y+child.size.y)
	if sandbox.info_scroll.size.y<29.9:failures.append("%s InformationScroll below 30px: %s"%[label,sandbox.info_scroll.size])
	var engaged:=str(sandbox.session.party_status().safe_phase)=="ENGAGED" and not bool(sandbox.session.party_status().terminal)
	if engaged:
		if not sandbox.combat_action_area.visible or not sandbox.combat_action_area.is_visible_in_tree():failures.append("%s ENGAGED action area hidden"%label)
		if sandbox.combat_action_area.custom_minimum_size.y<83.9:failures.append("%s ENGAGED action area budget below 84"%label)
	else:
		if sandbox.combat_action_area.visible or sandbox.combat_action_area.is_visible_in_tree():failures.append("%s noncombat action area visible"%label)
		if sandbox.combat_action_area.custom_minimum_size.y>0.1:failures.append("%s hidden action area retains height %s"%[label,sandbox.combat_action_area.custom_minimum_size])
		if sandbox.combat_action_dock.visible or sandbox.combat_action_dock.is_visible_in_tree():failures.append("%s noncombat dock visible"%label)

func _validate_fixed_combat_area(sandbox,label:String)->void:
	var area:Control=sandbox.combat_action_area;var feedback:Label=sandbox.action_feedback_label
	var dock:Control=sandbox.combat_action_dock;var root_box:Control=sandbox.root_layout
	if not area.visible or not area.is_visible_in_tree():failures.append("%s combat action area not visible"%label);return
	if not dock.visible or not dock.is_visible_in_tree():failures.append("%s combat dock not visible"%label);return
	if area.get_parent()!=root_box:failures.append("%s action area is not direct PartyLayout sibling"%label)
	if root_box.get_child(root_box.get_child_count()-1)!=area:failures.append("%s action area is not final PartyLayout sibling"%label)
	if dock.get_parent()!=area or feedback.get_parent()!=area:failures.append("%s feedback/dock hierarchy"%label)
	if _scroll_ancestor(area)!=null or _scroll_ancestor(dock)!=null or _scroll_ancestor(feedback)!=null:
		failures.append("%s fixed action area remains inside InformationScroll"%label)
	var viewport_rect:Rect2=sandbox.get_global_rect();var area_rect:Rect2=area.get_global_rect()
	var dock_rect:Rect2=dock.get_global_rect();var feedback_rect:Rect2=feedback.get_global_rect()
	if not _rect_contains(viewport_rect,area_rect):failures.append("%s action area outside viewport %s"%[label,area_rect])
	if not _rect_contains(viewport_rect,dock_rect):failures.append("%s dock outside viewport %s"%[label,dock_rect])
	if not _rect_contains(viewport_rect,feedback_rect):failures.append("%s feedback outside viewport %s"%[label,feedback_rect])
	if absf(area_rect.end.y-root_box.get_global_rect().end.y)>0.6 or absf(dock_rect.end.y-area_rect.end.y)>0.6:
		failures.append("%s action area/dock is not fixed at bottom area=%s dock=%s"%[label,area_rect,dock_rect])
	if area.size.y<83.9 or feedback.size.y<37.9 or dock.size.y<43.9:failures.append("%s fixed row heights area=%s feedback=%s dock=%s"%[label,area.size,feedback.size,dock.size])
	if feedback.get_theme_font_size("font_size")<16:failures.append("%s feedback font below 16"%label)
	_validate_feedback_lines(feedback,label)
	for button_name in ["ActorHold","OverrideClear","TurnConfirm"]:
		var button:=_button(sandbox,button_name)
		if button==null:
			failures.append("%s missing fixed button %s"%[label,button_name]);continue
		if button.get_parent()!=dock:failures.append("%s %s is duplicated/outside dock"%[label,button_name])
		if not _rect_contains(viewport_rect,button.get_global_rect()):failures.append("%s %s outside viewport"%[label,button_name])
		if button.size.x<43.9 or button.size.y<43.9:failures.append("%s %s below 44 touch target"%[label,button_name])
		if button.get_theme_font_size("font_size")<18:failures.append("%s %s font below 18"%[label,button_name])
		var font:Font=button.get_theme_font("font")
		var rendered:=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size"))
		if rendered.x>button.size.x-10.0:failures.append("%s dock text clips %s rendered=%s box=%s"%[label,button_name,rendered,button.size])
		if sandbox.deck.find_child(button_name,true,false)!=null:failures.append("%s duplicate %s in ContextDeck"%[label,button_name])
	if not "⚔ 전투 중" in sandbox.phase_label.text:failures.append("%s persistent combat banner missing"%label)
	var phase_font:Font=sandbox.phase_label.get_theme_font("font")
	for line in sandbox.phase_label.text.split("\n"):
		var rendered:=phase_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,sandbox.phase_label.get_theme_font_size("font_size"))
		if rendered.x>sandbox.phase_label.size.x+0.5:failures.append("%s phase banner text clips rendered=%s box=%s"%[label,rendered,sandbox.phase_label.size])
	await _validate_fixed_feedback(sandbox,feedback.text,label+" FIXED_DEFAULT")

func _validate_fixed_feedback(sandbox,expected_message:String,label:String)->void:
	var area:Control=sandbox.combat_action_area;var feedback:Label=sandbox.action_feedback_label;var dock:Control=sandbox.combat_action_dock
	if not expected_message in feedback.text:failures.append("%s fixed feedback misses facade message: %s"%[label,feedback.text])
	if _scroll_ancestor(feedback)!=null:failures.append("%s fixed feedback has ScrollContainer ancestor"%label)
	if not feedback.is_visible_in_tree() or not _rect_contains(sandbox.get_global_rect(),feedback.get_global_rect()):
		failures.append("%s fixed feedback unreachable %s"%[label,feedback.get_global_rect()]);return
	_validate_feedback_lines(feedback,label)
	sandbox.info_scroll.scroll_vertical=0;await process_frame;await process_frame
	if sandbox.info_scroll.size.y<29.9:failures.append("%s combat InformationScroll below 30px"%label)
	var action_status:=sandbox.find_child("ActionStatus",true,false) as Label
	if action_status==null:failures.append("%s combat information body row missing"%label)
	else:
		var visible_body:=action_status.get_global_rect().intersection(sandbox.info_scroll.get_global_rect())
		var line_height:=action_status.get_theme_font("font").get_height(action_status.get_theme_font_size("font_size"))
		if action_status.get_theme_font_size("font_size")<18 or visible_body.size.y+0.5<line_height:
			failures.append("%s no unclipped 18px information line visible=%s line_height=%.1f"%[label,visible_body,line_height])
	var area_before:=area.get_global_rect();var feedback_before:=feedback.get_global_rect();var dock_before:=dock.get_global_rect();var text_before:=feedback.text
	var scrolled_control:Control=null
	for child in sandbox.deck.get_children():
		if child is Control:scrolled_control=child;break
	var scroll_child_before:=Rect2() if scrolled_control==null else scrolled_control.get_global_rect()
	sandbox.info_scroll.scroll_vertical=100000;await process_frame;await process_frame
	if sandbox.info_scroll.scroll_vertical<=0:failures.append("%s InformationScroll fixture did not actually move"%label)
	if scrolled_control!=null and scrolled_control.get_global_rect()==scroll_child_before:failures.append("%s scroll content did not move"%label)
	if area.get_global_rect()!=area_before or feedback.get_global_rect()!=feedback_before or dock.get_global_rect()!=dock_before:
		failures.append("%s information scroll moved fixed action area"%label)
	if feedback.text!=text_before:failures.append("%s information scroll changed fixed feedback"%label)

func _validate_feedback_lines(feedback:Label,label:String)->void:
	var line_count:=feedback.get_line_count();var visible_lines:=feedback.get_visible_line_count()
	if line_count<1 or visible_lines<line_count:failures.append("%s feedback lines clipped visible=%d total=%d size=%s text=%s"%[label,visible_lines,line_count,feedback.size,feedback.text])

func _validate_camera_mapping(sandbox,label:String)->void:
	var grid=sandbox.grid;var bounds:Rect2i=grid.view_bounds()
	for world_position in [bounds.position,bounds.position+bounds.size-Vector2i.ONE]:
		var pixel:Vector2=grid.world_to_pixel_center(world_position)
		if grid.pixel_to_world_cell(pixel)!=world_position:failures.append("%s crop roundtrip failed %s"%[label,world_position])
	var offwindow:=Vector2i.ZERO if not grid.is_world_cell_visible(Vector2i.ZERO) else Vector2i(14,14)
	if grid.is_world_cell_visible(offwindow):failures.append("%s no off-window fixture"%label);return
	if grid.world_to_pixel_center(offwindow)!=Vector2(-1,-1) or grid.world_cell_rect(offwindow)!=Rect2():failures.append("%s off-window cell projects into grid"%label)
	var routed:Array=[]
	var capture:Callable=func(position):routed.append(position)
	grid.world_cell_pressed.connect(capture)
	var event:=InputEventScreenTouch.new();event.pressed=true;event.position=grid.world_to_pixel_center(offwindow);grid._gui_input(event)
	if not routed.is_empty():failures.append("%s off-window touch emitted world cell"%label)
	grid.world_cell_pressed.disconnect(capture)

func _validate_card_content(sandbox,label:String)->void:
	for child in sandbox.cards.get_children():
		if not child is Button: continue
		var card:=child as Button; var content:=card.find_child("CardContent",true,false) as Control
		if content==null:
			failures.append("%s missing measured card content %s"%[label,card.name]); continue
		var content_min:=content.get_combined_minimum_size()
		if content_min.x>card.size.x+0.1 or content_min.y>card.size.y+0.1:
			failures.append("%s card content minimum exceeds card %s min=%s card=%s"%[label,card.name,content_min,card.size])
		var card_rect:=card.get_global_rect(); var content_rect:=content.get_global_rect()
		if content_rect.position.x<card_rect.position.x-0.1 or content_rect.end.x>card_rect.end.x+0.1 \
				or content_rect.position.y<card_rect.position.y-0.1 or content_rect.end.y>card_rect.end.y+0.1:
			failures.append("%s card content bounds clip %s content=%s card=%s"%[label,card.name,content_rect,card_rect])
		var portrait:=card.find_child("Portrait",true,false) as TextureRect
		if portrait==null or not portrait.texture is AtlasTexture:
			failures.append("%s card portrait missing %s"%[label,card.name])
		for node_name in ["MemberName","MemberState","StressState","Readiness","EmotionState"]:
			var text_label:=card.find_child(node_name,true,false) as Label
			if text_label==null:
				failures.append("%s missing card row %s/%s"%[label,card.name,node_name]); continue
			var font:Font=text_label.get_theme_font("font")
			var rendered:=font.get_string_size(text_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,
				text_label.get_theme_font_size("font_size"))
			if rendered.x>text_label.size.x+0.5 or rendered.y>text_label.size.y+0.5:
				failures.append("%s rendered card row clips %s/%s rendered=%s box=%s text=%s"%[
					label,card.name,node_name,rendered,text_label.size,text_label.text])

func _collect_controls(node:Node,rows:Array[Node])->void:
	for child in node.get_children():
		if child is Control: rows.append(child)
		_collect_controls(child,rows)

func _inside_scroll(control:Control)->bool:
	var node:Node=control.get_parent()
	while node!=null:
		if node is ScrollContainer:return true
		node=node.get_parent()
	return false

func _scroll_ancestor(control:Control):
	var node:Node=control.get_parent()
	while node!=null:
		if node is ScrollContainer:return node as ScrollContainer
		node=node.get_parent()
	return null

func _rect_contains(outer:Rect2,inner:Rect2)->bool:
	return inner.position.x>=outer.position.x-0.1 and inner.position.y>=outer.position.y-0.1 \
		and inner.end.x<=outer.end.x+0.1 and inner.end.y<=outer.end.y+0.1
