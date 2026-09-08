class_name BaseSettlementService
extends RefCounted

var _session_ref:WeakRef
var _session:
	get:return _session_ref.get_ref()

func _init(session)->void:_session_ref=weakref(session)


func overview()->Dictionary:
	var levels:Dictionary=_session.BaseProgressionRulesScript.facility_levels(
		_session.sim.world.events)
	var rows:Array[Dictionary]=_session.BaseSettlementRulesScript.buildings(
		_session.sim.world.events,levels)
	var cycle=_session.sim.world.party_encounter.expedition_cycle
	var stock:Dictionary=_session.BaseProgressionRulesScript.secured_stock(
		_session.sim.world.events,int(cycle.expedition_index),str(cycle.phase))
	var options:Array[Dictionary]=[]
	for type_id in _session.BaseSettlementRulesScript.CONSTRUCTIBLE_TYPES:
		var built:bool=_session.BaseSettlementRulesScript.type_built(rows,type_id)
		var cost:Dictionary=_session.BaseSettlementRulesScript.CONSTRUCTION_COSTS[type_id].duplicate(true)
		var affordable:bool=_session.BaseProgressionRulesScript.can_afford(stock,cost)
		var in_town:bool=str(cycle.phase)=="TOWN"
		options.append({"type_id":type_id,
			"label":str(_session.BaseSettlementRulesScript.LABELS[type_id]),
			"footprint":_footprint_wire(type_id),"cost":cost,
			"can_build":not built and affordable and in_town,
			"message":"이미 건설했습니다." if built else (
				"마을에서 건설할 수 있습니다." if not in_town else (
					"건설 자원이 부족합니다." if not affordable else "빈 터를 선택하세요."))})
	return {"schema_version":_session.BaseSettlementRulesScript.SCHEMA_VERSION,
		"ruleset_id":_session.BaseSettlementRulesScript.RULESET_ID,
		"width":_session.BaseSettlementRulesScript.WIDTH,
		"height":_session.BaseSettlementRulesScript.HEIGHT,
		"tiles":_session.BaseSettlementRulesScript.tiles(),"buildings":rows,
		"build_options":options}.duplicate(true)


func build_assessment(type_id:String,tile_value:Variant)->Dictionary:
	if not _session.private_home_available():
		return {"accepted":false,"reason":"private_home_required","message":"여관에서 생활 중입니다. 먼저 탐험대의 집을 구하세요."}
	if _session.sim!=null and not preload("res://sim/base_work_rules.gd").current(_session.sim.world.events).is_empty():
		return {"accepted":false,"reason":"base_work_busy","message":"진행 중인 공사를 먼저 마치거나 취소하세요."}
	if _session==null or _session.sim==null or _session.sim.world==null:
		return _session._rejection_dto("session_not_initialized")
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:
		return _session._rejection_dto("base_scenario_unavailable")
	var cycle=_session.sim.world.party_encounter.expedition_cycle
	if cycle==null or str(cycle.phase)!="TOWN":
		return _session._rejection_dto("base_build_town_required")
	if type_id not in _session.BaseSettlementRulesScript.CONSTRUCTIBLE_TYPES:
		return _session._rejection_dto("base_building_type_unknown")
	var parsed:Dictionary=_tile_position(tile_value)
	if not bool(parsed.get("ok",false)):return _session._rejection_dto("base_building_position_invalid")
	var settlement:Dictionary=overview();var rows:Array=settlement.buildings
	if _session.BaseSettlementRulesScript.type_built(rows,type_id):
		return _session._rejection_dto("base_building_already_built")
	var cost:Dictionary=_session.BaseSettlementRulesScript.CONSTRUCTION_COSTS[type_id].duplicate(true)
	var stock:Dictionary=_session.BaseProgressionRulesScript.secured_stock(
		_session.sim.world.events,int(cycle.expedition_index),"TOWN")
	if not _session.BaseProgressionRulesScript.can_afford(stock,cost):
		return _session._rejection_dto("base_resources_insufficient")
	var tile_origin:Vector2i=parsed.position
	var placement_error:String=_session.BaseSettlementRulesScript.placement_error(
		type_id,tile_origin,0,rows)
	if not placement_error.is_empty():return _session._rejection_dto(placement_error)
	return _session._feedback_dto({"accepted":true,"reason":"ok","type_id":type_id,
		"tile_origin":[tile_origin.x,tile_origin.y],"footprint":_footprint_wire(type_id),
		"rotation":0,"cost":cost})


func build(type_id:String,tile_value:Variant)->Dictionary:
	var assessment:Dictionary=build_assessment(type_id,tile_value)
	if not bool(assessment.get("accepted",false)):return assessment
	var rollback:Dictionary=_session.sim.snapshot()
	if rollback.is_empty():return _session._rejection_dto("snapshot_unavailable")
	var state=_session.sim.world.party_encounter
	var rows:Array[Dictionary]=overview().buildings
	var instance_id:String=_session.BaseSettlementRulesScript.next_instance_id(rows,type_id)
	var building:Dictionary={"instance_id":instance_id,"type_id":type_id,
		"tile_origin":assessment.tile_origin.duplicate(true),"rotation":0}
	var event=_session.sim.world.emit_event("base.building_constructed",
		int(state.protagonist_id),-1,state.group_anchor,1,-1,
		{"schema_version":1,"ruleset_id":_session.BaseSettlementRulesScript.RULESET_ID,
			"building":building,"cost":assessment.cost.duplicate(true)})
	state.revision+=1;var error:String=_session.sim.world.world_state_error()
	if event==null or not error.is_empty():
		_session.sim=_session.SimulatorScript.from_snapshot(rollback)
		return _session._rejection_dto(error if not error.is_empty() else "base_build_failed")
	_session.command_journal.append({"kind":"base_settlement","operation":{
		"action":"BUILD","type_id":type_id,
		"tile_origin":assessment.tile_origin.duplicate(true)}})
	return _session._feedback_dto({"accepted":true,"reason":"ok",
		"event_id":int(event.id),"building":_building_by_id(instance_id),
		"settlement":overview()})


func type_built(type_id:String)->bool:
	if _session==null or _session.sim==null or _session.sim.world==null:return false
	var levels:Dictionary=_session.BaseProgressionRulesScript.facility_levels(_session.sim.world.events)
	return _session.BaseSettlementRulesScript.type_built(
		_session.BaseSettlementRulesScript.buildings(_session.sim.world.events,levels),type_id)


func _building_by_id(instance_id:String)->Dictionary:
	for row in overview().buildings:
		if str(row.instance_id)==instance_id:return row.duplicate(true)
	return {}


func _footprint_wire(type_id:String)->Array:
	var size:Vector2i=_session.BaseSettlementRulesScript.rotated_footprint(type_id,0)
	return [size.x,size.y]


static func _tile_position(value:Variant)->Dictionary:
	if value is Vector2i:return {"ok":true,"position":value}
	if value is Array and value.size()==2 and (value[0] is int or value[0] is float) \
			and (value[1] is int or value[1] is float) \
			and float(value[0])==floor(float(value[0])) \
			and float(value[1])==floor(float(value[1])) \
			and absf(float(value[0]))<=1024.0 and absf(float(value[1]))<=1024.0:
		return {"ok":true,"position":Vector2i(int(value[0]),int(value[1]))}
	return {"ok":false}
