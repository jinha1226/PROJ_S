extends RefCounted
## Physical neutral explorers. Runs only from actor cadence and uses canonical
## movement, melee, damage, and inventory authorities.
const Rules=preload("res://sim/living_expedition_rules.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Items=preload("res://sim/world_item_operations.gd")
const Perception=preload("res://sim/enemy_perception_registry.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
const Movement=preload("res://sim/systems/movement_system.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
const LABELS:={"EXPLORE":"탐색 중","FIGHT":"교전 중","REST":"휴식 중",
	"RETURN":"귀환 중","RETURNED":"마을로 귀환","DOWNED":"구조 필요","DEAD":"사망"}

static func choose(profile,health_ratio:int,enemy_distance:int,supplies:int,fatigue:int)->String:
	var caution:int=profile.value("C") if profile!=null else 500
	var emotion:int=profile.value("E") if profile!=null else 500
	var retreat_at:=25+int((caution+emotion)/60)
	if health_ratio<retreat_at or supplies<=0:return "RETURN"
	if enemy_distance<=1:return "FIGHT"
	if enemy_distance<=4 and health_ratio>=60+int(caution/50):return "FIGHT"
	if fatigue>=4 or health_ratio<85:return "REST" if enemy_distance>5 else "RETURN"
	return "EXPLORE"

static func process_tick(sim,step_index:int)->bool:
	var world=sim.world
	if not Rules.enabled(world) or world.party_encounter==null \
			or world.party_encounter.expedition_cycle.phase!="DUNGEON":return true
	var party=world.party_encounter;var rows:Array=Population.locations(world)
	if rows.is_empty():return true
	var hero=world.entities.get(world.party_control_actor_id())
	if hero==null:return false
	var expanded:bool=Rules.expanded_exploration(world)
	var changed:bool=false;var routing:Dictionary={}
	for row in rows:
		if not row is Dictionary:continue
		var id:=int(row.get("entity_id","-1"))
		if not world.entities.has(id) or not world.combatant_states.has(id):continue
		var entity=world.entities[id];var member=party.member(id)
		if member==null or not Rules.present(world,id):continue
		var life:String=world.combatant_states[id].life_state
		if life!="ACTIVE":
			row["state"]=life;row["activity"]=LABELS.get(life,life)
			row["position"]=[entity.position.x,entity.position.y];changed=true;continue
		var distant:=distance(entity.position,hero.position)>16
		if member.busy_until>world.world_time or distant and not expanded:continue
		if routing.is_empty():routing=_safe_occupancy_projection(world,-1)
		var nearest:Dictionary=_nearest_enemy(sim,entity.position)
		var enemy_id:int=int(nearest.id);var enemy_distance:int=int(nearest.distance)
		var food:String=item_id(world,id,"FOOD_RATION")
		var mode:String=choose(member.personality_profile,
			int(entity.health*100/maxi(1,entity.max_health)),enemy_distance,
			1 if not food.is_empty() else 0,int(row.get("fatigue",0)))
		# An explicit service decision remains durable after supplies arrive.
		if str(row.get("state",""))=="RETURN":mode="RETURN"
		if row.get("state","")=="REST" and int(row.get("rest_until",0))>world.world_time \
				and enemy_distance>5:mode="REST"
		var cost:int=100
		if mode=="FIGHT" and enemy_id>0:
			if enemy_distance==1:
				var issued:Dictionary=_issue_attack(sim,id,enemy_id,step_index)
				if issued.get("unsupported",false):
					cost=_step_away(sim,id,world.entities[enemy_id].position,routing)
				elif not issued.accepted:return false
				else:cost=int(issued.cost)
			else:cost=_walk(sim,id,world.entities[enemy_id].position,true,routing)
		elif mode=="RETURN":
			var exit:Vector2i=_position(row.get("entry",[-1,-1]))
			if exit==Vector2i(-1,-1):continue
			if distance(entity.position,exit)<=1:
				if "visitor_returned" not in entity.tags:entity.tags.append("visitor_returned")
				mode="RETURNED"
			else:cost=_walk(sim,id,exit,true,routing,row if expanded else {})
		elif mode=="REST" and enemy_distance>5:
			if int(row.get("rest_until",0))<=world.world_time:
				if not food.is_empty() and int(row.get("fatigue",0))>=4:
					if not Items.commit_use(world,id,food,entity.position,0).get("accepted",false):return false
				row["rest_until"]=world.world_time+300;row["fatigue"]=0
				var healing:int=mini(3,int(entity.max_health-entity.health))
				if healing>0:
					var before:=int(entity.health);entity.health+=healing
					if world.emit_event("population.rested",id,id,entity.position,healing,-1,
							{"schema_version":1,"health_before":before,
							"health_after":int(entity.health)})==null:return false
		else:
			var goals:Array=row.get("goals",[])
			if goals.is_empty():goals=[row.get("anchor",[entity.position.x,entity.position.y])]
			var goal_index:int=posmod(int(row.get("goal_index",0)),goals.size())
			var goal:Vector2i=_position(goals[goal_index])
			if goal==Vector2i(-1,-1):continue
			if distance(entity.position,goal)<=1:
				row["goal_index"]=(goal_index+1)%goals.size()
				row["fatigue"]=int(row.get("fatigue",0))+1
			else:
				var before:Vector2i=entity.position
				cost=_walk(sim,id,goal,true,routing,row if expanded else {})
				if expanded and entity.position==before:row["goal_index"]=(goal_index+1)%goals.size()
		# Off-screen expeditions still move, at a bounded coarse cadence.
		if expanded and distant:cost=maxi(cost,300)
		member.busy_until=world.world_time+maxi(1,cost)
		row["state"]=mode;row["activity"]=LABELS[mode]
		row["position"]=[entity.position.x,entity.position.y]
		row["needs_supplies"]=item_id(world,id,"FOOD_RATION").is_empty();changed=true
	# One shared enemy busy clock prevents the normal coordinator acting it again.
	var enemies:Array=sim.party_coordinator._stream_enemy_ids();enemies.sort()
	for enemy_value in enemies:
		var enemy_id:=int(enemy_value)
		if not world.entities.has(enemy_id) or not world.is_autonomous_target(enemy_id) \
				or not world.can_act(enemy_id,world.world_time) \
				or int(party.enemy_busy_rows.get(enemy_id,world.world_time+1))>world.world_time:continue
		var neutral_targets:Array[int]=_adjacent_independent_targets(world,enemy_id)
		if neutral_targets.is_empty():continue
		var targets:Array=neutral_targets.duplicate()
		for active_id in _adjacent_active_targets(world,enemy_id):
			if active_id not in targets:targets.append(active_id)
		targets.sort()
		var target_id:int=int(targets[posmod(enemy_id+step_index,targets.size())])
		var issued:Dictionary=_issue_attack(sim,enemy_id,target_id,step_index)
		if issued.get("unsupported",false):continue
		if not issued.accepted:return false
		party.enemy_busy_rows[enemy_id]=world.world_time+int(issued.cost)
	if changed:
		var cycle=party.expedition_cycle
		if world.emit_event("population.patrol",-1,-1,Vector2i(-1,-1),rows.size(),-1,
				{"expedition_index":cycle.expedition_index,"floor_index":cycle.floor_index,
				"rows":rows})==null:return false
		party.revision+=1
	return true

static func attack(sim,attacker:int,target:int,step_index:int)->bool:
	return bool(_issue_attack(sim,attacker,target,step_index).get("accepted",false))

static func _issue_attack(sim,attacker:int,target:int,step_index:int)->Dictionary:
	var world=sim.world
	if not world.entities.has(attacker) or not world.entities.has(target):return {"accepted":false}
	var entity:Variant=world.entities[target];var weapon_id:String=Items.equipped_weapon_id(world,attacker)
	var weapon:Variant=Weapons.definition(weapon_id)
	if weapon==null or int(weapon.range_min)>1 or not Items.attack_error(world,attacker).is_empty():
		return {"accepted":false,"unsupported":true}
	var context:String="INDEPENDENT/%d/%d/%d"%[step_index,attacker,target]
	var assessment:Dictionary=sim.melee.assess_attack(attacker,target,"SUGGESTED",
		step_index,world.world_time,context,0,weapon_id)
	if assessment.is_empty():return {"accepted":false}
	var frozen:Variant=sim.melee.freeze_assessment(assessment,entity.health,0)
	var results:Array=sim.melee.project_batch([frozen])
	if results.size()!=1:return {"accepted":false}
	var resolved:Variant=results[0]
	var event:Variant=world.emit_event("action.melee_attack",attacker,target,entity.position,
		int(assessment.base_damage),-1,resolved.action_data)
	if event==null:return {"accepted":false}
	if resolved.outcome in ["MISS","PARRIED"]:
		var result_event:Variant=world.emit_event("combat.attack_parried" if resolved.outcome=="PARRIED" \
				else "combat.attack_missed",-1,target,entity.position,0,event.id,
				{"schema_version":1,"combat_ruleset_id":sim.melee.COMBAT_RULESET_ID,
				"outcome":str(resolved.outcome)})
		return {"accepted":result_event!=null,"cost":int(weapon.attack_time)}
	if resolved.outcome=="FINISHER":
		var finished:Dictionary=sim.damage.apply_canonical_downed_finisher(entity,
			int(assessment.normal_final_damage),event.id,entity.position,step_index)
		return {"accepted":bool(finished.get("accepted",false)),"cost":int(weapon.attack_time)}
	var damaged:Dictionary=sim.damage.apply_canonical_active_damage(entity,int(resolved.final_damage),
		"physical",event.id,entity.position,step_index,entity.health,false,
		bool(resolved.bleed_proc_succeeded))
	return {"accepted":bool(damaged.get("accepted",false)),"cost":int(weapon.attack_time)}

static func _step_away(sim,id:int,threat:Vector2i,routing:Dictionary)->int:
	var world=sim.world;var entity=world.entities.get(id)
	if entity==null:return 0
	var origin:Vector2i=entity.position;var best:=Vector2i(-1,-1)
	for direction in Movement.MOVE_DIRECTIONS_8:
		var candidate:Vector2i=origin+direction
		if distance(candidate,threat)<=distance(origin,threat) \
				or routing.has("%d:%d"%[candidate.x,candidate.y]):continue
		var assessment=sim.movement.assess_move(id,candidate)
		if assessment.accepted:best=candidate;break
	if best==Vector2i(-1,-1):return 0
	var old_key:="%d:%d"%[origin.x,origin.y];routing.erase(old_key)
	var assessment=sim.movement.assess_move(id,best)
	var definition:Dictionary=Terrain.definition(str(assessment.terrain_id))
	var cost:int=int(definition.get("move_time_cost",100))
	if sim.movement.commit_preflighted_move(id,best,str(assessment.terrain_id),cost)==null:
		routing[old_key]=id;return 0
	routing["%d:%d"%[best.x,best.y]]=id
	return cost

static func _walk(sim,id:int,goal:Vector2i,adjacent_ok:bool=false,routing:Dictionary={},route_row:Dictionary={})->int:
	var world=sim.world
	if not world.entities.has(id):return 100
	if routing.is_empty():routing=_safe_occupancy_projection(world,-1)
	var old_position:Vector2i=world.entities[id].position
	routing.erase("%d:%d"%[old_position.x,old_position.y])
	var goals:Array=[]
	if not adjacent_ok:goals.append(goal)
	for direction in Movement.MOVE_DIRECTIONS_8:goals.append(goal+direction)
	var cells:Array=[]
	# A short, journaled route prefix avoids searching the whole dungeon every
	# time an explorer takes one step. Every cached hop is assessed again.
	if not route_row.is_empty() and route_row.get("route_goal",[])==[goal.x,goal.y]:
		var route:Array=route_row.get("route",[])
		if not route.is_empty():
			var cached:Vector2i=_position(route[0])
			if distance(old_position,cached)==1 and not routing.has("%d:%d"%[cached.x,cached.y]) \
					and sim.movement.assess_move(id,cached).accepted:cells=[old_position,cached]
	if cells.is_empty():
		var path:Dictionary=sim.pathfinder.find_path_to_any(id,goals,routing)
		cells=path.get("path",[])
		if not route_row.is_empty():
			route_row["route_goal"]=[goal.x,goal.y];route_row["route"]=[]
			for p in cells.slice(1,9):route_row.route.append([p.x,p.y])
	if cells.size()<2:
		routing["%d:%d"%[old_position.x,old_position.y]]=id;return 100
	var next:Vector2i=cells[1]
	var assessment=sim.movement.assess_move(id,next)
	if not assessment.accepted:
		routing["%d:%d"%[old_position.x,old_position.y]]=id;return 100
	var definition:Dictionary=Terrain.definition(str(assessment.terrain_id))
	var cost:=int(definition.get("move_time_cost",100))
	if sim.movement.commit_preflighted_move(id,next,str(assessment.terrain_id),cost)==null:
		routing["%d:%d"%[old_position.x,old_position.y]]=id;return 100
	routing["%d:%d"%[next.x,next.y]]=id
	if not route_row.is_empty() and not route_row.get("route",[]).is_empty():route_row.route.pop_front()
	return cost

static func _safe_occupancy_projection(world,actor_id:int)->Dictionary:
	var started:=preload("res://sim/perf_probe.gd").begin()
	# Non-empty projections replace real occupancy, so copy all blockers too.
	var result:Dictionary={}
	for entity_id_value in world.entities.keys():
		var entity_id:=int(entity_id_value)
		if entity_id==actor_id or not world.occupies_tile(entity_id):continue
		var entity=world.entities.get(entity_id)
		if entity!=null:result["%d:%d"%[entity.position.x,entity.position.y]]=entity_id
	for p in world.explorer_hazard_positions():result["%d:%d"%[p.x,p.y]]=-2
	if result.is_empty():result["safe-routing"]=-2
	preload("res://sim/perf_probe.gd").end("npc.routing_projection",started)
	return result

static func _nearest_enemy(sim,position:Vector2i)->Dictionary:
	var result:={"id":-1,"distance":999}
	for enemy_value in sim.party_coordinator._stream_enemy_ids():
		var enemy_id:=int(enemy_value)
		if not sim.world.entities.has(enemy_id) or not sim.world.is_autonomous_target(enemy_id):continue
		var enemy=sim.world.entities[enemy_id];var candidate:=distance(position,enemy.position)
		if candidate<=6 and Perception.has_line_of_sight(sim.world,position,enemy.position) \
				and (candidate<int(result.distance) or candidate==int(result.distance) \
				and (int(result.id)<0 or enemy_id<int(result.id))):
			result={"id":enemy_id,"distance":candidate}
	return result

static func _adjacent_active_targets(world,enemy_id:int)->Array[int]:
	var result:Array[int]=[];var enemy=world.entities[enemy_id]
	for id_value in world.party_encounter.active_party_member_ids:
		var id:=int(id_value)
		if world.entities.has(id) and world.is_autonomous_target(id) \
				and distance(enemy.position,world.entities[id].position)==1:result.append(id)
	result.sort();return result

static func _adjacent_independent_targets(world,enemy_id:int)->Array[int]:
	var result:Array[int]=[];var enemy=world.entities[enemy_id]
	for id_value in world.party_encounter.party_member_ids:
		var id:=int(id_value)
		var state=world.combatant_states.get(id)
		if Rules.present(world,id) and state!=null and state.life_state in ["ACTIVE","DOWNED"] \
				and distance(enemy.position,world.entities[id].position)==1:result.append(id)
	result.sort();return result

static func item_id(world,id:int,definition_id:String)->String:
	if world.item_state==null:return ""
	var inventory=world.item_state.inventory(id)
	if inventory!=null:
		for item in inventory.backpack:
			if str(item.definition_id)==definition_id and int(item.quantity)>0:return str(item.instance_id)
	return ""

static func _position(value:Variant)->Vector2i:
	return Vector2i(int(value[0]),int(value[1])) if value is Array and value.size()==2 \
		else (value if value is Vector2i else Vector2i(-1,-1))

static func distance(a:Vector2i,b:Vector2i)->int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))
