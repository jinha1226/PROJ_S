extends RefCounted

const Rules=preload("res://sim/base_work_rules.gd")
const Settlement=preload("res://sim/base_settlement_rules.gd")

static func commit(session,operation:Dictionary)->Dictionary:
	var error:=Rules.operation_error(operation)
	if not error.is_empty():return {"accepted":false,"reason":error}
	if session.sim==null or session.scenario_id!=session.DUO_SCENARIO_ID:
		return {"accepted":false,"reason":"base_scenario_unavailable"}
	var world=session.sim.world;var party=world.party_encounter
	if party.expedition_cycle.phase!="TOWN" or not world.is_settled():
		return {"accepted":false,"reason":"base_build_town_required"}
	var job:=Rules.current(world.events);var action:=str(operation.action)
	var data:Dictionary={};var worker_id:=-1
	if action in ["BUILD","UPGRADE"]:
		if not job.is_empty():return {"accepted":false,"reason":"base_work_busy","message":"진행 중인 공사를 먼저 마치거나 취소하세요."}
		for id in party.active_party_member_ids:
			if world.can_act(id,world.world_time):worker_id=int(id);break
		if worker_id<0:return {"accepted":false,"reason":"base_worker_missing","message":"작업 가능한 주민이 없습니다."}
		var type_id:=str(operation.type_id)
		var buildings:Array=session.base_overview().settlement.buildings
		if action=="BUILD":
			var assessed:Dictionary=session.base_build_assessment(type_id,operation.tile_origin)
			if not bool(assessed.get("accepted",false)):return assessed
			data=assessed.duplicate(true)
			data["instance_id"]=Settlement.next_instance_id(buildings,type_id)
		else:
			for facility in session.base_overview().facilities:
				if str(facility.id)==type_id:
					if not bool(facility.can_upgrade):return {"accepted":false,"reason":"base_upgrade_unavailable","message":str(facility.message)}
					data={"cost":facility.cost.duplicate(true),"from_level":int(facility.level),"to_level":int(facility.level)+1}
			for building in buildings:
				if str(building.type_id)==type_id:
					data["tile_origin"]=building.tile_origin.duplicate();data["footprint"]=building.footprint.duplicate()
			if not data.has("cost") or not data.has("tile_origin"):return {"accepted":false,"reason":"base_facility_not_built"}
		var route:=Rules.route_to_site(buildings,Vector2i(int(data.tile_origin[0]),int(data.tile_origin[1])),
			Vector2i(int(data.footprint[0]),int(data.footprint[1])))
		if route.is_empty():return {"accepted":false,"reason":"base_building_blocks_access"}
		data={"schema_version":1,"action":action,"type_id":type_id,"cost":data.cost,
			"tile_origin":data.tile_origin,"footprint":data.footprint,"worker_id":worker_id,
			"route":route,"required":route.size()-1+6,"from_level":int(data.get("from_level",0)),
			"to_level":int(data.get("to_level",1)),"instance_id":str(data.get("instance_id",""))}
	elif job.is_empty():return {"accepted":false,"reason":"base_work_missing"}
	elif action=="TICK" and not world.can_act(int(job.worker_id),world.world_time):
		return {"accepted":false,"reason":"base_worker_missing"}
	var rollback:Variant=session.sim.capture_rollback_memento()
	if not rollback is Dictionary:return {"accepted":false,"reason":"snapshot_unavailable"}
	var event_start:int=world.events.size()
	var event;var completed:=false
	if action in ["BUILD","UPGRADE"]:
		event=world.emit_event("base.work_ordered",worker_id,-1,party.group_anchor,1,-1,data)
	elif action=="CANCEL":
		event=world.emit_event("base.work_cancelled",int(job.worker_id),-1,party.group_anchor,0,int(job.order_id),{"cost":job.cost.duplicate(true)})
	else:
		job.progress=int(job.progress)+1
		event=world.emit_event("base.work_progressed",int(job.worker_id),-1,party.group_anchor,int(job.progress),int(job.order_id),{})
		if event!=null and int(job.progress)>=int(job.required):
			if str(job.action)=="BUILD":
				event=world.emit_event("base.building_constructed",int(job.worker_id),-1,party.group_anchor,1,int(job.order_id),
					{"schema_version":1,"ruleset_id":Settlement.RULESET_ID,"cost":{},"building":{
						"instance_id":str(job.instance_id),"type_id":str(job.type_id),"tile_origin":job.tile_origin.duplicate(),"rotation":0}})
			else:
				event=world.emit_event("base.facility_upgraded",int(job.worker_id),-1,party.group_anchor,int(job.to_level),int(job.order_id),
					{"schema_version":1,"ruleset_id":session.BaseProgressionRulesScript.RULESET_ID,"facility_id":str(job.type_id),
						"from_level":int(job.from_level),"to_level":int(job.to_level),"cost":{}})
			if event!=null:
				event=world.emit_event("base.work_completed",int(job.worker_id),-1,party.group_anchor,1,int(job.order_id),{})
				completed=event!=null
	party.revision+=1
	error=world.runtime_step_postcondition_error(event_start)
	if event==null or not error.is_empty():
		session.sim.restore_rollback_memento(rollback)
		return {"accepted":false,"reason":error if not error.is_empty() else "base_work_failed"}
	session.command_journal.append({"kind":"base_work","operation":operation.duplicate(true)})
	return {"accepted":true,"reason":"ok","completed":completed,
		"message":"시설이 완성되었습니다." if completed else ("공사를 취소하고 재료를 돌려받았습니다." if action=="CANCEL" else "주민이 공사를 진행합니다.")}
