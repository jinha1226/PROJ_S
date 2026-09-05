extends "res://tests/test_case.gd"

const Cycle = preload("res://sim/expedition_cycle_state.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")


func test_cycle_warning_bands_and_wire_are_deterministic() -> bool:
	var cycle = Cycle.active(3, 1000, 1000, 4)
	check(cycle != null, "valid expedition cycle is created")
	check_eq([cycle.status(1000).warning_band, cycle.status(1749).warning_band,
		cycle.status(1750).warning_band, cycle.status(1900).warning_band,
		cycle.status(2000).warning_band],
		["OPEN", "OPEN", "WARNING", "CRITICAL", "CLOSED"],
		"25% and 10% thresholds provide stable closure warnings")
	var wire: Dictionary = cycle.to_dict()
	check_eq(Cycle.wire_error(wire), "", "cycle wire validates")
	var restored = Cycle.from_dict(wire)
	check(restored != null and restored.to_dict() == wire,
		"cycle wire round-trips exactly")
	var tampered := wire.duplicate(true); tampered["extra"] = true
	check_eq(Cycle.wire_error(tampered), "invalid_expedition_cycle_keys",
		"unknown cycle state is rejected")
	return finish()


func test_world_time_deadline_returns_survivors_to_town_and_blocks_dungeon_turns() -> bool:
	var session = Session.new()
	var world = session.sim.world
	var state = world.party_encounter
	state.expedition_cycle = Cycle.active(1, world.world_time, 100, 1)
	var hero_id := int(state.protagonist_id)
	var result: Dictionary = session.commit_exploration(Command.wait(hero_id))
	check(bool(result.get("accepted", false)), "the action reaching the deadline completes")
	var cycle: Dictionary = session.expedition_cycle_status()
	check_eq([cycle.phase, cycle.return_reason, cycle.returned_at_world_time,
		cycle.remaining_world_time], ["TOWN", "TIME_LIMIT", 100, 0],
		"deadline atomically returns the surviving party")
	check_eq([session.party_status().view_mode, session.presentation_state().mode,
		session.presentation_state().banner.title], ["TOWN", "TOWN", "길드 홀"],
		"the facade switches from dungeon controls to the guild hall")
	check_eq(world.world_state_error(), "", "returned town state is canonical")
	var snapshot: Dictionary = session.sim.snapshot()
	var restored = Simulator.from_snapshot(snapshot)
	check(restored != null and restored.snapshot() == snapshot,
		"automatic return survives snapshot restore exactly")
	var blocked = session.sim.step(Command.wait(hero_id))
	check(not blocked.accepted and blocked.reason == "expedition_in_town",
		"core simulation rejects dungeon time actions while in town")
	return finish()


func test_schema_seventeen_save_migrates_to_open_legacy_cycle() -> bool:
	var source = Session.new()
	var encoded: Dictionary = JSON.parse_string(source.save_session_json())
	encoded.snapshot.party_encounter.schema_version = \
		PartyState.STAT_SCALING_SCHEMA_VERSION
	encoded.snapshot.party_encounter.erase("expedition_cycle")
	var restored = Session.new(1, 2)
	var loaded: Dictionary = restored.load_session_json(JSON.stringify(encoded))
	check(bool(loaded.get("accepted", false)),
		"v17 save without a campaign clock migrates: %s" % str(loaded.get("reason", "")))
	if bool(loaded.get("accepted", false)):
		var cycle: Dictionary = restored.expedition_cycle_status()
		check_eq([cycle.phase, cycle.closes_at_world_time],
			["DUNGEON", Cycle.MAX_WORLD_TIME],
			"legacy expedition stays open instead of immediately closing")
		check_eq(int(JSON.parse_string(restored.save_session_json()).snapshot.party_encounter.schema_version),
			PartyState.SCHEMA_VERSION,"migrated save writes the current party schema")
	return finish()


func test_town_guild_hall_surface_replaces_dungeon_controls() -> bool:
	var session = Session.new()
	var state = session.sim.world.party_encounter
	state.expedition_cycle = Cycle.active(2, session.sim.world.world_time, 100, 3)
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"town UI fixture reaches its deadline")
	var sandbox = Sandbox.new()
	sandbox.initialize_for_headless_test(session, false)
	check(sandbox.deck.get_node_or_null("TownGuildHallSummary") != null,
		"non-product layout builds the guild hall preparation summary")
	check(sandbox.deck.get_node_or_null("TownGuildHallStations") != null,
		"guild, party, storage and gate stations are visible")
	check(not sandbox._product_can_step(session.party_status()),
		"town surface exposes no dungeon movement input")
	sandbox.free()
	return finish()


func test_product_return_hides_the_dungeon_shell_instead_of_leaving_dead_controls() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	state.expedition_cycle = Cycle.active(1, session.sim.world.world_time, 100, 1)
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"product town fixture reaches its deadline")
	var sandbox = Sandbox.new()
	sandbox.initialize_for_headless_test(session, true)
	check(not sandbox.grid.visible and sandbox.info_scroll.visible and sandbox.deck.visible,
		"the guild hall replaces the product dungeon grid with its preparation deck")
	check(not sandbox.combat_action_area.visible \
		and sandbox.combat_action_dock.get_node_or_null("ProductDirectionPad") == null,
		"no movement or combat dock survives automatic return")
	check_eq(sandbox.phase_label.text, "마을",
		"the shared phase rail names the town instead of the stale combat phase")
	sandbox.free()
	return finish()


func test_guild_arrivals_are_diverse_recruitable_equipped_and_replay_exact() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	state.expedition_cycle = Cycle.active(1, session.sim.world.world_time, 100, 1)
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"guild fixture returns to town")
	var candidates: Array[Dictionary] = session.recruitable_companions()
	check_eq(candidates.size(), Session.GUILD_CANDIDATE_COUNT,
		"one return publishes a bounded stagecoach-sized candidate board")
	var species: Array[String] = []
	for row in candidates:
		check(bool(row.get("guild_candidate", false)) \
			and not str(row.get("weapon_definition_id", "")).is_empty() \
			and not str(row.get("fixed_trait_label", "")).is_empty(),
			"candidate exposes species, starting weapon and fixed trait")
		species.append(str(row.get("species_id", "")))
	var unique_species: Dictionary = {}
	for species_id in species: unique_species[species_id] = true
	check_eq(unique_species.size(), candidates.size(),
		"the first guild board does not duplicate species")
	if candidates.is_empty(): return finish()
	var first: Dictionary = candidates[0]
	var dungeon_phase_before_town:=str(state.safe_phase)
	state.safe_phase="ENGAGED"
	check(session.roster_change_assessment("RECRUIT",int(first.entity_id)).accepted,
		"town recruitment ignores the stale tactical phase left by a timed return")
	state.safe_phase=dungeon_phase_before_town
	var recruited: Dictionary = session.recruit_companion(int(first.entity_id))
	check(bool(recruited.get("accepted", false)) \
		and bool(recruited.get("guild_candidate", false)),
		"town recruitment fills one party slot")
	var equipped = session.sim.world.equipped_item(int(first.entity_id), "MAIN_HAND")
	check(equipped != null \
		and str(equipped.definition_id) == str(first.weapon_definition_id),
		"the advertised starting weapon becomes real item authority")
	check_eq(session.sim.world.world_state_error(), "",
		"guild recruitment leaves a canonical world")
	var snapshot: Dictionary = session.sim.snapshot()
	var restored = Simulator.from_snapshot(snapshot)
	check(restored != null and restored.snapshot() == snapshot,
		"guild board and hired equipment restore exactly")
	# This fixture shortens the otherwise 120,000-tick expedition by directly
	# replacing its clock, so exercise deterministic command replay with the same
	# fixture configuration instead of asking the public save loader to infer an
	# unjournaled ruleset mutation.
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	replay.sim.world.party_encounter.expedition_cycle = Cycle.active(
		1, replay.sim.world.world_time, 100, 1)
	check(replay.commit_exploration(Command.wait(
		replay.sim.world.party_encounter.protagonist_id)).accepted,
		"replay fixture returns to the same guild board")
	check(replay.recruit_companion(int(first.entity_id)).accepted,
		"guild recruitment command replays")
	check_eq(replay.sim.snapshot(), snapshot,
		"guild arrival and starting equipment replay exactly")
	return finish()


func test_town_market_spends_gold_reduces_stock_and_grants_real_item() -> bool:
	var session = _returned_town_session()
	check(session != null, "market fixture returns to town")
	if session == null: return finish()
	var gold_before: int = session.town_gold()
	var stock_before: int = _market_remaining(session, "POTION_HEALING")
	var result: Dictionary = session.purchase_town_item("POTION_HEALING")
	check(bool(result.get("accepted", false)), "market purchase commits")
	check_eq(session.town_gold(), gold_before - 12,
		"purchase price leaves the event-sourced purse")
	check_eq(_market_remaining(session, "POTION_HEALING"), stock_before - 1,
		"only the current return stock is consumed")
	var owner: Dictionary = session.sim.world.item_owner(str(result.get("instance_id", "")))
	check_eq([owner.kind, owner.entity_id], ["ENTITY",
		int(session.sim.world.party_encounter.protagonist_id)],
		"purchased item is canonical protagonist inventory authority")
	check_eq(session.sim.world.world_state_error(), "",
		"purchase leaves a canonical world")
	return finish()


func test_town_clinic_and_shrine_restore_party_state_with_bounded_effects() -> bool:
	var session = _returned_town_session()
	check(session != null, "care fixture returns to town")
	if session == null: return finish()
	var candidate_rows: Array[Dictionary] = session.recruitable_companions()
	check(not candidate_rows.is_empty(), "clinic fixture has a guild candidate")
	if candidate_rows.is_empty(): return finish()
	var companion_id := int(candidate_rows[0].entity_id)
	check(session.recruit_companion(companion_id).accepted,
		"clinic fixture recruits an active companion")
	var companion:Variant = session.sim.world.entities[companion_id]
	var member:Variant = session.sim.world.party_encounter.member(companion_id)
	var body:Variant = session.sim.world.body_states[companion_id]
	companion.health = maxi(1, companion.max_health - 27)
	body.current_blood = maxi(1, int(body.current_blood) - 100)
	body.shock = 70
	body.parts[0].layers[0].integrity = 600
	member.stress = 650
	var clinic: Dictionary = session.treat_town_clinic(companion_id)
	check(bool(clinic.get("accepted", false)), "clinic treats a living companion")
	check_eq([companion.health, body.current_blood, body.shock,
		body.parts[0].layers[0].integrity], [companion.max_health,
		int(body.body_scalars.blood_capacity), 0, 1000],
		"clinic restores HP, blood, shock and non-severed tissue")
	var shrine: Dictionary = session.rest_at_town_shrine(companion_id)
	check(bool(shrine.get("accepted", false)), "shrine rest commits")
	check_eq([member.stress, shrine.stress_before, shrine.stress_after],
		[350, 650, 350], "shrine applies a bounded stress reduction")
	check_eq(session.sim.world.world_state_error(), "",
		"town care leaves body and morale ledgers canonical")
	return finish()


func test_town_armory_transfers_real_ownership_and_departure_reopens_dungeon() -> bool:
	var session = _returned_town_session(3)
	check(session != null, "armory fixture returns to town")
	if session == null: return finish()
	var candidates: Array[Dictionary] = session.recruitable_companions()
	if candidates.is_empty():
		check(false, "armory fixture has a recruitable candidate")
		return finish()
	var companion_id := int(candidates[0].entity_id)
	check(session.recruit_companion(companion_id).accepted,
		"armory fixture recruits a destination member")
	var starting_weapon = session.sim.world.equipped_item(companion_id, "MAIN_HAND")
	var starting_weapon_id: String = str(starting_weapon.instance_id) \
		if starting_weapon != null else ""
	check(session.unequip_town_item(companion_id, "MAIN_HAND").accepted \
		and session.sim.world.equipped_item(companion_id, "MAIN_HAND") == null,
		"town armory unequips a companion's real item")
	check(session.equip_town_item(companion_id, starting_weapon_id, "MAIN_HAND").accepted \
		and session.sim.world.equipped_item(companion_id, "MAIN_HAND") != null,
		"town armory equips a companion's real item")
	var purchase: Dictionary = session.purchase_town_item("POTION_HEALING")
	var instance_id: String = str(purchase.get("instance_id", ""))
	var hero_id: int = int(session.sim.world.party_encounter.protagonist_id)
	var moved: Dictionary = session.transfer_town_item(hero_id, companion_id, instance_id)
	check(bool(moved.get("accepted", false)), "armory transfer commits")
	var owner: Dictionary = session.sim.world.item_owner(instance_id)
	check_eq([owner.kind, owner.entity_id], ["ENTITY", companion_id],
		"item has exactly one new canonical owner")
	var departed: Dictionary = session.depart_town()
	check(bool(departed.get("accepted", false)), "expedition gate departs")
	check_eq(departed.expedition_cycle.floor_index, 1,
		"only the default floor-one portal is currently available")
	check_eq([session.expedition_cycle_status().phase,
		session.expedition_cycle_status().expedition_index,
		session.expedition_cycle_status().floor_index], ["DUNGEON", 2, 1],
		"departure opens the next timed expedition from floor one")
	check_eq(session.sim.world.world_state_error(), "",
		"transfer and departure leave a canonical world")
	check_eq(session._journal_wire_error(session.command_journal), "",
		"town operations write a strict canonical journal")
	var expected_snapshot: Dictionary = session.sim.snapshot()
	var replay = _returned_town_session(3)
	check(replay != null, "town journal replay fixture returns to town")
	if replay != null:
		var replay_candidates: Array[Dictionary] = replay.recruitable_companions()
		var replay_companion_id := int(replay_candidates[0].entity_id)
		check(replay.recruit_companion(replay_companion_id).accepted,
			"town replay recruits the same deterministic candidate")
		var replay_weapon = replay.sim.world.equipped_item(replay_companion_id,
			"MAIN_HAND")
		var replay_weapon_id: String = str(replay_weapon.instance_id)
		check(replay.unequip_town_item(replay_companion_id, "MAIN_HAND").accepted,
			"town replay unequips companion")
		check(replay.equip_town_item(replay_companion_id, replay_weapon_id,
			"MAIN_HAND").accepted, "town replay equips companion")
		var replay_purchase: Dictionary = replay.purchase_town_item("POTION_HEALING")
		check(replay.transfer_town_item(int(replay.sim.world.party_encounter.protagonist_id),
			replay_companion_id,str(replay_purchase.instance_id)).accepted,
			"town replay transfers purchased item")
		check(replay.depart_town().accepted, "town replay departs")
		check_eq(replay.sim.snapshot(), expected_snapshot,
			"all journaled town actions replay to the exact snapshot")
	return finish()


func test_town_facility_tabs_build_actionable_panels() -> bool:
	var session = _returned_town_session()
	check(session != null, "facility UI fixture returns to town")
	if session == null: return finish()
	var sandbox = Sandbox.new()
	sandbox.initialize_for_headless_test(session, false)
	for row in [["CLINIC", "TownClinicTitle"], ["SHRINE", "TownShrineTitle"],
			["MARKET", "TownMarketTitle"], ["ARMORY", "TownArmoryTitle"],
			["GATE", "TownGateTitle"]]:
		sandbox.town_facility_id = str(row[0]); sandbox._refresh()
		check(sandbox.deck.get_node_or_null(str(row[1])) != null,
			"%s facility builds its actionable panel" % str(row[0]))
	sandbox.free()
	return finish()


func _returned_town_session(floor_index:int=1):
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	state.expedition_cycle = Cycle.active(floor_index,
		session.sim.world.world_time, 100, 1)
	var result: Dictionary = session.commit_exploration(Command.wait(state.protagonist_id))
	return session if bool(result.get("accepted", false)) \
		and session.expedition_cycle_status().phase == "TOWN" else null


func _market_remaining(session, definition_id: String) -> int:
	for row in session.town_market_stock():
		if str(row.get("definition_id", "")) == definition_id:
			return int(row.get("remaining", -1))
	return -1
