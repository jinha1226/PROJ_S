extends SceneTree

## Bounded Battleheart-control acceptance against the canonical DUO session.
## Normal map generation and public session APIs drive accepted actions.
## Isolated busy/empty-energy rejection probes restore their temporary changes;
## they never fabricate an accepted action. GUI input uses the engine input path.

const Session = preload("res://playtest/party_playtest_session.gd")
const SimCommand = preload("res://sim/sim_command.gd")
const PartyAction = preload("res://sim/party_action_command.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const ActiveEffects = preload("res://sim/abilities/active_effect_model.gd")

const WORLD_SEED := 44
const PERSONALITY_SEED := 20260828
# Genuine HEAD 3ae72d8 pack: schema 22, five-command combat journal, and verified
# successful load/save round-trip under the pre-change code.
const LEGACY_SAVE_PATH := "res://tests/fixtures/battleheart_schema22_combat.json"
const OPTIONAL_LEGACY_TOWN_SAVE_PATH := "/tmp/battle-root-valid-schema22.json"

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_case("valid_skills_damage_heal_move_time_energy_and_save", _valid_skills_damage_heal_move_time_energy_and_save)
	_case("invalid_skill_assessments_are_pure_and_action_wire_is_strict", _invalid_skill_assessments_are_pure_and_action_wire_is_strict)
	_case("actor_directives_are_isolated_and_basic_auto_has_no_actives", _actor_directives_are_isolated_and_basic_auto_has_no_actives)
	_case("energy_does_not_refill_on_retreat_or_disengage", _energy_does_not_refill_on_retreat_or_disengage)
	_case("shove_and_single_party_batch", _shove_and_single_party_batch)
	await _mobile_manual_dock_target_cancel_and_doublecast()
	_case("prechange_schema22_save_migrates", _prechange_schema22_save_migrates)
	if failures.is_empty():
		print("PASS battleheart MVP acceptance: 7 bounded cases")
	else:
		for failure in failures: printerr("FAIL ", failure)
		print("FAIL battleheart MVP acceptance: ", failures.size(), " failures")
	quit(1 if not failures.is_empty() else 0)

func _case(label: String, callback: Callable) -> void:
	var before := failures.size()
	var result = callback.call()
	if result != true and failures.size() == before: failures.append(label + " did not return true")
	if failures.size() == before: print("PASS battleheart :: ", label)

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _check_eq(got: Variant, expected: Variant, message: String) -> void:
	if got != expected: failures.append("%s (expected %s, got %s)" % [message, str(expected), str(got)])

func _new_engaged_duo():
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.DUO_SCENARIO_ID)
	if session.sim == null:
		_check(false, "DUO session did not initialize"); return null
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var best: Dictionary = {}
	for enemy_id_value in state.enemy_ids:
		var enemy_id := int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id): continue
		var enemy_position: Vector2i = session.sim.world.entities[enemy_id].position
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var path: Dictionary = session.find_exploration_path(hero_id, enemy_position + delta)
			if bool(path.get("found", false)) and (best.is_empty() or path.path.size() < best.path.size()): best = path
		if not best.is_empty() and best.path.size() <= 4: break
	if best.is_empty():
		_check(false, "normal generated DUO map has no route to an encounter"); return null
	for value in best.path.slice(1):
		var step: Dictionary = session.commit_exploration(SimCommand.move_to(hero_id, value))
		if not bool(step.get("accepted", false)):
			_check(false, "normal route step rejected: %s" % str(step.get("reason", ""))); return null
		if str(session.party_status().get("safe_phase", "")) == "CONTACT": break
	_check_eq(session.party_status().get("safe_phase", ""), "CONTACT", "generated route reaches contact")
	if str(session.party_status().get("safe_phase", "")) != "CONTACT": return null
	var companion_id := int(state.party_member_ids[1])
	var preview: Dictionary = session.preview_deployment("LINE", [companion_id])
	_check(bool(preview.get("accepted", false)), "normal deployment preview accepts companion")
	if not bool(preview.get("accepted", false)): return null
	var committed: Dictionary = session.commit_deployment()
	_check(bool(committed.get("accepted", false)), "normal deployment enters combat")
	_check_eq(session.party_status().get("safe_phase", ""), "ENGAGED", "generated deployment enters ENGAGED")
	return session

func _member(session, actor_id: int): return session.sim.world.party_encounter.member(actor_id)

func _active_skill_rows(session, actor_id: int) -> Array:
	if not session.has_method("active_skill_rows"):
		_check(false, "missing active_skill_rows(actor_id) API"); return []
	var rows = session.active_skill_rows(actor_id)
	_check(rows is Array, "active_skill_rows returns Array")
	return rows if rows is Array else []

func _find_valid_target(session, actor_id: int, skill_id: String) -> Dictionary:
	var state = session.sim.world.party_encounter
	for enemy_id_value in state.enemy_ids:
		var target_id := int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(target_id): continue
		var assessment: Dictionary = session.active_skill_assessment(actor_id, skill_id, target_id)
		if bool(assessment.get("accepted", false)): return {"target_id": target_id, "assessment": assessment}
	return {}

func _basic_auto_tick(session) -> bool:
	var planning: Dictionary = session.prepare_autonomous_party_turn()
	if not bool(planning.get("commit_ready", false)): return false
	var result: Dictionary = session.commit_turn()
	_check(bool(result.get("accepted", false)), "existing basic autonomous turn remains executable")
	return bool(result.get("accepted", false))

func _damage_event_count(session, target_id: int) -> int:
	var count := 0
	for event in session.sim.world.events:
		if int(event.target_id) == target_id and str(event.type).begins_with("combat.") and str(event.type).ends_with("_damage"): count += 1
	return count

func _valid_skills_damage_heal_move_time_energy_and_save() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.party_member_ids[1])
	var hero_rows := _active_skill_rows(session, hero_id)
	var companion_rows := _active_skill_rows(session, companion_id)
	var hero_ids: Array[String] = []
	var companion_ids: Array[String] = []
	for row in hero_rows:
		if row is Dictionary:
			hero_ids.append(str(row.get("skill_id", "")))
			for key in ["skill_id", "label", "cost", "energy", "max_energy", "can_select"]: _check(row.has(key), "hero skill row exposes %s" % key)
	for row in companion_rows:
		if row is Dictionary: companion_ids.append(str(row.get("skill_id", "")))
	_check_eq(hero_ids, ["STRIKE", "SHOVE"], "protagonist uses VANGUARD_V1")
	_check_eq(companion_ids, ["FIREBOLT", "MEND"], "companion uses SUPPORT_V1")
	_check_eq(int(_member(session, hero_id).energy), 12, "protagonist starts at 12 energy")
	_check_eq(int(_member(session, companion_id).energy), 12, "companion starts at 12 energy")

	# Let existing basic combat close distance; this uses a generated encounter
	# step rather than privately placing an adjacent target.
	var hero_target := {}
	for _attempt in range(4):
		hero_target = _find_valid_target(session, hero_id, "STRIKE")
		if not hero_target.is_empty(): break
		if not _basic_auto_tick(session): break
	_check(not hero_target.is_empty(), "generated combat exposes a real STRIKE target")
	if hero_target.is_empty(): return false
	var target_id := int(hero_target.target_id)
	var before_time := int(session.sim.world.world_time)
	var before_energy := int(_member(session, hero_id).energy)
	var before_health := int(session.sim.world.entities[target_id].health)
	var before_damage_events := _damage_event_count(session, target_id)
	var before_body = session.sim.world.body_of(target_id)
	var strike: Dictionary = session.use_active_skill(hero_id, "STRIKE", target_id)
	_check(bool(strike.get("accepted", false)), "protagonist STRIKE commits")
	if not bool(strike.get("accepted", false)): return false
	_check_eq(int(_member(session, hero_id).energy), before_energy - 3, "STRIKE costs exactly 3 energy")
	_check_eq(int(session.sim.world.world_time) - before_time, int(strike.get("time_cost", -1)), "STRIKE reports its canonical elapsed time")
	_check(int(strike.get("time_cost", 0)) >= 100, "STRIKE elapsed time covers skill and ready-ally actions")
	_check(int(session.sim.world.entities[target_id].health) < before_health, "STRIKE damages canonical enemy")
	_check(_damage_event_count(session, target_id) > before_damage_events, "STRIKE emits canonical combat damage")
	var after_body = session.sim.world.body_of(target_id)
	_check(after_body != null and before_body != null and (after_body.revision > before_body.revision or after_body.wounds.size() > before_body.wounds.size()), "STRIKE updates canonical body ledger")
	_check_eq(session.sim.world.world_state_error(), "", "STRIKE leaves world valid")
	var companion_target := _find_valid_target(session, companion_id, "FIREBOLT")
	_check(not companion_target.is_empty(), "generated combat exposes a real FIREBOLT target")
	if companion_target.is_empty(): return false
	var fire_target := int(companion_target.target_id)
	var fire_time := int(session.sim.world.world_time)
	var fire_energy := int(_member(session, companion_id).energy)
	var fire_health := int(session.sim.world.entities[fire_target].health)
	var fire_result: Dictionary = session.use_active_skill(companion_id, "FIREBOLT", fire_target)
	_check(bool(fire_result.get("accepted", false)), "companion FIREBOLT commits")
	if bool(fire_result.get("accepted", false)):
		_check_eq(int(_member(session, companion_id).energy), fire_energy - 3, "FIREBOLT costs exactly 3 energy")
		_check_eq(int(session.sim.world.world_time) - fire_time, int(fire_result.get("time_cost", -1)), "FIREBOLT reports its canonical elapsed time")
		_check(int(fire_result.get("time_cost", 0)) >= 120, "FIREBOLT elapsed time covers skill and ready-ally actions")
		_check(int(session.sim.world.entities[fire_target].health) < fire_health, "FIREBOLT damages canonical enemy")
		_check_eq(session.sim.world.world_state_error(), "", "FIREBOLT leaves world valid")

	# Observe a real enemy hit before testing MEND; no HP is injected by the test.
	var heal_target := -1
	for _attempt in range(18):
		for candidate in [hero_id, companion_id]:
			var candidate_mend: Dictionary = session.active_skill_assessment(
				companion_id, "MEND", candidate)
			if bool(candidate_mend.get("accepted", false)):
				heal_target = candidate; break
		if heal_target > 0 or str(session.party_status().get("safe_phase", "")) != "ENGAGED": break
		_basic_auto_tick(session)
	_check(heal_target > 0, "normal enemy combat creates MEND-recoverable party damage")
	if heal_target > 0:
		var mend_assessment: Dictionary = session.active_skill_assessment(companion_id, "MEND", heal_target)
		_check(bool(mend_assessment.get("accepted", false)), "MEND accepts observed recoverable damage")
		if bool(mend_assessment.get("accepted", false)):
			var mend_energy := int(_member(session, companion_id).energy)
			var mend_time := int(session.sim.world.world_time)
			var mend_event_start := int(session.sim.world.events.size())
			var mend: Dictionary = session.use_active_skill(companion_id, "MEND", heal_target)
			_check(bool(mend.get("accepted", false)), "companion MEND commits")
			if bool(mend.get("accepted", false)):
				var restored_magnitude := 0
				for event in session.sim.world.events.slice(mend_event_start):
					if str(event.type) == "health.restored" and int(event.target_id) == heal_target \
							and str(event.data.get("kind", "")) == "ACTIVE_SKILL":
						restored_magnitude += int(event.magnitude)
				_check(restored_magnitude > 0, "MEND emits positive canonical active-skill healing")
				_check_eq(int(_member(session, companion_id).energy), mend_energy - 4, "MEND costs exactly 4 energy")
				_check_eq(int(session.sim.world.world_time) - mend_time, int(mend.get("time_cost", -1)), "MEND reports its canonical elapsed time")
				_check(int(mend.get("time_cost", 0)) >= 120, "MEND elapsed time covers skill and ready-ally actions")
				_check_eq(session.sim.world.world_state_error(), "", "MEND leaves world valid")

	var encoded := session.save_session_json()
	var restored = Session.new(1, 2, Session.SOLO_FIXTURE_SCENARIO_ID)
	var loaded: Dictionary = restored.load_session_json(encoded)
	_check(bool(loaded.get("accepted", false)), "post-skill save/load is accepted")
	if bool(loaded.get("accepted", false)): _check_eq(restored.sim.snapshot(), session.sim.snapshot(), "post-skill save/load preserves canonical state")
	return true

func _invalid_skill_assessments_are_pure_and_action_wire_is_strict() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var baseline := session.save_session_json()
	var friendly: Dictionary = session.active_skill_assessment(hero_id, "STRIKE", companion_id)
	_check(not bool(friendly.get("accepted", false)), "enemy skill rejects friendly target")
	_check_eq(session.save_session_json(), baseline, "friendly rejection is mutation-pure")
	var heal_enemy: Dictionary = session.active_skill_assessment(companion_id, "MEND", enemy_id)
	_check(not bool(heal_enemy.get("accepted", false)), "MEND rejects enemy target")

	var far_id := -1
	var far_distance := -1
	for value in state.enemy_ids:
		var candidate_id := int(value)
		var distance := maxi(absi(session.sim.world.entities[candidate_id].position.x - session.sim.world.entities[companion_id].position.x), absi(session.sim.world.entities[candidate_id].position.y - session.sim.world.entities[companion_id].position.y))
		if distance > far_distance: far_id = candidate_id; far_distance = distance
	var out_of_range: Dictionary = session.active_skill_assessment(companion_id, "FIREBOLT", far_id)
	_check(not bool(out_of_range.get("accepted", false)), "FIREBOLT rejects out-of-range target")
	_check_eq(session.save_session_json(), baseline, "generated target rejection is mutation-pure")
	var geometry_caster := {"id":1,"team":"PARTY","position":Vector2i(1, 1),
		"hp":100,"max_hp":100,"energy":12,"skills":["FIREBOLT"]}
	var geometry_target := {"id":2,"team":"ENEMY","position":Vector2i(8, 1),
		"hp":100,"max_hp":100,"energy":0}
	var geometry_actors: Array = [geometry_caster, geometry_target]
	var pure_range: Dictionary = ActiveEffects.assess("FIREBOLT", geometry_caster,
		geometry_target, geometry_actors, {}, Rect2i(0, 0, 12, 12))
	_check_eq(str(pure_range.get("reason", "")), "사거리 밖입니다.", "pure geometry rejects FIREBOLT beyond range")
	geometry_target.position = Vector2i(4, 1)
	var pure_los: Dictionary = ActiveEffects.assess("FIREBOLT", geometry_caster,
		geometry_target, geometry_actors, {Vector2i(2, 1):true}, Rect2i(0, 0, 12, 12))
	_check_eq(str(pure_los.get("reason", "")), "벽에 가려져 있습니다.", "pure geometry rejects blocked FIREBOLT line")

	# Narrow rejection-only fixture. This avoids coupling insufficient-resource
	# validation to whether this generated encounter ends and refills energy.
	var energy_member = _member(session, companion_id)
	var energy_before := int(energy_member.energy)
	var energy_busy_before := int(energy_member.busy_until)
	energy_member.energy = 0
	energy_member.busy_until = int(session.sim.world.world_time)
	var energy_snapshot := session.save_session_json()
	var low_energy: Dictionary = session.active_skill_assessment(companion_id, "MEND", companion_id)
	_check(not bool(low_energy.get("accepted", false)), "insufficient energy rejects MEND")
	_check_eq(str(low_energy.get("reason", "")), "active_skill_energy_insufficient", "session reports canonical insufficient-energy reason")
	_check_eq(session.save_session_json(), energy_snapshot, "energy rejection is mutation-pure")
	energy_member.energy = energy_before
	energy_member.busy_until = energy_busy_before

	# Narrow rejection-only fixture: mark an actor busy without creating an
	# accepted skill or combat result.
	var member = _member(session, companion_id)
	var old_busy := int(member.busy_until)
	member.busy_until = int(session.sim.world.world_time) + 1
	var busy_snapshot := session.save_session_json()
	var busy: Dictionary = session.active_skill_assessment(companion_id, "MEND", companion_id)
	_check(not bool(busy.get("accepted", false)), "busy actor rejects active skill")
	_check(str(busy.get("reason", "")).contains("busy") or str(busy.get("reason", "")).contains("준비"), "busy reason is explicit")
	_check_eq(session.save_session_json(), busy_snapshot, "busy rejection is mutation-pure")
	member.busy_until = old_busy

	var legacy_hold := {"type":"HOLD","actor_id":"1","destination":[-1,-1],"target_id":"-1"}
	_check_eq(PartyAction.wire_error(legacy_hold), "", "legacy four-key HOLD remains valid")
	var missing_skill := {"type":"SKILL","actor_id":"1","destination":[-1,-1],"target_id":"3"}
	_check(PartyAction.wire_error(missing_skill) != "", "SKILL without skill_id is rejected")
	var unknown_skill := missing_skill.duplicate(true); unknown_skill.skill_id = "NOT_A_SKILL"
	_check(PartyAction.wire_error(unknown_skill) != "", "unknown SKILL id is rejected")
	return true

func _actor_directives_are_isolated_and_basic_auto_has_no_actives() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.party_member_ids[1])
	_check_eq(session.actor_command_status(hero_id).get("command_id", ""), "FOLLOW", "hero starts FOLLOW")
	_check_eq(session.actor_command_status(companion_id).get("command_id", ""), "FOLLOW", "companion starts FOLLOW")
	var stop: Dictionary = session.issue_actor_command(hero_id, "STOP_ATTACK")
	_check(bool(stop.get("accepted", false)), "hero STOP_ATTACK accepted")
	_check_eq(session.actor_command_status(hero_id).get("command_id", ""), "STOP_ATTACK", "hero directive visible")
	_check_eq(session.actor_command_status(companion_id).get("command_id", ""), "FOLLOW", "hero directive isolated")
	var hold: Dictionary = session.issue_actor_command(companion_id, "HOLD_POSITION")
	_check(bool(hold.get("accepted", false)), "companion HOLD_POSITION accepted")
	_check_eq(session.actor_command_status(companion_id).get("command_id", ""), "HOLD_POSITION", "companion directive visible")
	_check_eq(session.actor_command_status(hero_id).get("command_id", ""), "STOP_ATTACK", "companion directive isolated")
	var target_id := int(session.party_status().get("visible_enemy_ids", [])[0])
	var target_assessment: Dictionary = session.actor_command_assessment(hero_id, "ATTACK_TARGET", target_id)
	_check(bool(target_assessment.get("accepted", false)), "actor target directive previews")
	var target_result: Dictionary = session.issue_actor_command(hero_id, "ATTACK_TARGET", target_id)
	_check(bool(target_result.get("accepted", false)), "actor target directive commits")
	_check_eq(session.actor_command_status(hero_id).get("target_id", -1), target_id, "target belongs to named actor")

	var before_events: int = int(session.sim.world.events.size())
	var planning: Dictionary = session.prepare_autonomous_party_turn()
	_check(bool(planning.get("commit_ready", false)), "basic auto planner stays ready")
	for row in planning.get("preview", {}).get("actor_rows", []):
		if row is Dictionary: _check(str(row.get("action", {}).get("type", "")) != "SKILL", "AI never queues active SKILL")
	var commit: Dictionary = session.commit_turn()
	_check(bool(commit.get("accepted", false)), "basic auto combat still commits")
	for event in session.sim.world.events.slice(before_events): _check(str(event.type) != "action.skill", "basic auto emits no active skill")
	return true

func _energy_does_not_refill_on_retreat_or_disengage() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	var target := _find_valid_target(session, hero_id, "STRIKE")
	for _attempt in range(3):
		if not target.is_empty(): break
		_basic_auto_tick(session); target = _find_valid_target(session, hero_id, "STRIKE")
	_check(not target.is_empty(), "retreat fixture obtains valid STRIKE")
	if target.is_empty(): return false
	var used: Dictionary = session.use_active_skill(hero_id, "STRIKE", int(target.target_id))
	_check(bool(used.get("accepted", false)), "retreat fixture spends energy")
	var after_skill := int(_member(session, hero_id).energy)
	_check_eq(after_skill, 9, "retreat fixture has 9 energy")
	var actor_retreat: Dictionary = session.issue_actor_command(hero_id, "RETREAT")
	_check(bool(actor_retreat.get("accepted", false)), "actor RETREAT accepted")
	_check_eq(int(_member(session, hero_id).energy), after_skill, "actor RETREAT never refills energy")
	var party_retreat: Dictionary = session.issue_party_command("RETREAT")
	_check(bool(party_retreat.get("accepted", false)), "legacy party RETREAT remains accepted")
	_check_eq(int(_member(session, hero_id).energy), after_skill, "party RETREAT never refills energy")
	for _attempt in range(12):
		if str(session.party_status().get("safe_phase", "")) != "ENGAGED": break
		if not _basic_auto_tick(session): break
	if str(session.party_status().get("safe_phase", "")) in ["GROUPED", "GROUPED_COMPLETE"]:
		_check_eq(int(_member(session, hero_id).energy), after_skill, "disengage without victory does not refill")
	return true

func _shove_and_single_party_batch()->bool:
	var session=_new_engaged_duo()
	if session==null:return false
	var state=session.sim.world.party_encounter
	var hero_id:int=state.protagonist_id
	var target:Dictionary={}
	for attempt in range(6):
		target=_find_valid_target(session,hero_id,"SHOVE")
		if not target.is_empty():break
		if not _basic_auto_tick(session):break
	_check(not target.is_empty(),"generated encounter has legal SHOVE target")
	if target.is_empty():return false
	var target_id:int=target.target_id
	var assessment:Dictionary=session.active_skill_assessment(hero_id,"SHOVE",target_id)
	var landing:Vector2i=assessment.destination
	var before_time:int=session.sim.world.world_time
	var result:Dictionary=session.use_active_skill(hero_id,"SHOVE",target_id)
	_check(bool(result.get("accepted",false)),"SHOVE canonical action commits")
	if not result.get("accepted",false):return false
	var skill_root_id:=-1
	var actor_counts:Dictionary={}
	var pushed:=false
	for id in result.get("event_ids",[]):
		var event=session.sim.world.event_by_id(int(id))
		if event.type=="action.skill":skill_root_id=int(event.id)
		if event.actor_id in state.active_party_member_ids and event.type in [
				"action.skill","action.hold","action.move","action.melee_attack"]:
			actor_counts[event.actor_id]=int(actor_counts.get(event.actor_id,0))+1
		if event.type=="action.move" and event.actor_id==target_id \
				and event.cause_id==skill_root_id and event.position==landing:pushed=true
	_check(pushed,"SHOVE emits canonical movement to assessed landing")
	_check_eq(actor_counts.get(hero_id,0),1,"caster gets exactly one action, not skill plus melee")
	var longest:=100
	for id in actor_counts:
		_check_eq(actor_counts[id],1,"each acting ally gets one basic action")
		longest=maxi(longest,int(state.member(id).busy_until)-before_time)
	_check(actor_counts.size()>=2,"ready companion acts during player's skill step")
	_check_eq(int(result.time_cost),longest,"one timeline uses longest actor cost, not sum")
	_check_eq(session.sim.world.world_state_error(),"","SHOVE preserves body and position history")
	var loaded=Session.new()
	_check(bool(loaded.load_session_json(session.save_session_json()).get("accepted",false)),
		"SHOVE movement survives save replay")
	return true

func _mobile_manual_dock_target_cancel_and_doublecast() -> void:
	for width in [360, 390]:
		root.size = Vector2i(width, 640)
		# Match logical and physical test coordinates, rather than comparing a
		# stretched 450px project canvas against a 360px native window.
		root.content_scale_size = Vector2i(width, 640)
		var session = _new_engaged_duo()
		if session == null: continue
		var ui := Sandbox.new()
		ui.size = Vector2(width, 640)
		root.add_child(ui)
		ui.initialize_for_headless_test(session, true)
		ui.set_process(false)
		await process_frame; await process_frame
		var dock = ui.cards
		if dock == null:
			failures.append("mobile dock missing at %dpx" % width)
			ui.queue_free(); await process_frame; continue
		_check(dock.get_global_rect().end.x <= float(width) + 0.5,
			"manual dock remains inside %dpx viewport" % width)
		for child in dock.find_children("ActorSkill_*","Button",true,false):
			_check(child.size.y>=48 and child.size.x>=48,"portrait skill touch target >=48px")
		_check(ui.find_child("ManualActorSelector",true,false)==null,"no actor dropdown required")
		var state = session.sim.world.party_encounter
		var companion_id := int(state.party_member_ids[1])
		var target := _find_valid_target(session, companion_id, "FIREBOLT")
		for _attempt in range(4):
			if not target.is_empty(): break
			if not _basic_auto_tick(session): break
			target = _find_valid_target(session, companion_id, "FIREBOLT")
		_check(not target.is_empty(), "mobile fixture has FIREBOLT target")
		if target.is_empty(): ui.queue_free(); await process_frame; continue
		ui.autonomous_battle_clock.paused = false
		ui._on_manual_actor_selected(companion_id)
		await process_frame; await process_frame
		var skill_button := ui.find_child("ActorSkill_%d_FIREBOLT"%companion_id, true, false) as Button
		var portrait:=ui.find_child("MemberCard%d"%companion_id,true,false) as Control
		if skill_button!=null and portrait!=null:
			_check(skill_button.get_global_rect().end.y<=portrait.get_global_rect().position.y,
				"active skill is above its own portrait")
		_check(skill_button != null, "FIREBOLT button exists at %dpx" % width)
		if skill_button != null: await _tap_control(skill_button, 100 + width)
		_check_eq(str(ui._battle_target_mode), "ACTIVE_SKILL", "skill tap enters target mode")
		_check(bool(ui.autonomous_battle_clock.paused), "skill mode pauses auto combat")
		await process_frame; await process_frame
		var cancel_button := ui.find_child("PortraitBattleCancel", true, false) as Button
		_check(cancel_button != null, "target Cancel button exists at %dpx" % width)
		if cancel_button != null: await _tap_control(cancel_button, 200 + width)
		_check(str(ui._battle_target_mode).is_empty(), "cancel exits target mode")
		_check(not bool(ui.autonomous_battle_clock.paused), "cancel restores running auto state")
		ui.autonomous_battle_clock.paused = true
		ui._on_manual_skill_selected(companion_id, "FIREBOLT", "화염탄"); ui._cancel_battle_targeting("취소")
		_check(bool(ui.autonomous_battle_clock.paused), "cancel preserves paused auto state")
		var before_time := int(session.sim.world.world_time)
		var before_energy := int(_member(session, companion_id).energy)
		ui.autonomous_battle_clock.paused = false
		ui._on_manual_skill_selected(companion_id, "FIREBOLT", "화염탄")
		ui._commit_battle_target(int(target.target_id)); ui._commit_battle_target(int(target.target_id))
		_check_eq(int(_member(session, companion_id).energy), before_energy - 3, "double confirmation spends one FIREBOLT")
		_check(int(session.sim.world.world_time) - before_time >= 120, "double confirmation advances one canonical action")
		ui.queue_free(); await process_frame

func _tap_control(control: Control, _touch_index: int) -> void:
	var center := control.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0; press.pressed = true; press.position = center
	# Input performs mobile mouse-from-touch emulation for BaseButton; direct
	# Viewport.push_input bypasses that input-device translation in this test.
	Input.parse_input_event(press); await process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0; release.pressed = false; release.position = center
	Input.parse_input_event(release); await process_frame; await process_frame

func _prechange_schema22_save_migrates() -> bool:
	var fixture_paths: Array[String] = [LEGACY_SAVE_PATH]
	if FileAccess.file_exists(OPTIONAL_LEGACY_TOWN_SAVE_PATH):
		fixture_paths.append(OPTIONAL_LEGACY_TOWN_SAVE_PATH)
	for fixture_path in fixture_paths:
		if not FileAccess.file_exists(fixture_path):
			_check(false, "missing genuine prechange fixture: " + fixture_path); continue
		var file := FileAccess.open(fixture_path, FileAccess.READ)
		var encoded := file.get_as_text(); file.close()
		var restored = Session.new(1, 2, Session.SOLO_FIXTURE_SCENARIO_ID)
		var loaded: Dictionary = restored.load_session_json(encoded)
		_check(bool(loaded.get("accepted", false)), "schema22 prechange save migrates (%s): %s" % [fixture_path, str(loaded.get("reason", ""))])
		if bool(loaded.get("accepted", false)):
			for row in restored.sim.world.party_encounter.member_rows.values():
				_check_eq(int(row.energy), 12, "migrated member starts at max energy")
				_check(str(row.skill_loadout_id) in ["VANGUARD_V1", "SUPPORT_V1"], "migrated member has valid loadout")
	return true
