extends RefCounted
## Neutral expedition population, aid and explicit temporary recruitment.
## Physical AI belongs to independent_explorer_system; joined NPCs use party AI.
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
	var entity=world.entities.get(id);var member=party.member(id)
	if row.is_empty() or entity==null or member==null or member.presence!="RECRUITABLE" \
			or not preload("res://sim/living_expedition_rules.gd").present(world,id) \
			or world.combatant_states[id].life_state!="ACTIVE":
		return {"accepted":false,"message":"지금 동행을 제안할 수 없는 인물입니다"}
	var greeted:=false;var helped:=false
	for event in world.events:
		if event.target_id!=id or int(event.data.get("expedition_index",0))!=int(party.expedition_cycle.expedition_index):continue
		if event.type=="population.greeted":greeted=true
		if event.type=="population.assisted":helped=true
	var leader:int=world.party_control_actor_id();var player=world.entities[leader]
	var nearby:bool=_distance(player.position,entity.position)<=1
	var safe:bool=party.safe_phase in ["GROUPED","GROUPED_COMPLETE"] and not session._run_is_complete()
	var supply:=_ration(world,leader);var potion:=_healing_item(world,leader)
	var resting:bool=str(row.get("state","")) in ["REST","RETURN"]
	var hungry:bool=resting and _ration(world,id).is_empty()
	var injured:bool=resting and entity.health<entity.max_health
	var can_join:bool=nearby and safe and helped and Life.field_count(world)<Life.FIELD_LIMIT
	var can_aid:bool=nearby and safe and hungry and not helped and not supply.is_empty()
	var can_heal:bool=nearby and safe and injured and not helped and not potion.is_empty()
	var action:String="ACCEPT" if helped else ("HEAL" if injured and (not potion.is_empty() or not hungry) else ("AID" if hungry else "GREET"))
	var can_greet:bool=nearby and safe and not greeted
	var allowed:Dictionary={"ACCEPT":can_join,"HEAL":can_heal,"AID":can_aid,"GREET":can_greet}
	var message:String="도움을 주면 이번 원정에 확실히 동행할 수 있습니다."
	if helped:message="함께 가고 싶다고 합니다. 수락하면 동료가 됩니다." if Life.field_count(world)<Life.FIELD_LIMIT else "파티가 가득합니다. 도움은 기억하므로 자리가 나면 수락할 수 있습니다."
	elif not injured and not hungry:message="도움이 필요한 상태는 아닙니다. 이야기를 나눌 수 있습니다."
	elif injured and potion.is_empty():message="회복 물약이 필요합니다."
	elif hungry and supply.is_empty():message="나눠 줄 식량이 없습니다."
	if not nearby:message="바로 옆으로 다가가세요."
	elif not safe:message="전투가 끝난 뒤 대화할 수 있습니다."
	return {"accepted":true,"nearby":nearby,"can_greet":can_greet,"can_aid":can_aid,
		"can_heal":can_heal,"can_join":can_join,"needs_supplies":hungry,
		"greeted":greeted,"helped":helped,"activity":str(row.activity),
		"action":action,"can_act":allowed[action],
		"action_label":{"ACCEPT":"동행 수락","HEAL":"회복 물약 1개 주기","AID":"식량 1개 나누기","GREET":"이야기 나누기"}[action],
		"message":message}

static func interact(session,operation:Dictionary)->Dictionary:
	var error:=Rules.interaction_error(operation)
	if not error.is_empty():return {"accepted":false,"reason":error}
	var id:=int(operation.entity_id);var action:=str(operation.action)
	var view:=assess(session,id)
	var field:String={"AID":"can_aid","HEAL":"can_heal","ACCEPT":"can_join","GREET":"can_greet"}[action]
	if not view.get(field,false):return {"accepted":false,"reason":"visitor_interaction_unavailable","message":view.get("message","지금은 만날 수 없습니다")}
	var world=session.sim.world;var party=world.party_encounter
	var rollback:Dictionary=session.sim.snapshot()
	if rollback.is_empty():return {"accepted":false,"reason":"snapshot_unavailable"}
	var leader:int=world.party_control_actor_id();var ok:=true
	var message:="서로 인사를 나눴습니다."
	if action=="ACCEPT":
		ok=bool(session._apply_roster_change("RECRUIT",id,false,rollback).get("accepted",false))
		if ok:
			if "expedition_companion" not in world.entities[id].tags:world.entities[id].tags.append("expedition_companion")
			var rows:=Rules.locations(world)
			for i in range(rows.size()-1,-1,-1):
				if int(rows[i].entity_id)==id:rows.remove_at(i)
			ok=_emit(world,"population.patrol",rows)!=null
		message="이번 원정의 동료로 합류했습니다."
	else:
		if action in ["AID","HEAL"]:
			var item_id:String=_ration(world,leader) if action=="AID" else _healing_item(world,leader)
			var item=world.item_state.inventory(leader).item(item_id)
			var definition_id:String=str(item.definition_id)
			# Consume exactly one from the donor, not the entire stack.
			ok=bool(Items.commit_use(world,leader,item_id,world.entities[leader].position,0).get("accepted",false))
			if ok and action=="AID":
				ok=bool(Items.commit_grant(world,id,"FOOD_RATION",1,world.entities[id].position,"EXPEDITION_AID").get("accepted",false))
			if ok and action=="HEAL":
				var target=world.entities[id];var before:int=target.health
				target.health=mini(target.max_health,target.health+preload("res://sim/item_catalog_registry.gd").healing_amount(definition_id))
				ok=world.emit_event("population.healed",leader,id,target.position,target.health-before,-1,
					{"health_before":before,"health_after":int(target.health)})!=null
		var event=null
		if ok:
			event=world.emit_event("population.assisted" if action in ["AID","HEAL"] else "population.greeted",leader,id,
				world.entities[leader].position,30 if action in ["AID","HEAL"] else 10,-1,
				{"entity_id":str(id),"expedition_index":int(party.expedition_cycle.expedition_index),"aid_kind":action})
		ok=ok and event!=null and session.sim.relationships.record_aid(id,leader,event.id,30 if action in ["AID","HEAL"] else 10)
		if ok and action in ["AID","HEAL"]:
			var rows:=Rules.locations(world)
			for row in rows:
				if int(row.entity_id)!=id:continue
				row["needs_supplies"]=false;row["state"]="REST";row["decision_mode"]="REST"
				row["rest_until"]=world.world_time+600;row["activity"]="도움을 받고 동행 제안 중"
			ok=_emit(world,"population.patrol",rows)!=null
			message="도움을 받은 NPC가 동행을 제안합니다. [동행 수락]을 누르면 합류합니다."
	party.revision+=1
	if not ok or not session.sim.world.world_state_error().is_empty():
		session.sim=session.SimulatorScript.from_snapshot(rollback)
		return {"accepted":false,"reason":"visitor_interaction_failed","message":"상호작용을 완료하지 못했습니다"}
	session.command_journal.append({"kind":"population","operation":operation.duplicate(true)})
	return {"accepted":true,"reason":"ok","message":message}

static func _healing_item(world,id:int)->String:
	var inventory=world.item_state.inventory(id)
	if inventory!=null:
		for item in inventory.backpack:
			if preload("res://sim/item_catalog_registry.gd").healing_amount(str(item.definition_id))>0 and item.quantity>0:
				return str(item.instance_id)
	return ""

static func release_temporary(session)->void:
	var world=session.sim.world;var party=world.party_encounter
	if party.expedition_cycle.phase!="TOWN":return
	for id in party.active_party_member_ids.duplicate():
		var entity=world.entities[id]
		if id==world.party_control_actor_id():continue
		if "expedition_companion" not in entity.tags:continue
		entity.tags.erase("expedition_companion")
		party.active_party_member_ids.erase(id)
		party.member(id).presence="DEFEATED" if world.combatant_states[id].life_state=="DEAD" else "RECRUITABLE"
		world.emit_event("town.company_reserved",party.protagonist_id,id,entity.position,0,-1,{"entity_id":str(id),"expedition_index":int(party.expedition_cycle.expedition_index),"reason":"EXPEDITION_COMPANIONSHIP_ENDED"})
		party.revision+=1

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
