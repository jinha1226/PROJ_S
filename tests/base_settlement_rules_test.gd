extends "res://tests/test_case.gd"

const Rules=preload("res://sim/base_settlement_rules.gd")
const Progression=preload("res://sim/base_progression_rules.gd")
const Session=preload("res://playtest/party_playtest_session.gd")


func test_grid_baselines_and_placement_guards()->bool:
	var marker={"type":"base.settlement_initialized"}
	var levels={"STORAGE":1,"LODGE":1,"CLINIC":1}
	var sparse:Array[Dictionary]=Rules.buildings([marker],levels)
	var legacy:Array[Dictionary]=Rules.buildings([],levels)
	check_eq(sparse.size(),3,"new camp starts with storage, lodge and gate")
	check_eq(legacy.size(),6,"unmarked legacy camp retains all old services")
	check_eq(Rules.tiles().size(),256,"settlement publishes every 16x16 tile")
	check_eq(Rules.placement_error("CLINIC",Vector2i(14,14),0,sparse),
		"base_building_out_of_bounds","footprint must stay in bounds")
	check_eq(Rules.placement_error("CLINIC",Vector2i(6,6),0,sparse),
		"base_building_reserved","central access plaza is protected")
	check_eq(Rules.placement_error("CLINIC",Vector2i(1,2),0,sparse),
		"base_building_overlap","buildings cannot overlap")
	check_eq(Rules.placement_error("CLINIC",Vector2i(10,7),0,sparse),"",
		"clear connected lot accepts clinic")
	return finish()


func test_new_duo_build_is_atomic_gated_and_replay_exact()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var dungeon:Dictionary=session.base_overview()
	check_eq(dungeon.settlement.buildings.size(),3,"new DUO publishes sparse camp")
	check_eq(session.town_clinic_assessment(
		int(session.sim.world.party_encounter.protagonist_id)).reason,
		"base_clinic_not_built","clinic service is absent before construction")
	check(session.base_return().accepted,"new camp can return through canonical entry")
	var town:Dictionary=session.base_overview()
	var clinic_option:Dictionary=_option(town.settlement.build_options,"CLINIC")
	check(bool(clinic_option.can_build),"starter stock enables first clinic placement")
	check_eq(clinic_option.cost,Rules.CONSTRUCTION_COSTS.CLINIC,
		"construction cost is explicit in DTO")
	var before:Dictionary=session.sim.snapshot()
	var blocked:Dictionary=session.base_build("CLINIC",Vector2i(6,6))
	check_eq(blocked.reason,"base_building_reserved","reserved placement rejects")
	check_eq(session.sim.snapshot(),before,"rejected build is mutation-pure")
	var built:Dictionary=session.base_build("CLINIC",Vector2i(10,7))
	check(bool(built.accepted),"clinic builds on clear lot")
	check_eq(session.base_overview().stock,{"TIMBER":1,"STONE":0,"HERBS":0},
		"construction consumes secured stock exactly once")
	check_eq(session.base_build("CLINIC",Vector2i(4,2)).reason,
		"base_building_already_built","one building per functional type")
	check(session.town_clinic_assessment(
		int(session.sim.world.party_encounter.protagonist_id)).reason \
			!= "base_clinic_not_built","constructed clinic unlocks canonical service gate")
	check_eq(session.sim.world.world_state_error(),"","constructed world validates")
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.accepted),"construction journal loads: %s"%str(loaded))
	if bool(loaded.accepted):
		check_eq(restored.sim.snapshot(),session.sim.snapshot(),
			"build journal replay is snapshot exact")
		check_eq(restored.base_overview().settlement.buildings,
			session.base_overview().settlement.buildings,"layout replay is exact")
	return finish()


func test_unmarked_duo_save_migrates_to_complete_legacy_layout()->bool:
	var source=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(source.reset_party(44,20260828,Session.DUO_SCENARIO_ID,{},true,"human",false,false),
		"pre-settlement, pre-talent legacy fixture initializes")
	var wire:Dictionary=JSON.parse_string(source.save_session_json())
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(JSON.stringify(wire))
	check(bool(loaded.accepted),"unmarked DUO snapshot loads through legacy replay: %s"%str(loaded))
	if bool(loaded.accepted):
		var buildings:Array=restored.base_overview().settlement.buildings
		check_eq(buildings.size(),6,"legacy save keeps all previously available landmarks")
		for type_id in Rules.BUILDING_TYPES:
			check(Rules.type_built(buildings,type_id),"legacy layout retains %s"%type_id)
	return finish()


static func _option(rows:Array,type_id:String)->Dictionary:
	for row in rows:
		if str(row.get("type_id",""))==type_id:return row
	return {}
