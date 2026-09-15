extends RefCounted

const RULESET := "party-rescue-v1"
const GRACE := 1000
const Action = preload("res://sim/party_action_command.gd")
const Kernel = preload("res://sim/combat_kernel.gd")

static func enabled(world) -> bool:
	return world!=null and world.party_encounter!=null and preload("res://sim/runtime_history_index.gd").sync(world).first.has("party.rescue_enabled")

static func member(world,id:int) -> bool:
	return enabled(world) and id in world.party_encounter.active_party_member_ids

static func terminal(world,id:int) -> bool:
	return not member(world,id) and (world.lifecycle_succumbs(id) or world.party_encounter!=null and world.party_encounter.protagonist_id==id)

static func member_at(world,id:int,before:int)->bool:
	if not enabled(world):return false
	var activation=preload("res://sim/runtime_history_index.gd").sync(world).first["party.rescue_enabled"]
	return activation.id<before and id in world._party_active_ids_at_event(before)

static func deadline(world,id:int,at:int,before:int=-1) -> int:
	var eligible:bool=member_at(world,id,before) if before>=0 else member(world,id)
	return at+GRACE if eligible else (at/100+1)*100+100

static func downed_ids(world) -> Array[int]:
	var ids:Array[int]=[]
	if not enabled(world):return ids
	for id in world.party_encounter.active_party_member_ids:
		if world.combatant_states[id].life_state=="DOWNED":ids.append(id)
	return ids

static func links(world,before:int=-1) -> Dictionary:
	var result:Dictionary={}
	if not enabled(world):return result
	if before<0:return preload("res://sim/runtime_history_index.gd").sync(world).assist_links.duplicate(true)
	for e in world.events:
		if before>=0 and e.id>=before:break
		if e.type=="party.assist_started":result[int(e.actor_id)]={"target":int(e.target_id),"source":int(e.id),"moved":false}
		elif e.type=="party.assist_moved" and result.has(int(e.actor_id)):result[int(e.actor_id)].moved=true
		elif e.type=="party.assist_ended":result.erase(int(e.actor_id))
	return result

static func clear_status(world,id:int) -> bool:
	var c=world.combatant_states[id]
	for status in c.status_rows:
		if world.emit_event("status.expired",-1,id,world.entities[id].position,0,c.downed_source_event_id,
			{"schema_version":1,"status_ruleset_id":"bounded-status-lifecycle-v1","status_id":status.status_id,"reason":"RESCUE_GRACE"})==null:return false
	c.status_rows.clear()
	return true

static func threat_ids(world) -> Array[int]:
	var result:Array[int]=[]
	if not enabled(world):return result
	for enemy_id in world.party_encounter.enemy_ids:
		if not world.is_autonomous_target(enemy_id):continue
		for id in world.party_encounter.active_party_member_ids:
			if world.combatant_states[id].life_state=="DEAD":continue
			if Kernel.sees(world.entities[id].position,world.entities[enemy_id].position,world.combat_sight_blocked):
				result.append(enemy_id);break
	return result

static func safe(world,id:int) -> bool:
	if not threat_ids(world).is_empty():return false
	var tile=world.tile_at(world.entities[id].position)
	# Match actual risk evaluation at the caller for more complex affinities.
	return int(tile.fire)==0

static func next_deadline(world,end:int) -> Dictionary:
	var row:Dictionary={}
	for id in downed_ids(world):
		var at:int=world.combatant_states[id].downed_resolve_at
		if at<=end and (row.is_empty() or at<int(row.at)):row={"at":at,"id":-2}
	return row

static func settle(sim) -> bool:
	var w=sim.world
	if not enabled(w):return true
	for id in downed_ids(w):
		var c=w.combatant_states[id]
		if not clear_status(w,id):return false
		if w.world_time>=c.downed_resolve_at:
			if not bool(sim.damage.apply_canonical_downed_succumb(w.entities[id],c.downed_source_event_id,w.entities[id].position,w._active_step_index).accepted):return false
	# Do not resurrect a defeated run through another member's empty sight.
	if w.combatant_states[w.party_encounter.protagonist_id].life_state=="DEAD":return _end_invalid_links(w)
	for id in downed_ids(w):
		if not safe(w,id):continue
		var exposure=sim.evaluate_exposure_for_entity(id,w.entities[id].position)
		if exposure!=null and exposure.evaluation!=null and int(exposure.evaluation.total_risk)>0:continue
		var c=w.combatant_states[id]
		var original:int=c.downed_source_event_id
		var helper:=-1
		var assist_source:=-1
		for h in links(w):
			var link:Dictionary=links(w)[h]
			if int(link.target)==id and bool(link.moved) and w.can_act(h,w.world_time):helper=h;assist_source=int(link.source)
		var recovered=w.emit_event("entity.recovered",-1,id,w.entities[id].position,1,original,
			{"schema_version":1,"life_ruleset_id":"active-downed-dead-v1","recovered_health":1,"recovery_lock_until":str(w.world_time+100)})
		if recovered==null:return false
		w.entities[id].health=1;c.life_state="ACTIVE"
		c.downed_at=-1;c.downed_resolve_at=-1;c.downed_source_event_id=-1
		c.recovery_lock_until=w.world_time+100;c.recovery_source_event_id=recovered.id
		w.party_encounter.member(id).busy_until=maxi(w.party_encounter.member(id).busy_until,w.world_time+100)
		if helper>0:
			if w.emit_event("party.rescue_completed",helper,id,w.entities[id].position,1,recovered.id,
				{"ruleset_id":RULESET,"downed_event_id":str(original),"assist_event_id":str(assist_source)})==null:return false
	return _end_invalid_links(w)

static func _end_invalid_links(w) -> bool:
	for h in links(w):
		var link:Dictionary=links(w)[h]
		if w.combatant_states[h].life_state!="ACTIVE" or w.combatant_states[int(link.target)].life_state!="DOWNED" or w.entities[h].position.distance_squared_to(w.entities[int(link.target)].position)>2:
			if w.emit_event("party.assist_ended",h,int(link.target),w.entities[h].position,0,int(link.source),{"reason":"LIFE_CHANGED"})==null:return false
	return true

static func action_error(w,action) -> String:
	if not enabled(w):return "rescue_unavailable" if action.type in ["ASSIST","RELEASE","REASSURE","PROMISE"] else ""
	if action.type in ["REASSURE","PROMISE"]:
		return "" if dialogue_source(w,action.actor_id,action.target_id)!=null else "rest_dialogue_unavailable"
	var active_links:Dictionary=links(w)
	if active_links.has(action.actor_id) and action.type in ["MELEE","SKILL"]:return "release_before_attack"
	if action.type=="RELEASE":return "" if active_links.has(action.actor_id) else "not_assisting"
	if action.type!="ASSIST":return ""
	if not member(w,action.target_id) or action.target_id==action.actor_id or w.combatant_states[action.target_id].life_state!="DOWNED":return "target_not_downed"
	if active_links.has(action.actor_id):return "already_assisting"
	for link in active_links.values():
		if int(link.target)==action.target_id:return "target_already_assisted"
	var a:Vector2i=w.entities[action.actor_id].position
	var b:Vector2i=w.entities[action.target_id].position
	if a.distance_squared_to(b)>2 or not Kernel.open_edge(a,b,w.combat_solid):return "assist_not_adjacent"
	return ""

static func move_error(w,id:int,destination:Vector2i) -> String:
	var active_links:Dictionary=links(w)
	if not active_links.has(id):return ""
	var target:int=active_links[id].target
	var old:Vector2i=w.entities[id].position
	var from:Vector2i=w.entities[target].position
	if destination==from or from.distance_squared_to(old)>2 or not Kernel.open_edge(from,old,w.combat_solid):return "assist_path_blocked"
	return ""

static func commit_action(sim,action,cost:int) -> bool:
	var w=sim.world
	var active_links:Dictionary=links(w)
	var target:int=action.target_id if action.type=="ASSIST" else int(active_links[action.actor_id].target)
	var source:int=-1 if action.type=="ASSIST" else int(active_links[action.actor_id].source)
	var data:Dictionary={"downed_event_id":str(w.combatant_states[target].downed_source_event_id)} if action.type=="ASSIST" else {"reason":"RELEASE"}
	if w.emit_event("party.assist_started" if action.type=="ASSIST" else "party.assist_ended",action.actor_id,target,w.entities[action.actor_id].position,cost,source,data)==null:return false
	w.party_encounter.member(action.actor_id).busy_until=w.world_time+cost
	return true

static func follow_move(sim,id:int,old:Vector2i) -> bool:
	var w=sim.world
	var active_links:Dictionary=links(w)
	if not active_links.has(id):return true
	var target:int=active_links[id].target
	var from:Vector2i=w.entities[target].position
	var e=w.emit_event("party.assist_moved",id,target,old,0,int(active_links[id].source),
		{"from_position":[from.x,from.y],"to_position":[old.x,old.y]})
	if e==null:return false
	w.entities[target].position=old;w.reindex_entity_occupancy(target,from,old)
	return true

static func dialogue_source(w,actor:int,target:int):
	if not preload("res://sim/runtime_history_index.gd").sync(w).first.has("party.rescue_completed"):return null
	if not member(w,actor) or not member(w,target) or actor==target or not downed_ids(w).is_empty() or not threat_ids(w).is_empty():return null
	if not w.can_act(actor,w.world_time) or not w.can_act(target,w.world_time):return null
	if w.entities[actor].position.distance_squared_to(w.entities[target].position)>2:return null
	if not safe(w,actor) or not safe(w,target):return null
	var consumed:Dictionary={}
	for e in w.events:
		if e.type=="party.rescue_dialogue":consumed[e.cause_id]=true
	for index in range(w.events.size()-1,-1,-1):
		var e=w.events[index]
		if e.type=="party.rescue_completed" and not consumed.has(e.id) and ((e.actor_id==actor and e.target_id==target) or (e.actor_id==target and e.target_id==actor)):return e
	return null

static func commit_dialogue(sim,action)->bool:
	var w=sim.world
	var source=dialogue_source(w,action.actor_id,action.target_id)
	if source==null:return false
	for id in [action.actor_id,action.target_id]:
		var risk=sim.evaluate_exposure_for_entity(id,w.entities[id].position)
		if risk!=null and risk.evaluation!=null and int(risk.evaluation.total_risk)>0:return false
	if w.emit_event("party.rescue_dialogue",action.actor_id,action.target_id,w.entities[action.actor_id].position,100,source.id,{"choice":action.type,"ruleset_id":RULESET})==null:return false
	w.party_encounter.member(action.actor_id).busy_until=w.world_time+100
	return true

static func rescue_priority(w,helper:int,target:int)->int:
	var m=w.party_encounter.member(helper)
	var score:int=300 if m.personality_profile==null else 100+m.personality_profile.value("H")/5+m.personality_profile.value("A")/5
	score+=m.memory_state.salience_for_subject(target,["RESCUED_BY"])/2
	for e in w.events:
		if e.type=="party.rescue_dialogue" and e.data.choice=="PROMISE" and ((e.actor_id==helper and e.target_id==target) or (e.actor_id==target and e.target_id==helper)):
			score+=200;break
	return score

static func suggest(w,id:int,movement):
	if not member(w,id):return null
	var active_links:Dictionary=links(w)
	if active_links.has(id):
		var threats:Array[int]=threat_ids(w)
		var best:Vector2i=w.entities[id].position
		var best_score:=-2147483648
		for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
			var p:Vector2i=w.entities[id].position+d
			if not movement.assess_move(id,p).accepted or w.tile_at(p).fire>0:continue
			var score:=10000
			for enemy in threats:score=mini(score,int(p.distance_squared_to(w.entities[enemy].position)))
			if score>best_score:best_score=score;best=p
		return Action.move_to(id,best) if best!=w.entities[id].position else Action.hold(id)
	var target:=-1;var priority:=-1
	for other in downed_ids(w):
		var action=Action.new("ASSIST",id,Vector2i(-1,-1),other)
		if not action_error(w,action).is_empty():continue
		var score:=rescue_priority(w,id,other)
		if score>priority:priority=score;target=other
	return Action.new("ASSIST",id,Vector2i(-1,-1),target) if target>0 else null

# Audit the new event graph in addition to the existing position/lifecycle audits.
static func history_error(w)->String:
	if w.party_encounter==null:return ""
	var activated:=false;var active_links:Dictionary={};var credited:Dictionary={};var talked:Dictionary={}
	# Validate movement wires before historical position queries inspect future rows.
	for e in w.events:
		if e.type=="party.assist_moved":
			if e.data.size()!=2 or not w._party_metadata_position(e.data.get("from_position")) or not w._party_metadata_position(e.data.get("to_position")):return "rescue_move_invalid"
	for e in w.events:
		if e.type=="party.rescue_enabled":
			if activated or e.cause_id!=-1 or e.position!=Vector2i(-1,-1) or e.magnitude!=0 or e.step_index!=0 or e.world_time!=0 or e.actor_id!=w.party_encounter.protagonist_id or e.target_id!=-1 or e.data!={"ruleset_id":RULESET}:return "rescue_activation_invalid"
			activated=true
		if e.type not in ["party.assist_started","party.assist_moved","party.assist_ended","party.rescue_completed","party.rescue_dialogue","party.crisis_wait"]:continue
		if not activated or e.actor_id not in w._party_active_ids_at_event(e.id):return "rescue_actor_invalid"
		if e.type=="party.crisis_wait":
			if e.target_id!=-1 or e.magnitude!=100 or e.cause_id!=-1 or not e.data.is_empty():return "rescue_wait_invalid"
			continue
		if e.target_id not in w._party_active_ids_at_event(e.id) or e.actor_id==e.target_id:return "rescue_target_invalid"
		if e.type=="party.assist_started":
			if e.data.size()!=1 or not e.data.has("downed_event_id") or e.cause_id!=-1:return "rescue_assist_invalid"
			var helper_life:Dictionary=w._canonical_life_at_event(e.actor_id,e.id)
			var target_life:Dictionary=w._canonical_life_at_event(e.target_id,e.id)
			var helper_pos:Dictionary=w._entity_position_at_event(e.actor_id,e.id)
			var target_pos:Dictionary=w._entity_position_at_event(e.target_id,e.id)
			if not helper_life.get("ok",false) or helper_life.get("life_state","")!="ACTIVE" or not target_life.get("ok",false) or target_life.get("life_state","")!="DOWNED":return "rescue_assist_life_invalid"
			if not helper_pos.get("ok",false) or not target_pos.get("ok",false) or helper_pos.position!=e.position or helper_pos.position.distance_squared_to(target_pos.position)>2:return "rescue_assist_position_invalid"
			var downed=w.event_by_id(int(e.data.get("downed_event_id",-1)))
			if downed==null or downed.type!="entity.downed" or downed.target_id!=e.target_id or downed.id>=e.id or active_links.has(e.actor_id) or e.magnitude!=100:return "rescue_assist_invalid"
			for link in active_links.values():
				if link.target==e.target_id:return "rescue_duplicate_helper"
			active_links[e.actor_id]={"target":e.target_id,"source":e.id,"downed":downed.id,"moved":false}
		elif e.type in ["party.assist_moved","party.assist_ended"]:
			if not active_links.has(e.actor_id) or active_links[e.actor_id].source!=e.cause_id or active_links[e.actor_id].target!=e.target_id:return "rescue_link_invalid"
			if e.type=="party.assist_ended":
				if e.data.size()!=1 or e.data.get("reason") not in ["RELEASE","LIFE_CHANGED"] or e.magnitude!=(100 if e.data.reason=="RELEASE" else 0):return "rescue_release_invalid"
				active_links.erase(e.actor_id)
			else:
				if not e.data.get("from_position") is Array or not e.data.get("to_position") is Array or e.data.from_position.size()!=2 or e.data.to_position.size()!=2:return "rescue_move_invalid"
				var from:=Vector2i(int(e.data.from_position[0]),int(e.data.from_position[1]))
				var to:=Vector2i(int(e.data.to_position[0]),int(e.data.to_position[1]))
				if to!=e.position or from.distance_squared_to(to)>2 or from==to:return "rescue_move_invalid"
				var previous=w.event_by_id(e.id-1)
				if previous==null or previous.type!="action.move" or previous.actor_id!=e.actor_id or previous.world_time!=e.world_time or previous.data.get("from_position")!=[to.x,to.y]:return "rescue_move_driver_invalid"
				active_links[e.actor_id].moved=true
		elif e.type=="party.rescue_completed":
			if e.data.size()!=3 or e.data.get("ruleset_id")!=RULESET or e.magnitude!=1:return "rescue_credit_invalid"
			var source=w.event_by_id(e.cause_id)
			if source==null or source.type!="entity.recovered" or source.target_id!=e.target_id or source.world_time!=e.world_time or source.id>=e.id or credited.has(source.cause_id):return "rescue_credit_invalid"
			if not active_links.has(e.actor_id) or not active_links[e.actor_id].moved or active_links[e.actor_id].target!=e.target_id or int(e.data.get("downed_event_id",-1))!=source.cause_id or int(e.data.get("assist_event_id",-1))!=active_links[e.actor_id].source:return "rescue_credit_link_invalid"
			credited[source.cause_id]=e.id
		elif e.type=="party.rescue_dialogue":
			if e.data.size()!=2 or e.data.get("ruleset_id")!=RULESET:return "rescue_dialogue_invalid"
			var source=w.event_by_id(e.cause_id)
			if source==null or source.type!="party.rescue_completed" or source.id>=e.id or talked.has(source.id) or e.data.get("choice") not in ["REASSURE","PROMISE"] or e.magnitude!=100:return "rescue_dialogue_invalid"
			if not ((source.actor_id==e.actor_id and source.target_id==e.target_id) or (source.actor_id==e.target_id and source.target_id==e.actor_id)):return "rescue_dialogue_pair_invalid"
			talked[source.id]=true
	return ""
