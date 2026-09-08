extends "res://tests/battleheart_mvp_acceptance.gd"

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	_check(session.battle_loot().rows.is_empty(),"cannot loot during combat")
	await _drag_controls(session)
	# Use the genuine pre-change combat save for the victory/replay fixture,
	# independently from the drag control encounter.
	session=Session.new()
	var fixture:=FileAccess.open(LEGACY_SAVE_PATH,FileAccess.READ)
	_check(session.load_session_json(fixture.get_as_text()).get("accepted",false),"load loot encounter fixture")
	for attempt in range(90):
		if session.sim.world.party_encounter.safe_phase!="ENGAGED":break
		var acted:=false
		var members:Array=session.sim.world.party_encounter.active_party_member_ids.duplicate()
		members.reverse()
		for actor_id in members:
			var skills:Array=session.active_skill_rows(actor_id)
			skills.reverse()
			for skill in skills:
				if not skill.can_select or skill.skill_id=="SHOVE":continue
				if skill.skill_id=="MEND":
					var hero_id:int=session.sim.world.party_encounter.protagonist_id
					var healing:Dictionary=session.active_skill_assessment(actor_id,"MEND",hero_id)
					if healing.get("accepted",false):
						acted=session.use_active_skill(actor_id,"MEND",hero_id).get("accepted",false)
					if acted:break
					continue
				var target:=_find_valid_target(session,actor_id,str(skill.skill_id))
				if target.is_empty():continue
				var action:Dictionary=session.use_active_skill(actor_id,str(skill.skill_id),int(target.target_id))
				if action.get("accepted",false):acted=true;break
			if acted:break
		if not acted and not _basic_auto_tick(session):break
	print("LOOT fixture phase=",session.sim.world.party_encounter.safe_phase)
	var loot:Dictionary=session.battle_loot()
	_check(not loot.rows.is_empty(),"victory offers actual battlefield drops")
	if not loot.rows.is_empty():await _loot_controls(session,loot)
	for failure in failures:printerr("FAIL ",failure)
	print("PASS battle mobile/loot acceptance" if failures.is_empty() else "FAIL mobile/loot: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)

func _drag_controls(session)->void:
	root.size=Vector2i(360,640);root.content_scale_size=Vector2i(360,640)
	var ui:=Sandbox.new();ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	var state=session.sim.world.party_encounter
	var target_id:int=session.party_status().visible_enemy_ids[0]
	var target:Vector2=ui.grid.get_global_transform_with_canvas()*ui.grid.actor_visual_center(target_id)
	var before:int=session.sim.world.world_time
	for actor_id in state.active_party_member_ids:
		var portrait:=ui.cards.find_child("MemberCard%d"%actor_id,true,false) as Control
		var start:=portrait.get_global_rect().get_center()
		_touch(ui,0,start,true)
		await process_frame
		_check(ui.battle_drag.active,"portrait touch begins drag")
		ui._tick_autonomous_battle(2.0)
		_check_eq(session.sim.world.world_time,before,"held drag freezes auto stepping")
		var motion:=InputEventScreenDrag.new();motion.index=0;motion.position=target
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		_touch(ui,0,target,false)
		await process_frame
		_check_eq(session.actor_command_status(actor_id).target_id,target_id,"drag sets named actor's enemy")
		_check_eq(session.sim.world.world_time,before,"directive costs no extra turn")
		await process_frame;await process_frame
	var journal_count:int=session.command_journal.size()
	var portrait:=ui.cards.find_child("MemberCard%d"%state.protagonist_id,true,false) as Control
	_touch(ui,0,portrait.get_global_rect().get_center(),true)
	_touch(ui,1,target,true)
	_touch(ui,1,target,false)
	_touch(ui,0,target,false)
	_check_eq(session.command_journal.size(),journal_count,"second finger cancels rather than issuing attack")
	await process_frame;await process_frame
	var map_start:Vector2=ui.grid.get_global_transform_with_canvas()*ui.grid.actor_hit_rect(state.protagonist_id).get_center()
	_touch(ui,0,map_start,true);await process_frame
	_check(ui.battle_drag.active,"map character can start a target drag")
	_touch(ui,0,target,false);await process_frame;await process_frame
	_check_eq(session.actor_command_status(state.protagonist_id).target_id,target_id,"map drag sets enemy")
	journal_count=session.command_journal.size()
	portrait=ui.cards.find_child("MemberCard%d"%state.protagonist_id,true,false) as Control
	_touch(ui,0,portrait.get_global_rect().get_center(),true);await process_frame
	_touch(ui,0,Vector2(2,2),false);await process_frame;await process_frame
	_check_eq(session.command_journal.size(),journal_count,"empty drop issues no command or movement")
	ui.battle_drag.ignore_mouse_until=-1
	portrait=ui.cards.find_child("MemberCard%d"%state.protagonist_id,true,false) as Control
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true;press.position=portrait.get_global_rect().get_center()
	Input.parse_input_event(press);Input.flush_buffered_events();await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT
	release.pressed=false;release.position=target
	Input.parse_input_event(release);Input.flush_buffered_events();await process_frame
	_check_eq(session.command_journal.size(),journal_count+1,"desktop mouse drag commits exactly once")
	ui.queue_free();await process_frame

func _touch(_ui,index:int,position:Vector2,pressed:bool)->void:
	var event:=InputEventScreenTouch.new();event.index=index;event.position=position;event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _loot_controls(session,loot:Dictionary)->void:
	var inventory:Dictionary=session.protagonist_inventory()
	var first:Dictionary=loot.rows[0]
	var before_time:int=session.sim.world.world_time
	# Isolated capacity rejection probe: restore the exact live item state before
	# any accepted command or save, rather than putting fixture edits in a journal.
	var world=session.sim.world
	var original_items=world.item_state
	world.item_state=original_items.clone()
	var bag=world.item_state.inventory(world.party_encounter.protagonist_id)
	while bag.used_backpack_slots()<20:
		bag.backpack.append(preload("res://sim/item_instance.gd").new(
			"LOOT_TEST_%d"%bag.backpack.size(),str(first.definition_id),1))
	bag._sort_backpack()
	var rejected:Dictionary=session.take_battle_loot(int(loot.battle_id),str(first.instance_id))
	_check(not rejected.get("accepted",false),"full bag cannot take loot")
	_check_eq(session.battle_loot().rows.size(),loot.rows.size(),"full bag leaves loot on ground")
	world.item_state=original_items
	var hero_position:Vector2i=session.sim.world.entities[session.sim.world.party_encounter.protagonist_id].position
	var ui:=Sandbox.new();ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	ui._maybe_open_battle_loot()
	await process_frame;await process_frame
	_check(ui.battle_loot_panel.visible and ui.grid.modal_open,"postbattle loot modal blocks background")
	var left:=ui.battle_loot_panel.find_child("BagLeft",true,false) as Control
	var right:=ui.battle_loot_panel.find_child("LootRight",true,false) as Control
	_check(left.get_global_rect().end.x<=right.get_global_rect().position.x,"bag left / loot right")
	_check(right.get_global_rect().end.x<=360.5,"two loot columns fit mobile width")
	var item:=ui.battle_loot_panel.find_child("LootItem_0",true,false) as Control
	await _tap_control(item,0)
	_check_eq(session.protagonist_inventory().used_backpack_slots,inventory.used_backpack_slots+1,"only tapped item enters bag")
	_check_eq(session.battle_loot().rows.size(),loot.rows.size()-1,"unselected loot remains")
	_check_eq(session.sim.world.world_time,before_time,"loot selection costs zero time")
	_check_eq(session.sim.world.entities[session.sim.world.party_encounter.protagonist_id].position,hero_position,"loot does not teleport hero")
	var repeat:Dictionary=session.take_battle_loot(int(loot.battle_id),str(first.instance_id))
	_check(not repeat.get("accepted",false),"duplicate loot packet is rejected")
	var save:String=session.save_session_json()
	_check(not save.is_empty(),"loot state saves")
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(save)
	_check(restored.get("accepted",false),"loot journal replays: "+str(restored.get("reason","")))
	ui._close_battle_loot()
	ui._maybe_open_battle_loot()
	_check(not ui.battle_loot_panel.visible,"closing does not immediately reopen same victory")
	ui.queue_free();await process_frame
