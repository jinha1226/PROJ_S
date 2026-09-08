extends "res://tests/battle_mobile_loot_acceptance.gd"

func _run()->void:
	root.size=Vector2i(360,640);root.content_scale_size=Vector2i(360,640)
	# Continue a real, versioned pre-change encounter through the new scheduler.
	# The generated opening is covered separately (including defeat).
	var session=Session.new()
	var loaded:Dictionary=session.load_session_json(FileAccess.get_file_as_string(LEGACY_SAVE_PATH))
	_check(loaded.get("accepted",false),"legacy encounter loads into individual combat")
	if not loaded.get("accepted",false):quit(1);return
	var flow=session.individual_battle
	for index in range(180):
		var next:Dictionary=flow.next_event()
		if next.is_empty():break
		var actor_id:int=next.actor_id
		if actor_id in session.sim.world.party_encounter.active_party_member_ids:
			var skills:Array=session.active_skill_rows(actor_id);skills.reverse()
			for skill in skills:
				if not skill.can_select or str(skill.skill_id)=="SHOVE":continue
				var target:=_find_valid_target(session,actor_id,str(skill.skill_id))
				if target.is_empty():continue
				if flow.reserve(actor_id,str(skill.skill_id),int(target.target_id)).get("accepted",false):break
		var result:Dictionary=flow.commit()
		_check(result.get("accepted",false),"individual victory step: "+str(result.get("reason","")))
		if not result.get("accepted",false):break
	print("INDIVIDUAL LOOT phase=",session.sim.world.party_encounter.safe_phase)
	_check_eq(session.sim.world.party_encounter.safe_phase,"GROUPED_COMPLETE","victory automatically regroups")
	var loot:Dictionary=session.battle_loot()
	_check(not loot.rows.is_empty(),"individual victory produces selectable loot")
	if not loot.rows.is_empty():await _loot_controls(session,loot)
	for failure in failures:printerr("FAIL ",failure)
	print("PASS individual loot acceptance" if failures.is_empty() else "FAIL individual loot: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)
