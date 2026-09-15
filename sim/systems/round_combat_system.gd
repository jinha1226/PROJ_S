extends RefCounted
const Rules=preload("res://sim/round_combat_rules.gd")
const State=preload("res://sim/round_combat_state.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const Action=preload("res://sim/party_action_command.gd")
const Field=preload("res://sim/field_turn_rules.gd")
const Turns=preload("res://sim/systems/field_turn_system.gd")
const Skills=preload("res://sim/abilities/party_active_skill_service.gd")
const Items=preload("res://sim/world_item_operations.gd")
const Timing=preload("res://sim/field_action_timing.gd")
static var last_execution_error:=""
const Queue=preload("res://sim/systems/field_actor_queue.gd")

static func newly_visible(w,r:Dictionary)->Array:
	var result:Array=[]
	for id in w.party_encounter.enemy_ids:
		if str(id) not in r.known_enemy_ids and Field.visible(w,id):result.append(id)
	return result

static func incorporate(sim)->void:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	var ids:=newly_visible(w,r)
	if ids.is_empty():return
	var telegraphs:Dictionary={} if Rules.individual(w) else preload("res://sim/enemy_telegraph_rules.gd").plans(sim)
	# Newly discovered actors append after the existing unexecuted suffix;
	# no old participant loses its published position in the order.
	for key in Rules.order(w,ids):
		var id:=int(key);var action=Action.hold(id)
		if telegraphs.has(id):
			var row:Dictionary=telegraphs[id]
			if row.action_type=="MELEE":action=Action.melee(id,int(row.target_id))
			elif row.action_type=="MOVE" and not preload("res://sim/stage_counterplay.gd").enabled(w):action=Action.move_to(id,Vector2i(row.destination[0],row.destination[1]))
		var path:Array=[[action.destination.x,action.destination.y]] if action.type=="MOVE" else []
		r.order.append(key);r.participants.append(key);r.known_enemy_ids.append(key)
		r.plans[key]=Plans.pack(w,action,"AI",path)
	r.plan_revision=int(r.plan_revision)+1

static func confirm(sim,round_id:int,revision:int,resuming:bool=false,preview:bool=false)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	if r.phase=="DEPLOYMENT" and not resuming:
		if not Rules.enabled(w) or not w.is_settled():return Plans.reject("round_not_ready")
		if int(r.round_id)!=round_id or int(r.plan_revision)!=revision:return Plans.reject("round_revision_changed")
		return preload("res://sim/stage_counterplay.gd").deploy(sim)
	if not Rules.enabled(w) or r.phase not in (["INTERRUPTED"] if resuming else ["PLANNING"]):return Plans.reject("round_not_ready")
	if int(r.round_id)!=round_id or int(r.plan_revision)!=revision:return Plans.reject("round_revision_changed")
	if not w.is_settled():return Plans.reject("round_world_busy")
	var rollback:Dictionary=w.rollback_memento(false)
	var start_event:int=w.events.size();var step:int=w.step_index+1
	var darkness_sample:=Turns.Darkness.begin_sample(w)
	r.phase="RESOLVING";r.interrupt_reason=""
	w.begin_step(step)
	last_execution_error=""
	var rows:Array=[];var ok:=true
	var individual:=Rules.individual(w)
	var ally_acted:=false
	var initial_ally:bool=w.party_encounter.member(Rules.current_actor(w))!=null
	while int(r.execution_cursor)<r.order.size():
		var key:String=r.order[int(r.execution_cursor)];var id:=int(key)
		var ally:bool=w.party_encounter.member(id)!=null
		if individual and (ally_acted or not initial_ally) and ally and w.can_act(id,w.world_time) and Rules.engaged(w) and w.party_encounter.nine_room_floor.pending_exit.is_empty():
			r.phase="PLANNING";break
		var plan:Dictionary=r.plans[key]
		var retreating:bool=preload("res://sim/room_transition_rules.gd").enabled(w) and not w.party_encounter.nine_room_floor.pending_exit.is_empty()
		var slot:Dictionary
		if retreating and w.party_encounter.member(id)!=null:
			slot={"accepted":true,"actor_id":id,"status":"CANCELLED","reason":"party_retreat","movement":[],"damage":[],"conditional":false}
		elif individual and not Rules.engaged(w):slot={"accepted":true,"actor_id":id,"status":"CANCELLED","reason":"combat_ended","movement":[],"damage":[],"conditional":false}
		elif individual and not ally:slot=execute_individual_enemy(sim,id,step,preview)
		elif individual and ally:slot=execute_individual_ally(sim,plan,step,preview)
		else:slot=execute_slot(sim,plan,step,preview)
		rows.append(slot)
		if not slot.get("accepted",false):
			last_execution_error+="/slot/%s/%s"%[key,slot.get("reason","")]
			ok=false;break
		if slot.get("interrupted",false):
			r.phase="INTERRUPTED";r.interrupt_reason="new_threat";break
		if individual:
			incorporate(sim)
			if ally:
				ally_acted=true
			# Opportunity budgets replace sub-action cooldown in this ruleset.
			if ally:w.party_encounter.member(id).busy_until=w.world_time+Rules.ROUND_TIME
			else:w.party_encounter.enemy_busy_rows[id]=w.world_time+Rules.ROUND_TIME
		if key not in r.completed_actor_ids:r.completed_actor_ids.append(key)
		r.execution_cursor=int(r.execution_cursor)+1
		if not (preload("res://sim/room_transition_rules.gd").enabled(w) and not w.party_encounter.nine_room_floor.pending_exit.is_empty()) and not individual and not newly_visible(w,r).is_empty():r.phase="INTERRUPTED";r.interrupt_reason="new_threat";break
	if ok and int(r.execution_cursor)>=r.order.size():
		ok=finish_time(sim,step,darkness_sample,start_event)
		if ok and preload("res://sim/stage_counterplay.gd").enabled(w):ok=preload("res://sim/stage_counterplay.gd").finish_round(sim)
		if not ok and last_execution_error.is_empty():last_execution_error="time"
		if ok:
			r.round_time_committed=true;r.last_boundary_time=str(w.world_time)
			r.phase="EXPLORATION"
			var transition:Dictionary=preload("res://sim/systems/room_transition_system.gd").resolve_pending_exit(sim)
			ok=bool(transition.accepted)
	if ok:
		w.finish_step()
		ok=w.runtime_step_postcondition_error(start_event).is_empty()
	if not ok:
		w.finish_step()
		last_execution_error+="/"+w.runtime_step_postcondition_error(start_event)
		sim.restore_rollback_memento(rollback)
		return Plans.reject("round_execution_failed")
	var completed:bool=bool(r.round_time_committed)
	if individual:r.plan_revision=int(r.plan_revision)+1
	if completed:ok=Plans.begin(sim)
	if not ok:
		sim.restore_rollback_memento(rollback);return Plans.reject("round_plan_failed")
	return {"accepted":true,"reason":"interrupted" if r.phase=="INTERRUPTED" else "actor_action" if not completed else "ok",
		"completed":completed,"time_cost":Rules.ROUND_TIME if completed else 0,
		"slots":rows,"events_start":start_event,"events_end":w.events.size()}

static func execute_individual_ally(sim,plan:Dictionary,step:int,preview:bool)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	var id:=int(plan.actor_id);var key:=str(id)
	var result:=execute_slot(sim,plan,step,preview)
	if not result.accepted or result.get("interrupted",false) or plan.action.type!="MELEE" or not plan.item_operation.is_empty():return result
	if result.status!="DONE":return result
	r.slot_attacks[key]=int(r.slot_attacks.get(key,0))+1
	while Rules.remaining_attacks(w,id)>0 and w.can_act(id,w.world_time) and w.is_explicit_melee_target(int(plan.action.target_id)):
		var followup:=execute_slot(sim,Plans.pack(w,Action.melee(id,int(plan.action.target_id)),"USER"),step,preview)
		if not followup.accepted:return followup
		result.damage.append_array(followup.damage)
		if followup.status!="DONE":break
		r.slot_attacks[key]=int(r.slot_attacks.get(key,0))+1
	return result

static func execute_individual_enemy(sim,id:int,step:int,preview:bool)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat;var key:=str(id)
	var result:={"accepted":true,"actor_id":id,"status":"DONE","reason":"ok","movement":[],"damage":[],"conditional":false,"from_position":[w.entities[id].position.x,w.entities[id].position.y]}
	if not w.can_act(id,w.world_time):return cancel(result,"incapacitated")
	var movement_event=w.emit_event("stage.enemy_movement",id,-1,w.entities[id].position,0,-1,{"round_id":r.round_id,"room":preload("res://sim/stage_counterplay.gd").key(w)})
	if movement_event==null:result.accepted=false;return result
	# Forecast each leaf on this actor's turn, after earlier actors have acted.
	for i in range(Rules.move_budget(w,id)):
		var forecast:Dictionary=sim.party_coordinator.forecast_enemy_action(id)
		if forecast.get("action_type","")!="MOVE":break
		var path:Array=[forecast.destination]
		r.slot_progress[key]=0
		var move:Dictionary=execute_slot(sim,Plans.pack(w,Action.hold(id),"AI",path),step,preview,movement_event.id)
		if not move.accepted:return move
		result.movement.append_array(move.movement)
		if move.movement.is_empty() or not w.can_act(id,w.world_time):break
	for i in range(Rules.attack_budget(w,id)):
		var forecast:Dictionary=sim.party_coordinator.forecast_enemy_action(id)
		if forecast.get("action_type","")!="MELEE" or not w.can_act(id,w.world_time):break
		r.slot_progress[key]=0
		var attack:Dictionary=execute_slot(sim,Plans.pack(w,Action.melee(id,int(forecast.target_id)),"AI"),step,preview)
		if not attack.accepted:return attack
		result.damage.append_array(attack.damage)
		if attack.status!="DONE":break
		r.slot_attacks[key]=int(r.slot_attacks.get(key,0))+1
	r.slot_progress[key]=0
	result["end_position"]=[w.entities[id].position.x,w.entities[id].position.y]
	return result

static func execute_slot(sim,p:Dictionary,step:int,preview:bool=false,movement_cause:int=-1)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat;var id:=int(p.actor_id)
	var result:={"accepted":true,"actor_id":id,"status":"DONE","reason":"ok","movement":[],"damage":[],"conditional":false,"from_position":[w.entities[id].position.x,w.entities[id].position.y]}
	if not w.can_act(id,w.world_time):return cancel(result,"incapacitated")
	var member=w.party_encounter.member(id)
	if not Rules.individual(w) and member==null and preload("res://sim/stage_counterplay.gd").enabled(w) and [w.entities[id].position.x,w.entities[id].position.y]!=p.origin:return cancel(result,"attack_displaced")
	if not Rules.individual(w) and member!=null and member.busy_until>w.world_time:return cancel(result,"cooldown")
	var progress:int=r.slot_progress.get(p.actor_id,0)
	var spent:int=r.slot_spent.get(p.actor_id,0)
	var budget:=mini(int(p.move_budget),Rules.move_budget(w,id))
	for index in range(progress,p.path.size()):
		if not (preload("res://sim/room_transition_rules.gd").enabled(w) and not w.party_encounter.nine_room_floor.pending_exit.is_empty()) and not Rules.individual(w) and not newly_visible(w,r).is_empty():result.interrupted=true;result.conditional=true;return result
		var cell:=Vector2i(p.path[index][0],p.path[index][1]);var cost:=Rules.terrain_cost(w,cell)
		var assessment=sim.movement.assess_move(id,cell)
		if spent+cost>budget or not assessment.accepted:
			result.reason="move_budget" if spent+cost>budget else "path_blocked";break
		var exit:Dictionary=preload("res://sim/room_transition_rules.gd").portal_at(w,cell) if id==w.party_encounter.protagonist_id else {}
		if not exit.is_empty():
			var exit_check:Dictionary=preload("res://sim/systems/room_transition_system.gd").begin_exit(sim,id,exit.portal_id)
			if not exit_check.accepted:return cancel(result,exit_check.reason)
		var event=sim.movement.commit_preflighted_move(id,cell,str(assessment.terrain_id),
			Timing.duration(w,id,"MOVE",int(preload("res://sim/terrain_registry.gd").definition(str(assessment.terrain_id)).move_time_cost)),movement_cause)
		if event==null:result.accepted=false;return result
		spent+=cost;r.slot_progress[p.actor_id]=index+1;r.slot_spent[p.actor_id]=spent
		result.movement.append([cell.x,cell.y])
		load("res://sim/nine_room_care_rules.gd").mark_combat(w,id)
		if not after_leaf(sim,w.events.size()-1):result.accepted=false;return result
		if not (preload("res://sim/room_transition_rules.gd").enabled(w) and not w.party_encounter.nine_room_floor.pending_exit.is_empty()) and not Rules.individual(w) and not newly_visible(w,r).is_empty():result.interrupted=true;result.conditional=true;return result
	if preload("res://sim/room_transition_rules.gd").enabled(w) and not w.party_encounter.nine_room_floor.pending_exit.is_empty() and member!=null:return cancel(result,"party_retreat")
	var action=Action.from_dict(p.action)
	if action==null:result.accepted=false;return result
	if member==null and action.type=="MELEE" and preload("res://sim/stage_counterplay.gd").enabled(w):
		return execute_stage_attack(sim,p,step,result)
	if action.type in ["MELEE","SKILL"] and p.target_policy=="CELL" and action.target_id>0:
		action.target_id=-1
		for target in w.entities.values():
			if target.id==id or not w.is_explicit_melee_target(target.id):continue
			if [target.position.x,target.position.y]==p.target_cell:action.target_id=target.id;break
		if action.target_id<1:return cancel(result,"target_cell_empty")
	if action.type in ["MELEE","SKILL"] and action.target_id>0 and not w.is_explicit_melee_target(action.target_id):return cancel(result,"target_gone")
	var event_start:int=w.events.size();var accepted:=false
	if not p.item_operation.is_empty():
		var item_events:int=w.events.size()
		var item_result:=preload("res://sim/round_item_rules.gd").commit(sim,id,p.item_operation)
		if not item_result.get("accepted",false):
			if sim.world!=w or w.events.size()!=item_events:
				result.accepted=false;return result
			return cancel(result,str(item_result.get("reason","item_unavailable")))
		accepted=true
	elif action.type=="SKILL":
		var assessment:Dictionary=Skills.assess(w,id,action.skill_id,action.target_id,false,true,action.destination)
		if not assessment.get("accepted",false):return cancel(result,str(assessment.get("reason","skill_unavailable")))
		accepted=sim._commit_skill_effect(id,action.skill_id,action.target_id,assessment,step)!=null
	elif action.type=="MELEE":
		# Host hostility checks remain in ordinary commands. This fixed-cell
		# resolver alone may hit any occupant, including another enemy.
		var weapon_id:String=Items.equipped_weapon_id(w,id) if sim.party_coordinator._uses_weapon_combat(id) else ""
		if not weapon_id.is_empty() and not Items.attack_error(w,id).is_empty():return cancel(result,"weapon_unavailable")
		var strike_commitment:=("%s/strike/%d"%[r.rng_commitment,int(r.slot_attacks.get(p.actor_id,0))]).sha256_text() if Rules.individual(w) else str(r.rng_commitment)
		var context:="ROUND_ACTOR/%d/%s/%s/%d/%d"%[int(r.round_id),strike_commitment,p.actor_id,step,w.world_time]
		var assessment:Dictionary=sim.melee.assess_attack(id,action.target_id,"DIRECT" if p.source=="USER" else "SUGGESTED",step,w.world_time,context,0,weapon_id,
			sim.party_coordinator._weapon_occupants(id,action.target_id) if not weapon_id.is_empty() else {})
		if assessment.is_empty():return cancel(result,"attack_out_of_range")
		var cost:int=Timing.duration(w,id,"MELEE",int(assessment.get("attack_time",100)))
		accepted=sim._commit_active_ready_allies([{"action":action.to_dict(),"time_cost":cost,"combat_assessment":assessment}],step,w.world_time)
	else:
		# A move-only opportunity does not gain a free defensive HOLD buff.
		if not p.path.is_empty():accepted=true
		elif member!=null:accepted=Turns._commit_ally(sim,Action.hold(id),step,100)
		else:accepted=sim.party_coordinator._commit_hold(id,100)!=null
	result.accepted=accepted
	if not accepted:return result
	if not p.item_operation.is_empty() or action.type in ["MELEE","SKILL"]:load("res://sim/nine_room_care_rules.gd").deny_combat(w,id)
	if not after_leaf(sim,event_start):result.accepted=false;return result
	for event in w.events_since(event_start):
		if event.type.begins_with("combat.") and event.type.ends_with("_damage"):
			result.damage.append({"target_id":event.target_id,"amount":event.magnitude})
	if member!=null and p.item_operation.is_empty() and action.type not in ["MELEE","SKILL"] and (p.path.is_empty() or not result.movement.is_empty()):load("res://sim/nine_room_care_rules.gd").mark_combat(w,id)
	result["end_position"]=[w.entities[id].position.x,w.entities[id].position.y]
	return result

static func cancel(result:Dictionary,reason:String)->Dictionary:
	result.status="CANCELLED";result.reason=reason;return result

static func execute_stage_attack(sim,p:Dictionary,step:int,result:Dictionary)->Dictionary:
	var w=sim.world;var id:=int(p.actor_id)
	var cells:Array[Vector2i]=preload("res://sim/stage_enemy_rules.gd").cells(w,id,Vector2i(p.origin[0],p.origin[1]),Vector2i(p.target_cell[0],p.target_cell[1]))
	var targets:Array=[]
	for target in w.entities.values():
		if target.id!=id and target.position in cells and w.is_explicit_melee_target(target.id):targets.append(target.id)
	targets.sort()
	if targets.is_empty():return cancel(result,"target_cell_empty")
	var start:int=w.events.size();var strikes:=0
	for target in targets:
		if not w.can_act(id,w.world_time) or w.entities[id].position!=Vector2i(p.origin[0],p.origin[1]):break
		if w.entities[target].position not in cells:continue
		var leaf_start:int=w.events.size()
		var r:Dictionary=w.party_encounter.round_combat
		var target_commitment:=("%s/target/%d/strike/%d"%[r.rng_commitment,target,int(r.slot_attacks.get(p.actor_id,0))]).sha256_text()
		var context:="ROUND_ACTOR/%d/%s/%s/%d/%d"%[int(r.round_id),target_commitment,p.actor_id,step,w.world_time]
		var assessment:Dictionary=sim.melee.assess_attack(id,target,"SUGGESTED",step,w.world_time,context,0)
		if assessment.is_empty():continue
		var action=Action.melee(id,target)
		if not sim._commit_active_ready_allies([{"action":action.to_dict(),"time_cost":100,"combat_assessment":assessment}],step,w.world_time):
			result.accepted=false;return result
		strikes+=1
		if not after_leaf(sim,leaf_start):result.accepted=false;return result
	if strikes==0:return cancel(result,"attack_out_of_range")
	for event in w.events_since(start):
		if event.type.begins_with("combat.") and event.type.ends_with("_damage"):result.damage.append({"target_id":event.target_id,"amount":event.magnitude})
	return result

static func after_leaf(sim,event_start:int)->bool:
	if not preload("res://sim/abilities/monster_passive_service.gd").commit(sim,event_start):last_execution_error="passive";return false
	if not preload("res://sim/abilities/monster_ability_runtime.gd").reactions(sim,event_start):last_execution_error="reaction";return false
	if not Turns._social(sim,event_start,false):last_execution_error="social";return false
	if not sim.party_coordinator.reconcile_liveness(false):last_execution_error="liveness";return false
	sim.world.party_encounter.group_anchor=sim.world.entities[sim.world.party_control_actor_id()].position
	return true

static func finish_time(sim,step:int,sample:Dictionary,event_start:int)->bool:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	if r.round_time_committed:return false
	var start:int=int(r.round_start_time);var end:int=start+Rules.ROUND_TIME
	if end>sim.MAX_WORLD_TIME:return false
	var q=Queue.new();q.excluded_ids=r.participants.map(func(id):return int(id))
	for id in w.party_encounter.active_party_member_ids:
		if id not in q.excluded_ids:q.excluded_ids.append(id)
	var hold=Action.hold(w.party_encounter.protagonist_id)
	var known_plans:Dictionary=preload("res://sim/enemy_telegraph_rules.gd").plans(sim)
	var acted:Dictionary={}
	while true:
		var next:Dictionary=q.next(sim,end)
		if next.is_empty():break
		if not Turns._dispatch_kernel_action(sim,next,hold,step,sample,known_plans,acted):return false
		q.completed(sim,int(next.id))
	w.world_time=end
	if not preload("res://sim/abilities/monster_ability_runtime.gd").tick(sim,start,end):return false
	if not preload("res://sim/consumable_effects.gd").tick(sim,start,end):return false
	if not Turns.Darkness.commit_boundary(w,start,end,sample):return false
	w.party_encounter.group_anchor=w.entities[w.party_control_actor_id()].position
	if not load("res://sim/nine_room_care_rules.gd").finish_combat(w):return false
	if not preload("res://sim/systems/room_transition_system.gd").boundary(sim):return false
	sim._reconcile_expedition_cycle()
	return sim.party_coordinator.reconcile_liveness(false)
