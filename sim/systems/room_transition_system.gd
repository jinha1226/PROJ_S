extends RefCounted
const Rules=preload("res://sim/room_transition_rules.gd")
const RoundRules=preload("res://sim/round_combat_rules.gd")
const RoundState=preload("res://sim/round_combat_state.gd")
const Action=preload("res://sim/party_action_command.gd")
const Field=preload("res://sim/systems/field_turn_system.gd")
const Stage=preload("res://sim/stage_counterplay.gd")

static func begin_exit(sim,id:int,key:String)->Dictionary:
	var w=sim.world;var s:Dictionary=w.party_encounter.nine_room_floor
	var assessment:=Rules.assess(w,id,key,true)
	if not assessment.accepted:return assessment
	if not s.pending_exit.is_empty():return Rules.rejected("room_exit_pending")
	# Leaving an uncleared combat room is a retreat: forbidden in some authored
	# rooms, and always a party-wide stress hit committed here so the morale row
	# shares the request's step index (the round boundary never sees this event).
	var combat:bool=retreating(w)
	if combat and not Stage.retreat_allowed(w):return Rules.rejected("room_retreat_forbidden")
	s.request_serial=int(s.request_serial)+1
	s.pending_exit={"request_id":str(s.request_serial),"actor_id":str(id),"from_room":int(s.active_room_id),"portal_id":key,"stage":"REQUESTED","revision":int(s.revision)}
	var event=w.emit_event("room.exit_requested",id,-1,assessment.exit_cell,0,-1,{"schema_version":1,"request_id":str(s.request_serial),"portal_id":key,"revision":int(s.revision),"combat":combat})
	if event==null:s.pending_exit.clear();return Rules.rejected("room_exit_event_failed")
	if combat and not preload("res://sim/systems/party_morale_system.gd").commit_batch(w,[event],false):return Rules.rejected("room_retreat_stress_failed")
	return assessment

static func retreating(w)->bool:
	return RoundRules.active(w) and not Stage.cleared(w)

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
		if retreating(w) and not Stage.retreat_allowed(w):return Rules.rejected("room_retreat_forbidden")
		var r:Dictionary=w.party_encounter.round_combat
		if RoundRules.individual(w) and id!=RoundRules.current_actor(w):return Rules.rejected("round_not_current_actor")
		if r.phase=="DEPLOYMENT":return Rules.rejected("deployment_confirmation_required")
		if r.phase not in ["PLANNING","INTERRUPTED"]:return Rules.rejected("room_exit_busy")
		# The retreat request owns one existing round boundary; published enemy
		# actions remain frozen. Already completed slots are never replayed.
		var begun:=begin_exit(sim,id,key)
		if not begun.accepted:sim.restore_rollback_memento(rollback);return begun
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
	if not _tick_target(sim,target):return Rules.rejected("room_effect_failed")
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
	_arrive(w,p,int(assessed.target_room),assessed.party_ids,assessed.arrivals,str(request.request_id),false)
	return {"accepted":true,"reason":"ok","transitioned":true}

static func _arrive(w,p:Dictionary,target:int,ids:Array,cells:Array,request_id:String,by_map:bool)->void:
	var s:Dictionary=w.party_encounter.nine_room_floor;var from:int=int(s.active_room_id)
	for index in range(ids.size()):
		var id:int=ids[index];var to:Vector2i=cells[index];var previous:Vector2i=w.entities[id].position
		w.emit_event("room.entered",id,-1,to,0,-1,{"schema_version":1,"ruleset_id":Rules.Generator.RULESET_ID,"portal_id":p.portal_id,"floor_index":int(s.floor_index),"source_room":from,"target_room":target,"from_position":[previous.x,previous.y],"to_position":[to.x,to.y],"request_id":request_id,"travel":by_map})
		w.entities[id].position=to;w.reindex_entity_occupancy(id,previous,to)
	s.active_room_id=target;s.pending_exit.clear();s.revision=int(s.revision)+1
	for key in Rules.current_floor(w).rooms[target].exits:
		if key not in s.discovered_portals:s.discovered_portals.append(key)
	var visit:="%d:%d"%[s.floor_index,target]
	if visit not in s.visited:s.visited.append(visit)
	if p.portal_id not in s.discovered_portals:s.discovered_portals.append(p.portal_id)
	w.party_encounter.group_anchor=w.entities[w.party_encounter.protagonist_id].position
	var old_round:Dictionary=w.party_encounter.round_combat
	var next_round:=RoundState.fresh();next_round.round_id=int(old_round.round_id);next_round.plan_revision=int(old_round.plan_revision)+1
	next_round.stage_rooms=old_round.stage_rooms.duplicate(true)
	w.party_encounter.round_combat=next_round
	w.party_encounter.safe_phase="GROUPED";w.party_encounter.contact_kind="NONE";w.party_encounter.contact_enemy_id=-1;w.party_encounter.formation_id="NONE"
	w.set_meta("room_transition_visual",{"from_room":from,"to_room":target,"direction":Rules.membership(cells[0]),"revision":int(s.revision),"portal_id":p.portal_id})

static func _tick_target(sim,target:int)->bool:
	var w=sim.world;var s:Dictionary=w.party_encounter.nine_room_floor
	var room_key:="%d:%d"%[s.floor_index,target];var processed:int=int(s.effect_processed_at.get(room_key,"0"))
	var membership:=Vector2i(int(s.floor_index),target)
	if not preload("res://sim/consumable_effects.gd").tick(sim,processed,w.world_time,membership) or not preload("res://sim/abilities/monster_ability_runtime.gd").tick(sim,processed,w.world_time,membership):return false
	s.effect_processed_at[room_key]=str(w.world_time)
	return sim.party_coordinator.reconcile_liveness(false)

static func travel(sim,room_id:int,revision:int)->Dictionary:
	var w=sim.world
	if not Rules.enabled(w) or not w.is_settled():return Rules.rejected("room_exit_unavailable")
	var s:Dictionary=w.party_encounter.nine_room_floor
	if int(s.revision)!=revision:return Rules.rejected("room_revision_changed")
	if not s.pending_exit.is_empty():return Rules.rejected("room_exit_pending")
	if RoundRules.active(w) and not preload("res://sim/stage_counterplay.gd").cleared(w):return Rules.rejected("room_combat_active")
	var current:int=int(s.active_room_id);var p:Dictionary={}
	for candidate in Rules.portals(w):
		if candidate.portal_id in s.discovered_portals and [int(candidate.a),int(candidate.b)] in [[current,room_id],[room_id,current]]:p=candidate;break
	if p.is_empty():return Rules.rejected("room_not_adjacent")
	var ids:Array=Rules.party_ids(w)
	for id in ids:
		if not w.can_act(id,w.world_time) or preload("res://sim/abilities/monster_ability_runtime.gd").anchored(w,id):return Rules.rejected("room_party_cannot_move")
	var cells:Array=Rules.arrivals(w,p,room_id,ids)
	if cells.is_empty():return Rules.rejected("room_arrival_full")
	var start:int=w.events.size();var rollback:Dictionary=w.rollback_memento(false)
	if not _tick_target(sim,room_id):sim.restore_rollback_memento(rollback);return Rules.rejected("room_effect_failed")
	s.request_serial=int(s.request_serial)+1
	_arrive(w,p,room_id,ids,cells,"TRAVEL_%d"%int(s.request_serial),true)
	return {"accepted":true,"reason":"ok","transitioned":true,"time_cost":0,"events_start":start,"events_end":w.events.size()}

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
