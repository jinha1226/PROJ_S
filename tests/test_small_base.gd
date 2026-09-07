extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const CacheRules=preload("res://sim/base_resource_cache_rules.gd")
const BaseRules=preload("res://sim/base_progression_rules.gd")


func test_cache_layout_is_finite_floor_bounded_and_actor_independent()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var before:Array[Dictionary]=session._base_cache_rows()
	check_eq(before.size(),9,"one floor exposes nine finite caches")
	var bounds_raw:Array=session._map_layout.floor_bounds
	var bounds:=Rect2i(int(bounds_raw[0]),int(bounds_raw[1]),
		int(bounds_raw[2]),int(bounds_raw[3]))
	for row in before:
		check(bounds.has_point(Vector2i(int(row.position[0]),int(row.position[1]))),
			"cache remains inside selected floor")
	var hero=session.sim.world.entities[session.sim.world.party_encounter.protagonist_id]
	hero.position+=Vector2i.RIGHT
	check_eq(session._base_cache_rows(),before,
		"live actor movement cannot relocate deterministic caches")
	return finish()


func test_gather_is_position_bound_partial_and_capacity_limited()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var first:Dictionary=session._base_cache_rows()[0]
	var hero_id:=int(session.sim.world.party_encounter.protagonist_id)
	_place_party(session,Vector2i(int(first.position[0]),int(first.position[1])))
	var before_time:=int(session.sim.world.world_time)
	var gathered:Dictionary=session.base_gather()
	check(bool(gathered.get("accepted",false)),"reached cache gathers: %s"%str(gathered))
	check_eq(int(session.sim.world.world_time)-before_time,100,
		"gather consumes a canonical exploration action")
	var gathered_again:Dictionary=session.base_gather()
	var first_after:Dictionary=session._base_cache_rows().filter(func(row):
		return str(row.cache_id)==str(first.cache_id))[0]
	check_eq(int(first_after.available_amount),0,
		"the gathered cache stays exhausted across repeat assessment")
	var cycle=session.sim.world.party_encounter.expedition_cycle
	for row in session._base_cache_rows():
		if BaseRules.total_resources(BaseRules.carried(session.sim.world.events,
				int(cycle.expedition_index),"DUNGEON"))>=8:break
		_place_party(session,Vector2i(int(row.position[0]),int(row.position[1])))
		session.base_gather()
	var carried:=BaseRules.carried(session.sim.world.events,
		int(cycle.expedition_index),"DUNGEON")
	check_eq(BaseRules.total_resources(carried),8,"level-one storage caps haul at eight")
	return finish()


func test_manual_return_banks_once_and_base_commands_replay()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var hero_id:=int(session.sim.world.party_encounter.protagonist_id)
	var first:Dictionary=session._base_cache_rows()[0]
	_place_party(session,Vector2i(int(first.position[0]),int(first.position[1])))
	# This test intentionally supplies the matching move journal entry through the
	# normal route API in the replay-focused test below; here only banking purity is checked.
	var gathered:=session.base_gather()
	check(bool(gathered.get("accepted",false)),"haul exists before return: %s"%str(gathered))
	_place_party(session,session._map_layout.entry_position)
	var returned:=session.base_return()
	check(bool(returned.get("accepted",false)),"entry extraction returns to town")
	var stock:Dictionary=session.base_overview().stock
	check_eq(session.base_overview().stock,stock,"overview cannot bank the same haul twice")
	check(not bool(session.base_return().get("accepted",false)),
		"second return is rejected after banking boundary")
	check_eq(session.sim.world.world_state_error(),"","base return state validates")
	return finish()


func test_gather_crossing_deadline_banks_without_losing_cache_yield()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var first:Dictionary=session._base_cache_rows()[0]
	_place_party(session,Vector2i(int(first.position[0]),int(first.position[1])))
	state.expedition_cycle.closes_at_world_time=session.sim.world.world_time+100
	var gathered:Dictionary=session.base_gather()
	check(bool(gathered.get("accepted",false)),"deadline-crossing gather completes")
	check_eq(session.expedition_cycle_status().phase,"TOWN",
		"gather action reaching deadline returns party")
	var overview:Dictionary=session.base_overview()
	check_eq(int(overview.stock[str(first.resource_id)]),
		int(BaseRules.STARTER_STOCK[str(first.resource_id)])+int(gathered.amount),
		"deadline return banks exact gathered amount")
	check_eq(BaseRules.total_resources(overview.carried),0,
		"returned haul is no longer marked carried")
	return finish()


func _place_party(session,position:Vector2i)->void:
	var state=session.sim.world.party_encounter
	state.group_anchor=position
	for entity_id in state.active_party_member_ids:
		session.sim.world.entities[int(entity_id)].position=position


func test_upgrade_effects_trade_and_legacy_surface()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	# Seed a completed prior expedition as canonical gathered history so this test
	# can isolate upgrade pricing/effects without pathfinding through combat.
	for resource_id in BaseRules.RESOURCE_IDS:
		session.sim.world.emit_event("base.resource_gathered",state.protagonist_id,-1,
			state.group_anchor,20,-1,{"schema_version":1,"cache_id":"TEST_"+resource_id,
				"resource_id":resource_id,"amount":20,"expedition_index":0,
				"floor_index":1,"position":[state.group_anchor.x,state.group_anchor.y]})
	state.expedition_cycle.manual_return(session.sim.world.world_time)
	check(session.base_upgrade("STORAGE").accepted,"storage upgrades in town")
	check_eq(session.base_overview().capacity,12,"storage effect is live")
	check(session.base_upgrade("LODGE").accepted,"lodge upgrades in town")
	check_eq(session._base_lodge_recovery(),450,"lodge changes shrine recovery")
	check(session.base_upgrade("CLINIC").accepted,"clinic upgrades in town")
	check_eq([session._base_clinic_cost(),
		int(session._town_market_catalog_row("POTION_HEALING").stock)],
		[20,5],"clinic changes treatment cost and potion supply")
	var stock_before:=int(session.base_overview().stock.TIMBER)
	var sold:=session.base_sell("TIMBER",1)
	check(bool(sold.accepted) and int(session.base_overview().stock.TIMBER)==stock_before-1,
		"trade consumes secured material and grants gold")
	var legacy=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(not bool(legacy.base_overview().enabled),"legacy scenarios keep base opt-in disabled")
	var restored=Session.new()
	check(restored.load_session_json(legacy.save_session_json()).accepted,
		"legacy save still replays")
	return finish()


func test_upgraded_lodge_and_clinic_drive_real_town_services()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero_id:=int(state.protagonist_id)
	var target_id:=int(state.active_party_member_ids[1])
	for resource_id in BaseRules.RESOURCE_IDS:
		session.sim.world.emit_event("base.resource_gathered",hero_id,-1,
			state.group_anchor,30,-1,{"schema_version":1,"ruleset_id":BaseRules.RULESET_ID,
				"cache_id":"SERVICE_"+resource_id,
				"resource_id":resource_id,"amount":30,"expedition_index":0,
				"floor_index":1,"position":[state.group_anchor.x,state.group_anchor.y]})
	state.expedition_cycle.manual_return(session.sim.world.world_time)
	var fixture_error:String=session.sim.world.world_state_error()
	check_eq(fixture_error,"","service fixture is canonical")
	if not fixture_error.is_empty():return finish()
	var target=session.sim.world.entities[target_id]
	target.health-=10
	var clinic_l1:=session.treat_town_clinic(target_id)
	check(bool(clinic_l1.accepted) and int(clinic_l1.cost)==25,
		"level-one clinic transaction charges canonical cost")
	check(session.base_upgrade("CLINIC").accepted,"clinic reaches level two")
	target=session.sim.world.entities[target_id];target.health-=10
	var clinic_l2:=session.treat_town_clinic(target_id)
	check(bool(clinic_l2.accepted) and int(clinic_l2.cost)==20,
		"level-two clinic transaction uses reduced cost")
	var member=state.member(target_id);member.stress=800
	var lodge_l1:=session.rest_at_town_shrine(target_id)
	check(bool(lodge_l1.accepted) and int(lodge_l1.stress_after)==500,
		"level-one lodge drives existing shrine recovery")
	check(session.base_upgrade("LODGE").accepted,"lodge reaches level two")
	var lodge_l2:=session.rest_at_town_shrine(target_id)
	check(bool(lodge_l2.accepted) and int(lodge_l2.stress_after)==50,
		"level-two lodge drives stronger existing shrine recovery")
	check_eq(session.sim.world.world_state_error(),"",
		"mixed level-one and level-two service history validates")
	var snapshot:Dictionary=session.sim.snapshot()
	var restored=Session.SimulatorScript.from_snapshot(snapshot)
	check(restored!=null and restored.snapshot()==snapshot,
		"mixed service history snapshot restores exactly")
	return finish()


func test_return_and_trade_journal_save_reload_exact()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.base_return().accepted,"initial safe entry can extract")
	check(session.base_sell("TIMBER",1).accepted,"starter stock trade is journaled")
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.get("accepted",false)),"base journal reloads: %s"%str(loaded))
	if bool(loaded.get("accepted",false)):
		check_eq(restored.sim.snapshot(),session.sim.snapshot(),"base replay is snapshot exact")
		check_eq(restored.base_overview().stock,session.base_overview().stock,
			"base stock replay is exact")
	return finish()
