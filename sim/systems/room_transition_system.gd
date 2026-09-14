extends RefCounted
const Rules=preload("res://sim/room_transition_rules.gd")
const RoundRules=preload("res://sim/round_combat_rules.gd")
const RoundState=preload("res://sim/round_combat_state.gd")
const Action=preload("res://sim/party_action_command.gd")
const Field=preload("res://sim/systems/field_turn_system.gd")

static func begin_exit(sim,id:int,key:String)->Dictionary:
	var w=sim.world;var s:Dictionary=w.party_encounter.nine_room_floor
	var assessment:=Rules.assess(w,id,key,true)
	if not assessment.accepted:return assessment
	if not s.pending_exit.is_empty():return Rules.rejected("room_exit_pending")
	s.request_serial=int(s.request_serial)+1
	s.pending_exit={"request_id":str(s.request_serial),"actor_id":str(id),"from_room":int(s.active_room_id),"portal_id":key,"stage":"REQUESTED","revision":int(s.revision)}
	w.emit_event("room.exit_requested",id,-1,assessment.exit_cell,0,-1,{"schema_version":1,"request_id":str(s.request_serial),"portal_id":key,"revision":int(s.revision)})
	return assessment

static func request(sim,id:int,key:String,revision:int)->Dictionary:
	var w=sim.world
	if not Rules.enabled(w) or not w.is_settled():return Rules.rejected("room_exit_unavailable")
	var s:Dictionary=w.party_encounter.nine_room_floor
	if int(s.revision)!=revision:return Rules.rejected("room_revision_changed")
	var assessed:=Rules.assess(w,id,key,true)
	if not assessed.accepted:return assessed
	var start_event:int=w.events.size()
	var rollback:Dictionary=w.rollback_memento(false)
	if RoundRules.active(w):
		var r:Dictionary=w.party_encounter.round_combat
		if RoundRules.individual(w) and id!=RoundRules.current_actor(w):return Rules.rejected("round_not_current_actor")
		if r.phase=="DEPLOYMENT":return Rules.rejected("deployment_confirmation_required")
		if r.phase not in ["PLANNING","INTERRUPTED"]:return Rules.rejected("room_exit_busy")
		# The retreat request owns one existing round boundary; published enemy
		# actions remain frozen. Already completed slots are never replayed.
		var begun:=begin_exit(sim,id,key)
		if not begun.accepted:return begun
		var result:Dictionary=load("res://sim/systems/round_combat_system.gd").confirm(sim,int(r.round_id),int(r.plan_revision),r.phase=="INTERRUPTED")
		if not result.accepted:sim.restore_rollback_memento(rollback);return result
		return result.merged({"transitioned":int(sim.world.party_encounter.nine_room_floor.active_room_id)!=int(assessed.source_room),"reason":exit_reason(sim.world,start_event)},true)
	var begun:=begin_exit(sim,id,key)
	if not begun.accepted:return begun
	# Normal exploration movement already contains its terrain/injury cost.
	var step=Field.step(sim,Action.move_to(id,assessed.exit_cell))
	if not step.accepted:sim.restore_rollback_memento(rollback);return Rules.rejected(step.reason)
	var result:=resolve_pending_exit(sim)
	return {"accepted":true,"reason":exit_reason(sim.world,start_event),"transitioned":int(sim.world.party_encounter.nine_room_floor.active_room_id)!=int(assessed.source_room),"time_cost":step.time_cost,"events_start":start_event,"events_end":sim.world.events.size()}

static func resolve_pending_exit(sim)->Dictionary:
	var w=sim.world
	if not Rules.enabled(w):return {"accepted":true,"reason":"ok","transitioned":false}
	var s:Dictionary=w.party_encounter.nine_room_floor
	if s.pending_exit.is_empty():return {"accepted":true,"reason":"ok","transitioned":false}
	var request:Dictionary=s.pending_exit.duplicate(true)
	var connection:=Rules.portal(w,str(request.portal_id))
	var target:int=int(connection.b) if int(connection.a)==int(s.active_room_id) else int(connection.a)
	var room_key:="%d:%d"%[s.floor_index,target]
	var processed:int=int(s.effect_processed_at.get(room_key,"0"))
	var target_membership:=Vector2i(int(s.floor_index),target)
	if not preload("res://sim/consumable_effects.gd").tick(sim,processed,w.world_time,target_membership) or not preload("res://sim/abilities/monster_ability_runtime.gd").tick(sim,processed,w.world_time,target_membership):return Rules.rejected("room_effect_failed")
	s.effect_processed_at[room_key]=str(w.world_time)
	if not sim.party_coordinator.reconcile_liveness(false):return Rules.rejected("room_effect_failed")
	var assessed:=Rules.assess(w,int(request.actor_id),str(request.portal_id))
	if not assessed.accepted:
		s.pending_exit.clear();s.revision=int(s.revision)+1
		w.emit_event("room.exit_failed",int(request.actor_id),-1,w.entities[int(request.actor_id)].position,0,-1,{"request_id":request.request_id,"reason":assessed.reason})
		return {"accepted":true,"reason":assessed.reason,"transitioned":false}
	var p:=Rules.portal(w,str(request.portal_id));var pursuers:Array=[]
	for id in sim.party_coordinator._stream_enemy_ids():
		var awareness=w.party_encounter.enemy_awareness(id)
		if not w.can_act(id,w.world_time) or Rules.queued(w,id) or awareness==null or awareness.awareness_state not in ["HUNTING","ALERT","SEARCHING"] or preload("res://sim/abilities/monster_ability_runtime.gd").anchored(w,id):continue
		if Rules.path_distance(w,w.entities[id].position,assessed.exit_cell,int(Rules.Generator.CONFIG.pursuit_distance))>=0:pursuers.append(id)
	pursuers.sort();pursuers=pursuers.slice(0,int(Rules.Generator.CONFIG.pursuit_limit))
	for id in pursuers:
		s.pending_pursuit.append({"entity_id":str(id),"floor_index":int(s.floor_index),"source_room":int(s.active_room_id),"target_room":int(assessed.target_room),"portal_id":p.portal_id,"eligible_boundary":int(s.action_boundary)+2})
	var from:int=s.active_room_id
	for index in range(assessed.party_ids.size()):
		var id:int=assessed.party_ids[index];var to:Vector2i=assessed.arrivals[index];var previous:Vector2i=w.entities[id].position
		w.emit_event("room.entered",id,-1,to,0,-1,{"schema_version":1,"ruleset_id":Rules.Generator.RULESET_ID,"portal_id":p.portal_id,"floor_index":int(s.floor_index),"source_room":from,"target_room":int(assessed.target_room),"from_position":[previous.x,previous.y],"to_position":[to.x,to.y],"request_id":request.request_id})
		w.entities[id].position=to;w.reindex_entity_occupancy(id,previous,to)
	s.active_room_id=int(assessed.target_room);s.pending_exit.clear();s.revision=int(s.revision)+1
	for key in Rules.current_floor(w).rooms[int(s.active_room_id)].exits:
		if key not in s.discovered_portals:s.discovered_portals.append(key)
	var visit:="%d:%d"%[s.floor_index,s.active_room_id]
	if visit not in s.visited:s.visited.append(visit)
	if p.portal_id not in s.discovered_portals:s.discovered_portals.append(p.portal_id)
	w.party_encounter.group_anchor=w.entities[w.party_encounter.protagonist_id].position
	var old_round:Dictionary=w.party_encounter.round_combat
	var next_round:=RoundState.fresh();next_round.round_id=int(old_round.round_id);next_round.plan_revision=int(old_round.plan_revision)+1
	next_round.stage_rooms=old_round.stage_rooms.duplicate(true)
	w.party_encounter.round_combat=next_round
	w.party_encounter.safe_phase="GROUPED";w.party_encounter.contact_kind="NONE";w.party_encounter.contact_enemy_id=-1;w.party_encounter.formation_id="NONE"
	w.set_meta("room_transition_visual",{"from_room":from,"to_room":int(s.active_room_id),"direction":Rules.membership(assessed.arrivals[0]),"revision":int(s.revision),"portal_id":p.portal_id})
	return {"accepted":true,"reason":"ok","transitioned":true}

static func boundary(sim)->bool:
	var w=sim.world
	if not Rules.enabled(w):return true
	var s:Dictionary=w.party_encounter.nine_room_floor;s.action_boundary=int(s.action_boundary)+1
	s.effect_processed_at["%d:%d"%[s.floor_index,s.active_room_id]]=str(w.world_time)
	# No arrival during a retreat boundary: player response happens in the new
	# room first. Waiting clocks persist across repeated room transitions.
	if not s.pending_exit.is_empty():return true
	var remaining:Array=[];var arrived_cells:Array=[]
	for row in s.pending_pursuit:
		var id:=int(row.entity_id)
		if not w.is_unresolved_enemy(id):continue
		if int(row.floor_index)!=int(s.floor_index) or int(row.target_room)!=int(s.active_room_id) or int(s.action_boundary)<int(row.eligible_boundary):remaining.append(row);continue
		var p:=Rules.portal(w,str(row.portal_id));var cells:=Rules.arrivals(w,p,int(row.target_room),[id],arrived_cells)
		if cells.is_empty():remaining.append(row);continue
		var previous:Vector2i=w.entities[id].position;var to:Vector2i=cells[0];arrived_cells.append(to)
		w.emit_event("room.pursuit_arrived",id,-1,to,0,-1,{"schema_version":1,"ruleset_id":Rules.Generator.RULESET_ID,"portal_id":p.portal_id,"floor_index":int(s.floor_index),"source_room":int(row.source_room),"target_room":int(row.target_room),"from_position":[previous.x,previous.y],"to_position":[to.x,to.y],"request_id":"PURSUIT_"+row.entity_id})
		w.entities[id].position=to;w.reindex_entity_occupancy(id,previous,to)
		w.party_encounter.enemy_busy_rows[id]=w.world_time+100
		var awareness=w.party_encounter.enemy_awareness(id)
		if awareness!=null:awareness.last_known_target_position=w.entities[w.party_encounter.protagonist_id].position
		s.revision=int(s.revision)+1
	s.pending_pursuit=remaining
	return true

static func exit_reason(w,event_start:int)->String:
	for event in w.events_since(event_start):
		if event.type=="room.exit_failed":return str(event.data.reason)
	return "ok"
