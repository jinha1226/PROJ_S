extends RefCounted

const Rules=preload("res://sim/settlement_work_rules.gd")
const Grid=preload("res://sim/base_settlement_rules.gd")
const Ledger=preload("res://sim/base_progression_rules.gd")
const Production=preload("res://playtest/base_production_service.gd")
const Recipes=preload("res://sim/base_production_rules.gd")
const Rest=preload("res://playtest/base_rest_service.gd")
const Legacy=preload("res://playtest/legacy_base_work_service.gd")

static func reject(reason:String)->Dictionary:
	return {"accepted":false,"reason":reason,"message":{
		"base_building_already_built":"시설이나 청사진이 이미 있습니다.",
		"settlement_order_missing":"취소할 작업이 없습니다.",
		"settlement_legacy_pending":"기존 작업을 완료하거나 취소한 뒤 새 작업을 주문하세요.",
		"settlement_town_required":"거점에서 주문할 수 있습니다.",
		"settlement_rest_not_needed":"충분히 안정되어 있습니다.",
		"settlement_production_limit":"진행 중 주문과 완성품이 보관 한도에 도달했습니다."}.get(reason,reason)}

static func available(session,id:int)->bool:
	var world=session.sim.world;var party=world.party_encounter
	return id in session.company_member_ids() and Legacy.worker_available(session,id) \
		and (party.expedition_cycle.phase=="TOWN" or id not in party.active_party_member_ids)

static func needs_rest(world,id:int)->bool:
	var member=world.party_encounter.member(id)
	if member==null:return false
	return int(member.stress)>=600 or int(member.emotion_state.intensity("FEAR"))>=600 \
		or int(member.emotion_state.intensity("ANGER"))>=600 or int(member.emotion_state.intensity("SADNESS"))>=600

static func sync_residents(session,value:Dictionary)->void:
	var ids:Array=session.company_member_ids();ids.sort()
	for id in ids:
		var key:=str(id)
		if not value.residents.has(key):
			var spawn:Array=[7,7]
			for tile in [[7,7],[8,7],[6,7],[7,8],[8,8],[6,8],[9,7],[5,7],[9,8],[5,8],[10,7],[4,7]]:
				var occupied:=false
				for other in value.residents.values():
					if other.tile==tile:occupied=true
				if not occupied:spawn=tile.duplicate();break
			value.residents[key]={"entity_id":int(id),"tile":spawn,"job_id":-1,
				"priorities":{"HAUL":2,"BUILD":2,"PRODUCE":2},"rest_blocked":false,"retry_key":""}
	for resident in value.residents.values():
		if available(session,int(resident.entity_id)):continue
		if int(resident.job_id)<0:continue
		var job:Dictionary=value.jobs[str(resident.job_id)]
		release_worker(job,resident);value.schedule_revision=int(value.schedule_revision)+1

static func release_worker(job:Dictionary,resident:Dictionary)->void:
	if str(job.material_location)=="CARRIED":
		job.material_location="RECOVERY";job.material_tile=resident.tile.duplicate()
	job.worker_id=-1;job.route=[];job.route_cursor=0;job.slot=[];job.facility_slot=""
	job.state="BLOCKED";job.blocked_reason="worker_unavailable"
	resident.job_id=-1

static func assess(session,operation:Dictionary,value:Dictionary)->Dictionary:
	var world=session.sim.world;var action:=str(operation.action);var type_id:=str(operation.get("type_id",""))
	var buildings:Array=Rules.index(world).buildings
	var data:Dictionary={"cost":{},"gold_cost":0,"work_steps":6,"target_worker":-1}
	if action=="BUILD":
		var rows:=Rules.obstacles(world,value)
		if Grid.type_built(rows,type_id):return reject("base_building_already_built")
		var tile:=Vector2i(int(operation.tile_origin[0]),int(operation.tile_origin[1]))
		var error:=Grid.placement_error(type_id,tile,0,rows)
		if not error.is_empty():return reject(error)
		data.merge({"type_id":type_id,"tile_origin":[tile.x,tile.y],
			"footprint":[Grid.FOOTPRINTS[type_id].x,Grid.FOOTPRINTS[type_id].y],
			"cost":Grid.CONSTRUCTION_COSTS[type_id].duplicate(),"instance_id":Grid.next_instance_id(buildings,type_id)},true)
	elif action=="PRODUCE":
		var recipe:Dictionary=Recipes.RECIPES[str(operation.recipe_id)];type_id=str(recipe.facility_id)
		var count:int=Rules.index(world).ready[str(operation.recipe_id)]
		for job in Rules.active(value):
			if str(job.get("recipe_id",""))==str(operation.recipe_id) and not bool(job.cancel_requested):count+=int(recipe.quantity)
		if count>=int(recipe.stock_limit):return reject("settlement_production_limit")
		data.merge({"type_id":type_id,"cost":recipe.cost.duplicate(),"recipe_id":operation.recipe_id,"work_steps":recipe.work_steps},true)
	elif action=="REST":
		type_id="LODGE"
		var id:=int(operation.entity_id)
		if not available(session,id):return reject("base_worker_missing")
		var member=world.party_encounter.member(id)
		if member==null or (int(member.stress)<=0 and not needs_rest(world,id)):
			# The established overview also considers individual emotion values.
			var rows:=Rest.overview(session,buildings,{})
			var can_rest:=false
			for row in rows:
				if int(row.entity_id)==id:can_rest=bool(row.can_rest)
			if not can_rest:return reject("settlement_rest_not_needed")
		for job in Rules.active(value):
			if str(job.action)=="REST" and int(job.target_worker)==id:return reject("settlement_rest_already_ordered")
		if session.town_gold()<session.TOWN_SHRINE_COST:return reject("town_gold_insufficient")
		data.merge({"type_id":type_id,"gold_cost":session.TOWN_SHRINE_COST,"work_steps":Rest.WORK_STEPS,"target_worker":id},true)
	elif action=="UPGRADE":
		var from_level:int=Rules.index(world).levels[type_id]
		if from_level>=3:return reject("base_facility_max_level")
		for job in Rules.active(value):
			if str(job.action)=="UPGRADE" and str(job.type_id)==type_id:return reject("settlement_upgrade_already_ordered")
		data.merge({"type_id":type_id,"cost":Ledger.cost(type_id,from_level+1),"from_level":from_level,"to_level":from_level+1},true)
	if action!="BUILD":
		var found:=false
		for building in buildings:
			if str(building.type_id)==type_id:
				data["tile_origin"]=building.tile_origin.duplicate();data["footprint"]=building.footprint.duplicate();found=true;break
		if not found:return reject("base_facility_not_built")
	data["accepted"]=true;return data

static func new_job(world,value:Dictionary,action:String,data:Dictionary)->Dictionary:
	var id:=int(value.next_job_id);value.next_job_id=id+1
	var job:Dictionary={"job_id":id,"order_id":int(world._next_event_id),"action":action,"state":"QUEUED",
		"worker_id":-1,"created_tick":int(value.tick),"progress":0,"required":int(data.work_steps),
		"route":[],"route_cursor":0,"slot":[],"facility_slot":"","stage":"HAUL" if not data.cost.is_empty() else action,
		"blocked_reason":"","materials_reserved":false,"material_location":"STORAGE","material_tile":[],
		"cancel_requested":false,"recipe_id":"","from_level":0,"to_level":1,"instance_id":""}
	job.merge(data,true);job.erase("accepted");job.erase("work_steps")
	value.jobs[str(id)]=job;value.schedule_revision=int(value.schedule_revision)+1;return job

static func commit(session,operation:Dictionary)->Dictionary:
	if session.sim==null or session.scenario_id!=session.DUO_SCENARIO_ID:return reject("base_scenario_unavailable")
	var world=session.sim.world;var action:=str(operation.action)
	if not session.private_home_available():return reject("private_home_required")
	if world.party_encounter.expedition_cycle.phase!="TOWN":return reject("settlement_town_required")
	if not bool(Rules.index(world).state.enabled) and not preload("res://sim/base_work_rules.gd").legacy_current(world.events).is_empty():return reject("settlement_legacy_pending")
	if action=="CLAIM":
		var result:=Production.claim(session,str(operation.recipe_id))
		if result.accepted:session.command_journal[-1].operation=operation.duplicate(true)
		return result
	var before:=Rules.state(world);var value:=before.duplicate(true);value.enabled=true
	sync_residents(session,value)
	var selected:Dictionary={}
	if action!="TICK":value.schedule_revision=int(value.schedule_revision)+1
	if action in ["BUILD","UPGRADE","PRODUCE","REST"]:
		var data:=assess(session,operation,value)
		if not bool(data.get("accepted",false)):return data
		selected=new_job(world,value,action,data)
	elif action=="CANCEL":
		var id:=str(operation.get("job_id",-1))
		if value.jobs.has(id) and str(value.jobs[id].state) not in Rules.TERMINAL:selected=value.jobs[id]
		elif not operation.has("job_id"):
			var jobs:=Rules.active(value)
			if not jobs.is_empty():selected=jobs[0]
		if selected.is_empty() or bool(selected.cancel_requested):return reject("settlement_order_missing")
		selected.cancel_requested=true
		if int(selected.worker_id)>=0:release_worker(selected,value.residents[str(selected.worker_id)])
		if str(selected.material_location)=="STORAGE" or not bool(selected.materials_reserved):
			selected.state="CANCELLED";selected.materials_reserved=false;selected.blocked_reason=""
		else:
			selected.state="BLOCKED";selected.blocked_reason="return_materials";selected.stage="RETURN"
			selected.material_location="RECOVERY"
	elif action=="PRIORITY":
		var id:=str(operation.entity_id)
		if not value.residents.has(id):return reject("base_worker_missing")
		value.residents[id].priorities[str(operation.kind)]=int(operation.priority)
	elif action!="TICK":return reject("invalid_base_work_operation")
	var rollback:=transaction_image(world)
	if not world.is_settled():return reject("snapshot_unavailable")
	var start:int=world.events.size();var completed:=false
	if action=="TICK":
		var result:=advance_state(session,value)
		if not bool(result.accepted):restore_transaction(world,rollback);return result
		completed=bool(result.completed)
	if not selected.is_empty() and action=="REST":
		if world.emit_event("base.settlement_rest_reserved",int(selected.target_worker),-1,world.party_encounter.group_anchor,int(selected.gold_cost),-1,{"gold_cost":int(selected.gold_cost)})==null:
			restore_transaction(world,rollback);return reject("settlement_event_failed")
	if not selected.is_empty() and action=="CANCEL" and str(selected.action)=="REST":
		world.emit_event("base.rest_payment_released",int(selected.target_worker),-1,world.party_encounter.group_anchor,int(selected.gold_cost),int(selected.order_id),{"gold_cost":int(selected.gold_cost)})
	var error:=persist(world,before,value)
	if error.is_empty():error=postcondition(world,start,rollback)
	if not error.is_empty():restore_transaction(world,rollback);return reject(error)
	session.command_journal.append({"kind":"base_work","operation":operation.duplicate(true)})
	return {"accepted":true,"reason":"ok","completed":completed,"job_id":int(selected.get("job_id",-1)),
		"message":"작업 완료 · 시설과 완성품을 확인하세요." if completed else ("미소비 재료를 회수합니다." if action=="CANCEL" else "주민 작업 설정을 저장했습니다.")}

# This service changes only settlement events, party revision and rest emotions.
# Do not copy the entire dungeon/history for each half-second base tick.
static func transaction_image(world)->Dictionary:
	var members:Array=[]
	for member in world.party_encounter.member_rows.values():
		members.append({"member":member,"emotion":member.emotion_state,"stress":int(member.stress),"mode":str(member.mental_mode)})
	return {"event_count":world.events.size(),"next_event_id":world._next_event_id,"revision":world.party_encounter.revision,"members":members}

static func restore_transaction(world,image:Dictionary)->void:
	world.events.resize(int(image.event_count));world._next_event_id=int(image.next_event_id)
	world.party_encounter.revision=int(image.revision)
	for row in image.members:
		row.member.emotion_state=row.emotion;row.member.stress=int(row.stress);row.member.mental_mode=str(row.mode)
	world.remove_meta("settlement_work_index")
	if world.has_meta("town_gold_index"):world.remove_meta("town_gold_index")

static func postcondition(world,start:int,image:Dictionary)->String:
	if not world.is_settled() or int(world._next_event_id)!=world.events.size()+1:return "settlement_event_sequence_invalid"
	for n in range(start,world.events.size()):
		var event=world.events[n]
		if int(event.id)!=n+1 or int(event.step_index)!=int(world.step_index) or int(event.world_time)!=int(world.world_time):return "settlement_event_tail_invalid"
		if not world._is_valid_event_data(event.data):return "settlement_event_data_invalid"
		if int(event.cause_id)>=0:
			var cause=world.event_by_id(int(event.cause_id))
			if cause==null or int(cause.id)>=int(event.id) or int(cause.instigator_id)!=int(event.instigator_id):return "settlement_cause_invalid"
	for row in image.members:
		if row.member.emotion_state!=row.emotion:
			var error:=preload("res://sim/party_emotion_state.gd").wire_error(row.member.emotion_state.to_dict())
			if not error.is_empty():return error
		if int(row.member.stress)<0 or int(row.member.stress)>1000:return "settlement_stress_invalid"
	return ""

static func changed_row(before:Dictionary,after:Dictionary,id_field:String)->Dictionary:
	var patch:Dictionary={id_field:after[id_field]}
	for key in after:
		if before.has(key) and before[key]==after[key]:continue
		var value:Variant=after[key]
		patch[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	return patch

static func persist(world,before:Dictionary,value:Dictionary)->String:
	var error:=Rules.audit(value,Rules.stock(world,value))
	if not error.is_empty():return error
	var delta:Dictionary={"enabled":value.enabled,"tick":value.tick,"next_job_id":value.next_job_id,
		"last_step":value.last_step,"last_time":value.last_time,"schedule_revision":value.schedule_revision,"jobs":[],"residents":[]}
	for id in value.jobs:
		if not before.jobs.has(id) or before.jobs[id]!=value.jobs[id]:delta.jobs.append(changed_row(before.jobs.get(id,{}),value.jobs[id],"job_id"))
	for id in value.residents:
		if not before.residents.has(id) or before.residents[id]!=value.residents[id]:delta.residents.append(changed_row(before.residents.get(id,{}),value.residents[id],"entity_id"))
	var event=world.emit_event("base.settlement_work_changed",-1,-1,Vector2i(-1,-1),0,-1,delta)
	if event==null:return "settlement_event_failed"
	world.party_encounter.revision+=1
	return ""

static func storage(world)->Dictionary:
	for building in Rules.index(world).buildings:
		if str(building.type_id)=="STORAGE":return building
	return {}

static func occupied_tiles(session,value:Dictionary,except_id:int)->Array:
	var tiles:Array=[]
	for resident in value.residents.values():
		if int(resident.entity_id)!=except_id and available(session,int(resident.entity_id)):tiles.append(resident.tile)
	return tiles

static func movement_target(world,job:Dictionary)->Dictionary:
	if str(job.material_location)=="RECOVERY":return {"site":job.material_tile,"footprint":[1,1]}
	if str(job.stage) in ["HAUL","RETURN"]:
		var store:=storage(world);return {"site":store.tile_origin,"footprint":store.footprint}
	return {"site":job.tile_origin,"footprint":job.footprint}

static func retry_key(world,value:Dictionary)->String:
	return "%d:%d:%s:%d"%[int(value.schedule_revision),int(Rules.index(world).resource_revision),str(world.party_encounter.expedition_cycle.phase),int(world.world_time)]

static func assign(session,value:Dictionary,resident:Dictionary)->void:
	var key:=retry_key(session.sim.world,value)
	if str(resident.get("retry_key",""))==key:return
	resident.retry_key=key
	var world=session.sim.world;var best:Dictionary={};var candidates:Array=[]
	resident.rest_blocked=false
	var required_rest:=needs_rest(world,int(resident.entity_id))
	var available_stock:Dictionary=Rules.stock(world,value).available
	var member=world.party_encounter.member(int(resident.entity_id));var personality:=500
	if member!=null and member.personality_profile!=null:
		personality=member.personality_profile.value("C")
		if personality<0:personality=member.personality_profile.value("composure")
		if personality<0:personality=500
	for job in Rules.active(value):
		if int(job.worker_id)>=0:continue
		if int(job.target_worker)>=0 and int(job.target_worker)!=int(resident.entity_id):continue
		if required_rest and str(job.action)!="REST":resident.rest_blocked=true;continue
		var kind:=str(job.stage)
		if kind in ["RETURN","HAUL"] or str(job.material_location)=="RECOVERY":kind="HAUL"
		elif str(job.action)=="UPGRADE":kind="BUILD"
		elif str(job.action)=="PRODUCE":kind="PRODUCE"
		var priority:=3 if str(job.action)=="REST" else int(resident.priorities.get(kind,0))
		if priority==0:job.blocked_reason="priority_disabled";job.state="BLOCKED";continue
		if not job.cost.is_empty() and not bool(job.materials_reserved):
			if not Ledger.can_afford(available_stock,job.cost):
				job.state="BLOCKED";job.blocked_reason="materials_missing";continue
		var score:=priority*100000+mini(1000,int(value.tick)-int(job.created_tick))*10+(int(personality/100) if kind in ["BUILD","PRODUCE"] else 10-int(personality/100))
		score-=absi(int(resident.tile[0])-int(job.tile_origin[0]))+absi(int(resident.tile[1])-int(job.tile_origin[1]))
		if str(job.action)=="REST":score+=1000000
		candidates.append({"score":score,"job":job})
	candidates.sort_custom(func(a,b):return int(a.score)>int(b.score) if int(a.score)!=int(b.score) else int(a.job.job_id)<int(b.job.job_id))
	var path:Array=[]
	for candidate in candidates:
		var job:Dictionary=candidate.job
		var facility_key:=""
		if str(job.action) in ["PRODUCE","REST"] and str(job.stage) not in ["HAUL","RETURN","HAUL_SITE"] and str(job.material_location)!="RECOVERY":
			facility_key=str(job.type_id)+":"+str(job.action)
			var busy:=false
			for other in Rules.active(value):
				if str(other.get("facility_slot",""))==facility_key:busy=true
			if busy:job.state="BLOCKED";job.blocked_reason="facility_slot_busy";continue
		var site:Array=job.tile_origin;var footprint:Array=job.footprint
		if str(job.material_location)=="RECOVERY":site=job.material_tile;footprint=[1,1]
		elif str(job.stage) in ["HAUL","RETURN"]:
			var store:=storage(world);site=store.tile_origin;footprint=store.footprint
		var occupied:=occupied_tiles(session,value,int(resident.entity_id))
		for other in Rules.active(value):
			if not other.slot.is_empty():occupied.append(other.slot)
		path=Rules.route(resident.tile,site,footprint,Rules.obstacles(world,value),[],occupied)
		if path.is_empty():job.state="BLOCKED";job.blocked_reason="path_or_slot_missing";continue
		best=job;best.facility_slot=facility_key
		if str(best.stage) not in ["HAUL","RETURN"] and str(best.material_location)!="RECOVERY":best.slot=path[-1].duplicate()
		break
	if best.is_empty():return
	best.worker_id=int(resident.entity_id);resident.job_id=int(best.job_id);value.schedule_revision=int(value.schedule_revision)+1
	best.route=path;best.route_cursor=0;best.state="MOVING";best.blocked_reason=""
	if not best.cost.is_empty() and not bool(best.materials_reserved):best.materials_reserved=true

static func advance_state(session,value:Dictionary)->Dictionary:
	var world=session.sim.world;value.tick=int(value.tick)+1
	sync_residents(session,value)
	# Forced rest is paid through the existing lodge transaction. No invented fatigue meter.
	for resident in value.residents.values():
		var id:=int(resident.entity_id)
		if not available(session,id):continue
		if needs_rest(world,id):
			if int(resident.job_id)>=0:
				var current:Dictionary=value.jobs[str(resident.job_id)]
				if str(current.action)!="REST":release_worker(current,resident);value.schedule_revision=int(value.schedule_revision)+1
			var has_rest:=false
			for job in Rules.active(value):
				if str(job.action)=="REST" and int(job.target_worker)==id:has_rest=true
			if not has_rest and session.town_gold()>=session.TOWN_SHRINE_COST:
				var assessed:=assess(session,{"action":"REST","entity_id":id},value)
				if bool(assessed.get("accepted",false)):
					var rest_job:=new_job(world,value,"REST",assessed)
					# Cause references require the order boundary to exist before completion.
					var reserved=world.emit_event("base.settlement_rest_reserved",id,-1,world.party_encounter.group_anchor,int(rest_job.gold_cost),-1,{"gold_cost":int(rest_job.gold_cost)})
					if reserved==null:return reject("settlement_event_failed")
					rest_job.order_id=int(reserved.id)
		if int(resident.job_id)<0:assign(session,value,resident)
	var completed:=false
	for resident in value.residents.values():
		if int(resident.job_id)<0 or not available(session,int(resident.entity_id)):continue
		var job:Dictionary=value.jobs[str(resident.job_id)]
		if str(job.state)=="MOVING":
			if int(job.route_cursor)<job.route.size()-1:
				var next:Array=job.route[int(job.route_cursor)+1];var occupied:=false
				for other in value.residents.values():
					if int(other.entity_id)!=int(resident.entity_id) and available(session,int(other.entity_id)) and other.tile==next:occupied=true
				var buildings:=Rules.obstacles(world,value)
				for building in buildings:
					if Rect2i(int(building.tile_origin[0]),int(building.tile_origin[1]),int(building.footprint[0]),int(building.footprint[1])).has_point(Vector2i(int(next[0]),int(next[1]))):occupied=true
				if occupied:
					job.blocked_reason="resident_in_way"
					var target:=movement_target(world,job)
					var retry:=Rules.route(resident.tile,target.site,target.footprint,buildings,job.slot,occupied_tiles(session,value,int(resident.entity_id)))
					if not retry.is_empty():job.route=retry;job.route_cursor=0
					else:
						release_worker(job,resident);job.blocked_reason="path_missing";value.schedule_revision=int(value.schedule_revision)+1
					continue
				resident.tile=next.duplicate();job.route_cursor=int(job.route_cursor)+1;job.blocked_reason="";value.schedule_revision=int(value.schedule_revision)+1
				if str(job.material_location)=="CARRIED":job.material_tile=resident.tile.duplicate()
				continue
			if str(job.material_location)=="RECOVERY":
				job.material_location="CARRIED";job.stage="RETURN" if bool(job.cancel_requested) else "HAUL_SITE"
			elif str(job.stage)=="HAUL":
				value.schedule_revision=int(value.schedule_revision)+1
				job.material_location="CARRIED";job.stage="HAUL_SITE"
			elif str(job.stage)=="RETURN":
				value.schedule_revision=int(value.schedule_revision)+1
				job.material_location="STORAGE";job.materials_reserved=false;job.material_tile=[]
				job.state="CANCELLED" if bool(job.cancel_requested) else "QUEUED"
				job.stage="HAUL";job.worker_id=-1;job.slot=[];job.facility_slot="";resident.job_id=-1;continue
			elif str(job.stage)=="HAUL_SITE":
				value.schedule_revision=int(value.schedule_revision)+1
				job.material_location="SITE";job.material_tile=job.tile_origin.duplicate()
				job.stage="BUILD" if str(job.action)=="UPGRADE" else str(job.action)
				job.state="QUEUED";job.worker_id=-1;resident.job_id=-1;continue
			else:job.state="WORKING";continue
			var site:Array=job.tile_origin;var footprint:Array=job.footprint
			if str(job.stage)=="RETURN":
				var store:=storage(world);site=store.tile_origin;footprint=store.footprint
			var path:=Rules.route(resident.tile,site,footprint,Rules.obstacles(world,value),[],occupied_tiles(session,value,int(resident.entity_id)))
			if path.is_empty():release_worker(job,resident);job.blocked_reason="path_missing";continue
			job.route=path;job.route_cursor=0;job.material_tile=resident.tile.duplicate();continue
		if str(job.state)!="WORKING":continue
		job.progress=int(job.progress)+1
		if int(job.progress)<int(job.required):continue
		var result:=complete(session,job)
		if not bool(result.accepted):return result
		job.state="COMPLETED";job.material_location="CONSUMED";job.materials_reserved=false
		job.worker_id=-1;job.slot=[];job.facility_slot="";resident.job_id=-1;completed=true;value.schedule_revision=int(value.schedule_revision)+1
	return {"accepted":true,"completed":completed}

static func complete(session,job:Dictionary)->Dictionary:
	var world=session.sim.world;var party=world.party_encounter;var event
	if str(job.action)=="REST":event=Rest.complete(session,job)
	elif str(job.action)=="PRODUCE":event=Production.complete(world,job)
	elif str(job.action)=="BUILD":
		event=world.emit_event("base.building_constructed",int(job.worker_id),-1,party.group_anchor,1,int(job.order_id),
			{"schema_version":1,"ruleset_id":Grid.RULESET_ID,"cost":{},"building":{
				"instance_id":str(job.instance_id),"type_id":str(job.type_id),"tile_origin":job.tile_origin.duplicate(),"rotation":0}})
	else:
		event=world.emit_event("base.facility_upgraded",int(job.worker_id),-1,party.group_anchor,int(job.to_level),int(job.order_id),
			{"schema_version":1,"ruleset_id":Ledger.RULESET_ID,"facility_id":str(job.type_id),"from_level":int(job.from_level),"to_level":int(job.to_level),"cost":{}})
	if event==null:return reject("settlement_completion_failed")
	if not job.cost.is_empty():
		event=world.emit_event("base.settlement_material_consumed",int(job.worker_id),-1,party.group_anchor,0,int(job.order_id),{"cost":job.cost.duplicate(),"job_id":int(job.job_id)})
		if event==null:return reject("settlement_consumption_failed")
	return {"accepted":true}

# Called inside the owning expedition transaction; no separate journal row.
static func expedition_advance(session)->Dictionary:
	var world=session.sim.world;var before:=Rules.state(world)
	if not bool(before.enabled) or world.party_encounter.expedition_cycle.phase!="DUNGEON":return {"accepted":true}
	if int(before.last_step)==int(world.step_index) and int(before.last_time)==int(world.world_time):return {"accepted":true}
	var value:=before.duplicate(true)
	value.last_step=int(world.step_index);value.last_time=int(world.world_time)
	var result:=advance_state(session,value)
	if not bool(result.accepted):return result
	var error:=persist(world,before,value)
	return {"accepted":error.is_empty(),"reason":error}

static func release_assigned(session)->String:
	var world=session.sim.world;var before:=Rules.state(world)
	if not bool(before.enabled):return ""
	var value:=before.duplicate(true);sync_residents(session,value)
	value.last_step=int(world.step_index);value.last_time=int(world.world_time)
	for resident in value.residents.values():
		if int(resident.entity_id) not in world.party_encounter.active_party_member_ids or int(resident.job_id)<0:continue
		release_worker(value.jobs[str(resident.job_id)],resident);value.schedule_revision=int(value.schedule_revision)+1
	return persist(world,before,value)
