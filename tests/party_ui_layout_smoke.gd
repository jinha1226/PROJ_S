extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")

var failures:Array[String]=[]

func _init()->void: call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(450,800),Vector2(360,640)]:
		for preset in ["WEDGE","LINE","COLUMN"]:
			await _journey(viewport_size,preset)
		await _terminal(viewport_size)
	for failure in failures: printerr("FAIL "+failure)
	print("---- party UI layout smoke: %d journeys, %d failed ----"%[6,failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _journey(viewport_size:Vector2,preset:String)->void:
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(Session.new())
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); sandbox.size=viewport_size; root.add_child(sandbox)
	await process_frame; await process_frame
	var grid_id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
	_validate_layout(sandbox,"%s %s EXPLORATION"%[viewport_size,preset])
	var initial_actors:=0; for cell in sandbox.session.observe_party_world().cells: initial_actors+=cell.actors.size()
	if initial_actors!=1: failures.append("%s %s pre-contact actor visibility"%[viewport_size,preset])
	await _press(sandbox,"ExploreHold")
	_validate_layout(sandbox,"%s %s CONTACT"%[viewport_size,preset])
	var contact_actors:=0; for cell in sandbox.session.observe_party_world().cells: contact_actors+=cell.actors.size()
	if contact_actors!=2: failures.append("%s %s contact enemy reveal"%[viewport_size,preset])
	if not _button(sandbox,"DeployConfirm").disabled: failures.append("%s %s pre-preset confirm enabled"%[viewport_size,preset])
	sandbox._on_deploy_confirm(); await process_frame
	if not "먼저" in str(sandbox.find_child("ActionStatus",true,false).text): failures.append("%s %s rejected confirm invisible"%[viewport_size,preset])
	for preview_preset in ["WEDGE","LINE","COLUMN"]:
		await _press(sandbox,"Preset%s"%preview_preset)
		_validate_layout(sandbox,"%s %s PREVIEW_%s"%[viewport_size,preset,preview_preset])
		if sandbox.grid._ghosts.size()!=2: failures.append("%s %s %s ghost count"%[viewport_size,preset,preview_preset])
	await _press(sandbox,"Preset%s"%preset)
	await _press(sandbox,"DeployConfirm")
	if sandbox.session.party_status().safe_phase!="ENGAGED": failures.append("%s %s did not engage"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s COMBAT_HERO_PENDING"%[viewport_size,preset])
	await _press(sandbox,"ActorHold")
	_validate_layout(sandbox,"%s %s COMBAT_HERO_DIRECT"%[viewport_size,preset])
	var status:Dictionary=sandbox.session.party_status(); var companion:=int(status.party_member_ids[1])
	await _press(sandbox,"MemberCard%d"%companion)
	var companion_position:=Vector2i.ZERO
	for row in sandbox.session.party_cards():
		if int(row.entity_id)==companion: companion_position=Vector2i(int(row.logical_position[0]),int(row.logical_position[1])); break
	for direction in [Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,-1),Vector2i(-1,1)]:
		var destination:Vector2i=companion_position+direction
		if not sandbox.session.sim.assess_move(companion,destination).accepted \
				or sandbox.grid.actor_in_world_cell(destination)!=-1: continue
		await _press(sandbox,"MemberCard%d"%companion)
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
	await _press(sandbox,"OverrideClear")
	_validate_layout(sandbox,"%s %s COMBAT_COMPANION_AUTO"%[viewport_size,preset])
	var hero:=int(status.protagonist_id); await _press(sandbox,"MemberCard%d"%hero)
	var enemy:=int(sandbox.session.party_status().visible_enemy_ids[0]); await _touch_entity(sandbox,enemy)
	if sandbox.selected_member_id!=hero: failures.append("%s %s enemy tap selected enemy"%[viewport_size,preset])
	if not _button(sandbox,"OverrideClear").disabled: failures.append("%s %s enemy tap exposed companion controls"%[viewport_size,preset])
	var melee_ready_checked:=false
	for combat_turn in range(12):
		if sandbox.session.party_status().safe_phase=="REGROUP_READY": break
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
				var draft:Dictionary=sandbox.session.current_turn_preview()
				if bool(draft.get("accepted",false)) and str(draft.actor_rows[0].action.type)=="MOVE":
					moved_toward_enemy=true; break
			if not moved_toward_enemy: await _press(sandbox,"ActorHold")
		await _press(sandbox,"TurnConfirm")
	if sandbox.session.party_status().safe_phase!="REGROUP_READY": failures.append("%s %s victory phase"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s REGROUP"%[viewport_size,preset])
	await _press(sandbox,"RegroupConfirm")
	if sandbox.session.party_status().safe_phase!="GROUPED_COMPLETE": failures.append("%s %s regroup phase"%[viewport_size,preset])
	_validate_layout(sandbox,"%s %s GROUPED_COMPLETE"%[viewport_size,preset])
	var old_anchor:Array=sandbox.session.party_status().anchor
	await _press(sandbox,"ExploreW")
	if sandbox.session.party_status().anchor==old_anchor: failures.append("%s %s grouped-complete anchor stale"%[viewport_size,preset])
	if sandbox.grid.get_instance_id()!=grid_id or sandbox.grid.mapping_signature()!=mapping: failures.append("%s %s grid identity/mapping changed"%[viewport_size,preset])
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
	if sandbox.log_label.text.is_empty(): failures.append("%s terminal log empty"%viewport_size)
	sandbox.queue_free(); await process_frame

func _press(sandbox,node_name:String)->void:
	var button=_button(sandbox,node_name)
	if button==null:
		failures.append("missing button %s in %s"%[node_name,sandbox.session.party_status().safe_phase]); return
	button.pressed.emit(); await process_frame; await process_frame

func _button(root_node:Node,node_name:String)->Button:
	return root_node.find_child(node_name,true,false) as Button

func _touch_cell(sandbox,position:Vector2i)->void:
	var event:=InputEventScreenTouch.new(); event.pressed=true; event.position=sandbox.grid.world_to_pixel_center(position)
	sandbox.grid._gui_input(event); await process_frame; await process_frame

func _touch_entity(sandbox,entity_id:int)->void:
	var position:=Vector2i(-1,-1)
	for cell in sandbox.session.observe_party_world().cells:
		for actor in cell.actors:
			if int(actor.entity_id)==entity_id: position=Vector2i(int(cell.position[0]),int(cell.position[1])); break
		if position!=Vector2i(-1,-1): break
	await _touch_cell(sandbox,position)

func _validate_layout(sandbox,label:String)->void:
	var viewport_size:Vector2=sandbox.size; var expected:=330.0 if viewport_size.x>=450 else 300.0
	if sandbox.grid.size.x+0.1<expected or sandbox.grid.size.y+0.1<expected: failures.append("%s grid below budget"%label)
	if sandbox.grid.cell_size_px()<20.0: failures.append("%s cell below 20"%label)
	if sandbox.cards.get_child_count()!=3: failures.append("%s card count"%label)
	_validate_card_content(sandbox,label)
	var root_box=sandbox.get_node("PartyLayout"); var prior_end:=-100000.0
	for child in root_box.get_children():
		if not child is Control or not child.visible: continue
		var rect:=Rect2(child.position,child.size)
		if rect.position.x<-0.1 or rect.end.x>viewport_size.x+0.1: failures.append("%s horizontal overflow %s"%[label,child.name])
		if rect.position.y<-0.1 or rect.end.y>viewport_size.y+0.1: failures.append("%s vertical overflow %s"%[label,child.name])
		if rect.position.y+0.1<prior_end: failures.append("%s vertical overlap %s"%[label,child.name])
		prior_end=maxf(prior_end,rect.end.y)
	var controls:Array[Node]=[]; _collect_controls(root_box,controls)
	for node in controls:
		var control:=node as Control
		if not control.visible: continue
		var global_rect:=control.get_global_rect()
		if global_rect.position.x<-0.1 or global_rect.end.x>viewport_size.x+0.1 \
				or global_rect.position.y<-0.1 or global_rect.end.y>viewport_size.y+0.1:
			failures.append("%s child bounds %s %s"%[label,control.name,global_rect])
		if control is Button and (control.size.x<43.9 or control.size.y<43.9): failures.append("%s touch target %s %s"%[label,control.name,control.size])
	var deck_prior:=-100000.0
	for child in sandbox.deck.get_children():
		if child is Control and child.visible:
			if child.position.y+0.1<deck_prior: failures.append("%s deck overlap %s"%[label,child.name])
			deck_prior=maxf(deck_prior,child.position.y+child.size.y)

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
		for node_name in ["MemberName","MemberState","MemberElements","ExpectedAction"]:
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
