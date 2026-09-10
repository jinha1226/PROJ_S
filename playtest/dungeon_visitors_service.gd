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
		var member=party.member(id);var entity=world.entities.get(id)
		if entity==null or member==null or id in company or member.presence!="RECRUITABLE":continue
		if Rules.identity(str(entity.display_name)).explores:candidates.append(id)
	var occupied:Array=[]
	var entry:Vector2i=layout.entry_position
	var seeds:Array[Vector2i]=[entry+Vector2i(3,2),entry+Vector2i(-3,3)]
	var living:=preload("res://sim/living_expedition_rules.gd").enabled(world)
	if living and not layout.get("visitor_positions",[]).is_empty():seeds.assign(layout.visitor_positions)
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
					if p in occupied or not _safe(world,p,entry,living):continue
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
		if living:
			var id:=int(candidates[index]);var entity=world.entities[id]
			var old:Vector2i=entity.position
			entity.tags.erase("visitor_returned")
			for tag in entity.tags.duplicate():
				if str(tag).begins_with("visitor_floor:"):entity.tags.erase(tag)
			if "independent_explorer" not in entity.tags:entity.tags.append("independent_explorer")
			entity.tags.append("visitor_floor:"+str(party.expedition_cycle.floor_index))
			entity.position=chosen
			if world.emit_event("population.arrived",id,-1,chosen,0,-1,{"from":[old.x,old.y],"to":[chosen.x,chosen.y]})==null:return false
			var row:Dictionary=rows[-1]
			row["entry"]=[entry.x,entry.y];row["state"]="REST" if index==0 else ("RETURN" if index==2 else "EXPLORE")
			row["rest_until"]=world.world_time+300 if index==0 else 0
			row["fatigue"]=4 if index==0 else 0;row["goal_index"]=0
			row["goals"]=[[chosen.x+2,chosen.y],[chosen.x,chosen.y+2],[chosen.x-2,chosen.y]]
			if preload("res://sim/living_expedition_rules.gd").expanded_exploration(world):
				row["goals"]=_exploration_goals(world,layout,chosen,index)
			row.activity=preload("res://sim/systems/independent_explorer_system.gd").LABELS[row.state]
			row.needs_supplies=index==2
			var inventory=world.item_state.inventory(id)
			if inventory==null:return false
			if inventory.equipped_item("MAIN_HAND")==null:
				var grant:Dictionary=Items.commit_grant(world,id,"WEAPON_SHORT_SWORD",1,chosen,"INDEPENDENT_EXPEDITION")
				if not grant.get("accepted",false) or not Items.commit_equip(world,id,str(grant.instance_id),"MAIN_HAND",chosen,0).get("accepted",false):return false
			if index!=2 and preload("res://sim/systems/independent_explorer_system.gd").item_id(world,id,"FOOD_RATION").is_empty():
				if not Items.commit_grant(world,id,"FOOD_RATION",2,chosen,"INDEPENDENT_EXPEDITION").get("accepted",false):return false
	return _emit(world,"population.floor_arrived",rows)!=null

static func _exploration_goals(world,layout:Dictionary,start:Vector2i,ordinal:int)->Array:
	# One bounded flood on arrival. Goals are journaled with the visitor, so
	# neither rendering nor hidden player knowledge drives neutral exploration.
	var reachable:Dictionary={start:true};var frontier:Array[Vector2i]=[start];var cursor:=0
	while cursor<frontier.size():
		var here:Vector2i=frontier[cursor];cursor+=1
		for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var next:Vector2i=here+direction
			if reachable.has(next) or not world.in_bounds(next):continue
			var tile=world.tile_at(next)
			if not Terrain.definition(str(tile.terrain)).get("passable",false) \
					or tile.fire>0 or tile.wetness>0 or str(tile.terrain)=="shallow_water":continue
			reachable[next]=true;frontier.append(next)
	var candidates:Array[Vector2i]=[]
	for center in layout.get("room_centers",[]):
		if reachable.has(center) and _distance(center,start)>=8:candidates.append(center)
	if candidates.is_empty():
		for cell in frontier:
			if _distance(cell,start)>=8 and (cell.x+cell.y)%7==0:candidates.append(cell)
	var goals:Array=[]
	if candidates.is_empty():return [[start.x,start.y]]
	# Different explorers start in different rooms; each then visits the circuit.
	var offset:=posmod(ordinal*3,candidates.size())
	for i in range(mini(8,candidates.size())):
		var p:Vector2i=candidates[(offset+i)%candidates.size()]
		goals.append([p.x,p.y])
	return goals

static func _safe(world,p:Vector2i,entry:Vector2i,living:bool=false)->bool:
	if not world.in_bounds(p) or _distance(p,entry)<2:return false
	var tile=world.tile_at(p)
	if not Terrain.definition(str(tile.terrain)).get("passable",false) or tile.fire>0 or tile.wetness>0:return false
	if not world.occupying_entities_at(p).is_empty():return false
	if living:return true
	for id in world.party_encounter.enemy_ids:
		var enemy=world.entities.get(id)
		if enemy!=null and world.is_unresolved_enemy(id) and _distance(p,enemy.position)<5:return false
	return true

static func advance(session)->void:
	if not session.town_life_enabled():return
	if preload("res://sim/living_expedition_rules.gd").enabled(session.sim.world):return
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
		var member=party.member(int(row.entity_id))
		if member==null:continue
		var p:=Vector2i(int(row.position[0]),int(row.position[1]))
		var anchor:=Vector2i(int(row.anchor[0]),int(row.anchor[1]))
		var profile=member.personality_profile
		if profile==null:continue
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
	if action=="AID":
		ok=bool(Items.commit_transfer(world,leader,id,_ration(world,leader),
			world.entities[leader].position,0).get("accepted",false))
	var event=world.emit_event("population.assisted" if action=="AID" else "population.greeted",leader,id,
		world.entities[leader].position,30 if action=="AID" else 10,-1,
		{"entity_id":str(id),"expedition_index":int(party.expedition_cycle.expedition_index)})
	ok=ok and event!=null and session.sim.relationships.record_aid(id,leader,event.id,30 if action=="AID" else 10)
	if ok and action=="AID":
		var rows:=Rules.locations(world)
		for row in rows:
			if int(row.get("entity_id","-1"))!=id:continue
			row["needs_supplies"]=false;row["state"]="RETURN"
			row["activity"]="물자를 받고 귀환 중";break
		ok=_emit(world,"population.patrol",rows)!=null
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
