extends "res://tests/test_case.gd"

const Rules = preload("res://sim/party_ration_rules.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")
const WorldState = preload("res://sim/world_state.gd")
const Command = preload("res://sim/sim_command.gd")
const ItemRegistry = preload("res://sim/item_registry.gd")
const DropRegistry = preload("res://sim/species_drop_registry.gd")
const Cycle = preload("res://sim/expedition_cycle_state.gd")
const Timing = preload("res://sim/action_timing_table.gd")
const RationSystem = preload("res://sim/systems/party_ration_system.gd")


func test_rules_load_and_bands_are_derived_from_content() -> bool:
	check_eq(Rules.registry_error(), "", "hunger_rules.json validates")
	var rules: Dictionary = Rules.rules()
	check_eq(int(rules.ration_max), 300, "ration_max read from content")
	check_eq(Rules.ration_max_milli(), 300000, "max is stored in milli")
	check_eq(Rules.band(300000), "FED", "full gauge is FED")
	check_eq(Rules.band(100000), "FED", "exactly hungry_below is still FED")
	check_eq(Rules.band(99999), "HUNGRY", "below hungry_below is HUNGRY")
	check_eq(Rules.band(0), "STARVING", "zero is STARVING")
	check_eq(Rules.drain_per_interval_milli(1), 1000, "solo drains base rate")
	check_eq(Rules.drain_per_interval_milli(3), 2000, "each extra member adds 500 milli")
	check_eq(Rules.drain_per_interval_milli(0), 1000, "zero members clamps to one")
	return finish()


func test_state_persists_ration_and_legacy_saves_load_full() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	check_eq(int(state.schema_version), 22, "fresh state uses ration schema")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "fresh run starts full")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"fresh run anchors the drain clock at creation time")
	state.ration_milli = 123456
	var wire: Dictionary = state.to_dict()
	check(wire.has("ration_milli") and wire.has("ration_processed_at"),
		"v22 wire carries both ration keys")
	check_eq(PartyState.wire_error(wire, session.sim.world.width, session.sim.world.height), "",
		"v22 wire validates")
	var restored = PartyState.from_dict(wire)
	check_eq(int(restored.ration_milli), 123456, "round trip keeps the gauge")
	check_eq(int(restored.ration_processed_at), int(state.ration_processed_at),
		"round trip keeps the drain clock")
	var legacy: Dictionary = wire.duplicate(true)
	legacy.erase("ration_milli"); legacy.erase("ration_processed_at")
	legacy["schema_version"] = 21
	check_eq(PartyState.wire_error(legacy, session.sim.world.width, session.sim.world.height), "",
		"v21 wire without ration keys still validates")
	var migrated = PartyState.from_dict(legacy)
	check_eq(int(migrated.ration_milli), Rules.ration_max_milli(), "legacy save loads full")
	check_eq(int(migrated.schema_version), 22, "legacy save upgrades to v22")
	var broken: Dictionary = wire.duplicate(true)
	broken["ration_milli"] = Rules.ration_max_milli() + 1
	check(not PartyState.wire_error(broken, session.sim.world.width, session.sim.world.height).is_empty(),
		"gauge above max is rejected")
	var negative: Dictionary = wire.duplicate(true)
	negative["ration_milli"] = -1
	check(not PartyState.wire_error(negative, session.sim.world.width, session.sim.world.height).is_empty(),
		"negative gauge is rejected")
	var missing: Dictionary = wire.duplicate(true)
	missing.erase("ration_milli")
	check(not PartyState.wire_error(missing, session.sim.world.width, session.sim.world.height).is_empty(),
		"v22 wire without ration keys is rejected")
	check_eq(session.sim.world.world_state_error(), "", "world with ration state stays canonical")
	return finish()


func test_legacy_snapshot_reanchors_ration_clock() -> bool:
	var session = Session.new()
	var hero_id: int = int(session.sim.world.party_encounter.protagonist_id)
	check(bool(session.commit_exploration(Command.wait(hero_id)).get("accepted", false)),
		"waiting advances the run before the save")
	check(int(session.sim.world.world_time) > 0, "waiting advanced world time before the save")
	var snapshot: Dictionary = session.sim.snapshot()
	var legacy_party: Dictionary = snapshot.party_encounter.duplicate(true)
	legacy_party.erase("ration_milli"); legacy_party.erase("ration_processed_at")
	legacy_party["schema_version"] = 21
	snapshot["party_encounter"] = legacy_party
	var restored = WorldState.from_snapshot(snapshot)
	check(restored != null, "legacy v21 snapshot still restores")
	if restored == null: return finish()
	check_eq(int(restored.party_encounter.ration_milli), Rules.ration_max_milli(),
		"legacy restore loads a full gauge")
	check_eq(int(restored.party_encounter.ration_processed_at), int(restored.world_time),
		"legacy restore anchors the drain clock at the restored world time")
	check_eq(restored.world_state_error(), "", "re-anchored legacy world stays canonical")
	return finish()


func test_legacy_session_save_migrates_with_a_full_anchored_gauge() -> bool:
	var source = Session.new()
	var hero_id: int = int(source.sim.world.party_encounter.protagonist_id)
	# A genuine pre-ration save carries no drain history at all. Park the source
	# clock beyond the longest single action so the journalled step drains nothing
	# and the fixture is a faithful v20 save rather than a downgraded modern one.
	source.sim.world.party_encounter.ration_processed_at = Timing.MAX_WAIT_COST
	check(bool(source.commit_exploration(Command.wait(hero_id)).get("accepted", false)),
		"waiting advances the run before the save")
	var encoded: Dictionary = JSON.parse_string(source.save_session_json())
	encoded.snapshot.party_encounter.schema_version = PartyState.EMOTION_STATE_SCHEMA_VERSION
	encoded.snapshot.party_encounter.erase("ration_milli")
	encoded.snapshot.party_encounter.erase("ration_processed_at")
	var saved_world_time := int(str(encoded.snapshot.world_time))
	check(saved_world_time > 0, "the save carries a nonzero world time")
	var restored = Session.new(1, 2)
	var loaded: Dictionary = restored.load_session_json(JSON.stringify(encoded))
	check(bool(loaded.get("accepted", false)),
		"v20 save without ration keys migrates: %s" % str(loaded.get("reason", "")))
	if not bool(loaded.get("accepted", false)): return finish()
	var state = restored.sim.world.party_encounter
	check_eq(int(state.ration_milli), Rules.ration_max_milli(),
		"a migrated save starts on a full gauge")
	check_eq(int(state.ration_processed_at), saved_world_time,
		"a migrated save anchors the drain clock at its own world time")
	check_eq(restored.sim.world.world_state_error(), "", "the migrated world stays canonical")
	return finish()


func test_food_ration_content_market_and_start_bag() -> bool:
	var definition = ItemRegistry.definition("FOOD_RATION")
	check(definition != null and str(definition.category) == "CONSUMABLE" \
		and str(definition.use_kind) == "EAT" and int(definition.stack_limit) == 10,
		"FOOD_RATION is a stackable EAT consumable")
	check_eq(DropRegistry.registry_error(), "", "drop tables accept a consumable ration roll")
	var dropped := false
	for death_event_id in range(1, 200):
		for roll in DropRegistry.rolls_for(44, death_event_id, "goblin"):
			if str(roll.definition_id) == "FOOD_RATION": dropped = true
	check(dropped, "goblins can drop a ration within 200 deterministic rolls")
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	var start_ration = session.sim.world.inventory_of(hero_id).item("START_RATION_001")
	check(start_ration != null and str(start_ration.definition_id) == "FOOD_RATION" \
		and int(start_ration.quantity) == 2, "hero starts with two rations")
	var catalog_ids: Array = []
	for row in Session.TOWN_MARKET_CATALOG: catalog_ids.append(str(row.definition_id))
	check("FOOD_RATION" in catalog_ids, "town market sells rations")
	# A full-health hero is refused with item_heal_not_needed before the use_kind
	# gate is ever reached, so wound a fixture with canonical combat damage first.
	# Health is a projection of the event ledger, so no direct HP poke is allowed.
	var wounded = Session.new(44, 20260828, Session.SOLO_FIXTURE_SCENARIO_ID)
	var wounded_id := int(wounded.sim.world.party_encounter.protagonist_id)
	check(bool(wounded.commit_exploration(Command.wait(wounded_id)).get("accepted", false)) \
		and bool(wounded.enter_solo_combat().get("accepted", false)),
		"ration fixture enters canonical combat")
	for _turn in range(12):
		if int(wounded.sim.world.entities[wounded_id].health) \
			< int(wounded.sim.world.entities[wounded_id].max_health): break
		if not bool(wounded.commit_direct_solo_action(wounded_id, "HOLD").get("accepted", false)): break
	check(int(wounded.sim.world.entities[wounded_id].health) \
		< int(wounded.sim.world.entities[wounded_id].max_health),
		"canonical enemy damage clears the item_heal_not_needed gate")
	var manual: Dictionary = wounded.use_inventory_item("START_RATION_001")
	check(not bool(manual.get("accepted", false)), "rations are never used by hand")
	check_eq(str(manual.get("reason", "")), "item_use_unimplemented",
		"a wounded hero is refused on the EAT use_kind, not on heal-not-needed")
	check_eq(int(wounded.sim.world.inventory_of(wounded_id).item("START_RATION_001").quantity), 2,
		"rejected manual use consumes nothing")
	check_eq(wounded.sim.world.world_state_error(), "", "the rejected use leaves a canonical world")
	return finish()


func _wait(session) -> void:
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	check(bool(session.commit_exploration(Command.wait(hero_id)).accepted), "wait fixture commits")


func _events_of(session, type: String) -> Array:
	var rows: Array = []
	for event in session.sim.world.events:
		if str(event.type) == type: rows.append(event)
	return rows


func test_gauge_drains_by_world_time_and_party_size() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var full := Rules.ration_max_milli()
	_wait(session)
	check_eq(int(state.ration_milli), full - 1000, "one 100-time wait drains 1000 milli for a solo party")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"drain clock follows world time")
	# Simulate 100 more elapsed time without a second real step: rewind the clock.
	# The clock is never allowed to go negative, so pull it back to the run start.
	state.ration_processed_at = 0
	_wait(session)
	check_eq(int(state.ration_milli), full - 3000, "elapsed intervals are applied in one tick")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"the clock lands on the last whole interval")
	# Crossing hungry_below announces the new band exactly once.
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "HUNGRY", "the drain crosses hungry_below")
	var changed := _events_of(session, "party.ration_changed")
	check_eq(changed.size(), 1, "band change emits exactly one event")
	if changed.size() == 1:
		check_eq(str(changed[0].data.get("after", "")), "HUNGRY", "event names the new band")
		check_eq(str(changed[0].data.get("before", "")), "FED", "event names the old band")
		check_eq(int(changed[0].data.get("ration_milli", -1)), int(state.ration_milli),
			"event carries the gauge it announces")
		check_eq(str(changed[0].data.get("ruleset_id", "")), Rules.RULESET_ID,
			"event names the ration ruleset")
	_wait(session)
	check_eq(_events_of(session, "party.ration_changed").size(), 1,
		"staying in the same band emits nothing")
	check_eq(session.sim.world.world_state_error(), "", "drain keeps canonical state")
	# Party of three drains twice as fast.
	var trio = Session.new(44, 20260828, "SHOWCASE_V1")
	var trio_state = trio.sim.world.party_encounter
	check(trio_state.active_party_member_ids.size() >= 3, "showcase fixture has three active members")
	var trio_full := int(trio_state.ration_milli)
	_wait(trio)
	check_eq(int(trio_state.ration_milli), trio_full - Rules.drain_per_interval_milli(
		trio_state.active_party_member_ids.size()), "three members drain 2000 milli per interval")
	return finish()


func test_town_phase_freezes_and_departure_resets_the_gauge() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	state.ration_milli = 50000
	state.expedition_cycle = Cycle.active(1, session.sim.world.world_time, 100, 1)
	_wait(session)
	check_eq(str(session.expedition_cycle_status().phase), "TOWN", "deadline returns the party to town")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "returning to town refills the gauge")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"the return anchors the drain clock")
	# Town refuses exploration ticks outright, so nothing can drain there, and a
	# tick that did arrive would still be inert and leave the clock current.
	check_eq(str(session.commit_exploration(Command.wait(hero_id)).get("reason", "")),
		"exploration_phase_required", "town refuses exploration commands")
	state.ration_processed_at = 0
	check(RationSystem.process_tick(session.sim.world, null, 1), "a town tick succeeds")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "town phase does not drain")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"town keeps the clock current so departure starts fresh")
	# Departure re-anchors the gauge for the next expedition.
	state.ration_milli = 50000
	state.ration_processed_at = 0
	check(bool(session.depart_town().get("accepted", false)), "the party departs for the next run")
	state = session.sim.world.party_encounter
	check_eq(str(session.expedition_cycle_status().phase), "DUNGEON", "departure reopens the dungeon")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "departure refills the gauge")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"departure anchors the drain clock")
	check_eq(session.sim.world.world_state_error(), "", "town reset keeps canonical state")
	return finish()
