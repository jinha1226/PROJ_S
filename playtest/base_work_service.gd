extends RefCounted

const Rules=preload("res://sim/base_work_rules.gd")
const Settlement=preload("res://sim/base_settlement_rules.gd")
const Production=preload("res://playtest/base_production_service.gd")
const Rest=preload("res://playtest/base_rest_service.gd")

static func commit(session,operation:Dictionary)->Dictionary:
	var error:=Rules.operation_error(operation)
	if not error.is_empty():return {"accepted":false,"reason":error}
	if session.sim==null or session.scenario_id!=session.DUO_SCENARIO_ID:
		return {"accepted":false,"reason":"base_scenario_unavailable"}
	if not session.private_home_available():return {"accepted":false,"reason":"private_home_required","message":"먼저 탐험대의 집을 구하세요. 휴식은 공공 여관에서 가능합니다."}
	var world=session.sim.world;var party=world.party_encounter
	if party.expedition_cycle.phase!="TOWN" or not world.is_settled():
		return {"accepted":false,"reason":"base_build_town_required"}
	var job:=Rules.current(world.events);var action:=str(operation.action)
	if action=="CLAIM":return Production.claim(session,str(operation.recipe_id))
	var data:Dictionary={};var worker_id:=-1
	if action in ["BUILD","UPGRADE","PRODUCE","REST"]:
		if not job.is_empty():return {"accepted":false,"reason":"base_work_busy","message":"진행 중인 작업을 먼저 마치거나 취소하세요."}
		var workers:Array=session.company_member_ids()
		if session.town_life_enabled():
			workers.sort_custom(func(a,b):return int(a in party.active_party_member_ids)<int(b in party.active_party_member_ids) if (a in party.active_party_member_ids)!=(b in party.active_party_member_ids) else int(a)<int(b))
		for id in workers:
			if worker_available(session,int(id)):worker_id=int(id);break
		if worker_id<0:return {"accepted":false,"reason":"base_worker_missing","message":"작업 가능한 주민이 없습니다."}
		var type_id:=str(operation.get("type_id",""))
		var buildings:Array=session.base_overview().settlement.buildings
		if action=="REST":
			data=Rest.assess(session,int(operation.entity_id))
			if not bool(data.get("accepted",false)):return data
			type_id="LODGE";worker_id=int(data.worker_id)
		elif action=="PRODUCE":
			data=Production.assess(session,str(operation.recipe_id))
			if not bool(data.get("accepted",false)):return data
			type_id=str(data.type_id)
		elif action=="BUILD":
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
		if action=="REST":route=Rest.route(buildings,Vector2i(int(data.tile_origin[0]),int(data.tile_origin[1])),
			Vector2i(int(data.footprint[0]),int(data.footprint[1])))
		if route.is_empty():return {"accepted":false,"reason":"base_building_blocks_access"}
		var production_recipe:=str(data.get("recipe_id",""))
		var work_steps:=int(data.get("work_steps",6))
		var gold_cost:=int(data.get("gold_cost",0))
		data={"schema_version":1,"action":action,"type_id":type_id,"cost":data.cost,
			"tile_origin":data.tile_origin,"footprint":data.footprint,"worker_id":worker_id,
			"route":route,"required":route.size()-1+work_steps,"from_level":int(data.get("from_level",0)),
			"to_level":int(data.get("to_level",1)),"instance_id":str(data.get("instance_id",""))}
		if action=="PRODUCE":data["recipe_id"]=production_recipe
		elif action=="REST":data["gold_cost"]=gold_cost
	elif job.is_empty():return {"accepted":false,"reason":"base_work_missing"}
	elif action=="TICK" and not worker_available(session,int(job.worker_id)):
		return {"accepted":false,"reason":"base_worker_missing"}
	var rollback:Variant=session.sim.capture_rollback_memento()
	if not rollback is Dictionary:return {"accepted":false,"reason":"snapshot_unavailable"}
	var event_start:int=world.events.size()
	var event;var completed:=false
	if action in ["BUILD","UPGRADE","PRODUCE","REST"]:
		event=world.emit_event("base.work_ordered",worker_id,-1,party.group_anchor,1,-1,data)
	elif action=="CANCEL":
		var refund:Dictionary={"cost":job.cost.duplicate(true)}
		if str(job.action)=="REST":refund["gold_cost"]=int(job.gold_cost)
		event=world.emit_event("base.work_cancelled",int(job.worker_id),-1,party.group_anchor,0,int(job.order_id),refund)
	else:
		job.progress=int(job.progress)+1
		event=world.emit_event("base.work_progressed",int(job.worker_id),-1,party.group_anchor,int(job.progress),int(job.order_id),{})
		if event!=null and int(job.progress)>=int(job.required):
			if str(job.action)=="REST":
				event=Rest.complete(session,job)
			elif str(job.action)=="PRODUCE":
				event=Production.complete(world,job)
			elif str(job.action)=="BUILD":
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
	var message:="주민이 작업을 진행합니다."
	if action=="REST":message="선택한 주민이 숙소로 이동합니다."
	if completed:message="회복 물약이 완성되었습니다. 진료소에서 가져가세요." if str(job.action)=="PRODUCE" else "시설이 완성되었습니다."
	if completed and str(job.action)=="REST":message="휴식을 마치고 마음이 안정되었습니다."
	elif action=="CANCEL":message="작업을 취소하고 재료를 돌려받았습니다."
	if action=="CANCEL" and str(job.action)=="REST":message="휴식을 취소하고 예약한 골드를 돌려받았습니다."
	return {"accepted":true,"reason":"ok","completed":completed,"message":message}

static func worker_available(session,id:int)->bool:
	var world=session.sim.world
	if world.can_act(id,world.world_time):return true
	if not session.town_life_enabled() or id not in session.company_member_ids():return false
	var body=world.combatant_states.get(id)
	return body!=null and body.life_state=="ACTIVE" and body.status_rows.is_empty() \
		and world.world_time>=body.recovery_lock_until
