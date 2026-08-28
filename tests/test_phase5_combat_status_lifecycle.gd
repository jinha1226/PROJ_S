extends "res://tests/test_case.gd"

const Simulator = preload("res://sim/simulator.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const LabSession = preload("res://playtest/playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Plan = preload("res://sim/party_turn_plan.gd")
const WorldState = preload("res://sim/world_state.gd")
const Profiles = preload("res://sim/combat_profile_registry.gd")
const Statuses = preload("res://sim/status_registry.gd")
const StatusRow = preload("res://sim/combat_status_row.gd")
const Melee = preload("res://sim/systems/melee_combat_system.gd")
const Terrain = preload("res://sim/terrain_registry.gd")

func test_exact_registries_formulas_and_sha_reference_vector() -> bool:
	check_eq(Profiles.registry_error(), "", "profile registry")
	check_eq(Statuses.registry_error(), "", "status registry")
	var expected := {
		"hero":["party-hero-v1",600,150,24,2,650,100],
		"companion":["party-companion-v1",575,130,24,2,550,100],
		"melee_enemy":["party-goblin-v1",550,100,16,2,400,50],
		"lead":["phase3-lead-v1",600,150,24,2,650,100],
		"melee_threat":["phase3-threat-v1",550,100,20,2,400,50],
		"passive_ally":["phase3-passive-v1",500,130,12,2,250,100],
		"other":["combatant-default-v1",500,100,12,2,300,100],
	}
	for kind in expected:
		var profile_id := Profiles.profile_id_for_kind(kind)
		var row := Profiles.profile(profile_id); var value: Array = expected[kind]
		check_eq([profile_id,row.accuracy_milli,row.evasion_milli,row.power,row.armor_flat,
			row.bleed_proc_milli,row.bleed_resist_milli], value, "profile %s" % kind)
	check_eq([24-2,16-2,24-2,20-2],[22,14,22,18],"normal damage")
	check_eq([22-int(22*250/1000),14-int(14*250/1000),18-int(18*250/1000)],
		[17,11,14],"guard damage")
	var key := Melee.commitment_key(44,3,200,"PARTY_TURN/3",0,1,4)
	check_eq(key,"deterministic-melee-resolution-v1|seed=44|step=3|time=200|batch=PARTY_TURN/3|ordinal=0|attacker=1|target=4","commitment key")
	check_eq(Melee.commitment_hash(key),"31da9bf354e293ea453d56f126a8a3237d974b4191d48b5472f29ca2a862f418","commitment hash")
	check_eq(Melee.lane_hash(key,"HIT"),"bb11037a45dd86174f2045b3c275ff7e09e1eba4fe5a1aaf2d733b0325687ff1","hit hash")
	check_eq(Melee.lane_roll_milli(key,"HIT"),746,"hit roll")
	check_eq(Melee.lane_hash(key,"BLEED"),"fa1afe5d417c07fa5c2525052dcabe140de1f759b7f8b652f4f46b0036ea102e","bleed hash")
	check_eq(Melee.lane_roll_milli(key,"BLEED"),405,"bleed roll")
	return finish()

func test_snapshot_v6_exact_rows_strict_rejection_and_round_trip() -> bool:
	var sim = Simulator.new(3,2,44); var hero=sim.world.add_entity("hero","Hero",Vector2i.ZERO)
	var goblin=sim.world.add_entity("melee_enemy","Goblin",Vector2i(1,0))
	var snapshot: Dictionary = sim.snapshot()
	check_eq([snapshot.snapshot_version,snapshot.ruleset_version,snapshot.combat_ruleset_id,
		snapshot.combat_profile_ruleset_id,snapshot.combatant_schema_id,snapshot.agent_state_schema_id,
		snapshot.life_ruleset_id,snapshot.status_ruleset_id,snapshot.party_member_schema_id],
		[6,"phase5-combat-status-lifecycle-v1","deterministic-melee-resolution-v1",
		"combat-profile-registry-v1","combatant-state-v1","agent-state-v2",
		"active-downed-dead-v1","bounded-status-lifecycle-v1","party-member-v2"],"v6 IDs")
	check_eq(snapshot.combatant_states.map(func(r): return r.entity_id),[str(hero.id),str(goblin.id)],"combatant order")
	check_eq(Simulator.from_snapshot(snapshot).snapshot(),snapshot,"v6 round trip")
	var old=snapshot.duplicate(true);old.snapshot_version=5
	check_eq(WorldState.snapshot_restore_error(old),"unsupported_snapshot_version","v5 rejected")
	var missing=snapshot.duplicate(true);missing.combatant_states.pop_back()
	check_eq(WorldState.snapshot_restore_error(missing),"combatant_entity_set_mismatch","missing combatant")
	var bad_profile=snapshot.duplicate(true);bad_profile.combatant_states[0].combat_profile_id="missing"
	check_eq(WorldState.snapshot_restore_error(bad_profile),"unknown_combat_profile_id","unknown profile")
	var bad_sentinel=snapshot.duplicate(true);bad_sentinel.combatant_states[0].downed_at="0"
	check_eq(WorldState.snapshot_restore_error(bad_sentinel),"active_combatant_sentinel_invalid","active sentinel")
	var old_agent_session=Session.new(); var old_agent=old_agent_session.sim.snapshot()
	# Party rows reject the removed v1 status authority.
	old_agent.party_encounter.member_rows[0]["status_ids"]=[]
	check_eq(WorldState.snapshot_restore_error(old_agent),"invalid_party_member_keys","old party status key")
	var lab=LabSession.new().sim.snapshot();lab.agent_states[0]["guarded_until"]="0"
	check_eq(WorldState.snapshot_restore_error(lab),"invalid_agent_state_keys","old agent guard key")
	return finish()

func test_snapshot_v6_rejects_legacy_fixed_melee_and_physical_chain() -> bool:
	var sim = Simulator.new(2, 1, 90210)
	var attacker = sim.world.add_entity("hero", "Legacy Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Legacy Target", Vector2i.RIGHT)
	check(attacker != null and target != null, "legacy melee wire entities built")
	if attacker == null or target == null: return finish()
	var snapshot: Dictionary = sim.snapshot()
	snapshot.step_index = "1"
	snapshot.next_event_id = "3"
	for row in snapshot.entities:
		if int(str(row.id)) == target.id:
			row.health = target.health - 22
	snapshot.events = [
		{"id":"1", "step_index":"1", "world_time":"0",
			"type":"action.melee_attack", "actor_id":str(attacker.id),
			"target_id":str(target.id), "position":[1, 0], "magnitude":22,
			"cause_id":"-1", "instigator_id":str(attacker.id),
			"data":{"combat_ruleset_id":"fixed-melee-v1"}},
		{"id":"2", "step_index":"1", "world_time":"0",
			"type":"combat.physical_damage", "actor_id":"-1",
			"target_id":str(target.id), "position":[1, 0], "magnitude":22,
			"cause_id":"1", "instigator_id":str(attacker.id),
			"data":{"damage_type":"physical"}},
	]
	var restore_error := WorldState.snapshot_restore_error(snapshot)
	check(not restore_error.is_empty(),
		"strict v6 rejects legacy fixed-melee/physical chain; actual=%s" % restore_error)
	check(Simulator.from_snapshot(snapshot) == null,
		"legacy fixed-melee v6 snapshot never constructs")
	return finish()

func test_pristine_bootstrap_dead_requires_pristine_snapshot_provenance() -> bool:
	var sim = Simulator.new(2, 1, 721)
	var corpse = sim.world.add_entity("other", "Bootstrap Corpse", Vector2i.ZERO)
	var witness = sim.world.add_entity("other", "Active Witness", Vector2i.RIGHT)
	check(corpse != null and witness != null, "pristine corpse provenance entities built")
	if corpse == null or witness == null: return finish()
	check(sim.world.bootstrap_set_combatant_life_state(corpse.id, "DEAD"),
		"pristine corpse bootstrap seam succeeds")
	var canonical: Dictionary = sim.snapshot()
	check_eq([canonical.step_index, canonical.world_time, canonical.events],
		["0", "0", []], "pristine corpse baseline has zero step/time/history")
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"pristine corpse baseline restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "pristine corpse baseline constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical, "pristine corpse baseline roundtrip exact")
	var advanced: Dictionary = canonical.duplicate(true)
	advanced.step_index = "1"
	var unrelated: Dictionary = canonical.duplicate(true)
	unrelated.step_index = "1"; unrelated.next_event_id = "2"
	unrelated.events.append({"id":"1", "step_index":"1", "world_time":"0",
		"type":"action.wait", "actor_id":str(witness.id), "target_id":"-1",
		"position":[1, 0], "magnitude":0, "cause_id":"-1",
		"instigator_id":str(witness.id), "data":{}})
	var results: Array = []; var accepted: Array = []
	for pair in [["advanced_empty_history", advanced], ["unrelated_witness_history", unrelated]]:
		var error := WorldState.snapshot_restore_error(pair[1])
		results.append([pair[0], error])
		if error.is_empty(): accepted.append(pair[0])
	check(accepted.is_empty(),
		"accepted non-pristine bootstrap corpse forgeries: %s; errors=%s" % [accepted, results])
	for result in results:
		check_eq(result[1], "dead_without_pristine_bootstrap",
			"%s corpse provenance rejection" % result[0])
	return finish()

func test_life_predicates_are_distinct_and_queries_are_pure() -> bool:
	var sim=Simulator.new(3,1,9);var actor=sim.world.add_entity("hero","A",Vector2i.ZERO)
	var before=sim.snapshot()
	for index in range(20):
		check(sim.world.can_act(actor.id,0),"active can act")
		check(sim.world.occupies_tile(actor.id),"active occupies")
		check(sim.world.is_environment_exposed(actor.id),"active exposed")
		check(sim.world.is_explicit_melee_target(actor.id),"active explicit")
		check(sim.world.is_autonomous_target(actor.id),"active autonomous")
		check(sim.world.is_unresolved_enemy(actor.id),"active unresolved")
	check_eq(sim.snapshot(),before,"predicate purity")
	var row=sim.world.combatant_states[actor.id];actor.health=0;row.life_state="DOWNED"
	row.downed_at=0;row.downed_resolve_at=200;row.downed_source_event_id=1
	var row_before=row.to_dict()
	check(not sim.world.can_act(actor.id,0),"downed cannot act")
	check(sim.world.occupies_tile(actor.id),"downed occupies")
	check(sim.world.is_environment_exposed(actor.id),"downed exposed")
	check(sim.world.is_explicit_melee_target(actor.id),"downed explicit")
	check(not sim.world.is_autonomous_target(actor.id),"downed not autonomous")
	check(sim.world.is_unresolved_enemy(actor.id),"downed unresolved")
	check_eq(row.to_dict(),row_before,"downed query purity")
	return finish()

func test_bleed_snapshot_replay_accepts_every_legal_cadence_state_and_rejects_forgery() -> bool:
	var fresh: Dictionary = _bleed_fixture(0, false)
	var tick1: Dictionary = _bleed_fixture(1, false)
	var tick2: Dictionary = _bleed_fixture(2, false)
	var refreshed: Dictionary = _bleed_fixture(1, true)
	var expired: Dictionary = _bleed_fixture(3, false)
	for pair in [["fresh", fresh], ["tick1", tick1], ["tick2", tick2],
			["refreshed", refreshed], ["expired", expired]]:
		check(not pair[1].is_empty(), "%s fixture built" % pair[0])
		if not pair[1].is_empty():
			check_eq(WorldState.snapshot_restore_error(pair[1]), "", "%s replay accepted" % pair[0])
	if fresh.is_empty() or refreshed.is_empty() or expired.is_empty(): return finish()
	check_eq([fresh.combatant_states[1].status_rows[0].next_tick_at,
		tick1.combatant_states[1].status_rows[0].next_tick_at,
		tick2.combatant_states[1].status_rows[0].next_tick_at], ["100", "200", "300"],
		"fresh/tick1/tick2 next cadence")
	check_eq([fresh.combatant_states[1].status_rows[0].expires_at,
		tick1.combatant_states[1].status_rows[0].expires_at,
		tick2.combatant_states[1].status_rows[0].expires_at], ["300", "300", "300"],
		"expiry remains fixed across ticks")
	check_eq([refreshed.combatant_states[1].status_rows[0].next_tick_at,
		refreshed.combatant_states[1].status_rows[0].expires_at], ["200", "400"],
		"refresh preserves next and extends expiry")
	check(expired.combatant_states[1].status_rows.is_empty(), "third tick must expire row")

	var bad_cadence := tick1.duplicate(true)
	bad_cadence.combatant_states[1].status_rows[0].expires_at = "400"
	check(not WorldState.snapshot_restore_error(bad_cadence).is_empty(), "forged tick cadence rejected")
	var bad_source := refreshed.duplicate(true)
	bad_source.combatant_states[1].status_rows[0].source_event_id = fresh.combatant_states[1].status_rows[0].source_event_id
	check(not WorldState.snapshot_restore_error(bad_source).is_empty(), "stale apply source after refresh rejected")
	var legacy_cross := fresh.duplicate(true)
	for event in legacy_cross.events:
		if event.type == "combat.physical_damage": event.data = {"damage_type":"physical"}; break
	check(not WorldState.snapshot_restore_error(legacy_cross).is_empty(), "canonical status cannot cite legacy damage")
	var extra_data := fresh.duplicate(true)
	for event in extra_data.events:
		if event.type == "status.applied": event.data["extra"] = 1; break
	check(not WorldState.snapshot_restore_error(extra_data).is_empty(), "status exact data keys")
	var extra_envelope := fresh.duplicate(true)
	extra_envelope.events[0]["extra"] = 1
	check_eq(WorldState.snapshot_restore_error(extra_envelope), "invalid_event_shape", "event envelope exact keys")
	var no_natural_expire := expired.duplicate(true)
	for event in no_natural_expire.events:
		if event.type == "status.expired": event.type = "status.tick"; break
	check(not WorldState.snapshot_restore_error(no_natural_expire).is_empty(), "third tick without natural expiry rejected")
	return finish()

func test_status_apply_and_refresh_exact_event_forge_matrix() -> bool:
	var fresh: Dictionary = _bleed_fixture(0, false)
	var refreshed: Dictionary = _bleed_fixture(1, true)
	for fixture in [["status.applied", fresh], ["status.refreshed", refreshed]]:
		check(not fixture[1].is_empty(), "%s fixture built" % fixture[0])
		if not fixture[1].is_empty():
			check_eq(WorldState.snapshot_restore_error(fixture[1]), "",
				"%s canonical baseline restores" % fixture[0])
	var mutations := ["actor", "target", "position", "magnitude", "instigator",
		"extra_data", "missing_data", "schema", "status", "ruleset", "timing",
		"cause", "row_source"]
	var results: Array = []
	for fixture in [["status.applied", fresh], ["status.refreshed", refreshed]]:
		if fixture[1].is_empty(): continue
		for mutation in mutations:
			var forged: Dictionary = _status_apply_or_refresh_forge(
				fixture[1], fixture[0], mutation)
			results.append(["%s %s" % [fixture[0], mutation],
				WorldState.snapshot_restore_error(forged)])
	var accepted: Array = []
	for result in results:
		if result[1].is_empty(): accepted.append(result[0])
	check(accepted.is_empty(), "accepted APPLY/REFRESH forgeries: %s" % [accepted])
	for result in results:
		check(not result[1].is_empty(), "%s forge rejected" % result[0])
	return finish()

func _status_apply_or_refresh_forge(baseline: Dictionary, event_type: String,
		mutation: String) -> Dictionary:
	var forged: Dictionary = baseline.duplicate(true)
	var event_index := -1
	for index in range(forged.events.size()):
		if forged.events[index].type == event_type: event_index = index
	if event_index < 0: return {}
	var event: Dictionary = forged.events[event_index]
	var owner_id: int = int(event.target_id)
	match mutation:
		"actor": event.actor_id = "1"
		"target": event.target_id = "1" if owner_id != 1 else "2"
		"position": event.position = [0, 0] if event.position != [0, 0] else [1, 0]
		"magnitude": event.magnitude = 1
		"instigator": event.instigator_id = event.target_id
		"extra_data": event.data["extra"] = 1
		"missing_data": event.data.erase("tick_damage")
		"schema": event.data.schema_version = 2
		"status": event.data.status_id = "NOT_BLEEDING"
		"ruleset": event.data.status_ruleset_id = "forged-status-ruleset"
		"timing": event.data.next_tick_at = str(int(event.data.next_tick_at) + 1)
		"cause":
			event.cause_id = "1" if event_type == "status.applied" else "2"
		"row_source":
			var row: Dictionary = _combatant_wire(forged, owner_id)
			if not row.is_empty(): row.status_rows[0].source_event_id = "2"
	return forged

func test_status_tick_expire_event_forges_and_downed_tick_child_rejection() -> bool:
	var tick1: Dictionary = _bleed_fixture(1, false)
	var expired: Dictionary = _bleed_fixture(3, false)
	for fixture in [["status.tick", tick1], ["status.expired", expired]]:
		check(not fixture[1].is_empty(), "%s fixture built" % fixture[0])
		if not fixture[1].is_empty():
			check_eq(WorldState.snapshot_restore_error(fixture[1]), "",
				"%s canonical baseline restores" % fixture[0])
	var tick_mutations := ["actor", "target", "position", "magnitude", "instigator",
		"extra_data", "missing_data", "schema", "status", "ruleset", "timing",
		"cause", "row_source", "child_type", "child_cause", "child_target",
		"child_position", "child_step", "child_time", "correlated_position"]
	var expire_mutations := ["actor", "target", "position", "magnitude", "instigator",
		"extra_data", "missing_data", "schema", "status", "ruleset", "timing",
		"cause", "reason", "order"]
	var results: Array = []
	for mutation in tick_mutations:
		var forged: Dictionary = _status_tick_or_expire_forge(tick1, "status.tick", mutation)
		results.append(["status.tick %s" % mutation,
			WorldState.snapshot_restore_error(forged)])
	for mutation in expire_mutations:
		var forged: Dictionary = _status_tick_or_expire_forge(
			expired, "status.expired", mutation)
		results.append(["status.expired %s" % mutation,
			WorldState.snapshot_restore_error(forged)])
	var life_forge: Dictionary = _downed_bleed_physical_tick_child_forge()
	check(not life_forge.is_empty(), "DOWNED BLEED physical tick-child forge built")
	if not life_forge.is_empty():
		var life_error := WorldState.snapshot_restore_error(life_forge)
		check_eq(life_error, "status_tick_life_child_invalid",
			"DOWNED owner cannot receive ACTIVE physical tick child")
		results.append(["DOWNED BLEED physical tick child", life_error])
	var accepted: Array = []
	for result in results:
		if result[1].is_empty(): accepted.append(result[0])
	check(accepted.is_empty(), "accepted TICK/EXPIRED/life forgeries: %s" % [accepted])
	for result in results:
		check(not result[1].is_empty(), "%s forge rejected" % result[0])
	return finish()

func _status_tick_or_expire_forge(baseline: Dictionary, event_type: String,
		mutation: String) -> Dictionary:
	var forged: Dictionary = baseline.duplicate(true)
	var event_index := -1
	for index in range(forged.events.size()):
		if forged.events[index].type == event_type: event_index = index
	if event_index < 0: return {}
	var event: Dictionary = forged.events[event_index]
	var owner_id: int = int(event.target_id)
	match mutation:
		"actor": event.actor_id = "1"
		"target": event.target_id = "1" if owner_id != 1 else "2"
		"position": event.position = [0, 0] if event.position != [0, 0] else [1, 0]
		"magnitude": event.magnitude = 2 if event_type == "status.tick" else 1
		"instigator": event.instigator_id = event.target_id
		"extra_data": event.data["extra"] = 1
		"missing_data": event.data.erase(
			"tick_damage" if event_type == "status.tick" else "reason")
		"schema": event.data.schema_version = 2
		"status": event.data.status_id = "NOT_BLEEDING"
		"ruleset": event.data.status_ruleset_id = "forged-status-ruleset"
		"timing":
			if event_type == "status.tick":
				event.data.scheduled_tick_at = str(int(event.data.scheduled_tick_at) + 1)
			else: event.world_time = str(int(event.world_time) + 1)
		"cause": event.cause_id = "1" if event_type == "status.tick" else "3"
		"row_source":
			var row: Dictionary = _combatant_wire(forged, owner_id)
			if not row.is_empty(): row.status_rows[0].source_event_id = "2"
		"reason": event.data.reason = "OWNER_DIED"
		"child_type": forged.events[event_index + 1].type = "combat.fire_damage"
		"child_cause": forged.events[event_index + 1].cause_id = "3"
		"child_target": forged.events[event_index + 1].target_id = "1"
		"child_position": forged.events[event_index + 1].position = [2, 0]
		"child_step": forged.events[event_index + 1].step_index = "1"
		"child_time": forged.events[event_index + 1].world_time = "101"
		"correlated_position":
			event.position = [2, 0]
			forged.events[event_index + 1].position = [2, 0]
		"order":
			var tick_child: Dictionary = forged.events[event_index - 1].duplicate(true)
			var reordered_expiry: Dictionary = event.duplicate(true)
			reordered_expiry.id = tick_child.id
			tick_child.id = event.id
			forged.events[event_index - 1] = reordered_expiry
			forged.events[event_index] = tick_child
	return forged

func _downed_bleed_physical_tick_child_forge() -> Dictionary:
	var snapshot: Dictionary = _bleed_present_recovery_forge()
	if snapshot.is_empty(): return {}
	var action: Dictionary = {}; var damage: Dictionary = {}; var applied: Dictionary = {}
	var downed_event: Dictionary = {}; var first_tick: Dictionary = {}; var first_child: Dictionary = {}
	for event in snapshot.events:
		match str(event.type):
			"action.melee_attack": if action.is_empty(): action = event
			"combat.physical_damage":
				if damage.is_empty(): damage = event
				elif first_child.is_empty(): first_child = event
			"status.applied": applied = event
			"entity.downed": downed_event = event
			"status.tick": if first_tick.is_empty(): first_tick = event
	if action.is_empty() or damage.is_empty() or applied.is_empty() or downed_event.is_empty() \
			or first_tick.is_empty() or first_child.is_empty(): return {}
	downed_event.id = "3"; applied.id = "4"; first_tick.id = "5"; first_tick.cause_id = "4"
	first_child.id = "6"; first_child.cause_id = "5"
	snapshot.events = [action, damage, downed_event, applied, first_tick, first_child]
	snapshot.next_event_id = "7"; snapshot.step_index = "2"; snapshot.world_time = "100"
	for schedule in snapshot.scheduled_entries: schedule.due_time = "200"
	var target_id: int = int(downed_event.target_id)
	for entity in snapshot.entities:
		if int(entity.id) == target_id: entity.health = 0; break
	var row: Dictionary = _combatant_wire(snapshot, target_id)
	row.life_state = "DOWNED"; row.downed_at = downed_event.world_time
	row.downed_resolve_at = downed_event.data.downed_resolve_at
	row.downed_source_event_id = downed_event.id; row.recovery_lock_until = "0"
	row.recovery_source_event_id = "-1"; row.status_rows[0].next_tick_at = "200"
	row.status_rows[0].source_event_id = applied.id
	return snapshot

func test_canonical_bleedout_snapshot_roundtrip_and_reason_forge() -> bool:
	var canonical: Dictionary = _bleedout_fixture()
	check(not canonical.is_empty(), "canonical BLEEDOUT fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"canonical DOWNED BLEED tick-to-BLEEDOUT restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical BLEEDOUT constructs world")
	if restored != null:
		check_eq(restored.snapshot(), canonical, "canonical BLEEDOUT roundtrip exact")
	var mutations := ["downed_damage_reason", "downed_damage_cause", "tick_source",
		"expiry_cause", "expiry_reason", "death_cause", "death_reason",
		"downed_damage_type", "death_damage_type", "terminal_order", "expiry_gap",
		"downed_damage_instigator", "expiry_instigator", "death_instigator"]
	var results: Array = []
	for mutation in mutations:
		var forged: Dictionary = _bleedout_forge(canonical, mutation)
		results.append([mutation, WorldState.snapshot_restore_error(forged)])
	var accepted: Array = []
	for result in results:
		if result[1].is_empty(): accepted.append(result[0])
	check(accepted.is_empty(), "accepted BLEEDOUT source/reason forgeries: %s" % [accepted])
	for result in results:
		check(not result[1].is_empty(), "BLEEDOUT %s forge rejected" % result[0])
	return finish()

func _bleedout_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var tick_index := -1; var damage_index := -1; var expiry_index := -1; var death_index := -1
	for index in range(forged.events.size()):
		match str(forged.events[index].type):
			"status.tick": tick_index = index
			"combat.downed_damage": damage_index = index
			"status.expired": expiry_index = index
			"entity.died": death_index = index
	if tick_index < 0 or damage_index < 0 or expiry_index < 0 or death_index < 0: return {}
	match mutation:
		"downed_damage_reason": forged.events[damage_index].data.reason = "NOT_BLEEDOUT"
		"downed_damage_cause": forged.events[damage_index].cause_id = "4"
		"tick_source": forged.events[tick_index].cause_id = "3"
		"expiry_cause": forged.events[expiry_index].cause_id = "5"
		"expiry_reason": forged.events[expiry_index].data.reason = "NATURAL"
		"death_cause": forged.events[death_index].cause_id = "5"
		"death_reason": forged.events[death_index].data.reason = "FINISHER"
		"downed_damage_type": forged.events[damage_index].data.damage_type = "fire"
		"death_damage_type": forged.events[death_index].data.damage_type = "fire"
		"terminal_order":
			var expiry: Dictionary = forged.events[expiry_index].duplicate(true)
			var death: Dictionary = forged.events[death_index].duplicate(true)
			death.id = expiry.id; expiry.id = forged.events[death_index].id
			forged.events[expiry_index] = death; forged.events[death_index] = expiry
		"expiry_gap":
			forged.events[expiry_index].id = "8"; forged.events[death_index].id = "9"
			forged.events.insert(expiry_index, {"id":"7", "step_index":"2",
				"world_time":"100", "type":"action.hold", "actor_id":"1", "target_id":"-1",
				"position":[0, 0], "magnitude":100, "cause_id":"-1", "instigator_id":"1",
				"data":{}})
			forged.next_event_id = "10"
			var guard_row: Dictionary = _combatant_wire(forged, 1)
			guard_row.guarded_until = "300"; guard_row.guard_source_event_id = "7"
		"downed_damage_instigator": forged.events[damage_index].instigator_id = "2"
		"expiry_instigator": forged.events[expiry_index].instigator_id = "2"
		"death_instigator": forged.events[death_index].instigator_id = "2"
	return forged

func _bleedout_fixture() -> Dictionary:
	var snapshot: Dictionary = _downed_bleed_physical_tick_child_forge()
	if snapshot.is_empty(): return {}
	var tick_index := -1
	for index in range(snapshot.events.size()):
		if snapshot.events[index].type == "status.tick": tick_index = index
	if tick_index < 0 or tick_index + 1 >= snapshot.events.size(): return {}
	var tick: Dictionary = snapshot.events[tick_index]
	var old_child: Dictionary = snapshot.events[tick_index + 1]
	var downed_damage := {"id":old_child.id, "step_index":tick.step_index,
		"world_time":tick.world_time, "type":"combat.downed_damage", "actor_id":"-1",
		"target_id":tick.target_id, "position":tick.position.duplicate(true), "magnitude":3,
		"cause_id":tick.id, "instigator_id":tick.instigator_id,
		"data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1", "damage_type":"physical",
			"requested_damage":3, "applied_health_damage":0, "reason":"BLEEDOUT"}}
	snapshot.events[tick_index + 1] = downed_damage
	snapshot.events.append({"id":"7", "step_index":tick.step_index,
		"world_time":tick.world_time, "type":"status.expired", "actor_id":"-1",
		"target_id":tick.target_id, "position":tick.position.duplicate(true), "magnitude":0,
		"cause_id":"6", "instigator_id":tick.instigator_id,
		"data":{"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "reason":"OWNER_DIED"}})
	snapshot.events.append({"id":"8", "step_index":tick.step_index,
		"world_time":tick.world_time, "type":"entity.died", "actor_id":"-1",
		"target_id":tick.target_id, "position":tick.position.duplicate(true), "magnitude":0,
		"cause_id":"6", "instigator_id":tick.instigator_id,
		"data":{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"DOWNED", "reason":"BLEEDOUT", "damage_type":"physical"}})
	snapshot.next_event_id = "9"
	var target_id: int = int(tick.target_id); var row: Dictionary = _combatant_wire(snapshot, target_id)
	row.life_state = "DEAD"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = "-1"; row.downed_resolve_at = "-1"; row.downed_source_event_id = "-1"
	row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"; row.status_rows = []
	return snapshot

func test_canonical_active_fire_electric_damage_roundtrip_and_source_whitelist() -> bool:
	var fixtures := {"fire":_active_hazard_fixture("fire"),
		"electric":_active_hazard_fixture("electric")}
	var source_results: Array = []
	for damage_type in ["fire", "electric"]:
		var canonical: Dictionary = fixtures[damage_type]
		check(not canonical.is_empty(), "canonical ACTIVE %s fixture built" % damage_type)
		if canonical.is_empty(): continue
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"canonical ACTIVE %s damage restores" % damage_type)
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "canonical ACTIVE %s constructs world" % damage_type)
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"canonical ACTIVE %s roundtrip exact" % damage_type)
		var forged: Dictionary = canonical.duplicate(true)
		var wrong_source_id := "-1"
		for event in forged.events:
			if event.type == "action.%s" % ("ignite" if damage_type == "fire" else "discharge"):
				wrong_source_id = event.id; break
		for event in forged.events:
			if event.type == "combat.%s_damage" % damage_type:
				event.cause_id = wrong_source_id; break
		source_results.append([damage_type, WorldState.snapshot_restore_error(forged)])
	var accepted: Array = []
	for result in source_results:
		if result[1].is_empty(): accepted.append(result[0])
	check(accepted.is_empty(), "accepted ACTIVE hazard source forgeries: %s" % [accepted])
	for result in source_results:
		check(not result[1].is_empty(), "%s damage wrong source type rejected" % result[0])
	return finish()

func test_typed_fire_electric_damage_three_way_schema_dispatch() -> bool:
	var results: Array = []; var accepted: Array = []
	for damage_type in ["fire", "electric"]:
		var canonical: Dictionary = _active_hazard_fixture(damage_type)
		var legacy: Dictionary = _active_hazard_fixture(damage_type, false)
		check(not canonical.is_empty(), "%s canonical dispatch fixture built" % damage_type)
		check(not legacy.is_empty(), "%s real legacy dispatch fixture built" % damage_type)
		if canonical.is_empty() or legacy.is_empty(): continue
		check_eq(WorldState.snapshot_restore_error(legacy), "",
			"real legacy %s damage restores" % damage_type)
		var restored = Simulator.from_snapshot(legacy)
		check(restored != null, "real legacy %s damage constructs" % damage_type)
		if restored != null:
			check_eq(restored.snapshot(), legacy,
				"real legacy %s damage roundtrip exact" % damage_type)
		for mutation in ["schema_two", "legacy_extra", "mixed_missing"]:
			var forged: Dictionary = canonical.duplicate(true) \
				if mutation != "legacy_extra" else legacy.duplicate(true)
			var found := false
			for event in forged.events:
				if event.type != "combat.%s_damage" % damage_type: continue
				match mutation:
					"schema_two": event.data.schema_version = 2
					"legacy_extra": event.data.extra = 1
					"mixed_missing":
						event.data = {"damage_type":damage_type, "schema_version":1}
				found = true
				break
			var error := "fixture_damage_event_missing" \
				if not found else WorldState.snapshot_restore_error(forged)
			results.append([damage_type, mutation, error])
			if error.is_empty(): accepted.append("%s:%s" % [damage_type, mutation])
	check(accepted.is_empty(), "accepted typed damage dispatch forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[2].is_empty(), "%s %s dispatch forge rejected" \
			% [result[0], result[1]])
	return finish()

func _active_hazard_fixture(damage_type: String, canonical: bool = true) -> Dictionary:
	var sim = Simulator.new(1, 1, 121 if damage_type == "fire" else 122)
	var target = sim.world.add_entity("other", "Hazard Target", Vector2i.ZERO)
	if target == null: return {}
	if damage_type == "fire":
		sim.world.tile_at(Vector2i.ZERO).flammability = 100
		if not sim.step(Command.ignite(Vector2i.ZERO, 50)).accepted: return {}
	else:
		sim.world.tile_at(Vector2i.ZERO).base_conductivity = 30
		if not sim.step(Command.discharge(Vector2i.ZERO, 20)).accepted: return {}
	if target.health <= 0: return {}
	var snapshot = sim.snapshot()
	if not snapshot is Dictionary: return {}
	var found := false
	for event in snapshot.events:
		if event.type != "combat.%s_damage" % damage_type: continue
		if canonical:
			event.data = {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":damage_type, "requested_damage":event.magnitude,
				"applied_health_damage":event.magnitude}
		elif event.data != {"damage_type":damage_type}:
			return {}
		found = true; break
	return snapshot if found else {}

func test_canonical_miss_child_roundtrip_and_exact_contract_forges() -> bool:
	var canonical: Dictionary = _canonical_miss_fixture()
	check(not canonical.is_empty(), "canonical MISS child fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "", "canonical MISS child restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical MISS child constructs world")
	if restored != null:
		check_eq(restored.snapshot(), canonical, "canonical MISS child roundtrip exact")
	var mutations := ["missing", "actor", "target", "position", "magnitude", "cause",
		"instigator", "data_extra", "outcome", "duplicate"]
	var results: Array = []; var accepted: Array = []
	for mutation in mutations:
		var forged: Dictionary = _miss_child_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted MISS child forgeries: %s; errors=%s" % [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "MISS child %s forge rejected" % result[0])
	return finish()

func _canonical_miss_fixture() -> Dictionary:
	var seed_value := 43
	var sim = Simulator.new(2, 1, seed_value)
	var attacker = sim.world.add_entity("hero", "Miss Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Miss Target", Vector2i.RIGHT)
	if attacker == null or target == null or not _begin_fixture_step(sim.world, 0): return {}
	var ordinal := 0
	var key := Melee.commitment_key(seed_value, 1, 0, "PARTY_TURN/1", ordinal,
		attacker.id, target.id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	if hit_roll < 950: return {}
	var action = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
			"batch_context":"PARTY_TURN/1", "intent_ordinal":ordinal, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"MISS",
			"processed_step_index":"1", "attack_start_world_time":"0",
			"commitment_hash":Melee.commitment_hash(key), "hit_chance_milli":950,
			"hit_roll_milli":hit_roll, "bleed_chance_milli":600,
			"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
			"base_damage":24, "target_evasion_milli":100, "armor_flat":2,
			"armor_reduction":2, "frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":0})
	if action == null: return {}
	var miss = sim.world.emit_event("combat.attack_missed", -1, target.id, target.position, 0,
		action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1", "outcome":"MISS"})
	if miss == null: return {}
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _miss_child_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action_index := -1; var child_index := -1
	for index in range(forged.events.size()):
		if forged.events[index].type == "action.melee_attack": action_index = index
		elif forged.events[index].type == "combat.attack_missed": child_index = index
	if action_index < 0 or child_index < 0: return {}
	var action: Dictionary = forged.events[action_index]
	var child: Dictionary = forged.events[child_index]
	match mutation:
		"missing":
			forged.events.remove_at(child_index); forged.next_event_id = child.id
		"actor": child.actor_id = action.actor_id
		"target": child.target_id = action.actor_id
		"position": child.position = [0, 0]
		"magnitude": child.magnitude = 1
		"cause": child.cause_id = "-1"
		"instigator": child.instigator_id = child.target_id
		"data_extra": child.data.extra = 1
		"outcome": child.data.outcome = "HIT"
		"duplicate":
			var duplicate: Dictionary = child.duplicate(true)
			duplicate.id = forged.next_event_id; forged.events.append(duplicate)
			forged.next_event_id = str(int(forged.next_event_id) + 1)
	return forged

func test_canonical_hit_physical_child_cardinality_and_damage_correlation() -> bool:
	var canonical: Dictionary = _canonical_hit_fixture()
	check(not canonical.is_empty(), "canonical HIT physical child fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "", "canonical HIT child restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical HIT child constructs world")
	if restored != null:
		check_eq(restored.snapshot(), canonical, "canonical HIT child roundtrip exact")
	var results: Array = []; var accepted: Array = []
	for mutation in ["missing", "duplicate", "damage_mismatch"]:
		var forged: Dictionary = _hit_child_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted HIT child forgeries: %s; errors=%s" % [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "HIT child %s forge rejected" % result[0])
	return finish()

func _canonical_hit_fixture() -> Dictionary:
	var sim = Simulator.new(2, 1, 142)
	var attacker = sim.world.add_entity("hero", "Hit Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Hit Target", Vector2i.RIGHT)
	if attacker == null or target == null or not _begin_fixture_step(sim.world, 0): return {}
	var candidate: Dictionary = _strike_candidate(142, 1, 0, "PARTY_TURN/1",
		attacker.id, target.id, false)
	if candidate.is_empty(): return {}
	var action = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
			"batch_context":"PARTY_TURN/1", "intent_ordinal":candidate.ordinal,
			"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":"1", "attack_start_world_time":"0",
			"commitment_hash":Melee.commitment_hash(candidate.key), "hit_chance_milli":950,
			"hit_roll_milli":candidate.hit_roll, "bleed_chance_milli":600,
			"bleed_roll_milli":candidate.bleed_roll, "bleed_proc_succeeded":false,
			"base_damage":24, "target_evasion_milli":100, "armor_flat":2,
			"armor_reduction":2, "frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":22})
	if action == null: return {}
	var damage = sim.world.emit_event("combat.physical_damage", -1, target.id,
		target.position, 22, action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1", "damage_type":"physical",
			"requested_damage":22, "applied_health_damage":22})
	if damage == null: return {}
	target.health = 78; sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _hit_child_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var damage_index := -1; var target_id := -1
	for index in range(forged.events.size()):
		if forged.events[index].type == "combat.physical_damage":
			damage_index = index; target_id = int(forged.events[index].target_id); break
	if damage_index < 0: return {}
	var damage: Dictionary = forged.events[damage_index]
	match mutation:
		"missing":
			forged.events.remove_at(damage_index); forged.next_event_id = damage.id
			for entity in forged.entities:
				if int(entity.id) == target_id: entity.health = 100; break
		"duplicate":
			var duplicate: Dictionary = damage.duplicate(true)
			duplicate.id = forged.next_event_id; forged.events.append(duplicate)
			forged.next_event_id = str(int(forged.next_event_id) + 1)
			for entity in forged.entities:
				if int(entity.id) == target_id: entity.health = 56; break
		"damage_mismatch":
			damage.magnitude = 21; damage.data.requested_damage = 21
			damage.data.applied_health_damage = 21
			for entity in forged.entities:
				if int(entity.id) == target_id: entity.health = 79; break
	return forged

func test_canonical_melee_positions_and_actor_bind_to_batch_start_move_history() -> bool:
	var canonical: Dictionary = _move_anchored_canonical_hit_fixture()
	check(not canonical.is_empty(), "MOVE-anchored canonical HIT fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"MOVE-anchored canonical HIT baseline restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "MOVE-anchored canonical HIT baseline constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"MOVE-anchored canonical HIT baseline roundtrip exact")
	var results: Array = []; var accepted: Array = []
	for mutation in ["correlated_target_position", "correlated_actor_swap",
			"coherent_nonadjacent_actor_swap"]:
		var forged: Dictionary = _move_anchored_hit_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted MOVE-history melee forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		if result[0] == "coherent_nonadjacent_actor_swap":
			check_eq(result[1], "canonical_melee_batch_frozen_position_invalid",
				"coherent nonadjacent actor swap rejects at frozen batch geometry")
		else:
			check(not result[1].is_empty(), "%s MOVE-history forge rejected" % result[0])
	return finish()

func test_canonical_melee_coherent_nonadjacent_actor_move_history_exact_error() -> bool:
	var canonical: Dictionary = _move_anchored_canonical_hit_fixture()
	check(not canonical.is_empty(), "coherent nonadjacent actor baseline built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"coherent nonadjacent actor baseline restores")
	var forged: Dictionary = _move_anchored_hit_forge(
		canonical, "coherent_nonadjacent_actor_swap")
	check(not forged.is_empty(), "coherent nonadjacent actor forge built")
	if not forged.is_empty():
		check_eq(WorldState.snapshot_restore_error(forged),
			"canonical_melee_batch_frozen_position_invalid",
			"coherent MOVE history cannot hide nonadjacent frozen attacker")
	return finish()

func _move_anchored_canonical_hit_fixture() -> Dictionary:
	var seed_value := _move_anchored_hit_seed()
	if seed_value < 0: return {}
	var sim = Simulator.new(4, 3, seed_value)
	var attacker = sim.world.add_entity("hero", "Anchored Attacker", Vector2i(0, 1))
	var target = sim.world.add_entity("melee_enemy", "Anchored Target", Vector2i(3, 1))
	var alternate = sim.world.add_entity("hero", "Alternate Attacker", Vector2i(0, 0))
	if attacker == null or target == null or alternate == null \
			or not _begin_fixture_step(sim.world, 0): return {}
	for move in [[attacker.id, Vector2i(1, 1)], [target.id, Vector2i(2, 1)],
			[alternate.id, Vector2i(1, 0)]]:
		var assessment = sim.movement.assess_move(int(move[0]), move[1])
		if not assessment.accepted: return {}
		var definition: Dictionary = Terrain.definition(str(assessment.terrain_id))
		if definition.is_empty() or sim.movement.commit_preflighted_move(int(move[0]),
				move[1], str(assessment.terrain_id), int(definition.move_time_cost)) == null:
			return {}
	sim.world.finish_step()
	if not _begin_fixture_step(sim.world, 50): return {}
	var key := Melee.commitment_key(seed_value, 2, 50, "PARTY_TURN/2", 0,
		attacker.id, target.id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	if hit_roll >= 950 or bleed_roll < 600: return {}
	var action = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
			"batch_context":"PARTY_TURN/2", "intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":"2", "attack_start_world_time":"50",
			"commitment_hash":Melee.commitment_hash(key), "hit_chance_milli":950,
			"hit_roll_milli":hit_roll, "bleed_chance_milli":600,
			"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
			"base_damage":24, "target_evasion_milli":100, "armor_flat":2,
			"armor_reduction":2, "frozen_guarded_until":"0",
			"guard_source_event_id":"-1", "guarded":false,
			"guard_reduction":0, "final_damage":22})
	if action == null: return {}
	var damage = sim.world.emit_event("combat.physical_damage", -1, target.id,
		target.position, 22, action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":22,
			"applied_health_damage":22})
	if damage == null: return {}
	target.health = 78
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _move_anchored_hit_seed() -> int:
	for candidate_seed in range(1, 10000):
		var baseline_key := Melee.commitment_key(candidate_seed, 2, 50,
			"PARTY_TURN/2", 0, 1, 2)
		var alternate_key := Melee.commitment_key(candidate_seed, 2, 50,
			"PARTY_TURN/2", 0, 3, 2)
		if Melee.lane_roll_milli(baseline_key, "HIT") < 950 \
				and Melee.lane_roll_milli(baseline_key, "BLEED") >= 600 \
				and Melee.lane_roll_milli(alternate_key, "HIT") < 950 \
				and Melee.lane_roll_milli(alternate_key, "BLEED") >= 600:
			return candidate_seed
	return -1

func _move_anchored_hit_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action: Dictionary = {}; var damage: Dictionary = {}
	for event in forged.events:
		if event.type == "action.melee_attack": action = event
		elif event.type == "combat.physical_damage": damage = event
	if action.is_empty() or damage.is_empty(): return {}
	match mutation:
		"correlated_target_position":
			for entity in forged.entities:
				if int(entity.id) == int(action.target_id):
					entity.position = [2, 2]
					break
			action.position = [2, 2]
			damage.position = [2, 2]
		"correlated_actor_swap":
			var alternate_id := 3
			for entity in forged.entities:
				if int(entity.id) == alternate_id:
					entity.position = [2, 0]
					break
			action.actor_id = str(alternate_id)
			action.instigator_id = str(alternate_id)
			var key := Melee.commitment_key(int(forged.seed), int(action.step_index),
				int(action.world_time), str(action.data.batch_context),
				int(action.data.intent_ordinal), alternate_id, int(action.target_id))
			action.data.commitment_hash = Melee.commitment_hash(key)
			action.data.hit_roll_milli = Melee.lane_roll_milli(key, "HIT")
			action.data.bleed_roll_milli = Melee.lane_roll_milli(key, "BLEED")
			damage.instigator_id = str(alternate_id)
		"coherent_nonadjacent_actor_swap":
			var alternate_id := 3
			var alternate_move: Dictionary = {}
			for event in forged.events:
				if event.type == "action.move" and int(event.actor_id) == alternate_id:
					alternate_move = event
					break
			if alternate_move.is_empty(): return {}
			alternate_move.position = [0, 1]
			alternate_move.data.from_position = [0, 0]
			alternate_move.data.to_position = [0, 1]
			for entity in forged.entities:
				if int(entity.id) == alternate_id:
					entity.position = [0, 1]
					break
			action.actor_id = str(alternate_id)
			action.instigator_id = str(alternate_id)
			var key := Melee.commitment_key(int(forged.seed), int(action.step_index),
				int(action.world_time), str(action.data.batch_context),
				int(action.data.intent_ordinal), alternate_id, int(action.target_id))
			action.data.commitment_hash = Melee.commitment_hash(key)
			action.data.hit_roll_milli = Melee.lane_roll_milli(key, "HIT")
			action.data.bleed_roll_milli = Melee.lane_roll_milli(key, "BLEED")
			damage.instigator_id = str(alternate_id)
	return forged

func test_canonical_overkill_skip_shadow_and_zero_child_contract() -> bool:
	var canonical: Dictionary = _canonical_overkill_fixture()
	check(not canonical.is_empty(), "canonical all-actions-first OVERKILL_SKIP fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "", "canonical OVERKILL_SKIP restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical OVERKILL_SKIP constructs world")
	if restored != null:
		check_eq(restored.snapshot(), canonical, "canonical OVERKILL_SKIP roundtrip exact")
	var results: Array = []; var accepted: Array = []
	for mutation in ["positive_child", "standalone", "ordinal_gap"]:
		var forged: Dictionary = _overkill_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted OVERKILL_SKIP forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "OVERKILL_SKIP %s forge rejected" % result[0])
	return finish()

func test_canonical_melee_target_life_binds_to_batch_start_projection() -> bool:
	var canonical: Dictionary = _canonical_overkill_fixture()
	check(not canonical.is_empty(), "same-batch life projection baseline built")
	if canonical.is_empty(): return finish()
	var batch_lives: Array = []
	for event in canonical.events:
		if event.type == "action.melee_attack":
			batch_lives.append(event.data.target_life_at_batch_start)
	check_eq(batch_lives, ["ACTIVE", "ACTIVE"],
		"all-actions-first baseline freezes ACTIVE target life for both intents")
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"same-batch life projection baseline restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "same-batch life projection baseline constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"same-batch life projection baseline roundtrip exact")
	var forged: Dictionary = _same_batch_free_finisher_forge(canonical)
	check(not forged.is_empty(), "same-batch free FINISHER forge built")
	if not forged.is_empty():
		var error := WorldState.snapshot_restore_error(forged)
		check(not error.is_empty(),
			"same-batch free FINISHER rejected; actual error=%s" % error)
	return finish()

func test_downed_batch_finisher_then_overkill_shadow_and_dangling_proof() -> bool:
	var canonical: Dictionary = _downed_finisher_overkill_batch_fixture()
	check(not canonical.is_empty(), "pre-DOWNED FINISHER/OVERKILL batch fixture built")
	if canonical.is_empty(): return finish()
	var baseline_error := WorldState.snapshot_restore_error(canonical)
	check_eq(baseline_error, "",
		"pre-DOWNED FINISHER/OVERKILL batch restores; actual=%s" % baseline_error)
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "pre-DOWNED FINISHER/OVERKILL batch constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"pre-DOWNED FINISHER/OVERKILL batch roundtrip exact")
	var dangling: Dictionary = _dangling_downed_overkill_forge(canonical)
	check(not dangling.is_empty(), "dangling pre-DOWNED OVERKILL forge built")
	if not dangling.is_empty():
		var forge_error := WorldState.snapshot_restore_error(dangling)
		check(baseline_error.is_empty() and not forge_error.is_empty(),
			"dangling proof coverage requires legal baseline; baseline=%s forge=%s" \
			% [baseline_error, forge_error])
	return finish()

func test_canonical_multi_target_batch_sort_prefix_and_driver_order_contracts() -> bool:
	var canonical: Dictionary = _multi_target_batch_order_fixture()
	check(not canonical.is_empty(), "multi-target canonical batch-order fixture built")
	if canonical.is_empty(): return finish()
	var baseline_error := WorldState.snapshot_restore_error(canonical)
	check_eq(baseline_error, "", "multi-target canonical batch-order baseline restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "multi-target canonical batch-order baseline constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"multi-target canonical batch-order baseline roundtrip exact")
	var results: Array = []; var accepted: Array = []
	for mutation in ["event_order_ordinals", "interleaved_result", "driver_order",
			"duplicate_actor"]:
		var forged: Dictionary = _multi_target_batch_order_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged) if not forged.is_empty() \
			else "fixture_build_failed"
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(baseline_error.is_empty() and accepted.is_empty(),
		"accepted multi-target batch ordering forgeries: %s; baseline=%s errors=%s" \
		% [accepted, baseline_error, results])
	for result in results:
		check(baseline_error.is_empty() and not result[1].is_empty(),
			"multi-target batch %s ordering forge rejected; actual=%s" \
			% [result[0], result[1]])
	return finish()

func test_canonical_multi_target_result_driver_completes_tail_before_next_ordinal() -> bool:
	var canonical: Dictionary = _multi_target_resolution_tail_fixture()
	check(not canonical.is_empty(), "multi-target resolution-tail fixture built")
	if canonical.is_empty(): return finish()
	var baseline_error := WorldState.snapshot_restore_error(canonical)
	check_eq(baseline_error, "", "multi-target resolution-tail baseline restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "multi-target resolution-tail baseline constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"multi-target resolution-tail baseline roundtrip exact")
	var forged: Dictionary = _multi_target_resolution_tail_interleave_forge(canonical)
	check(not forged.is_empty(), "multi-target resolution-tail interleave forge built")
	if not forged.is_empty():
		var error := WorldState.snapshot_restore_error(forged)
		check_eq(error, "canonical_melee_result_tail_order_invalid",
			"ordinal result tail completes before next driver; actual=%s" % error)
	return finish()

func _multi_target_resolution_tail_fixture() -> Dictionary:
	var seed_value := -1
	for candidate_seed in range(1, 10000):
		var later_key := Melee.commitment_key(candidate_seed, 1, 0,
			"PARTY_TURN/1", 1, 1, 4)
		var first_key := Melee.commitment_key(candidate_seed, 1, 0,
			"PARTY_TURN/1", 0, 2, 3)
		if Melee.lane_roll_milli(later_key, "HIT") < 950 \
				and Melee.lane_roll_milli(later_key, "BLEED") >= 600 \
				and Melee.lane_roll_milli(first_key, "HIT") < 950 \
				and Melee.lane_roll_milli(first_key, "BLEED") < 500:
			seed_value = candidate_seed
			break
	if seed_value < 0: return {}
	var sim = Simulator.new(3, 2, seed_value)
	var later_actor = sim.world.add_entity("hero", "Later-tail Actor", Vector2i(2, 0))
	var first_actor = sim.world.add_entity("companion", "First-tail Actor", Vector2i(0, 0))
	var first_target = sim.world.add_entity("melee_enemy", "First-tail Target",
		Vector2i(0, 1), 22)
	var later_target = sim.world.add_entity("melee_enemy", "Later-tail Target",
		Vector2i(2, 1))
	if later_actor == null or first_actor == null or first_target == null \
			or later_target == null or not _begin_fixture_step(sim.world, 0): return {}
	var later_action = sim.world.emit_event("action.melee_attack", later_actor.id,
		later_target.id, later_target.position, 24, -1, _batch_hit_action_data(
			seed_value, 1, later_actor.id, later_target.id, "party-hero-v1", 600))
	var first_action = sim.world.emit_event("action.melee_attack", first_actor.id,
		first_target.id, first_target.position, 24, -1, _batch_hit_action_data(
			seed_value, 0, first_actor.id, first_target.id,
			"party-companion-v1", 500, true))
	if later_action == null or first_action == null: return {}
	var first_damage = sim.world.emit_event("combat.physical_damage", -1,
		first_target.id, first_target.position, 22, first_action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":22,
			"applied_health_damage":22})
	if first_damage == null: return {}
	first_target.health = 0
	var downed = sim.world.emit_event("entity.downed", -1, first_target.id,
		first_target.position, 0, first_damage.id, {"schema_version":1,
			"life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"ACTIVE", "downed_resolve_at":"200",
			"terminal_immediate":false})
	if downed == null: return {}
	var first_state = sim.world.combatant_states[first_target.id]
	first_state.life_state = "DOWNED"; first_state.guarded_until = 0
	first_state.guard_source_event_id = -1; first_state.downed_at = 0
	first_state.downed_resolve_at = 200; first_state.downed_source_event_id = downed.id
	first_state.recovery_lock_until = 0; first_state.recovery_source_event_id = -1
	var applied = sim.world.emit_event("status.applied", -1, first_target.id,
		first_target.position, 0, first_damage.id, {"schema_version":1,
			"status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "next_tick_at":"100",
			"expires_at":"300", "tick_damage":3})
	if applied == null: return {}
	var status = StatusRow.new("BLEEDING")
	status.applied_at = 0; status.refreshed_at = 0; status.next_tick_at = 100
	status.expires_at = 300; status.source_event_id = applied.id
	first_state.status_rows = [status]
	var later_damage = sim.world.emit_event("combat.physical_damage", -1,
		later_target.id, later_target.position, 22, later_action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":22,
			"applied_health_damage":22})
	if later_damage == null: return {}
	later_target.health = 78
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _multi_target_resolution_tail_interleave_forge(canonical: Dictionary) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var actions: Array = []; var first_damage: Dictionary = {}
	var later_damage: Dictionary = {}; var downed: Dictionary = {}; var applied: Dictionary = {}
	for event in forged.events:
		if event.type == "action.melee_attack": actions.append(event)
		elif event.type == "combat.physical_damage":
			var source: Dictionary = forged.events[int(event.cause_id) - 1]
			if int(source.data.intent_ordinal) == 0: first_damage = event
			else: later_damage = event
		elif event.type == "entity.downed": downed = event
		elif event.type == "status.applied": applied = event
	if actions.size() != 2 or first_damage.is_empty() or later_damage.is_empty() \
			or downed.is_empty() or applied.is_empty(): return {}
	first_damage.id = "3"
	later_damage.id = "4"
	downed.id = "5"; downed.cause_id = "3"
	applied.id = "6"; applied.cause_id = "3"
	forged.events = [actions[0], actions[1], first_damage, later_damage, downed, applied]
	forged.next_event_id = "7"
	var first_target_id: int = int(first_damage.target_id)
	var first_row: Dictionary = _combatant_wire(forged, first_target_id)
	first_row.downed_source_event_id = "5"
	first_row.status_rows[0].source_event_id = "6"
	return forged

func _multi_target_batch_order_fixture() -> Dictionary:
	var seed_value := -1
	for candidate_seed in range(1, 10000):
		var valid := true
		for vector in [[1, 1, 4, 600], [0, 2, 3, 500],
				[0, 1, 4, 600], [1, 2, 3, 500], [0, 1, 3, 600]]:
			var key := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1",
				int(vector[0]), int(vector[1]), int(vector[2]))
			if Melee.lane_roll_milli(key, "HIT") >= 950 \
					or Melee.lane_roll_milli(key, "BLEED") < int(vector[3]):
				valid = false
				break
		if valid:
			seed_value = candidate_seed
			break
	if seed_value < 0: return {}
	var sim = Simulator.new(3, 2, seed_value)
	var first_actor = sim.world.add_entity("hero", "Higher-target Actor", Vector2i(2, 0))
	var second_actor = sim.world.add_entity("companion", "Lower-target Actor", Vector2i(0, 0))
	var lower_target = sim.world.add_entity("melee_enemy", "Lower Target", Vector2i(0, 1))
	var higher_target = sim.world.add_entity("melee_enemy", "Higher Target", Vector2i(2, 1))
	if first_actor == null or second_actor == null or lower_target == null \
			or higher_target == null or not _begin_fixture_step(sim.world, 0): return {}
	# Adapter order intentionally differs from canonical (target_id, attacker_id) order.
	var ordinal_one = sim.world.emit_event("action.melee_attack", first_actor.id,
		higher_target.id, higher_target.position, 24, -1, _batch_hit_action_data(
			seed_value, 1, first_actor.id, higher_target.id, "party-hero-v1", 600))
	var ordinal_zero = sim.world.emit_event("action.melee_attack", second_actor.id,
		lower_target.id, lower_target.position, 24, -1, _batch_hit_action_data(
			seed_value, 0, second_actor.id, lower_target.id, "party-companion-v1", 500))
	if ordinal_one == null or ordinal_zero == null: return {}
	# Result drivers are emitted only after the complete action prefix, in ordinal order.
	for pair in [[ordinal_zero, lower_target], [ordinal_one, higher_target]]:
		var action = pair[0]; var target = pair[1]
		if sim.world.emit_event("combat.physical_damage", -1, target.id,
				target.position, 22, action.id, {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}) == null: return {}
		target.health = 78
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _multi_target_batch_order_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var actions: Array = []; var damages: Array = []
	for event in forged.events:
		if event.type == "action.melee_attack": actions.append(event)
		elif event.type == "combat.physical_damage": damages.append(event)
	if actions.size() != 2 or damages.size() != 2: return {}
	var ordinal_one: Dictionary = actions[0]
	var ordinal_zero: Dictionary = actions[1]
	var zero_damage: Dictionary = damages[0]
	var one_damage: Dictionary = damages[1]
	match mutation:
		"event_order_ordinals":
			ordinal_one.data = _batch_hit_action_data(int(forged.seed), 0,
				int(ordinal_one.actor_id), int(ordinal_one.target_id),
				str(ordinal_one.data.attacker_profile_id),
				int(ordinal_one.data.bleed_chance_milli))
			ordinal_zero.data = _batch_hit_action_data(int(forged.seed), 1,
				int(ordinal_zero.actor_id), int(ordinal_zero.target_id),
				str(ordinal_zero.data.attacker_profile_id),
				int(ordinal_zero.data.bleed_chance_milli))
		"interleaved_result":
			ordinal_zero.id = "1"
			zero_damage.id = "2"; zero_damage.cause_id = "1"
			ordinal_one.id = "3"
			one_damage.id = "4"; one_damage.cause_id = "3"
			forged.events = [ordinal_zero, zero_damage, ordinal_one, one_damage]
		"driver_order":
			one_damage.id = "3"
			zero_damage.id = "4"
			forged.events = [ordinal_one, ordinal_zero, one_damage, zero_damage]
		"duplicate_actor":
			var duplicate_actor_id: int = int(ordinal_one.actor_id)
			for entity in forged.entities:
				if int(entity.id) == duplicate_actor_id:
					entity.position = [1, 0]
					break
			ordinal_zero.actor_id = str(duplicate_actor_id)
			ordinal_zero.instigator_id = str(duplicate_actor_id)
			ordinal_zero.data = _batch_hit_action_data(int(forged.seed), 0,
				duplicate_actor_id, int(ordinal_zero.target_id), "party-hero-v1", 600)
			zero_damage.instigator_id = str(duplicate_actor_id)
	return forged

func _downed_finisher_overkill_batch_fixture() -> Dictionary:
	var seed_value := -1
	for candidate_seed in range(1, 10000):
		var opening_key := Melee.commitment_key(candidate_seed, 1, 0,
			"PARTY_TURN/1", 0, 1, 3)
		if Melee.lane_roll_milli(opening_key, "HIT") < 950 \
				and Melee.lane_roll_milli(opening_key, "BLEED") >= 600:
			seed_value = candidate_seed
			break
	if seed_value < 0: return {}
	var sim = Simulator.new(2, 2, seed_value)
	var attacker = sim.world.add_entity("hero", "Lower Finisher", Vector2i(0, 1))
	var later = sim.world.add_entity("companion", "Later Overkill", Vector2i(1, 0))
	var target = sim.world.add_entity("melee_enemy", "Pre-downed Target", Vector2i(1, 1), 22)
	if attacker == null or later == null or target == null \
			or not _begin_fixture_step(sim.world, 0): return {}
	var target_state = sim.world.combatant_states[target.id]
	var opening_key := Melee.commitment_key(seed_value, 1, 0, "PARTY_TURN/1",
		0, attacker.id, target.id)
	var opening = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
			"batch_context":"PARTY_TURN/1", "intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":"1", "attack_start_world_time":"0",
			"commitment_hash":Melee.commitment_hash(opening_key), "hit_chance_milli":950,
			"hit_roll_milli":Melee.lane_roll_milli(opening_key, "HIT"),
			"bleed_chance_milli":600,
			"bleed_roll_milli":Melee.lane_roll_milli(opening_key, "BLEED"),
			"bleed_proc_succeeded":false, "base_damage":24,
			"target_evasion_milli":100, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":22})
	if opening == null: return {}
	var opening_damage = sim.world.emit_event("combat.physical_damage", -1, target.id,
		target.position, 22, opening.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":22,
			"applied_health_damage":22})
	if opening_damage == null: return {}
	target.health = 0
	var downed = sim.world.emit_event("entity.downed", -1, target.id, target.position, 0,
		opening_damage.id, {"schema_version":1,
			"life_ruleset_id":"active-downed-dead-v1", "previous_life_state":"ACTIVE",
			"downed_resolve_at":"200", "terminal_immediate":false})
	if downed == null: return {}
	target_state.life_state = "DOWNED"
	target_state.guarded_until = 0; target_state.guard_source_event_id = -1
	target_state.downed_at = 0; target_state.downed_resolve_at = 200
	target_state.downed_source_event_id = downed.id
	target_state.recovery_lock_until = 0; target_state.recovery_source_event_id = -1
	target_state.status_rows.clear()
	sim.world.finish_step()
	var downed_snapshot = sim.snapshot()
	if not downed_snapshot is Dictionary or not _begin_fixture_step(sim.world, 100): return {}
	var first_key := Melee.commitment_key(seed_value, 2, 100, "PARTY_TURN/2",
		0, attacker.id, target.id)
	var later_key := Melee.commitment_key(seed_value, 2, 100, "PARTY_TURN/2",
		1, later.id, target.id)
	var first = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, _downed_batch_action_data(first_key, 0,
			"party-hero-v1", "FINISHER"))
	var overkill = sim.world.emit_event("action.melee_attack", later.id, target.id,
		target.position, 24, -1, _downed_batch_action_data(later_key, 1,
			"party-companion-v1", "OVERKILL_SKIP"))
	if first == null or overkill == null: return {}
	var pressure = sim.world.emit_event("combat.downed_damage", -1, target.id,
		target.position, 22, first.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":22,
			"applied_health_damage":0, "reason":"FINISHER"})
	if pressure == null: return {}
	var death = sim.world.emit_event("entity.died", -1, target.id, target.position, 0,
		pressure.id, {"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"DOWNED", "reason":"FINISHER",
			"damage_type":"physical"})
	if death == null: return {}
	var snapshot: Dictionary = downed_snapshot.duplicate(true)
	snapshot.events.append(first.to_dict()); snapshot.events.append(overkill.to_dict())
	snapshot.events.append(pressure.to_dict()); snapshot.events.append(death.to_dict())
	snapshot.next_event_id = str(int(snapshot.next_event_id) + 4)
	snapshot.step_index = "2"; snapshot.world_time = "100"
	for schedule in snapshot.scheduled_entries: schedule.due_time = "200"
	var row: Dictionary = _combatant_wire(snapshot, target.id)
	row.life_state = "DEAD"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = "-1"; row.downed_resolve_at = "-1"; row.downed_source_event_id = "-1"
	row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"; row.status_rows = []
	return snapshot

func _downed_batch_action_data(key: String, ordinal: int, attacker_profile: String,
		outcome: String) -> Dictionary:
	return {"schema_version":1,
		"combat_ruleset_id":"deterministic-melee-resolution-v1",
		"attacker_profile_id":attacker_profile, "target_profile_id":"party-goblin-v1",
		"batch_context":"PARTY_TURN/2", "intent_ordinal":ordinal,
		"intent_mode":"FINISHER", "target_life_at_batch_start":"DOWNED",
		"outcome":outcome, "processed_step_index":"2",
		"attack_start_world_time":"100", "commitment_hash":Melee.commitment_hash(key),
		"hit_chance_milli":1000, "hit_roll_milli":Melee.lane_roll_milli(key, "HIT"),
		"bleed_chance_milli":0, "bleed_roll_milli":Melee.lane_roll_milli(key, "BLEED"),
		"bleed_proc_succeeded":false, "base_damage":24, "target_evasion_milli":100,
		"armor_flat":2, "armor_reduction":2, "frozen_guarded_until":"0",
		"guard_source_event_id":"-1", "guarded":false, "guard_reduction":0,
		"final_damage":0}

func _dangling_downed_overkill_forge(canonical: Dictionary) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var downed: Dictionary = {}; var first_terminal_id := -1
	for event in forged.events:
		if event.type == "entity.downed": downed = event
		elif event.type == "combat.downed_damage" and first_terminal_id < 0:
			first_terminal_id = int(event.id)
	if downed.is_empty() or first_terminal_id < 0: return {}
	forged.events = forged.events.slice(0, first_terminal_id - 1)
	forged.next_event_id = str(first_terminal_id)
	var target_id: int = int(downed.target_id)
	var row: Dictionary = _combatant_wire(forged, target_id)
	row.life_state = "DOWNED"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = downed.world_time; row.downed_resolve_at = downed.data.downed_resolve_at
	row.downed_source_event_id = downed.id
	row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"; row.status_rows = []
	return forged

func _same_batch_free_finisher_forge(canonical: Dictionary) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action: Dictionary = {}
	for event in forged.events:
		if event.type == "action.melee_attack" \
				and event.data.get("outcome", "") == "OVERKILL_SKIP":
			action = event
			break
	if action.is_empty(): return {}
	var key := Melee.commitment_key(int(forged.seed), int(action.step_index),
		int(action.world_time), str(action.data.batch_context),
		int(action.data.intent_ordinal), int(action.actor_id), int(action.target_id))
	action.data.target_life_at_batch_start = "DOWNED"
	action.data.intent_mode = "FINISHER"
	action.data.outcome = "FINISHER"
	action.data.commitment_hash = Melee.commitment_hash(key)
	action.data.hit_chance_milli = 1000
	action.data.hit_roll_milli = Melee.lane_roll_milli(key, "HIT")
	action.data.bleed_chance_milli = 0
	action.data.bleed_roll_milli = Melee.lane_roll_milli(key, "BLEED")
	action.data.bleed_proc_succeeded = false
	action.data.guarded = false
	action.data.guard_reduction = 0
	action.data.final_damage = 0
	var pressure_id: String = forged.next_event_id
	forged.events.append({"id":pressure_id, "step_index":action.step_index,
		"world_time":action.world_time, "type":"combat.downed_damage", "actor_id":"-1",
		"target_id":action.target_id, "position":action.position.duplicate(true),
		"magnitude":22, "cause_id":action.id, "instigator_id":action.instigator_id,
		"data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":22,
			"applied_health_damage":0, "reason":"FINISHER"}})
	var death_id := str(int(pressure_id) + 1)
	forged.events.append({"id":death_id, "step_index":action.step_index,
		"world_time":action.world_time, "type":"entity.died", "actor_id":"-1",
		"target_id":action.target_id, "position":action.position.duplicate(true),
		"magnitude":0, "cause_id":pressure_id, "instigator_id":action.instigator_id,
		"data":{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"DOWNED", "reason":"FINISHER",
			"damage_type":"physical"}})
	forged.next_event_id = str(int(death_id) + 1)
	var target_id: int = int(action.target_id)
	for entity in forged.entities:
		if int(entity.id) == target_id:
			entity.health = 0
			break
	var row: Dictionary = _combatant_wire(forged, target_id)
	row.life_state = "DEAD"
	row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = "-1"; row.downed_resolve_at = "-1"
	row.downed_source_event_id = "-1"
	row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"
	row.status_rows = []
	return forged

func _canonical_overkill_fixture() -> Dictionary:
	var seed_value := -1
	for candidate_seed in range(1, 1000):
		var key := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1", 0, 1, 3)
		if Melee.lane_roll_milli(key, "HIT") < 950 \
				and Melee.lane_roll_milli(key, "BLEED") >= 600:
			seed_value = candidate_seed; break
	if seed_value < 0: return {}
	var sim = Simulator.new(2, 2, seed_value)
	var attacker = sim.world.add_entity("hero", "Batch Attacker", Vector2i.ZERO)
	var later = sim.world.add_entity("companion", "Batch Later Actor", Vector2i.RIGHT)
	var target = sim.world.add_entity("melee_enemy", "Batch Target", Vector2i(1, 1), 22)
	if attacker == null or later == null or target == null \
			or not _begin_fixture_step(sim.world, 0): return {}
	var hit = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, _overkill_action_data(
			seed_value, 0, attacker.id, target.id, "party-hero-v1", 600, "HIT"))
	var overkill = sim.world.emit_event("action.melee_attack", later.id, target.id,
		target.position, 24, -1, _overkill_action_data(
			seed_value, 1, later.id, target.id, "party-companion-v1", 500,
			"OVERKILL_SKIP"))
	if hit == null or overkill == null: return {}
	var damage = sim.world.emit_event("combat.physical_damage", -1, target.id,
		target.position, 22, hit.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1", "damage_type":"physical",
			"requested_damage":22, "applied_health_damage":22})
	if damage == null: return {}
	target.health = 0
	var downed = sim.world.emit_event("entity.downed", -1, target.id, target.position, 0,
		damage.id, {"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"ACTIVE", "downed_resolve_at":"200",
			"terminal_immediate":false})
	if downed == null: return {}
	var row = sim.world.combatant_states[target.id]
	row.life_state = "DOWNED"; row.guarded_until = 0; row.guard_source_event_id = -1
	row.downed_at = 0; row.downed_resolve_at = 200; row.downed_source_event_id = downed.id
	row.recovery_lock_until = 0; row.recovery_source_event_id = -1; row.status_rows.clear()
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _overkill_action_data(seed_value: int, ordinal: int, attacker_id: int,
		target_id: int, attacker_profile_id: String, bleed_chance: int,
		outcome: String) -> Dictionary:
	var key := Melee.commitment_key(seed_value, 1, 0, "PARTY_TURN/1", ordinal,
		attacker_id, target_id)
	return {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"attacker_profile_id":attacker_profile_id, "target_profile_id":"party-goblin-v1",
		"batch_context":"PARTY_TURN/1", "intent_ordinal":ordinal, "intent_mode":"STRIKE",
		"target_life_at_batch_start":"ACTIVE", "outcome":outcome,
		"processed_step_index":"1", "attack_start_world_time":"0",
		"commitment_hash":Melee.commitment_hash(key), "hit_chance_milli":950,
		"hit_roll_milli":Melee.lane_roll_milli(key, "HIT"), "bleed_chance_milli":bleed_chance,
		"bleed_roll_milli":Melee.lane_roll_milli(key, "BLEED"), "bleed_proc_succeeded":false,
		"base_damage":24, "target_evasion_milli":100, "armor_flat":2,
		"armor_reduction":2, "frozen_guarded_until":"0", "guard_source_event_id":"-1",
		"guarded":false, "guard_reduction":0, "final_damage":22 if outcome == "HIT" else 0}

func _overkill_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var overkill: Dictionary = {}; var target_id := -1
	for event in forged.events:
		if event.type == "action.melee_attack" and event.data.outcome == "OVERKILL_SKIP":
			overkill = event; target_id = int(event.target_id); break
	if overkill.is_empty(): return {}
	match mutation:
		"positive_child":
			forged.events.append({"id":forged.next_event_id, "step_index":overkill.step_index,
				"world_time":overkill.world_time, "type":"combat.physical_damage", "actor_id":"-1",
				"target_id":overkill.target_id, "position":overkill.position.duplicate(true),
				"magnitude":1, "cause_id":overkill.id, "instigator_id":overkill.instigator_id,
				"data":{"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":1,
					"applied_health_damage":1}})
			forged.next_event_id = str(int(forged.next_event_id) + 1)
		"standalone":
			overkill.id = "1"; overkill.data = _overkill_action_data(int(forged.seed), 0,
				int(overkill.actor_id), target_id, str(overkill.data.attacker_profile_id),
				int(overkill.data.bleed_chance_milli), "OVERKILL_SKIP")
			forged.events = [overkill]; forged.next_event_id = "2"
			for entity in forged.entities:
				if int(entity.id) == target_id: entity.health = int(entity.max_health); break
			var row: Dictionary = _combatant_wire(forged, target_id)
			row.life_state = "ACTIVE"; row.downed_at = "-1"; row.downed_resolve_at = "-1"
			row.downed_source_event_id = "-1"; row.recovery_lock_until = "0"
			row.recovery_source_event_id = "-1"; row.status_rows = []
		"ordinal_gap":
			overkill.data = _overkill_action_data(int(forged.seed), 2,
				int(overkill.actor_id), target_id, str(overkill.data.attacker_profile_id),
				int(overkill.data.bleed_chance_milli), "OVERKILL_SKIP")
	return forged

func test_non_overkill_canonical_batch_ordinals_are_contiguous_and_unique() -> bool:
	var batch: Dictionary = _two_hit_batch_fixture()
	var singleton: Dictionary = _singleton_hit_from_batch(batch)
	for pair in [["singleton", singleton], ["two-action batch", batch]]:
		check(not pair[1].is_empty(), "%s ordinal fixture built" % pair[0])
		if not pair[1].is_empty():
			check_eq(WorldState.snapshot_restore_error(pair[1]), "",
				"%s ordinal baseline restores" % pair[0])
	if batch.is_empty() or singleton.is_empty(): return finish()
	var cases := [["singleton ordinal two", _non_overkill_ordinal_forge(singleton, "singleton_two")],
		["duplicate ordinals", _non_overkill_ordinal_forge(batch, "duplicate")],
		["batch ordinal gap", _non_overkill_ordinal_forge(batch, "gap")]]
	var results: Array = []; var accepted: Array = []
	for pair in cases:
		var error := WorldState.snapshot_restore_error(pair[1])
		results.append([pair[0], error])
		if error.is_empty(): accepted.append(pair[0])
	check(accepted.is_empty(), "accepted non-OVERKILL ordinal forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "%s rejected" % result[0])
	return finish()

func _two_hit_batch_fixture() -> Dictionary:
	var seed_value := -1
	for candidate_seed in range(1, 10000):
		var hero0 := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1", 0, 1, 3)
		var hero2 := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1", 2, 1, 3)
		var companion0 := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1", 0, 2, 3)
		var companion1 := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1", 1, 2, 3)
		var companion2 := Melee.commitment_key(candidate_seed, 1, 0, "PARTY_TURN/1", 2, 2, 3)
		if Melee.lane_roll_milli(hero0, "HIT") < 950 \
				and Melee.lane_roll_milli(hero0, "BLEED") >= 600 \
				and Melee.lane_roll_milli(hero2, "HIT") < 950 \
				and Melee.lane_roll_milli(hero2, "BLEED") >= 600 \
				and Melee.lane_roll_milli(companion0, "HIT") < 950 \
				and Melee.lane_roll_milli(companion0, "BLEED") >= 500 \
				and Melee.lane_roll_milli(companion1, "HIT") < 950 \
				and Melee.lane_roll_milli(companion1, "BLEED") >= 500 \
				and Melee.lane_roll_milli(companion2, "HIT") < 950 \
				and Melee.lane_roll_milli(companion2, "BLEED") >= 500:
			seed_value = candidate_seed; break
	if seed_value < 0: return {}
	var sim = Simulator.new(3, 2, seed_value)
	var hero = sim.world.add_entity("hero", "Ordinal Hero", Vector2i.ZERO)
	var companion = sim.world.add_entity("companion", "Ordinal Companion", Vector2i.RIGHT)
	var target = sim.world.add_entity("melee_enemy", "Ordinal Target", Vector2i(1, 1))
	if hero == null or companion == null or target == null \
			or not _begin_fixture_step(sim.world, 0): return {}
	var first = sim.world.emit_event("action.melee_attack", hero.id, target.id,
		target.position, 24, -1, _batch_hit_action_data(
			seed_value, 0, hero.id, target.id, "party-hero-v1", 600))
	var second = sim.world.emit_event("action.melee_attack", companion.id, target.id,
		target.position, 24, -1, _batch_hit_action_data(
			seed_value, 1, companion.id, target.id, "party-companion-v1", 500))
	if first == null or second == null: return {}
	for action in [first, second]:
		if sim.world.emit_event("combat.physical_damage", -1, target.id, target.position, 22,
				action.id, {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}) == null: return {}
	target.health = 56; sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _batch_hit_action_data(seed_value: int, ordinal: int, attacker_id: int,
		target_id: int, attacker_profile_id: String, bleed_chance: int,
		bleed_proc: bool = false) -> Dictionary:
	var key := Melee.commitment_key(seed_value, 1, 0, "PARTY_TURN/1", ordinal,
		attacker_id, target_id)
	return {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"attacker_profile_id":attacker_profile_id, "target_profile_id":"party-goblin-v1",
		"batch_context":"PARTY_TURN/1", "intent_ordinal":ordinal, "intent_mode":"STRIKE",
		"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
		"processed_step_index":"1", "attack_start_world_time":"0",
		"commitment_hash":Melee.commitment_hash(key), "hit_chance_milli":950,
		"hit_roll_milli":Melee.lane_roll_milli(key, "HIT"),
		"bleed_chance_milli":bleed_chance, "bleed_roll_milli":Melee.lane_roll_milli(key, "BLEED"),
		"bleed_proc_succeeded":bleed_proc, "base_damage":24, "target_evasion_milli":100,
		"armor_flat":2, "armor_reduction":2, "frozen_guarded_until":"0",
		"guard_source_event_id":"-1", "guarded":false, "guard_reduction":0,
		"final_damage":22}

func _singleton_hit_from_batch(batch: Dictionary) -> Dictionary:
	if batch.is_empty(): return {}
	var singleton: Dictionary = batch.duplicate(true)
	var action: Dictionary = {}; var damage: Dictionary = {}
	for event in singleton.events:
		if event.type == "action.melee_attack" and int(event.data.intent_ordinal) == 0: action = event
	if action.is_empty(): return {}
	for event in singleton.events:
		if event.type == "combat.physical_damage" and event.cause_id == action.id: damage = event; break
	if damage.is_empty(): return {}
	damage.id = "2"; damage.cause_id = "1"; singleton.events = [action, damage]
	singleton.next_event_id = "3"
	for entity in singleton.entities:
		if int(entity.id) == int(action.target_id): entity.health = 78; break
	return singleton

func _non_overkill_ordinal_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var actions: Array = forged.events.filter(func(event):
		return event.type == "action.melee_attack")
	if actions.is_empty(): return {}
	var action: Dictionary = actions[0] if mutation == "singleton_two" else actions[1]
	var new_ordinal := 0 if mutation == "duplicate" else 2
	var profile_id: String = str(action.data.attacker_profile_id)
	var bleed_chance := 600 if profile_id == "party-hero-v1" else 500
	action.data = _batch_hit_action_data(int(forged.seed), new_ordinal,
		int(action.actor_id), int(action.target_id), profile_id, bleed_chance)
	return forged

func test_canonical_downed_fire_electric_hazard_roundtrip_and_source_reason_forges() -> bool:
	var results: Array = []
	for damage_type in ["fire", "electric"]:
		var canonical: Dictionary = _downed_hazard_fixture(damage_type)
		check(not canonical.is_empty(), "canonical DOWNED %s HAZARD fixture built" % damage_type)
		if canonical.is_empty(): continue
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"canonical DOWNED %s HAZARD restores" % damage_type)
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "canonical DOWNED %s HAZARD constructs world" % damage_type)
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"canonical DOWNED %s HAZARD roundtrip exact" % damage_type)
		var bad_reason := canonical.duplicate(true)
		var bad_source := canonical.duplicate(true); var action_source_id := "-1"
		for event in bad_reason.events:
			if event.type == "combat.downed_damage": event.data.reason = "NOT_HAZARD"; break
		for event in bad_source.events:
			if event.type == "action.%s" % ("ignite" if damage_type == "fire" else "discharge"):
				action_source_id = event.id; break
		for event in bad_source.events:
			if event.type == "combat.downed_damage": event.cause_id = action_source_id; break
		results.append(["%s reason" % damage_type,
			WorldState.snapshot_restore_error(bad_reason)])
		results.append(["%s source" % damage_type,
			WorldState.snapshot_restore_error(bad_source)])
	var accepted: Array = []
	for result in results:
		if result[1].is_empty(): accepted.append(result[0])
	check(accepted.is_empty(), "accepted DOWNED HAZARD forgeries: %s" % [accepted])
	for result in results:
		check(not result[1].is_empty(), "DOWNED HAZARD %s forge rejected" % result[0])
	return finish()

func _downed_hazard_fixture(damage_type: String) -> Dictionary:
	var downed: Dictionary = _downed_only_fixture()
	if downed.is_empty(): return {}
	var sim = Simulator.from_snapshot(downed)
	if sim == null or not _begin_fixture_step(sim.world, 100): return {}
	var downed_event = sim.world.event_by_id(3)
	if downed_event == null: return {}
	var target_id: int = downed_event.target_id
	var target = sim.world.entities[target_id]; var action = null; var source = null
	if damage_type == "fire":
		sim.world.tile_at(target.position).flammability = 100
		action = sim.world.emit_event("action.ignite", -1, -1, target.position, 50)
		if action == null or not sim.environment.ignite(target.position, 50, action.id, 2): return {}
		for event in sim.world.events:
			if event.type == "environment.ignited": source = event
	else:
		sim.world.tile_at(target.position).base_conductivity = 30
		action = sim.world.emit_event("action.discharge", -1, -1, target.position, 20)
		if action == null or not sim.environment.discharge(target.position, 20, action.id, 2): return {}
		for event in sim.world.events:
			if event.type == "environment.electric_arc" and event.position == target.position:
				source = event; break
	if source == null: return {}
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	if not snapshot is Dictionary: return {}
	var pressure_id: int = int(snapshot.next_event_id); var death_id := pressure_id + 1
	var position_wire := [target.position.x, target.position.y]
	snapshot.events.append({"id":str(pressure_id), "step_index":str(source.step_index),
		"world_time":str(source.world_time), "type":"combat.downed_damage", "actor_id":"-1",
		"target_id":str(target_id), "position":position_wire.duplicate(), "magnitude":20,
		"cause_id":str(source.id), "instigator_id":str(source.instigator_id),
		"data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":damage_type, "requested_damage":20,
			"applied_health_damage":0, "reason":"HAZARD"}})
	snapshot.events.append({"id":str(death_id), "step_index":str(source.step_index),
		"world_time":str(source.world_time), "type":"entity.died", "actor_id":"-1",
		"target_id":str(target_id), "position":position_wire.duplicate(), "magnitude":0,
		"cause_id":str(pressure_id), "instigator_id":str(source.instigator_id),
		"data":{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"DOWNED", "reason":"HAZARD", "damage_type":damage_type}})
	snapshot.next_event_id = str(death_id + 1)
	var row: Dictionary = _combatant_wire(snapshot, target_id)
	row.life_state = "DEAD"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = "-1"; row.downed_resolve_at = "-1"; row.downed_source_event_id = "-1"
	row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"; row.status_rows = []
	return snapshot

func _downed_only_fixture() -> Dictionary:
	var snapshot: Dictionary = _finisher_fixture().duplicate(true)
	if snapshot.is_empty(): return {}
	var downed_event: Dictionary = {}
	for event in snapshot.events:
		if event.type == "entity.downed": downed_event = event; break
	if downed_event.is_empty(): return {}
	snapshot.events = snapshot.events.slice(0, int(downed_event.id))
	snapshot.next_event_id = str(int(downed_event.id) + 1)
	snapshot.step_index = downed_event.step_index; snapshot.world_time = downed_event.world_time
	for schedule in snapshot.scheduled_entries: schedule.due_time = "100"
	var target_id: int = int(downed_event.target_id)
	for entity in snapshot.entities:
		if int(entity.id) == target_id: entity.health = 0; break
	var row: Dictionary = _combatant_wire(snapshot, target_id)
	row.life_state = "DOWNED"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = downed_event.world_time; row.downed_resolve_at = downed_event.data.downed_resolve_at
	row.downed_source_event_id = downed_event.id; row.recovery_lock_until = "0"
	row.recovery_source_event_id = "-1"; row.status_rows = []
	return snapshot

func test_canonical_protagonist_party_defeat_roundtrip_and_death_forges() -> bool:
	var canonical: Dictionary = _party_defeat_fixture()
	check(not canonical.is_empty(), "canonical protagonist PARTY_DEFEAT fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"canonical protagonist PARTY_DEFEAT restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical protagonist PARTY_DEFEAT constructs world")
	if restored != null:
		check_eq(restored.snapshot(), canonical, "canonical protagonist PARTY_DEFEAT roundtrip exact")
	var results: Array = []
	for mutation in ["death_reason", "death_cause", "terminal_order"]:
		var forged: Dictionary = _party_defeat_forge(canonical, mutation)
		results.append([mutation, WorldState.snapshot_restore_error(forged)])
	var accepted: Array = []
	for result in results:
		if result[1].is_empty(): accepted.append(result[0])
	check(accepted.is_empty(), "accepted PARTY_DEFEAT forgeries: %s" % [accepted])
	for result in results:
		check(not result[1].is_empty(), "PARTY_DEFEAT %s forge rejected" % result[0])
	return finish()

func test_protagonist_dead_owner_cannot_receive_posthumous_bleed_apply() -> bool:
	var forged: Dictionary = _party_dead_posthumous_bleed_forge()
	check(not forged.is_empty(), "posthumous protagonist BLEED apply fixture built")
	if forged.is_empty(): return finish()
	var error := WorldState.snapshot_restore_error(forged)
	check_eq(error, "status_apply_owner_life_invalid",
		"BLEED cannot be applied after owner projects DEAD; actual=%s" % error)
	return finish()

func _party_dead_posthumous_bleed_forge() -> Dictionary:
	var snapshot: Dictionary = _party_defeat_fixture().duplicate(true)
	if snapshot.is_empty(): return {}
	var seed_value := -1
	var context := "PARTY_ENEMY/1/100"
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, 1, 100,
			context, 0, 4, 1)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 900 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") < 300:
			seed_value = candidate_seed
			break
	if seed_value < 0: return {}
	snapshot.seed = str(seed_value)
	for entity in snapshot.entities:
		if int(entity.id) == 4:
			entity.position = [8, 7]
			break
	var key := Melee.commitment_key(seed_value, 1, 100, context, 0, 4, 1)
	var action := {"id":"3", "step_index":"1", "world_time":"100",
		"type":"action.melee_attack", "actor_id":"4", "target_id":"1",
		"position":[7, 7], "magnitude":16, "cause_id":"-1", "instigator_id":"4",
		"data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-goblin-v1",
			"target_profile_id":"party-hero-v1", "batch_context":context,
			"intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":"1", "attack_start_world_time":"100",
			"commitment_hash":Melee.commitment_hash(key), "hit_chance_milli":900,
			"hit_roll_milli":Melee.lane_roll_milli(key, "HIT"),
			"bleed_chance_milli":300,
			"bleed_roll_milli":Melee.lane_roll_milli(key, "BLEED"),
			"bleed_proc_succeeded":true, "base_damage":16,
			"target_evasion_milli":150, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":14}}
	var physical := {"id":"4", "step_index":"1", "world_time":"100",
		"type":"combat.physical_damage", "actor_id":"-1", "target_id":"1",
		"position":[7, 7], "magnitude":5, "cause_id":"3", "instigator_id":"4",
		"data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":14,
			"applied_health_damage":5}}
	var downed: Dictionary = snapshot.events[3].duplicate(true)
	downed.id = "5"; downed.cause_id = "4"; downed.instigator_id = "4"
	var death: Dictionary = snapshot.events[4].duplicate(true)
	death.id = "6"; death.cause_id = "5"; death.instigator_id = "4"
	death.data.damage_type = "physical"
	var later_two: Dictionary = snapshot.events[5].duplicate(true)
	var later_three: Dictionary = snapshot.events[6].duplicate(true)
	later_two.id = "7"; later_three.id = "8"
	var applied := {"id":"9", "step_index":"1", "world_time":"100",
		"type":"status.applied", "actor_id":"-1", "target_id":"1",
		"position":[7, 7], "magnitude":0, "cause_id":"4", "instigator_id":"4",
		"data":{"schema_version":1,
			"status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "next_tick_at":"200",
			"expires_at":"400", "tick_damage":3}}
	var expired := {"id":"10", "step_index":"1", "world_time":"100",
		"type":"status.expired", "actor_id":"-1", "target_id":"1",
		"position":[7, 7], "magnitude":0, "cause_id":"5", "instigator_id":"4",
		"data":{"schema_version":1,
			"status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "reason":"OWNER_DIED"}}
	snapshot.events = [snapshot.events[0], snapshot.events[1], action, physical,
		downed, death, later_two, later_three, applied, expired]
	snapshot.next_event_id = "11"
	var hero_row: Dictionary = _combatant_wire(snapshot, 1)
	hero_row.status_rows = []
	return snapshot

func _party_defeat_fixture() -> Dictionary:
	var session = Session.new(910, 808); var state = session.sim.world.party_encounter
	var hero_id: int = state.protagonist_id
	session.sim.world.entities[hero_id].health = 5
	if session.sim.world.bootstrap_set_fire(state.group_anchor, 100) == null: return {}
	if not session.commit_exploration(Command.wait(hero_id)).accepted: return {}
	var snapshot = session.sim.snapshot()
	if not snapshot is Dictionary: return {}
	var damage_index := -1; var death_index := -1
	for index in range(snapshot.events.size()):
		var event: Dictionary = snapshot.events[index]
		if event.type == "combat.fire_damage" and int(event.target_id) == hero_id:
			damage_index = index
		elif event.type == "entity.died" and int(event.target_id) == hero_id:
			death_index = index; break
	if damage_index < 0 or death_index != damage_index + 1: return {}
	var damage: Dictionary = snapshot.events[damage_index]
	var legacy_death: Dictionary = snapshot.events[death_index]
	damage.data = {"schema_version":1,
		"combat_ruleset_id":"deterministic-melee-resolution-v1", "damage_type":"fire",
		"requested_damage":20, "applied_health_damage":damage.magnitude}
	var old_death_id: int = int(legacy_death.id)
	for index in range(death_index + 1, snapshot.events.size()):
		var later: Dictionary = snapshot.events[index]
		later.id = str(int(later.id) + 1)
		if int(later.cause_id) == old_death_id: later.cause_id = str(old_death_id + 1)
		elif int(later.cause_id) > old_death_id: later.cause_id = str(int(later.cause_id) + 1)
	var downed := {"id":str(old_death_id), "step_index":damage.step_index,
		"world_time":damage.world_time, "type":"entity.downed", "actor_id":"-1",
		"target_id":damage.target_id, "position":damage.position.duplicate(true), "magnitude":0,
		"cause_id":damage.id, "instigator_id":damage.instigator_id,
		"data":{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"ACTIVE", "downed_resolve_at":"-1",
			"terminal_immediate":true}}
	var canonical_death := {"id":str(old_death_id + 1), "step_index":damage.step_index,
		"world_time":damage.world_time, "type":"entity.died", "actor_id":"-1",
		"target_id":damage.target_id, "position":damage.position.duplicate(true), "magnitude":0,
		"cause_id":str(old_death_id), "instigator_id":damage.instigator_id,
		"data":{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"DOWNED", "reason":"PARTY_DEFEAT", "damage_type":"fire"}}
	snapshot.events[death_index] = downed
	snapshot.events.insert(death_index + 1, canonical_death)
	snapshot.next_event_id = str(int(snapshot.next_event_id) + 1)
	return snapshot

func _party_defeat_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var downed_index := -1; var death_index := -1; var damage_id := "-1"
	for index in range(forged.events.size()):
		var event: Dictionary = forged.events[index]
		if event.type == "combat.fire_damage": damage_id = event.id
		elif event.type == "entity.downed": downed_index = index
		elif event.type == "entity.died": death_index = index
	if downed_index < 0 or death_index < 0: return {}
	match mutation:
		"death_reason": forged.events[death_index].data.reason = "HAZARD"
		"death_cause": forged.events[death_index].cause_id = damage_id
		"terminal_order":
			var downed: Dictionary = forged.events[downed_index].duplicate(true)
			var death: Dictionary = forged.events[death_index].duplicate(true)
			death.id = downed.id; death.cause_id = damage_id; downed.id = forged.events[death_index].id
			forged.events[downed_index] = death; forged.events[death_index] = downed
	return forged

func test_party_assessment_nullable_hidden_rolls_deep_copy_and_tamper_noop() -> bool:
	var session=_engaged_adjacent();var world=session.sim.world;var state=world.party_encounter
	var request=Request.new(Action.melee(state.protagonist_id,state.enemy_ids[0]),[])
	var before=session.sim.snapshot()
	check(before is Dictionary,"engaged snapshot: %s"%session.sim.world.world_state_error())
	if not before is Dictionary:return finish()
	var plan=session.sim.preview_party_turn(request)
	check_eq(session.sim.snapshot(),before,"preview pure")
	var wire: Dictionary=plan.to_dict();var melee_count:=0
	for row in wire.actor_rows:
		if row.action.type=="MELEE":
			melee_count+=1;check(row.combat_assessment is Dictionary,"melee assessment")
			check(not row.combat_assessment.has("hit_roll_milli") and not row.combat_assessment.has("bleed_roll_milli") \
				and not row.combat_assessment.has("outcome"),"raw result hidden")
		else:check(row.combat_assessment==null,"non-melee null")
	check(melee_count>0,"melee present")
	var detached=plan.to_dict();detached.actor_rows[0].combat_assessment.commitment_hash="0".repeat(64)
	check(plan.to_dict()!=detached,"deep copy")
	var tampered=plan.to_dict();tampered.actor_rows[0].combat_assessment.commitment_hash="0".repeat(64)
	tampered.plan_hash=Plan.canonical_hash(tampered)
	var result=session.sim.step_party_turn(Plan.new(tampered))
	check(not result.accepted,"tamper rejected")
	check_eq(result.reason,"stale_or_tampered_combat_plan","tamper reason")
	check_eq(session.sim.snapshot(),before,"tamper exact no-op")
	var committed=session.sim.step_party_turn(plan)
	check(committed.accepted,"authoritative plan commits")
	var forged:Dictionary=session.sim.snapshot();var found_damage:=false
	for event in forged.events:
		if event.type=="combat.physical_damage":event.cause_id="-1";event.instigator_id="-1";found_damage=true;break
	check(found_damage,"party physical damage fixture")
	check_eq(WorldState.snapshot_restore_error(forged),"physical_damage_chain_invalid","party physical cause is mode-independent")
	return finish()

func test_outer_processed_step_matches_party_assessment_batch_and_production_events() -> bool:
	var session = _engaged_adjacent(); var world = session.sim.world; var state = world.party_encounter
	check_eq(world.step_index, 2, "fixture settled base step")
	var rng_before: int = world.rng.state
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(state.protagonist_id, state.enemy_ids[0]), []))
	var wire: Dictionary = plan.to_dict()
	var assessment: Dictionary = wire.actor_rows[0].combat_assessment
	check_eq([assessment.processed_step_index, assessment.attack_start_world_time,
		assessment.batch_context], ["3", str(world.world_time), "PARTY_TURN/3"],
		"outer step/time/context frozen into assessment")
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "production Party attack commits")
	check_eq(result.processed_step_index, 3, "result reports owned processed step")
	var combat_events: Array = result.events.filter(func(event):
		return event.type in ["action.melee_attack", "combat.physical_damage", "entity.died"])
	check(not combat_events.is_empty(), "production combat events emitted")
	for event in combat_events:
		check_eq(event.step_index, 3, "%s uses exact processed step" % event.type)
	check_eq(world.rng.state, rng_before, "fixed A melee path consumes no global RNG")
	return finish()

func test_party_direct_melee_runtime_commits_keyed_no_bleed_miss() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var actor_id: int = probe_state.protagonist_id
	var target_id: int = probe_state.enemy_ids[0]
	var processed_step: int = probe_world.step_index + 1
	var attack_time: int = probe_world.world_time
	var batch_context := "PARTY_TURN/%d" % processed_step
	var probe_assessment: Dictionary = Melee.new(probe_world, probe.sim.damage).assess_attack(
		actor_id, target_id, "DIRECT", processed_step, attack_time, batch_context, 0)
	check(not probe_assessment.is_empty(), "Party direct seed-search assessment built")
	if probe_assessment.is_empty(): return finish()
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var key := Melee.commitment_key(candidate_seed, processed_step, attack_time,
			batch_context, 0, actor_id, target_id)
		var hit_roll := Melee.lane_roll_milli(key, "HIT")
		var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
		if bleed_roll < int(probe_assessment.bleed_chance_milli): continue
		if hit_roll >= int(probe_assessment.hit_chance_milli):
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "deterministic no-BLEED Party MISS seed found")

	for expected_outcome in ["MISS"]:
		var session = _engaged_adjacent(selected_seed)
		var world = session.sim.world; var state = world.party_encounter
		actor_id = state.protagonist_id; target_id = state.enemy_ids[0]
		processed_step = world.step_index + 1; attack_time = world.world_time
		batch_context = "PARTY_TURN/%d" % processed_step
		var overrides: Array = []
		for member_id in state.party_member_ids:
			if member_id != actor_id and state.member(member_id).presence == "DEPLOYED":
				overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
		var request = Request.new(Action.melee(actor_id, target_id), overrides)
		var rng_before: int = world.rng.state
		var plan = session.sim.preview_party_turn(request)
		var plan_wire: Dictionary = plan.to_dict()
		check(plan_wire.accepted, "%s Party direct preview accepted" % expected_outcome)
		var assessment: Dictionary = {}
		for row in plan_wire.actor_rows:
			if int(row.actor_id) == actor_id: assessment = row.combat_assessment; break
		check(not assessment.is_empty(), "%s Party direct canonical assessment present" % expected_outcome)
		if assessment.is_empty(): continue
		check_eq([assessment.processed_step_index, assessment.attack_start_world_time,
			assessment.batch_context, assessment.intent_ordinal, assessment.source],
			[str(processed_step), str(attack_time), batch_context, 0, "DIRECT"],
			"%s Party direct assessment freezes processed batch coordinates" % expected_outcome)
		var key := Melee.commitment_key(world.seed, processed_step, attack_time,
			batch_context, 0, actor_id, target_id)
		var hit_roll := Melee.lane_roll_milli(key, "HIT")
		var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
		check_eq(assessment.commitment_hash, Melee.commitment_hash(key),
			"%s Party direct assessment freezes exact commitment" % expected_outcome)
		check(bleed_roll >= int(assessment.bleed_chance_milli),
			"%s selected commitment is deterministically no-BLEED" % expected_outcome)
		check((hit_roll >= int(assessment.hit_chance_milli)) == (expected_outcome == "MISS"),
			"%s selected commitment has keyed outcome" % expected_outcome)

		var result = session.sim.step_party_turn(plan)
		check(result.accepted, "%s Party direct preview commits" % expected_outcome)
		check_eq(result.processed_step_index, processed_step,
			"%s commit reports assessment processed step" % expected_outcome)
		var action = null
		for event in result.events:
			if event.type == "action.melee_attack" and event.actor_id == actor_id \
					and event.target_id == target_id:
				action = event; break
		check(action != null, "%s direct melee action emitted" % expected_outcome)
		if action != null:
			var final_damage: int = int(assessment.normal_final_damage) \
				if expected_outcome == "HIT" else 0
			var expected_action_data := {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"attacker_profile_id":assessment.attacker_profile_id,
				"target_profile_id":assessment.target_profile_id,
				"batch_context":batch_context, "intent_ordinal":0,
				"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE",
				"outcome":expected_outcome, "processed_step_index":str(processed_step),
				"attack_start_world_time":str(attack_time),
				"commitment_hash":Melee.commitment_hash(key),
				"hit_chance_milli":assessment.hit_chance_milli,
				"hit_roll_milli":hit_roll,
				"bleed_chance_milli":assessment.bleed_chance_milli,
				"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
				"base_damage":assessment.base_damage,
				"target_evasion_milli":assessment.target_evasion_milli,
				"armor_flat":assessment.target_armor_flat,
				"armor_reduction":assessment.armor_reduction,
				"frozen_guarded_until":assessment.frozen_guarded_until,
				"guard_source_event_id":assessment.guard_source_event_id,
				"guarded":assessment.guarded,
				"guard_reduction":assessment.guard_reduction,
				"final_damage":final_damage}
			check_eq([action.step_index, action.world_time, action.position,
				action.magnitude, action.cause_id, action.instigator_id],
				[processed_step, attack_time, world.entities[target_id].position,
				int(assessment.base_damage), -1, actor_id],
				"%s direct action exact canonical envelope" % expected_outcome)
			check_eq(action.data, expected_action_data,
				"%s direct action exact canonical v1 data" % expected_outcome)
			var children: Array = result.events.filter(func(event):
				return event.cause_id == action.id and event.type in [
					"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
			check_eq(children.size(), 1,
				"%s direct action has one exact combat result child" % expected_outcome)
			if children.size() == 1:
				var child = children[0]
				var expected_type := "combat.attack_missed" \
					if expected_outcome == "MISS" else "combat.physical_damage"
				var expected_child_data := {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1", "outcome":"MISS"} \
					if expected_outcome == "MISS" else {"schema_version":1,
						"combat_ruleset_id":"deterministic-melee-resolution-v1",
						"damage_type":"physical", "requested_damage":final_damage,
						"applied_health_damage":final_damage}
				check_eq([child.type, child.step_index, child.world_time, child.actor_id,
					child.target_id, child.position, child.magnitude, child.cause_id,
					child.instigator_id], [expected_type, processed_step, attack_time, -1,
					target_id, action.position, final_damage, action.id, actor_id],
					"%s direct result exact canonical envelope" % expected_outcome)
				check_eq(child.data, expected_child_data,
					"%s direct result exact canonical v1 data" % expected_outcome)
		check_eq(world.rng.state, rng_before,
			"%s keyed Party commit consumes no global RNG" % expected_outcome)
		var canonical = session.sim.snapshot()
		check(canonical is Dictionary,
			"%s committed Party snapshot constructs" % expected_outcome)
		if canonical is Dictionary:
			check_eq(WorldState.snapshot_restore_error(canonical), "",
				"%s committed Party snapshot restores" % expected_outcome)
			var restored = Simulator.from_snapshot(canonical)
			check(restored != null, "%s committed Party snapshot loads" % expected_outcome)
			if restored != null:
				check_eq(restored.snapshot(), canonical,
					"%s committed Party snapshot roundtrip exact" % expected_outcome)
	return finish()

func test_party_direct_melee_runtime_commits_keyed_no_bleed_hit() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var actor_id: int = probe_state.protagonist_id
	var target_id: int = probe_state.enemy_ids[0]
	var processed_step: int = probe_world.step_index + 1
	var attack_time: int = probe_world.world_time
	var batch_context := "PARTY_TURN/%d" % processed_step
	var probe_assessment: Dictionary = Melee.new(probe_world, probe.sim.damage).assess_attack(
		actor_id, target_id, "DIRECT", processed_step, attack_time, batch_context, 0)
	check(not probe_assessment.is_empty(), "Party direct HIT seed-search assessment built")
	if probe_assessment.is_empty(): return finish()
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var key := Melee.commitment_key(candidate_seed, processed_step, attack_time,
			batch_context, 0, actor_id, target_id)
		if Melee.lane_roll_milli(key, "HIT") < int(probe_assessment.hit_chance_milli) \
				and Melee.lane_roll_milli(key, "BLEED") >= int(probe_assessment.bleed_chance_milli):
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "deterministic no-BLEED Party HIT seed found")
	if selected_seed < 0: return finish()

	var session = _engaged_adjacent(selected_seed)
	var world = session.sim.world; var state = world.party_encounter
	actor_id = state.protagonist_id; target_id = state.enemy_ids[0]
	processed_step = world.step_index + 1; attack_time = world.world_time
	batch_context = "PARTY_TURN/%d" % processed_step
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != actor_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(actor_id, target_id), overrides))
	var plan_wire: Dictionary = plan.to_dict()
	check(plan_wire.accepted, "HIT Party direct preview accepted")
	var assessment: Dictionary = {}
	for row in plan_wire.actor_rows:
		if int(row.actor_id) == actor_id: assessment = row.combat_assessment; break
	check(not assessment.is_empty(), "HIT Party direct canonical assessment present")
	if assessment.is_empty(): return finish()
	check_eq([assessment.processed_step_index, assessment.attack_start_world_time,
		assessment.batch_context, assessment.intent_ordinal, assessment.source],
		[str(processed_step), str(attack_time), batch_context, 0, "DIRECT"],
		"HIT Party direct assessment freezes processed batch coordinates")
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		batch_context, 0, actor_id, target_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	check_eq(assessment.commitment_hash, Melee.commitment_hash(key),
		"HIT Party direct assessment freezes exact commitment")
	check(hit_roll < int(assessment.hit_chance_milli),
		"selected Party commitment is keyed HIT")
	check(bleed_roll >= int(assessment.bleed_chance_milli),
		"selected Party HIT commitment is deterministically no-BLEED")
	check_eq([assessment.base_damage, assessment.target_armor_flat,
		assessment.armor_reduction, assessment.guarded, assessment.guard_reduction,
		assessment.normal_final_damage], [24, 2, 2, false, 0, 22],
		"Party HIT freezes exact unguarded 24 minus armor 2 formula")
	var rng_before: int = world.rng.state
	var hp_before: int = world.entities[target_id].health
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "HIT Party direct preview commits")
	check_eq(result.processed_step_index, processed_step,
		"HIT commit reports assessment processed step")
	var action = null; var action_index := -1
	for index in range(result.events.size()):
		var event = result.events[index]
		if event.type == "action.melee_attack" and event.actor_id == actor_id \
				and event.target_id == target_id:
			action = event; action_index = index; break
	check(action != null, "HIT direct melee action emitted")
	if action != null:
		var expected_action_data := {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":assessment.attacker_profile_id,
			"target_profile_id":assessment.target_profile_id,
			"batch_context":batch_context, "intent_ordinal":0,
			"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE",
			"outcome":"HIT", "processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":assessment.hit_chance_milli,
			"hit_roll_milli":hit_roll,
			"bleed_chance_milli":assessment.bleed_chance_milli,
			"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
			"base_damage":24, "target_evasion_milli":assessment.target_evasion_milli,
			"armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":assessment.frozen_guarded_until,
			"guard_source_event_id":assessment.guard_source_event_id,
			"guarded":false, "guard_reduction":0, "final_damage":22}
		check_eq([action.step_index, action.world_time, action.actor_id, action.target_id,
			action.position, action.magnitude, action.cause_id, action.instigator_id],
			[processed_step, attack_time, actor_id, target_id,
				world.entities[target_id].position, 24, -1, actor_id],
			"HIT direct action exact canonical envelope")
		check_eq(action.data, expected_action_data,
			"HIT direct action exact canonical v1 data")
		var children: Array = result.events.filter(func(event):
			return event.cause_id == action.id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		check_eq(children.size(), 1, "HIT direct action has one exact combat result child")
		if children.size() == 1:
			var child = children[0]; var child_index: int = result.events.find(child)
			check_eq([child.type, child.step_index, child.world_time, child.actor_id,
				child.target_id, child.position, child.magnitude, child.cause_id,
				child.instigator_id], ["combat.physical_damage", processed_step,
				attack_time, -1, target_id, action.position, 22, action.id, actor_id],
				"HIT direct physical child exact canonical envelope")
			check_eq(child.data, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":22,
				"applied_health_damage":22},
				"HIT direct physical child exact canonical v1 data")
			var last_melee_action_index := action_index
			for index in range(result.events.size()):
				if result.events[index].type == "action.melee_attack" \
						and result.events[index].actor_id in state.party_member_ids:
					last_melee_action_index = maxi(last_melee_action_index, index)
			check(last_melee_action_index < child_index,
				"all same-batch melee actions precede the first canonical result")
	check_eq(world.entities[target_id].health, hp_before - 22,
		"HIT production path applies exact final health damage 22")
	check_eq(world.rng.state, rng_before,
		"HIT keyed Party commit consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "HIT committed Party snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"HIT committed Party snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "HIT committed Party snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"Hit committed Party snapshot roundtrip exact")
	return finish()

func test_party_direct_melee_runtime_commits_keyed_bleed_hit_and_status() -> bool:
	var session = _engaged_adjacent(2, 100)
	var world = session.sim.world; var state = world.party_encounter
	var actor_id: int = state.protagonist_id
	var target_id: int = state.enemy_ids[0]
	var processed_step: int = world.step_index + 1
	var attack_time: int = world.world_time
	var batch_context := "PARTY_TURN/%d" % processed_step
	check_eq([actor_id, target_id, processed_step, attack_time], [1, 4, 3, 200],
		"known Party BLEED commitment coordinates exact")
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != actor_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(actor_id, target_id), overrides))
	var plan_wire: Dictionary = plan.to_dict(); var assessment: Dictionary = {}
	check(plan_wire.accepted, "BLEED HIT Party direct preview accepted")
	for row in plan_wire.actor_rows:
		if int(row.actor_id) == actor_id: assessment = row.combat_assessment; break
	check(not assessment.is_empty(), "BLEED HIT Party direct assessment present")
	if assessment.is_empty(): return finish()
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		batch_context, 0, actor_id, target_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	check_eq([assessment.source, assessment.processed_step_index,
		assessment.attack_start_world_time, assessment.batch_context,
		assessment.intent_ordinal, assessment.commitment_hash,
		assessment.hit_chance_milli, assessment.bleed_chance_milli,
		assessment.base_damage, assessment.normal_final_damage],
		["DIRECT", "3", "200", "PARTY_TURN/3", 0,
			Melee.commitment_hash(key), 950, 600, 24, 22],
		"BLEED HIT assessment freezes exact canonical coordinates and formula")
	check_eq([hit_roll, bleed_roll], [599, 16],
		"known Party commitment has exact keyed HIT and BLEED rolls")
	check(hit_roll < int(assessment.hit_chance_milli) \
			and bleed_roll < int(assessment.bleed_chance_milli),
		"known Party commitment deterministically succeeds HIT and BLEED")
	var rng_before: int = world.rng.state
	var hp_before: int = world.entities[target_id].health
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "BLEED HIT Party direct preview commits")
	var action = null; var physical = null; var applied = null
	for event in result.events:
		if event.type == "action.melee_attack" and event.actor_id == actor_id \
				and event.target_id == target_id:
			action = event
		elif event.type == "combat.physical_damage" and action != null \
				and event.target_id == target_id and event.cause_id == action.id:
			physical = event
		elif event.type == "status.applied" and event.target_id == target_id:
			applied = event
	check(action != null, "BLEED HIT emits direct melee action")
	if action != null:
		check_eq([action.step_index, action.world_time, action.position,
			action.magnitude, action.cause_id, action.instigator_id],
			[processed_step, attack_time, world.entities[target_id].position,
				24, -1, actor_id], "BLEED HIT action exact envelope")
		check_eq(action.data, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":assessment.attacker_profile_id,
			"target_profile_id":assessment.target_profile_id,
			"batch_context":batch_context, "intent_ordinal":0,
			"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE",
			"outcome":"HIT", "processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":950, "hit_roll_milli":hit_roll,
			"bleed_chance_milli":600, "bleed_roll_milli":bleed_roll,
			"bleed_proc_succeeded":true, "base_damage":24,
			"target_evasion_milli":100, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":assessment.frozen_guarded_until,
			"guard_source_event_id":assessment.guard_source_event_id,
			"guarded":false, "guard_reduction":0, "final_damage":22},
			"BLEED HIT action exact canonical v1 data")
	check(physical != null, "BLEED HIT emits canonical physical child")
	if action != null and physical != null:
		check_eq([physical.step_index, physical.world_time, physical.actor_id,
			physical.target_id, physical.position, physical.magnitude,
			physical.cause_id, physical.instigator_id, physical.data],
			[processed_step, attack_time, -1, target_id, action.position, 22,
				action.id, actor_id, {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}],
			"BLEED HIT physical child exact canonical v1")
		var last_leaf_index := -1
		for index in range(result.events.size()):
			var event = result.events[index]
			if event.world_time == attack_time and event.actor_id in state.party_member_ids \
					and event.type.begins_with("action."):
				last_leaf_index = maxi(last_leaf_index, index)
		check(last_leaf_index < result.events.find(physical),
			"all Party action leaves precede BLEED result chain")
	check(applied != null, "successful BLEED proc emits status.applied")
	if physical != null and applied != null:
		check_eq([applied.step_index, applied.world_time, applied.actor_id,
			applied.target_id, applied.position, applied.magnitude,
			applied.cause_id, applied.instigator_id, applied.data],
			[processed_step, attack_time, -1, target_id, physical.position, 0,
				physical.id, actor_id, {"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "next_tick_at":"300",
					"expires_at":"500", "tick_damage":3}],
			"BLEED HIT status apply exact canonical v1")
		check(result.events.find(physical) + 1 == result.events.find(applied),
			"BLEED apply is immediate child of typed damage")
	var target_state = world.combatant_states[target_id]
	var cadence_ticks: Array = result.events.filter(func(event):
		return event.type == "status.tick" and event.target_id == target_id \
			and event.world_time == 300)
	var cadence_damage: Array = result.events.filter(func(event):
		return cadence_ticks.size() == 1 and event.type == "combat.physical_damage" \
			and event.target_id == target_id and event.cause_id == cadence_ticks[0].id)
	check_eq([cadence_ticks.size(), cadence_damage.size()], [1, 1],
		"BLEED HIT outer operation processes exact T300 tick and physical child")
	check_eq(world.entities[target_id].health, hp_before - 25,
		"BLEED HIT plus due T300 tick applies exact health damage")
	check_eq(target_state.status_rows.size(), 1,
		"BLEED HIT creates exactly one authoritative status row")
	if target_state.status_rows.size() == 1 and applied != null:
		check_eq(target_state.status_rows[0].to_dict(), {"schema_version":1,
			"status_id":"BLEEDING", "applied_at":"200", "refreshed_at":"200",
			"next_tick_at":"400", "expires_at":"500",
			"source_event_id":str(applied.id)},
			"BLEED HIT authoritative row exact after T300 cadence")
	check_eq(world.rng.state, rng_before,
		"BLEED HIT keyed Party commit consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "BLEED HIT committed Party snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"BLEED HIT committed Party snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "BLEED HIT committed Party snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"BLEED HIT committed Party snapshot roundtrip exact")
	return finish()

func test_party_direct_second_keyed_bleed_hit_refreshes_single_status_row() -> bool:
	var probe = _engaged_adjacent(1, 100)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var actor_id: int = probe_state.protagonist_id
	var target_id: int = probe_state.enemy_ids[0]
	var first_step: int = probe_world.step_index + 1
	var first_time: int = probe_world.world_time
	var second_step := first_step + 1; var second_time := first_time + 100
	var first_context := "PARTY_TURN/%d" % first_step
	var second_context := "PARTY_TURN/%d" % second_step
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var first_key := Melee.commitment_key(candidate_seed, first_step,
			first_time, first_context, 0, actor_id, target_id)
		var second_key := Melee.commitment_key(candidate_seed, second_step,
			second_time, second_context, 0, actor_id, target_id)
		if Melee.lane_roll_milli(first_key, "HIT") < 950 \
				and Melee.lane_roll_milli(first_key, "BLEED") < 600 \
				and Melee.lane_roll_milli(second_key, "HIT") < 950 \
				and Melee.lane_roll_milli(second_key, "BLEED") < 600:
			selected_seed = candidate_seed
			break
	check(selected_seed > 0,
		"reachable consecutive Party HIT+BLEED commitment seed found")
	if selected_seed < 0: return finish()

	var session = _engaged_adjacent(selected_seed, 100)
	var world = session.sim.world; var state = world.party_encounter
	actor_id = state.protagonist_id; target_id = state.enemy_ids[0]
	first_step = world.step_index + 1; first_time = world.world_time
	first_context = "PARTY_TURN/%d" % first_step
	var first_overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != actor_id and state.member(member_id).presence == "DEPLOYED":
			first_overrides.append({"actor_id":member_id,
				"action":Action.hold(member_id)})
	var first_plan = session.sim.preview_party_turn(Request.new(
		Action.melee(actor_id, target_id), first_overrides))
	var first_wire: Dictionary = first_plan.to_dict(); var first_assessment: Dictionary = {}
	check(first_wire.accepted, "first BLEED refresh-sequence preview accepted")
	for row in first_wire.actor_rows:
		if int(row.actor_id) == actor_id: first_assessment = row.combat_assessment; break
	check(not first_assessment.is_empty(),
		"first BLEED refresh-sequence assessment present")
	if first_assessment.is_empty(): return finish()
	var first_key := Melee.commitment_key(world.seed, first_step, first_time,
		first_context, 0, actor_id, target_id)
	var first_hit_roll := Melee.lane_roll_milli(first_key, "HIT")
	var first_bleed_roll := Melee.lane_roll_milli(first_key, "BLEED")
	check(first_hit_roll < 950 and first_bleed_roll < 600,
		"first refresh-sequence key succeeds HIT and BLEED")
	var hp_before: int = world.entities[target_id].health
	var rng_before: int = world.rng.state
	var first_result = session.sim.step_party_turn(first_plan)
	check(first_result.accepted, "first BLEED refresh-sequence turn commits")
	var first_action = null; var first_physical = null; var applied = null
	for event in first_result.events:
		if event.type == "action.melee_attack" and event.actor_id == actor_id \
				and event.target_id == target_id:
			first_action = event
		elif event.type == "combat.physical_damage" and first_action != null \
				and event.cause_id == first_action.id:
			first_physical = event
		elif event.type == "status.applied" and event.target_id == target_id:
			applied = event
	check(first_action != null and first_physical != null,
		"first BLEED refresh-sequence action and physical emit")
	if first_action != null:
		check_eq([first_action.step_index, first_action.world_time,
			first_action.position, first_action.magnitude, first_action.cause_id,
			first_action.instigator_id], [first_step, first_time,
				world.entities[target_id].position, 24, -1, actor_id],
			"first BLEED refresh-sequence action exact envelope")
		check_eq(first_action.data, _expected_bleed_hit_action_data(
			first_assessment, first_key, first_hit_roll, first_bleed_roll),
			"first BLEED refresh-sequence action exact canonical v1 data")
	if first_action != null and first_physical != null:
		check_eq([first_physical.step_index, first_physical.world_time,
			first_physical.actor_id, first_physical.target_id, first_physical.position,
			first_physical.magnitude, first_physical.cause_id,
			first_physical.instigator_id, first_physical.data],
			[first_step, first_time, -1, target_id, first_action.position, 22,
				first_action.id, actor_id, {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}],
			"first BLEED refresh-sequence physical exact canonical v1")
	check(applied != null, "first successful proc emits status.applied")
	var first_next_tick := ((first_time / 100) + 1) * 100
	var first_expires := first_next_tick + 200
	if first_physical != null and applied != null:
		check_eq([applied.step_index, applied.world_time, applied.actor_id,
			applied.target_id, applied.position, applied.magnitude, applied.cause_id,
			applied.instigator_id, applied.data], [first_step, first_time, -1,
				target_id, first_physical.position, 0, first_physical.id, actor_id,
				{"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "next_tick_at":str(first_next_tick),
					"expires_at":str(first_expires), "tick_damage":3}],
			"first BLEED status.applied exact canonical v1")
		check_eq(first_result.events.find(applied),
			first_result.events.find(first_physical) + 1,
			"first BLEED apply immediately follows typed damage")
	check_eq(world.combatant_states[target_id].status_rows.size(), 1,
		"first proc creates one BLEEDING row")
	if world.combatant_states[target_id].status_rows.size() == 1 and applied != null:
		check_eq(world.combatant_states[target_id].status_rows[0].to_dict(),
			{"schema_version":1, "status_id":"BLEEDING",
				"applied_at":str(first_time), "refreshed_at":str(first_time),
				"next_tick_at":str(first_next_tick + 100), "expires_at":str(first_expires),
				"source_event_id":str(applied.id)},
			"first BLEEDING row exact after T300 tick and before refresh")

	second_step = world.step_index + 1; second_time = world.world_time
	second_context = "PARTY_TURN/%d" % second_step
	check_eq([second_step, second_time], [first_step + 1, first_time + 100],
		"second fresh Party turn has expected step/time")
	var second_overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != actor_id and state.member(member_id).presence == "DEPLOYED":
			second_overrides.append({"actor_id":member_id,
				"action":Action.hold(member_id)})
	var second_plan = session.sim.preview_party_turn(Request.new(
		Action.melee(actor_id, target_id), second_overrides))
	var second_wire: Dictionary = second_plan.to_dict(); var second_assessment: Dictionary = {}
	check(second_wire.accepted, "second BLEED refresh preview accepted")
	for row in second_wire.actor_rows:
		if int(row.actor_id) == actor_id: second_assessment = row.combat_assessment; break
	check(not second_assessment.is_empty(), "second BLEED refresh assessment present")
	if second_assessment.is_empty(): return finish()
	var second_key := Melee.commitment_key(world.seed, second_step, second_time,
		second_context, 0, actor_id, target_id)
	var second_hit_roll := Melee.lane_roll_milli(second_key, "HIT")
	var second_bleed_roll := Melee.lane_roll_milli(second_key, "BLEED")
	check(second_hit_roll < 950 and second_bleed_roll < 600,
		"second refresh-sequence key succeeds HIT and BLEED")
	var second_result = session.sim.step_party_turn(second_plan)
	check(second_result.accepted, "second BLEED refresh turn commits")
	var second_action = null; var second_physical = null; var refreshed = null
	for event in second_result.events:
		if event.type == "action.melee_attack" and event.actor_id == actor_id \
				and event.target_id == target_id:
			second_action = event
		elif event.type == "combat.physical_damage" and second_action != null \
				and event.cause_id == second_action.id:
			second_physical = event
		elif event.type == "status.refreshed" and event.target_id == target_id:
			refreshed = event
	check(second_action != null and second_physical != null,
		"second BLEED refresh action and physical emit")
	if second_action != null:
		check_eq([second_action.step_index, second_action.world_time,
			second_action.position, second_action.magnitude, second_action.cause_id,
			second_action.instigator_id], [second_step, second_time,
				world.entities[target_id].position, 24, -1, actor_id],
			"second BLEED refresh action exact envelope")
		check_eq(second_action.data, _expected_bleed_hit_action_data(
			second_assessment, second_key, second_hit_roll, second_bleed_roll),
			"second BLEED refresh action exact canonical v1 data")
	if second_action != null and second_physical != null:
		check_eq([second_physical.step_index, second_physical.world_time,
			second_physical.actor_id, second_physical.target_id,
			second_physical.position, second_physical.magnitude,
			second_physical.cause_id, second_physical.instigator_id,
			second_physical.data], [second_step, second_time, -1, target_id,
				second_action.position, 22, second_action.id, actor_id,
				{"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}],
			"second BLEED refresh physical exact canonical v1")
		var last_leaf_index := -1
		for index in range(second_result.events.size()):
			var event = second_result.events[index]
			if event.world_time == second_time and event.actor_id in state.party_member_ids \
					and event.type.begins_with("action."):
				last_leaf_index = maxi(last_leaf_index, index)
		check(last_leaf_index < second_result.events.find(second_physical),
			"all second-turn Party leaves precede refresh result chain")
	check(refreshed != null, "second successful proc emits status.refreshed")
	var refreshed_expires := maxi(first_expires,
		((second_time / 100) + 1) * 100 + 200)
	if second_physical != null and refreshed != null:
		check_eq([refreshed.step_index, refreshed.world_time, refreshed.actor_id,
			refreshed.target_id, refreshed.position, refreshed.magnitude,
			refreshed.cause_id, refreshed.instigator_id, refreshed.data],
			[second_step, second_time, -1, target_id, second_physical.position, 0,
				second_physical.id, actor_id, {"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "next_tick_at":str(first_next_tick + 100),
					"expires_at":str(refreshed_expires), "tick_damage":3}],
			"second BLEED status.refreshed exact canonical v1")
		check_eq(second_result.events.find(refreshed),
			second_result.events.find(second_physical) + 1,
			"BLEED refresh immediately follows latest typed damage")
	var final_rows: Array = world.combatant_states[target_id].status_rows
	check_eq(final_rows.size(), 1, "refresh keeps exactly one BLEEDING row")
	if final_rows.size() == 1 and refreshed != null:
		check_eq(final_rows[0].to_dict(), {"schema_version":1,
			"status_id":"BLEEDING", "applied_at":str(first_time),
			"refreshed_at":str(second_time), "next_tick_at":str(first_next_tick + 200),
			"expires_at":str(refreshed_expires),
			"source_event_id":str(refreshed.id)},
			"refresh preserves apply and advances through due T400 tick exactly")
	check_eq(world.entities[target_id].health, hp_before - 50,
		"two BLEED HITs plus T300/T400 ticks apply exact total health damage")
	check_eq(world.rng.state, rng_before,
		"two keyed BLEED turns consume no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "refreshed BLEED Party snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"refreshed BLEED Party snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "refreshed BLEED Party snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"refreshed BLEED Party snapshot roundtrip exact")
	return finish()

func test_party_direct_melee_runtime_commits_keyed_guarded_no_bleed_hit() -> bool:
	var probe: Dictionary = _guarded_engaged_adjacent(1)
	check(not probe.is_empty(), "production enemy HOLD guard seed-search fixture built")
	if probe.is_empty(): return finish()
	var probe_session = probe.session; var probe_world = probe_session.sim.world
	var probe_state = probe_world.party_encounter
	var actor_id: int = probe_state.protagonist_id
	var target_id: int = probe_state.enemy_ids[0]
	var processed_step: int = probe_world.step_index + 1
	var attack_time: int = probe_world.world_time
	var batch_context := "PARTY_TURN/%d" % processed_step
	var probe_assessment: Dictionary = Melee.new(
		probe_world, probe_session.sim.damage).assess_attack(actor_id, target_id,
		"DIRECT", processed_step, attack_time, batch_context, 0)
	check(not probe_assessment.is_empty(), "guarded Party HIT seed-search assessment built")
	if probe_assessment.is_empty(): return finish()
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, batch_context, 0, actor_id, target_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") \
				< int(probe_assessment.hit_chance_milli) \
				and Melee.lane_roll_milli(candidate_key, "BLEED") \
				>= int(probe_assessment.bleed_chance_milli):
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "deterministic guarded no-BLEED Party HIT seed found")
	if selected_seed < 0: return finish()

	var fixture: Dictionary = _guarded_engaged_adjacent(selected_seed)
	check(not fixture.is_empty(), "production enemy HOLD guarded Party fixture built")
	if fixture.is_empty(): return finish()
	var session = fixture.session; var world = session.sim.world
	var state = world.party_encounter
	actor_id = state.protagonist_id; target_id = state.enemy_ids[0]
	processed_step = world.step_index + 1; attack_time = world.world_time
	batch_context = "PARTY_TURN/%d" % processed_step
	var target_state = world.combatant_states[target_id]
	check_eq([target_state.guarded_until, target_state.guard_source_event_id],
		[int(fixture.guarded_until), int(fixture.hold_id)],
		"target guard retains exact production HOLD expiry/source")
	check(attack_time < target_state.guarded_until,
		"production HOLD guard is active at Party batch start")
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != actor_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(actor_id, target_id), overrides))
	var plan_wire: Dictionary = plan.to_dict(); var assessment: Dictionary = {}
	check(plan_wire.accepted, "guarded HIT Party direct preview accepted")
	for row in plan_wire.actor_rows:
		if int(row.actor_id) == actor_id: assessment = row.combat_assessment; break
	check(not assessment.is_empty(), "guarded HIT Party direct assessment present")
	if assessment.is_empty(): return finish()
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		batch_context, 0, actor_id, target_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	check_eq([assessment.processed_step_index, assessment.attack_start_world_time,
		assessment.batch_context, assessment.intent_ordinal, assessment.source],
		[str(processed_step), str(attack_time), batch_context, 0, "DIRECT"],
		"guarded HIT assessment freezes processed batch coordinates")
	check_eq([assessment.base_damage, assessment.target_armor_flat,
		assessment.armor_reduction, assessment.guarded, assessment.guard_reduction,
		assessment.normal_final_damage, assessment.frozen_guarded_until,
		assessment.guard_source_event_id],
		[24, 2, 2, true, 5, 17, str(fixture.guarded_until), str(fixture.hold_id)],
		"guarded HIT freezes exact 24 minus armor 2 minus guard 5 formula/source")
	check_eq(assessment.commitment_hash, Melee.commitment_hash(key),
		"guarded HIT assessment freezes exact commitment")
	check(hit_roll < int(assessment.hit_chance_milli),
		"guarded selected commitment is keyed HIT")
	check(bleed_roll >= int(assessment.bleed_chance_milli),
		"guarded selected commitment is deterministically no-BLEED")
	var rng_before: int = world.rng.state
	var hp_before: int = world.entities[target_id].health
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "guarded HIT Party direct preview commits")
	check_eq(result.processed_step_index, processed_step,
		"guarded HIT commit reports assessment processed step")
	var action = null
	for event in result.events:
		if event.type == "action.melee_attack" and event.actor_id == actor_id \
				and event.target_id == target_id:
			action = event; break
	check(action != null, "guarded HIT direct melee action emitted")
	if action != null:
		var expected_action_data := {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":assessment.attacker_profile_id,
			"target_profile_id":assessment.target_profile_id,
			"batch_context":batch_context, "intent_ordinal":0,
			"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE",
			"outcome":"HIT", "processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":assessment.hit_chance_milli,
			"hit_roll_milli":hit_roll,
			"bleed_chance_milli":assessment.bleed_chance_milli,
			"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
			"base_damage":24, "target_evasion_milli":assessment.target_evasion_milli,
			"armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":str(fixture.guarded_until),
			"guard_source_event_id":str(fixture.hold_id),
			"guarded":true, "guard_reduction":5, "final_damage":17}
		check_eq([action.step_index, action.world_time, action.actor_id, action.target_id,
			action.position, action.magnitude, action.cause_id, action.instigator_id],
			[processed_step, attack_time, actor_id, target_id,
				world.entities[target_id].position, 24, -1, actor_id],
			"guarded HIT direct action exact canonical envelope")
		check_eq(action.data, expected_action_data,
			"guarded HIT direct action exact canonical v1 data")
		var children: Array = result.events.filter(func(event):
			return event.cause_id == action.id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		check_eq(children.size(), 1,
			"guarded HIT direct action has one exact combat result child")
		if children.size() == 1:
			var child = children[0]
			check_eq([child.type, child.step_index, child.world_time, child.actor_id,
				child.target_id, child.position, child.magnitude, child.cause_id,
				child.instigator_id], ["combat.physical_damage", processed_step,
				attack_time, -1, target_id, action.position, 17, action.id, actor_id],
				"guarded HIT physical child exact canonical envelope")
			check_eq(child.data, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":17,
				"applied_health_damage":17},
				"guarded HIT physical child exact canonical v1 data")
	check_eq(world.entities[target_id].health, hp_before - 17,
		"guarded HIT applies exact final health damage 17")
	check_eq([target_state.guarded_until, target_state.guard_source_event_id],
		[int(fixture.guarded_until), int(fixture.hold_id)],
		"guarded HIT preserves exact historical HOLD authority")
	check_eq(world.rng.state, rng_before,
		"guarded keyed Party commit consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "guarded HIT committed Party snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"guarded HIT committed Party snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "guarded HIT committed Party snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"guarded HIT committed Party snapshot roundtrip exact")
	return finish()

func test_party_two_melee_batch_downs_once_then_emits_overkill_skip() -> bool:
	var probe: Dictionary = _two_melee_plan_fixture(1)
	check(not probe.is_empty(), "two-Party-melee seed-search fixture built")
	if probe.is_empty(): return finish()
	var probe_session = probe.session; var probe_world = probe_session.sim.world
	var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var companion_id: int = probe.companion_id
	var target_id: int = probe_state.enemy_ids[0]
	var processed_step: int = probe_world.step_index + 1
	var attack_time: int = probe_world.world_time
	var context := "PARTY_TURN/%d" % processed_step
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var hero_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 0, hero_id, target_id)
		var companion_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 1, companion_id, target_id)
		if Melee.lane_roll_milli(hero_key, "HIT") < 950 \
				and Melee.lane_roll_milli(hero_key, "BLEED") >= 600 \
				and Melee.lane_roll_milli(companion_key, "BLEED") >= 500:
			selected_seed = candidate_seed; break
	check(selected_seed > 0, "deterministic two-Party-melee no-BLEED seed found")
	if selected_seed < 0: return finish()
	var fixture: Dictionary = _two_melee_plan_fixture(selected_seed)
	check(not fixture.is_empty(), "two-Party-melee runtime fixture built")
	if fixture.is_empty(): return finish()
	var session = fixture.session; var world = session.sim.world
	var state = world.party_encounter
	hero_id = state.protagonist_id; companion_id = fixture.companion_id
	target_id = state.enemy_ids[0]; processed_step = world.step_index + 1
	attack_time = world.world_time; context = "PARTY_TURN/%d" % processed_step
	world.entities[target_id].health = 22
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id == hero_id or state.member(member_id).presence != "DEPLOYED": continue
		overrides.append({"actor_id":member_id,
			"action":Action.melee(member_id, target_id) \
				if member_id == companion_id else Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(hero_id, target_id), overrides))
	var wire: Dictionary = plan.to_dict(); var assessments: Dictionary = {}
	check(wire.accepted, "two-Party-melee lethal preview accepted")
	for row in wire.actor_rows:
		if row.combat_assessment is Dictionary:
			assessments[int(row.actor_id)] = row.combat_assessment
	check_eq(assessments.size(), 2, "both explicit Party MELEE rows freeze assessments")
	if assessments.size() != 2: return finish()
	check_eq([assessments[hero_id].intent_ordinal,
		assessments[companion_id].intent_ordinal], [0, 1],
		"same-target Party ordinals follow attacker ID order")
	var rng_before: int = world.rng.state
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "two-Party-melee lethal batch commits")
	var actions: Dictionary = {}
	for event in result.events:
		if event.type == "action.melee_attack" and event.target_id == target_id \
				and event.actor_id in [hero_id, companion_id]:
			actions[event.actor_id] = event
	check_eq(actions.size(), 2, "both Party frozen melee actions emit")
	if actions.size() == 2:
		for actor_id in [hero_id, companion_id]:
			var action = actions[actor_id]; var assessment: Dictionary = assessments[actor_id]
			var ordinal := 0 if actor_id == hero_id else 1
			var outcome := "HIT" if actor_id == hero_id else "OVERKILL_SKIP"
			var final_damage := 22 if actor_id == hero_id else 0
			var key := Melee.commitment_key(world.seed, processed_step, attack_time,
				context, ordinal, actor_id, target_id)
			var hit_roll := Melee.lane_roll_milli(key, "HIT")
			var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
			check_eq([action.step_index, action.world_time, action.position,
				action.magnitude, action.instigator_id], [processed_step, attack_time,
				world.entities[target_id].position, 24, actor_id],
				"Party batch actor %d exact canonical action envelope" % actor_id)
			check_eq(action.data, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"attacker_profile_id":assessment.attacker_profile_id,
				"target_profile_id":assessment.target_profile_id,
				"batch_context":context, "intent_ordinal":ordinal,
				"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE",
				"outcome":outcome, "processed_step_index":str(processed_step),
				"attack_start_world_time":str(attack_time),
				"commitment_hash":Melee.commitment_hash(key),
				"hit_chance_milli":assessment.hit_chance_milli,
				"hit_roll_milli":hit_roll,
				"bleed_chance_milli":assessment.bleed_chance_milli,
				"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
				"base_damage":24, "target_evasion_milli":assessment.target_evasion_milli,
				"armor_flat":2, "armor_reduction":2,
				"frozen_guarded_until":assessment.frozen_guarded_until,
				"guard_source_event_id":assessment.guard_source_event_id,
				"guarded":assessment.guarded,
				"guard_reduction":assessment.guard_reduction,
				"final_damage":final_damage},
				"Party batch actor %d exact %s data" % [actor_id, outcome])
		var combat_results: Array = result.events.filter(func(event):
			return event.type in ["combat.attack_missed", "combat.physical_damage",
				"combat.downed_damage"] and event.target_id == target_id)
		if not combat_results.is_empty():
			check(maxi(result.events.find(actions[hero_id]),
				result.events.find(actions[companion_id])) < result.events.find(combat_results[0]),
				"all Party melee actions precede first combat result")
		var hero_children: Array = result.events.filter(func(event):
			return event.cause_id == actions[hero_id].id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		var companion_children: Array = result.events.filter(func(event):
			return event.cause_id == actions[companion_id].id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		check_eq(hero_children.size(), 1, "ordinal-zero HIT has one physical driver")
		check_eq(companion_children.size(), 0, "ordinal-one OVERKILL_SKIP has zero result children")
		if hero_children.size() == 1:
			var damage = hero_children[0]
			check_eq([damage.type, damage.magnitude, damage.data],
				["combat.physical_damage", 22, {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}],
				"ordinal-zero Party physical driver exact")
			var downed: Array = result.events.filter(func(event):
				return event.type == "entity.downed" and event.target_id == target_id \
					and event.cause_id == damage.id)
			check_eq(downed.size(), 1, "ordinal-zero Party HIT downs target exactly once")
			if downed.size() == 1:
				check_eq(downed[0].data, {"schema_version":1,
					"life_ruleset_id":"active-downed-dead-v1",
					"previous_life_state":"ACTIVE", "downed_resolve_at":"300",
					"terminal_immediate":false}, "Party enemy DOWNED data exact")
	check_eq([world.entities[target_id].health,
		world.combatant_states[target_id].life_state], [0, "DOWNED"],
		"Party lethal batch leaves enemy unresolved DOWNED")
	check(result.events.filter(func(event):
		return event.type in ["party.victory", "party.regroup_started",
			"party.regroup_completed"]).is_empty(),
		"DOWNED final enemy does not trigger victory or regroup")
	check_eq(world.rng.state, rng_before,
		"two-Party-melee keyed batch consumes no global RNG")
	return finish()

func test_party_same_target_bleed_lethal_then_childless_overkill_is_canonical() -> bool:
	var fixture: Dictionary = _two_melee_plan_fixture(2, 100)
	check(not fixture.is_empty(), "seed-two same-target BLEED fixture built")
	if fixture.is_empty(): return finish()
	var session = fixture.session; var world = session.sim.world
	var state = world.party_encounter
	var hero_id: int = state.protagonist_id
	var companion_id: int = fixture.companion_id
	var target_id: int = state.enemy_ids[0]
	var processed_step: int = world.step_index + 1
	var attack_time: int = world.world_time
	var context := "PARTY_TURN/%d" % processed_step
	check_eq([processed_step, attack_time, world.seed], [3, 200, 2],
		"seed-two same-target commitment coordinates exact")
	world.entities[target_id].health = 22
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id == hero_id or state.member(member_id).presence != "DEPLOYED": continue
		overrides.append({"actor_id":member_id,
			"action":Action.melee(member_id, target_id) \
				if member_id == companion_id else Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(hero_id, target_id), overrides))
	var wire: Dictionary = plan.to_dict(); var assessments: Dictionary = {}
	check(wire.accepted, "seed-two same-target BLEED preview accepted")
	for row in wire.actor_rows:
		if row.combat_assessment is Dictionary:
			assessments[int(row.actor_id)] = row.combat_assessment
	check_eq(assessments.size(), 2, "seed-two freezes both same-target assessments")
	if assessments.size() != 2: return finish()
	check_eq([assessments[hero_id].intent_ordinal,
		assessments[companion_id].intent_ordinal], [0, 1],
		"seed-two same-target ordinals exact")
	var hero_key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 0, hero_id, target_id)
	var companion_key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 1, companion_id, target_id)
	var hero_hit := Melee.lane_roll_milli(hero_key, "HIT")
	var hero_bleed := Melee.lane_roll_milli(hero_key, "BLEED")
	var companion_hit := Melee.lane_roll_milli(companion_key, "HIT")
	var companion_bleed := Melee.lane_roll_milli(companion_key, "BLEED")
	check(hero_hit < int(assessments[hero_id].hit_chance_milli) \
			and hero_bleed < int(assessments[hero_id].bleed_chance_milli),
		"seed-two ordinal-zero is keyed HIT+BLEED")
	var rng_before: int = world.rng.state
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "seed-two same-target BLEED batch commits")
	var actions: Dictionary = {}; var physical = null; var downed = null; var applied = null
	for event in result.events:
		if event.type == "action.melee_attack" and event.target_id == target_id \
				and event.actor_id in [hero_id, companion_id]:
			actions[event.actor_id] = event
		elif event.type == "combat.physical_damage" and event.target_id == target_id:
			physical = event
		elif event.type == "entity.downed" and event.target_id == target_id:
			downed = event
		elif event.type == "status.applied" and event.target_id == target_id:
			applied = event
	check_eq(actions.size(), 2, "seed-two emits both canonical melee leaves")
	if actions.size() == 2:
		var hero_action = actions[hero_id]
		var companion_action = actions[companion_id]
		check_eq(hero_action.data, _expected_bleed_hit_action_data(
			assessments[hero_id], hero_key, hero_hit, hero_bleed),
			"ordinal-zero lethal BLEED action exact canonical data")
		var expected_overkill := _expected_bleed_hit_action_data(
			assessments[companion_id], companion_key, companion_hit, companion_bleed)
		expected_overkill.outcome = "OVERKILL_SKIP"
		expected_overkill.bleed_proc_succeeded = false
		expected_overkill.final_damage = 0
		check_eq(companion_action.data, expected_overkill,
			"ordinal-one OVERKILL_SKIP retains frozen rolls and is childless")
		var companion_children: Array = result.events.filter(func(event):
			return event.cause_id == companion_action.id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		check_eq(companion_children.size(), 0,
			"BLEED batch ordinal-one OVERKILL_SKIP has zero combat children")
		if physical != null:
			var prefix_end := maxi(result.events.find(hero_action),
				result.events.find(companion_action))
			for prefix_event in result.events:
				if prefix_event.type == "party.override_committed" \
						and prefix_event.world_time == attack_time:
					prefix_end = maxi(prefix_end, result.events.find(prefix_event))
			check(prefix_end < result.events.find(physical),
				"both melee leaves and inline override precede BLEED result chain")
	check(physical != null and downed != null and applied != null,
		"lethal BLEED emits physical, DOWNED, then status.applied")
	if physical != null:
		check_eq([physical.magnitude, physical.cause_id, physical.data],
			[22, actions[hero_id].id if actions.has(hero_id) else -1,
				{"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":22}],
			"lethal BLEED physical driver exact")
	if physical != null and downed != null and applied != null:
		check_eq([result.events.find(downed), result.events.find(applied)],
			[result.events.find(physical) + 1, result.events.find(physical) + 2],
			"lethal BLEED lifecycle/status tail is contiguous")
		check_eq([downed.cause_id, applied.cause_id], [physical.id, physical.id],
			"DOWNED and BLEED apply cite exact physical driver")
	var ticks: Array = result.events.filter(func(event):
		return applied != null and event.type == "status.tick" \
			and event.target_id == target_id and event.cause_id == applied.id)
	check_eq(ticks.size(), 1,
		"DOWNED BLEED owner emits one due T300 tick")
	var tick = ticks[0] if ticks.size() == 1 else null
	if tick != null:
		check_eq([tick.step_index, tick.world_time, tick.actor_id, tick.target_id,
			tick.position, tick.magnitude, tick.instigator_id, tick.data],
			[processed_step, 300, -1, target_id,
				world.entities[target_id].position, 3, hero_id,
				{"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "tick_damage":3,
					"scheduled_tick_at":"300"}],
			"DOWNED BLEED T300 tick exact")
	var pressures: Array = result.events.filter(func(event):
		return tick != null and event.type == "combat.downed_damage" \
			and event.target_id == target_id and event.cause_id == tick.id)
	check_eq(pressures.size(), 1,
		"DOWNED BLEED T300 tick emits one BLEEDOUT pressure")
	var pressure = pressures[0] if pressures.size() == 1 else null
	if pressure != null:
		check_eq([pressure.step_index, pressure.world_time, pressure.actor_id,
			pressure.target_id, pressure.position, pressure.magnitude,
			pressure.instigator_id, pressure.data], [processed_step, 300, -1,
			target_id, tick.position, 3, hero_id, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":3,
				"applied_health_damage":0, "reason":"BLEEDOUT"}],
			"DOWNED BLEED pressure exact")
	var expiries: Array = result.events.filter(func(event):
		return pressure != null and event.type == "status.expired" \
			and event.target_id == target_id and event.cause_id == pressure.id)
	var deaths: Array = result.events.filter(func(event):
		return pressure != null and event.type == "entity.died" \
			and event.target_id == target_id and event.cause_id == pressure.id)
	check_eq([expiries.size(), deaths.size()], [1, 1],
		"BLEEDOUT emits exact owner cleanup and terminal death")
	var expired = expiries[0] if expiries.size() == 1 else null
	var death = deaths[0] if deaths.size() == 1 else null
	if expired != null:
		check_eq([expired.step_index, expired.world_time, expired.actor_id,
			expired.target_id, expired.position, expired.magnitude,
			expired.instigator_id, expired.data], [processed_step, 300, -1,
			target_id, pressure.position, 0, hero_id, {"schema_version":1,
				"status_ruleset_id":"bounded-status-lifecycle-v1",
				"status_id":"BLEEDING", "reason":"OWNER_DIED"}],
			"BLEEDOUT owner cleanup exact")
	if death != null:
		check_eq([death.step_index, death.world_time, death.actor_id,
			death.target_id, death.position, death.magnitude,
			death.instigator_id, death.data], [processed_step, 300, -1,
			target_id, pressure.position, 0, hero_id, {"schema_version":1,
				"life_ruleset_id":"active-downed-dead-v1",
				"previous_life_state":"DOWNED", "reason":"BLEEDOUT",
				"damage_type":"physical"}], "BLEEDOUT death exact")
	if tick != null and pressure != null and expired != null and death != null:
		check_eq([result.events.find(pressure), result.events.find(expired),
			result.events.find(death)], [result.events.find(tick) + 1,
				result.events.find(tick) + 2, result.events.find(tick) + 3],
			"T300 tick/pressure/cleanup/death tail is contiguous")
	var tail: Array = result.events.filter(func(event):
		return event.type in ["party.victory", "party.regroup_started",
			"party.member_regrouped", "party.regroup_completed"])
	var victory: Array = tail.filter(func(event): return event.type == "party.victory")
	var started: Array = tail.filter(func(event): return event.type == "party.regroup_started")
	var completed: Array = tail.filter(func(event): return event.type == "party.regroup_completed")
	check_eq([victory.size(), started.size(), completed.size()], [1, 1, 1],
		"final-enemy BLEEDOUT emits exact victory/regroup roots")
	if death != null and victory.size() == 1 and started.size() == 1 \
			and completed.size() == 1:
		check_eq([victory[0].cause_id, started[0].cause_id,
			completed[0].cause_id], [death.id, victory[0].id, started[0].id],
			"BLEEDOUT victory/regroup exact cause chain")
		for event in tail:
			check_eq([event.step_index, event.world_time], [processed_step, 300],
				"%s shares BLEEDOUT terminal boundary" % event.type)
	var rows: Array = world.combatant_states[target_id].status_rows
	check_eq([world.entities[target_id].health,
		world.combatant_states[target_id].life_state, rows.size(), state.safe_phase],
		[0, "DEAD", 0, "GROUPED_COMPLETE"],
		"lethal BLEED cadence ends DEAD with no row and completed regroup")
	check_eq(world.rng.state, rng_before,
		"same-target BLEED shadow consumes no global RNG")
	return finish()

func test_party_fresh_finisher_defers_regroup_until_due_occurrences_complete() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var target_id: int = probe_state.enemy_ids[0]
	var first_step: int = probe_world.step_index + 1
	var first_time: int = probe_world.world_time
	var first_context := "PARTY_TURN/%d" % first_step
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var key := Melee.commitment_key(candidate_seed, first_step, first_time,
			first_context, 0, hero_id, target_id)
		if Melee.lane_roll_milli(key, "HIT") < 950 \
				and Melee.lane_roll_milli(key, "BLEED") >= 600:
			selected_seed = candidate_seed; break
	check(selected_seed > 0, "fresh-turn FINISHER opening HIT/no-BLEED seed found")
	if selected_seed < 0: return finish()
	var session = _engaged_adjacent(selected_seed)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; target_id = state.enemy_ids[0]
	world.entities[target_id].health = 22
	var first_overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != hero_id and state.member(member_id).presence == "DEPLOYED":
			first_overrides.append({"actor_id":member_id,
				"action":Action.hold(member_id)})
	var rng_before: int = world.rng.state
	var first_plan = session.sim.preview_party_turn(Request.new(
		Action.melee(hero_id, target_id), first_overrides))
	var first_result = session.sim.step_party_turn(first_plan)
	check(first_result.accepted, "opening canonical downing Party turn accepted")
	var opening_actions: Array = first_result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == hero_id \
			and event.target_id == target_id)
	check_eq(opening_actions.size(), 1, "opening Party HIT action emitted once")
	if opening_actions.size() == 1:
		check_eq([opening_actions[0].data.get("outcome"),
			opening_actions[0].data.get("bleed_proc_succeeded")], ["HIT", false],
			"opening turn is canonical HIT without BLEED")
	check_eq([world.entities[target_id].health,
		world.combatant_states[target_id].life_state], [0, "DOWNED"],
		"opening Party turn leaves final enemy DOWNED")
	check(first_result.events.filter(func(event):
		return (event.type == "entity.died" and event.target_id == target_id) \
			or event.type in ["party.victory", "party.regroup_started",
				"party.regroup_completed"]).is_empty(),
		"opening DOWNED turn has no death/victory/regroup")
	if world.combatant_states[target_id].life_state != "DOWNED": return finish()

	var finisher_step: int = world.step_index + 1
	var finisher_time: int = world.world_time
	var finisher_context := "PARTY_TURN/%d" % finisher_step
	var finisher_overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != hero_id and state.member(member_id).presence == "DEPLOYED":
			finisher_overrides.append({"actor_id":member_id,
				"action":Action.hold(member_id)})
	var finisher_plan = session.sim.preview_party_turn(Request.new(
		Action.melee(hero_id, target_id), finisher_overrides))
	var finisher_wire: Dictionary = finisher_plan.to_dict()
	check(finisher_wire.accepted, "fresh explicit FINISHER preview accepted")
	var finisher_end_time: int = finisher_time + int(finisher_wire.total_time_cost)
	var assessment: Dictionary = {}
	for row in finisher_wire.actor_rows:
		if int(row.actor_id) == hero_id: assessment = row.combat_assessment; break
	check(not assessment.is_empty(), "fresh explicit FINISHER assessment present")
	if assessment.is_empty(): return finish()
	check_eq([assessment.target_life_state, assessment.intent_mode,
		assessment.processed_step_index, assessment.attack_start_world_time,
		assessment.batch_context, assessment.intent_ordinal],
		["DOWNED", "FINISHER", str(finisher_step), str(finisher_time),
			finisher_context, 0], "fresh-turn FINISHER preview freezes exact mode/context")
	var key := Melee.commitment_key(world.seed, finisher_step, finisher_time,
		finisher_context, 0, hero_id, target_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	var result = session.sim.step_party_turn(finisher_plan)
	check(result.accepted, "fresh explicit FINISHER Party turn commits: %s" % result.reason)
	var actions: Array = result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == hero_id \
			and event.target_id == target_id)
	check_eq(actions.size(), 1, "fresh FINISHER action emitted exactly once")
	var action = actions[0] if actions.size() == 1 else null
	if action != null:
		check_eq([action.step_index, action.world_time, action.position,
			action.magnitude, action.cause_id, action.instigator_id],
			[finisher_step, finisher_time, action.position, 24, -1, hero_id],
			"fresh FINISHER action exact canonical envelope")
		check_eq(action.data, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-hero-v1",
			"target_profile_id":"party-goblin-v1",
			"batch_context":finisher_context, "intent_ordinal":0,
			"intent_mode":"FINISHER", "target_life_at_batch_start":"DOWNED",
			"outcome":"FINISHER", "processed_step_index":str(finisher_step),
			"attack_start_world_time":str(finisher_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":1000, "hit_roll_milli":hit_roll,
			"bleed_chance_milli":0, "bleed_roll_milli":bleed_roll,
			"bleed_proc_succeeded":false, "base_damage":24,
			"target_evasion_milli":100, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":0},
			"fresh FINISHER exact canonical v1 data")
	var pressures: Array = result.events.filter(func(event):
		return action != null and event.type == "combat.downed_damage" \
			and event.cause_id == action.id and event.target_id == target_id)
	check_eq(pressures.size(), 1, "fresh FINISHER emits one downed-damage driver")
	var pressure = pressures[0] if pressures.size() == 1 else null
	if pressure != null:
		check_eq([pressure.step_index, pressure.world_time, pressure.actor_id,
			pressure.target_id, pressure.position, pressure.magnitude,
			pressure.cause_id, pressure.instigator_id, pressure.data],
			[finisher_step, finisher_time, -1, target_id, action.position, 22,
				action.id, hero_id, {"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":22,
					"applied_health_damage":0, "reason":"FINISHER"}],
			"fresh FINISHER downed-damage exact")
	var deaths: Array = result.events.filter(func(event):
		return pressure != null and event.type == "entity.died" \
			and event.target_id == target_id and event.cause_id == pressure.id)
	check_eq(deaths.size(), 1, "fresh FINISHER emits one terminal death")
	var death = deaths[0] if deaths.size() == 1 else null
	if death != null:
		check_eq([death.step_index, death.world_time, death.actor_id,
			death.target_id, death.position, death.magnitude, death.cause_id,
			death.instigator_id, death.data], [finisher_step, finisher_time, -1,
			target_id, action.position, 0, pressure.id, hero_id,
			{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
				"previous_life_state":"DOWNED", "reason":"FINISHER",
				"damage_type":"physical"}], "fresh FINISHER death exact")
	var forbidden_results: Array = result.events.filter(func(event):
		return action != null and event.cause_id == action.id and event.type in [
			"combat.attack_missed", "combat.physical_damage", "entity.downed"])
	check(forbidden_results.is_empty(),
		"fresh FINISHER has no miss/physical/new-downed child")
	var tail: Array = result.events.filter(func(event):
		return event.type in ["party.victory", "party.regroup_started",
			"party.member_regrouped", "party.regroup_completed"])
	check(not tail.is_empty(), "final FINISHER emits victory and regroup tail")
	if death != null and not tail.is_empty():
		check(result.events.find(death) < result.events.find(tail[0]),
			"FINISHER death precedes victory/regroup tail")
		check_eq(result.events.find(tail[0]), result.events.size() - tail.size(),
			"all due schedule/environment events complete before terminal regroup tail")
		check_eq([result.processed_step_index, result.start_time,
			result.end_time, result.time_cost, result.timeline],
			[finisher_step, finisher_time, finisher_end_time,
				int(finisher_wire.total_time_cost), finisher_wire.timeline],
			"FINISHER result retains exact accepted due-occurrence timeline")
		for event in tail:
			check_eq([event.step_index, event.world_time],
				[finisher_step, finisher_end_time],
				"%s is deferred to end-time but tail remains elapsed-zero" % event.type)
		var victory = tail.filter(func(event): return event.type == "party.victory")
		var started = tail.filter(func(event): return event.type == "party.regroup_started")
		var completed = tail.filter(func(event): return event.type == "party.regroup_completed")
		check_eq([victory.size(), started.size(), completed.size()], [1, 1, 1],
			"FINISHER has exact single victory/regroup roots")
		if victory.size() == 1 and started.size() == 1 and completed.size() == 1:
			check_eq([victory[0].cause_id, started[0].cause_id,
				completed[0].cause_id], [death.id, victory[0].id, started[0].id],
				"FINISHER victory/regroup exact cause chain")
	check_eq([world.entities[target_id].health,
		world.combatant_states[target_id].life_state, state.safe_phase],
		[0, "DEAD", "GROUPED_COMPLETE"],
		"fresh FINISHER final enemy death completes regroup")
	check_eq(world.rng.state, rng_before,
		"two-turn keyed FINISHER flow consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "fresh FINISHER snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"fresh FINISHER snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "fresh FINISHER snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"fresh FINISHER snapshot roundtrip exact")
	return finish()

func test_party_same_outer_enemy_and_protagonist_deaths_prioritize_defeat() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var target_id: int = probe_state.enemy_ids[0]
	var first_step: int = probe_world.step_index + 1
	var first_time: int = probe_world.world_time
	var first_context := "PARTY_TURN/%d" % first_step
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, first_step,
			first_time, first_context, 0, hero_id, target_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 950 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") >= 600:
			selected_seed = candidate_seed; break
	check(selected_seed > 0, "defeat-priority opening HIT/no-BLEED seed found")
	if selected_seed < 0: return finish()
	var session = _engaged_adjacent(selected_seed)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; target_id = state.enemy_ids[0]
	world.entities[target_id].health = 22
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != hero_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var opening = session.sim.step_party_turn(session.sim.preview_party_turn(
		Request.new(Action.melee(hero_id, target_id), overrides)))
	check(opening.accepted, "defeat-priority opening downing turn accepted")
	check_eq([world.entities[target_id].health,
		world.combatant_states[target_id].life_state], [0, "DOWNED"],
		"defeat-priority opening leaves final enemy DOWNED")
	check(opening.events.filter(func(event): return event.type in ["entity.died",
		"party.victory", "party.regroup_started", "party.regroup_completed"]).is_empty(),
		"unresolved DOWNED enemy emits no death/victory/regroup")
	if world.combatant_states[target_id].life_state != "DOWNED": return finish()

	var hero_position: Vector2i = world.entities[hero_id].position
	var ignition = world.emit_event("environment.ignited", -1, -1,
		hero_position, 100)
	check(ignition != null, "defeat-priority exact fire source seeded")
	if ignition == null: return finish()
	var fire_tile = world.tile_at(hero_position)
	fire_tile.fire = 100
	fire_tile.fire_source_event_id = ignition.id
	fire_tile.fire_damage_eligible_time = world.world_time
	world.entities[hero_id].health = 5
	var environment_due := -1
	for schedule in world.scheduled_entries:
		if str(schedule.kind) == "system.environment_tick":
			environment_due = int(schedule.due_time); break
	check(environment_due > world.world_time and environment_due <= world.world_time + 100,
		"due environment tick lies inside fresh FINISHER operation")

	var processed_step: int = world.step_index + 1
	var start_time: int = world.world_time
	var event_start: int = world.events.size()
	var rng_before: int = world.rng.state
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = rng_before
	for neighbor in world.cardinal_neighbors(hero_position):
		var neighbor_tile = world.tile_at(neighbor)
		if neighbor_tile.fire == 0 and neighbor_tile.flammability > 0:
			expected_rng.randi_range(1, 100)
	var plan = session.sim.preview_party_turn(Request.new(
		Action.melee(hero_id, target_id), overrides))
	check(plan.to_dict().accepted, "defeat-priority fresh FINISHER preview accepted")
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "same-outer FINISHER plus lethal fire commits: %s" % result.reason)
	var enemy_deaths: Array = result.events.filter(func(event):
		return event.type == "entity.died" and event.target_id == target_id \
			and event.data.get("reason") == "FINISHER")
	var hero_deaths: Array = result.events.filter(func(event):
		return event.type == "entity.died" and event.target_id == hero_id)
	check_eq([enemy_deaths.size(), hero_deaths.size()], [1, 1],
		"same outer operation emits both exact terminal deaths")
	if enemy_deaths.size() == 1 and hero_deaths.size() == 1:
		check_eq([enemy_deaths[0].step_index, hero_deaths[0].step_index],
			[processed_step, processed_step], "both death chains share processed step")
		check_eq([enemy_deaths[0].world_time, hero_deaths[0].world_time],
			[start_time, environment_due], "FINISHER precedes due fire at exact times")
		check(result.events.find(enemy_deaths[0]) < result.events.find(hero_deaths[0]),
			"enemy terminal chain precedes protagonist terminal chain")
		var hero_damage = world.event_by_id(hero_deaths[0].cause_id)
		check(hero_damage != null, "protagonist legacy fire death cites damage")
		if hero_damage != null:
			check_eq([hero_damage.type, hero_damage.step_index,
				hero_damage.world_time, hero_damage.actor_id, hero_damage.target_id,
				hero_damage.position, hero_damage.magnitude, hero_damage.cause_id,
				hero_damage.instigator_id, hero_damage.data],
				["combat.fire_damage", processed_step, environment_due, -1, hero_id,
					hero_position, 5, ignition.id, -1, {"damage_type":"fire"}],
				"protagonist exact allowed legacy fire driver")
		check_eq([hero_deaths[0].actor_id, hero_deaths[0].target_id,
			hero_deaths[0].position, hero_deaths[0].magnitude,
			hero_deaths[0].instigator_id, hero_deaths[0].data],
			[-1, hero_id, hero_position, 0, -1, {"damage_type":"fire"}],
			"protagonist exact allowed legacy fire death")
	var forbidden_tail: Array = result.events.filter(func(event):
		return event.type in ["party.victory", "party.regroup_started",
			"party.member_regrouped", "party.regroup_completed"])
	check(forbidden_tail.is_empty(),
		"same-outer protagonist death suppresses victory/regroup: %s" % [
			forbidden_tail.map(func(event): return event.type)])
	check_eq([world.entities[hero_id].health,
		world.combatant_states[hero_id].life_state,
		world.entities[target_id].health,
		world.combatant_states[target_id].life_state,
		state.member(hero_id).presence, state.safe_phase],
		[0, "DEAD", 0, "DEAD", "DEFEATED", "PARTY_DEFEATED"],
		"simultaneous outer resolution publishes defeat priority")
	check(result.events.filter(func(event):
		return event.type in ["status.applied", "status.refreshed"] \
			and event.target_id == hero_id).is_empty(),
		"terminal environmental death applies no protagonist status")
	check_eq(world.events.size() - event_start, result.events.size(),
		"same-outer result owns every emitted event")
	check_eq(world.rng.state, expected_rng.state,
		"same-outer keyed combat plus fire spread consumes exact environment RNG draws")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "defeat-priority snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"defeat-priority snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "defeat-priority snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"defeat-priority snapshot/RNG roundtrip exact")
	return finish()

func test_party_enemy_actor_batch_canonical_hit_causes_immediate_party_defeat() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var enemy_id: int = probe_state.enemy_ids[0]
	var processed_step: int = probe_world.step_index + 1
	var actor_schedule_id := -1; var attack_time := -1
	for schedule in probe_world.scheduled_entries:
		if schedule.kind == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time); break
	check(actor_schedule_id > 0 and attack_time > probe_world.world_time,
		"Party enemy cadence identity/due time found")
	var context := "PARTY_ENEMY/%d/%d" % [actor_schedule_id, attack_time]
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var key := Melee.commitment_key(candidate_seed, processed_step, attack_time,
			context, 0, enemy_id, hero_id)
		if Melee.lane_roll_milli(key, "HIT") < 900 \
				and Melee.lane_roll_milli(key, "BLEED") >= 300:
			selected_seed = candidate_seed; break
	check(selected_seed > 0, "Party enemy deterministic HIT/no-BLEED seed found")
	if selected_seed < 0: return finish()
	var session = _engaged_adjacent(selected_seed)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; enemy_id = state.enemy_ids[0]
	processed_step = world.step_index + 1
	actor_schedule_id = -1; attack_time = -1
	for schedule in world.scheduled_entries:
		if schedule.kind == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time); break
	context = "PARTY_ENEMY/%d/%d" % [actor_schedule_id, attack_time]
	var enemy_position: Vector2i = world.entities[enemy_id].position
	var move_destination := Vector2i(-1, -1)
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
			Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1)]:
		var candidate: Vector2i = enemy_position + direction
		if candidate != world.entities[hero_id].position \
				and session.sim.movement.assess_move(hero_id, candidate).accepted:
			move_destination = candidate; break
	check(move_destination != Vector2i(-1, -1),
		"protagonist has legal MOVE that remains enemy-adjacent")
	if move_destination == Vector2i(-1, -1): return finish()
	world.entities[hero_id].health = 10
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != hero_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.move_to(hero_id, move_destination), overrides))
	check(plan.to_dict().accepted, "Party MOVE turn with due enemy cadence previews")
	var rng_before: int = world.rng.state
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "Party MOVE turn with lethal enemy cadence commits")
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 0, enemy_id, hero_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	var actions: Array = result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == enemy_id \
			and event.target_id == hero_id)
	check_eq(actions.size(), 1, "Party enemy cadence emits one melee action")
	var action = actions[0] if actions.size() == 1 else null
	if action != null:
		check_eq([action.step_index, action.world_time, action.actor_id,
			action.target_id, action.position, action.magnitude, action.cause_id,
			action.instigator_id], [processed_step, attack_time, enemy_id, hero_id,
			move_destination, 16, -1, enemy_id],
			"Party enemy cadence action exact canonical envelope")
		check_eq(action.data, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-goblin-v1",
			"target_profile_id":"party-hero-v1", "batch_context":context,
			"intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":900, "hit_roll_milli":hit_roll,
			"bleed_chance_milli":300, "bleed_roll_milli":bleed_roll,
			"bleed_proc_succeeded":false, "base_damage":16,
			"target_evasion_milli":150, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":14},
			"Party enemy cadence action exact canonical HIT data")
	var damages: Array = result.events.filter(func(event):
		return action != null and event.type == "combat.physical_damage" \
			and event.cause_id == action.id and event.target_id == hero_id)
	check_eq(damages.size(), 1, "Party enemy lethal HIT emits one physical driver")
	var damage = damages[0] if damages.size() == 1 else null
	if damage != null:
		check_eq([damage.step_index, damage.world_time, damage.actor_id,
			damage.target_id, damage.position, damage.magnitude, damage.cause_id,
			damage.instigator_id, damage.data], [processed_step, attack_time, -1,
			hero_id, move_destination, 10, action.id, enemy_id,
			{"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":14,
				"applied_health_damage":10}],
			"Party enemy lethal physical requested14/applied10 exact")
	var downed_events: Array = result.events.filter(func(event):
		return damage != null and event.type == "entity.downed" \
			and event.target_id == hero_id and event.cause_id == damage.id)
	check_eq(downed_events.size(), 1, "protagonist lethal HIT emits terminal DOWNED")
	var downed = downed_events[0] if downed_events.size() == 1 else null
	if downed != null:
		check_eq([downed.step_index, downed.world_time, downed.actor_id,
			downed.target_id, downed.position, downed.magnitude,
			downed.instigator_id, downed.data], [processed_step, attack_time, -1,
			hero_id, move_destination, 0, enemy_id, {"schema_version":1,
				"life_ruleset_id":"active-downed-dead-v1",
				"previous_life_state":"ACTIVE", "downed_resolve_at":"-1",
				"terminal_immediate":true}],
			"protagonist terminal DOWNED exact")
	var deaths: Array = result.events.filter(func(event):
		return downed != null and event.type == "entity.died" \
			and event.target_id == hero_id and event.cause_id == downed.id)
	check_eq(deaths.size(), 1, "terminal protagonist DOWNED immediately emits death")
	var death = deaths[0] if deaths.size() == 1 else null
	if death != null:
		check_eq([death.step_index, death.world_time, death.actor_id,
			death.target_id, death.position, death.magnitude, death.instigator_id,
			death.data], [processed_step, attack_time, -1, hero_id,
			move_destination, 0, enemy_id, {"schema_version":1,
				"life_ruleset_id":"active-downed-dead-v1",
				"previous_life_state":"DOWNED", "reason":"PARTY_DEFEAT",
				"damage_type":"physical"}],
			"protagonist PARTY_DEFEAT death exact")
		if downed != null:
			check(result.events.find(damage) + 1 == result.events.find(downed) \
				and result.events.find(downed) + 1 == result.events.find(death),
				"physical to terminal DOWNED to death are immediate")
	var hero_state = world.combatant_states[hero_id]
	check_eq([world.entities[hero_id].health, hero_state.life_state,
		hero_state.guarded_until, hero_state.guard_source_event_id,
		hero_state.downed_at, hero_state.downed_resolve_at,
		hero_state.downed_source_event_id, hero_state.recovery_lock_until,
		hero_state.recovery_source_event_id, hero_state.status_rows.size(),
		state.member(hero_id).presence, state.safe_phase],
		[0, "DEAD", 0, -1, -1, -1, -1, 0, -1, 0,
			"DEFEATED", "PARTY_DEFEATED"],
		"protagonist PARTY_DEFEAT final authorities exact")
	check(result.events.filter(func(event):
		return (event.type in ["status.applied", "status.refreshed"] \
			and event.target_id == hero_id) or event.type in ["party.victory",
			"party.regroup_started", "party.regroup_completed"]).is_empty(),
		"terminal protagonist has no status proc or victory/regroup")
	check_eq(world.rng.state, rng_before,
		"Party enemy keyed lethal cadence consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "Party enemy lethal snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"Party enemy lethal snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "Party enemy lethal snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"Party enemy lethal snapshot roundtrip exact")
	return finish()

func test_party_enemy_actor_batch_commits_keyed_bleed_hit_and_status() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var enemy_id: int = probe_state.enemy_ids[0]
	var processed_step: int = probe_world.step_index + 1
	var actor_schedule_id := -1; var attack_time := -1
	for schedule in probe_world.scheduled_entries:
		if schedule.kind == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time)
			break
	check(actor_schedule_id > 0 and attack_time > probe_world.world_time,
		"BLEED Party enemy cadence identity/due time found")
	var context := "PARTY_ENEMY/%d/%d" % [actor_schedule_id, attack_time]
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 0, enemy_id, hero_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 900 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") < 300:
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "reachable PARTY_ENEMY keyed HIT+BLEED seed found")
	if selected_seed < 0: return finish()

	var session = _engaged_adjacent(selected_seed)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; enemy_id = state.enemy_ids[0]
	processed_step = world.step_index + 1
	actor_schedule_id = -1; attack_time = -1
	for schedule in world.scheduled_entries:
		if schedule.kind == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time)
			break
	context = "PARTY_ENEMY/%d/%d" % [actor_schedule_id, attack_time]
	var enemy_position: Vector2i = world.entities[enemy_id].position
	var move_destination := Vector2i(-1, -1)
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
			Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1)]:
		var candidate: Vector2i = enemy_position + direction
		if candidate != world.entities[hero_id].position \
				and session.sim.movement.assess_move(hero_id, candidate).accepted:
			move_destination = candidate
			break
	check(move_destination != Vector2i(-1, -1),
		"BLEED target has legitimate adjacent Party MOVE destination")
	if move_destination == Vector2i(-1, -1): return finish()
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != hero_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(
		Action.move_to(hero_id, move_destination), overrides))
	check(plan.to_dict().accepted, "Party MOVE with due BLEED enemy cadence previews")
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 0, enemy_id, hero_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	check(hit_roll < 900 and bleed_roll < 300,
		"selected PARTY_ENEMY commitment succeeds HIT and BLEED")
	var hp_before: int = world.entities[hero_id].health
	var rng_before: int = world.rng.state
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "Party MOVE with due BLEED enemy cadence commits")
	var actions: Array = result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == enemy_id \
			and event.target_id == hero_id)
	check_eq(actions.size(), 1, "PARTY_ENEMY BLEED cadence emits one melee action")
	var action = actions[0] if actions.size() == 1 else null
	if action != null:
		check_eq([action.step_index, action.world_time, action.actor_id,
			action.target_id, action.position, action.magnitude, action.cause_id,
			action.instigator_id], [processed_step, attack_time, enemy_id, hero_id,
			move_destination, 16, -1, enemy_id],
			"PARTY_ENEMY BLEED action exact canonical envelope")
		check_eq(action.data, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-goblin-v1",
			"target_profile_id":"party-hero-v1", "batch_context":context,
			"intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":900, "hit_roll_milli":hit_roll,
			"bleed_chance_milli":300, "bleed_roll_milli":bleed_roll,
			"bleed_proc_succeeded":true, "base_damage":16,
			"target_evasion_milli":150, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":14},
			"PARTY_ENEMY BLEED action exact canonical v1 data")
	var physicals: Array = result.events.filter(func(event):
		return action != null and event.type == "combat.physical_damage" \
			and event.cause_id == action.id and event.target_id == hero_id)
	check_eq(physicals.size(), 1, "PARTY_ENEMY BLEED emits one physical child")
	var physical = physicals[0] if physicals.size() == 1 else null
	if physical != null:
		check_eq([physical.step_index, physical.world_time, physical.actor_id,
			physical.target_id, physical.position, physical.magnitude,
			physical.instigator_id, physical.data], [processed_step, attack_time,
			-1, hero_id, move_destination, 14, enemy_id, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":14,
				"applied_health_damage":14}],
			"PARTY_ENEMY BLEED physical exact canonical v1")
		var last_enemy_leaf_index := -1
		for index in range(result.events.size()):
			var event = result.events[index]
			if event.world_time == attack_time and event.actor_id in state.enemy_ids \
					and event.type.begins_with("action."):
				last_enemy_leaf_index = maxi(last_enemy_leaf_index, index)
		check(last_enemy_leaf_index < result.events.find(physical),
			"all PARTY_ENEMY action leaves precede BLEED result chain")
	var applied_rows: Array = result.events.filter(func(event):
		return physical != null and event.type == "status.applied" \
			and event.target_id == hero_id and event.cause_id == physical.id)
	check_eq(applied_rows.size(), 1,
		"PARTY_ENEMY successful proc emits one status.applied")
	var applied = applied_rows[0] if applied_rows.size() == 1 else null
	if physical != null and applied != null:
		check_eq([applied.step_index, applied.world_time, applied.actor_id,
			applied.target_id, applied.position, applied.magnitude,
			applied.cause_id, applied.instigator_id, applied.data],
			[processed_step, attack_time, -1, hero_id, move_destination, 0,
				physical.id, enemy_id, {"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "next_tick_at":"300",
					"expires_at":"500", "tick_damage":3}],
			"PARTY_ENEMY BLEED status apply exact canonical v1")
		check_eq(result.events.find(applied), result.events.find(physical) + 1,
			"PARTY_ENEMY status apply immediately follows typed damage")
	var hero_state = world.combatant_states[hero_id]
	check_eq([world.entities[hero_id].health, hero_state.life_state,
		hero_state.status_rows.size()], [hp_before - 14, "ACTIVE", 1],
		"PARTY_ENEMY BLEED leaves active target with one row")
	if hero_state.status_rows.size() == 1 and applied != null:
		check_eq(hero_state.status_rows[0].to_dict(), {"schema_version":1,
			"status_id":"BLEEDING", "applied_at":"200", "refreshed_at":"200",
			"next_tick_at":"300", "expires_at":"500",
			"source_event_id":str(applied.id)},
			"PARTY_ENEMY BLEED authoritative row exact")
	check(result.events.filter(func(event):
		return event.type == "action.melee_attack" \
			and event.data.get("combat_ruleset_id") == "fixed-melee-v1").is_empty(),
		"PARTY_ENEMY BLEED cadence emits no fixed-melee action")
	check_eq(world.rng.state, rng_before,
		"PARTY_ENEMY keyed BLEED cadence consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "PARTY_ENEMY BLEED snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"PARTY_ENEMY BLEED snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "PARTY_ENEMY BLEED snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"PARTY_ENEMY BLEED snapshot roundtrip exact")
	return finish()

func test_runtime_nonhero_downed_recovers_at_due_cadence_without_same_tick_action() -> bool:
	var probe = _engaged_adjacent(1)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var enemy_id: int = probe_state.enemy_ids[0]
	var opening_step: int = probe_world.step_index + 1
	var opening_time: int = probe_world.world_time
	var opening_context := "PARTY_TURN/%d" % opening_step
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, opening_step,
			opening_time, opening_context, 0, hero_id, enemy_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 950 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") >= 600:
			selected_seed = candidate_seed; break
	check(selected_seed > 0, "runtime recovery opening HIT/no-BLEED seed found")
	if selected_seed < 0: return finish()
	var session = _engaged_adjacent(selected_seed)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; enemy_id = state.enemy_ids[0]
	world.entities[enemy_id].health = 22
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != hero_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var rng_before: int = world.rng.state
	var opening = session.sim.step_party_turn(session.sim.preview_party_turn(
		Request.new(Action.melee(hero_id, enemy_id), overrides)))
	check(opening.accepted, "runtime recovery opening downing turn accepted")
	var downed_events: Array = opening.events.filter(func(event):
		return event.type == "entity.downed" and event.target_id == enemy_id)
	check_eq(downed_events.size(), 1, "runtime recovery opening emits one DOWNED source")
	var downed = downed_events[0] if downed_events.size() == 1 else null
	if downed == null: return finish()
	var enemy_state = world.combatant_states[enemy_id]
	var resolve_at: int = int(downed.data.downed_resolve_at)
	check_eq([world.world_time, world.entities[enemy_id].health,
		enemy_state.life_state, enemy_state.downed_at,
		enemy_state.downed_resolve_at, enemy_state.downed_source_event_id,
		enemy_state.status_rows.size()], [200, 0, "DOWNED", opening_time,
		resolve_at, downed.id, 0], "runtime recovery DOWNED authority exact")
	check_eq(resolve_at, 300, "runtime recovery uses strict next-boundary-plus-one cadence")
	check(opening.events.filter(func(event):
		return event.actor_id == enemy_id and event.world_time == 200 \
			and event.type.begins_with("action.")).is_empty(),
		"DOWNED enemy is excluded from first actor cadence")
	check(not world.can_act(enemy_id, world.world_time) \
		and not world.is_autonomous_target(enemy_id),
		"settled DOWNED enemy remains excluded before recovery")
	var downed_snapshot = session.sim.snapshot()
	check(downed_snapshot is Dictionary, "runtime DOWNED snapshot constructs")
	if downed_snapshot is Dictionary:
		check_eq(WorldState.snapshot_restore_error(downed_snapshot), "",
			"runtime DOWNED snapshot restores before deadline")
		var downed_restored = Simulator.from_snapshot(downed_snapshot)
		check(downed_restored != null, "runtime DOWNED snapshot loads")
		if downed_restored != null:
			check_eq(downed_restored.snapshot(), downed_snapshot,
				"runtime DOWNED snapshot roundtrip exact")

	var recovery_step: int = world.step_index + 1
	var recovery_start: int = world.world_time
	var recovery = session.sim.step_party_turn(session.sim.preview_party_turn(
		Request.new(Action.hold(hero_id), overrides)))
	check(recovery.accepted,
		"outer operation through recovery deadline accepted: %s" % recovery.reason)
	if not recovery.accepted: return finish()
	check_eq([recovery.processed_step_index, recovery.start_time,
		recovery.end_time], [recovery_step, recovery_start, resolve_at],
		"recovery operation exact processed-step/time boundary")
	var recovered_events: Array = recovery.events.filter(func(event):
		return event.type == "entity.recovered" and event.target_id == enemy_id)
	check_eq(recovered_events.size(), 1, "deadline emits one canonical recovery")
	var recovered = recovered_events[0] if recovered_events.size() == 1 else null
	var recovered_health: int = maxi(1,
		int((world.entities[enemy_id].max_health + 9) / 10))
	var recovery_lock_until := resolve_at + 100
	if recovered != null:
		check_eq([recovered.step_index, recovered.world_time, recovered.actor_id,
			recovered.target_id, recovered.position, recovered.magnitude,
			recovered.cause_id, recovered.instigator_id, recovered.data],
			[recovery_step, resolve_at, -1, enemy_id,
				world.entities[enemy_id].position, recovered_health, downed.id, hero_id,
				{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
					"recovered_health":recovered_health,
					"recovery_lock_until":str(recovery_lock_until)}],
			"runtime recovered event exact envelope/data/provenance")
	check(recovery.events.filter(func(event):
		return event.actor_id == enemy_id and event.world_time == resolve_at \
			and event.type.begins_with("action.")).is_empty(),
		"recovered actor does not join the cadence whose tick-start set excluded it")
	enemy_state = world.combatant_states[enemy_id]
	check_eq([world.entities[enemy_id].health, enemy_state.life_state,
		enemy_state.guarded_until, enemy_state.guard_source_event_id,
		enemy_state.downed_at, enemy_state.downed_resolve_at,
		enemy_state.downed_source_event_id, enemy_state.recovery_lock_until,
		enemy_state.recovery_source_event_id, enemy_state.status_rows.size()],
		[recovered_health, "ACTIVE", 0, -1, -1, -1, -1,
			recovery_lock_until, recovered.id if recovered != null else -1, 0],
		"runtime recovery state resets DOWNED/guard sentinels and sets exact lock")
	check(not world.can_act(enemy_id, resolve_at),
		"recovered actor remains locked at recovery cadence")
	check_eq(world.rng.state, rng_before,
		"DOWNED-to-recovered lifecycle consumes no global RNG")
	var recovery_snapshot = session.sim.snapshot()
	check(recovery_snapshot is Dictionary, "runtime recovered snapshot constructs")
	if recovery_snapshot is Dictionary:
		check_eq(WorldState.snapshot_restore_error(recovery_snapshot), "",
			"runtime recovered snapshot restores")
		var recovery_restored = Simulator.from_snapshot(recovery_snapshot)
		check(recovery_restored != null, "runtime recovered snapshot loads")
		if recovery_restored != null:
			check_eq(recovery_restored.snapshot(), recovery_snapshot,
				"runtime recovered snapshot roundtrip exact")

	var unlocked_step: int = world.step_index + 1
	var unlocked = session.sim.step_party_turn(session.sim.preview_party_turn(
		Request.new(Action.hold(hero_id), overrides)))
	check(unlocked.accepted, "next actor cadence after recovery lock accepted")
	if not unlocked.accepted: return finish()
	check_eq([unlocked.processed_step_index, unlocked.end_time],
		[unlocked_step, recovery_lock_until],
		"next actor cadence reaches exact recovery-lock boundary")
	var enemy_actions: Array = unlocked.events.filter(func(event):
		return event.actor_id == enemy_id and event.world_time == recovery_lock_until \
			and event.type.begins_with("action."))
	check_eq(enemy_actions.size(), 1,
		"recovered actor may emit exactly one action at next cadence")
	check(world.can_act(enemy_id, recovery_lock_until),
		"recovery lock releases exactly at boundary")
	check(unlocked.events.filter(func(event):
		return event.type == "entity.recovered" and event.target_id == enemy_id).is_empty(),
		"recovery is not duplicated at later cadence")
	check_eq(world.rng.state, rng_before,
		"post-lock keyed actor cadence consumes no global RNG")
	var unlocked_snapshot = session.sim.snapshot()
	check(unlocked_snapshot is Dictionary, "post-lock runtime snapshot constructs")
	if unlocked_snapshot is Dictionary:
		check_eq(WorldState.snapshot_restore_error(unlocked_snapshot), "",
			"post-lock runtime snapshot restores")
		var unlocked_restored = Simulator.from_snapshot(unlocked_snapshot)
		check(unlocked_restored != null, "post-lock runtime snapshot loads")
		if unlocked_restored != null:
			check_eq(unlocked_restored.snapshot(), unlocked_snapshot,
				"post-lock runtime snapshot roundtrip exact")
	return finish()

func test_phase3_actor_batch_emits_decisions_then_exact_canonical_melee_actions() -> bool:
	var session = LabSession.new(7, 125)
	check(session.advance_ticks(1).ok, "Phase3 canonical batch activation")
	var world = session.sim.world
	var lead_id: int = session.lead_roster()[0].entity_id
	var lead_state = world.agent_states[lead_id]
	var threat_id: int = lead_state.active_threat_id
	var ally_id := -1
	for actor_id in world.agent_states:
		var actor_state = world.agent_states[actor_id]
		if actor_state.trial_slot == 0 and actor_state.controller_kind == "PASSIVE_ALLY":
			ally_id = actor_id
		if actor_state.trial_slot != 0: actor_state.busy_until = 10000
	check(ally_id > 0, "Phase3 slot-zero ally found")
	if ally_id < 0: return finish()
	world.agent_states[ally_id].busy_until = 10000
	world.entities[lead_id].position = world.entities[threat_id].position + Vector2i(0, 1)
	world.entities[ally_id].position = world.entities[threat_id].position + Vector2i(1, 0)
	world.entities[lead_id].health = world.entities[lead_id].max_health
	world.entities[threat_id].health = world.entities[threat_id].max_health
	world.entities[ally_id].health = world.entities[ally_id].max_health
	lead_state.busy_until = 0; lead_state.current_reaction = "ENGAGE"
	lead_state.commitment_until = 1000
	world.agent_states[threat_id].busy_until = 0
	var event_start: int = world.events.size()
	var processed_step_index: int = world.step_index + 1
	world.begin_step(processed_step_index)
	var batch_ok := true
	while not world.scheduled_entries.is_empty() \
			and int(world.scheduled_entries[0].due_time) <= 200:
		var entry: Dictionary = world.take_next_schedule()
		world.world_time = int(entry.due_time)
		batch_ok = session.sim._dispatch_schedule(entry, processed_step_index) and batch_ok
		if int(entry.repeat_interval) > 0: world.requeue_repeating(entry)
	world.world_time = 200; world.finish_step()
	check(batch_ok, "Phase3 two-attack batch commits through outer dispatch")
	var events: Array = world.events.slice(event_start)
	var decisions: Array = events.filter(func(event):
		return event.type == "ai.decision_selected")
	var actions: Array = events.filter(func(event):
		return event.type == "action.melee_attack")
	var results: Array = events.filter(func(event):
		return event.type in ["combat.attack_missed", "combat.physical_damage"])
	check_eq(actions.size(), 2, "both Phase3 batch-start ACTIVE attack intents emit")
	check(not decisions.is_empty(), "Phase3 lead decision emitted")
	if not decisions.is_empty() and actions.size() == 2:
		var last_decision_index := -1; var first_action_index := events.size()
		for decision in decisions: last_decision_index = maxi(last_decision_index, events.find(decision))
		for action in actions: first_action_index = mini(first_action_index, events.find(action))
		check(last_decision_index < first_action_index,
			"all Phase3 decisions precede both melee actions")
	if actions.size() == 2 and not results.is_empty():
		var last_action_index := maxi(events.find(actions[0]), events.find(actions[1]))
		var first_result_index := events.size()
		for result in results: first_result_index = mini(first_result_index, events.find(result))
		check(last_action_index < first_result_index,
			"both Phase3 melee actions precede every combat result")
	var exact_action_keys := ["armor_flat", "armor_reduction", "attack_start_world_time",
		"attacker_profile_id", "base_damage", "batch_context", "bleed_chance_milli",
		"bleed_proc_succeeded", "bleed_roll_milli", "combat_ruleset_id",
		"commitment_hash", "final_damage", "frozen_guarded_until",
		"guard_reduction", "guard_source_event_id", "guarded", "hit_chance_milli",
		"hit_roll_milli", "intent_mode", "intent_ordinal", "outcome",
		"processed_step_index", "schema_version", "target_evasion_milli",
		"target_life_at_batch_start", "target_profile_id"]
	for action in actions:
		var action_keys: Array = action.data.keys(); action_keys.sort()
		check_eq(action_keys, exact_action_keys,
			"Phase3 actor %d action has exact canonical v1 keys" % action.actor_id)
		check_eq([action.data.get("schema_version"),
			action.data.get("combat_ruleset_id")],
			[1, "deterministic-melee-resolution-v1"],
			"Phase3 actor %d action uses canonical v1 ruleset" % action.actor_id)
	return finish()

func test_phase3_actor_cadence_commits_keyed_bleed_hit_and_status() -> bool:
	var probe = LabSession.new(1, 125)
	check(probe.advance_ticks(1).ok, "Phase3 BLEED seed probe activates")
	var probe_world = probe.sim.world
	var probe_lead_id: int = probe.lead_roster()[0].entity_id
	var probe_threat_id: int = probe_world.agent_states[probe_lead_id].active_threat_id
	var probe_schedule_id := -1; var attack_time := -1
	for schedule in probe_world.scheduled_entries:
		if schedule.kind == "system.actor_tick" and int(schedule.due_time) == 200:
			probe_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time)
			break
	check(probe_schedule_id > 0, "Phase3 BLEED actor cadence identity found")
	var processed_step: int = probe_world.step_index + 1
	var context := "PHASE3_ACTOR/%d/%d" % [probe_schedule_id, attack_time]
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 0, probe_lead_id, probe_threat_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 950 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") < 600:
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "reachable Phase3 keyed HIT+BLEED seed found")
	if selected_seed < 0: return finish()

	var session = LabSession.new(selected_seed, 125)
	check(session.advance_ticks(1).ok, "Phase3 BLEED fixture activates")
	var world = session.sim.world
	var lead_id: int = session.lead_roster()[0].entity_id
	var lead_state = world.agent_states[lead_id]
	var threat_id: int = lead_state.active_threat_id
	var target_position: Vector2i = world.entities[lead_id].position + Vector2i.RIGHT
	check(_relocate(session.sim, threat_id, target_position),
		"Phase3 BLEED target reaches adjacency through MOVE history")
	for actor_id in world.agent_states:
		world.agent_states[actor_id].busy_until = 0 if actor_id == lead_id else 10000
	lead_state.current_reaction = "ENGAGE"; lead_state.commitment_until = 1000
	world.entities[threat_id].health = world.entities[threat_id].max_health
	processed_step = world.step_index + 1
	var actor_schedule_id := -1
	attack_time = -1
	for schedule in world.scheduled_entries:
		if schedule.kind == "system.actor_tick" and int(schedule.due_time) == 200:
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time)
			break
	context = "PHASE3_ACTOR/%d/%d" % [actor_schedule_id, attack_time]
	var assessment: Dictionary = Melee.new(world, session.sim.damage).assess_attack(
		lead_id, threat_id, "SUGGESTED", processed_step, attack_time, context, 0)
	check(not assessment.is_empty(), "Phase3 BLEED canonical assessment builds")
	if assessment.is_empty(): return finish()
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 0, lead_id, threat_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	check(hit_roll < int(assessment.hit_chance_milli) \
			and bleed_roll < int(assessment.bleed_chance_milli),
		"selected Phase3 commitment succeeds HIT and BLEED")
	var threat_state = world.combatant_states[threat_id]
	var hold = world.event_by_id(threat_state.guard_source_event_id)
	check(hold != null and hold.type == "action.hold" \
			and hold.actor_id == threat_id and hold.world_time + 200 == threat_state.guarded_until,
		"Phase3 BLEED target retains production HOLD guard source")
	check_eq([assessment.base_damage, assessment.target_armor_flat,
		assessment.armor_reduction, assessment.guarded,
		assessment.guard_reduction, assessment.normal_final_damage,
		assessment.frozen_guarded_until, assessment.guard_source_event_id],
		[24, 2, 2, true, 5, 17, str(threat_state.guarded_until),
			str(threat_state.guard_source_event_id)],
		"Phase3 BLEED assessment freezes exact guarded formula/source")
	var hp_before: int = world.entities[threat_id].health
	var rng_before: int = world.rng.state
	var event_start: int = world.events.size()
	world.begin_step(processed_step)
	var batch_ok := true
	while not world.scheduled_entries.is_empty() \
			and int(world.scheduled_entries[0].due_time) <= attack_time:
		var entry: Dictionary = world.take_next_schedule()
		world.world_time = int(entry.due_time)
		batch_ok = session.sim._dispatch_schedule(entry, processed_step) and batch_ok
		if int(entry.repeat_interval) > 0: world.requeue_repeating(entry)
	world.world_time = attack_time
	world.finish_step()
	check(batch_ok, "Phase3 BLEED actor cadence commits")
	var events: Array = world.events.slice(event_start)
	var decisions: Array = events.filter(func(event):
		return event.type == "ai.decision_selected")
	var actions: Array = events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == lead_id \
			and event.target_id == threat_id)
	check_eq(actions.size(), 1, "Phase3 BLEED cadence emits one melee action")
	var action = actions[0] if actions.size() == 1 else null
	var decision = null
	for event in decisions:
		if event.actor_id == lead_id: decision = event; break
	check(decision != null, "Phase3 BLEED lead emits decision trace")
	if action != null and decision != null:
		check_eq([action.step_index, action.world_time, action.actor_id,
			action.target_id, action.position, action.magnitude, action.cause_id,
			action.instigator_id], [processed_step, attack_time, lead_id, threat_id,
			target_position, 24, decision.id, threat_id],
			"Phase3 BLEED action exact canonical envelope/cause")
		check_eq(action.data, _expected_bleed_hit_action_data(
			assessment, key, hit_roll, bleed_roll),
			"Phase3 BLEED action exact canonical v1 data")
	var physicals: Array = events.filter(func(event):
		return action != null and event.type == "combat.physical_damage" \
			and event.cause_id == action.id and event.target_id == threat_id)
	check_eq(physicals.size(), 1, "Phase3 BLEED HIT emits one physical child")
	var physical = physicals[0] if physicals.size() == 1 else null
	if physical != null:
		check_eq([physical.step_index, physical.world_time, physical.actor_id,
			physical.target_id, physical.position, physical.magnitude,
			physical.instigator_id, physical.data], [processed_step, attack_time,
			-1, threat_id, target_position, 17, threat_id, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":17,
				"applied_health_damage":17}],
			"Phase3 BLEED physical exact canonical v1")
		var last_prefix_index := -1
		for event in decisions: last_prefix_index = maxi(last_prefix_index, events.find(event))
		for leaf in events.filter(func(event): return event.type.begins_with("action.")):
			last_prefix_index = maxi(last_prefix_index, events.find(leaf))
		check(last_prefix_index < events.find(physical),
			"all Phase3 decisions/actions precede BLEED result chain")
	var applied_rows: Array = events.filter(func(event):
		return physical != null and event.type == "status.applied" \
			and event.target_id == threat_id and event.cause_id == physical.id)
	check_eq(applied_rows.size(), 1,
		"Phase3 successful proc emits one status.applied")
	var applied = applied_rows[0] if applied_rows.size() == 1 else null
	if physical != null and applied != null:
		check_eq([applied.step_index, applied.world_time, applied.actor_id,
			applied.target_id, applied.position, applied.magnitude,
			applied.cause_id, applied.instigator_id, applied.data],
			[processed_step, attack_time, -1, threat_id, target_position, 0,
				physical.id, threat_id, {"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "next_tick_at":"300",
					"expires_at":"500", "tick_damage":3}],
			"Phase3 BLEED status apply exact canonical v1")
		check_eq(events.find(applied), events.find(physical) + 1,
			"Phase3 BLEED apply immediately follows typed damage")
	check_eq([world.entities[threat_id].health, threat_state.life_state,
		threat_state.status_rows.size()], [hp_before - 17, "ACTIVE", 1],
		"Phase3 BLEED leaves active target with one row")
	if threat_state.status_rows.size() == 1 and applied != null:
		check_eq(threat_state.status_rows[0].to_dict(), {"schema_version":1,
			"status_id":"BLEEDING", "applied_at":"200", "refreshed_at":"200",
			"next_tick_at":"300", "expires_at":"500",
			"source_event_id":str(applied.id)},
			"Phase3 BLEED authoritative row exact")
	check(events.filter(func(event):
		return event.type == "action.melee_attack" \
			and event.data.get("combat_ruleset_id") == "fixed-melee-v1").is_empty(),
		"Phase3 BLEED cadence emits no fixed-melee action")
	check_eq(world.rng.state, rng_before,
		"Phase3 keyed BLEED cadence consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "Phase3 BLEED snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"Phase3 BLEED snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "Phase3 BLEED snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"Phase3 BLEED snapshot roundtrip exact")
	return finish()

func test_phase3_lethal_batch_retains_frozen_attacker_and_downs_instead_of_dies() -> bool:
	var session = LabSession.new(7, 125)
	check(session.advance_ticks(1).ok, "Phase3 lethal retention activation")
	var world = session.sim.world
	var lead_id: int = session.lead_roster()[0].entity_id
	var lead_state = world.agent_states[lead_id]
	var threat_id: int = lead_state.active_threat_id
	var ally_id := -1
	for actor_id in world.agent_states:
		var actor_state = world.agent_states[actor_id]
		if actor_state.trial_slot == 0 and actor_state.controller_kind == "PASSIVE_ALLY":
			ally_id = actor_id
		if actor_state.trial_slot != 0: actor_state.busy_until = 10000
	check(ally_id > 0, "Phase3 lethal retention ally found")
	if ally_id < 0: return finish()
	world.agent_states[ally_id].busy_until = 10000
	world.agent_states[threat_id].busy_until = 0
	var threat_batch_position: Vector2i = world.entities[lead_id].position + Vector2i.RIGHT
	check(_relocate(session.sim, threat_id, threat_batch_position),
		"Phase3 threat reaches lead/ally-adjacent cell through MOVE history")
	world.entities[lead_id].health = 18
	world.entities[ally_id].health = 14
	world.entities[threat_id].health = world.entities[threat_id].max_health
	lead_state.busy_until = 0; lead_state.current_reaction = "ENGAGE"
	lead_state.commitment_until = 1000
	world.agent_states[threat_id].busy_until = 0
	var event_start: int = world.events.size()
	var processed_step_index: int = world.step_index + 1
	var actor_schedule_id := -1
	for schedule in world.scheduled_entries:
		if schedule.kind == "system.actor_tick" and int(schedule.due_time) == 200:
			actor_schedule_id = int(schedule.schedule_id); break
	check(actor_schedule_id > 0, "Phase3 lethal actor cadence identity found")
	var batch_context := "PHASE3_ACTOR/%d/200" % actor_schedule_id
	var threat_guarded_until: int = world.combatant_states[threat_id].guarded_until
	var threat_guard_source: int = world.combatant_states[threat_id].guard_source_event_id
	var threat_hold = world.event_by_id(threat_guard_source)
	check(threat_hold != null and threat_hold.type == "action.hold" \
			and threat_hold.actor_id == threat_id \
			and threat_hold.world_time + 200 == threat_guarded_until,
		"Phase3 threat guard has exact production HOLD provenance")
	var ally_guarded_until: int = world.combatant_states[ally_id].guarded_until
	var ally_guard_source: int = world.combatant_states[ally_id].guard_source_event_id
	var ally_hold = world.event_by_id(ally_guard_source)
	check(ally_hold != null and ally_hold.type == "action.hold" \
			and ally_hold.actor_id == ally_id \
			and ally_hold.world_time + 200 == ally_guarded_until,
		"Phase3 passive ally guard has exact production HOLD provenance")
	var rng_before: int = world.rng.state
	world.begin_step(processed_step_index)
	var batch_ok := true
	while not world.scheduled_entries.is_empty() \
			and int(world.scheduled_entries[0].due_time) <= 200:
		var entry: Dictionary = world.take_next_schedule()
		world.world_time = int(entry.due_time)
		batch_ok = session.sim._dispatch_schedule(entry, processed_step_index) and batch_ok
		if int(entry.repeat_interval) > 0: world.requeue_repeating(entry)
	world.world_time = 200; world.finish_step()
	check(batch_ok, "Phase3 lethal two-attack batch commits")
	var events: Array = world.events.slice(event_start)
	var actions: Array = events.filter(func(event):
		return event.type == "action.melee_attack")
	check_eq(actions.size(), 2,
		"both batch-start ACTIVE Phase3 attack intents emit before lethal resolution")
	for action in actions:
		check_eq([action.data.get("schema_version"),
			action.data.get("combat_ruleset_id")],
			[1, "deterministic-melee-resolution-v1"],
			"Phase3 lethal actor %d action is canonical" % action.actor_id)
	var lead_action = null; var threat_action = null
	for action in actions:
		if action.actor_id == lead_id: lead_action = action
		elif action.actor_id == threat_id: threat_action = action
	check(lead_action != null and threat_action != null,
		"both reciprocal Phase3 frozen actions are retained")
	if lead_action != null and threat_action != null:
		check(events.find(lead_action) < events.find(threat_action),
			"Phase3 actor traversal emits lead action before threat action")
		for action in [threat_action, lead_action]:
			var is_threat: bool = action.actor_id == threat_id
			var ordinal := 0 if is_threat else 1
			var expected_target_id := ally_id if is_threat else threat_id
			var attacker_profile := "phase3-threat-v1" if is_threat else "phase3-lead-v1"
			var target_profile := "phase3-passive-v1" if is_threat else "phase3-threat-v1"
			var target_evasion := 130 if is_threat else 100
			var hit_chance := 920 if is_threat else 950
			var bleed_chance := 300 if is_threat else 600
			var base_damage := 20 if is_threat else 24
			var guarded := true
			var guard_reduction := 4 if is_threat else 5
			var final_damage := 14 if is_threat else 17
			var frozen_guarded_until := ally_guarded_until if is_threat \
				else threat_guarded_until
			var guard_source_event_id := ally_guard_source if is_threat \
				else threat_guard_source
			var key := Melee.commitment_key(7, processed_step_index, 200,
				batch_context, ordinal, action.actor_id, expected_target_id)
			var hit_roll := Melee.lane_roll_milli(key, "HIT")
			var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
			check_eq([ordinal, hit_roll, bleed_roll],
				[0, 86, 985] if is_threat else [1, 709, 837],
				"Phase3 lethal keyed ordinal/roll reference")
			check(hit_roll < hit_chance and bleed_roll >= bleed_chance,
				"Phase3 lethal row is deterministic HIT without BLEED")
			check_eq([action.step_index, action.world_time, action.target_id,
				action.position, action.magnitude, action.instigator_id],
				[processed_step_index, 200, expected_target_id,
					world.entities[expected_target_id].position, base_damage, threat_id],
				"Phase3 lethal actor %d exact action envelope" % action.actor_id)
			check_eq(action.data, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"attacker_profile_id":attacker_profile,
				"target_profile_id":target_profile,
				"batch_context":batch_context, "intent_ordinal":ordinal,
				"intent_mode":"STRIKE", "target_life_at_batch_start":"ACTIVE",
				"outcome":"HIT", "processed_step_index":str(processed_step_index),
				"attack_start_world_time":"200",
				"commitment_hash":Melee.commitment_hash(key),
				"hit_chance_milli":hit_chance, "hit_roll_milli":hit_roll,
				"bleed_chance_milli":bleed_chance, "bleed_roll_milli":bleed_roll,
				"bleed_proc_succeeded":false, "base_damage":base_damage,
				"target_evasion_milli":target_evasion, "armor_flat":2,
				"armor_reduction":2, "frozen_guarded_until":str(frozen_guarded_until),
				"guard_source_event_id":str(guard_source_event_id), "guarded":guarded,
				"guard_reduction":guard_reduction, "final_damage":final_damage},
				"Phase3 lethal actor %d exact canonical v1 data" % action.actor_id)
		check_eq([threat_action.data.intent_ordinal, lead_action.data.intent_ordinal],
			[0, 1], "Phase3 lethal ordinals follow target then attacker sort, not emission")
		var result_drivers: Array = events.filter(func(event):
			return event.type in ["combat.attack_missed", "combat.physical_damage",
				"combat.downed_damage"])
		if not result_drivers.is_empty():
			check(maxi(events.find(lead_action), events.find(threat_action)) \
				< events.find(result_drivers[0]),
				"both Phase3 lethal actions precede every result mutation")
	var downed_events: Array = events.filter(func(event):
		return event.type == "entity.downed" and event.target_id == ally_id)
	var death_events: Array = events.filter(func(event):
		return event.type == "entity.died" and event.target_id == ally_id)
	check_eq(downed_events.size(), 1,
		"lethal threat HIT emits exactly one canonical nonhero entity.downed")
	check_eq(death_events.size(), 0,
		"lethal threat HIT does not immediately kill the passive ally")
	var threat_damage = null; var lead_damage = null
	if threat_action != null and lead_action != null:
		for event in events:
			if event.type != "combat.physical_damage": continue
			if event.cause_id == threat_action.id: threat_damage = event
			elif event.cause_id == lead_action.id: lead_damage = event
	check(threat_damage != null and lead_damage != null,
		"both keyed HIT rows emit exact physical result drivers")
	if threat_damage != null:
		check_eq([threat_damage.step_index, threat_damage.world_time,
			threat_damage.actor_id, threat_damage.target_id, threat_damage.position,
			threat_damage.magnitude, threat_damage.cause_id, threat_damage.instigator_id,
			threat_damage.data], [processed_step_index, 200, -1, ally_id,
			world.entities[ally_id].position, 14, threat_action.id, threat_id,
			{"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":14,
				"applied_health_damage":14}],
			"ordinal-zero threat physical driver exact")
	if lead_damage != null:
		check_eq([lead_damage.step_index, lead_damage.world_time,
			lead_damage.actor_id, lead_damage.target_id, lead_damage.position,
			lead_damage.magnitude, lead_damage.cause_id, lead_damage.instigator_id,
			lead_damage.data], [processed_step_index, 200, -1, threat_id,
			world.entities[threat_id].position, 17, lead_action.id, threat_id,
			{"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":17,
				"applied_health_damage":17}],
			"ordinal-one frozen lead physical driver exact")
	if downed_events.size() == 1 and threat_damage != null:
		var downed = downed_events[0]
		check_eq([downed.step_index, downed.world_time, downed.actor_id,
			downed.target_id, downed.position, downed.magnitude, downed.cause_id,
			downed.instigator_id, downed.data], [processed_step_index, 200, -1,
			ally_id, world.entities[ally_id].position, 0, threat_damage.id, threat_id,
			{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
				"previous_life_state":"ACTIVE", "downed_resolve_at":"400",
				"terminal_immediate":false}],
			"ordinal-zero nonhero DOWNED tail exact")
		if lead_damage != null:
			check(events.find(threat_damage) + 1 == events.find(downed),
				"ordinal-zero damage has immediate lifecycle child")
			check(events.find(downed) < events.find(lead_damage),
				"ordinal-zero lifecycle tail completes before ordinal-one result")
	var ally_combatant = world.combatant_states[ally_id]
	check_eq([world.entities[ally_id].health, ally_combatant.life_state,
		ally_combatant.guarded_until, ally_combatant.guard_source_event_id,
		ally_combatant.downed_at, ally_combatant.downed_resolve_at,
		ally_combatant.downed_source_event_id, ally_combatant.recovery_lock_until,
		ally_combatant.recovery_source_event_id, ally_combatant.status_rows.size()],
		[0, "DOWNED", 0, -1, 200, 400,
			downed_events[0].id if downed_events.size() == 1 else -1, 0, -1, 0],
		"Phase3 passive ally final DOWNED authority exact")
	check_eq(world.entities[threat_id].health,
		world.entities[threat_id].max_health - 17,
		"already-frozen ordinal-one lead HIT mutates threat after ally is DOWNED")
	check_eq(world.rng.state, rng_before,
		"Phase3 lethal keyed batch consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "Phase3 lethal committed snapshot constructs: %s" \
		% world.world_state_error())
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"Phase3 lethal committed snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "Phase3 lethal committed snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"Phase3 lethal committed snapshot roundtrip exact")
	return finish()

func test_phase3_same_target_batch_projects_lethal_then_childless_overkill() -> bool:
	var probe = LabSession.new(1, 125)
	check(probe.advance_ticks(1).ok, "Phase3 same-target seed probe activates")
	var probe_world = probe.sim.world
	var probe_lead_id: int = probe.lead_roster()[0].entity_id
	var probe_threat_id: int = probe_world.agent_states[probe_lead_id].active_threat_id
	var probe_ally_id := -1
	for actor_id in probe_world.agent_states:
		var actor_state = probe_world.agent_states[actor_id]
		if actor_state.trial_slot == 0 and actor_state.controller_kind == "PASSIVE_ALLY":
			probe_ally_id = actor_id
	check(probe_threat_id > 0 and probe_ally_id > 0,
		"Phase3 same-target attackers found")
	if probe_threat_id <= 0 or probe_ally_id <= 0: return finish()
	var probe_schedule_id := -1
	var probe_due_time := -1
	for schedule in probe_world.scheduled_entries:
		if schedule.kind == "system.actor_tick" and int(schedule.due_time) == 200:
			probe_schedule_id = int(schedule.schedule_id)
			probe_due_time = int(schedule.due_time)
			break
	check(probe_schedule_id > 0, "Phase3 same-target actor cadence found")
	if probe_schedule_id <= 0: return finish()
	var first_attacker_id := mini(probe_threat_id, probe_ally_id)
	var attacker_profile := Profiles.profile(
		probe_world.combatant_states[first_attacker_id].combat_profile_id)
	var target_profile := Profiles.profile(
		probe_world.combatant_states[probe_lead_id].combat_profile_id)
	var hit_chance := clampi(500 + int(attacker_profile.accuracy_milli) \
		- int(target_profile.evasion_milli), 50, 950)
	var bleed_chance := clampi(int(attacker_profile.bleed_proc_milli) \
		- int(target_profile.bleed_resist_milli), 0, 1000)
	var probe_processed_step: int = probe_world.step_index + 1
	var probe_context := "PHASE3_ACTOR/%d/%d" % [probe_schedule_id, probe_due_time]
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed,
			probe_processed_step, probe_due_time, probe_context, 0,
			first_attacker_id, probe_lead_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < hit_chance \
				and Melee.lane_roll_milli(candidate_key, "BLEED") >= bleed_chance:
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "Phase3 same-target HIT/no-BLEED seed found")
	if selected_seed <= 0: return finish()

	var session = LabSession.new(selected_seed, 125)
	check(session.advance_ticks(1).ok, "Phase3 same-target fixture activates")
	var world = session.sim.world
	var lead_id: int = session.lead_roster()[0].entity_id
	var threat_id: int = world.agent_states[lead_id].active_threat_id
	var ally_id := -1
	for actor_id in world.agent_states:
		var actor_state = world.agent_states[actor_id]
		if actor_state.trial_slot == 0 and actor_state.controller_kind == "PASSIVE_ALLY":
			ally_id = actor_id
		if actor_state.trial_slot != 0:
			actor_state.busy_until = 10000
	check(threat_id > 0 and ally_id > 0, "Phase3 same-target fixture actors found")
	if threat_id <= 0 or ally_id <= 0: return finish()
	world.agent_states[ally_id].controller_kind = "MELEE_THREAT"
	world.agent_states[threat_id].busy_until = 0
	world.agent_states[ally_id].busy_until = 0
	world.agent_states[lead_id].busy_until = 10000
	world.entities[threat_id].position = world.entities[lead_id].position + Vector2i.RIGHT
	world.entities[ally_id].position = world.entities[lead_id].position + Vector2i.DOWN
	world.entities[lead_id].health = 1
	var event_start: int = world.events.size()
	var processed_step: int = world.step_index + 1
	world.begin_step(processed_step)
	var batch_ok := true
	while not world.scheduled_entries.is_empty() \
			and int(world.scheduled_entries[0].due_time) <= 200:
		var entry: Dictionary = world.take_next_schedule()
		world.world_time = int(entry.due_time)
		batch_ok = session.sim._dispatch_schedule(entry, processed_step) and batch_ok
		if int(entry.repeat_interval) > 0: world.requeue_repeating(entry)
	world.world_time = 200
	world.finish_step()
	check(batch_ok, "Phase3 same-target actor batch commits")
	var events: Array = world.events.slice(event_start)
	var actions: Array = events.filter(func(event):
		return event.type == "action.melee_attack" and event.target_id == lead_id \
			and event.actor_id in [threat_id, ally_id])
	check_eq(actions.size(), 2, "both same-target frozen actions emit")
	var first_action = null
	var second_action = null
	for action in actions:
		if action.actor_id == mini(threat_id, ally_id): first_action = action
		else: second_action = action
	check(first_action != null and second_action != null,
		"same-target actions retain canonical actor ordinal order")
	if first_action != null and second_action != null:
		check_eq([first_action.data.get("combat_ruleset_id"),
			first_action.data.get("intent_ordinal"), first_action.data.get("outcome"),
			second_action.data.get("combat_ruleset_id"),
			second_action.data.get("intent_ordinal"), second_action.data.get("outcome")],
			["deterministic-melee-resolution-v1", 0, "HIT",
				"deterministic-melee-resolution-v1", 1, "OVERKILL_SKIP"],
			"same-target batch emits lethal HIT then projected OVERKILL_SKIP")
		var first_children: Array = events.filter(func(event):
			return event.cause_id == first_action.id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		var second_children: Array = events.filter(func(event):
			return event.cause_id == second_action.id and event.type in [
				"combat.attack_missed", "combat.physical_damage", "combat.downed_damage"])
		check_eq([first_children.size(), second_children.size()], [1, 0],
			"lethal HIT owns one result and OVERKILL_SKIP is childless")
		if not first_children.is_empty():
			check(maxi(events.find(first_action), events.find(second_action)) \
				< events.find(first_children[0]),
				"same-target batch preserves all-actions-first result order")
	var downed_events: Array = events.filter(func(event):
		return event.type == "entity.downed" and event.target_id == lead_id)
	var death_events: Array = events.filter(func(event):
		return event.type == "entity.died" and event.target_id == lead_id)
	check_eq([world.entities[lead_id].health,
		world.combatant_states[lead_id].life_state,
		downed_events.size(), death_events.size()], [0, "DOWNED", 1, 0],
		"first same-target lethal HIT transitions target to DOWNED only")

	var next_event_start: int = world.events.size()
	var next_processed_step: int = world.step_index + 1
	world.begin_step(next_processed_step)
	var next_ok := true
	while not world.scheduled_entries.is_empty() \
			and int(world.scheduled_entries[0].due_time) <= 300:
		var entry: Dictionary = world.take_next_schedule()
		world.world_time = int(entry.due_time)
		next_ok = session.sim._dispatch_schedule(entry, next_processed_step) and next_ok
		if int(entry.repeat_interval) > 0: world.requeue_repeating(entry)
	world.world_time = 300
	world.finish_step()
	check(next_ok, "post-DOWNED actor cadence commits")
	var next_events: Array = world.events.slice(next_event_start)
	check(next_events.filter(func(event):
		return event.actor_id == lead_id and event.type.begins_with("action.")).is_empty(),
		"DOWNED actor is excluded from the next autonomous cadence")
	check(next_events.filter(func(event):
		return event.type == "action.melee_attack" and event.target_id == lead_id).is_empty(),
		"DOWNED target is excluded from the next autonomous cadence")
	return finish()

func test_enemy_hold_updates_guard_and_source_through_production_contact_path() -> bool:
	var session = Session.new(55, 66); var world = session.sim.world; var state = world.party_encounter
	state.party_detection_radius = 3; state.enemy_detection_radius = 4
	var result = session.sim.step(Command.wait(state.protagonist_id))
	check(result.accepted, "enemy-ambush contact operation accepted")
	check_eq(state.contact_kind, "ENEMY_AMBUSH", "fixture enters enemy ambush")
	var enemy_id: int = state.enemy_ids[0]
	var holds: Array = result.events.filter(func(event):
		return event.type == "action.hold" and event.actor_id == enemy_id)
	check_eq(holds.size(), 1, "non-adjacent ambusher commits HOLD")
	if holds.size() == 1:
		var combatant = world.combatant_states[enemy_id]
		check_eq(combatant.guarded_until, holds[0].world_time + 200, "enemy HOLD writes guard expiry")
		check_eq(combatant.guard_source_event_id, holds[0].id, "enemy HOLD writes source")
	return finish()

func test_enemy_ambush_contact_commits_exact_keyed_no_bleed_melee() -> bool:
	var probe = Session.new(1, 20260828)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var enemy_id: int = probe_state.enemy_ids[0]
	probe_state.party_detection_radius = 0
	probe_state.enemy_detection_radius = 3
	probe_world.entities[enemy_id].position = probe_world.entities[hero_id].position + Vector2i.RIGHT
	var processed_step: int = probe_world.step_index + 1
	var actor_schedule_id: int = -1; var attack_time: int = -1
	for schedule in probe_world.scheduled_entries:
		if str(schedule.kind) == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time); break
	var context := "PARTY_AMBUSH/%d/%d" % [actor_schedule_id, attack_time]
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 0, enemy_id, hero_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 900 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") >= 300:
			selected_seed = candidate_seed; break
	check(selected_seed > 0, "enemy-ambush keyed HIT/no-BLEED seed found")
	if selected_seed < 0: return finish()

	var session = Session.new(selected_seed, 20260828)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; enemy_id = state.enemy_ids[0]
	state.party_detection_radius = 0; state.enemy_detection_radius = 3
	var hero_position: Vector2i = world.entities[hero_id].position
	var enemy_position: Vector2i = hero_position + Vector2i.RIGHT
	world.entities[enemy_id].position = enemy_position
	processed_step = world.step_index + 1
	actor_schedule_id = -1; attack_time = -1
	for schedule in world.scheduled_entries:
		if str(schedule.kind) == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time); break
	context = "PARTY_AMBUSH/%d/%d" % [actor_schedule_id, attack_time]
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 0, enemy_id, hero_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	var hp_before: int = world.entities[hero_id].health
	var result = session.sim.step(Command.wait(hero_id))
	check(result.accepted, "adjacent ENEMY_AMBUSH generic outer step accepted")
	check_eq([result.processed_step_index, state.safe_phase, state.contact_kind,
		state.contact_enemy_id], [processed_step, "CONTACT", "ENEMY_AMBUSH", enemy_id],
		"enemy ambush publishes exact contact state")
	var contacts: Array = result.events.filter(func(event):
		return event.type == "encounter.enemy_ambush")
	check_eq(contacts.size(), 1, "enemy ambush emits one contact root")
	var contact = contacts[0] if contacts.size() == 1 else null
	if contact != null:
		check_eq([contact.step_index, contact.world_time, contact.actor_id,
			contact.target_id, contact.position, contact.magnitude, contact.cause_id,
			contact.instigator_id, contact.data], [processed_step, attack_time,
			enemy_id, hero_id, hero_position, 0, -1, enemy_id,
			{"contact_kind":"ENEMY_AMBUSH", "enemy_id":str(enemy_id),
				"enemy_position":[enemy_position.x, enemy_position.y],
				"facing":[1, 0]}], "ENEMY_AMBUSH contact exact envelope/data")
	var actions: Array = result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == enemy_id \
			and event.target_id == hero_id)
	check_eq(actions.size(), 1, "adjacent ambusher emits one melee action")
	var action = actions[0] if actions.size() == 1 else null
	if action != null and contact != null:
		check_eq([action.step_index, action.world_time, action.actor_id,
			action.target_id, action.position, action.magnitude, action.cause_id,
			action.instigator_id], [processed_step, attack_time, enemy_id, hero_id,
			hero_position, 16, contact.id, enemy_id],
			"ENEMY_AMBUSH melee exact canonical envelope/cause")
		check_eq(action.data, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-goblin-v1",
			"target_profile_id":"party-hero-v1", "batch_context":context,
			"intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":900, "hit_roll_milli":hit_roll,
			"bleed_chance_milli":300, "bleed_roll_milli":bleed_roll,
			"bleed_proc_succeeded":false, "base_damage":16,
			"target_evasion_milli":150, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":14},
			"ENEMY_AMBUSH exact keyed HIT/no-BLEED action data")
	var children: Array = result.events.filter(func(event):
		return action != null and event.cause_id == action.id \
			and event.type in ["combat.attack_missed", "combat.physical_damage"])
	check_eq(children.size(), 1, "ambush HIT emits exactly one direct combat child")
	if children.size() == 1:
		var child = children[0]
		check_eq([child.type, child.step_index, child.world_time, child.actor_id,
			child.target_id, child.position, child.magnitude, child.instigator_id,
			child.data], ["combat.physical_damage", processed_step, attack_time,
			-1, hero_id, hero_position, 14, enemy_id,
			{"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":14,
				"applied_health_damage":14}],
			"ENEMY_AMBUSH exact physical child")
		if action != null:
			check_eq(result.events.find(child), result.events.find(action) + 1,
				"single ambush action precedes its immediate result")
	var all_actions: Array = result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id in state.enemy_ids)
	var all_results: Array = result.events.filter(func(event):
		return event.type in ["combat.attack_missed", "combat.physical_damage"] \
			and event.instigator_id in state.enemy_ids)
	if not all_actions.is_empty() and not all_results.is_empty():
		check(result.events.find(all_actions.back()) < result.events.find(all_results[0]),
			"all ambush actions precede every keyed result")
	check_eq(world.entities[hero_id].health, hp_before - 14,
		"ENEMY_AMBUSH exact keyed damage applied")
	check(result.events.filter(func(event):
		return event.type in ["status.applied", "status.refreshed"] \
			and event.target_id == hero_id).is_empty(),
		"no-BLEED ambush emits no status child")

	var control = Session.new(selected_seed, 20260828)
	var control_state = control.sim.world.party_encounter
	control_state.party_detection_radius = 3
	control_state.enemy_detection_radius = 4
	var control_result = control.sim.step(Command.wait(control_state.protagonist_id))
	check(control_result.accepted and control_state.contact_kind == "ENEMY_AMBUSH",
		"same-seed nonadjacent HOLD cadence control accepted")
	check_eq(control.sim.world.rng.state, world.rng.state,
		"keyed ENEMY_AMBUSH consumes no RNG beyond same cadence HOLD control")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "ENEMY_AMBUSH keyed snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"ENEMY_AMBUSH keyed snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "ENEMY_AMBUSH keyed snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"ENEMY_AMBUSH keyed snapshot roundtrip exact")
	return finish()

func test_enemy_ambush_contact_commits_keyed_bleed_hit_and_status() -> bool:
	var probe = Session.new(1, 20260828)
	var probe_world = probe.sim.world; var probe_state = probe_world.party_encounter
	var hero_id: int = probe_state.protagonist_id
	var enemy_id: int = probe_state.enemy_ids[0]
	probe_state.party_detection_radius = 0; probe_state.enemy_detection_radius = 3
	probe_world.entities[enemy_id].position = \
		probe_world.entities[hero_id].position + Vector2i.RIGHT
	var processed_step: int = probe_world.step_index + 1
	var actor_schedule_id := -1; var attack_time := -1
	for schedule in probe_world.scheduled_entries:
		if str(schedule.kind) == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time)
			break
	var context := "PARTY_AMBUSH/%d/%d" % [actor_schedule_id, attack_time]
	var selected_seed := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 0, enemy_id, hero_id)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 900 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") < 300:
			selected_seed = candidate_seed
			break
	check(selected_seed > 0, "reachable ENEMY_AMBUSH keyed HIT+BLEED seed found")
	if selected_seed < 0: return finish()

	var session = Session.new(selected_seed, 20260828)
	var world = session.sim.world; var state = world.party_encounter
	hero_id = state.protagonist_id; enemy_id = state.enemy_ids[0]
	state.party_detection_radius = 0; state.enemy_detection_radius = 3
	var hero_position: Vector2i = world.entities[hero_id].position
	world.entities[enemy_id].position = hero_position + Vector2i.RIGHT
	processed_step = world.step_index + 1
	actor_schedule_id = -1; attack_time = -1
	for schedule in world.scheduled_entries:
		if str(schedule.kind) == "system.actor_tick":
			actor_schedule_id = int(schedule.schedule_id)
			attack_time = int(schedule.due_time)
			break
	context = "PARTY_AMBUSH/%d/%d" % [actor_schedule_id, attack_time]
	var key := Melee.commitment_key(world.seed, processed_step, attack_time,
		context, 0, enemy_id, hero_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	check(hit_roll < 900 and bleed_roll < 300,
		"selected ENEMY_AMBUSH key succeeds HIT and BLEED")
	var hp_before: int = world.entities[hero_id].health
	var rng_before: int = world.rng.state
	var result = session.sim.step(Command.wait(hero_id))
	check(result.accepted, "BLEED ENEMY_AMBUSH outer step accepted")
	var contacts: Array = result.events.filter(func(event):
		return event.type == "encounter.enemy_ambush")
	check_eq(contacts.size(), 1, "BLEED ENEMY_AMBUSH emits exact contact root")
	var contact = contacts[0] if contacts.size() == 1 else null
	var actions: Array = result.events.filter(func(event):
		return event.type == "action.melee_attack" and event.actor_id == enemy_id \
			and event.target_id == hero_id)
	check_eq(actions.size(), 1, "BLEED ambusher emits one melee action")
	var action = actions[0] if actions.size() == 1 else null
	if action != null and contact != null:
		check_eq([action.step_index, action.world_time, action.position,
			action.magnitude, action.cause_id, action.instigator_id],
			[processed_step, attack_time, hero_position, 16, contact.id, enemy_id],
			"BLEED ENEMY_AMBUSH action exact envelope")
		check_eq(action.data, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-goblin-v1",
			"target_profile_id":"party-hero-v1", "batch_context":context,
			"intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":900, "hit_roll_milli":hit_roll,
			"bleed_chance_milli":300, "bleed_roll_milli":bleed_roll,
			"bleed_proc_succeeded":true, "base_damage":16,
			"target_evasion_milli":150, "armor_flat":2, "armor_reduction":2,
			"frozen_guarded_until":"0", "guard_source_event_id":"-1",
			"guarded":false, "guard_reduction":0, "final_damage":14},
			"BLEED ENEMY_AMBUSH action exact canonical v1 data")
	var physicals: Array = result.events.filter(func(event):
		return action != null and event.type == "combat.physical_damage" \
			and event.cause_id == action.id and event.target_id == hero_id)
	check_eq(physicals.size(), 1, "BLEED ambush emits one physical result")
	var physical = physicals[0] if physicals.size() == 1 else null
	if physical != null:
		check_eq([physical.step_index, physical.world_time, physical.actor_id,
			physical.position, physical.magnitude, physical.instigator_id,
			physical.data], [processed_step, attack_time, -1, hero_position, 14,
			enemy_id, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":14,
				"applied_health_damage":14}],
			"BLEED ENEMY_AMBUSH physical exact canonical v1")
		var last_leaf_index := -1
		for index in range(result.events.size()):
			var event = result.events[index]
			if event.world_time == attack_time and event.actor_id in state.enemy_ids \
					and event.type.begins_with("action."):
				last_leaf_index = maxi(last_leaf_index, index)
		check(last_leaf_index < result.events.find(physical),
			"all ENEMY_AMBUSH action leaves precede BLEED result chain")
	var applied_rows: Array = result.events.filter(func(event):
		return physical != null and event.type == "status.applied" \
			and event.target_id == hero_id and event.cause_id == physical.id)
	check_eq(applied_rows.size(), 1, "BLEED ambush emits one status.applied child")
	var applied = applied_rows[0] if applied_rows.size() == 1 else null
	if physical != null and applied != null:
		check_eq([applied.step_index, applied.world_time, applied.actor_id,
			applied.position, applied.magnitude, applied.instigator_id, applied.data],
			[processed_step, attack_time, -1, hero_position, 0, enemy_id,
				{"schema_version":1,
					"status_ruleset_id":"bounded-status-lifecycle-v1",
					"status_id":"BLEEDING", "next_tick_at":"200",
					"expires_at":"400", "tick_damage":3}],
			"BLEED ENEMY_AMBUSH status apply exact canonical v1")
		check_eq(result.events.find(applied), result.events.find(physical) + 1,
			"BLEED status apply immediately follows typed damage")
	check_eq(world.entities[hero_id].health, hp_before - 14,
		"BLEED ambush applies exact health damage")
	var status_rows: Array = world.combatant_states[hero_id].status_rows
	check_eq(status_rows.size(), 1, "BLEED ambush creates one status row")
	if status_rows.size() == 1 and applied != null:
		check_eq(status_rows[0].to_dict(), {"schema_version":1,
			"status_id":"BLEEDING", "applied_at":"100", "refreshed_at":"100",
			"next_tick_at":"200", "expires_at":"400",
			"source_event_id":str(applied.id)},
			"BLEED ENEMY_AMBUSH status row exact")
	check_eq(world.rng.state, rng_before,
		"BLEED ENEMY_AMBUSH keyed commit consumes no global RNG")
	var canonical = session.sim.snapshot()
	check(canonical is Dictionary, "BLEED ENEMY_AMBUSH snapshot constructs")
	if canonical is Dictionary:
		check_eq(WorldState.snapshot_restore_error(canonical), "",
			"BLEED ENEMY_AMBUSH snapshot restores")
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "BLEED ENEMY_AMBUSH snapshot loads")
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"BLEED ENEMY_AMBUSH snapshot roundtrip exact")
	return finish()

func test_combat_assessment_exact_wire_preview_purity_and_every_field_tamper_noop() -> bool:
	var session = _engaged_adjacent(); var world = session.sim.world; var state = world.party_encounter
	var hero_id: int = state.protagonist_id; var enemy_id: int = state.enemy_ids[0]
	var request = Request.new(Action.melee(hero_id, enemy_id), [])
	var baseline: Dictionary = session.sim.snapshot()
	var plan = session.sim.preview_party_turn(request); var wire: Dictionary = plan.to_dict()
	var row: Dictionary = wire.actor_rows[0]; var assessment: Dictionary = row.combat_assessment
	var expected := {"schema_version":1, "attacker_id":str(hero_id), "target_id":str(enemy_id),
		"attacker_position":[world.entities[hero_id].position.x, world.entities[hero_id].position.y],
		"target_position":[world.entities[enemy_id].position.x, world.entities[enemy_id].position.y],
		"attacker_life_state":"ACTIVE", "target_life_state":"ACTIVE",
		"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
		"target_evasion_milli":100, "target_armor_flat":2, "frozen_guarded_until":"0",
		"guard_source_event_id":"-1", "source":"DIRECT", "processed_step_index":"3",
		"attack_start_world_time":str(world.world_time), "batch_context":"PARTY_TURN/3",
		"intent_ordinal":0, "intent_mode":"STRIKE", "hit_chance_milli":950,
		"bleed_chance_milli":600, "base_damage":24, "armor_reduction":2,
		"guarded":false, "guard_reduction":0, "normal_final_damage":22,
		"commitment_hash":Melee.commitment_hash(Melee.commitment_key(
			world.seed, 3, world.world_time, "PARTY_TURN/3", 0, hero_id, enemy_id))}
	check_eq(assessment, expected, "exact public assessment")
	var actual_keys: Array = assessment.keys(); actual_keys.sort()
	var expected_keys: Array = Plan.ASSESSMENT_KEYS.duplicate(); expected_keys.sort()
	check_eq(actual_keys, expected_keys, "assessment exact key set")
	for forbidden in ["hit_roll_milli", "bleed_roll_milli", "hit_hash", "bleed_hash",
			"commitment_key", "outcome"]:
		check(not assessment.has(forbidden), "preview forbids %s" % forbidden)
	for repeat_index in range(100):
		check_eq(session.sim.preview_party_turn(request).to_dict(), wire,
			"preview %d deterministic" % repeat_index)
	check_eq(session.sim.snapshot(), baseline, "100 previews preserve full snapshot")

	for field in Plan.ASSESSMENT_KEYS:
		var forged: Dictionary = wire.duplicate(true)
		forged.actor_rows[0].combat_assessment[field] = _different_assessment_value(
			field, forged.actor_rows[0].combat_assessment[field])
		_check_tampered_party_plan_noop(session, forged, "assessment field %s" % field)
	for field in Plan.ASSESSMENT_KEYS:
		var missing: Dictionary = wire.duplicate(true)
		missing.actor_rows[0].combat_assessment.erase(field)
		_check_tampered_party_plan_noop(session, missing, "missing assessment field %s" % field)
	for forbidden in ["hit_roll_milli", "bleed_roll_milli", "hit_hash", "bleed_hash",
			"commitment_key", "outcome", "extra"]:
		var extra: Dictionary = wire.duplicate(true)
		extra.actor_rows[0].combat_assessment[forbidden] = 7
		_check_tampered_party_plan_noop(session, extra, "forbidden assessment field %s" % forbidden)
	return finish()

func _different_assessment_value(field: String, value: Variant) -> Variant:
	match field:
		"schema_version": return 2
		"attacker_id", "target_id": return "999"
		"attacker_position", "target_position": return [int(value[0]) + 1, int(value[1])]
		"attacker_life_state": return "DOWNED"
		"target_life_state": return "DOWNED" if value == "ACTIVE" else "ACTIVE"
		"attacker_profile_id": return "party-companion-v1"
		"target_profile_id": return "combatant-default-v1"
		"frozen_guarded_until": return "1"
		"guard_source_event_id": return "1"
		"source": return "SUGGESTED" if value != "SUGGESTED" else "OVERRIDE"
		"processed_step_index": return "4"
		"attack_start_world_time": return str(int(value) + 1)
		"batch_context": return "PARTY_TURN/4"
		"intent_mode": return "FINISHER" if value == "STRIKE" else "STRIKE"
		"guarded": return not bool(value)
		"commitment_hash": return "0".repeat(64)
		_: return int(value) + 1

func _check_tampered_party_plan_noop(session, forged: Dictionary, label: String) -> void:
	var before: Dictionary = session.sim.snapshot()
	forged.plan_hash = Plan.canonical_hash(forged)
	var result = session.sim.step_party_turn(Plan.new(forged))
	check(not result.accepted, "%s rejected" % label)
	check_eq(result.reason, "stale_or_tampered_combat_plan", "%s reason" % label)
	check_eq(session.sim.snapshot(), before, "%s exact no-op" % label)

func test_snapshot_combatant_wire_profile_order_sentinel_and_overdue_forge_matrix() -> bool:
	var sim = Simulator.new(3, 2, 71)
	sim.world.add_entity("hero", "Hero", Vector2i.ZERO)
	sim.world.add_entity("melee_enemy", "Enemy", Vector2i.RIGHT)
	var base: Dictionary = sim.snapshot()
	check_eq(WorldState.snapshot_restore_error(base), "", "active baseline restores")
	var cases: Array = []
	var unsorted := base.duplicate(true); unsorted.combatant_states.reverse()
	cases.append(["combatant sort", unsorted])
	var duplicate := base.duplicate(true); duplicate.combatant_states[1] = duplicate.combatant_states[0].duplicate(true)
	cases.append(["combatant duplicate", duplicate])
	var missing_row := base.duplicate(true); missing_row.combatant_states.pop_back()
	cases.append(["combatant missing", missing_row])
	var extra_key := base.duplicate(true); extra_key.combatant_states[0]["extra"] = 1
	cases.append(["combatant extra key", extra_key])
	var missing_key := base.duplicate(true); missing_key.combatant_states[0].erase("guarded_until")
	cases.append(["combatant missing key", missing_key])
	var kind_profile := base.duplicate(true); kind_profile.combatant_states[0].combat_profile_id = "party-companion-v1"
	cases.append(["kind profile mismatch", kind_profile])
	var unknown_profile := base.duplicate(true); unknown_profile.combatant_states[0].combat_profile_id = "missing"
	cases.append(["unknown profile", unknown_profile])
	var active_zero := base.duplicate(true); active_zero.entities[0].health = 0
	cases.append(["ACTIVE health zero", active_zero])
	var active_down := base.duplicate(true); active_down.combatant_states[0].downed_at = "0"
	cases.append(["ACTIVE down sentinel", active_down])
	var guard_pair := base.duplicate(true); guard_pair.combatant_states[0].guarded_until = "200"
	cases.append(["guard sentinel pair", guard_pair])
	var recovery_pair := base.duplicate(true); recovery_pair.combatant_states[0].recovery_lock_until = "100"
	cases.append(["recovery sentinel pair", recovery_pair])
	for pair in cases:
		check(not WorldState.snapshot_restore_error(pair[1]).is_empty(), "%s rejected" % pair[0])

	var dead_sim = Simulator.new(2, 1, 72)
	var corpse = dead_sim.world.add_entity("other", "Corpse", Vector2i.ZERO)
	check(dead_sim.world.bootstrap_set_combatant_life_state(corpse.id, "DEAD"), "pristine DEAD bootstrap")
	var dead: Dictionary = dead_sim.snapshot()
	check_eq(WorldState.snapshot_restore_error(dead), "", "DEAD baseline restores")
	for mutation in ["health", "guard", "downed", "recovery", "status"]:
		var forged := dead.duplicate(true)
		match mutation:
			"health": forged.entities[0].health = 1
			"guard": forged.combatant_states[0].guarded_until = "200"; forged.combatant_states[0].guard_source_event_id = "1"
			"downed": forged.combatant_states[0].downed_at = "0"; forged.combatant_states[0].downed_resolve_at = "200"; forged.combatant_states[0].downed_source_event_id = "1"
			"recovery": forged.combatant_states[0].recovery_lock_until = "100"; forged.combatant_states[0].recovery_source_event_id = "1"
			"status": forged.combatant_states[0].status_rows = [{"schema_version":1,
				"status_id":"BLEEDING", "applied_at":"0", "refreshed_at":"0",
				"next_tick_at":"100", "expires_at":"300", "source_event_id":"1"}]
		check(not WorldState.snapshot_restore_error(forged).is_empty(), "DEAD %s sentinel rejected" % mutation)

	var fresh: Dictionary = _bleed_fixture(0, false)
	if not fresh.is_empty():
		var duplicate_status := fresh.duplicate(true)
		duplicate_status.combatant_states[1].status_rows.append(
			duplicate_status.combatant_states[1].status_rows[0].duplicate(true))
		check(not WorldState.snapshot_restore_error(duplicate_status).is_empty(), "duplicate status rejected")
		var overdue := fresh.duplicate(true); overdue.world_time = "100"
		for schedule in overdue.scheduled_entries: schedule.due_time = "200"
		check(not WorldState.snapshot_restore_error(overdue).is_empty(), "settled overdue status rejected")
	return finish()

func test_guard_and_recovery_source_sentinel_pair_matrix() -> bool:
	var sim = Simulator.new(2, 1, 73)
	sim.world.add_entity("other", "Sentinel", Vector2i.ZERO)
	var baseline: Dictionary = sim.snapshot()
	check_eq(WorldState.snapshot_restore_error(baseline), "", "source sentinel baseline restores")
	var cases: Array = []
	var guard_negative := baseline.duplicate(true)
	guard_negative.combatant_states[0].guarded_until = "0"
	guard_negative.combatant_states[0].guard_source_event_id = "-2"
	cases.append(["guard time zero source negative two", guard_negative])
	var recovery_negative := baseline.duplicate(true)
	recovery_negative.combatant_states[0].recovery_lock_until = "0"
	recovery_negative.combatant_states[0].recovery_source_event_id = "-2"
	cases.append(["recovery time zero source negative two", recovery_negative])
	var guard_zero_id := baseline.duplicate(true)
	guard_zero_id.combatant_states[0].guarded_until = "100"
	guard_zero_id.combatant_states[0].guard_source_event_id = "0"
	cases.append(["guard positive time source zero", guard_zero_id])
	var recovery_zero_id := baseline.duplicate(true)
	recovery_zero_id.combatant_states[0].recovery_lock_until = "100"
	recovery_zero_id.combatant_states[0].recovery_source_event_id = "0"
	cases.append(["recovery positive time source zero", recovery_zero_id])
	var guard_negative_id := baseline.duplicate(true)
	guard_negative_id.combatant_states[0].guarded_until = "100"
	guard_negative_id.combatant_states[0].guard_source_event_id = "-2"
	cases.append(["guard positive time source negative two", guard_negative_id])
	var recovery_negative_id := baseline.duplicate(true)
	recovery_negative_id.combatant_states[0].recovery_lock_until = "100"
	recovery_negative_id.combatant_states[0].recovery_source_event_id = "-2"
	cases.append(["recovery positive time source negative two", recovery_negative_id])
	var accepted: Array = []
	for pair in cases:
		if WorldState.snapshot_restore_error(pair[1]).is_empty(): accepted.append(pair[0])
	check(accepted.is_empty(), "accepted source sentinel pairs: %s" % [accepted])
	for pair in cases:
		check(not WorldState.snapshot_restore_error(pair[1]).is_empty(), "%s rejected" % pair[0])
	return finish()

func test_canonical_melee_frozen_guard_sentinel_and_batch_start_history() -> bool:
	var canonical: Dictionary = _canonical_guarded_hit_fixture()
	check(not canonical.is_empty(), "canonical frozen-guard HIT fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"canonical frozen-guard HIT restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical frozen-guard HIT constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"canonical frozen-guard HIT roundtrip exact")
	var mutations := ["zero_until_zero_source", "zero_until_negative_two_source",
		"positive_until_zero_source", "positive_until_negative_two_source",
		"older_hold_source"]
	var results: Array = []; var accepted: Array = []
	for mutation in mutations:
		var forged: Dictionary = _canonical_guarded_hit_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted frozen-guard forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "frozen guard %s forge rejected" % result[0])
	return finish()

func _canonical_guarded_hit_fixture() -> Dictionary:
	var seed_value := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, 3, 100,
			"PARTY_TURN/3", 0, 1, 2)
		if Melee.lane_roll_milli(candidate_key, "HIT") < 950 \
				and Melee.lane_roll_milli(candidate_key, "BLEED") >= 600:
			seed_value = candidate_seed
			break
	if seed_value < 0: return {}
	var sim = Simulator.new(2, 1, seed_value)
	var attacker = sim.world.add_entity("hero", "Guard Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Guard Target", Vector2i.RIGHT)
	if attacker == null or target == null or not _begin_fixture_step(sim.world, 0): return {}
	var target_state = sim.world.combatant_states[target.id]
	var older_hold = sim.world.emit_event("action.hold", target.id, -1,
		target.position, 100)
	if older_hold == null: return {}
	target_state.guarded_until = 200; target_state.guard_source_event_id = older_hold.id
	sim.world.finish_step()
	if not _begin_fixture_step(sim.world, 50): return {}
	var current_hold = sim.world.emit_event("action.hold", target.id, -1,
		target.position, 100)
	if current_hold == null: return {}
	target_state.guarded_until = 250; target_state.guard_source_event_id = current_hold.id
	sim.world.finish_step()
	if not _begin_fixture_step(sim.world, 100): return {}
	var key := Melee.commitment_key(seed_value, 3, 100, "PARTY_TURN/3", 0,
		attacker.id, target.id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	var action = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
			"batch_context":"PARTY_TURN/3", "intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":"HIT",
			"processed_step_index":"3", "attack_start_world_time":"100",
			"commitment_hash":Melee.commitment_hash(key), "hit_chance_milli":950,
			"hit_roll_milli":hit_roll, "bleed_chance_milli":600,
			"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":false,
			"base_damage":24, "target_evasion_milli":100, "armor_flat":2,
			"armor_reduction":2, "frozen_guarded_until":"250",
			"guard_source_event_id":str(current_hold.id), "guarded":true,
			"guard_reduction":5, "final_damage":17})
	if action == null: return {}
	var damage = sim.world.emit_event("combat.physical_damage", -1, target.id,
		target.position, 17, action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":17,
			"applied_health_damage":17})
	if damage == null: return {}
	target.health = 83
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _canonical_guarded_hit_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action: Dictionary = {}
	for event in forged.events:
		if event.type == "action.melee_attack":
			action = event
			break
	if action.is_empty(): return {}
	match mutation:
		"zero_until_zero_source":
			action.data.frozen_guarded_until = "0"
			action.data.guard_source_event_id = "0"
		"zero_until_negative_two_source":
			action.data.frozen_guarded_until = "0"
			action.data.guard_source_event_id = "-2"
		"positive_until_zero_source":
			action.data.guard_source_event_id = "0"
		"positive_until_negative_two_source":
			action.data.guard_source_event_id = "-2"
		"older_hold_source":
			action.data.frozen_guarded_until = "200"
			action.data.guard_source_event_id = "1"
	return forged

func test_canonical_finisher_snapshot_round_trip_and_driver_field_forges() -> bool:
	var canonical: Dictionary = _finisher_fixture()
	check(not canonical.is_empty(), "canonical finisher fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "", "canonical finisher restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical finisher constructs world")
	if restored != null: check_eq(restored.snapshot(), canonical, "canonical finisher round trip")
	var bad_driver := canonical.duplicate(true)
	for event in bad_driver.events:
		if event.type == "combat.downed_damage":
			event.cause_id = "-1"; event.instigator_id = "-1"; break
	check(not WorldState.snapshot_restore_error(bad_driver).is_empty(), "finisher driver forge rejected")
	var bad_field := canonical.duplicate(true)
	for event in bad_field.events:
		if event.type == "combat.downed_damage": event.data.requested_damage = 21; break
	check(not WorldState.snapshot_restore_error(bad_field).is_empty(), "finisher requested damage forge rejected")
	var bad_downed_driver := canonical.duplicate(true)
	for event in bad_downed_driver.events:
		if event.type == "entity.downed": event.cause_id = "1"; break
	check(not WorldState.snapshot_restore_error(bad_downed_driver).is_empty(), "downed must cite typed damage")
	var bad_downed_field := canonical.duplicate(true)
	for event in bad_downed_field.events:
		if event.type == "entity.downed": event.data.terminal_immediate = true; break
	check(not WorldState.snapshot_restore_error(bad_downed_field).is_empty(), "non-protagonist terminal flag forge rejected")
	return finish()

func test_canonical_finisher_outcome_direct_child_cardinality() -> bool:
	var canonical: Dictionary = _finisher_fixture()
	check(not canonical.is_empty(), "FINISHER outcome-cardinality fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"FINISHER outcome-cardinality baseline restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "FINISHER outcome-cardinality baseline constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"FINISHER outcome-cardinality baseline roundtrip exact")
	var results: Array = []; var accepted: Array = []
	for mutation in ["missing_terminal_result", "positive_physical_child",
			"duplicate_terminal_result"]:
		var forged: Dictionary = _finisher_outcome_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted FINISHER outcome forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "FINISHER %s forge rejected" % result[0])
	return finish()

func _finisher_outcome_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action_index := -1; var pressure_index := -1; var death_index := -1
	var downed: Dictionary = {}
	for index in range(forged.events.size()):
		var event: Dictionary = forged.events[index]
		if event.type == "action.melee_attack" \
				and event.data.get("outcome", "") == "FINISHER":
			action_index = index
		elif event.type == "combat.downed_damage":
			pressure_index = index
		elif event.type == "entity.died":
			death_index = index
		elif event.type == "entity.downed":
			downed = event
	if action_index < 0 or pressure_index < 0 or death_index < 0 or downed.is_empty():
		return {}
	var action: Dictionary = forged.events[action_index]
	var pressure: Dictionary = forged.events[pressure_index]
	var death: Dictionary = forged.events[death_index]
	match mutation:
		"missing_terminal_result":
			forged.events = forged.events.slice(0, action_index + 1)
			forged.next_event_id = pressure.id
			var target_id: int = int(action.target_id)
			for entity in forged.entities:
				if int(entity.id) == target_id:
					entity.health = 0
					break
			var row: Dictionary = _combatant_wire(forged, target_id)
			row.life_state = "DOWNED"
			row.guarded_until = "0"; row.guard_source_event_id = "-1"
			row.downed_at = downed.world_time
			row.downed_resolve_at = downed.data.downed_resolve_at
			row.downed_source_event_id = downed.id
			row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"
			row.status_rows = []
		"positive_physical_child":
			var child_id: String = forged.next_event_id
			forged.events.append({"id":child_id, "step_index":action.step_index,
				"world_time":action.world_time, "type":"combat.physical_damage",
				"actor_id":"-1", "target_id":action.target_id,
				"position":action.position.duplicate(true), "magnitude":1,
				"cause_id":action.id, "instigator_id":action.instigator_id,
				"data":{"schema_version":1,
					"combat_ruleset_id":"deterministic-melee-resolution-v1",
					"damage_type":"physical", "requested_damage":1,
					"applied_health_damage":1}})
			forged.next_event_id = str(int(child_id) + 1)
		"duplicate_terminal_result":
			var duplicate_pressure: Dictionary = pressure.duplicate(true)
			duplicate_pressure.id = forged.next_event_id
			var duplicate_death: Dictionary = death.duplicate(true)
			duplicate_death.id = str(int(duplicate_pressure.id) + 1)
			duplicate_death.cause_id = duplicate_pressure.id
			forged.events.append(duplicate_pressure)
			forged.events.append(duplicate_death)
			forged.next_event_id = str(int(duplicate_death.id) + 1)
	return forged

func _finisher_fixture() -> Dictionary:
	var sim = Simulator.new(3, 1, 44)
	var attacker = sim.world.add_entity("hero", "Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Target", Vector2i.RIGHT, 22)
	if attacker == null or target == null: return {}
	var target_state = sim.world.combatant_states[target.id]
	if not _begin_fixture_step(sim.world, 0): return {}
	var opening_ordinal := -1; var opening_key := ""; var opening_hit := -1; var opening_bleed := -1
	for candidate in range(1000):
		var candidate_key := Melee.commitment_key(44, 1, 0, "PARTY_TURN/1", candidate,
			attacker.id, target.id)
		var hit_roll := Melee.lane_roll_milli(candidate_key, "HIT")
		var bleed_roll := Melee.lane_roll_milli(candidate_key, "BLEED")
		if hit_roll < 950 and bleed_roll >= 600:
			opening_ordinal = candidate; opening_key = candidate_key
			opening_hit = hit_roll; opening_bleed = bleed_roll; break
	if opening_ordinal < 0: return {}
	var opening_data := {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"attacker_profile_id":"party-hero-v1", "target_profile_id":"party-goblin-v1",
		"batch_context":"PARTY_TURN/1", "intent_ordinal":opening_ordinal, "intent_mode":"STRIKE",
		"target_life_at_batch_start":"ACTIVE", "outcome":"HIT", "processed_step_index":"1",
		"attack_start_world_time":"0", "commitment_hash":Melee.commitment_hash(opening_key),
		"hit_chance_milli":950, "hit_roll_milli":opening_hit, "bleed_chance_milli":600,
		"bleed_roll_milli":opening_bleed, "bleed_proc_succeeded":false,
		"base_damage":24, "target_evasion_milli":100,
		"armor_flat":2, "armor_reduction":2, "frozen_guarded_until":"0",
		"guard_source_event_id":"-1", "guarded":false, "guard_reduction":0, "final_damage":22}
	var opening = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, opening_data)
	if opening == null: return {}
	var damage = sim.world.emit_event("combat.physical_damage", -1, target.id, target.position,
		22, opening.id, {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"damage_type":"physical", "requested_damage":22, "applied_health_damage":22})
	if damage == null: return {}
	target.health = 0
	var downed = sim.world.emit_event("entity.downed", -1, target.id, target.position, 0,
		damage.id, {"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
		"previous_life_state":"ACTIVE", "downed_resolve_at":"200", "terminal_immediate":false})
	if downed == null: return {}
	target_state.life_state = "DOWNED"; target_state.guarded_until = 0; target_state.guard_source_event_id = -1
	target_state.downed_at = 0; target_state.downed_resolve_at = 200; target_state.downed_source_event_id = downed.id
	target_state.recovery_lock_until = 0; target_state.recovery_source_event_id = -1
	sim.world.finish_step()
	if not _begin_fixture_step(sim.world, 100): return {}
	var key := Melee.commitment_key(44, 2, 100, "PARTY_TURN/2", 0, attacker.id, target.id)
	var finisher_data := opening_data.duplicate(true)
	finisher_data.batch_context = "PARTY_TURN/2"; finisher_data.intent_ordinal = 0
	finisher_data.intent_mode = "FINISHER"; finisher_data.target_life_at_batch_start = "DOWNED"
	finisher_data.outcome = "FINISHER"; finisher_data.processed_step_index = "2"
	finisher_data.attack_start_world_time = "100"; finisher_data.commitment_hash = Melee.commitment_hash(key)
	finisher_data.hit_chance_milli = 1000; finisher_data.hit_roll_milli = Melee.lane_roll_milli(key, "HIT")
	finisher_data.bleed_chance_milli = 0; finisher_data.bleed_roll_milli = Melee.lane_roll_milli(key, "BLEED")
	finisher_data.bleed_proc_succeeded = false; finisher_data.final_damage = 0
	var action = sim.world.emit_event("action.melee_attack", attacker.id, target.id,
		target.position, 24, -1, finisher_data)
	if action == null: return {}
	var pressure = sim.world.emit_event("combat.downed_damage", -1, target.id, target.position,
		22, action.id, {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"damage_type":"physical", "requested_damage":22, "applied_health_damage":0,
		"reason":"FINISHER"})
	if pressure == null: return {}
	var death = sim.world.emit_event("entity.died", -1, target.id, target.position, 0,
		pressure.id, {"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
		"previous_life_state":"DOWNED", "reason":"FINISHER", "damage_type":"physical"})
	if death == null: return {}
	target_state.life_state = "DEAD"; target_state.guarded_until = 0; target_state.guard_source_event_id = -1
	target_state.downed_at = -1; target_state.downed_resolve_at = -1; target_state.downed_source_event_id = -1
	target_state.recovery_lock_until = 0; target_state.recovery_source_event_id = -1
	target_state.status_rows.clear(); sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func test_sha_dimension_uniqueness_roundtrip_real_armor_and_terminal_predicates() -> bool:
	var base_args := [44, 3, 200, "PARTY_TURN/3", 0, 1, 4]
	var argument_rows := [base_args, [45,3,200,"PARTY_TURN/3",0,1,4],
		[44,4,200,"PARTY_TURN/3",0,1,4], [44,3,201,"PARTY_TURN/3",0,1,4],
		[44,3,200,"PARTY_TURN/4",0,1,4], [44,3,200,"PARTY_TURN/3",1,1,4],
		[44,3,200,"PARTY_TURN/3",0,2,4], [44,3,200,"PARTY_TURN/3",0,1,5]]
	var seen_keys: Dictionary = {}; var seen_digests: Dictionary = {}
	for args in argument_rows:
		var key := Melee.commitment_key(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		var digest := Melee.commitment_hash(key)
		check(not seen_keys.has(key), "commitment dimensions produce unique key")
		check(not seen_digests.has(digest), "commitment dimensions produce unique digest")
		seen_keys[key] = true; seen_digests[digest] = true
	var base_key := Melee.commitment_key(base_args[0], base_args[1], base_args[2],
		base_args[3], base_args[4], base_args[5], base_args[6])
	check(Melee.lane_hash(base_key, "HIT") != Melee.lane_hash(base_key, "BLEED"),
		"lane dimension produces unique digest")
	check(Melee.lane_hash(base_key, "HIT") != Melee.commitment_hash(base_key),
		"lane digest distinct from commitment digest")

	var session = _engaged_adjacent(); var state = session.sim.world.party_encounter
	check_eq(session.sim.world.step_index, 2, "real fixture base step two")
	var request = Request.new(Action.melee(state.protagonist_id, state.enemy_ids[0]), [])
	var before_plan: Dictionary = session.sim.preview_party_turn(request).to_dict()
	var restored = Simulator.from_snapshot(session.sim.snapshot())
	check(restored != null, "real fixture snapshot restores")
	if restored != null:
		var after_plan: Dictionary = restored.preview_party_turn(request).to_dict()
		check_eq(after_plan, before_plan, "assessment exact across snapshot roundtrip")
		check_eq(after_plan.actor_rows[0].combat_assessment.processed_step_index, "3",
			"base two maps to processed three after roundtrip")

	var formula_cases := [["hero", "melee_enemy", 24, 2, 22],
		["melee_enemy", "hero", 16, 2, 14], ["lead", "melee_threat", 24, 2, 22],
		["melee_threat", "lead", 20, 2, 18]]
	for formula in formula_cases:
		var plain: Dictionary = _real_melee_assessment(formula[0], formula[1], false)
		check_eq([plain.base_damage, plain.target_armor_flat, plain.armor_reduction,
			plain.normal_final_damage], [formula[2], formula[3], formula[3], formula[4]],
			"real assess_attack armor %s to %s" % [formula[0], formula[1]])
	var guard_cases := [["hero", "melee_enemy", 17], ["melee_enemy", "hero", 11],
		["melee_threat", "lead", 14]]
	for formula in guard_cases:
		var guarded: Dictionary = _real_melee_assessment(formula[0], formula[1], true)
		check(guarded.guarded, "real guarded assessment flagged")
		check_eq(guarded.normal_final_damage, formula[2],
			"real guarded damage %s to %s" % [formula[0], formula[1]])

	var predicate_sim = Simulator.new(2, 1, 81)
	var actor = predicate_sim.world.add_entity("other", "Actor", Vector2i.ZERO)
	var actor_state = predicate_sim.world.combatant_states[actor.id]
	actor_state.recovery_lock_until = 100; actor_state.recovery_source_event_id = 1
	check(not predicate_sim.world.can_act(actor.id, 99), "recovery lock blocks before boundary")
	check(predicate_sim.world.can_act(actor.id, 100), "recovery lock releases at boundary")
	for missing_id in [-1, 999]:
		check(not predicate_sim.world.can_act(missing_id, 100), "missing cannot act")
		check(not predicate_sim.world.occupies_tile(missing_id), "missing does not occupy")
		check(not predicate_sim.world.is_environment_exposed(missing_id), "missing not exposed")
		check(not predicate_sim.world.is_explicit_melee_target(missing_id), "missing not explicit target")
		check(not predicate_sim.world.is_autonomous_target(missing_id), "missing not autonomous target")
		check(not predicate_sim.world.is_unresolved_enemy(missing_id), "missing not unresolved")
	var dead_sim = Simulator.new(2, 1, 82); var dead = dead_sim.world.add_entity("other", "Dead", Vector2i.ZERO)
	check(dead_sim.world.bootstrap_set_combatant_life_state(dead.id, "DEAD"), "DEAD predicate fixture")
	check(not dead_sim.world.can_act(dead.id, 0), "DEAD cannot act")
	check(not dead_sim.world.occupies_tile(dead.id), "DEAD does not occupy")
	check(not dead_sim.world.is_environment_exposed(dead.id), "DEAD not exposed")
	check(not dead_sim.world.is_explicit_melee_target(dead.id), "DEAD not explicit target")
	check(not dead_sim.world.is_autonomous_target(dead.id), "DEAD not autonomous target")
	check(not dead_sim.world.is_unresolved_enemy(dead.id), "DEAD resolved")
	return finish()

func _real_melee_assessment(attacker_kind: String, target_kind: String, guarded: bool) -> Dictionary:
	var sim = Simulator.new(2, 1, 83)
	var attacker = sim.world.add_entity(attacker_kind, "Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity(target_kind, "Target", Vector2i.RIGHT)
	if guarded:
		sim.world.begin_step(1)
		var hold = sim.world.emit_event("action.hold", target.id, -1, target.position, 100)
		var target_state = sim.world.combatant_states[target.id]
		target_state.guarded_until = 200; target_state.guard_source_event_id = hold.id
		sim.world.finish_step()
	var processed: int = sim.world.step_index + 1
	return Melee.new(sim.world, sim.damage).assess_attack(attacker.id, target.id, "DIRECT",
		processed, sim.world.world_time, "PARTY_TURN/%d" % processed, 0)

func test_pure_melee_assessment_requires_positive_processed_step() -> bool:
	var sim = Simulator.new(2, 1, 84)
	var attacker = sim.world.add_entity("hero", "Assessment Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Assessment Target", Vector2i.RIGHT)
	check(attacker != null and target != null, "processed-step assessment pair built")
	if attacker == null or target == null: return finish()
	var before: Dictionary = sim.snapshot()
	var melee = Melee.new(sim.world, sim.damage)
	var zero: Dictionary = melee.assess_attack(attacker.id, target.id, "DIRECT",
		0, 0, "PARTY_TURN/0", 0)
	var negative: Dictionary = melee.assess_attack(attacker.id, target.id, "DIRECT",
		-1, 0, "PARTY_TURN/-1", 0)
	var positive: Dictionary = melee.assess_attack(attacker.id, target.id, "DIRECT",
		1, 0, "PARTY_TURN/1", 0)
	check(zero.is_empty(), "processed step zero assessment rejected")
	check(negative.is_empty(), "negative processed step assessment rejected")
	check(not positive.is_empty(), "processed step one assessment accepted")
	if not positive.is_empty():
		check_eq([positive.processed_step_index, positive.batch_context,
			positive.attack_start_world_time], ["1", "PARTY_TURN/1", "0"],
			"positive assessment freezes exact processed step context and time")
	check_eq(sim.snapshot(), before, "processed-step assessment boundary checks are pure")
	return finish()

func test_party_override_canonical_hit_allows_metadata_child() -> bool:
	var canonical: Dictionary = _party_override_canonical_fixture("HIT")
	check(not canonical.is_empty(), "Party override canonical HIT fixture built")
	if canonical.is_empty(): return finish()
	var error := WorldState.snapshot_restore_error(canonical)
	check_eq(error, "", "Party override canonical HIT restores with metadata child")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "Party override canonical HIT constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"Party override canonical HIT roundtrip exact")
	return finish()

func test_party_override_canonical_miss_allows_metadata_child() -> bool:
	var canonical: Dictionary = _party_override_canonical_fixture("MISS")
	check(not canonical.is_empty(), "Party override canonical MISS fixture built")
	if canonical.is_empty(): return finish()
	var target_id := -1
	for event in canonical.events:
		if event.type == "action.melee_attack":
			target_id = int(event.target_id)
			break
	for entity in canonical.entities:
		if int(entity.id) == target_id:
			check_eq(entity.health, entity.max_health,
				"Party override MISS leaves target HP unchanged")
			break
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"Party override canonical MISS restores with metadata child")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "Party override canonical MISS constructs")
	if restored != null:
		check_eq(restored.snapshot(), canonical,
			"Party override canonical MISS roundtrip exact")
	return finish()

func test_party_override_move_hold_roundtrip_and_immediate_leaf_adjacency() -> bool:
	var forge_results: Array = []
	for action_type in ["MOVE", "HOLD"]:
		var canonical: Dictionary = _party_override_nonmelee_fixture(action_type)
		check(not canonical.is_empty(), "Party override %s production fixture built" % action_type)
		if canonical.is_empty(): continue
		var baseline_error := WorldState.snapshot_restore_error(canonical)
		check_eq(baseline_error, "", "Party override %s baseline restores" % action_type)
		var restored = Simulator.from_snapshot(canonical)
		check(restored != null, "Party override %s baseline constructs" % action_type)
		if restored != null:
			check_eq(restored.snapshot(), canonical,
				"Party override %s baseline roundtrip exact" % action_type)
		var leaf_type := "action.move" if action_type == "MOVE" else "action.hold"
		var forged: Dictionary = _party_override_unrelated_interposition_forge(
			canonical, leaf_type)
		check(not forged.is_empty(), "Party override %s adjacency forge built" % action_type)
		if forged.is_empty(): continue
		var forge_error := WorldState.snapshot_restore_error(forged)
		forge_results.append([action_type, forge_error])
		check_eq(forge_error, "party_override_leaf_invalid",
			"Party override %s cited leaf must be immediately adjacent; actual=%s" \
			% [action_type, forge_error])
	check_eq(forge_results.size(), 2, "MOVE and HOLD adjacency forges both exercised")
	return finish()

func _party_override_nonmelee_fixture(action_type: String) -> Dictionary:
	if action_type not in ["MOVE", "HOLD"]: return {}
	var setup: Dictionary = _two_melee_plan_fixture()
	if setup.is_empty(): return {}
	var session = setup.session; var world = session.sim.world
	var state = world.party_encounter; var actor_id: int = int(setup.companion_id)
	var override_action = Action.hold(actor_id)
	if action_type == "MOVE":
		var destination := _first_legal_move(session.sim, actor_id)
		if destination == Vector2i(-1, -1): return {}
		override_action = Action.move_to(actor_id, destination)
	var request = Request.new(Action.hold(state.protagonist_id), [
		{"actor_id":actor_id, "action":override_action}])
	var plan = session.sim.preview_party_turn(request)
	var plan_wire: Dictionary = plan.to_dict()
	if not bool(plan_wire.get("accepted", false)): return {}
	var matching_row: Dictionary = {}
	for row in plan_wire.actor_rows:
		if int(row.actor_id) == actor_id:
			matching_row = row
			break
	if matching_row.is_empty() or str(matching_row.source) != "OVERRIDE" \
			or not bool(matching_row.overridden) \
			or str(matching_row.action.type) != action_type:
		return {}
	var result = session.sim.step_party_turn(plan)
	if not result.accepted: return {}
	var snapshot = session.sim.snapshot()
	if not snapshot is Dictionary: return {}
	var expected_leaf := "action.move" if action_type == "MOVE" else "action.hold"
	var inline_found := false
	for index in range(snapshot.events.size() - 1):
		var leaf: Dictionary = snapshot.events[index]
		var metadata: Dictionary = snapshot.events[index + 1]
		if leaf.type == expected_leaf and int(leaf.actor_id) == actor_id \
				and metadata.type == "party.override_committed" \
				and metadata.cause_id == leaf.id:
			inline_found = true
			break
	return snapshot if inline_found else {}

func test_party_override_leaf_requires_immediate_event_adjacency() -> bool:
	var canonical: Dictionary = _party_override_canonical_fixture("HIT")
	check(not canonical.is_empty(), "Party override adjacency baseline built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"Party override adjacency baseline restores")
	var forged: Dictionary = _party_override_unrelated_interposition_forge(canonical)
	check(not forged.is_empty(), "Party override unrelated interposition forge built")
	if not forged.is_empty():
		var error := WorldState.snapshot_restore_error(forged)
		check_eq(error, "party_override_leaf_invalid",
			"Party override cited leaf must be immediately adjacent; actual=%s" % error)
	return finish()

func _party_override_unrelated_interposition_forge(canonical: Dictionary,
		expected_leaf_type: String = "action.melee_attack") -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action_index := -1; var override_index := -1
	for index in range(forged.events.size()):
		var event: Dictionary = forged.events[index]
		if event.type != "party.override_committed": continue
		var candidate_index := int(event.cause_id) - 1
		if candidate_index >= 0 and candidate_index < forged.events.size() \
				and forged.events[candidate_index].type == expected_leaf_type:
			action_index = candidate_index
			override_index = index
			break
	if action_index < 0 or override_index != action_index + 1: return {}
	var action: Dictionary = forged.events[action_index]
	var override: Dictionary = forged.events[override_index]
	if override.cause_id != action.id: return {}
	var insertion_id: int = int(override.id)
	for event in forged.events:
		if int(event.id) >= insertion_id:
			event.id = str(int(event.id) + 1)
	for event in forged.events:
		if int(event.cause_id) >= insertion_id:
			event.cause_id = str(int(event.cause_id) + 1)
	var witness_id: int = int(forged.party_encounter.protagonist_id)
	var witness_position: Array = []
	for entity in forged.entities:
		if int(entity.id) == witness_id:
			witness_position = entity.position.duplicate(true)
			break
	if witness_position.is_empty(): return {}
	forged.events.insert(override_index, {"id":str(insertion_id),
		"step_index":action.step_index, "world_time":action.world_time,
		"type":"activity.rest", "actor_id":str(witness_id), "target_id":"-1",
		"position":witness_position, "magnitude":1, "cause_id":"-1",
		"instigator_id":str(witness_id), "data":{}})
	forged.next_event_id = str(int(forged.next_event_id) + 1)
	return forged

func test_party_override_committed_exact_metadata_child_forge_matrix() -> bool:
	var canonical: Dictionary = _party_override_canonical_fixture("HIT")
	check(not canonical.is_empty(), "Party override metadata forge baseline built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "",
		"Party override metadata forge baseline restores")
	var mutations := ["duplicate", "non_inline", "target", "wrong_actor",
		"position", "magnitude", "extra_data", "wrong_leaf"]
	var results: Array = []; var accepted: Array = []
	for mutation in mutations:
		var forged: Dictionary = _party_override_metadata_forge(canonical, mutation)
		var error := WorldState.snapshot_restore_error(forged)
		results.append([mutation, error])
		if error.is_empty(): accepted.append(mutation)
	check(accepted.is_empty(), "accepted Party override metadata forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "Party override %s forge rejected" % result[0])
	return finish()

func _party_override_metadata_forge(canonical: Dictionary, mutation: String) -> Dictionary:
	var forged: Dictionary = canonical.duplicate(true)
	var action_index := -1; var override_index := -1; var result_index := -1
	for index in range(forged.events.size()):
		var event: Dictionary = forged.events[index]
		if event.type == "action.melee_attack" and event.data.get("schema_version") == 1:
			action_index = index
		elif event.type == "party.override_committed":
			override_index = index
		elif event.type == "combat.physical_damage" and action_index >= 0 \
				and event.cause_id == forged.events[action_index].id:
			result_index = index
	if action_index < 0 or override_index < 0 or result_index < 0: return {}
	var action: Dictionary = forged.events[action_index]
	var override: Dictionary = forged.events[override_index]
	var result: Dictionary = forged.events[result_index]
	match mutation:
		"duplicate":
			var duplicate: Dictionary = override.duplicate(true)
			duplicate.id = result.id
			result.id = str(int(result.id) + 1)
			forged.events.insert(result_index, duplicate)
			forged.next_event_id = str(int(forged.next_event_id) + 1)
		"non_inline":
			var early_result: Dictionary = result.duplicate(true)
			var late_override: Dictionary = override.duplicate(true)
			early_result.id = override.id
			late_override.id = result.id
			forged.events[override_index] = early_result
			forged.events[result_index] = late_override
		"target": override.target_id = action.target_id
		"wrong_actor":
			var other_actor_id := -1
			for member_id in forged.party_encounter.party_member_ids:
				var candidate_id := int(member_id)
				if candidate_id != int(action.actor_id) \
						and candidate_id != int(forged.party_encounter.protagonist_id):
					other_actor_id = candidate_id
					break
			if other_actor_id < 0: return {}
			override.actor_id = str(other_actor_id)
			for entity in forged.entities:
				if int(entity.id) == other_actor_id:
					override.position = entity.position.duplicate(true)
					break
		"position": override.position = action.position.duplicate(true)
		"magnitude": override.magnitude = int(override.magnitude) + 1
		"extra_data": override.data = {"extra":1}
		"wrong_leaf":
			for candidate in forged.events:
				if candidate.id >= override.id: break
				if str(candidate.type).begins_with("action.") \
						and candidate.id != action.id:
					override.cause_id = candidate.id
					override.instigator_id = candidate.instigator_id
					break
	return forged

func _party_override_canonical_fixture(outcome: String) -> Dictionary:
	if outcome not in ["HIT", "MISS"]: return {}
	var setup: Dictionary = _two_melee_plan_fixture()
	if setup.is_empty(): return {}
	var session = setup.session; var world = session.sim.world
	var state = world.party_encounter
	var actor_id: int = int(setup.companion_id)
	var target_id: int = int(state.enemy_ids[0])
	var base_snapshot = session.sim.snapshot()
	if not base_snapshot is Dictionary: return {}
	var processed_step: int = world.step_index + 1
	var attack_time: int = world.world_time
	var context := "PARTY_TURN/%d" % processed_step
	var seed_value := -1
	for candidate_seed in range(1, 10000):
		var candidate_key := Melee.commitment_key(candidate_seed, processed_step,
			attack_time, context, 0, actor_id, target_id)
		var candidate_hit := Melee.lane_roll_milli(candidate_key, "HIT")
		var candidate_bleed := Melee.lane_roll_milli(candidate_key, "BLEED")
		if (outcome == "MISS" and candidate_hit >= 950) \
				or (outcome == "HIT" and candidate_hit < 950 and candidate_bleed >= 500):
			seed_value = candidate_seed
			break
	if seed_value < 0 or not _begin_fixture_step(world, attack_time): return {}
	world.seed = seed_value
	var assessment: Dictionary = Melee.new(world, session.sim.damage).assess_attack(
		actor_id, target_id, "OVERRIDE", processed_step, attack_time, context, 0)
	if assessment.is_empty(): return {}
	var key := Melee.commitment_key(seed_value, processed_step, attack_time, context,
		0, actor_id, target_id)
	var final_damage: int = int(assessment.normal_final_damage) if outcome == "HIT" else 0
	var target = world.entities[target_id]
	var action = world.emit_event("action.melee_attack", actor_id, target_id,
		target.position, int(assessment.base_damage), -1, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"attacker_profile_id":assessment.attacker_profile_id,
			"target_profile_id":assessment.target_profile_id,
			"batch_context":context, "intent_ordinal":0, "intent_mode":"STRIKE",
			"target_life_at_batch_start":"ACTIVE", "outcome":outcome,
			"processed_step_index":str(processed_step),
			"attack_start_world_time":str(attack_time),
			"commitment_hash":Melee.commitment_hash(key),
			"hit_chance_milli":assessment.hit_chance_milli,
			"hit_roll_milli":Melee.lane_roll_milli(key, "HIT"),
			"bleed_chance_milli":assessment.bleed_chance_milli,
			"bleed_roll_milli":Melee.lane_roll_milli(key, "BLEED"),
			"bleed_proc_succeeded":false, "base_damage":assessment.base_damage,
			"target_evasion_milli":assessment.target_evasion_milli,
			"armor_flat":assessment.target_armor_flat,
			"armor_reduction":assessment.armor_reduction,
			"frozen_guarded_until":assessment.frozen_guarded_until,
			"guard_source_event_id":assessment.guard_source_event_id,
			"guarded":assessment.guarded, "guard_reduction":assessment.guard_reduction,
			"final_damage":final_damage})
	if action == null: return {}
	var member = state.member(actor_id)
	var composure: int = member.personality_profile.value("composure")
	var stress_delta: int = maxi(1, 20 + int((999 - composure) / 20))
	var override = world.emit_event("party.override_committed", actor_id, -1,
		world.entities[actor_id].position, stress_delta, action.id)
	if override == null: return {}
	var result_event = null
	if outcome == "HIT":
		result_event = world.emit_event("combat.physical_damage", -1, target_id,
			target.position, final_damage, action.id, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"damage_type":"physical", "requested_damage":final_damage,
				"applied_health_damage":final_damage})
		if result_event == null or target.health <= final_damage: return {}
		target.health -= final_damage
	else:
		result_event = world.emit_event("combat.attack_missed", -1, target_id,
			target.position, 0, action.id, {"schema_version":1,
				"combat_ruleset_id":"deterministic-melee-resolution-v1",
				"outcome":"MISS"})
		if result_event == null: return {}
	member.stress = clampi(member.stress + stress_delta, 0, 1000)
	member.busy_until = attack_time + 100
	world.finish_step()
	var snapshot: Dictionary = base_snapshot.duplicate(true)
	snapshot.seed = str(seed_value)
	snapshot.events.append(action.to_dict())
	snapshot.events.append(override.to_dict())
	snapshot.events.append(result_event.to_dict())
	snapshot.next_event_id = str(int(snapshot.next_event_id) + 3)
	snapshot.step_index = str(processed_step)
	for entity in snapshot.entities:
		if int(entity.id) == target_id:
			if outcome == "HIT": entity.health = int(entity.health) - final_damage
			break
	for row in snapshot.party_encounter.member_rows:
		if int(row.entity_id) == actor_id:
			row.stress = clampi(int(row.stress) + stress_delta, 0, 1000)
			row.busy_until = str(attack_time + 100)
			break
	return snapshot

func test_universal_party_hold_exact_source_forges_swap_and_equal_candidate_projection() -> bool:
	var session = _engaged_adjacent(); var state = session.sim.world.party_encounter
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id != state.protagonist_id and state.member(member_id).presence == "DEPLOYED":
			overrides.append({"actor_id":member_id, "action":Action.hold(member_id)})
	var plan = session.sim.preview_party_turn(Request.new(Action.hold(state.protagonist_id), overrides))
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "Party HOLD fixture commits")
	var canonical: Dictionary = session.sim.snapshot()
	check_eq(WorldState.snapshot_restore_error(canonical), "", "Party HOLD snapshot restores")
	var source_events: Array = []
	for event in canonical.events:
		if event.type == "action.hold" and event.cause_id == "-1": source_events.append(event)
	check(source_events.size() >= 2, "Party fixture has two independent HOLD sources")
	if source_events.size() < 2: return finish()
	var source: Dictionary = source_events[0]; var actor_id: int = int(source.actor_id)
	var actor_row: Dictionary = _combatant_wire(canonical, actor_id)
	check_eq(actor_row.guard_source_event_id, source.id, "latest Party HOLD owns guard row")

	var target_forge := canonical.duplicate(true); target_forge.events[int(source.id)-1].target_id = str(state.enemy_ids[0])
	check(not WorldState.snapshot_restore_error(target_forge).is_empty(), "Party HOLD target forge rejected")
	var magnitude_forge := canonical.duplicate(true); magnitude_forge.events[int(source.id)-1].magnitude = 99
	check(not WorldState.snapshot_restore_error(magnitude_forge).is_empty(), "Party HOLD magnitude forge rejected")
	var data_forge := canonical.duplicate(true); data_forge.events[int(source.id)-1].data = {"extra":1}
	check(not WorldState.snapshot_restore_error(data_forge).is_empty(), "Party HOLD data forge rejected")
	var type_forge := canonical.duplicate(true); type_forge.events[int(source.id)-1].type = "action.wait"
	check(not WorldState.snapshot_restore_error(type_forge).is_empty(), "guard source type forge rejected")
	var position_forge := canonical.duplicate(true)
	var old_position: Array = position_forge.events[int(source.id)-1].position
	position_forge.events[int(source.id)-1].position = [old_position[0] + 1, old_position[1]]
	check(not WorldState.snapshot_restore_error(position_forge).is_empty(), "Party HOLD position forge rejected")
	var cause_forge := canonical.duplicate(true)
	var old_cause: Dictionary = cause_forge.events[0]
	cause_forge.events[int(source.id)-1].cause_id = old_cause.id
	cause_forge.events[int(source.id)-1].instigator_id = old_cause.instigator_id
	check(not WorldState.snapshot_restore_error(cause_forge).is_empty(), "Party HOLD cause forge rejected")
	var source_swap := canonical.duplicate(true)
	var first_actor: int = int(source_events[0].actor_id); var second_actor: int = int(source_events[1].actor_id)
	var first_row: Dictionary = _combatant_wire(source_swap, first_actor)
	var second_row: Dictionary = _combatant_wire(source_swap, second_actor)
	var first_source: String = first_row.guard_source_event_id
	first_row.guard_source_event_id = second_row.guard_source_event_id
	second_row.guard_source_event_id = first_source
	check(not WorldState.snapshot_restore_error(source_swap).is_empty(), "Party guard source-id swap rejected")

	var equal_sim = Simulator.new(2, 1, 91); var equal_actor = equal_sim.world.add_entity("other", "Guard", Vector2i.ZERO)
	equal_sim.world.begin_step(1)
	var first_hold = equal_sim.world.emit_event("action.hold", equal_actor.id, -1, equal_actor.position, 100)
	var equal_state = equal_sim.world.combatant_states[equal_actor.id]
	equal_state.guarded_until = 200; equal_state.guard_source_event_id = first_hold.id
	var second_hold = equal_sim.world.emit_event("action.hold", equal_actor.id, -1, equal_actor.position, 100)
	var equal_candidate: int = second_hold.world_time + 200
	if equal_candidate > equal_state.guarded_until:
		equal_state.guarded_until = equal_candidate; equal_state.guard_source_event_id = second_hold.id
	equal_sim.world.finish_step()
	var equal_snapshot: Dictionary = equal_sim.snapshot()
	check_eq(equal_snapshot.combatant_states[0].guard_source_event_id, str(first_hold.id),
		"equal candidate retains earlier guard source")
	check_eq(WorldState.snapshot_restore_error(equal_snapshot), "", "equal candidate guard replay restores")
	return finish()

func _combatant_wire(snapshot: Dictionary, entity_id: int) -> Dictionary:
	for row in snapshot.combatant_states:
		if int(row.entity_id) == entity_id: return row
	return {}

func test_exact_recovery_snapshot_roundtrip_and_per_field_forge_matrix() -> bool:
	var canonical: Dictionary = _recovered_fixture()
	check(not canonical.is_empty(), "canonical recovery fixture built")
	if canonical.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(canonical), "", "canonical recovery restores")
	var restored = Simulator.from_snapshot(canonical)
	check(restored != null, "canonical recovery constructs world")
	if restored != null: check_eq(restored.snapshot(), canonical, "canonical recovery roundtrip")
	var recovery_index := -1; var target_id := -1
	for index in range(canonical.events.size()):
		if canonical.events[index].type == "entity.recovered":
			recovery_index = index; target_id = int(canonical.events[index].target_id); break
	check(recovery_index >= 0, "recovery event present")
	if recovery_index < 0: return finish()
	var forgeries: Array = []
	var actor := canonical.duplicate(true); actor.events[recovery_index].actor_id = "1"
	forgeries.append(["recovery actor envelope", actor])
	var target := canonical.duplicate(true); target.events[recovery_index].target_id = "1"
	forgeries.append(["recovery target envelope", target])
	var position := canonical.duplicate(true); position.events[recovery_index].position = [2,0]
	forgeries.append(["recovery position envelope", position])
	var magnitude := canonical.duplicate(true); magnitude.events[recovery_index].magnitude = 2
	forgeries.append(["recovery magnitude envelope", magnitude])
	var cause := canonical.duplicate(true); cause.events[recovery_index].cause_id = "2"
	forgeries.append(["recovery original-down cause", cause])
	var extra := canonical.duplicate(true); extra.events[recovery_index].data["extra"] = 1
	forgeries.append(["recovery exact data keys", extra])
	var schema := canonical.duplicate(true); schema.events[recovery_index].data.schema_version = 2
	forgeries.append(["recovery schema", schema])
	var health_data := canonical.duplicate(true); health_data.events[recovery_index].data.recovered_health = 2
	forgeries.append(["recovery health data", health_data])
	var lock_data := canonical.duplicate(true); lock_data.events[recovery_index].data.recovery_lock_until = "301"
	forgeries.append(["recovery lock data", lock_data])
	var hp := canonical.duplicate(true)
	for entity in hp.entities:
		if int(entity.id) == target_id: entity.health = 2; break
	forgeries.append(["recovery projected HP", hp])
	var row_lock := canonical.duplicate(true); _combatant_wire(row_lock, target_id).recovery_lock_until = "301"
	forgeries.append(["recovery projected lock", row_lock])
	var row_source := canonical.duplicate(true); _combatant_wire(row_source, target_id).recovery_source_event_id = "3"
	forgeries.append(["recovery projected source", row_source])
	for pair in forgeries:
		check(not WorldState.snapshot_restore_error(pair[1]).is_empty(), "%s forge rejected" % pair[0])
	return finish()

func _recovered_fixture() -> Dictionary:
	var finished: Dictionary = _finisher_fixture()
	if finished.is_empty(): return {}
	var downed := finished.duplicate(true); var downed_event: Dictionary = {}
	for event in downed.events:
		if event.type == "entity.downed": downed_event = event; break
	if downed_event.is_empty(): return {}
	downed.events = downed.events.slice(0, int(downed_event.id))
	downed.next_event_id = str(int(downed_event.id) + 1); downed.step_index = downed_event.step_index
	downed.world_time = downed_event.world_time
	for schedule in downed.scheduled_entries: schedule.due_time = "100"
	var target_id: int = int(downed_event.target_id)
	for entity in downed.entities:
		if int(entity.id) == target_id: entity.health = 0; break
	var row: Dictionary = _combatant_wire(downed, target_id)
	row.life_state = "DOWNED"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = downed_event.world_time; row.downed_resolve_at = downed_event.data.downed_resolve_at
	row.downed_source_event_id = downed_event.id; row.recovery_lock_until = "0"
	row.recovery_source_event_id = "-1"; row.status_rows = []
	var sim = Simulator.from_snapshot(downed)
	if sim == null or not _begin_fixture_step(sim.world, 100): return {}
	sim.world.finish_step()
	if not _begin_fixture_step(sim.world, 200): return {}
	var target = sim.world.entities[target_id]; var state = sim.world.combatant_states[target_id]
	var recovered_health: int = maxi(1, int((target.max_health + 9) / 10))
	var recovered = sim.world.emit_event("entity.recovered", -1, target_id, target.position,
		recovered_health, int(downed_event.id), {"schema_version":1,
		"life_ruleset_id":"active-downed-dead-v1", "recovered_health":recovered_health,
		"recovery_lock_until":"300"})
	if recovered == null: return {}
	target.health = recovered_health; state.life_state = "ACTIVE"
	state.downed_at = -1; state.downed_resolve_at = -1; state.downed_source_event_id = -1
	state.recovery_lock_until = 300; state.recovery_source_event_id = recovered.id
	sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func test_party_nonmelee_null_facade_deep_copy_and_ordinal_tamper_noop_matrix() -> bool:
	var hold_session = _engaged_adjacent(); var hold_state = hold_session.sim.world.party_encounter
	var hold_plan = hold_session.sim.preview_party_turn(Request.new(
		Action.hold(hold_state.protagonist_id), [])); var hold_wire: Dictionary = hold_plan.to_dict()
	check(hold_wire.accepted and not hold_wire.actor_rows.is_empty(), "real HOLD plan non-empty")
	check_eq(hold_wire.actor_rows[0].action.type, "HOLD", "real direct HOLD row")
	check(hold_wire.actor_rows[0].combat_assessment == null, "real HOLD assessment exact null")
	for row in hold_wire.actor_rows:
		if row.action.type != "MELEE": check(row.combat_assessment == null, "%s assessment exact null" % row.action.type)

	var move_session = _engaged_adjacent(); var move_state = move_session.sim.world.party_encounter
	var destination := _first_legal_move(move_session.sim, move_state.protagonist_id)
	check(destination != Vector2i(-1,-1), "real MOVE destination exists")
	if destination != Vector2i(-1,-1):
		var move_wire: Dictionary = move_session.sim.preview_party_turn(Request.new(
			Action.move_to(move_state.protagonist_id, destination), [])).to_dict()
		check(move_wire.accepted and not move_wire.actor_rows.is_empty(), "real MOVE plan non-empty")
		check_eq(move_wire.actor_rows[0].action.type, "MOVE", "real direct MOVE row")
		check(move_wire.actor_rows[0].combat_assessment == null, "real MOVE assessment exact null")

	var facade = _engaged_adjacent(); var facade_state = facade.sim.world.party_encounter
	var facade_preview: Dictionary = facade.begin_turn(Action.melee(
		facade_state.protagonist_id, facade_state.enemy_ids[0]))
	check(facade_preview.accepted, "facade melee preview accepted")
	var pristine_facade: Dictionary = facade.current_turn_preview()
	check(pristine_facade.actor_rows[0].combat_assessment is Dictionary, "facade exposes assessment")
	facade_preview.actor_rows[0].combat_assessment.target_position[0] += 1
	facade_preview.actor_rows[0].combat_assessment.commitment_hash = "0".repeat(64)
	check_eq(facade.current_turn_preview(), pristine_facade, "facade nested assessment deeply detached")
	var core_plan = facade.sim.preview_party_turn(Request.new(Action.melee(
		facade_state.protagonist_id, facade_state.enemy_ids[0]), []))
	var detached_rows: Array = core_plan.get_value("actor_rows", [])
	detached_rows[0].combat_assessment.attacker_position[0] += 1
	check_eq(core_plan.get_value("actor_rows", [])[0].combat_assessment,
		core_plan.to_dict().actor_rows[0].combat_assessment, "plan nested assessment deeply detached")

	var multi: Dictionary = _two_melee_plan_fixture()
	check(not multi.is_empty(), "two-melee fixture built")
	if multi.is_empty(): return finish()
	var session = multi.session; var suggested: Dictionary = multi.suggested
	var authoritative: Dictionary = multi.override
	var suggested_row: Dictionary = {}; var override_row: Dictionary = {}
	for row in suggested.actor_rows:
		if int(row.actor_id) == int(multi.companion_id): suggested_row = row; break
	for row in authoritative.actor_rows:
		if int(row.actor_id) == int(multi.companion_id): override_row = row; break
	check(not suggested_row.is_empty() and suggested_row.action.type == "MELEE", "real suggested melee row")
	if not suggested_row.is_empty() and suggested_row.action.type == "MELEE":
		check_eq([suggested_row.source, suggested_row.combat_assessment.source],
			["SUGGESTED", "SUGGESTED"], "suggested source correlated")
	check(not override_row.is_empty() and override_row.action.type == "MELEE", "real override melee row")
	if not override_row.is_empty() and override_row.action.type == "MELEE":
		check_eq([override_row.source, override_row.combat_assessment.source],
			["OVERRIDE", "OVERRIDE"], "override source correlated")
	var melee_indexes: Array = []
	for index in range(authoritative.actor_rows.size()):
		if authoritative.actor_rows[index].action.type == "MELEE": melee_indexes.append(index)
	check_eq(melee_indexes.size(), 2, "fixture has exactly two melee rows")
	if melee_indexes.size() != 2: return finish()
	check_eq([authoritative.actor_rows[melee_indexes[0]].combat_assessment.intent_ordinal,
		authoritative.actor_rows[melee_indexes[1]].combat_assessment.intent_ordinal], [0,1],
		"authoritative melee ordinals contiguous")
	var gap := authoritative.duplicate(true)
	gap.actor_rows[melee_indexes[1]].combat_assessment.intent_ordinal = 2
	_check_tampered_party_plan_noop(session, gap, "ordinal gap")
	var duplicate := authoritative.duplicate(true)
	duplicate.actor_rows[melee_indexes[1]].combat_assessment.intent_ordinal = 0
	_check_tampered_party_plan_noop(session, duplicate, "ordinal duplicate")
	var out_of_order := authoritative.duplicate(true)
	out_of_order.actor_rows[melee_indexes[0]].combat_assessment.intent_ordinal = 1
	out_of_order.actor_rows[melee_indexes[1]].combat_assessment.intent_ordinal = 0
	_check_tampered_party_plan_noop(session, out_of_order, "ordinal row order mismatch")
	var unexpected := hold_wire.duplicate(true)
	unexpected.actor_rows[0].combat_assessment = authoritative.actor_rows[melee_indexes[0]].combat_assessment.duplicate(true)
	_check_tampered_party_plan_noop(hold_session, unexpected, "HOLD non-null assessment")
	return finish()

func _first_legal_move(sim, actor_id: int) -> Vector2i:
	var origin: Vector2i = sim.world.entities[actor_id].position
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
			Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1)]:
		if sim.movement.assess_move(actor_id, origin + direction).accepted: return origin + direction
	return Vector2i(-1,-1)

func _two_melee_plan_fixture(world_seed: int = 44,
		bootstrap_world_time: int = 0) -> Dictionary:
	var session = _engaged_adjacent(world_seed, bootstrap_world_time)
	var world = session.sim.world; var state = world.party_encounter
	var target_id: int = state.enemy_ids[0]; var companion_id := -1
	var melee = Melee.new(world, session.sim.damage)
	for member_id in state.party_member_ids:
		if member_id != state.protagonist_id and state.member(member_id).presence == "DEPLOYED" \
				and melee.can_attack(member_id, target_id): companion_id = member_id; break
	if companion_id < 0:
		for member_id in state.party_member_ids:
			if member_id == state.protagonist_id or state.member(member_id).presence != "DEPLOYED": continue
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
					Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1)]:
				var candidate: Vector2i = world.entities[target_id].position + direction
				if _relocate(session.sim, member_id, candidate) and melee.can_attack(member_id, target_id):
					companion_id = member_id; break
			if companion_id > 0: break
	if companion_id < 0: return {}
	var direct = Action.melee(state.protagonist_id, target_id)
	var suggested: Dictionary = session.sim.preview_party_turn(Request.new(direct, [])).to_dict()
	var overrides: Array = []
	for member_id in state.party_member_ids:
		if member_id == state.protagonist_id or state.member(member_id).presence != "DEPLOYED": continue
		overrides.append({"actor_id":member_id, "action":Action.melee(member_id, target_id) \
			if member_id == companion_id else Action.hold(member_id)})
	var override: Dictionary = session.sim.preview_party_turn(Request.new(direct, overrides)).to_dict()
	if not suggested.get("accepted", false) or not override.get("accepted", false): return {}
	return {"session":session, "companion_id":companion_id,
		"suggested":suggested, "override":override}

func test_processed_step_single_owner_runtime_and_lower_entrypoint_source_regression() -> bool:
	var session = _engaged_adjacent(); var world = session.sim.world; var state = world.party_encounter
	check_eq(world.step_index, 2, "runtime starts at settled base step two")
	var request = Request.new(Action.melee(state.protagonist_id, state.enemy_ids[0]), [])
	var plan = session.sim.preview_party_turn(request); var plan_wire: Dictionary = plan.to_dict()
	var assessment: Dictionary = plan_wire.actor_rows[0].combat_assessment
	check_eq([assessment.processed_step_index, assessment.batch_context], ["3", "PARTY_TURN/3"],
		"preview freezes outer processed step and batch")
	var result = session.sim.step_party_turn(plan)
	check(result.accepted, "processed-step runtime fixture commits")
	check_eq(result.processed_step_index, 3, "result reports outer processed step")
	var action = null; var child = null
	for event in result.events:
		check_eq(event.step_index, 3, "scheduled/direct event %s shares outer step" % event.type)
		if event.type == "action.melee_attack" and event.actor_id == state.protagonist_id:
			action = event
	if action != null:
		for event in result.events:
			if event.cause_id == action.id and event.type in ["combat.physical_damage", "combat.attack_missed"]:
				child = event; break
	check(action != null, "direct action emitted")
	if action != null:
		check_eq(action.step_index, 3, "action uses processed step three")
	check(child != null, "action result child emitted")
	if child != null: check_eq(child.step_index, 3, "action child uses same processed step")

	var actor_source := FileAccess.get_file_as_string("res://sim/systems/actor_coordinator.gd")
	var party_source := FileAccess.get_file_as_string("res://sim/systems/party_encounter_coordinator.gd")
	var damage_source := FileAccess.get_file_as_string("res://sim/systems/damage_system.gd")
	var melee_source := FileAccess.get_file_as_string("res://sim/systems/melee_combat_system.gd")
	var environment_source := FileAccess.get_file_as_string("res://sim/systems/environment_system.gd")
	check(not "step_index + 1" in actor_source, "Actor coordinator never recomputes next step")
	check(not "step_index + 1" in party_source, "Party coordinator never recomputes next step")
	var default_pattern := RegEx.new(); default_pattern.compile("processed_step_index\\s*:\\s*int\\s*=")
	check(default_pattern.search(actor_source) == null, "Actor processed step has no default")
	check(default_pattern.search(party_source) == null, "Party processed step has no default")
	check(default_pattern.search(damage_source) == null, "Damage processed step has no default")
	check(default_pattern.search(melee_source) == null, "Melee processed step has no default")
	check(default_pattern.search(environment_source) == null, "Environment processed step has no default")
	var actor_tick := _function_source(actor_source, "process_tick")
	var party_tick := _function_source(party_source, "process_tick")
	var enemy_batch := _function_source(party_source, "_enemy_batch")
	var actor_freeze := _function_source(actor_source, "_freeze_melee_batch")
	var apply_damage := _function_source(damage_source, "apply_damage")
	var assess_attack := _function_source(melee_source, "assess_attack")
	var environment_tick := _function_source(environment_source, "process_tick")
	var environment_match := _function_source(environment_source, "_processed_step_matches")
	for pair in [["Actor tick", actor_tick], ["Party tick", party_tick],
			["Party enemy batch", enemy_batch], ["Damage", apply_damage],
			["Environment tick", environment_tick]]:
		check(pair[1].count("processed_step_index") >= 2, "%s explicitly consumes processed step" % pair[0])
	check(assess_attack.count("processed_step_index") >= 3 \
			and "processed_step_index <= 0" in assess_attack,
		"pure melee assessment rejects a nonpositive processed step")
	check("combat.assess_attack" in actor_freeze \
			and "processed_step_index" in actor_freeze \
			and "combat.project_batch" in actor_freeze,
		"Phase3 canonical freeze/project passes the owned processed step")
	check(_requires_active_processed_step(actor_tick),
		"Actor tick requires active-step equality")
	check(_requires_active_processed_step(party_tick),
		"Party tick requires active-step equality")
	check(_requires_active_processed_step(enemy_batch),
		"Party enemy batch requires active-step equality")
	check(_requires_active_processed_step(apply_damage),
		"Damage requires active-step equality")
	check(_requires_active_processed_step(environment_tick),
		"Environment tick requires active-step equality")
	check("processed_step_index == world._active_step_index" in environment_match \
			or "world._active_step_index == processed_step_index" in environment_match,
		"Environment helpers reject settled-step fallback")
	return finish()

func _function_source(source: String, function_name: String) -> String:
	var start: int = source.find("func %s(" % function_name)
	if start < 0: return ""
	var next: int = source.find("\nfunc ", start + 5)
	return source.substr(start) if next < 0 else source.substr(start, next - start)

func _requires_active_processed_step(source: String) -> bool:
	return "processed_step_index != world._active_step_index" in source \
		or "world._active_step_index != processed_step_index" in source

func test_fixture_seam_encounter_rejection_liveness_scan_and_recovery_lock_damage() -> bool:
	var party = Session.new(101, 102); var party_world = party.sim.world
	var party_before: Dictionary = party.sim.snapshot(); var hero_id: int = party_world.party_encounter.protagonist_id
	check(not party_world.bootstrap_set_combatant_life_state(hero_id, "DEAD"),
		"Party encounter rejects bootstrap life fixture seam")
	check_eq(party.sim.snapshot(), party_before, "Party fixture rejection exact no-op")
	var lab = LabSession.new(103, 104); var lab_before: Dictionary = lab.sim.snapshot()
	var lead_id: int = lab.lead_roster()[0].entity_id
	check(not lab.sim.world.bootstrap_set_combatant_life_state(lead_id, "DEAD"),
		"Phase3 Lab rejects bootstrap life fixture seam")
	check_eq(lab.sim.snapshot(), lab_before, "Phase3 fixture rejection exact no-op")

	var production_paths: Array[String] = []
	_collect_gd_sources("res://sim", production_paths)
	_collect_gd_sources("res://playtest", production_paths)
	production_paths = _deduped_sorted_paths(production_paths)
	var is_alive_pattern := RegEx.new()
	is_alive_pattern.compile("\\.is_alive\\s*\\(")
	var fixture_definition_pattern := RegEx.new()
	fixture_definition_pattern.compile("^\\s*func\\s+bootstrap_set_combatant_life_state\\s*\\(")
	var fixture_reference_pattern := RegEx.new()
	fixture_reference_pattern.compile("bootstrap_set_combatant_life_state\\s*\\(")
	var is_alive_hits: Array[String] = []
	var fixture_definitions: Array[String] = []; var fixture_calls: Array[String] = []
	for path in production_paths:
		var source := FileAccess.get_file_as_string(path)
		if is_alive_pattern.search(source) != null: is_alive_hits.append(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index in range(lines.size()):
			var line: String = lines[line_index]
			if fixture_reference_pattern.search(line) == null: continue
			if fixture_definition_pattern.search(line) != null:
				fixture_definitions.append(path)
			elif not line.strip_edges().begins_with("#"):
				fixture_calls.append("%s:%d" % [path, line_index + 1])
	check_eq(is_alive_hits, [], "production liveness consumers have zero SimEntity.is_alive calls")
	check_eq(fixture_definitions, ["res://sim/world_state.gd"],
		"bootstrap life fixture seam has one exact production definition")
	check_eq(fixture_calls, [], "production has zero bootstrap life fixture callers")

	var recovered_snapshot: Dictionary = _recovered_fixture()
	var recovered = Simulator.from_snapshot(recovered_snapshot)
	check(recovered != null, "recovery-lock damage fixture restores")
	if recovered != null:
		var target_id := -1
		for event in recovered.world.events:
			if event.type == "entity.recovered": target_id = event.target_id
		check(target_id > 0, "recovered target found")
		if target_id > 0:
			var target = recovered.world.entities[target_id]
			check(not recovered.world.can_act(target_id, recovered.world.world_time),
				"recovery-locked ACTIVE cannot act")
			var attacker_id := 1 if target_id != 1 else 2; var processed: int = recovered.world.step_index + 1
			recovered.world.begin_step(processed)
			var action = recovered.world.emit_event("action.melee_attack", attacker_id, target_id,
				target.position, 22, -1, {"combat_ruleset_id":"fixed-melee-v1"})
			var hp_before: int = target.health
			var applied: int = recovered.damage.apply_damage(target, 1, "physical", action.id,
				target.position, processed)
			check_eq(applied, 1, "recovery lock does not block explicit-step damage")
			check_eq(target.health, hp_before - 1, "recovery-locked ACTIVE HP decreases")
	return finish()

func test_production_raw_health_numeric_comparisons_are_explicitly_allowlisted() -> bool:
	var production_paths: Array[String] = []
	_collect_gd_sources("res://sim", production_paths)
	_collect_gd_sources("res://playtest", production_paths)
	production_paths = _deduped_sorted_paths(production_paths)
	var comparison_pattern := RegEx.new()
	comparison_pattern.compile("(?m)(?:\\bhealth\\b|\\.health)[^\\n]{0,48}(?:==|!=|<=|>=|<|>)\\s*-?\\d+|-?\\d+\\s*(?:==|!=|<=|>=|<|>)[^\\n]{0,48}(?:\\bhealth\\b|\\.health)")
	var raw_health_hits: Array[String] = []
	for path in production_paths:
		if comparison_pattern.search(FileAccess.get_file_as_string(path)) != null:
			raw_health_hits.append(path)
	var allowed_paths: Array[String] = ["res://sim/sim_entity.gd",
		"res://sim/systems/damage_system.gd", "res://sim/world_state.gd"]
	check_eq(raw_health_hits, allowed_paths,
		"raw health comparisons stay inside the exact compatibility/arithmetic/invariant allowlist")
	for allowed_path in allowed_paths:
		check(allowed_path in raw_health_hits,
			"raw health allowlist entry remains exercised: %s" % allowed_path)
	return finish()

func test_runtime_melee_adapters_have_no_legacy_fixed_damage_fallbacks() -> bool:
	var adapter_paths := ["res://sim/simulator.gd",
		"res://sim/systems/actor_coordinator.gd",
		"res://sim/systems/party_encounter_coordinator.gd",
		"res://sim/systems/melee_combat_system.gd"]
	var forbidden := RegEx.new()
	forbidden.compile("fixed-melee-v1|(?:func\\s+)?commit_attack\\s*\\(|\\.apply_damage\\s*\\(")
	var hits: Array[String] = []
	for path in adapter_paths:
		var source := FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = source.split("\n")
		for line_index in range(lines.size()):
			if forbidden.search(lines[line_index]) != null:
				hits.append("%s:%d:%s" % [path, line_index + 1,
					lines[line_index].strip_edges()])
	check_eq(hits, [],
		"runtime keyed-melee adapters contain no fixed-melee/commit_attack/legacy apply path")
	return finish()

func _deduped_sorted_paths(paths: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for path in paths:
		if path not in result: result.append(path)
	result.sort()
	return result

func _collect_gd_sources(root: String, output: Array[String]) -> void:
	var directory = DirAccess.open(root)
	if directory == null: return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var path := root.path_join(name)
		if directory.current_is_dir(): _collect_gd_sources(path, output)
		elif name.ends_with(".gd"): output.append(path)
		name = directory.get_next()
	directory.list_dir_end()

func test_lifecycle_equal_step_recovery_and_post_recovery_damage_replay_legal() -> bool:
	var equal_step: Dictionary = _recovered_fixture().duplicate(true)
	var downed_step := ""
	for event in equal_step.events:
		if event.type == "entity.downed": downed_step = event.step_index
		elif event.type == "entity.recovered": event.step_index = downed_step
	equal_step.step_index = downed_step
	check_eq(WorldState.snapshot_restore_error(equal_step), "",
		"same outer processed-step downed-to-recovery restores")
	var equal_restored = Simulator.from_snapshot(equal_step)
	check(equal_restored != null, "same-step recovery constructs world")
	if equal_restored != null:
		check_eq(equal_restored.snapshot(), equal_step, "same-step recovery roundtrip exact")

	var damaged: Dictionary = _post_recovery_canonical_damage_fixture()
	check(not damaged.is_empty(), "post-recovery damage fixture built")
	if not damaged.is_empty():
		check_eq(WorldState.snapshot_restore_error(damaged), "",
			"post-recovery canonical nonlethal damage replays final HP")
		var damaged_restored = Simulator.from_snapshot(damaged)
		check(damaged_restored != null, "post-recovery damaged world constructs")
		if damaged_restored != null:
			check_eq(damaged_restored.snapshot(), damaged, "post-recovery damage roundtrip exact")
	return finish()

func _post_recovery_canonical_damage_fixture() -> Dictionary:
	var snapshot: Dictionary = _recovered_fixture().duplicate(true)
	if snapshot.is_empty(): return {}
	var recovery: Dictionary = {}
	for event in snapshot.events:
		if event.type == "entity.recovered": recovery = event; break
	if recovery.is_empty(): return {}
	var sim = Simulator.from_snapshot(snapshot)
	if sim == null: return {}
	# The recovered goblin remains locked through T300. At T400 it may legally
	# make an ordinal-zero canonical, keyed, non-BLEED attack on the original hero.
	if not _begin_fixture_step(sim.world, 300): return {}
	sim.world.finish_step()
	if not _begin_fixture_step(sim.world, 400): return {}
	var recovered_actor_id: int = int(recovery.target_id)
	var target_id := 1 if recovered_actor_id != 1 else 2
	var step: int = sim.world._active_step_index
	var context := "PARTY_TURN/%d" % step
	var assessment: Dictionary = Melee.new(sim.world, sim.damage).assess_attack(
		recovered_actor_id, target_id, "DIRECT", step, 400, context, 0)
	if assessment.is_empty(): return {}
	var key := Melee.commitment_key(sim.world.seed, step, 400, context, 0,
		recovered_actor_id, target_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	if hit_roll >= int(assessment.hit_chance_milli) \
			or bleed_roll < int(assessment.bleed_chance_milli):
		return {}
	var action_data := _expected_bleed_hit_action_data(
		assessment, key, hit_roll, bleed_roll)
	action_data.bleed_proc_succeeded = false
	var target = sim.world.entities[target_id]
	var action = sim.world.emit_event("action.melee_attack", recovered_actor_id,
		target_id, target.position, int(assessment.base_damage), -1, action_data)
	if action == null: return {}
	var applied_damage: int = int(assessment.normal_final_damage)
	var damage = sim.world.emit_event("combat.physical_damage", -1, target_id,
		target.position, applied_damage, action.id, {"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":applied_damage,
			"applied_health_damage":applied_damage})
	if damage == null: return {}
	target.health -= applied_damage
	sim.world.finish_step()
	var canonical = sim.snapshot()
	return canonical if canonical is Dictionary else {}

func test_lifecycle_rejects_bleed_recovery_and_legacy_death_resurrection_forges() -> bool:
	var bleeding_recovery: Dictionary = _bleed_present_recovery_forge()
	check(not bleeding_recovery.is_empty(), "BLEED-present recovery forge built")
	if not bleeding_recovery.is_empty():
		var bleed_error := WorldState.snapshot_restore_error(bleeding_recovery)
		check_eq(bleed_error, "status_tick_life_child_invalid",
			"DOWNED BLEED cadence cannot emit ACTIVE physical tick children")
		check(not bleed_error.is_empty(),
			"recovery cannot retain BLEED history and row")
	var resurrection: Dictionary = _legacy_death_resurrection_forge()
	check(not resurrection.is_empty(), "legacy-death resurrection forge built")
	if not resurrection.is_empty():
		check(not WorldState.snapshot_restore_error(resurrection).is_empty(),
			"legacy entity.died is terminal before later canonical lifecycle")
	return finish()

func test_reserved_lifecycle_schema_dispatch_and_terminal_consumption() -> bool:
	var cases: Array = []
	var downed_schema2: Dictionary = _downed_only_fixture()
	for event in downed_schema2.events:
		if event.type == "entity.downed": event.data.schema_version = 2; break
	cases.append(["entity.downed schema two", downed_schema2])
	cases.append(["orphan canonical entity.died", _orphan_canonical_death_fixture()])
	var duplicate_death: Dictionary = _finisher_fixture().duplicate(true)
	var terminal: Dictionary = {}
	for event in duplicate_death.events:
		if event.type == "entity.died": terminal = event
	if not terminal.is_empty():
		var duplicate: Dictionary = terminal.duplicate(true)
		duplicate.id = duplicate_death.next_event_id
		duplicate_death.events.append(duplicate)
		duplicate_death.next_event_id = str(int(duplicate_death.next_event_id) + 1)
	cases.append(["duplicate canonical terminal death", duplicate_death])
	var recovered_schema2: Dictionary = _recovered_fixture().duplicate(true)
	for event in recovered_schema2.events:
		if event.type == "entity.recovered": event.data.schema_version = 2; break
	cases.append(["entity.recovered schema two sanity", recovered_schema2])
	var death_schema2: Dictionary = _finisher_fixture().duplicate(true)
	for event in death_schema2.events:
		if event.type == "entity.died": event.data.schema_version = 2; break
	cases.append(["entity.died schema two sanity", death_schema2])
	var results: Array = []; var accepted: Array = []
	for pair in cases:
		var error := WorldState.snapshot_restore_error(pair[1])
		results.append([pair[0], error])
		if error.is_empty(): accepted.append(pair[0])
	check(accepted.is_empty(), "accepted reserved lifecycle forgeries: %s; errors=%s" \
		% [accepted, results])
	for result in results:
		check(not result[1].is_empty(), "%s rejected" % result[0])
	return finish()

func _orphan_canonical_death_fixture() -> Dictionary:
	var sim = Simulator.new(2, 1, 131)
	var target = sim.world.add_entity("other", "Orphan terminal", Vector2i.ZERO)
	if target == null: return {}
	var snapshot: Dictionary = sim.snapshot()
	target = null
	snapshot.events.append({"id":"1", "step_index":"0", "world_time":"0",
		"type":"entity.died", "actor_id":"-1", "target_id":"1", "position":[0, 0],
		"magnitude":0, "cause_id":"-1", "instigator_id":"-1",
		"data":{"schema_version":1, "life_ruleset_id":"active-downed-dead-v1",
			"previous_life_state":"DOWNED", "reason":"HAZARD", "damage_type":"fire"}})
	snapshot.next_event_id = "2"; snapshot.entities[0].health = 0
	var row: Dictionary = snapshot.combatant_states[0]
	row.life_state = "DEAD"; row.guarded_until = "0"; row.guard_source_event_id = "-1"
	row.downed_at = "-1"; row.downed_resolve_at = "-1"; row.downed_source_event_id = "-1"
	row.recovery_lock_until = "0"; row.recovery_source_event_id = "-1"; row.status_rows = []
	return snapshot

func test_nonterminal_nonhero_downed_cannot_claim_owner_died_status_cleanup() -> bool:
	var forged: Dictionary = _nonterminal_downed_owner_died_cleanup_forge()
	check(not forged.is_empty(), "nonterminal DOWNED OWNER_DIED cleanup forge built")
	if not forged.is_empty():
		check(not WorldState.snapshot_restore_error(forged).is_empty(),
			"nonterminal nonhero DOWNED cannot clean status as OWNER_DIED")
	return finish()

func _nonterminal_downed_owner_died_cleanup_forge() -> Dictionary:
	var snapshot: Dictionary = _downed_bleed_physical_tick_child_forge()
	if snapshot.is_empty(): return {}
	var downed: Dictionary = {}; var applied: Dictionary = {}
	for event in snapshot.events:
		if event.type == "entity.downed": downed = event
		elif event.type == "status.applied": applied = event
	if downed.is_empty() or applied.is_empty(): return {}
	snapshot.events = snapshot.events.slice(0, int(applied.id))
	snapshot.events.append({"id":str(int(applied.id) + 1), "step_index":downed.step_index,
		"world_time":downed.world_time, "type":"status.expired", "actor_id":"-1",
		"target_id":downed.target_id, "position":downed.position.duplicate(true), "magnitude":0,
		"cause_id":downed.id, "instigator_id":downed.instigator_id,
		"data":{"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "reason":"OWNER_DIED"}})
	snapshot.next_event_id = str(int(applied.id) + 2)
	snapshot.step_index = downed.step_index; snapshot.world_time = downed.world_time
	for schedule in snapshot.scheduled_entries: schedule.due_time = "100"
	var row: Dictionary = _combatant_wire(snapshot, int(downed.target_id))
	row.status_rows = []
	return snapshot

func _bleed_present_recovery_forge() -> Dictionary:
	var snapshot: Dictionary = _recovered_fixture().duplicate(true)
	if snapshot.is_empty(): return {}
	var action: Dictionary = {}; var damage: Dictionary = {}; var recovery: Dictionary = {}
	for event in snapshot.events:
		if event.type == "action.melee_attack": action = event
		elif event.type == "combat.physical_damage": damage = event
		elif event.type == "entity.recovered": recovery = event
	if action.is_empty() or damage.is_empty() or recovery.is_empty(): return {}
	var seed_value := 2
	snapshot.seed = str(seed_value)
	var key := Melee.commitment_key(seed_value, int(action.step_index),
		int(action.world_time), str(action.data.batch_context), 0,
		int(action.actor_id), int(action.target_id))
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	if hit_roll >= int(action.data.hit_chance_milli) \
			or bleed_roll >= int(action.data.bleed_chance_milli): return {}
	action.data.intent_ordinal = 0; action.data.commitment_hash = Melee.commitment_hash(key)
	action.data.hit_roll_milli = hit_roll; action.data.bleed_roll_milli = bleed_roll
	action.data.bleed_proc_succeeded = true
	snapshot.events.pop_back()
	var status_id: int = int(recovery.id); var instigator: String = damage.instigator_id
	snapshot.events.append({"id":str(status_id), "step_index":damage.step_index,
		"world_time":damage.world_time, "type":"status.applied", "actor_id":"-1",
		"target_id":damage.target_id, "position":damage.position.duplicate(true), "magnitude":0,
		"cause_id":damage.id, "instigator_id":damage.instigator_id,
		"data":{"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "next_tick_at":"100", "expires_at":"300", "tick_damage":3}})
	snapshot.events.append({"id":str(status_id + 1), "step_index":"2", "world_time":"100",
		"type":"status.tick", "actor_id":"-1", "target_id":damage.target_id,
		"position":damage.position.duplicate(true), "magnitude":3, "cause_id":str(status_id),
		"instigator_id":instigator, "data":{"schema_version":1,
			"status_ruleset_id":"bounded-status-lifecycle-v1", "status_id":"BLEEDING",
			"tick_damage":3, "scheduled_tick_at":"100"}})
	snapshot.events.append({"id":str(status_id + 2), "step_index":"2", "world_time":"100",
		"type":"combat.physical_damage", "actor_id":"-1", "target_id":damage.target_id,
		"position":damage.position.duplicate(true), "magnitude":3, "cause_id":str(status_id + 1),
		"instigator_id":instigator, "data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1", "damage_type":"physical",
			"requested_damage":3, "applied_health_damage":3}})
	snapshot.events.append({"id":str(status_id + 3), "step_index":"3", "world_time":"200",
		"type":"status.tick", "actor_id":"-1", "target_id":damage.target_id,
		"position":damage.position.duplicate(true), "magnitude":3, "cause_id":str(status_id),
		"instigator_id":instigator, "data":{"schema_version":1,
			"status_ruleset_id":"bounded-status-lifecycle-v1", "status_id":"BLEEDING",
			"tick_damage":3, "scheduled_tick_at":"200"}})
	snapshot.events.append({"id":str(status_id + 4), "step_index":"3", "world_time":"200",
		"type":"combat.physical_damage", "actor_id":"-1", "target_id":damage.target_id,
		"position":damage.position.duplicate(true), "magnitude":3, "cause_id":str(status_id + 3),
		"instigator_id":instigator, "data":{"schema_version":1,
			"combat_ruleset_id":"deterministic-melee-resolution-v1", "damage_type":"physical",
			"requested_damage":3, "applied_health_damage":3}})
	recovery.id = str(status_id + 5); snapshot.events.append(recovery)
	snapshot.next_event_id = str(status_id + 6)
	var target_id: int = int(recovery.target_id); var row: Dictionary = _combatant_wire(snapshot, target_id)
	row.recovery_source_event_id = recovery.id
	row.status_rows = [{"schema_version":1, "status_id":"BLEEDING", "applied_at":"0",
		"refreshed_at":"0", "next_tick_at":"300", "expires_at":"300",
		"source_event_id":str(status_id)}]
	return snapshot

func _legacy_death_resurrection_forge() -> Dictionary:
	var snapshot: Dictionary = _recovered_fixture().duplicate(true)
	if snapshot.is_empty(): return {}
	var target_id := -1; var attacker_id := -1; var position: Array = []
	for event in snapshot.events:
		match str(event.type):
			"action.melee_attack":
				attacker_id = int(event.actor_id); target_id = int(event.target_id); position = event.position.duplicate(true)
				event.step_index = "2"; event.world_time = "100"
				event.data.processed_step_index = "2"; event.data.attack_start_world_time = "100"
				event.data.batch_context = "PARTY_TURN/2"
				var candidate: Dictionary = _strike_candidate(int(snapshot.seed), 2, 100,
					"PARTY_TURN/2", attacker_id, target_id, false)
				if candidate.is_empty(): return {}
				event.data.intent_ordinal = candidate.ordinal
				event.data.commitment_hash = Melee.commitment_hash(candidate.key)
				event.data.hit_roll_milli = candidate.hit_roll
				event.data.bleed_roll_milli = candidate.bleed_roll
				event.data.bleed_proc_succeeded = false
			"combat.physical_damage": event.step_index = "2"; event.world_time = "100"
			"entity.downed":
				event.step_index = "2"; event.world_time = "100"; event.data.downed_resolve_at = "300"
			"entity.recovered":
				event.step_index = "3"; event.world_time = "300"; event.data.recovery_lock_until = "400"
	if target_id < 0: return {}
	for event in snapshot.events:
		event.id = str(int(event.id) + 3)
		if int(event.cause_id) > 0: event.cause_id = str(int(event.cause_id) + 3)
	var canonical_events: Array = snapshot.events.duplicate(true)
	snapshot.events = [
		{"id":"1", "step_index":"1", "world_time":"0", "type":"action.melee_attack",
			"actor_id":str(attacker_id), "target_id":str(target_id), "position":position.duplicate(true),
			"magnitude":22, "cause_id":"-1", "instigator_id":str(attacker_id),
			"data":{"combat_ruleset_id":"fixed-melee-v1"}},
		{"id":"2", "step_index":"1", "world_time":"0", "type":"combat.physical_damage",
			"actor_id":"-1", "target_id":str(target_id), "position":position.duplicate(true),
			"magnitude":22, "cause_id":"1", "instigator_id":str(attacker_id),
			"data":{"damage_type":"physical"}},
		{"id":"3", "step_index":"1", "world_time":"0", "type":"entity.died",
			"actor_id":"-1", "target_id":str(target_id), "position":position.duplicate(true),
			"magnitude":0, "cause_id":"2", "instigator_id":str(attacker_id),
			"data":{"damage_type":"physical"}},
	]
	snapshot.events.append_array(canonical_events)
	snapshot.next_event_id = str(int(snapshot.next_event_id) + 3)
	snapshot.step_index = "3"; snapshot.world_time = "300"
	for schedule in snapshot.scheduled_entries: schedule.due_time = "400"
	var row: Dictionary = _combatant_wire(snapshot, target_id)
	row.recovery_lock_until = "400"; row.recovery_source_event_id = "7"
	return snapshot

func _strike_candidate(seed_value: int, step_value: int, time_value: int, context: String,
		attacker_id: int, target_id: int, want_bleed: bool) -> Dictionary:
	for ordinal in range(1000):
		var key := Melee.commitment_key(seed_value, step_value, time_value, context,
			ordinal, attacker_id, target_id)
		var hit_roll := Melee.lane_roll_milli(key, "HIT")
		var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
		if hit_roll < 950 and ((bleed_roll < 600) == want_bleed):
			return {"ordinal":ordinal, "key":key, "hit_roll":hit_roll, "bleed_roll":bleed_roll}
	return {}

func _expected_bleed_hit_action_data(assessment: Dictionary, key: String,
		hit_roll: int, bleed_roll: int) -> Dictionary:
	return {"schema_version":1,
		"combat_ruleset_id":"deterministic-melee-resolution-v1",
		"attacker_profile_id":assessment.attacker_profile_id,
		"target_profile_id":assessment.target_profile_id,
		"batch_context":assessment.batch_context,
		"intent_ordinal":assessment.intent_ordinal,
		"intent_mode":assessment.intent_mode,
		"target_life_at_batch_start":assessment.target_life_state,
		"outcome":"HIT",
		"processed_step_index":assessment.processed_step_index,
		"attack_start_world_time":assessment.attack_start_world_time,
		"commitment_hash":Melee.commitment_hash(key),
		"hit_chance_milli":assessment.hit_chance_milli,
		"hit_roll_milli":hit_roll,
		"bleed_chance_milli":assessment.bleed_chance_milli,
		"bleed_roll_milli":bleed_roll,
		"bleed_proc_succeeded":true,
		"base_damage":assessment.base_damage,
		"target_evasion_milli":assessment.target_evasion_milli,
		"armor_flat":assessment.target_armor_flat,
		"armor_reduction":assessment.armor_reduction,
		"frozen_guarded_until":assessment.frozen_guarded_until,
		"guard_source_event_id":assessment.guard_source_event_id,
		"guarded":assessment.guarded,
		"guard_reduction":assessment.guard_reduction,
		"final_damage":assessment.normal_final_damage}

func _engaged_adjacent(world_seed: int = 44, bootstrap_world_time: int = 0):
	var session=Session.new(world_seed,20260828);var state=session.sim.world.party_encounter
	if bootstrap_world_time > 0:
		if not session.sim.world.bootstrap_set_world_time(bootstrap_world_time): return null
	session.commit_exploration(Command.wait(state.protagonist_id))
	var companions:Array=[state.party_member_ids[1],state.party_member_ids[2]]
	var deployment=session.sim.preview_deployment("WEDGE",companions)
	session.sim.deploy_party(deployment)
	var hero=session.sim.world.entities[state.protagonist_id];var enemy=session.sim.world.entities[state.enemy_ids[0]]
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var candidate=hero.position+direction
		if session.sim.world.in_bounds(candidate) and session.sim.world.blocking_entity_at(candidate,enemy.id)==null:
			_relocate(session.sim,enemy.id,candidate);break
	return session

func _guarded_engaged_adjacent(world_seed: int) -> Dictionary:
	var session = Session.new(world_seed, 20260828)
	var world = session.sim.world; var state = world.party_encounter
	state.party_detection_radius = 3; state.enemy_detection_radius = 4
	var contact = session.sim.step(Command.wait(state.protagonist_id))
	if not contact.accepted or state.contact_kind != "ENEMY_AMBUSH": return {}
	var target_id: int = state.enemy_ids[0]
	var holds: Array = contact.events.filter(func(event):
		return event.type == "action.hold" and event.actor_id == target_id)
	if holds.size() != 1: return {}
	var hold = holds[0]
	var target_state = world.combatant_states[target_id]
	if target_state.guarded_until != hold.world_time + 200 \
			or target_state.guard_source_event_id != hold.id:
		return {}
	var companions: Array = [state.party_member_ids[1], state.party_member_ids[2]]
	var deployment = session.sim.preview_deployment("WEDGE", companions)
	if not bool(deployment.get("accepted", false)): return {}
	var deployed = session.sim.deploy_party(deployment)
	if not deployed.accepted: return {}
	var hero = world.entities[state.protagonist_id]; var target = world.entities[target_id]
	for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var candidate: Vector2i = hero.position + direction
		if world.in_bounds(candidate) and world.blocking_entity_at(candidate, target.id) == null:
			if _relocate(session.sim, target.id, candidate): break
	if maxi(absi(hero.position.x - target.position.x),
			absi(hero.position.y - target.position.y)) != 1:
		return {}
	if target_state.guarded_until != hold.world_time + 200 \
			or target_state.guard_source_event_id != hold.id:
		return {}
	return {"session":session, "hold_id":hold.id,
		"hold_world_time":hold.world_time,
		"guarded_until":target_state.guarded_until}

func _relocate(sim, entity_id: int, target: Vector2i) -> bool:
	for attempt in range(32):
		var current:Vector2i=sim.world.entities[entity_id].position
		if current==target:return true
		var delta:=target-current
		for direction in [Vector2i(signi(delta.x),signi(delta.y)),Vector2i(signi(delta.x),0),Vector2i(0,signi(delta.y))]:
			if direction==Vector2i.ZERO:continue
			var destination:Vector2i=current+direction;var assessment=sim.movement.assess_move(entity_id,destination)
			if not assessment.accepted:continue
			var definition:Dictionary=Terrain.definition(assessment.terrain_id)
			if sim.movement.commit_preflighted_move(entity_id,destination,assessment.terrain_id,definition.move_time_cost)==null:return false
			break
	return sim.world.entities[entity_id].position==target

func test_runtime_bleed_ticks_three_actor_occurrences_then_expires_naturally() -> bool:
	var opening: Dictionary = _bleed_fixture(0, false)
	check(not opening.is_empty(), "runtime BLEED cadence canonical T0 fixture built")
	if opening.is_empty(): return finish()
	check_eq(WorldState.snapshot_restore_error(opening), "",
		"runtime BLEED cadence canonical T0 fixture restores")
	var sim = Simulator.from_snapshot(opening)
	check(sim != null, "runtime BLEED cadence canonical T0 fixture constructs")
	if sim == null: return finish()
	check_eq(sim.snapshot(), opening,
		"runtime BLEED cadence canonical T0 fixture roundtrip exact")

	var world = sim.world
	var attacker_id := 1
	var target_id := 2
	var target = world.entities[target_id]
	var target_state = world.combatant_states[target_id]
	var applied = null
	var opening_damage = null
	for event in world.events:
		if event.type == "combat.physical_damage" and event.target_id == target_id:
			opening_damage = event
		elif event.type == "status.applied" and event.target_id == target_id:
			applied = event
	check(opening_damage != null and applied != null,
		"runtime BLEED cadence T0 has physical source and status apply")
	if opening_damage == null or applied == null: return finish()
	check_eq([applied.step_index, applied.world_time, applied.actor_id,
		applied.target_id, applied.position, applied.magnitude, applied.cause_id,
		applied.instigator_id, applied.data], [1, 0, -1, target_id,
		target.position, 0, opening_damage.id, attacker_id, {"schema_version":1,
			"status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "next_tick_at":"100",
			"expires_at":"300", "tick_damage":3}],
		"runtime BLEED cadence T0 apply exact")
	check_eq(target_state.status_rows.size(), 1,
		"runtime BLEED cadence T0 has one authoritative row")
	if target_state.status_rows.size() == 1:
		check_eq(target_state.status_rows[0].to_dict(), {"schema_version":1,
			"status_id":"BLEEDING", "applied_at":"0", "refreshed_at":"0",
			"next_tick_at":"100", "expires_at":"300",
			"source_event_id":str(applied.id)},
			"runtime BLEED cadence T0 row exact")

	var hp_after_apply: int = target.health
	var rng_before: int = world.rng.state
	for boundary in [100, 200, 300, 400]:
		var event_start: int = world.events.size()
		var processed_step: int = world.step_index + 1
		world.begin_step(processed_step)
		var dispatch_ok := true
		while not world.scheduled_entries.is_empty() \
				and int(world.scheduled_entries[0].due_time) <= boundary:
			var entry: Dictionary = world.take_next_schedule()
			world.world_time = int(entry.due_time)
			dispatch_ok = sim._dispatch_schedule(entry, processed_step) and dispatch_ok
			if int(entry.repeat_interval) > 0:
				world.requeue_repeating(entry)
		world.world_time = boundary
		world.finish_step()
		check(dispatch_ok, "runtime BLEED cadence T%d outer dispatch succeeds" % boundary)

		var occurrence_events: Array = world.events.slice(event_start)
		var ticks: Array = occurrence_events.filter(func(event):
			return event.type == "status.tick" and event.target_id == target_id)
		var damages: Array = occurrence_events.filter(func(event):
			return event.type == "combat.physical_damage" and event.target_id == target_id)
		var expiries: Array = occurrence_events.filter(func(event):
			return event.type == "status.expired" and event.target_id == target_id)
		if boundary <= 300:
			check_eq(ticks.size(), 1,
				"runtime BLEED cadence T%d emits one scheduled tick" % boundary)
			check_eq(damages.size(), 1,
				"runtime BLEED cadence T%d emits one physical child" % boundary)
			var tick = ticks[0] if ticks.size() == 1 else null
			var damage = damages[0] if damages.size() == 1 else null
			if tick != null:
				check_eq([tick.step_index, tick.world_time, tick.actor_id,
					tick.target_id, tick.position, tick.magnitude, tick.cause_id,
					tick.instigator_id, tick.data], [processed_step, boundary, -1,
					target_id, target.position, 3, applied.id, attacker_id,
					{"schema_version":1,
						"status_ruleset_id":"bounded-status-lifecycle-v1",
						"status_id":"BLEEDING", "tick_damage":3,
						"scheduled_tick_at":str(boundary)}],
					"runtime BLEED cadence T%d tick exact" % boundary)
			if tick != null and damage != null:
				check_eq([damage.step_index, damage.world_time, damage.actor_id,
					damage.target_id, damage.position, damage.magnitude,
					damage.cause_id, damage.instigator_id, damage.data],
					[processed_step, boundary, -1, target_id, target.position, 3,
						tick.id, attacker_id, {"schema_version":1,
							"combat_ruleset_id":"deterministic-melee-resolution-v1",
							"damage_type":"physical", "requested_damage":3,
							"applied_health_damage":3}],
					"runtime BLEED cadence T%d physical child exact" % boundary)
				check_eq(occurrence_events.find(damage), occurrence_events.find(tick) + 1,
					"runtime BLEED cadence T%d physical immediately follows tick" % boundary)
			if boundary < 300:
				check_eq(expiries.size(), 0,
					"runtime BLEED cadence T%d does not expire early" % boundary)
				check_eq(target_state.status_rows.size(), 1,
					"runtime BLEED cadence T%d retains one row" % boundary)
				if target_state.status_rows.size() == 1:
					check_eq(target_state.status_rows[0].to_dict(), {"schema_version":1,
						"status_id":"BLEEDING", "applied_at":"0", "refreshed_at":"0",
						"next_tick_at":str(boundary + 100), "expires_at":"300",
						"source_event_id":str(applied.id)},
						"runtime BLEED cadence T%d advances only next tick" % boundary)
			else:
				check_eq(expiries.size(), 1,
					"runtime BLEED cadence T300 emits one natural expiry")
				var expired = expiries[0] if expiries.size() == 1 else null
				if tick != null and damage != null and expired != null:
					check_eq([expired.step_index, expired.world_time, expired.actor_id,
						expired.target_id, expired.position, expired.magnitude,
						expired.cause_id, expired.instigator_id, expired.data],
						[processed_step, 300, -1, target_id, target.position, 0,
							tick.id, attacker_id, {"schema_version":1,
								"status_ruleset_id":"bounded-status-lifecycle-v1",
								"status_id":"BLEEDING", "reason":"NATURAL"}],
						"runtime BLEED cadence T300 natural expiry exact")
					check_eq(occurrence_events.find(expired),
						occurrence_events.find(damage) + 1,
						"runtime BLEED cadence T300 expiry follows final damage")
				check_eq(target_state.status_rows.size(), 0,
					"runtime BLEED cadence T300 removes authoritative row")
		else:
			check_eq([ticks.size(), damages.size(), expiries.size()], [0, 0, 0],
				"runtime BLEED cadence T400 emits no status tail")
		check_eq(world.rng.state, rng_before,
			"runtime BLEED cadence T%d consumes no global RNG" % boundary)
		var settled = sim.snapshot()
		check(settled is Dictionary,
			"runtime BLEED cadence T%d settled snapshot constructs" % boundary)
		if settled is Dictionary:
			check_eq(WorldState.snapshot_restore_error(settled), "",
				"runtime BLEED cadence T%d settled snapshot restores" % boundary)
			var restored = Simulator.from_snapshot(settled)
			check(restored != null,
				"runtime BLEED cadence T%d settled snapshot loads" % boundary)
			if restored != null:
				check_eq(restored.snapshot(), settled,
					"runtime BLEED cadence T%d settled snapshot roundtrip exact" % boundary)
	check_eq(target.health, hp_after_apply - 9,
		"runtime BLEED cadence applies exact total HP delta nine")
	return finish()

func _bleed_fixture(tick_count: int, refresh_after_tick1: bool) -> Dictionary:
	var seed_value := _bleed_fixture_seed(refresh_after_tick1)
	if seed_value < 0: return {}
	var sim = Simulator.new(3, 1, seed_value)
	var attacker = sim.world.add_entity("hero", "Attacker", Vector2i.ZERO)
	var target = sim.world.add_entity("melee_enemy", "Target", Vector2i.RIGHT)
	if attacker == null or target == null: return {}
	if not _begin_fixture_step(sim.world, 0): return {}
	var opening: Dictionary = _emit_canonical_hit(sim.world, attacker.id, target.id)
	if opening.is_empty(): return {}
	var apply_event = sim.world.emit_event("status.applied", -1, target.id, target.position, 0,
		int(opening.damage_id), {"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
		"status_id":"BLEEDING", "next_tick_at":"100", "expires_at":"300", "tick_damage":3})
	if apply_event == null: return {}
	var row = StatusRow.new("BLEEDING")
	row.applied_at = 0; row.refreshed_at = 0; row.next_tick_at = 100
	row.expires_at = 300; row.source_event_id = apply_event.id
	sim.world.combatant_states[target.id].status_rows = [row]
	sim.world.finish_step()
	for tick_index in range(tick_count):
		var due: int = (tick_index + 1) * 100
		if not _begin_fixture_step(sim.world, due): return {}
		var tick = sim.world.emit_event("status.tick", -1, target.id, target.position, 3,
			row.source_event_id, {"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "tick_damage":3, "scheduled_tick_at":str(due)})
		if tick == null: return {}
		var applied: int = mini(3, target.health)
		var tick_damage = sim.world.emit_event("combat.physical_damage", -1, target.id, target.position,
			applied, tick.id, {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
			"damage_type":"physical", "requested_damage":3, "applied_health_damage":applied})
		if tick_damage == null: return {}
		target.health -= applied
		row.next_tick_at += 100
		if tick_index == 2:
			var expired = sim.world.emit_event("status.expired", -1, target.id, target.position, 0,
				tick.id, {"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
				"status_id":"BLEEDING", "reason":"NATURAL"})
			if expired == null: return {}
			sim.world.combatant_states[target.id].status_rows.clear()
		sim.world.finish_step()
	if refresh_after_tick1:
		if tick_count != 1 or not _begin_fixture_step(sim.world, 150): return {}
		var refresh_hit: Dictionary = _emit_canonical_hit(sim.world, attacker.id, target.id)
		if refresh_hit.is_empty(): return {}
		var refreshed = sim.world.emit_event("status.refreshed", -1, target.id, target.position, 0,
			int(refresh_hit.damage_id), {"schema_version":1, "status_ruleset_id":"bounded-status-lifecycle-v1",
			"status_id":"BLEEDING", "next_tick_at":"200", "expires_at":"400", "tick_damage":3})
		if refreshed == null: return {}
		row.refreshed_at = 150; row.expires_at = 400; row.source_event_id = refreshed.id
		sim.world.finish_step()
	var snapshot = sim.snapshot()
	return snapshot if snapshot is Dictionary else {}

func _bleed_fixture_seed(require_refresh: bool) -> int:
	for candidate_seed in range(1, 10000):
		var opening_key := Melee.commitment_key(candidate_seed, 1, 0,
			"PARTY_TURN/1", 0, 1, 2)
		if Melee.lane_roll_milli(opening_key, "HIT") >= 950:
			continue
		if Melee.lane_roll_milli(opening_key, "BLEED") >= 600:
			continue
		if require_refresh:
			var refresh_key := Melee.commitment_key(candidate_seed, 3, 150,
				"PARTY_TURN/3", 0, 1, 2)
			if Melee.lane_roll_milli(refresh_key, "HIT") >= 950:
				continue
			if Melee.lane_roll_milli(refresh_key, "BLEED") >= 600:
				continue
		return candidate_seed
	return -1

func _emit_canonical_hit(world, attacker_id: int, target_id: int) -> Dictionary:
	var attacker = world.entities[attacker_id]; var target = world.entities[target_id]
	var attacker_state = world.combatant_states[attacker_id]
	var target_state = world.combatant_states[target_id]
	var attacker_profile: Dictionary = Profiles.profile(attacker_state.combat_profile_id)
	var target_profile: Dictionary = Profiles.profile(target_state.combat_profile_id)
	var step: int = world._active_step_index; var now: int = world.world_time
	var context := "PARTY_TURN/%d" % step
	var hit_chance: int = clampi(500 + int(attacker_profile.accuracy_milli) - int(target_profile.evasion_milli), 50, 950)
	var bleed_chance: int = clampi(int(attacker_profile.bleed_proc_milli) - int(target_profile.bleed_resist_milli), 0, 1000)
	var ordinal := 0
	var key := Melee.commitment_key(world.seed, step, now, context, ordinal,
		attacker_id, target_id)
	var hit_roll := Melee.lane_roll_milli(key, "HIT")
	var bleed_roll := Melee.lane_roll_milli(key, "BLEED")
	if hit_roll >= hit_chance or bleed_roll >= bleed_chance: return {}
	var base_damage: int = int(attacker_profile.power)
	var armor_reduction: int = mini(int(target_profile.armor_flat), maxi(0, base_damage - 1))
	var final_damage: int = maxi(1, base_damage - armor_reduction)
	var action_data := {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"attacker_profile_id":attacker_state.combat_profile_id, "target_profile_id":target_state.combat_profile_id,
		"batch_context":context, "intent_ordinal":ordinal, "intent_mode":"STRIKE",
		"target_life_at_batch_start":"ACTIVE", "outcome":"HIT", "processed_step_index":str(step),
		"attack_start_world_time":str(now), "commitment_hash":Melee.commitment_hash(key),
		"hit_chance_milli":hit_chance, "hit_roll_milli":hit_roll, "bleed_chance_milli":bleed_chance,
		"bleed_roll_milli":bleed_roll, "bleed_proc_succeeded":true, "base_damage":base_damage,
		"target_evasion_milli":int(target_profile.evasion_milli), "armor_flat":int(target_profile.armor_flat),
		"armor_reduction":armor_reduction, "frozen_guarded_until":"0", "guard_source_event_id":"-1",
		"guarded":false, "guard_reduction":0, "final_damage":final_damage}
	var action = world.emit_event("action.melee_attack", attacker_id, target_id, target.position,
		base_damage, -1, action_data)
	if action == null: return {}
	var applied: int = mini(final_damage, target.health)
	var damage = world.emit_event("combat.physical_damage", -1, target_id, target.position, applied,
		action.id, {"schema_version":1, "combat_ruleset_id":"deterministic-melee-resolution-v1",
		"damage_type":"physical", "requested_damage":final_damage, "applied_health_damage":applied})
	if damage == null: return {}
	target.health -= applied
	return {"action_id":action.id, "damage_id":damage.id}

func _begin_fixture_step(world, at_time: int) -> bool:
	if not world.is_settled() or at_time < world.world_time: return false
	while not world.scheduled_entries.is_empty() and int(world.scheduled_entries[0].due_time) <= at_time:
		var entry: Dictionary = world.take_next_schedule()
		if int(entry.due_time) != at_time: return false
		world.requeue_repeating(entry)
	world.world_time = at_time
	world.begin_step(world.step_index + 1)
	return true
