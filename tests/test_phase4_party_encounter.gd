extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Plan = preload("res://sim/party_turn_plan.gd")
const Simulator = preload("res://sim/simulator.gd")
const WorldState = preload("res://sim/world_state.gd")
const PersonalRelation = preload("res://sim/personal_relation.gd")
const TerrainRegistry = preload("res://sim/terrain_registry.gd")
const EnemyAwareness = preload("res://sim/enemy_awareness_state.gd")

func test_grouped_members_are_exposed_but_do_not_occupy_or_block() -> bool:
	var session = Session.new(77,88); var world=session.sim.world; var state=world.party_encounter
	check_eq(world.occupying_entities_at(state.group_anchor).size(),1,"one exploration occupant")
	check_eq(world.exposed_entities_at(state.group_anchor).size(),3,"three grouped exposures")
	check_eq(world.blocking_entity_at(state.group_anchor).id,state.protagonist_id,"only protagonist blocks")
	var cards=session.party_cards(); check_eq(cards.size(),3,"three cards")
	for row in cards: check(bool(row.element_exposure.applicable),"grouped exposure applicable")
	var observation=session.observe_party_world(); var actors:=0
	for cell in observation.cells: actors += cell.actors.size()
	check_eq(actors,3,"protagonist and two presentation followers render before contact")
	check_eq(world.occupying_entities_at(state.group_anchor).size(),1,
		"presentation followers do not become authoritative occupants")
	check_eq(world.blocking_entity_at(state.group_anchor).id,state.protagonist_id,
		"presentation followers never become blockers")
	return finish()

func test_generic_sim_commands_are_phase_gated_and_transactional() -> bool:
	var grouped = Session.new(); var grouped_state = grouped.sim.world.party_encounter
	var grouped_before = grouped.sim.snapshot()
	var companion_result = grouped.sim.step(Command.wait(grouped_state.party_member_ids[1]))
	check(not companion_result.accepted, "grouped companion generic command rejected")
	check_eq(companion_result.reason, "party_protagonist_command_required", "grouped actor gate reason")
	check_eq(grouped.sim.snapshot(), grouped_before, "grouped actor gate exact no-op")

	var contact = Session.new(); var contact_state = contact.sim.world.party_encounter
	contact.commit_exploration(Command.wait(contact_state.protagonist_id))
	var engaged = _engaged()
	var defeated = Session.new(); var defeated_state = defeated.sim.world.party_encounter
	check(defeated.sim.world.bootstrap_set_fire(defeated_state.group_anchor, 100) != null, "phase gate defeat fixture")
	check(_prime_grouped_hazard_health(defeated, defeated_state.protagonist_id, 20),
		"phase gate defeat fixture uses canonical fire damage")
	check(defeated.sim.step(Command.wait(defeated_state.protagonist_id)).accepted, "exploration element death allowed")
	check_eq(defeated.party_status().safe_phase, "PARTY_DEFEATED", "defeat fixture terminal")

	for row in [["CONTACT", contact], ["ENGAGED", engaged], ["PARTY_DEFEATED", defeated]]:
		var label: String = row[0]; var session = row[1]; var status: Dictionary = session.party_status()
		var before: Dictionary = session.sim.snapshot(); var hero_id := int(status.protagonist_id)
		var preview = session.sim.preview(Command.wait(hero_id))
		check(not preview.accepted, "%s generic preview rejected" % label)
		check_eq(preview.reason, "party_specialized_flow_required", "%s stable phase gate reason" % label)
		var result = session.sim.step(Command.wait(hero_id))
		check(not result.accepted, "%s generic step rejected" % label)
		check_eq(result.reason, "party_specialized_flow_required", "%s step phase gate reason" % label)
		check_eq(session.sim.snapshot(), before, "%s generic command exact no-op" % label)
		check_eq(session.sim.world.step_index, int(before.step_index), "%s step unchanged" % label)
		check_eq(session.sim.world.world_time, int(before.world_time), "%s time unchanged" % label)
	return finish()

func test_detection_deployment_preview_purity_and_atomic_commit() -> bool:
	var session=Session.new(7,9); var protagonist=session.sim.world.party_encounter.protagonist_id
	var before=JSON.stringify(session.sim.snapshot()); var result=session.commit_exploration(Command.wait(protagonist))
	check(result.accepted,"wait accepted"); check_eq(session.party_status().safe_phase,"CONTACT","contact reached")
	check_eq(session.party_status().contact_kind,"PARTY_AMBUSH","radius branch")
	var snapshot=JSON.stringify(session.sim.snapshot()); var companions=session.sim.world.party_encounter.party_member_ids.slice(1)
	var plan:Dictionary
	for index in range(100): plan=session.preview_deployment("WEDGE",companions)
	check_eq(JSON.stringify(session.sim.snapshot()),snapshot,"deployment preview pure")
	check(plan.accepted,"formation accepted"); check_eq(plan.placements.size(),3,"three placements")
	var committed=session.commit_deployment(); check(committed.accepted,"deployment committed")
	check_eq(session.party_status().safe_phase,"ENGAGED","engaged")
	check_eq(session.sim.world.step_index,2,"one step detection plus one deployment")
	return finish()

func test_four_member_party_recruits_deploys_and_keeps_support_rear_unique() -> bool:
	var session=Session.new(44,20260828,"SHOWCASE_V1")
	var state=session.sim.world.party_encounter
	var recruitable:Array=session.party_status().recruitable_member_ids
	check_eq(recruitable.size(),1,"four-member fixture has one direct recruit")
	if recruitable.is_empty():return finish()
	check(session.recruit_companion(int(recruitable[0])).accepted,
		"third companion fills the fourth active slot")
	check_eq(state.active_party_member_ids.size(),4,
		"active party supports protagonist and three companions")
	check(session.commit_exploration_direction(Vector2i.RIGHT).accepted,
		"four-member fixture reaches contact")
	var companions:Array=session.available_companion_ids()
	var plan:Dictionary=session.preview_deployment("WEDGE",companions)
	check(plan.accepted,"four-member wedge accepted: %s"%str(plan.get("reason","missing")))
	check_eq(plan.placements.size(),4,"wedge places all four active members")
	var positions:Dictionary={}
	for row in plan.placements:positions[str(row.position)]=true
	check_eq(positions.size(),4,"four-member wedge positions are unique")
	if plan.placements.size()==4:
		var expected_rear:Vector2i=state.group_anchor-state.facing*2
		check_eq(plan.placements[3].position,[expected_rear.x,expected_rear.y],
			"third companion receives deterministic protected rear position")
	if plan.accepted:
		check(session.commit_deployment().accepted,"four-member deployment commits")
	check_eq(state.active_party_member_ids.size(),4,
		"deployment retains all four active members")
	check(session.sim.world.world_state_error().is_empty(),
		"four-member deployed world satisfies strict validation")
	return finish()

func test_deployment_reserved_diagonal_flanks_match_snapshot_projection() -> bool:
	var session = Session.new(7,9); var state = session.sim.world.party_encounter
	check(session.sim.world.bootstrap_set_terrain(Vector2i(6,6), "wall"), "first wedge wall fixture")
	check(session.sim.world.bootstrap_set_terrain(Vector2i(7,6), "wall"), "diagonal flank wall fixture")
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted, "wall fixture reaches contact")
	state = session.sim.world.party_encounter
	check_eq(state.facing, Vector2i.RIGHT, "contact faces right")
	var preview: Dictionary = session.preview_deployment("WEDGE", state.party_member_ids.slice(1))
	check(bool(preview.accepted), "wedge preview accepted with fallbacks")
	check_eq(preview.placements[1].placement, "fallback", "first blocked wedge cell falls back")
	check_eq(preview.placements[1].position, [6,7], "first fallback deterministic")
	check_eq(preview.placements[2].placement, "fallback", "reserved diagonal flank blocks second preset")
	check_eq(preview.placements[2].position, [8,7], "second fallback deterministic")
	check(session.commit_deployment().accepted, "fallback deployment commits")
	var snapshot: Dictionary = session.sim.snapshot()
	# WorldState's direct wire is intentionally strict about item integer types;
	# JSON number normalization belongs to the session transport boundary. This
	# test exercises canonical deployment projection, so restore the typed wire.
	var restored = WorldState.from_snapshot(snapshot)
	check(restored != null, "fallback snapshot restores")
	if restored != null:
		check_eq(restored.snapshot(), snapshot, "fallback snapshot round trip exact")
	return finish()

func test_party_turn_preview_is_pure_override_commits_and_stale_rejects() -> bool:
	var session=_engaged(); var state=session.sim.world.party_encounter; var hero=state.protagonist_id
	var destination=session.sim.world.entities[hero].position+Vector2i.RIGHT
	var direct=Action.move_to(hero,destination); var companion=state.party_member_ids[2]
	var first=session.begin_turn(direct); check(first.accepted,"turn preview")
	var base=JSON.stringify(session.sim.snapshot())
	for index in range(100): session.current_turn_preview()
	check_eq(JSON.stringify(session.sim.snapshot()),base,"turn preview byte pure")
	var overridden=session.override_companion(companion,Action.hold(companion)); check(overridden.accepted,"legal override never refused")
	var committed=session.commit_turn(); check(committed.accepted,"party batch committed")
	check(session.sim.world.party_encounter.member(companion).stress>0,"override stress committed")
	var stale_plan=session.sim.preview_party_turn(load("res://sim/party_turn_request.gd").new(Action.hold(hero),[]))
	session.sim.world.party_encounter.revision += 1
	var stale=session.sim.step_party_turn(stale_plan); check(not stale.accepted,"stale rejected"); check_eq(stale.reason,"stale_party_plan","stale reason")
	return finish()

func test_victory_automatically_regroups_in_the_killing_turn_and_fault_rolls_back() -> bool:
	var session=_engaged(); var state=session.sim.world.party_encounter; var hero=state.protagonist_id; var enemy=state.enemy_ids[0]
	var before=JSON.stringify(session.sim.snapshot()); var preview=session.sim.preview_party_turn(load("res://sim/party_turn_request.gd").new(Action.hold(hero),[]))
	session.sim.party_coordinator.fail_after_leaf_index=2; var failed=session.sim.step_party_turn(preview)
	check(not failed.accepted,"fault rejected"); check_eq(JSON.stringify(session.sim.snapshot()),before,"last leaf rollback exact")
	state=session.sim.world.party_encounter; hero=state.protagonist_id; enemy=state.enemy_ids[0]
	check(_relocate_with_move_events(session.sim, enemy,
		session.sim.world.entities[hero].position + Vector2i.RIGHT), "enemy fixture follows canonical move history")
	session.sim.world.entities[enemy].health=22
	var action=Action.melee(hero,enemy); session.begin_turn(action); var committed=session.commit_turn()
	check(committed.accepted,"killing turn accepted"); check_eq(session.party_status().safe_phase,"GROUPED_COMPLETE","victory automatically groups")
	var grouped_complete_snapshot:Dictionary=session.sim.snapshot()
	var grouped_complete_restored=WorldState.from_snapshot(grouped_complete_snapshot)
	check(grouped_complete_restored!=null,"grouped-complete typed snapshot restores")
	if grouped_complete_restored!=null:
		check_eq(grouped_complete_restored.snapshot(),grouped_complete_snapshot,
			"grouped-complete round trip")
	var event_types:Array=[]; for event in committed.event_ids: event_types.append(session.sim.world.event_by_id(event).type)
	check("party.victory" in event_types and "party.regroup_started" in event_types and "party.regroup_completed" in event_types,"same turn owns complete victory chain")
	var victory=session.sim.world.events.filter(func(event):return event.type=="party.victory")[0]
	var started=session.sim.world.events.filter(func(event):return event.type=="party.regroup_started")[0]
	check_eq(started.cause_id,victory.id,"regroup starts from victory cause")
	check_eq(started.step_index,victory.step_index,"victory and regroup same step")
	var occupants:=0; for y in range(15): for x in range(15): occupants+=session.sim.world.occupying_entities_at(Vector2i(x,y)).size()
	check_eq(occupants,1,"only protagonist occupies after regroup")
	return finish()

func test_automatic_regroup_runs_after_due_environment_tick_at_deployed_positions() -> bool:
	var session=_engaged(); var world=session.sim.world; var state=world.party_encounter
	var hero=state.protagonist_id; var companion=state.party_member_ids[1]; var enemy=state.enemy_ids[0]
	check(_relocate_with_move_events(session.sim,enemy,world.entities[hero].position+Vector2i.RIGHT),"enemy adjacent")
	world.entities[enemy].health=22
	var deployed_position:Vector2i=world.entities[companion].position; var health_before:int=world.entities[companion].health
	var ignition=world.emit_event("environment.ignited",-1,-1,deployed_position,100)
	var tile=world.tile_at(deployed_position); tile.fire=100; tile.fire_source_event_id=ignition.id; tile.fire_damage_eligible_time=world.world_time
	var request=Request.new(Action.melee(hero,enemy),[{"actor_id":companion,"action":Action.hold(companion)}])
	var result=session.sim.step_party_turn(session.sim.preview_party_turn(request))
	check(result.accepted,"killing turn with due environment tick accepted")
	check(world.entities[companion].health<health_before,"environment evaluates companion at deployed combat tile")
	check_eq(state.safe_phase,"GROUPED_COMPLETE","finalizer groups only after cadence")
	check_eq(world.entities[companion].position,state.group_anchor,"companion grouped after environment resolution")
	var damage_index:=-1; var regroup_index:=-1
	for index in range(world.events.size()):
		if world.events[index].type=="combat.fire_damage" and world.events[index].target_id==companion:damage_index=index
		if world.events[index].type=="party.regroup_started":regroup_index=index
	check(damage_index>=0 and regroup_index>damage_index,"environment damage precedes automatic regroup events")
	return finish()

func test_snapshot_v5_strict_xor_round_trip_and_v4_rejection() -> bool:
	var session=Session.new(); var snapshot:Dictionary=session.sim.snapshot()
	check_eq(snapshot.snapshot_version,9,"snapshot v9"); check_eq(snapshot.ruleset_version,"phase5-combat-status-lifecycle-v1","ruleset")
	var restored=WorldState.from_snapshot(snapshot)
	check(restored!=null,"typed party snapshot restores")
	if restored!=null:check_eq(restored.snapshot(),snapshot,"party round trip")
	var conflict=snapshot.duplicate(true); conflict.encounter_lab={}
	check_eq(WorldState.snapshot_restore_error(conflict),"encounter_mode_conflict","xor wire")
	var old=snapshot.duplicate(true); old.snapshot_version=7
	check_eq(WorldState.snapshot_restore_error(old),"unsupported_snapshot_version","no v6 migration")
	var noncanonical=snapshot.duplicate(true); noncanonical.party_encounter.revision=0
	check_eq(WorldState.snapshot_restore_error(noncanonical),"noncanonical_party_revision","party int64 strict")
	return finish()

func test_rehashed_party_and_deployment_forgery_never_executes() -> bool:
	var session = _engaged(); var state = session.sim.world.party_encounter; var hero = state.protagonist_id
	var original = session.sim.preview_party_turn(Request.new(Action.hold(hero), [])).to_dict()
	var variants: Array = []
	var cost_forgery = original.duplicate(true); cost_forgery.actor_rows[0].time_cost = 1; variants.append(_rehash(cost_forgery))
	var action_forgery = original.duplicate(true); action_forgery.actor_rows[0].action.type = "MOVE"
	action_forgery.actor_rows[0].action.destination = [8,7]; variants.append(_rehash(action_forgery))
	var target_forgery = original.duplicate(true); target_forgery.actor_rows[0].action.type = "MELEE"
	target_forgery.actor_rows[0].action.target_id = str(state.enemy_ids[0]); variants.append(_rehash(target_forgery))
	var total_forgery = original.duplicate(true); total_forgery.total_time_cost = 999; variants.append(_rehash(total_forgery))
	for forged in variants:
		var before := JSON.stringify(session.sim.snapshot())
		var result = session.sim.step_party_turn(Plan.new(forged))
		check(not result.accepted, "rehashed party forgery rejected")
		check_eq(result.reason, "stale_or_tampered_combat_plan", "forgery mismatch reason")
		check_eq(JSON.stringify(session.sim.snapshot()), before, "forgery is exact no-op")
	var malformed = original.duplicate(true); malformed.canonical_request.protagonist_action.actor_id = "01"
	var malformed_result = session.sim.step_party_turn(Plan.new(_rehash(malformed)))
	check(not malformed_result.accepted, "malformed canonical request rejected without assert")
	check_eq(malformed_result.reason, "noncanonical_party_actor_id", "strict request reason")

	var contact = Session.new(); var contact_state = contact.sim.world.party_encounter
	check(contact.sim.world.bootstrap_set_terrain(Vector2i(0,0), "wall"), "wall fixture")
	contact.commit_exploration(Command.wait(contact_state.protagonist_id))
	var malformed_deployment = contact.sim.deploy_party([])
	check(not malformed_deployment.accepted, "non-dictionary deployment rejected without runtime error")
	check_eq(malformed_deployment.reason, "invalid_deployment_plan", "malformed deployment reason")
	var deployment: Dictionary = contact.sim.preview_deployment("WEDGE", contact_state.party_member_ids.slice(1))
	var deployment_before := JSON.stringify(contact.sim.snapshot())
	var duplicate = deployment.duplicate(true); duplicate.placements[2].position = duplicate.placements[1].position.duplicate()
	duplicate = _rehash(duplicate); var duplicate_result = contact.sim.deploy_party(duplicate)
	check(not duplicate_result.accepted, "duplicate deployment rejected")
	check_eq(duplicate_result.reason, "deployment_plan_mismatch", "duplicate mismatch reason")
	check_eq(JSON.stringify(contact.sim.snapshot()), deployment_before, "duplicate deployment no-op")
	var impassable = deployment.duplicate(true); impassable.placements[1].position = [0,0]
	impassable = _rehash(impassable); var impassable_result = contact.sim.deploy_party(impassable)
	check(not impassable_result.accepted, "impassable deployment rejected")
	check_eq(impassable_result.reason, "deployment_plan_mismatch", "impassable mismatch reason")
	check_eq(JSON.stringify(contact.sim.snapshot()), deployment_before, "impassable deployment no-op")
	return finish()

func test_grouped_fire_and_electric_deaths_reconcile_before_contact_and_restore() -> bool:
	var fire_session = Session.new(909,808); var fire_state = fire_session.sim.world.party_encounter
	var companion = fire_state.party_member_ids[1]
	check(fire_session.sim.world.bootstrap_set_fire(fire_state.group_anchor, 100) != null, "fire fixture")
	check(_prime_grouped_hazard_health(fire_session, companion, 20),
		"companion fire fixture uses canonical damage history")
	fire_state.party_detection_radius = 4; fire_state.enemy_detection_radius = 3
	var fire_result = fire_session.commit_exploration(Command.wait(fire_state.protagonist_id))
	check(fire_result.accepted, "fire tick step accepted")
	check_eq(fire_session.sim.world.party_encounter.member(companion).presence, "DEFEATED", "grouped fire death reconciled")
	check_eq(fire_session.party_status().safe_phase, "CONTACT", "surviving hero may still contact")
	var dead_deployment = fire_session.sim.preview_deployment("WEDGE", [companion])
	check(not bool(dead_deployment.accepted), "defeated companion cannot be deployed")
	check_eq(dead_deployment.reason, "invalid_companion_ids", "defeated deployment reason")
	check_eq(WorldState.from_snapshot(fire_session.sim.snapshot()).snapshot(), fire_session.sim.snapshot(), "grouped fire restore")

	var hero_fire = Session.new(910,808); var hero_state = hero_fire.sim.world.party_encounter
	check(hero_fire.sim.world.bootstrap_set_fire(hero_state.group_anchor, 100) != null, "hero fire fixture")
	check(_prime_grouped_hazard_health(hero_fire, hero_state.protagonist_id, 20),
		"hero fire fixture uses canonical damage history")
	var hero_result = hero_fire.commit_exploration(Command.wait(hero_state.protagonist_id))
	check(hero_result.accepted, "hero death action settles")
	check_eq(hero_fire.party_status().safe_phase, "PARTY_DEFEATED", "hero death terminal")
	check_eq(_event_count(hero_fire.sim.world.events, ["encounter.detected","encounter.party_ambush","encounter.enemy_ambush"]), 0, "dead hero cannot contact")
	check_eq(WorldState.from_snapshot(hero_fire.sim.snapshot()).snapshot(), hero_fire.sim.snapshot(), "hero death restore")

	var electric_a = Session.new(911,809); var electric_state = electric_a.sim.world.party_encounter
	check(_prime_grouped_electric_health(electric_a, electric_state.protagonist_id, 40),
		"electric fixture uses canonical damage history")
	var electric_result = electric_a.sim.step(Command.discharge(electric_state.group_anchor, 40, electric_state.protagonist_id))
	check(electric_result.accepted, "electric action accepted")
	check_eq(electric_a.party_status().safe_phase, "PARTY_DEFEATED", "electric liveness terminal")
	var electric_b = Session.new(911,809); var electric_b_state = electric_b.sim.world.party_encounter
	check(_prime_grouped_electric_health(electric_b, electric_b_state.protagonist_id, 40),
		"second electric fixture uses canonical damage history")
	electric_b.sim.step(Command.discharge(electric_b_state.group_anchor, 40, electric_b_state.protagonist_id))
	check_eq(electric_a.sim.snapshot(), electric_b.sim.snapshot(), "grouped electric deterministic")
	check_eq(WorldState.from_snapshot(electric_a.sim.snapshot()).snapshot(), electric_a.sim.snapshot(), "electric restore")
	return finish()

func _prime_grouped_hazard_health(session, target_id: int, ceiling: int) -> bool:
	var state = session.sim.world.party_encounter
	state.party_detection_radius = 0; state.enemy_detection_radius = 0
	for enemy_id in state.enemy_ids:
		state.enemy_busy_rows[enemy_id] = 10000
	for _turn in range(16):
		var target = session.sim.world.entities[target_id]
		if int(target.health) <= ceiling: return int(target.health) > 0
		var result = session.sim.step(Command.wait(state.protagonist_id))
		if not result.accepted or state.safe_phase != "GROUPED": return false
	return false

func _prime_grouped_electric_health(session, target_id: int, ceiling: int) -> bool:
	var state = session.sim.world.party_encounter
	state.party_detection_radius = 0; state.enemy_detection_radius = 0
	for enemy_id in state.enemy_ids:
		state.enemy_busy_rows[enemy_id] = 10000
	for _turn in range(16):
		var target = session.sim.world.entities[target_id]
		if int(target.health) <= ceiling: return int(target.health) > 0
		var result = session.sim.step(Command.discharge(
			state.group_anchor, 20, state.protagonist_id))
		if not result.accepted or state.safe_phase != "GROUPED": return false
	return false

func test_grouped_complete_exploration_move_synchronizes_anchor_positions_and_exposure() -> bool:
	var session = _ready_for_regroup(); check_eq(session.party_status().safe_phase,"GROUPED_COMPLETE","auto regroup fixture")
	var before_anchor: Array = session.party_status().anchor
	var moved = session.commit_exploration_direction(Vector2i.LEFT)
	check(moved.accepted, "post-regroup exploration move")
	var status: Dictionary = session.party_status(); check(status.anchor != before_anchor, "anchor moved")
	check_eq(status.anchor, status.protagonist_position, "anchor follows protagonist")
	for row in session.party_cards():
		if bool(row.alive):
			check_eq(row.logical_position, status.anchor, "alive grouped logical position synchronized")
			check_eq(row.element_exposure.position, status.anchor, "grouped exposure samples new anchor")
	check_eq(WorldState.from_snapshot(session.sim.snapshot()).snapshot(), session.sim.snapshot(), "post-regroup move restore")
	return finish()

func test_melee_rejects_friendly_grouped_and_dormant_targets_and_enemy_targets_deployed_only() -> bool:
	var session = _engaged(); var state = session.sim.world.party_encounter; var hero = state.protagonist_id
	var companion = state.party_member_ids[1]
	for target_id in [hero, companion]:
		var rejected = session.sim.preview_party_turn(Request.new(Action.melee(hero, target_id), []))
		check(not bool(rejected.get_value("accepted", false)), "friendly target rejected")
		check_eq(rejected.get_value("reason"), "melee_not_legal", "friendly melee reason")
	var override_request = Request.new(Action.hold(hero), [{"actor_id": companion, "action": Action.melee(companion, hero)}])
	var override_rejected = session.sim.preview_party_turn(override_request)
	check(not bool(override_rejected.get_value("accepted", false)), "companion friendly override rejected")

	var solo = Session.new(); var solo_state = solo.sim.world.party_encounter; solo.commit_exploration(Command.wait(solo_state.protagonist_id))
	solo.preview_deployment("LINE", []); check(solo.commit_deployment().accepted, "solo deployment")
	solo_state = solo.sim.world.party_encounter; var enemy = solo_state.enemy_ids[0]
	check(_relocate_with_move_events(solo.sim, enemy,
		solo.sim.world.entities[solo_state.protagonist_id].position + Vector2i.RIGHT), "solo enemy canonical relocation")
	solo.sim.world.party_encounter.enemy_busy_rows[enemy] = solo.sim.world.world_time
	var turn = solo.sim.preview_party_turn(Request.new(Action.hold(solo_state.protagonist_id), []))
	var turn_result = solo.sim.step_party_turn(turn); check(turn_result.accepted, "enemy response turn")
	for event in turn_result.events:
		if event.actor_id == enemy and event.type == "action.melee_attack":
			check_eq(event.target_id, solo_state.protagonist_id, "enemy only targets deployed hero")
	return finish()

func test_staged_melee_emits_overkill_intent_once_and_damage_once() -> bool:
	var session = _engaged(); var state = session.sim.world.party_encounter; var hero = state.protagonist_id
	var companion = state.party_member_ids[1]; var enemy = state.enemy_ids[0]
	check(_relocate_with_move_events(session.sim, enemy, Vector2i(7,6)), "staged enemy canonical relocation")
	session.sim.world.entities[enemy].health = 10
	var request = Request.new(Action.melee(hero, enemy), [{"actor_id": companion, "action": Action.melee(companion, enemy)}])
	var preview = session.sim.preview_party_turn(request); check(bool(preview.get_value("accepted", false)), "two staged attacks legal")
	var result = session.sim.step_party_turn(preview); check(result.accepted, "staged turn committed")
	check_eq(_event_count(result.events, ["action.melee_attack"]), 2, "both intents emitted")
	check_eq(_event_count(result.events, ["combat.physical_damage"]), 1, "dead target takes damage once")
	var damage_total := 0
	for event in result.events: if event.type == "combat.physical_damage": damage_total += event.magnitude
	check_eq(damage_total, 10, "damage normalized to remaining health")
	check_eq(session.party_status().safe_phase, "GROUPED_COMPLETE", "overkill automatically settles and regroups")
	return finish()

func test_enemy_ambushers_resolve_by_id_and_rubble_move_sets_actual_busy_cost() -> bool:
	var ambush = Session.new(); var state = ambush.sim.world.party_encounter; var first_enemy = state.enemy_ids[0]
	ambush.sim.world.entities[first_enemy].position = Vector2i(8,7)
	var second = ambush.sim.world.add_entity("melee_enemy", "고블린 정찰병", Vector2i(12,12), 40, ["party_enemy"], "goblin", "enemy")
	_register_fixture_enemy(state,second,true)
	state.party_detection_radius = 0; state.enemy_detection_radius = 3
	check(ambush.commit_exploration(Command.wait(state.protagonist_id)).accepted, "enemy ambush contact")
	check_eq(ambush.party_status().contact_kind, "ENEMY_AMBUSH", "ambush kind")
	var opening_ids: Array = []
	for event in ambush.sim.world.events:
		if event.type in ["action.melee_attack", "action.hold"] and event.actor_id in state.enemy_ids: opening_ids.append(event.actor_id)
	check_eq(opening_ids, state.enemy_ids,
		"all encounter-aware ambushers act in entity ID order regardless of radius")
	var outside_action = ambush.sim.world.events.filter(func(event): return event.actor_id == second.id and event.type == "action.hold")
	check_eq(outside_action.size(), 1, "outside-radius encounter enemy still resolves HOLD")

	var mover = Session.new(); var mover_state = mover.sim.world.party_encounter
	check(mover.sim.world.bootstrap_set_terrain(Vector2i(10,7), "rubble"), "rubble fixture")
	mover.commit_exploration(Command.wait(mover_state.protagonist_id)); mover.preview_deployment("WEDGE", mover_state.party_member_ids.slice(1)); mover.commit_deployment()
	var moved_enemy = mover_state.enemy_ids[0]; var party_turn = mover.sim.preview_party_turn(Request.new(Action.hold(mover_state.protagonist_id), []))
	var result = mover.sim.step_party_turn(party_turn); check(result.accepted, "turn reaches enemy cadence")
	check_eq(mover.sim.world.entities[moved_enemy].position, Vector2i(10,7), "enemy moved onto rubble")
	check_eq(mover.sim.world.party_encounter.enemy_busy_rows[moved_enemy], 340, "enemy busy uses rubble 140 cost")

	# contact_enemy_id is immutable encounter evidence, not a requirement that the
	# first-seen enemy remain alive while another encounter enemy still fights.
	var multi = Session.new(); var multi_state = multi.sim.world.party_encounter
	var reserve_enemy = multi.sim.world.add_entity("melee_enemy", "고블린 지원병", Vector2i(12,8), 40,
		["party_enemy"], "goblin", "enemy")
	_register_fixture_enemy(multi_state,reserve_enemy,true)
	multi.commit_exploration(Command.wait(multi_state.protagonist_id))
	multi.preview_deployment("WEDGE", multi_state.party_member_ids.slice(1)); check(multi.commit_deployment().accepted, "multi enemy deployment")
	multi_state = multi.sim.world.party_encounter; var contact_enemy = multi_state.contact_enemy_id
	check(_relocate_with_move_events(multi.sim, contact_enemy,
		multi.sim.world.entities[multi_state.protagonist_id].position + Vector2i.RIGHT), "contact enemy canonical relocation")
	multi.sim.world.entities[contact_enemy].health = 22
	var kill_first = multi.sim.step_party_turn(multi.sim.preview_party_turn(
		Request.new(Action.melee(multi_state.protagonist_id, contact_enemy), [])))
	check(kill_first.accepted, "first-contact enemy can die while reserve remains")
	check_eq(multi.party_status().safe_phase, "ENGAGED", "remaining enemy keeps encounter engaged")
	check(not multi.sim.world.entities[contact_enemy].is_alive(), "contact evidence ID may reference defeated enemy")
	check_eq(WorldState.from_snapshot(multi.sim.snapshot()).snapshot(), multi.sim.snapshot(), "multi enemy engaged snapshot restores")
	return finish()

func test_weighted_companion_suggestions_use_direct_action_personality_relation_and_hazard_purely() -> bool:
	# The utility ruleset keeps the adjacent attack legal at both personality
	# extremes, while aggression and boldness still raise ENGAGE's disclosed score.
	var personality = _engaged_one_companion(); var pstate = personality.sim.world.party_encounter
	var hero: int = pstate.protagonist_id; var companion: int = pstate.party_member_ids[1]; var enemy: int = pstate.enemy_ids[0]
	check(_relocate_with_move_events(personality.sim, enemy,
		personality.sim.world.entities[companion].position + Vector2i.RIGHT), "personality enemy canonical relocation")
	_set_facet(pstate.member(companion).personality_profile, "aggression", 0)
	_set_facet(pstate.member(companion).personality_profile, "boldness", 0)
	_set_facet(pstate.member(companion).personality_profile, "composure", 999)
	var cautious := _suggestion_for(personality.sim.preview_party_turn(Request.new(Action.hold(hero), [])), companion)
	var cautious_explanation:Dictionary=personality.sim.party_coordinator.explain_companion_turn(
		Request.new(Action.hold(hero),[]))
	check_eq(cautious.type, "MELEE", "adjacent ENGAGE remains a legal leaf")
	_set_facet(pstate.member(companion).personality_profile, "aggression", 999)
	_set_facet(pstate.member(companion).personality_profile, "boldness", 999)
	var aggressive := _suggestion_for(personality.sim.preview_party_turn(Request.new(Action.hold(hero), [])), companion)
	var aggressive_explanation:Dictionary=personality.sim.party_coordinator.explain_companion_turn(
		Request.new(Action.hold(hero),[]))
	check_eq(aggressive.type, "MELEE", "high aggression and boldness use legal melee")
	check_eq(int(aggressive.target_id), enemy, "personality melee targets encounter enemy")
	check(_candidate_score(aggressive_explanation,companion,"ENGAGE") \
		> _candidate_score(cautious_explanation,companion,"ENGAGE"),
		"aggression and boldness increase the data-driven ENGAGE score")

	# With two symmetric enemies, the protagonist's direct target becomes the
	# support focus. P1 treats that focus as a squad hint; protagonist relation no
	# longer hard-vetoes it (ally trust instead contributes to PROTECT).
	var support = Session.new(); var sstate = support.sim.world.party_encounter
	hero = sstate.protagonist_id; companion = sstate.party_member_ids[1]; var focus_enemy: int = sstate.enemy_ids[0]
	var reserve = support.sim.world.add_entity("melee_enemy", "고블린 지원병", Vector2i(12,8), 40,
		["party_enemy"], "goblin", "enemy")
	_register_fixture_enemy(sstate,reserve,true)
	sstate.enemy_busy_rows[reserve.id]=support.sim.world.world_time
	support.commit_exploration(Command.wait(hero)); support.preview_deployment("WEDGE", [companion])
	check(support.commit_deployment().accepted, "support deployment")
	check(_relocate_with_move_events(support.sim, focus_enemy, Vector2i(8,7)), "support enemy canonical relocation")
	check(_relocate_with_move_events(support.sim, reserve.id, Vector2i(7,8)), "support reserve canonical relocation")
	for facet in ["aggression", "boldness", "composure"]: _set_facet(sstate.member(companion).personality_profile, facet, 999)
	var relation = PersonalRelation.new(companion, hero); relation.personal_trust_delta = 40; relation.gratitude = 100
	support.sim.world.personal_relations["%d:%d" % [companion,hero]] = relation
	var follow_focus := _suggestion_for(support.sim.preview_party_turn(Request.new(Action.melee(hero, focus_enemy), [])), companion)
	var follow_reserve := _suggestion_for(support.sim.preview_party_turn(Request.new(Action.melee(hero, reserve.id), [])), companion)
	check_eq(follow_focus.type, "MOVE", "positive support relation approaches direct focus")
	check_eq(follow_reserve.type, "MOVE", "direct action can switch support focus")
	check(_chebyshev(Vector2i(int(follow_focus.destination[0]), int(follow_focus.destination[1])),
		support.sim.world.entities[focus_enemy].position) < _chebyshev(support.sim.world.entities[companion].position,
		support.sim.world.entities[focus_enemy].position), "focus suggestion advances toward protagonist target")
	check(_chebyshev(Vector2i(int(follow_reserve.destination[0]), int(follow_reserve.destination[1])), reserve.position) \
		< _chebyshev(support.sim.world.entities[companion].position, reserve.position), "changed direct target changes approach")
	check(follow_focus.destination != follow_reserve.destination, "symmetric direct targets produce distinct first steps")
	relation.personal_trust_delta = -40; relation.gratitude = 0; relation.grievance = 100
	var opposed := _suggestion_for(support.sim.preview_party_turn(Request.new(Action.melee(hero, focus_enemy), [])), companion)
	check_eq(opposed.type, "MOVE", "negative support relation still chooses a legal approach")
	check_eq(opposed.destination,follow_focus.destination,
		"protagonist relation does not override the derived squad focus")

	# WeightedPathfinder supplies the deterministic first step. P1 exposure is a
	# leaf-routing input, not a cross-action veto; a forced hazardous first step
	# remains legal at either composure extreme and preview stays byte-pure.
	var hazard = _engaged_one_companion(); var hstate = hazard.sim.world.party_encounter
	hero = hstate.protagonist_id; companion = hstate.party_member_ids[1]; enemy = hstate.enemy_ids[0]
	for facet in ["aggression", "boldness", "composure"]: _set_facet(hstate.member(companion).personality_profile, facet, 999)
	var safe_suggestion := _suggestion_for(hazard.sim.preview_party_turn(Request.new(Action.hold(hero), [])), companion)
	check_eq(safe_suggestion.type, "MOVE", "driven companion approaches distant enemy")
	var approach_cells: Array[Vector2i] = []
	for direction in hazard.sim.movement.MOVE_DIRECTIONS_8:
		var approach: Vector2i = hazard.sim.world.entities[enemy].position + direction
		if hazard.sim.world.in_bounds(approach): approach_cells.append(approach)
	var weighted_path: Dictionary = hazard.sim.pathfinder.find_path_to_any(companion, approach_cells)
	check(bool(weighted_path.found), "weighted approach path exists")
	check_eq(safe_suggestion.destination, [weighted_path.path[1].x, weighted_path.path[1].y], "suggestion uses weighted path first step")
	var hazard_position := Vector2i(int(safe_suggestion.destination[0]), int(safe_suggestion.destination[1]))
	var ignition = hazard.sim.world.emit_event("environment.ignited", -1, -1, hazard_position, 100)
	var hazard_tile = hazard.sim.world.tile_at(hazard_position); hazard_tile.fire = 100
	hazard_tile.fire_source_event_id = ignition.id; hazard_tile.fire_damage_eligible_time = hazard.sim.world.world_time
	var composed := _suggestion_for(hazard.sim.preview_party_turn(Request.new(Action.hold(hero), [])), companion)
	check_eq(composed.type, "MOVE", "high composure tolerates deterministic hazard")
	_set_facet(hstate.member(companion).personality_profile, "composure", 0)
	var shaken := _suggestion_for(hazard.sim.preview_party_turn(Request.new(Action.hold(hero), [])), companion)
	check_eq(shaken.type, "MOVE", "hazard does not veto the selected utility action")
	check_eq(shaken.destination,composed.destination,
		"forced route keeps the only legal immediate step")
	var pure_snapshot: Dictionary = hazard.sim.snapshot()
	for index in range(10): hazard.sim.preview_party_turn(Request.new(Action.hold(hero), []))
	check_eq(hazard.sim.snapshot(), pure_snapshot, "personality relation hazard preview remains pure")
	return finish()

func test_snapshot_party_semantic_tamper_table_is_rejected() -> bool:
	var grouped = Session.new().sim.snapshot()
	var contact_session = Session.new(); var contact_state = contact_session.sim.world.party_encounter
	contact_session.commit_exploration(Command.wait(contact_state.protagonist_id)); var contact = contact_session.sim.snapshot()
	var engaged_session = _engaged(); var engaged = engaged_session.sim.snapshot()
	var ready_session = _ready_for_regroup(); var ready = ready_session.sim.snapshot()
	var complete = ready.duplicate(true)
	var two_enemy_ready_session = _ready_for_regroup_two_enemies()
	check_eq(two_enemy_ready_session.party_status().safe_phase, "GROUPED_COMPLETE", "two-enemy tamper fixture")
	var two_enemy_ready = two_enemy_ready_session.sim.snapshot()
	var cases: Array = []
	var overlap = grouped.duplicate(true); overlap.party_encounter.enemy_ids[0] = overlap.party_encounter.party_member_ids[2]
	overlap.party_encounter.enemy_busy_rows[0].entity_id = overlap.party_encounter.party_member_ids[2]; cases.append(["overlap", overlap])
	var bad_contact = contact.duplicate(true); bad_contact.party_encounter.contact_enemy_id = "999"; cases.append(["contact membership", bad_contact])
	var negative_busy = grouped.duplicate(true); negative_busy.party_encounter.enemy_busy_rows[0].busy_until = "-1"; cases.append(["negative busy", negative_busy])
	var overflow_busy = grouped.duplicate(true); overflow_busy.party_encounter.enemy_busy_rows[0].busy_until = "9223372036854775708"; cases.append(["overflow busy", overflow_busy])
	var slot_gap = grouped.duplicate(true); slot_gap.party_encounter.member_rows[2].roster_slot = 3; cases.append(["slot gap", slot_gap])
	var wrong_role = grouped.duplicate(true); wrong_role.party_encounter.member_rows[1].role = "PROTAGONIST"; cases.append(["duplicate protagonist role", wrong_role])
	var swapped_slots = grouped.duplicate(true); swapped_slots.party_encounter.member_rows[1].roster_slot = 2
	swapped_slots.party_encounter.member_rows[2].roster_slot = 1; cases.append(["swapped roster slots", swapped_slots])
	var moved_anchor = grouped.duplicate(true); moved_anchor.party_encounter.group_anchor = [8,7]
	moved_anchor.entities[1].position = [8,7]; moved_anchor.entities[2].position = [8,7]
	cases.append(["anchor companions moved without protagonist", moved_anchor])
	var bad_phase = grouped.duplicate(true); bad_phase.party_encounter.safe_phase = "PARTY_DEFEATED"; cases.append(["false defeat", bad_phase])
	var settled_ready=complete.duplicate(true); settled_ready.party_encounter.safe_phase="REGROUP_READY"; cases.append(["settled regroup-ready forbidden in v2",settled_ready])
	var duplicate_position = engaged.duplicate(true); duplicate_position.entities[1].position = duplicate_position.entities[0].position.duplicate(); cases.append(["duplicate deployed", duplicate_position])
	var impassable = engaged.duplicate(true); var hero_pos: Array = impassable.entities[0].position; var tile_index := int(hero_pos[1]) * 15 + int(hero_pos[0])
	impassable.tiles[tile_index].terrain = "wall"; cases.append(["impassable deployed", impassable])
	var missing_contact_event = contact.duplicate(true)
	_snapshot_event(missing_contact_event,"encounter.party_ambush").type="tampered.contact"
	cases.append(["contact evidence", missing_contact_event])
	var contact_facing = contact.duplicate(true); _snapshot_event(contact_facing, "encounter.party_ambush").data.facing = [-1,0]
	cases.append(["contact facing correlation", contact_facing])
	var correlated_facing = contact.duplicate(true); correlated_facing.party_encounter.facing = [-1,0]
	_snapshot_event(correlated_facing, "encounter.party_ambush").data.facing = [-1,0]
	cases.append(["contact state and event facing cannot jointly forge geometry", correlated_facing])
	var correlated_anchor = contact.duplicate(true); correlated_anchor.party_encounter.group_anchor = [8,7]
	for member_wire in correlated_anchor.party_encounter.party_member_ids:
		_snapshot_entity(correlated_anchor, int(member_wire)).position = [8,7]
	_snapshot_event(correlated_anchor, "encounter.party_ambush").position = [8,7]
	cases.append(["contact anchor and every grouped position require root movement history", correlated_anchor])
	var contact_extra = contact.duplicate(true); _snapshot_event(contact_extra, "encounter.party_ambush").data.extra = "forged"
	cases.append(["contact data exactness", contact_extra])
	var contact_actor = contact.duplicate(true); var actor_event: Dictionary = _snapshot_event(contact_actor, "encounter.party_ambush")
	actor_event.actor_id = contact_actor.party_encounter.party_member_ids[1]; actor_event.instigator_id = actor_event.actor_id
	cases.append(["contact actor correlation", contact_actor])
	var contact_target = contact.duplicate(true); _snapshot_event(contact_target, "encounter.party_ambush").target_id = contact_target.party_encounter.party_member_ids[1]
	cases.append(["contact target correlation", contact_target])
	var missing_formation_event = engaged.duplicate(true)
	for event in missing_formation_event.events:
		if event.type == "party.deployment_completed": event.type = "tampered.deployment"
	cases.append(["formation evidence", missing_formation_event])
	var deployment_cause = engaged.duplicate(true); _snapshot_event(deployment_cause, "party.member_deployed").cause_id = deployment_cause.events[0].id
	cases.append(["deployed member cause", deployment_cause])
	var deployment_position = engaged.duplicate(true); _snapshot_event(deployment_position, "party.member_deployed").position = [0,0]
	cases.append(["deployed member position", deployment_position])
	var deployment_completed_cause = engaged.duplicate(true); _snapshot_event(deployment_completed_cause, "party.deployment_completed").cause_id = deployment_completed_cause.events[0].id
	cases.append(["deployment completed cause", deployment_completed_cause])
	var correlated_formation = engaged.duplicate(true); correlated_formation.party_encounter.formation_id = "LINE"
	for event in correlated_formation.events:
		if str(event.type) in ["party.member_deployed", "party.deployment_completed"]:
			event.data.formation_id = "LINE"
	cases.append(["formation strings cannot relabel wedge geometry", correlated_formation])
	var victory_cause = ready.duplicate(true); var victory_event: Dictionary = _snapshot_event(victory_cause, "party.victory")
	victory_event.cause_id = _snapshot_event(victory_cause, "encounter.party_ambush").id
	cases.append(["victory cause", victory_cause])
	var victory_position = ready.duplicate(true); _snapshot_event(victory_position, "party.victory").position = [0,0]
	cases.append(["victory position", victory_position])
	var first_death_cause = two_enemy_ready.duplicate(true); var enemy_deaths: Array = []
	for event in first_death_cause.events:
		if str(event.type) == "entity.died" and str(event.target_id) in first_death_cause.party_encounter.enemy_ids:
			enemy_deaths.append(event)
	check(enemy_deaths.size() >= 2, "two enemy fixture has ordered death evidence")
	if enemy_deaths.size() >= 2:
		_snapshot_event(first_death_cause, "party.victory").cause_id = enemy_deaths[0].id
		cases.append(["victory cause must be final encounter enemy death", first_death_cause])
	var regroup_member_cause = complete.duplicate(true)
	_snapshot_event(regroup_member_cause, "party.member_regrouped").cause_id = _snapshot_event(regroup_member_cause, "party.victory").id
	cases.append(["regroup member cause", regroup_member_cause])
	var regroup_root_cause=complete.duplicate(true); _snapshot_event(regroup_root_cause,"party.regroup_started").cause_id=-1
	cases.append(["regroup root must be caused by victory",regroup_root_cause])
	var regroup_step=complete.duplicate(true); _snapshot_event(regroup_step,"party.regroup_started").step_index="0"
	cases.append(["victory and regroup must share step",regroup_step])
	var regroup_completed_position = complete.duplicate(true); _snapshot_event(regroup_completed_position, "party.regroup_completed").position = [0,0]
	cases.append(["regroup completed position", regroup_completed_position])
	var correlated_regroup = complete.duplicate(true); correlated_regroup.party_encounter.group_anchor = [8,7]
	for member_wire in correlated_regroup.party_encounter.party_member_ids:
		var member_id := int(member_wire); var member_entity: Dictionary = _snapshot_entity(correlated_regroup, member_id)
		if int(member_entity.health) > 0: member_entity.position = [8,7]
	for event in correlated_regroup.events:
		if str(event.type) in ["party.victory", "party.regroup_started", "party.member_regrouped", "party.regroup_completed"]:
			event.position = [8,7]
	cases.append(["regroup history cannot shift with current grouped anchor", correlated_regroup])
	for row in cases:
		var reason := WorldState.snapshot_restore_error(row[1])
		check(not reason.is_empty(), "%s rejected" % row[0])
		check(WorldState.from_snapshot(row[1]) == null, "%s returns null" % row[0])
	return finish()

func test_deployment_turn_victory_and_regroup_faults_rollback_every_surface() -> bool:
	for point in ["deployment_member_event", "deployment_completed_event"]:
		var contact = Session.new(); var contact_state = contact.sim.world.party_encounter
		contact.commit_exploration(Command.wait(contact_state.protagonist_id))
		var deployment = contact.sim.preview_deployment("WEDGE", contact_state.party_member_ids.slice(1)); var before = contact.sim.snapshot()
		contact.sim.party_coordinator.fail_point = point; var result = contact.sim.deploy_party(deployment)
		check(not result.accepted, "%s deployment rejected" % point); check_eq(contact.sim.snapshot(), before, "%s deployment rollback" % point)

	var override_session = _engaged(); var override_state = override_session.sim.world.party_encounter
	var override_companion = override_state.party_member_ids[1]
	var override_plan = override_session.sim.preview_party_turn(Request.new(Action.hold(override_state.protagonist_id),
		[{"actor_id":override_companion, "action":Action.move_to(override_companion,
			override_session.sim.world.entities[override_companion].position + Vector2i.RIGHT)}]))
	var override_before = override_session.sim.snapshot(); override_session.sim.party_coordinator.fail_point = "turn_override_event"
	var override_result = override_session.sim.step_party_turn(override_plan)
	check(not override_result.accepted, "override event fault"); check_eq(override_session.sim.snapshot(), override_before, "override fault rollback")

	var schedule_session = _engaged(); var schedule_state = schedule_session.sim.world.party_encounter
	var schedule_plan = schedule_session.sim.preview_party_turn(Request.new(Action.hold(schedule_state.protagonist_id), [])); var schedule_before = schedule_session.sim.snapshot()
	schedule_session.sim.party_coordinator.fail_point = "party_schedule"; var schedule_result = schedule_session.sim.step_party_turn(schedule_plan)
	check(not schedule_result.accepted, "schedule fault"); check_eq(schedule_session.sim.snapshot(), schedule_before, "schedule rollback")

	var victory_session = _engaged(); var victory_state = victory_session.sim.world.party_encounter; var victory_enemy = victory_state.enemy_ids[0]
	check(_relocate_with_move_events(victory_session.sim, victory_enemy,
		victory_session.sim.world.entities[victory_state.protagonist_id].position + Vector2i.RIGHT), "victory enemy canonical relocation")
	victory_session.sim.world.entities[victory_enemy].health = 22
	var victory_plan = victory_session.sim.preview_party_turn(Request.new(Action.melee(victory_state.protagonist_id, victory_enemy), [])); var victory_before = victory_session.sim.snapshot()
	victory_session.sim.party_coordinator.fail_point = "victory_event"; var victory_result = victory_session.sim.step_party_turn(victory_plan)
	check(not victory_result.accepted, "victory event fault"); check_eq(victory_session.sim.snapshot(), victory_before, "victory fault rollback")

	for point in ["automatic_regroup_after_victory", "automatic_regroup_started_event", "automatic_regroup_member_event", "automatic_regroup_completed_event"]:
		var automatic = _engaged(); var automatic_state = automatic.sim.world.party_encounter; var automatic_enemy = automatic_state.enemy_ids[0]
		check(_relocate_with_move_events(automatic.sim, automatic_enemy, automatic.sim.world.entities[automatic_state.protagonist_id].position+Vector2i.RIGHT), "%s enemy fixture"%point)
		automatic.sim.world.entities[automatic_enemy].health=22
		var automatic_plan=automatic.sim.preview_party_turn(Request.new(Action.melee(automatic_state.protagonist_id,automatic_enemy),[])); var automatic_before=automatic.sim.snapshot()
		automatic.sim.party_coordinator.fail_point=point; var automatic_result=automatic.sim.step_party_turn(automatic_plan)
		check(not automatic_result.accepted,"%s rejected"%point); check_eq(automatic.sim.snapshot(),automatic_before,"%s full killing-turn rollback"%point)
	return finish()

func _engaged():
	var session=Session.new(); var state=session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id)); session.preview_deployment("WEDGE",state.party_member_ids.slice(1)); session.commit_deployment()
	return session

func _engaged_one_companion():
	var session = Session.new(); var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE", [state.party_member_ids[1]])
	session.commit_deployment()
	return session

func _ready_for_regroup():
	var session = _engaged(); var state = session.sim.world.party_encounter; var enemy = state.enemy_ids[0]
	if not _relocate_with_move_events(session.sim, enemy,
			session.sim.world.entities[state.protagonist_id].position + Vector2i.RIGHT):
		return session
	session.sim.world.entities[enemy].health = 22
	var result = session.sim.step_party_turn(session.sim.preview_party_turn(Request.new(Action.melee(state.protagonist_id, enemy), [])))
	if not result.accepted: return session
	return session

func _ready_for_regroup_two_enemies():
	var session = Session.new(); var state = session.sim.world.party_encounter; var first_enemy: int = state.enemy_ids[0]
	var reserve = session.sim.world.add_entity("melee_enemy", "고블린 후위", Vector2i(12,8), 40,
		["party_enemy"], "goblin", "enemy")
	_register_fixture_enemy(state,reserve,true)
	state.enemy_busy_rows[first_enemy] = 10000; state.enemy_busy_rows[reserve.id] = 10000
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE", state.party_member_ids.slice(1))
	if not session.commit_deployment().accepted: return session
	state = session.sim.world.party_encounter; var hero: int = state.protagonist_id
	if not _relocate_with_move_events(session.sim, first_enemy, session.sim.world.entities[hero].position + Vector2i.RIGHT):
		return session
	session.sim.world.entities[first_enemy].health = 22
	var first_result = session.sim.step_party_turn(session.sim.preview_party_turn(Request.new(Action.melee(hero, first_enemy), [])))
	if not first_result.accepted: return session
	if not _relocate_with_move_events(session.sim, reserve.id, session.sim.world.entities[hero].position + Vector2i.RIGHT):
		return session
	session.sim.world.entities[reserve.id].health = 22
	session.sim.step_party_turn(session.sim.preview_party_turn(Request.new(Action.melee(hero, reserve.id), [])))
	return session

func _rehash(data: Dictionary) -> Dictionary:
	var copy := data.duplicate(true); copy.erase("plan_hash")
	data["plan_hash"] = JSON.stringify(copy).sha256_text(); return data

func _register_fixture_enemy(state,enemy,hunting:bool=false)->void:
	state.enemy_ids.append(enemy.id)
	state.enemy_ids.sort()
	state.enemy_busy_rows[enemy.id]=0
	var awareness=EnemyAwareness.new(enemy.id,enemy.position)
	if hunting:
		awareness.awareness_state="HUNTING"
		awareness.suspicion=1000
		awareness.last_known_target_position=state.group_anchor
	state.enemy_awareness_rows[enemy.id]=awareness

func _event_count(events: Array, types: Array) -> int:
	var result := 0
	for event in events:
		if event.type in types: result += 1
	return result

func _snapshot_event(snapshot: Dictionary, event_type: String) -> Dictionary:
	for event in snapshot.events:
		if str(event.type) == event_type: return event
	return {}

func _snapshot_entity(snapshot: Dictionary, entity_id: int) -> Dictionary:
	for entity in snapshot.entities:
		if int(entity.id) == entity_id: return entity
	return {}

func _set_facet(profile, facet_id: String, value: int) -> void:
	for row in profile.facet_rows:
		if str(row.facet_id) == facet_id:
			row.base_value = value
			return

func _suggestion_for(plan, actor_id: int) -> Dictionary:
	for row in plan.to_dict().get("actor_rows", []):
		if int(row.actor_id) == actor_id: return row.suggestion
	return {}

func _candidate_score(explanation:Dictionary,actor_id:int,action_id:String)->int:
	for companion_row in explanation.get("companions",[]):
		if int(companion_row.actor_id)!=actor_id:continue
		for candidate in companion_row.candidates:
			if str(candidate.action_id)==action_id:return int(candidate.score)
	return -1000000

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x), absi(a.y-b.y))

func _relocate_with_move_events(sim, entity_id: int, target: Vector2i) -> bool:
	# Test fixtures must preserve the same canonical movement evidence expected from
	# production turns; direct position writes would create an impossible snapshot.
	for attempt in range(64):
		var current: Vector2i = sim.world.entities[entity_id].position
		if current == target:
			return true
		var delta := target - current
		var preferred: Array[Vector2i] = []
		var diagonal := Vector2i(signi(delta.x), signi(delta.y))
		if diagonal != Vector2i.ZERO:
			preferred.append(diagonal)
		if delta.x != 0:
			preferred.append(Vector2i(signi(delta.x), 0))
		if delta.y != 0:
			preferred.append(Vector2i(0, signi(delta.y)))
		for direction in sim.movement.MOVE_DIRECTIONS_8:
			if direction not in preferred:
				preferred.append(direction)
		var committed := false
		for direction in preferred:
			var destination := current + direction
			if _chebyshev(destination, target) >= _chebyshev(current, target):
				continue
			var assessment = sim.movement.assess_move(entity_id, destination)
			if not assessment.accepted:
				continue
			var definition: Dictionary = TerrainRegistry.definition(str(assessment.terrain_id))
			if sim.movement.commit_preflighted_move(entity_id, destination,
					str(assessment.terrain_id), int(definition.move_time_cost)) == null:
				return false
			committed = true
			break
		if not committed:
			return false
	return false
