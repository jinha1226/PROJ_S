extends RefCounted

const Grid=preload("res://sim/base_settlement_rules.gd")
const Ledger=preload("res://sim/base_progression_rules.gd")
const TERMINAL=["COMPLETED","CANCELLED"]
const KINDS=["GATHER","HAUL","BUILD","PRODUCE"]
static var path_searches:=0
const DIRECTIONS=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]

# The only authority is the event stream. Metadata is a disposable suffix index.
static func index(world)->Dictionary:
	var cache:Dictionary=world.get_meta("settlement_work_index",{})
	var count:int=world.events.size()
	if cache.is_empty() or int(cache.cursor)>count or (int(cache.cursor)>0 and cache.tail!=world.events[int(cache.cursor)-1]):
		cache={"cursor":0,"tail":null,"resource_revision":0,"state":empty_state(),"spent":Ledger.STARTER_STOCK.duplicate(),
			"gathered":{},"levels":{"STORAGE":1,"LODGE":1,"CLINIC":1},"buildings":[],
			"life":{"enabled":false,"house_owned":false,"members":[]},"topology_dirty":true,"ready":{"HEALING_POTION":0}}
	for n in range(int(cache.cursor),count):
		var event=world.events[n];var data:Dictionary=event.data
		if event.type=="town.life_started":
			cache.life.enabled=true;cache.life.members=[int(data.founder_id)]
			cache.life.house_owned=bool(data.get("frontier",false))
		elif event.type=="town.company_joined":
			var id:=int(data.entity_id)
			if id not in cache.life.members:cache.life.members.append(id)
		elif event.type=="town.house_acquired":cache.life.house_owned=true
		if event.type=="base.settlement_work_changed":
			if data.has("gathering"):cache.state["gathering"]=data.gathering.duplicate(true)
			for key in ["enabled","tick","next_job_id","last_step","last_time","schedule_revision"]:
				if data.has(key):cache.state[key]=data[key]
			for row in data.get("jobs",[]):
				var id:=str(row.job_id)
				if not cache.state.jobs.has(id):cache.state.jobs[id]={}
				cache.state.jobs[id].merge(row.duplicate(true),true)
			for row in data.get("residents",[]):
				var id:=str(row.entity_id)
				if not cache.state.residents.has(id):cache.state.residents[id]={}
				cache.state.residents[id].merge(row.duplicate(true),true)
		if event.type in ["base.local_resource_deposited","base.resource_gathered","base.resource_sold","dungeon.expedition_returned","party.expedition_auto_returned","base.building_constructed","base.facility_upgraded"]:cache.resource_revision=int(event.id)
		if event.type=="base.resource_gathered":
			var expedition:=str(data.expedition_index)
			if not cache.gathered.has(expedition):cache.gathered[expedition]={"TIMBER":0,"STONE":0,"HERBS":0}
			cache.gathered[expedition][str(data.resource_id)]+=int(data.amount)
		else:
			var delta:=Ledger.secured_stock([event],0,"TOWN")
			for resource in Ledger.RESOURCE_IDS:cache.spent[resource]+=int(delta[resource])-int(Ledger.STARTER_STOCK[resource])
		if event.type in ["base.settlement_initialized","base.building_constructed","base.facility_upgraded"]:
			cache.topology_dirty=true
		if event.type in ["base.production_completed","base.production_claimed"]:
			var recipe:=str(data.get("recipe_id",""))
			cache.ready[recipe]=int(cache.ready.get(recipe,0))+int(data.get("quantity",0))*(1 if event.type=="base.production_completed" else -1)
	cache.cursor=count;cache.tail=world.events[-1] if count>0 else null
	if cache.topology_dirty:
		cache.levels=Ledger.facility_levels(world.events)
		cache.buildings=Grid.buildings(world.events,cache.levels)
		cache.topology_dirty=false
	world.set_meta("settlement_work_index",cache)
	return cache

static func empty_state()->Dictionary:
	return {"enabled":false,"tick":0,"schedule_revision":0,"next_job_id":1,"last_step":-1,"last_time":-1,"jobs":{},"residents":{}}

static func state(world)->Dictionary:return index(world).state.duplicate(true)

static func active(state_value:Dictionary)->Array:
	var jobs:Array=[]
	for job in state_value.jobs.values():
		if str(job.state) not in TERMINAL:jobs.append(job)
	jobs.sort_custom(func(a,b):return int(a.job_id)<int(b.job_id))
	return jobs

static func stock(world,state_value:Dictionary={})->Dictionary:
	var cache:=index(world);var total:Dictionary=cache.spent.duplicate()
	var cycle=world.party_encounter.expedition_cycle
	for expedition in cache.gathered:
		if int(expedition)<int(cycle.expedition_index) or (int(expedition)==int(cycle.expedition_index) and cycle.phase=="TOWN"):
			for resource in Ledger.RESOURCE_IDS:total[resource]+=int(cache.gathered[expedition][resource])
	var reserved:Dictionary={"TIMBER":0,"STONE":0,"HERBS":0};var outside:Dictionary=reserved.duplicate()
	var value:Dictionary=cache.state if state_value.is_empty() else state_value
	for job in value.jobs.values():
		if not bool(job.get("materials_reserved",false)) or str(job.material_location)=="CONSUMED":continue
		for resource in Ledger.RESOURCE_IDS:
			reserved[resource]+=int(job.cost.get(resource,0))
			if str(job.material_location)!="STORAGE":outside[resource]+=int(job.cost.get(resource,0))
	var physical:=total.duplicate();var available:=total.duplicate()
	for resource in Ledger.RESOURCE_IDS:
		physical[resource]-=int(outside[resource]);available[resource]-=int(reserved[resource])
	return {"total":total,"physical":physical,"reserved":reserved,"available":available,"outside":outside}

static func obstacles(world,state_value:Dictionary)->Array:
	var result:Array=index(world).buildings.duplicate(true)
	for job in active(state_value):
		if str(job.action)=="BUILD" and not bool(job.get("cancel_requested",false)):
			result.append({"instance_id":"BLUEPRINT_%d"%int(job.job_id),"type_id":job.type_id,
				"tile_origin":job.tile_origin,"footprint":job.footprint})
	return result

static func route(start:Array,site:Array,footprint:Array,buildings:Array,slot:Array=[],occupied:Array=[])->Array:
	path_searches+=1
	var blocked:Dictionary={}
	for p in Grid.BLOCKED_TILES:blocked[p]=true
	for row in buildings:
		var rect:=Rect2i(int(row.tile_origin[0]),int(row.tile_origin[1]),int(row.footprint[0]),int(row.footprint[1]))
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):blocked[Vector2i(x,y)]=true
	for tile in occupied:blocked[Vector2i(int(tile[0]),int(tile[1]))]=true
	var target:=Rect2i(int(site[0]),int(site[1]),int(footprint[0]),int(footprint[1]))
	var first:=Vector2i(int(start[0]),int(start[1]));var queue:Array=[first];var parents:Dictionary={first:first}
	var cursor:=0;var goal:=Vector2i(-1,-1)
	while cursor<queue.size():
		var p:Vector2i=queue[cursor];cursor+=1
		if not blocked.has(p) and (p==Vector2i(int(slot[0]),int(slot[1])) if not slot.is_empty() else target.grow(1).has_point(p) and not target.has_point(p)):
			goal=p;break
		for d in DIRECTIONS:
			var next:Vector2i=p+d
			if Rect2i(0,0,16,16).has_point(next) and not blocked.has(next) and not parents.has(next):
				parents[next]=p;queue.append(next)
	if goal.x<0:return []
	var result:Array=[]
	while goal!=first:result.push_front([goal.x,goal.y]);goal=parents[goal]
	result.push_front(start.duplicate());return result

static func audit(state_value:Dictionary,stocks:Dictionary)->String:
	var workers:Dictionary={};var slots:Dictionary={};var facilities:Dictionary={}
	for resource in Ledger.RESOURCE_IDS:
		if int(stocks.available[resource])<0 or int(stocks.physical[resource])<0:return "settlement_negative_stock"
	for resident in state_value.residents.values():
		if int(resident.job_id)>=0:
			var id:=str(resident.job_id)
			if not state_value.jobs.has(id) or int(state_value.jobs[id].worker_id)!=int(resident.entity_id) or str(state_value.jobs[id].state) in TERMINAL:return "settlement_resident_job_mismatch"
		if resident.tile.size()!=2 or int(resident.tile[0])<0 or int(resident.tile[0])>=16 or int(resident.tile[1])<0 or int(resident.tile[1])>=16:return "settlement_resident_position_invalid"
	for job in state_value.jobs.values():
		for resource in job.cost:
			if resource not in Ledger.RESOURCE_IDS or int(job.cost[resource])<0:return "settlement_material_cost_invalid"
		if str(job.material_location) not in ["STORAGE","CARRIED","SITE","RECOVERY","CONSUMED"]:return "settlement_material_location_invalid"
		var facility_key:=str(job.get("facility_slot",""))
		if not facility_key.is_empty() and str(job.state) not in TERMINAL:
			if facilities.has(facility_key):return "settlement_duplicate_facility_slot"
			facilities[facility_key]=true
		if int(job.worker_id)>=0 and str(job.state) not in TERMINAL:
			if workers.has(str(job.worker_id)):return "settlement_duplicate_worker"
			var worker:=str(job.worker_id)
			if not state_value.residents.has(worker) or int(state_value.residents[worker].job_id)!=int(job.job_id):return "settlement_worker_job_mismatch"
			workers[str(job.worker_id)]=int(job.job_id)
		if not job.get("slot",[]).is_empty() and str(job.state) not in TERMINAL:
			var key:=str(job.slot)
			if slots.has(key):return "settlement_duplicate_slot"
			slots[key]=true
		if str(job.state)=="WORKING" and not job.cost.is_empty() and str(job.material_location)!="SITE":return "settlement_work_before_delivery"
	return ""

static func reason_label(reason:String)->String:
	return {"materials_missing":"자재 부족 · 보급 후 재개", "worker_unavailable":"작업 가능한 주민 대기",
		"priority_disabled":"작업 우선순위가 꺼져 있습니다", "path_missing":"통로가 막혀 있습니다",
		"path_or_slot_missing":"통로 또는 작업 자리 대기", "facility_slot_busy":"작업 자리 대기",
		"resident_in_way":"앞의 주민이 이동하기를 기다립니다", "return_materials":"미소비 자재 회수 대기"}.get(reason,"")

static func action_label(action:String)->String:
	return {"BUILD":"건설","UPGRADE":"증축","PRODUCE":"물약 제조","REST":"휴식","GATHER":"주변 채집"}.get(action,"작업")

static func status_label(job:Dictionary)->String:
	var reason:=reason_label(str(job.get("blocked_reason","")))
	if not reason.is_empty():return reason
	if bool(job.get("cancel_requested",false)):return "자재를 창고로 돌려보내는 중"
	if str(job.get("state",""))=="MOVING":
		return {"HAUL":"창고로 이동 중","HAUL_SITE":"자재 운반 중","RETURN":"자재 반환 중"}.get(str(job.stage),"작업 장소로 이동 중")
	return {"QUEUED":"작업 대기","RESERVED":"예약됨","WORKING":"작업 중","BLOCKED":"작업 대기","COMPLETED":"완료","CANCELLED":"취소됨"}.get(str(job.get("state","")),"작업 대기")
