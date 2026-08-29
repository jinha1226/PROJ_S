class_name DungeonDuelSimulator
extends RefCounted

const SESSION_FORMAT_VERSION:=2
const ESCAPE_DISTANCE:=8
const StateScript=preload("res://sim/dungeon_population/dungeon_population_state.gd")
const ActorScript=preload("res://sim/dungeon_population/dungeon_actor_state.gd")
const HexacoScript=preload("res://sim/dungeon_population/hexaco_profile.gd")
const RegistryScript=preload("res://sim/dungeon_population/dungeon_action_registry.gd")
const Int64CodecScript=preload("res://sim/int64_codec.gd")

var state
var registry
var command_journal:Array[Dictionary]=[]

func _init(p_seed:int=1,p_registry=null)->void:
	registry=p_registry if p_registry!=null else RegistryScript.new()
	reset(p_seed)

func reset(p_seed:int=1)->Dictionary:
	state=StateScript.new();state.seed=p_seed
	var species:=["human","dwarf","goblin","amphibian"]
	var first_species_index:=HexacoScript.sample(p_seed,1,"species",species.size())
	var second_species_index:=HexacoScript.sample(p_seed,2,"species",species.size())
	if second_species_index==first_species_index:second_species_index=(second_species_index+1)%species.size()
	var distance:=1+HexacoScript.sample(p_seed,0,"distance",6);state.distance=distance
	for entity_id in [1,2]:
		var actor=ActorScript.new();actor.entity_id=entity_id
		actor.display_name="아린" if entity_id==1 else "보라"
		actor.species_id=species[first_species_index if entity_id==1 else second_species_index]
		actor.profile=HexacoScript.generated(p_seed,entity_id)
		actor.hp=40+HexacoScript.sample(p_seed,entity_id,"hp",61)
		actor.armed=HexacoScript.sample(p_seed,entity_id,"armed",100)>=25
		actor.weapon_id=(["SPEAR","SWORD"][HexacoScript.sample(p_seed,entity_id,"weapon",2)] if actor.armed else "NONE")
		actor.power=25+HexacoScript.sample(p_seed,entity_id,"power",76)
		actor.supplies=HexacoScript.sample(p_seed,entity_id,"supplies",3)
		var memories:=["NONE","HELPED","HARMED","EXILED"]
		actor.memory_kind=memories[HexacoScript.sample(p_seed,entity_id,"memory",memories.size())]
		actor.memory_modifier={"NONE":0,"HELPED":15,"HARMED":-35,"EXILED":-55}[actor.memory_kind]
		var status_roll:=HexacoScript.sample(p_seed,entity_id,"status",4)
		if status_roll==1:actor.status_effect={"status_id":"BLEEDING","remaining_quanta":3,"tick_damage":4}
		elif status_roll==2:actor.status_effect={"status_id":"POISONED","remaining_quanta":4,"tick_damage":3}
		actor.position=Vector2i(4 if entity_id==1 else 4+distance,7)
		state.actors[entity_id]=actor
	command_journal.clear()
	return {"accepted":true,"reason":"ok","seed":str(p_seed)}

func restart_same_scenario()->Dictionary:return reset(state.seed)
func new_random_scenario(seed:int)->Dictionary:return reset(seed)

func decision_breakdowns()->Array:
	var rows:Array=[]
	for entity_id in [1,2]:
		var actor=state.actors[entity_id];var other=state.actors[3-entity_id]
		if not actor.alive:
			rows.append({"actor_id":str(entity_id),"selected_action_id":"HOLD",
				"selected_reason_ko":"이미 쓰러져 행동할 수 없다.","selection_mode":"NONE",
				"continued":false,"intent_turn_count":0,"switch_reason_code":"NONE",
				"switch_reason_ko":"이미 쓰러져 행동할 수 없다.","candidates":[]})
		else:rows.append(_decision_breakdown(actor,other))
	return rows.duplicate(true)

func step()->Dictionary:
	if state.phase!="ACTIVE":return {"accepted":false,"reason":"duel_complete"}
	var rollback:Dictionary=snapshot();var decisions:Array=decision_breakdowns()
	for row in decisions:_commit_decision(state.actors[int(str(row.actor_id))],row)
	var before_signals:Dictionary={}
	for entity_id in [1,2]:before_signals[entity_id]=_interrupt_signature(state.actors[entity_id])
	state.turn_index+=1;state.world_time+=100
	var first_event_id:int=state.next_event_id;var selected:Dictionary={}
	for row in decisions:selected[int(str(row.actor_id))]=str(row.selected_action_id)
	var damage_by_target:={1:0,2:0};var executions:Dictionary={}
	for entity_id in [1,2]:executions[entity_id]=registry.execution(selected[entity_id])
	for entity_id in [1,2]:
		var actor=state.actors[entity_id];var execution:Dictionary=executions[entity_id]
		var target_id:=-1
		if str(execution.target_role)=="OTHER":target_id=3-entity_id
		elif str(execution.target_role)=="SELF":target_id=entity_id
		_emit("ACTION",entity_id,target_id,selected[entity_id],0,actor.position)
	# MELEE intents are calculated from the same pre-resolution state, so mutual
	# attacks remain simultaneous and an attacker cannot erase the other's turn.
	for entity_id in [1,2]:
		var actor=state.actors[entity_id];var other=state.actors[3-entity_id];var execution:Dictionary=executions[entity_id]
		if not actor.alive or str(execution.atomic_verb)!="MELEE" or state.distance>1 or not actor.armed:continue
		var damage:=5+int(actor.power/10)+HexacoScript.sample(state.seed,entity_id,
			"damage/"+str(state.turn_index),6)
		damage_by_target[other.entity_id]+=damage
		_emit("DAMAGE",entity_id,other.entity_id,selected[entity_id],damage,other.position)
	for target_id in [1,2]:
		var target=state.actors[target_id]
		if int(damage_by_target[target_id])<=0:continue
		target.hp=maxi(0,target.hp-int(damage_by_target[target_id]));target.alive=target.hp>0
		target.memory_kind="HARMED";target.memory_modifier=-35
		_mark_interrupt(target)
		_emit("MEMORY",target_id,3-target_id,selected[3-target_id],35,target.position)
	# Surviving MOVE intents resolve together from their declared directions.
	var first_x:int=state.actors[1].position.x;var second_x:int=state.actors[2].position.x
	for entity_id in [1,2]:
		var actor=state.actors[entity_id];var execution:Dictionary=executions[entity_id]
		if not actor.alive or str(execution.atomic_verb)!="MOVE":continue
		var direction:=str(execution.movement_direction)
		if entity_id==1:first_x+=1 if direction=="TOWARD" else -1
		else:second_x+=-1 if direction=="TOWARD" else 1
	first_x=clampi(first_x,1,13);second_x=clampi(second_x,1,13)
	if second_x<=first_x:
		var midpoint:=clampi(int((first_x+second_x)/2),1,12);first_x=midpoint;second_x=midpoint+1
	state.actors[1].position.x=first_x;state.actors[2].position.x=second_x
	state.distance=second_x-first_x
	for entity_id in [1,2]:
		var actor=state.actors[entity_id];var execution:Dictionary=executions[entity_id]
		if actor.alive and str(execution.atomic_verb)=="MOVE":
			_emit("MOVE",entity_id,3-entity_id,selected[entity_id],state.distance,actor.position)
	# USE_ITEM happens after incoming simultaneous damage but before the status tick.
	for entity_id in [1,2]:
		var actor=state.actors[entity_id];var execution:Dictionary=executions[entity_id]
		if not actor.alive or str(execution.atomic_verb)!="USE_ITEM" or actor.supplies<=0:continue
		var before:int=actor.hp;actor.supplies-=1;actor.hp=mini(actor.max_hp,actor.hp+12)
		if not actor.status_effect.is_empty():
			actor.status_effect.remaining_quanta=int(actor.status_effect.remaining_quanta)-2
			if int(actor.status_effect.remaining_quanta)<=0:actor.status_effect={}
		_emit("HEAL",entity_id,-1,selected[entity_id],actor.hp-before,actor.position)
	for entity_id in [1,2]:
		var actor=state.actors[entity_id]
		if not actor.alive or actor.status_effect.is_empty():continue
		var damage:=int(actor.status_effect.tick_damage);actor.hp=maxi(0,actor.hp-damage)
		actor.status_effect.remaining_quanta=int(actor.status_effect.remaining_quanta)-1
		if int(actor.status_effect.remaining_quanta)<=0:actor.status_effect={}
		actor.alive=actor.hp>0
		_emit("STATUS_TICK",entity_id,-1,selected[entity_id],damage,actor.position)
	for entity_id in [1,2]:
		var actor=state.actors[entity_id]
		if not actor.alive and not _death_emitted_this_turn(entity_id):
			_emit("DEATH",entity_id,-1,selected[entity_id],0,actor.position)
	for entity_id in [1,2]:
		if before_signals[entity_id]!=_interrupt_signature(state.actors[entity_id]):
			_mark_interrupt(state.actors[entity_id])
	var any_dead:bool=not state.actors[1].alive or not state.actors[2].alive
	var escaped_ids:Array=[]
	if not any_dead:
		for entity_id in [1,2]:
			var execution:Dictionary=executions[entity_id]
			if str(execution.get("atomic_verb",""))=="MOVE" \
					and str(execution.get("movement_direction",""))=="AWAY" \
					and _escape_reached(state.actors[entity_id]):escaped_ids.append(entity_id)
	for entity_id in escaped_ids:
		_emit("ESCAPED",entity_id,3-entity_id,selected[entity_id],state.distance,
			state.actors[entity_id].position)
	state.phase="COMPLETE" if any_dead else ("ESCAPED" if not escaped_ids.is_empty() else "ACTIVE")
	var event_ids:Array=[]
	for event in state.events:
		if int(str(event.event_id))>=first_event_id:event_ids.append(str(event.event_id))
	state.last_resolution={"turn_index":str(state.turn_index),"action_rows":[
		{"actor_id":"1","action_id":selected[1]},{"actor_id":"2","action_id":selected[2]}],
		"event_ids":event_ids}
	var error:=StateScript.wire_error(snapshot(),registry.action_ids(),_action_definition_map())
	if not error.is_empty():
		state=StateScript.from_dict(rollback);return {"accepted":false,"reason":error}
	command_journal.append({"kind":"STEP"})
	return {"accepted":true,"reason":"ok","turn_index":str(state.turn_index),
		"resolution":state.last_resolution.duplicate(true),"events":recent_logs(32)}

func resolve_turn()->Dictionary:return step()

func observation()->Dictionary:
	var actor_rows:Array=[]
	for entity_id in [1,2]:actor_rows.append(_actor_dto(state.actors[entity_id]))
	return {"schema_version":1,"seed":str(state.seed),"tick_index":str(state.turn_index),
		"world_time":str(state.world_time),"map_size":[15,15],"distance":state.distance,
		"actors":actor_rows,"phase":state.phase,"last_resolution":state.last_resolution.duplicate(true),
		"recent_events":recent_logs(24)}.duplicate(true)

func recent_logs(limit:int=32)->Array:
	var rows:Array=[];var start:=maxi(0,state.events.size()-clampi(limit,0,128))
	for index in range(start,state.events.size()):
		var event:Dictionary=state.events[index]
		rows.append(event.merged({"message":_event_message(event)}))
	return rows.duplicate(true)

func species_relation_prior(first_species:String,second_species:String)->int:
	if first_species==second_species:return 60
	var pair:Array=[first_species,second_species];pair.sort()
	var priors:={"dwarf|human":25,"goblin|human":-75,"amphibian|human":-10,
		"dwarf|goblin":-80,"amphibian|dwarf":5,"amphibian|goblin":-35}
	return int(priors.get(str(pair[0])+"|"+str(pair[1]),-20))

func relation_assessment(actor_id:Variant)->Dictionary:
	var parsed:=int(str(actor_id));var actor=state.actors.get(parsed);var other=state.actors.get(3-parsed)
	if actor==null or other==null:return {"accepted":false,"reason":"actor_not_found"}
	var prior:=species_relation_prior(actor.species_id,other.species_id)
	var effective:=clampi(prior+actor.memory_modifier,-100,100)
	return {"accepted":true,"actor_id":str(parsed),"species_prior":prior,
		"memory_kind":actor.memory_kind,"memory_modifier":actor.memory_modifier,"effective":effective}

func snapshot()->Dictionary:return state.to_dict().duplicate(true)

func save_json()->String:
	return JSON.stringify({"session_format_version":SESSION_FORMAT_VERSION,"seed":str(state.seed),
		"registry_manifest":registry.canonical_manifest(),
		"registry_fingerprint":registry.ruleset_fingerprint(),
		"snapshot":snapshot(),"journal":command_journal.duplicate(true)})

func load_json(encoded:String)->Dictionary:
	var decoded=JSON.parse_string(encoded)
	if not decoded is Dictionary:return {"accepted":false,"reason":"invalid_duel_session"}
	var keys:Array=decoded.keys();keys.sort()
	if keys != ["journal","registry_fingerprint","registry_manifest","seed","session_format_version","snapshot"] \
			or decoded.session_format_version!=SESSION_FORMAT_VERSION \
			or not Int64CodecScript.is_canonical(decoded.seed) or not decoded.snapshot is Dictionary \
			or not decoded.journal is Array or not decoded.registry_manifest is Array \
			or not decoded.registry_fingerprint is String \
			or str(decoded.registry_fingerprint).length()!=64:return {"accepted":false,"reason":"invalid_duel_session_wire"}
	var current_manifest:Array=registry.canonical_manifest()
	if decoded.registry_manifest!=current_manifest \
			or str(decoded.registry_fingerprint)!=registry.ruleset_fingerprint() \
			or str(decoded.registry_fingerprint)!=JSON.stringify(decoded.registry_manifest).sha256_text():
		return {"accepted":false,"reason":"duel_registry_ruleset_mismatch"}
	var error:=StateScript.wire_error(decoded.snapshot,registry.action_ids(),_action_definition_map())
	if not error.is_empty():return {"accepted":false,"reason":error}
	var restored=StateScript.from_dict(decoded.snapshot)
	var replay=load("res://sim/dungeon_population/dungeon_population_simulator.gd").new(
		Int64CodecScript.parse(decoded.seed,"duel seed"),registry)
	for row in decoded.journal:
		if row!={"kind":"STEP"}:return {"accepted":false,"reason":"invalid_duel_journal"}
		if not replay.step().accepted:return {"accepted":false,"reason":"duel_journal_replay_failed"}
	if replay.snapshot()!=restored.to_dict():return {"accepted":false,"reason":"duel_journal_snapshot_mismatch"}
	state=restored;command_journal.clear();for row in decoded.journal:command_journal.append(row.duplicate(true))
	return {"accepted":true,"reason":"ok"}

func _decision_breakdown(actor,other)->Dictionary:
	var inputs:Dictionary=_decision_inputs(actor,other)
	if actor.current_intent_id.is_empty():
		var first_episode:int=actor.decision_episode_id+1
		var fresh:Dictionary=registry.evaluate_actor(actor,other,inputs,state.seed,first_episode)
		return _decorate_decision(fresh,actor,"NEW",false,first_episode,"NEW",{},
			_candidate(fresh,str(fresh.selected_action_id)))
	var episode:int=maxi(1,actor.decision_episode_id)
	var current_evaluation:Dictionary=registry.evaluate_actor(actor,other,inputs,state.seed,episode)
	var current_candidate:Dictionary=_candidate(current_evaluation,actor.current_intent_id)
	var trigger:=""
	var elapsed:int=maxi(0,state.turn_index-actor.intent_started_turn)
	if current_candidate.is_empty():trigger="ILLEGAL"
	elif registry.goal_complete(actor.current_intent_id,inputs,elapsed):trigger="GOAL_COMPLETE"
	elif not bool(current_candidate.get("legal",false)):trigger="ILLEGAL"
	elif actor.decision_interrupt_version!=actor.intent_interrupt_version:trigger="INTERRUPT"
	if not trigger.is_empty():
		var next_episode:int=episode+1
		var replanned:Dictionary=registry.evaluate_actor(actor,other,inputs,state.seed,next_episode)
		var replanned_candidate:Dictionary=_candidate(replanned,str(replanned.selected_action_id))
		var mode:="RESTARTED" if str(replanned.selected_action_id)==actor.current_intent_id else "SWITCHED"
		return _decorate_decision(replanned,actor,mode,false,next_episode,trigger,
			current_candidate,replanned_candidate)
	var policy:Dictionary=registry.intent_policy(actor.current_intent_id)
	var challenger_id:=str(current_evaluation.selected_action_id)
	var challenger:Dictionary=_candidate(current_evaluation,challenger_id)
	var reason_code:="CHALLENGER"
	if state.turn_index<actor.commitment_until_turn:reason_code="COMMITMENT"
	var should_switch:=false
	if reason_code!="COMMITMENT" and challenger_id!=actor.current_intent_id:
		var threshold:=int(current_candidate.total)+int(policy.get("retention_bonus",0)) \
			+int(policy.get("switch_margin",0))
		should_switch=int(challenger.total)>=threshold
	if should_switch:
		return _decorate_decision(current_evaluation,actor,"SWITCHED",false,episode+1,
			"CHALLENGER",current_candidate,challenger)
	_force_selected(current_evaluation,actor.current_intent_id)
	return _decorate_decision(current_evaluation,actor,"RETAINED",true,episode,reason_code,
		current_candidate,challenger)

func _decorate_decision(row:Dictionary,actor,mode:String,continued:bool,episode:int,
		reason_code:String,current_candidate:Dictionary,challenger:Dictionary)->Dictionary:
	var selected_id:=str(row.get("selected_action_id","HOLD"))
	var policy:Dictionary=registry.intent_policy(actor.current_intent_id if continued else selected_id)
	var turn_count:=1 if not continued else maxi(1,state.turn_index-actor.intent_started_turn+1)
	var reason_ko:=_intent_reason_ko(reason_code,continued,turn_count,mode)
	row["selection_mode"]=mode;row["continued"]=continued
	row["intent_turn_count"]=turn_count;row["decision_episode_id"]=str(episode)
	row["current_intent_id"]=actor.current_intent_id
	row["switch_reason_code"]=reason_code;row["switch_reason_ko"]=reason_ko
	row["retention_bonus"]=int(policy.get("retention_bonus",0))
	row["switch_margin"]=int(policy.get("switch_margin",0))
	row["current_score"]=int(current_candidate.get("total",0))
	row["challenger_action_id"]=str(challenger.get("action_id",selected_id))
	row["challenger_score"]=int(challenger.get("total",0))
	row["selected_reason_ko"]=reason_ko
	return row.duplicate(true)

func _intent_reason_ko(reason_code:String,continued:bool,turn_count:int,mode:String)->String:
	if continued:
		if reason_code=="COMMITMENT":return "이어가는 중 %d턴 · 아직 행동을 유지할 때다."%turn_count
		return "이어가는 중 %d턴 · 바꿀 만큼 큰 이유가 없다."%turn_count
	match reason_code:
		"ILLEGAL":return "이어가던 행동이 더는 가능하지 않아 다시 판단했다."
		"INTERRUPT":return "피해나 몸 상태 변화가 생겨 다시 판단했다."
		"GOAL_COMPLETE":return "이전 행동의 목표를 마쳐 다시 판단했다."
		"CHALLENGER":return "새 행동의 점수가 전환 기준을 넘어 판단을 바꿨다."
	return "새 판단을 시작했다." if mode=="NEW" else "상황을 다시 판단했다."

func _commit_decision(actor,row:Dictionary)->void:
	if bool(row.get("continued",false)):
		actor.intent_reason_code=str(row.get("switch_reason_code","CHALLENGER"))
		return
	var action_id:=str(row.selected_action_id);var policy:Dictionary=registry.intent_policy(action_id)
	var execution:Dictionary=registry.execution(action_id);var target_id:=-1
	if str(execution.get("target_role",""))=="OTHER":target_id=3-actor.entity_id
	elif str(execution.get("target_role",""))=="SELF":target_id=actor.entity_id
	actor.current_intent_id=action_id;actor.intent_started_turn=state.turn_index
	actor.commitment_until_turn=state.turn_index+int(policy.get("commitment_turns",1))
	actor.intent_target_id=target_id;actor.decision_episode_id=int(str(row.decision_episode_id))
	actor.intent_interrupt_version=actor.decision_interrupt_version
	actor.intent_reason_code=str(row.get("switch_reason_code","NEW"))

func _candidate(row:Dictionary,action_id:String)->Dictionary:
	for value in row.get("candidates",[]):
		if value is Dictionary and str(value.get("action_id",""))==action_id:return value
	return {}

func _force_selected(row:Dictionary,action_id:String)->void:
	row["selected_action_id"]=action_id
	for value in row.get("candidates",[]):
		if value is Dictionary:value["selected"]=str(value.get("action_id",""))==action_id

func _mark_interrupt(actor)->void:actor.decision_interrupt_version+=1

func _interrupt_signature(actor)->Array:
	return [_hp_band(actor.hp),_dot_danger(actor),bool(actor.alive),str(actor.memory_kind)]

func _hp_band(hp:int)->int:
	if hp<=25:return 0
	if hp<=50:return 1
	if hp<=75:return 2
	return 3

func _dot_danger(actor)->int:
	if actor.status_effect.is_empty():return 0
	var projected:=int(actor.status_effect.tick_damage)*int(actor.status_effect.remaining_quanta)
	if projected>=actor.hp:return 3
	if projected*2>=actor.hp:return 2
	return 1

func _escape_reached(actor)->bool:
	return state.distance>=ESCAPE_DISTANCE or (actor.entity_id==1 and actor.position.x<=1) \
		or (actor.entity_id==2 and actor.position.x>=13)

func _decision_inputs(actor,other)->Dictionary:
	var relation:Dictionary=relation_assessment(actor.entity_id);var health:int=actor.hp*10
	var injury:int=1000-health;var dot:int=1000 if not actor.status_effect.is_empty() else 0
	var threat:=clampi((other.power-actor.power)*8+(7-state.distance)*80,0,1000)
	var effective:=int(relation.effective)
	return {"HEXACO":{"H":actor.profile.value("H"),"E":actor.profile.value("E"),
		"X":actor.profile.value("X"),"A":actor.profile.value("A"),
		"C":actor.profile.value("C"),"O":actor.profile.value("O")},
		"STATE":{"health":health,"injury":injury,"dot":dot,"armed":1000 if actor.armed else 0,
			"power":actor.power*10,"power_gap":maxi(0,other.power-actor.power)*10,
			"supplies":1000 if actor.supplies>0 else 0,"treatment_need":maxi(injury,dot)},
		"RELATION":{"species_prior":int(relation.species_prior),"memory_modifier":actor.memory_modifier,
			"affinity":clampi((effective+100)*5,0,1000),"hostility":clampi(-effective*10,0,1000),
			"fear_pressure":clampi((-actor.memory_modifier)*12,0,1000),
			"neutrality":clampi(1000-absi(effective)*10,0,1000)},
		"CONTEXT":{"distance":state.distance,"other_alive":1000 if other.alive else 0,
			"escape_reached":1000 if _escape_reached(actor) else 0,
			"escape_space":1000 if state.distance<12 else 0,"approach_pressure":state.distance*140,
			"threat":threat,"uncertainty":500}}

func _actor_dto(actor)->Dictionary:
	return {"id":str(actor.entity_id),"name":actor.display_name,"species_id":actor.species_id,
		"position":[actor.position.x,actor.position.y],"hp":actor.hp,"max_hp":actor.max_hp,
		"alive":actor.alive,"dot":actor.status_effect.duplicate(true),"armed":actor.armed,
		"weapon":actor.weapon_id,"power":actor.power,"supplies":actor.supplies,
		"memory":{"kind":actor.memory_kind,"modifier":actor.memory_modifier},
		"intent":{"action_id":actor.current_intent_id,"started_turn":str(actor.intent_started_turn),
			"commitment_until_turn":str(actor.commitment_until_turn),"target_id":str(actor.intent_target_id),
			"decision_episode_id":str(actor.decision_episode_id),
			"turn_count":0 if actor.current_intent_id.is_empty() else state.turn_index-actor.intent_started_turn+1,
			"reason_code":actor.intent_reason_code},
		"hexaco":actor.profile.to_dict(),"relation":relation_assessment(actor.entity_id)}

func _action_definition_map()->Dictionary:
	var rows:Dictionary={}
	for action_id in registry.action_ids():rows[action_id]=registry.definition(action_id)
	return rows

func _emit(type:String,actor_id:int,target_id:int,action_id:String,magnitude:int,position:Vector2i)->void:
	state.events.append({"event_id":str(state.next_event_id),"turn_index":str(state.turn_index),
		"world_time":str(state.world_time),"type":type,"actor_id":str(actor_id),
		"target_id":str(target_id),"action_id":action_id,"magnitude":magnitude,
		"position":[position.x,position.y]})
	state.next_event_id+=1
	if state.events.size()>512:state.events.pop_front()

func _death_emitted_this_turn(entity_id:int)->bool:
	for index in range(state.events.size()-1,-1,-1):
		var event:Dictionary=state.events[index]
		if int(str(event.turn_index))<state.turn_index:return false
		if event.type=="DEATH" and int(str(event.actor_id))==entity_id:return true
	return false

func _event_message(event:Dictionary)->String:
	var actor=state.actors[int(str(event.actor_id))];var name:=str(actor.display_name)
	match str(event.type):
		"ACTION":return "%s가 %s을 선택했다."%[name,str(event.action_id)]
		"DAMAGE":return "%s의 공격이 %d 피해를 예고했다."%[name,int(event.magnitude)]
		"MOVE":return "%s가 움직였다."%name
		"HEAL":return "%s가 스스로를 치료했다."%name
		"STATUS_TICK":return "%s의 상태이상이 %d 피해를 냈다."%[name,int(event.magnitude)]
		"MEMORY":return "%s가 공격받은 일을 기억했다."%name
		"DEATH":return "%s가 쓰러졌다."%name
		"ESCAPED":return "%s가 거리를 벌려 조우에서 벗어났다."%name
	return "%s에게 사건이 일어났다."%name
