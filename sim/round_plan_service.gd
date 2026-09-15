extends RefCounted
const Rules=preload("res://sim/round_combat_rules.gd")
const State=preload("res://sim/round_combat_state.gd")
const Action=preload("res://sim/party_action_command.gd")
const FieldTurns=preload("res://sim/systems/field_turn_system.gd")
const Field=preload("res://sim/field_turn_rules.gd")

static func pack(w,action,source:String,path:Array=[])->Dictionary:
	var actor=w.entities[action.actor_id]
	var origin:Vector2i=actor.position
	var destination:Vector2i=Vector2i(path.back()[0],path.back()[1]) if not path.is_empty() else origin
	var target:Vector2i=action.destination if action.destination!=Vector2i(-1,-1) and action.type=="SKILL" else w.entities[action.target_id].position if w.entities.has(action.target_id) else Vector2i(-1,-1)
	var final_action=Action.hold(action.actor_id) if action.type=="MOVE" else action
	var entity_policy:bool=action.type=="SKILL" and preload("res://sim/abilities/active_skill_registry.gd").definition(action.skill_id).get("target","") in ["ALLY","SELF"]
	return {"actor_id":str(action.actor_id),"item_operation":{},"source":source,"origin":[origin.x,origin.y],
		"destination":[destination.x,destination.y],"path":path.duplicate(true),
		"action":final_action.to_dict(),"target_policy":"ENTITY" if entity_policy or Rules.individual(w) else "CELL",
		"target_cell":[target.x,target.y],"anchor":"WORLD_TILE","move_budget":Rules.move_budget(w,action.actor_id)}

static func begin(sim)->bool:
	var w=sim.world
	if not Rules.enabled(w):return true
	var previous:Dictionary=w.party_encounter.round_combat
	if previous.phase in ["DEPLOYMENT","PLANNING","RESOLVING","INTERRUPTED"]:return true
	if not Rules.engaged(w):return true
	var r:=State.fresh();r.round_id=int(previous.round_id)+1;r.plan_revision=int(previous.plan_revision)+1
	r.phase="PLANNING";r.round_start_time=str(w.world_time);r.last_boundary_time=previous.last_boundary_time
	r.stage_rooms=previous.stage_rooms.duplicate(true)
	var staged:bool=preload("res://sim/stage_counterplay.gd").enabled(w)
	if staged and not preload("res://sim/stage_counterplay.gd").prepare(sim,r):return false
	var ids:Array=[]
	for id in w.party_encounter.active_party_member_ids:
		if w.party_encounter.member(id).presence=="DEPLOYED" and w.occupies_tile(id):ids.append(id)
	for id in Rules.relevant_enemies(w):
		# Hidden pursuers keep combat engaged, but are never disclosed or given
		# an invisible party-slot attack. They continue pursuit at world ticks.
		if Field.visible(w,id):ids.append(id);r.known_enemy_ids.append(str(id))
	r.order=Rules.order(w,ids);r.participants=r.order.duplicate()
	r.rng_commitment=("round-v1/%d/%d/%d"%[w.seed,r.round_id,w.world_time]).sha256_text()
	var hold=Action.hold(w.party_encounter.protagonist_id)
	var board:Dictionary=FieldTurns.Board.build(w,hold)
	var enemy_plans:Dictionary={} if staged else preload("res://sim/enemy_telegraph_rules.gd").plans(sim)
	for id_wire in r.order:
		var id:=int(id_wire);var action=Action.hold(id)
		if w.party_encounter.member(id)!=null:
			if not staged and r.phase!="DEPLOYMENT" and id!=w.party_encounter.protagonist_id and w.can_act(id,w.world_time):
				var decision:Dictionary=sim.party_coordinator._companion_decision(id,hold,board)
				action=sim.party_coordinator._leaf_to_action(id,decision.selected_leaf)
				if not sim.party_coordinator._action_error(action).is_empty():action=Action.hold(id)
		elif not staged and r.phase!="DEPLOYMENT" and enemy_plans.has(id):
			var row:Dictionary=enemy_plans[id]
			if row.action_type=="MELEE":action=Action.melee(id,int(row.target_id))
			elif row.action_type=="MOVE" and not staged:action=Action.move_to(id,Vector2i(row.destination[0],row.destination[1]))
		var path:Array=[[action.destination.x,action.destination.y]] if action.type=="MOVE" else []
		r.plans[id_wire]=pack(w,action,"AI",path)
	w.party_encounter.round_combat=r
	return State.wire_error(r,w.width,w.height).is_empty()

static func edit(sim,actor_id:int,draft:Dictionary,revision:int)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	if r.phase not in ["DEPLOYMENT","PLANNING","INTERRUPTED"]:return reject("round_not_editable")
	if revision!=int(r.plan_revision):return reject("round_revision_changed")
	if Rules.individual(w) and r.phase!="DEPLOYMENT" and actor_id!=Rules.current_actor(w):return reject("round_not_current_actor")
	var key:=str(actor_id)
	if not r.plans.has(key) or w.party_encounter.member(actor_id)==null or key in r.completed_actor_ids:return reject("round_actor_not_editable")
	var keys:Array=draft.keys();keys.sort()
	if keys not in [["action","path"],["action","item_operation","path"]]:return reject("round_draft_invalid")
	var action=Action.from_dict(draft.action)
	if action==null or action.actor_id!=actor_id or action.type=="MOVE" or not draft.path is Array:return reject("round_draft_invalid")
	if action.type in ["MELEE","SKILL"] and action.target_id in w.party_encounter.enemy_ids and not Field.visible(w,action.target_id):return reject("round_target_unseen")
	var candidate:=pack(w,action,"USER",draft.path)
	if Rules.individual(w) and r.phase!="DEPLOYMENT" and action.type=="MELEE":
		var origin:=Vector2i(candidate.destination[0],candidate.destination[1])
		if not w.entities.has(action.target_id) or not w.entities[action.target_id].position in preload("res://sim/srpg_attack_preview.gd").cells(w,actor_id,origin):return reject("target_out_of_range")
	# Placement is a zero-time setup, not the first combat movement allowance.
	if r.phase=="DEPLOYMENT":candidate.move_budget=12
	candidate.item_operation=draft.get("item_operation",{}).duplicate(true)
	var error:=State.plan_error(candidate,w.width,w.height)
	if not error.is_empty():return reject("round_draft_"+error)
	if r.phase=="DEPLOYMENT":
		var deployment_error:String=preload("res://sim/stage_counterplay.gd").deployment_error(w,candidate)
		if not deployment_error.is_empty():return reject(deployment_error)
	var visible:=Field.visible_cells(w);var budget:=0
	for cell in candidate.path:
		if not visible.has("%d:%d"%[int(cell[0]),int(cell[1])]):return reject("round_path_unseen")
		budget+=Rules.terrain_cost(w,Vector2i(cell[0],cell[1]))
	if budget>int(candidate.move_budget):return reject("round_move_budget")
	# Already committed prefix movement cannot be edited or replayed. A new
	# interrupted draft starts at the current position, but keeps the original
	# total budget and spent ledger. Repeated edits must never refund movement.
	if r.phase=="INTERRUPTED" or Rules.individual(w) and r.phase!="DEPLOYMENT":
		var spent:int=int(r.slot_spent.get(key,0))
		candidate.move_budget=int(r.plans[key].move_budget)
		if budget>maxi(0,mini(int(candidate.move_budget),Rules.move_budget(w,actor_id))-spent):return reject("round_move_budget")
		r.slot_progress[key]=0
	if Rules.individual(w) and candidate.action.type=="MELEE" and Rules.remaining_attacks(w,actor_id)<=0:return reject("round_attack_budget")
	r.plans[key]=candidate;r.plan_revision=int(r.plan_revision)+1
	return {"accepted":true,"reason":"ok","plan_revision":int(r.plan_revision)}

static func reject(reason:String)->Dictionary:return {"accepted":false,"reason":reason}
