class_name PartyCombatObserverSimulator
extends RefCounted

const SessionScript = preload("res://playtest/party_playtest_session.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const ActionScript = preload("res://sim/party_action_command.gd")
const RequestScript = preload("res://sim/party_turn_request.gd")
const EnemyAwarenessScript = preload("res://sim/enemy_awareness_state.gd")
const EnemySquadBlackboardScript = preload("res://sim/enemy_squad_blackboard.gd")
const PartyMemberScript = preload("res://sim/party_member_state.gd")
const HexacoProfileScript = preload("res://sim/dungeon_population/hexaco_profile.gd")

const MODE_ID := "PARTY_COMBAT"
const RULESET_ID := "party-combat-observer-v1"
const MAX_TURNS := 120

var seed: int = 1
var turn_index: int = 0
var session
var _setup_error := ""
var _next_request
var _next_plan


func _init(p_seed: int = 1) -> void:
	reset(p_seed)


func reset(p_seed: int = 1) -> Dictionary:
	seed = p_seed
	turn_index = 0
	_setup_error = ""
	_next_request = null
	_next_plan = null
	session = SessionScript.new(seed, 20260902 + posmod(seed, 997))
	if session == null or session.sim == null:
		_setup_error = "session_bootstrap_failed"
		return {"accepted":false,"reason":_setup_error}
	if not _bootstrap_four_by_four():
		return {"accepted":false,"reason":_setup_error}
	if not _prepare_next_turn():
		return {"accepted":false,"reason":_setup_error}
	return {"accepted":true,"reason":"ok","seed":str(seed)}


func step() -> Dictionary:
	if not _setup_error.is_empty():
		return {"accepted":false,"reason":_setup_error}
	if _terminal():
		return {"accepted":false,"reason":"combat_complete"}
	var result = session.sim.step_party_turn(_next_plan)
	if result == null or not bool(result.accepted):
		return {"accepted":false,"reason":str(
			result.reason if result != null else "turn_failed"),
			"observation":observation()}
	turn_index += 1
	if not _terminal() and turn_index < MAX_TURNS:
		_prepare_next_turn()
	return {"accepted":true,"reason":"ok","turn_index":str(turn_index),
		"observation":observation()}


func observation() -> Dictionary:
	if session == null or session.sim == null:
		return {"mode":MODE_ID,"terminal":true,"phase":"SETUP_FAILED",
			"phase_label":"파티 전투 · 준비 실패","goal":_setup_error,
			"seed":str(seed),"turn_index":str(turn_index),"map_size":[15,15],
			"terrain_rows":[],"actors":[],"party_members":[],"enemies":[],
			"next_queue":[],"intent_lines":[],"recent_events":[]}
	var world = session.sim.world
	var state = world.party_encounter
	var party_rows: Array[Dictionary] = []
	var enemy_rows: Array[Dictionary] = []
	for member_id_value in state.active_party_member_ids:
		var member_id := int(member_id_value)
		if not world.entities.has(member_id):continue
		party_rows.append(_actor_row(member_id,"PARTY"))
	for enemy_id_value in state.enemy_ids:
		var enemy_id := int(enemy_id_value)
		if not world.entities.has(enemy_id):continue
		enemy_rows.append(_actor_row(enemy_id,"ENEMY"))
	var plan := _next_plan_rows()
	var status := str(state.safe_phase)
	var won := status in ["GROUPED","GROUPED_COMPLETE"] and _alive_enemy_count()==0
	var terminal := _terminal() or turn_index >= MAX_TURNS
	return {
		"schema_version":1,"mode":MODE_ID,"ruleset_id":RULESET_ID,
		"seed":str(seed),"turn_index":str(turn_index),
		"world_time":str(world.world_time),"completed_cycles":0,
		"expedition_number":1,"phase":status,
		"phase_label":"파티 전투 · %s" % ("승리" if won else (
			"패배" if status=="PARTY_DEFEATED" else "자동 교전")),
		"location":"DUNGEON","terminal":terminal,
		"goal":"동료는 자동 판단하고 주인공 행동을 공통 의도로 해석한다.",
		"map_size":[world.width,world.height],"terrain_rows":_terrain_rows(),
		"entry":[-1,-1],"actors":party_rows+enemy_rows,
		"party_members":party_rows,"enemies":enemy_rows,
		"party":_force_summary(party_rows),"enemy_force":_force_summary(enemy_rows),
		"next_queue":plan.queue,"intent_lines":plan.lines,
		"decision":{"ruleset_id":RULESET_ID,
			"selected_label":"자동 파티 계획",
			"selected_reason":"주인공의 행동이 공통 집중 표적이 되고 동료가 스스로 행동한다.",
			"companions":plan.explanations},
		"warning":session.party_status().get("contact_warning",{"available":false}),
		"recent_events":_recent_events(),
	}.duplicate(true)


func _bootstrap_four_by_four() -> bool:
	var world = session.sim.world
	var state = world.party_encounter
	var companion = world.add_entity("companion","보린",
		state.group_anchor+Vector2i(-1,1),110,
		["party_member","recruitable"],"dwarf","party")
	if companion == null:
		_setup_error = "companion_fixture_failed"
		return false
	state.party_member_ids.append(companion.id)
	state.party_member_ids.sort()
	state.member_rows[companion.id]=PartyMemberScript.new(companion.id,3,
		"COMPANION","RECRUITABLE",HexacoProfileScript.generated(seed,companion.id))
	for existing_enemy_id_value in state.enemy_ids:
		var existing_enemy_id:=int(existing_enemy_id_value)
		var existing_awareness=state.enemy_awareness(existing_enemy_id)
		if existing_awareness!=null:
			existing_awareness.awareness_state="HUNTING"
			existing_awareness.suspicion=1000
			existing_awareness.last_known_target_position=state.group_anchor
	var spawned:=0
	for radius in range(3,8):
		for y in range(state.group_anchor.y-radius,state.group_anchor.y+radius+1):
			for x in range(state.group_anchor.x-radius,state.group_anchor.x+radius+1):
				if maxi(absi(x-state.group_anchor.x),absi(y-state.group_anchor.y))!=radius:
					continue
				var position:=Vector2i(x,y)
				if not world.in_bounds(position) or not world.occupying_entities_at(position).is_empty():
					continue
				var enemy=world.add_entity("melee_enemy","감염체 %d"%(spawned+2),
					position,60,["party_enemy"],"human","enemy")
				if enemy==null:continue
				state.enemy_ids.append(enemy.id);state.enemy_ids.sort()
				state.enemy_busy_rows[enemy.id]=0
				var awareness=EnemyAwarenessScript.new(enemy.id,enemy.position)
				awareness.awareness_state="HUNTING";awareness.suspicion=1000
				awareness.last_known_target_position=state.group_anchor
				state.enemy_awareness_rows[enemy.id]=awareness
				spawned+=1
				if spawned==3:break
			if spawned==3:break
		if spawned==3:break
	if spawned!=3:
		_setup_error="enemy_fixture_failed"
		return false
	var recruit:Dictionary=session.recruit_companion(companion.id)
	if not bool(recruit.get("accepted",false)):
		_setup_error="recruit_fixture_failed:%s"%str(recruit.get("reason","unknown"))
		return false
	var contact:Dictionary=session.commit_exploration(
		CommandScript.wait(state.protagonist_id))
	if not bool(contact.get("accepted",false)) or state.safe_phase!="CONTACT":
		_setup_error="contact_fixture_failed"
		return false
	session.preview_deployment("WEDGE",session.available_companion_ids())
	var deployment:Dictionary=session.commit_deployment()
	if not bool(deployment.get("accepted",false)) or state.safe_phase!="ENGAGED":
		_setup_error="deployment_fixture_failed"
		return false
	_setup_error=world.world_state_error()
	return _setup_error.is_empty()


func _prepare_next_turn() -> bool:
	if _terminal():return false
	var state=session.sim.world.party_encounter
	var hold=ActionScript.hold(state.protagonist_id)
	var hero_action=session.sim.party_coordinator._suggest(state.protagonist_id,hold)
	_next_request=RequestScript.new(hero_action,[])
	_next_plan=session.sim.preview_party_turn(_next_request)
	var preview:Dictionary=_next_plan.to_dict()
	if not bool(preview.get("accepted",false)):
		_setup_error=str(preview.get("reason","plan_failed"))
		_next_plan=null
		return false
	return true


func _next_plan_rows()->Dictionary:
	var queue: Array[Dictionary] = []
	var lines: Array[Dictionary] = []
	var explanations: Array = []
	if _terminal():return {"queue":queue,"lines":lines,"explanations":explanations}
	var world=session.sim.world
	var state=world.party_encounter
	var semantic_targets:Dictionary={}
	if _next_request==null or _next_plan==null:
		return {"queue":queue,"lines":lines,"explanations":explanations}
	var board=session.sim.party_coordinator.explain_companion_turn(_next_request)
	for explanation in board.get("companions",[]):
		var actor_id:=int(explanation.actor_id)
		var selected_id:=str(explanation.selected_action_id)
		var target_id:=-1
		for candidate in explanation.candidates:
			if str(candidate.action_id)==selected_id and bool(candidate.legal):
				target_id=int(candidate.leaf.target_id);break
		semantic_targets[actor_id]=target_id
		explanations.append({"actor_id":actor_id,
			"name":world.entities[actor_id].display_name,
			"action_id":selected_id,"mode":str(explanation.mode),
			"target_id":target_id})
	var preview:Dictionary=_next_plan.to_dict()
	for row in preview.get("actor_rows",[]):
		var actor_id:=int(row.actor_id)
		var action:Dictionary=row.action
		var target_id:=int(action.target_id)
		if target_id<=0:target_id=int(semantic_targets.get(actor_id,-1))
		queue.append(_queue_row(actor_id,str(action.type),target_id,
			"PANIC" if _member_mode(actor_id)=="PANIC" else ""))
		_append_intent_line(lines,actor_id,target_id,action.get("destination",[-1,-1]))
	var enemy_board:Dictionary=EnemySquadBlackboardScript.build(world)
	var enemy_ids:Array=state.enemy_ids.duplicate();enemy_ids.sort()
	for enemy_id_value in enemy_ids:
		var enemy_id:=int(enemy_id_value)
		if not world.is_autonomous_target(enemy_id):continue
		var forecast:Dictionary=session.sim.party_coordinator.forecast_enemy_action(
			enemy_id,enemy_board)
		if not bool(forecast.get("accepted",false)):continue
		var target_id:=int(forecast.get("target_id",-1))
		queue.append(_queue_row(enemy_id,str(forecast.get("action_type","HOLD")),
			target_id,""))
		_append_intent_line(lines,enemy_id,target_id,
			forecast.get("destination",[-1,-1]))
	return {"queue":queue,"lines":lines,"explanations":explanations}


func _queue_row(actor_id:int,action_type:String,target_id:int,warning:String)->Dictionary:
	var entity=session.sim.world.entities[actor_id]
	return {"actor_id":actor_id,"name":str(entity.display_name),
		"glyph":_glyph(actor_id),"action_type":action_type,
		"action_symbol":_action_symbol(action_type,warning),
		"target_id":target_id,"target_name":str(
			session.sim.world.entities[target_id].display_name) \
			if target_id>0 and session.sim.world.entities.has(target_id) else "",
		"warning":warning}


func _append_intent_line(lines:Array[Dictionary],actor_id:int,target_id:int,
		destination_value:Variant)->void:
	var world=session.sim.world
	if not world.entities.has(actor_id):return
	var target_position:=Vector2i(-1,-1)
	if target_id>0 and world.entities.has(target_id):
		target_position=world.entities[target_id].position
	elif destination_value is Array and destination_value.size()==2:
		target_position=Vector2i(int(destination_value[0]),int(destination_value[1]))
	if target_position==Vector2i(-1,-1):return
	var from:Vector2i=world.entities[actor_id].position
	lines.append({"actor_id":actor_id,"target_id":target_id,
		"from":[from.x,from.y],"to":[target_position.x,target_position.y],
		"faction":"PARTY" if actor_id in world.party_encounter.party_member_ids \
		else "ENEMY"})


func _actor_row(entity_id:int,force:String)->Dictionary:
	var world=session.sim.world
	var entity=world.entities[entity_id]
	var combatant=world.combatant_states[entity_id]
	return {"entity_id":entity_id,"name":str(entity.display_name),
		"glyph":_glyph(entity_id),"position":[entity.position.x,entity.position.y],
		"visible":true,"hp":int(entity.health),"max_hp":int(entity.max_health),
		"life_state":str(combatant.life_state),"force":force,
		"mode":_member_mode(entity_id)}


func _glyph(entity_id:int)->String:
	var state=session.sim.world.party_encounter
	if entity_id==state.protagonist_id:return "@"
	if entity_id in state.party_member_ids:
		var member=state.member(entity_id)
		return str(["@","A","B","C"][clampi(int(member.roster_slot),0,3)])
	var index:int=state.enemy_ids.find(entity_id)
	return str(["g","k","o","G"][posmod(index,4)])


func _action_symbol(action_type:String,warning:String)->String:
	if warning=="PANIC":return "!"
	return {"MELEE":"⚔","MOVE":"↑","HOLD":"·"}.get(action_type,"?")


func _member_mode(entity_id:int)->String:
	var member=session.sim.world.party_encounter.member(entity_id)
	return str(member.mental_mode) if member!=null else ""


func _force_summary(rows:Array[Dictionary])->Dictionary:
	var active:=0;var hp:=0;var max_hp:=0
	for row in rows:
		if str(row.life_state)=="ACTIVE":active+=1
		hp+=maxi(0,int(row.hp));max_hp+=maxi(1,int(row.max_hp))
	return {"count":rows.size(),"active":active,"hp":hp,"max_hp":max_hp}


func _recent_events()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for row in session.recent_event_log(12):
		rows.append({"turn":str(row.step_index),"message":str(row.message)})
	return rows


func _terrain_rows()->Array[String]:
	var rows:Array[String]=[]
	for y in range(session.sim.world.height):
		var row:=""
		for x in range(session.sim.world.width):
			row+="#" if str(session.sim.world.tile_at(Vector2i(x,y)).terrain)=="wall" else "."
		rows.append(row)
	return rows


func _alive_enemy_count()->int:
	var count:=0
	for enemy_id in session.sim.world.party_encounter.enemy_ids:
		if session.sim.world.is_autonomous_target(int(enemy_id)):count+=1
	return count


func _terminal()->bool:
	if session==null or session.sim==null:return true
	return str(session.sim.world.party_encounter.safe_phase)!="ENGAGED"
