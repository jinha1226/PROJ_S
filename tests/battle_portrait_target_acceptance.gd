extends "res://tests/battle_mobile_loot_acceptance.gd"

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	root.size=Vector2i(360,640);root.content_scale_size=Vector2i(360,640)
	var ui:=Sandbox.new();ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame;await process_frame
	var party=session.sim.world.party_encounter
	var actor_id:int=party.protagonist_id
	var targets:Array=session.party_status().visible_enemy_ids
	_check(targets.size()>=2,"multiple targets for hover switching")
	var first:int=targets[0];var second:int=targets[1]
	var portrait:=ui.cards.find_child("MemberCard%d"%actor_id,true,false) as Control
	var first_card:=ui.battle_enemy_strip.row.get_node("EnemyPortrait%d"%first) as Control
	var second_card:=ui.battle_enemy_strip.row.get_node("EnemyPortrait%d"%second) as Control
	_check(first_card.get_global_rect().position.y<portrait.get_global_rect().position.y,"enemy portraits above allies")
	_check(ui.grid.size.y>250,"map remains usable at 360 x 640")
	_check(ui.cards.get_global_rect().end.x<=360.5,"portrait controls fit mobile width")
	var journal_count:int=session.command_journal.size()
	_touch(ui,0,portrait.get_global_rect().get_center(),true)
	_motion(first_card.get_global_rect().get_center())
	_check_eq(ui.grid.target_preview_id,first,"hover highlights matching map enemy before release")
	_check_eq(session.command_journal.size(),journal_count,"hover alone never commits")
	var card_instance:=first_card.get_instance_id()
	ui._refresh_individual_battle_surface()
	_check_eq(ui.battle_enemy_strip.row.get_node("EnemyPortrait%d"%first).get_instance_id(),
		card_instance,"refresh preserves held portrait identity and ordering")
	_motion(second_card.get_global_rect().get_center())
	_check_eq(ui.grid.target_preview_id,second,"hover switches map target immediately")
	_touch(ui,0,second_card.get_global_rect().get_center(),false)
	_check_eq(session.actor_command_status(actor_id).target_id,second,"portrait drop commits selected target")
	_check_eq(ui.grid.target_preview_id,-1,"release clears transient preview")
	await process_frame;await process_frame
	# A second finger cancels and clears both presentation surfaces.
	portrait=ui.cards.find_child("MemberCard%d"%actor_id,true,false) as Control
	_touch(ui,0,portrait.get_global_rect().get_center(),true)
	_motion(first_card.get_global_rect().get_center())
	_touch(ui,1,Vector2(3,3),true)
	_check_eq(ui.grid.target_preview_id,-1,"multitouch cancels map preview")
	_touch(ui,1,Vector2(3,3),false);_touch(ui,0,first_card.get_global_rect().get_center(),false)
	await process_frame;await process_frame
	# Real skill button drag reserves through the same core assessment.
	var caster:int=party.active_party_member_ids[1]
	var valid:Dictionary={}
	for attempt in range(24):
		for id in targets:
			if session.individual_battle.assessment(caster,"FIREBOLT",id).get("accepted",false):
				valid={"target_id":id};break
		if not valid.is_empty():break
		if not session.individual_battle.commit().get("accepted",false):break
	ui._refresh_individual_battle_surface()
	await process_frame;await process_frame
	if not valid.is_empty():
		var skill_button:=ui.cards.find_child("ActorSkill_%d_FIREBOLT"%caster,true,false) as Control
		var card:=ui.battle_enemy_strip.row.get_node("EnemyPortrait%d"%int(valid.target_id)) as Control
		var before_time:int=session.sim.world.world_time
		_touch(ui,0,skill_button.get_global_rect().get_center(),true)
		_motion(card.get_global_rect().get_center())
		_check(ui.battle_drag.target_valid,"skill preview uses authoritative assessment")
		_touch(ui,0,card.get_global_rect().get_center(),false)
		_check_eq(session.individual_battle.queued(caster).get("target_id",-1),int(valid.target_id),"skill drop reserves exact target")
		_check_eq(session.sim.world.world_time,before_time,"skill reservation costs no time")
	else:_check(false,"FIREBOLT target fixture exists")
	await process_frame;await process_frame
	# Wrong-faction drop previews in red and must never reserve an attack.
	var skill_button:=ui.cards.find_child("ActorSkill_%d_FIREBOLT"%caster,true,false) as Control
	portrait=ui.cards.find_child("MemberCard%d"%actor_id,true,false) as Control
	journal_count=session.command_journal.size()
	_touch(ui,0,skill_button.get_global_rect().get_center(),true)
	_motion(portrait.get_global_rect().get_center())
	_check(not ui.grid.target_preview_valid,"invalid faction has red map preview")
	_touch(ui,0,portrait.get_global_rect().get_center(),false)
	_check_eq(session.command_journal.size(),journal_count,"invalid faction never commits")
	await process_frame;await process_frame
	# A stale portrait cannot target a now-dead enemy. Isolated negative probe:
	# restore the fixture fields before any canonical operation follows.
	portrait=ui.cards.find_child("MemberCard%d"%actor_id,true,false) as Control
	first_card=ui.battle_enemy_strip.row.get_node_or_null("EnemyPortrait%d"%first) as Control
	if first_card!=null:
		var profile=session.sim.world.combatant_states[first]
		var original_life:String=profile.life_state
		_touch(ui,0,portrait.get_global_rect().get_center(),true)
		profile.life_state="DEAD"
		_motion(first_card.get_global_rect().get_center())
		_touch(ui,0,first_card.get_global_rect().get_center(),false)
		profile.life_state=original_life
		_check_eq(session.command_journal.size(),journal_count,"stale dead target never commits")
	ui.queue_free();await process_frame
	await _mobile_manual_dock_target_cancel_and_doublecast()
	for failure in failures:printerr("FAIL ",failure)
	print("PASS portrait target acceptance" if failures.is_empty() else "FAIL portrait targets")
	quit(0 if failures.is_empty() else 1)

func _motion(position:Vector2)->void:
	var event:=InputEventScreenDrag.new();event.index=0;event.position=position
	Input.parse_input_event(event);Input.flush_buffered_events()
