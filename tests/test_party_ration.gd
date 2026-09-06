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
	# A genuine pre-ration save carries no drain history at all, so the journalled
	# step is shorter than one drain interval: the replay the loader runs against
	# the migrated snapshot then has nothing of its own to subtract.
	check(bool(source.commit_exploration(Command.wait_for(
		int(Rules.rules().drain_interval) / 2, hero_id)).get("accepted", false)),
		"a sub-interval wait advances the run before the save")
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
	# Crossing hungry_below announces the new band exactly once. Empty the food bag
	# first: a stocked hero eats on the crossing tick and swings the band straight
	# back, which is the auto-meal test's subject rather than the drain's.
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"the drain fixture discards its rations before crossing the threshold")
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


func test_hungry_party_eats_one_ration_automatically() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "FED",
		"one more interval leaves 99,500: eaten and refilled")
	check_eq(int(state.ration_milli), mini(Rules.ration_max_milli(),
		Rules.hungry_below_milli() + 500 - 1000 + Rules.food_nutrition_milli()),
		"eating adds food_nutrition capped at max")
	check_eq(int(session.sim.world.inventory_of(hero_id).item("START_RATION_001").quantity), 1,
		"one ration was consumed from the hero bag")
	var eaten := _events_of(session, "party.ration_eaten")
	check_eq(eaten.size(), 1, "one meal event")
	if eaten.size() == 1:
		check_eq(str(eaten[0].data.get("definition_id", "")), "FOOD_RATION", "meal names the food")
	check_eq(_events_of(session, "party.ration_missing").size(), 0, "no missing event while fed")
	check_eq(session.sim.world.world_state_error(), "", "auto meal keeps canonical state")
	return finish()


func test_eaten_gauge_survives_a_session_save_and_reload() -> bool:
	# The journal is the whole save authority, and a directly poked gauge is not in
	# it, so this fixture drains through journalled waits alone: the reload below
	# replays the very same meal instead of restoring a state no command produced.
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var interval := int(Rules.rules().drain_interval)
	while int(state.ration_milli) > Rules.hungry_below_milli():
		var intervals := (int(state.ration_milli) - Rules.hungry_below_milli()) \
			/ Rules.drain_per_interval_milli(1)
		if intervals < 1: break
		check(bool(session.commit_exploration(Command.wait_for(
			mini(Timing.MAX_WAIT_COST, intervals * interval), hero_id)).get("accepted", false)),
			"long waits drain the gauge down to the hungry threshold")
	check_eq(int(state.ration_milli), Rules.hungry_below_milli(),
		"journalled waits park the gauge on the threshold, still FED")
	check_eq(_events_of(session, "party.ration_eaten").size(), 0, "a fed party eats nothing")
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "FED", "the crossing tick eats and refills")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "one ration covers the whole gauge")
	check_eq(_events_of(session, "party.ration_eaten").size(), 1, "exactly one journalled meal")
	var saved := session.save_session_json()
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var loaded: Dictionary = replay.load_session_json(saved)
	check(bool(loaded.get("accepted", false)),
		"session save/load round trip: %s" % str(loaded.get("reason", "")))
	if not bool(loaded.get("accepted", false)): return finish()
	check_eq(int(replay.sim.world.party_encounter.ration_milli), int(state.ration_milli),
		"loaded gauge matches")
	check_eq(int(replay.sim.world.inventory_of(hero_id).item("START_RATION_001").quantity), 1,
		"the reloaded bag also lost exactly one ration")
	check_eq(replay.sim.world.world_state_error(), "", "the reloaded world stays canonical")
	return finish()


func test_missing_food_reports_once_per_band_entry() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "HUNGRY", "no food leaves the party hungry")
	check_eq(_events_of(session, "party.ration_missing").size(), 1, "entering HUNGRY without food reports once")
	_wait(session); _wait(session)
	check_eq(_events_of(session, "party.ration_missing").size(), 1, "later hungry ticks stay silent")
	check_eq(session.sim.world.world_state_error(), "", "missing food keeps canonical state")
	return finish()


func _latest_member_event(session, type: String, member_id: int):
	var latest = null
	for event in session.sim.world.events:
		if str(event.type) == type and int(event.actor_id) == member_id: latest = event
	return latest


func _member_event_carries(session, type: String, member_id: int, trigger: String) -> bool:
	for event in session.sim.world.events:
		if str(event.type) == type and int(event.actor_id) == member_id \
				and trigger in event.data.get("trigger_codes", []):
			return true
	return false


func test_starving_party_takes_damage_and_stress_each_interval() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	# The journal is the whole save authority, so this fixture empties the gauge
	# through journalled waits alone: the reload below replays the very same
	# starve ticks instead of restoring a gauge no command ever produced.
	var interval := int(Rules.rules().drain_interval)
	var per_interval := Rules.drain_per_interval_milli(1)
	while int(state.ration_milli) > per_interval:
		var intervals := maxi(1, (int(state.ration_milli) - per_interval) / per_interval)
		var drained: bool = bool(session.commit_exploration(Command.wait_for(
			mini(Timing.MAX_WAIT_COST, intervals * interval), hero_id)).get("accepted", false))
		check(drained, "long waits drain the empty bag down to its last interval")
		if not drained: return finish()
	check_eq(int(state.ration_milli), per_interval, "the fixture parks one interval short of empty")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 0, "a hungry party is not starving yet")
	var hero = session.sim.world.entities[hero_id]
	var health_before := int(hero.health)
	var starve_damage := int(Rules.rules().starve_damage)
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "STARVING", "the last interval empties the gauge")
	check_eq(int(hero.health), health_before, "the interval the last ration paid for costs no HP")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 0,
		"emptying the gauge is not itself a starving interval")
	_wait(session)
	check_eq(int(hero.health), health_before - starve_damage,
		"the first interval spent at zero costs starve_damage HP")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 1, "one starve tick event")
	check_eq(_events_of(session, "combat.starvation_damage").size(), 1, "one starvation damage event")
	var damage_event = _events_of(session, "combat.starvation_damage")[0]
	var tick_event = _events_of(session, "party.ration_starve_tick")[0]
	check_eq(int(damage_event.cause_id), int(tick_event.id), "damage is caused by the starve tick")
	check_eq(int(damage_event.magnitude), starve_damage,
		"the damage leaf spends the content damage")
	check_eq(str(tick_event.data.get("ruleset_id", "")), Rules.RULESET_ID,
		"the tick names the ration ruleset")
	check_eq(int(tick_event.data.get("damage", 0)), starve_damage,
		"the tick carries the content damage")
	check_eq(int(tick_event.data.get("stress", 0)), int(Rules.rules().starve_stress),
		"the tick carries the content stress")
	check(str(hero_id) in tick_event.data.get("member_ids", []),
		"the tick names its starving members")
	var morale = _latest_member_event(session, "party.morale_changed", hero_id)
	check(morale != null, "starving commits a morale leaf")
	if morale != null:
		check(int(morale.data.direct_delta) >= int(Rules.rules().starve_stress),
			"starving raises stress by starve_stress")
		check("STARVING" in morale.data.trigger_codes, "the morale leaf names the starving trigger")
	var emotion = _latest_member_event(session, "party.emotion_changed", hero_id)
	check(emotion != null and "STARVING" in emotion.data.trigger_codes,
		"starving frightens the hero")
	check(_member_event_carries(session, "party.emotion_changed", hero_id, "RATION_MISSING"),
		"an empty bag frightened the hero when the party turned hungry")
	check_eq(session.sim.world.world_state_error(), "", "starvation damage passes ledger validation")
	# Three elapsed intervals apply three separate ticks in one step.
	check(bool(session.commit_exploration(Command.wait_for(3 * interval, hero_id)).get(
		"accepted", false)), "a three-interval wait starves three times")
	check_eq(int(hero.health), health_before - 4 * starve_damage,
		"three intervals apply three more damages")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 4, "each interval has its own tick event")
	check_eq(_events_of(session, "combat.starvation_damage").size(), 4, "each tick has its own damage leaf")
	var ticks := _events_of(session, "party.ration_starve_tick")
	check(int(ticks[1].step_index) == int(ticks[3].step_index),
		"the three caught-up intervals all bite inside one step")
	check_eq(session.sim.world.world_state_error(), "", "batched starvation stays canonical")
	var saved := session.save_session_json()
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var reloaded: Dictionary = replay.load_session_json(saved)
	check(bool(reloaded.get("accepted", false)),
		"starved session reloads: %s" % str(reloaded.get("reason", "")))
	check_eq(replay.sim.world.world_state_error(), "", "reloaded starvation history validates")
	# One process_tick can spend several intervals at once. Rewind the drain clock
	# (the journal is already saved above) to force that batch: the stress stacks
	# per interval while the persisted trigger list stays one code long.
	var stress := int(Rules.rules().starve_stress)
	state.ration_processed_at = int(session.sim.world.world_time) - 2 * interval
	_wait(session)
	var batched = _latest_member_event(session, "party.morale_changed", hero_id)
	check(batched != null, "a batched starve step commits a morale leaf")
	if batched != null:
		check_eq(int(batched.data.direct_delta), 3 * stress,
			"three intervals in one tick stack three stress deltas")
		check_eq(batched.data.trigger_codes.count("STARVING"), 1,
			"the batched leaf records the starving code once")
	check_eq(session.sim.world.world_state_error(), "", "the batched morale leaf validates")
	# A catch-up span is charged only for the intervals the gauge actually spent at
	# zero: 1500 milli still pays for two of the three solo intervals below.
	var ticks_before := _events_of(session, "party.ration_starve_tick").size()
	var health_before_partial := int(hero.health)
	state.ration_milli = 1500
	state.ration_processed_at = int(session.sim.world.world_time) - 2 * interval
	_wait(session)
	check_eq(int(state.ration_milli), 0, "the partial catch-up empties the gauge")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), ticks_before + 1,
		"three intervals with two of them paid for starve exactly once")
	check_eq(int(hero.health), health_before_partial - starve_damage,
		"the paid intervals cost no health")
	check_eq(session.sim.world.world_state_error(), "", "the partial catch-up stays canonical")
	return finish()


func test_tampered_starve_ticks_are_rejected_by_the_ledger() -> bool:
	# The tick alone says who starves and for how much, so a hand-built snapshot
	# must not be able to widen either bound past what the ration ruleset allows.
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	state.ration_milli = 0
	_wait(session)
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 1, "the fixture starves once")
	var snapshot: Dictionary = session.sim.snapshot()
	check_eq(WorldState.snapshot_restore_error(snapshot), "", "the honest starved snapshot restores")
	var outsider_id := int(state.enemy_ids[0]) if not state.enemy_ids.is_empty() else 999999
	check(outsider_id not in state.party_member_ids, "the tamper fixture has a non-party id")
	var tampers: Array = [
		["damage", 9999, "an inflated damage bound"],
		["member_ids", [str(hero_id), str(outsider_id)], "a non-party member"],
		["ruleset_id", "not-the-ration-ruleset", "a foreign ruleset"],
	]
	for tamper in tampers:
		var forged: Dictionary = snapshot.duplicate(true)
		var patched := false
		for row in forged.events:
			if str(row.type) != "party.ration_starve_tick": continue
			row.data[str(tamper[0])] = tamper[1]
			patched = true
		check(patched, "the forged snapshot carries a starve tick to tamper with")
		check(not WorldState.snapshot_restore_error(forged).is_empty(),
			"%s is rejected" % str(tamper[2]))
		check(WorldState.from_snapshot(forged) == null,
			"%s never yields a world" % str(tamper[2]))
	# A tick nothing points at is still an allowed morale/emotion source, so it has
	# to prove its own envelope even with no damage leaf hanging off it.
	var starve_damage := int(Rules.rules().starve_damage)
	var honest_data := {"schema_version": 1, "ruleset_id": Rules.RULESET_ID,
		"member_ids": [str(hero_id)], "damage": starve_damage,
		"stress": int(Rules.rules().starve_stress)}
	check_eq(WorldState.snapshot_restore_error(_appended(snapshot,
		"party.ration_starve_tick", hero_id, starve_damage, honest_data)), "",
		"an honest stray tick is still accepted, so the forgeries below are the subject")
	# hunger_rules.json is the tuning surface, so the ledger cannot pin stress to
	# the live content value; it bounds it by the morale scale instead.
	var loud_data: Dictionary = honest_data.duplicate(true)
	loud_data.stress = 100000
	var loud := _appended(snapshot, "party.ration_starve_tick", hero_id, starve_damage, loud_data)
	check_eq(WorldState.snapshot_restore_error(loud), "starve_tick_envelope_invalid",
		"a stray tick with off-scale stress is rejected without any damage leaf")
	check(WorldState.from_snapshot(loud) == null, "the inflated stray tick never yields a world")
	var missing := _appended(snapshot, "party.ration_missing", hero_id, 0,
		{"schema_version": 1, "ruleset_id": Rules.RULESET_ID,
			"ration_milli": Rules.ration_max_milli() + 1})
	check_eq(WorldState.snapshot_restore_error(missing), "ration_missing_envelope_invalid",
		"a forged empty-bag notice is rejected")
	check(WorldState.from_snapshot(missing) == null, "the forged notice never yields a world")
	return finish()


func _appended(snapshot: Dictionary, type: String, actor_id: int, magnitude: int,
		data: Dictionary) -> Dictionary:
	# The ledger is contiguous, so a forged row lands at the tail with the next id
	# and the last row's step and clock: nothing but its own envelope is unusual.
	var forged: Dictionary = snapshot.duplicate(true)
	var last: Dictionary = forged.events[forged.events.size() - 1]
	forged.events.append({"id": str(forged.events.size() + 1),
		"step_index": str(last.step_index), "world_time": str(last.world_time),
		"type": type, "actor_id": str(actor_id), "target_id": "-1",
		"position": last.position.duplicate(), "magnitude": magnitude,
		"cause_id": "-1", "instigator_id": str(actor_id), "data": data.duplicate(true)})
	forged.next_event_id = str(int(str(forged.next_event_id)) + 1)
	return forged


func test_ration_clock_ahead_of_world_time_is_rejected() -> bool:
	# wire_error cannot see the world clock, so a drain clock parked in the future
	# is only catchable where the two fields meet.
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	_wait(session)
	var snapshot: Dictionary = session.sim.snapshot()
	check_eq(WorldState.snapshot_restore_error(snapshot), "", "the honest snapshot restores")
	var forged: Dictionary = snapshot.duplicate(true)
	forged.party_encounter.ration_processed_at = str(int(str(forged.world_time)) + 100)
	check(not WorldState.snapshot_restore_error(forged).is_empty(),
		"a drain clock ahead of the world clock is rejected")
	check(WorldState.from_snapshot(forged) == null, "the forged clock never yields a world")
	return finish()


func test_starvation_can_kill_and_the_death_validates() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	# Health is a projection of the event ledger, so the kill has to be starved
	# for: park a whole health bar of starve intervals on the drain clock and let
	# one step spend them all. The clock may never go negative, so buy the runway
	# with a long fed wait first.
	var hero = session.sim.world.entities[hero_id]
	var max_health := int(hero.max_health)
	var runway := max_health * int(Rules.rules().starve_interval)
	while int(session.sim.world.world_time) < runway:
		var span := mini(Timing.MAX_WAIT_COST, runway - int(session.sim.world.world_time))
		var advanced: bool = bool(session.commit_exploration(
			Command.wait_for(span, hero_id)).get("accepted", false))
		check(advanced, "long fed waits put a health bar of intervals on the clock")
		if not advanced: return finish()
	check_eq(int(hero.health), max_health, "the fed runway costs no health")
	check_eq(Rules.band(int(state.ration_milli)), "FED", "the runway never starves on its own")
	state.ration_milli = 0
	state.ration_processed_at = int(session.sim.world.world_time) - runway
	_wait(session)
	check_eq(str(session.sim.world.combatant_states[hero_id].life_state), "DEAD", "starvation kills at 0 HP")
	check_eq(_events_of(session, "entity.died").size(), 1, "one death event")
	check_eq(str(_events_of(session, "entity.died")[0].data.get("damage_type", "")), "starvation",
		"death records the starvation damage type")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), max_health,
		"the dead hero stops accruing starve ticks")
	check_eq(session.sim.world.world_state_error(), "", "starvation death passes ledger validation")
	return finish()


func test_floor_ration_dto_and_log_copy() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var ground = session.sim.world.item_state.ground_items
	var floor_ration = ground.item("GROUND_FLOOR1_RATION")
	check(floor_ration != null and str(floor_ration.definition_id) == "FOOD_RATION",
		"floor one places one ration on the ground")
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check_eq(replay.sim.world.item_state.ground_items.position_of("GROUND_FLOOR1_RATION"),
		ground.position_of("GROUND_FLOOR1_RATION"), "floor ration position is seed-fixed")
	var status: Dictionary = session.party_status()
	check_eq(int(status.get("ration", -1)), 300, "status exposes the whole-unit gauge")
	check_eq(int(status.get("ration_max", -1)), 300, "status exposes the max")
	check_eq(str(status.get("ration_band", "")), "FED", "status exposes the band")
	var state = session.sim.world.party_encounter
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	var log: Dictionary = session.combat_log(8, 80)
	var messages: Array[String] = []
	for group in log.get("groups", []):
		for row in group.get("rows", []): messages.append(str(row.get("message", "")))
	check("배급 식량을 먹었다." in messages, "meal reaches the important log with Korean copy")
	return finish()
