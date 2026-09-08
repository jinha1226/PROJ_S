extends RefCounted
## Lightweight neutral expeditions: stable residents, seeded floor placement,
## slow safe patrols, and remembered encounters. Not extra allied combat AI.
const Rules=preload("res://sim/town_population_rules.gd")
const Life=preload("res://sim/town_life_rules.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
const Items=preload("res://sim/world_item_operations.gd")

static func enter(session,layout:Dictionary)->bool:
	if not session.town_life_enabled():return true
	var world=session.sim.world;var party=world.party_encounter;var rows:Array=[]
	var company:Array=session.company_member_ids()
	var candidates:Array=[]
	for id in party.party_member_ids:
		if id in company or party.member(id).presence!="RECRUITABLE":continue
		if Rules.identity(str(world.entities[id].display_name)).explores:candidates.append(id)
	var occupied:Array=[]
	var entry:Vector2i=layout.entry_position
	var seeds:Array[Vector2i]=[entry+Vector2i(3,2),entry+Vector2i(-3,3)]
	for cache in session._base_progression_service._base_cache_rows():
		var p:Array=cache.position
		seeds.append(Vector2i(int(p[0]),int(p[1]))+Vector2i(2,0))
	for index in range(mini(Rules.FLOOR_COUNT,candidates.size())):
		var seed:Vector2i=seeds[index%seeds.size()]
		var chosen:=Vector2i(-1,-1)
		for radius in range(0,9):
			for dy in range(-radius,radius+1):
				for dx in range(-radius,radius+1):
					var p:=seed+Vector2i(dx,dy)
					if p in occupied or not _safe(world,p,entry):continue
					var close:=false
					for used in occupied:
						if _distance(p,used)<3:close=true;break
					if close:continue
					chosen=p;break
				if chosen.x>=0:break
			if chosen.x>=0:break
		if chosen.x<0:continue
		occupied.append(chosen)
		rows.append({"entity_id":str(candidates[index]),"position":[chosen.x,chosen.y],
			"anchor":[chosen.x,chosen.y],"needs_supplies":index%4==0,"activity":"물자가 떨어져 대기 중" if index%4==0 else "주변 탐색 중"})
	return _emit(world,"population.floor_arrived",rows)!=null

static func _safe(world,p:Vector2i,entry:Vector2i)->bool:
	if not world.in_bounds(p) or _distance(p,entry)<2:return false
	var tile=world.tile_at(p)
	if not Terrain.definition(str(tile.terrain)).get("passable",false) or tile.fire>0 or tile.wetness>0:return false
	if not world.occupying_entities_at(p).is_empty():return false
	for id in world.party_encounter.enemy_ids:
		if world.is_unresolved_enemy(id) and _distance(p,world.entities[id].position)<5:return false
	return true

static func advance(session)->void:
	if not session.town_life_enabled():return
	var world=session.sim.world;var party=world.party_encounter
	if party.expedition_cycle.phase!="DUNGEON" or party.safe_phase not in ["GROUPED","GROUPED_COMPLETE"]:return
	var rows:=Rules.locations(world)
	if rows.is_empty():return
	var last_time:=0
	for index in range(world.events.size()-1,-1,-1):
		if world.events[index].type in ["population.patrol","population.floor_arrived"]:
			last_time=int(world.events[index].world_time);break
	if world.world_time-last_time<Rules.PATROL_INTERVAL:return
	var directions:=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
	var used:Array=[]
	for row in rows:used.append(Vector2i(int(row.position[0]),int(row.position[1])))
	for row in rows:
		if bool(row.needs_supplies):continue
		var p:=Vector2i(int(row.position[0]),int(row.position[1]))
		var anchor:=Vector2i(int(row.anchor[0]),int(row.anchor[1]))
		var profile=party.member(int(row.entity_id)).personality_profile
		var radius:=3 if profile.value("O")>=500 else 1
		for offset in range(4):
			var next:Vector2i=p+directions[posmod(int(row.entity_id)+int(world.world_time/Rules.PATROL_INTERVAL)+offset,4)]
			if next in used or _distance(next,anchor)>radius or not _safe(world,next,party.group_anchor):continue
			used.erase(p);used.append(next);row.position=[next.x,next.y];break
	_emit(world,"population.patrol",rows)

static func assess(session,id:int)->Dictionary:
	var world=session.sim.world;var party=world.party_encounter
	var row:Dictionary={}
	for visitor in Rules.locations(world):
		if int(visitor.entity_id)==id:row=visitor;break
	if row.is_empty():return {"accepted":false,"message":"이 층에 있는 인물이 아닙니다"}
	var greeted:=false;var helped:=false
	for event in world.events:
		if event.target_id!=id or int(event.data.get("expedition_index",0))!=int(party.expedition_cycle.expedition_index):continue
		if event.type=="population.greeted":greeted=true
		if event.type=="population.assisted":helped=true
	var player=world.entities[world.party_control_actor_id()]
	var nearby:bool=_distance(player.position,Vector2i(int(row.position[0]),int(row.position[1])))<=1
	var safe:bool=party.safe_phase in ["GROUPED","GROUPED_COMPLETE"]
	var supply:=_ration(world,world.party_control_actor_id())
	return {"accepted":true,"nearby":nearby,"can_greet":nearby and safe and not greeted,
		"can_aid":nearby and safe and bool(row.needs_supplies) and not helped and not supply.is_empty(),
		"needs_supplies":bool(row.needs_supplies) and not helped,"greeted":greeted,"helped":helped,
		"activity":"물자를 받고 귀환 준비 중" if helped else str(row.activity),
		"message":"바로 옆에서 이야기할 수 있습니다" if not nearby else (
			"식량 1개로 귀환을 도울 수 있습니다" if row.needs_supplies and not helped else "마을에서 다시 만나 동행을 제안할 수 있습니다")}

static func interact(session,operation:Dictionary)->Dictionary:
	var error:=Rules.interaction_error(operation)
	if not error.is_empty():return {"accepted":false,"reason":error}
	var id:=int(operation.entity_id);var action:=str(operation.action)
	var view:=assess(session,id)
	if not view.get("can_aid" if action=="AID" else "can_greet",false):return {"accepted":false,"reason":"visitor_interaction_unavailable","message":view.get("message","지금은 만날 수 없습니다")}
	var world=session.sim.world;var party=world.party_encounter
	var captured:Variant=session.sim.snapshot()
	if not captured is Dictionary or captured.is_empty():return {"accepted":false,"reason":"snapshot_unavailable"}
	var rollback:Dictionary=captured
	var leader:int=world.party_control_actor_id();var ok:=true
	if action=="AID":ok=bool(Items.commit_use(world,leader,_ration(world,leader),world.entities[leader].position,0).get("accepted",false))
	var event=world.emit_event("population.assisted" if action=="AID" else "population.greeted",leader,id,
		world.entities[leader].position,30 if action=="AID" else 10,-1,
		{"entity_id":str(id),"expedition_index":int(party.expedition_cycle.expedition_index)})
	ok=ok and event!=null and session.sim.relationships.record_aid(id,leader,event.id,30 if action=="AID" else 10)
	party.revision+=1
	if not ok or not world.world_state_error().is_empty():
		session.sim=session.SimulatorScript.from_snapshot(rollback)
		return {"accepted":false,"reason":"visitor_interaction_failed","message":"상호작용을 완료하지 못했습니다"}
	session.command_journal.append({"kind":"population","operation":operation.duplicate(true)})
	return {"accepted":true,"reason":"ok","message":"식량을 나눴습니다. 이 도움을 마을에서도 기억합니다." if action=="AID" else "서로 인사를 나눴습니다. 마을에서도 아는 사이로 만납니다."}

static func _ration(world,id:int)->String:
	var inventory=world.item_state.inventory(id)
	if inventory!=null:
		for item in inventory.backpack:
			if str(item.definition_id)=="FOOD_RATION" and item.quantity>0:return str(item.instance_id)
	return ""

static func _emit(world,type:String,rows:Array):
	var cycle=world.party_encounter.expedition_cycle
	return world.emit_event(type,-1,-1,Vector2i(-1,-1),rows.size(),-1,
		{"expedition_index":int(cycle.expedition_index),"floor_index":int(cycle.floor_index),"rows":rows})

static func _distance(a:Vector2i,b:Vector2i)->int:return maxi(absi(a.x-b.x),absi(a.y-b.y))
