class_name DungeonDuelSimulator
extends RefCounted

const SESSION_FORMAT_VERSION:=3
const OBSERVATION_SCHEMA_VERSION:=3
const ACTOR_COUNT:=5
const MAP_SIZE:=21
const PERCEPTION_RANGE:=8
const StateScript=preload("res://sim/dungeon_population/dungeon_population_state.gd")
const ActorScript=preload("res://sim/dungeon_population/dungeon_actor_state.gd")
const HexacoScript=preload("res://sim/dungeon_population/hexaco_profile.gd")
const RegistryScript=preload("res://sim/dungeon_population/dungeon_action_registry.gd")
const Int64CodecScript=preload("res://sim/int64_codec.gd")

var state
var registry
var command_journal:Array[Dictionary]=[]

func _init(p_seed:int=1,p_registry=null)->void:
	registry=p_registry if p_registry!=null else RegistryScript.new();reset(p_seed)

func reset(p_seed:int=1)->Dictionary:
	state=StateScript.new();state.seed=p_seed
	var species:=["human","dwarf","goblin","amphibian"]
	var names:=["아린","보라","카일","도윤","세라"]
	for entity_id in range(1,ACTOR_COUNT+1):
		var actor=ActorScript.new();actor.entity_id=entity_id;actor.display_name=names[entity_id-1]
		actor.species_id=species[HexacoScript.sample(p_seed,entity_id,"species",species.size())]
		actor.profile=HexacoScript.generated(p_seed,entity_id)
		actor.hp=55+HexacoScript.sample(p_seed,entity_id,"hp",46)
		actor.armed=HexacoScript.sample(p_seed,entity_id,"armed",100)>=25
		actor.weapon_id=(["SPEAR","SWORD"][HexacoScript.sample(
			p_seed,entity_id,"weapon",2)] if actor.armed else "NONE")
		actor.power=25+HexacoScript.sample(p_seed,entity_id,"power",76)
		actor.supplies=HexacoScript.sample(p_seed,entity_id,"supplies",3)
		actor.status_effect={};actor.alive=true;actor.presence="ACTIVE"
		state.actors[entity_id]=actor
	_apply_seed_stratum(p_seed,absi(p_seed)%4)
	command_journal.clear()
	return {"accepted":true,"reason":"ok","seed":str(p_seed)}

func restart_same_scenario()->Dictionary:return reset(state.seed)
func new_random_scenario(seed:int)->Dictionary:return reset(seed)

func decision_breakdowns()->Array:
	var rows:Array=[]
	for entity_id in range(1,ACTOR_COUNT+1):
		var actor=state.actors[entity_id]
		if actor.presence!="ACTIVE":
			rows.append({"actor_id":str(entity_id),"selected_action_id":"HOLD",
				"selected_target_id":"-1","selected_reason_ko":"조우에서 이탈해 행동할 수 없다." \
					if actor.presence=="ESCAPED" else "이미 쓰러져 행동할 수 없다.",
				"selection_mode":"NONE","continued":false,"intent_turn_count":0,
				"switch_reason_code":"NONE","switch_reason_ko":"행동 불가","candidates":[]})
		else:rows.append(_decision_breakdown(actor))
	return rows.duplicate(true)

func step()->Dictionary:
	if state.phase!="ACTIVE":return {"accepted":false,"reason":"duel_complete"}
	var rollback:Dictionary=snapshot();var decisions:Array=decision_breakdowns()
	var active_ids:Array=_active_ids()
	var decision_by_actor:Dictionary={}
	for actor_id in active_ids:
		var row:Dictionary=decisions[actor_id-1];decision_by_actor[actor_id]=row
		_commit_decision(state.actors[actor_id],row)
	var before_signals:Dictionary={};var start_positions:Dictionary={}
	for actor_id in active_ids:
		before_signals[actor_id]=_interrupt_signature(state.actors[actor_id])
		start_positions[actor_id]=state.actors[actor_id].position
	state.turn_index+=1;state.world_time+=100
	var first_event_id:int=state.next_event_id;var executions:Dictionary={}
	for actor_id in active_ids:
		var row:Dictionary=decision_by_actor[actor_id]
		executions[actor_id]=registry.execution(str(row.selected_action_id))
		_emit("ACTION",actor_id,int(str(row.selected_target_id)),str(row.selected_action_id),0,
			state.actors[actor_id].position)
	var damage_by_target:Dictionary={};var attackers_by_target:Dictionary={}
	for actor_id in active_ids:
		damage_by_target[actor_id]=0;attackers_by_target[actor_id]=[]
	for actor_id in active_ids:
		var actor=state.actors[actor_id];var row:Dictionary=decision_by_actor[actor_id]
		var target_id:=int(str(row.selected_target_id));var execution:Dictionary=executions[actor_id]
		if str(execution.atomic_verb)!="MELEE" or not state.actors.has(target_id):continue
		var target=state.actors[target_id]
		if target.presence!="ACTIVE" or not actor.armed \
				or _chebyshev(start_positions[actor_id],start_positions[target_id])>1:continue
		var damage:=5+int(actor.power/10)+HexacoScript.sample(state.seed,actor_id,
			"damage/"+str(state.turn_index)+"/"+str(target_id),6)
		damage_by_target[target_id]=int(damage_by_target[target_id])+damage
		attackers_by_target[target_id].append({"actor_id":actor_id,
			"action_id":str(row.selected_action_id)})
		_emit("DAMAGE",actor_id,target_id,str(row.selected_action_id),damage,start_positions[target_id])
	for target_id in active_ids:
		var target=state.actors[target_id];var damage:int=int(damage_by_target[target_id])
		if damage<=0:continue
		target.hp=maxi(0,target.hp-damage);target.alive=target.hp>0
		for attack in attackers_by_target[target_id]:
			var attacker_id:=int(attack.actor_id);target.set_memory(attacker_id,"HARMED")
			_emit("MEMORY",target_id,attacker_id,str(attack.action_id),35,target.position)
		_mark_interrupt(target)
		if not target.alive:target.presence="DEAD"
	var move_proposals:Dictionary={};var occupied:Dictionary={}
	for actor_id in _active_ids():occupied[_position_key(state.actors[actor_id].position)]=actor_id
	for actor_id in active_ids:
		var actor=state.actors[actor_id]
		if actor.presence!="ACTIVE":continue
		var row:Dictionary=decision_by_actor[actor_id];var execution:Dictionary=executions[actor_id]
		if str(execution.atomic_verb)!="MOVE":continue
		var target_id:int=int(str(row.selected_target_id));var destination:Vector2i=actor.position
		if str(execution.movement_direction)=="TOWARD":
			if state.actors.has(target_id) and state.actors[target_id].presence=="ACTIVE":
				destination=_approach_destination(actor.position,state.actors[target_id].position)
		else:destination=_flee_destination(actor,target_id,occupied)
		if destination==actor.position or not _in_bounds(destination) \
				or occupied.has(_position_key(destination)):continue
		move_proposals[actor_id]=destination
	var move_winners:Dictionary={};var destination_groups:Dictionary={}
	for actor_id in move_proposals:
		var key:=_position_key(move_proposals[actor_id])
		if not destination_groups.has(key):destination_groups[key]=[]
		destination_groups[key].append(actor_id)
	for key in destination_groups:
		var contenders:Array=destination_groups[key];var destination:Vector2i=move_proposals[contenders[0]]
		var winner:int=_movement_winner(contenders,destination)
		move_winners[winner]=destination
	var winner_ids:Array=move_winners.keys();winner_ids.sort()
	for actor_id in winner_ids:
		state.actors[actor_id].position=move_winners[actor_id]
		var row:Dictionary=decision_by_actor[actor_id]
		_emit("MOVE",actor_id,int(str(row.selected_target_id)),str(row.selected_action_id),
			_chebyshev(start_positions[actor_id],state.actors[actor_id].position),state.actors[actor_id].position)
	for actor_id in active_ids:
		var actor=state.actors[actor_id]
		if actor.presence!="ACTIVE" or str(executions[actor_id].atomic_verb)!="USE_ITEM" \
				or actor.supplies<=0:continue
		var before:int=actor.hp;actor.supplies-=1;actor.hp=mini(actor.max_hp,actor.hp+12)
		if not actor.status_effect.is_empty():
			actor.status_effect.remaining_quanta=int(actor.status_effect.remaining_quanta)-2
			if int(actor.status_effect.remaining_quanta)<=0:actor.status_effect={}
		_emit("HEAL",actor_id,actor_id,str(decision_by_actor[actor_id].selected_action_id),
			actor.hp-before,actor.position)
	for actor_id in active_ids:
		var actor=state.actors[actor_id]
		if actor.presence!="ACTIVE" or actor.status_effect.is_empty():continue
		var damage:=int(actor.status_effect.tick_damage);actor.hp=maxi(0,actor.hp-damage)
		actor.status_effect.remaining_quanta=int(actor.status_effect.remaining_quanta)-1
		if int(actor.status_effect.remaining_quanta)<=0:actor.status_effect={}
		actor.alive=actor.hp>0
		_emit("STATUS_TICK",actor_id,-1,str(decision_by_actor[actor_id].selected_action_id),damage,actor.position)
		if not actor.alive:actor.presence="DEAD"
	for actor_id in active_ids:
		var actor=state.actors[actor_id]
		if actor.presence=="DEAD" and not _event_emitted_this_turn("DEATH",actor_id):
			_emit("DEATH",actor_id,-1,str(decision_by_actor[actor_id].selected_action_id),0,actor.position)
	for actor_id in active_ids:
		var actor=state.actors[actor_id];var execution:Dictionary=executions[actor_id]
		if actor.presence=="ACTIVE" and str(execution.atomic_verb)=="MOVE" \
				and str(execution.movement_direction)=="AWAY" and _on_boundary(actor.position):
			var row:Dictionary=decision_by_actor[actor_id]
			_emit("ESCAPED",actor_id,int(str(row.selected_target_id)),str(row.selected_action_id),0,actor.position)
			actor.presence="ESCAPED";_mark_interrupt(actor)
	for actor_id in active_ids:
		if before_signals[actor_id]!=_interrupt_signature(state.actors[actor_id]):
			_mark_interrupt(state.actors[actor_id])
	state.phase="COMPLETE" if _active_ids().size()<=1 else "ACTIVE"
	var event_ids:Array=[]
	for event in state.events:
		if int(str(event.event_id))>=first_event_id:event_ids.append(str(event.event_id))
	var action_rows:Array=[]
	for actor_id in active_ids:
		var row:Dictionary=decision_by_actor[actor_id]
		action_rows.append({"actor_id":str(actor_id),"action_id":str(row.selected_action_id),
			"target_id":str(row.selected_target_id)})
	state.last_resolution={"turn_index":str(state.turn_index),"action_rows":action_rows,"event_ids":event_ids}
	var error:=StateScript.wire_error(snapshot(),registry.action_ids(),_action_definition_map())
	if not error.is_empty():state=StateScript.from_dict(rollback);return {"accepted":false,"reason":error}
	command_journal.append({"kind":"STEP"})
	return {"accepted":true,"reason":"ok","turn_index":str(state.turn_index),
		"resolution":state.last_resolution.duplicate(true),"events":recent_logs(32)}

func resolve_turn()->Dictionary:return step()

func observation()->Dictionary:
	var actor_rows:Array=[]
	for entity_id in range(1,ACTOR_COUNT+1):actor_rows.append(_actor_dto(state.actors[entity_id]))
	return {"schema_version":OBSERVATION_SCHEMA_VERSION,"seed":str(state.seed),
		"tick_index":str(state.turn_index),"world_time":str(state.world_time),
		"map_size":[MAP_SIZE,MAP_SIZE],"actors":actor_rows,"phase":state.phase,
		"last_resolution":state.last_resolution.duplicate(true),"recent_events":recent_logs(24)}.duplicate(true)

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

func relation_assessment(actor_id:Variant,target_id:Variant)->Dictionary:
	var parsed_actor:=int(str(actor_id));var parsed_target:=int(str(target_id))
	var actor=state.actors.get(parsed_actor);var target=state.actors.get(parsed_target)
	if actor==null or target==null or parsed_actor==parsed_target:
		return {"accepted":false,"reason":"actor_not_found"}
	var memory:Dictionary=actor.memory_for(parsed_target)
	var prior:=species_relation_prior(actor.species_id,target.species_id)
	var effective:=clampi(prior+int(memory.modifier),-100,100)
	return {"accepted":true,"actor_id":str(parsed_actor),"target_id":str(parsed_target),
		"species_prior":prior,"memory_kind":str(memory.kind),
		"memory_modifier":int(memory.modifier),"effective":effective}

func snapshot()->Dictionary:return state.to_dict().duplicate(true)

func save_json()->String:
	return JSON.stringify({"session_format_version":SESSION_FORMAT_VERSION,"seed":str(state.seed),
		"registry_manifest":registry.canonical_manifest(),"registry_fingerprint":registry.ruleset_fingerprint(),
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
			or str(decoded.registry_fingerprint).length()!=64:
		return {"accepted":false,"reason":"invalid_duel_session_wire"}
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

func _decision_breakdown(actor)->Dictionary:
	var target_contexts:Array=[]
	for target in _perceived_targets(actor):
		target_contexts.append({"target_id":target.entity_id,"inputs":_decision_inputs(actor,target)})
	var self_inputs:Dictionary=_self_decision_inputs(actor,target_contexts)
	if actor.current_intent_id.is_empty():
		var first_episode:int=actor.decision_episode_id+1
		var fresh:Dictionary=registry.evaluate_actor(actor,target_contexts,self_inputs,state.seed,first_episode)
		return _decorate_decision(fresh,actor,"NEW",false,first_episode,"NEW",{},
			_candidate(fresh,str(fresh.selected_action_id),int(str(fresh.selected_target_id))))
	var episode:int=maxi(1,actor.decision_episode_id)
	var current_evaluation:Dictionary=registry.evaluate_actor(actor,target_contexts,self_inputs,state.seed,episode)
	var current_candidate:Dictionary=_candidate(current_evaluation,actor.current_intent_id,actor.intent_target_id)
	var elapsed:int=maxi(0,state.turn_index-actor.intent_started_turn);var trigger:=""
	var current_inputs:Dictionary=_inputs_for_target(actor.intent_target_id,target_contexts,self_inputs)
	if current_candidate.is_empty():trigger="ILLEGAL"
	elif registry.goal_complete(actor.current_intent_id,current_inputs,elapsed):trigger="GOAL_COMPLETE"
	elif not bool(current_candidate.get("legal",false)):trigger="ILLEGAL"
	elif actor.decision_interrupt_version!=actor.intent_interrupt_version:trigger="INTERRUPT"
	if not trigger.is_empty():
		var next_episode:=episode+1
		var replanned:Dictionary=registry.evaluate_actor(actor,target_contexts,self_inputs,state.seed,next_episode)
		var target_id:=int(str(replanned.selected_target_id))
		var replanned_candidate:Dictionary=_candidate(replanned,str(replanned.selected_action_id),target_id)
		var same:bool=str(replanned.selected_action_id)==actor.current_intent_id \
			and target_id==actor.intent_target_id
		return _decorate_decision(replanned,actor,"RESTARTED" if same else "SWITCHED",false,
			next_episode,trigger,current_candidate,replanned_candidate)
	var policy:Dictionary=registry.intent_policy(actor.current_intent_id)
	var challenger_id:=str(current_evaluation.selected_action_id)
	var challenger_target:=int(str(current_evaluation.selected_target_id))
	var challenger:Dictionary=_candidate(current_evaluation,challenger_id,challenger_target)
	var reason_code:="COMMITMENT" if state.turn_index<actor.commitment_until_turn else "CHALLENGER"
	var same_challenger:bool=challenger_id==actor.current_intent_id \
		and challenger_target==actor.intent_target_id
	var should_switch:=false
	if reason_code!="COMMITMENT" and not same_challenger:
		var threshold:=int(current_candidate.total)+int(policy.get("retention_bonus",0)) \
			+int(policy.get("switch_margin",0))
		should_switch=int(challenger.total)>=threshold
	if should_switch:
		return _decorate_decision(current_evaluation,actor,"SWITCHED",false,episode+1,
			"CHALLENGER",current_candidate,challenger)
	_force_selected(current_evaluation,actor.current_intent_id,actor.intent_target_id)
	return _decorate_decision(current_evaluation,actor,"RETAINED",true,episode,reason_code,
		current_candidate,challenger)

func _decorate_decision(row:Dictionary,actor,mode:String,continued:bool,episode:int,
		reason_code:String,current_candidate:Dictionary,challenger:Dictionary)->Dictionary:
	var selected_id:=str(row.get("selected_action_id","HOLD"))
	var selected_target:=int(str(row.get("selected_target_id","-1")))
	var policy:Dictionary=registry.intent_policy(actor.current_intent_id if continued else selected_id)
	var turn_count:=1 if not continued else maxi(1,state.turn_index-actor.intent_started_turn+1)
	var reason_ko:=_intent_reason_ko(reason_code,continued,turn_count,mode)
	row["selection_mode"]=mode;row["continued"]=continued;row["intent_turn_count"]=turn_count
	row["decision_episode_id"]=str(episode);row["current_intent_id"]=actor.current_intent_id
	row["current_target_id"]=str(actor.intent_target_id);row["selected_target_id"]=str(selected_target)
	row["switch_reason_code"]=reason_code;row["switch_reason_ko"]=reason_ko
	row["retention_bonus"]=int(policy.get("retention_bonus",0))
	row["switch_margin"]=int(policy.get("switch_margin",0))
	row["current_score"]=int(current_candidate.get("total",0))
	row["challenger_action_id"]=str(challenger.get("action_id",selected_id))
	row["challenger_target_id"]=str(challenger.get("target_id",selected_target))
	row["challenger_score"]=int(challenger.get("total",0));row["selected_reason_ko"]=reason_ko
	return row.duplicate(true)

func _intent_reason_ko(reason_code:String,continued:bool,turn_count:int,mode:String)->String:
	if continued:
		if reason_code=="COMMITMENT":return "이어가는 중 %d턴 · 아직 행동을 유지할 때다."%turn_count
		return "이어가는 중 %d턴 · 바꿀 만큼 큰 이유가 없다."%turn_count
	match reason_code:
		"ILLEGAL":return "대상을 잃거나 행동이 불가능해 다시 판단했다."
		"INTERRUPT":return "피해나 몸 상태 변화가 생겨 다시 판단했다."
		"GOAL_COMPLETE":return "이전 행동의 목표를 마쳐 다시 판단했다."
		"CHALLENGER":return "새 행동의 점수가 전환 기준을 넘어 판단을 바꿨다."
	return "새 판단을 시작했다." if mode=="NEW" else "상황을 다시 판단했다."

func _commit_decision(actor,row:Dictionary)->void:
	if bool(row.get("continued",false)):
		actor.intent_reason_code=str(row.get("switch_reason_code","CHALLENGER"));return
	var action_id:=str(row.selected_action_id);var target_id:=int(str(row.selected_target_id))
	var policy:Dictionary=registry.intent_policy(action_id)
	actor.current_intent_id=action_id;actor.intent_started_turn=state.turn_index
	actor.commitment_until_turn=state.turn_index+int(policy.get("commitment_turns",1))
	actor.intent_target_id=target_id;actor.decision_episode_id=int(str(row.decision_episode_id))
	actor.intent_interrupt_version=actor.decision_interrupt_version
	actor.intent_reason_code=str(row.get("switch_reason_code","NEW"))

func _candidate(row:Dictionary,action_id:String,target_id:int)->Dictionary:
	for value in row.get("candidates",[]):
		if value is Dictionary and str(value.get("action_id",""))==action_id \
				and int(str(value.get("target_id","-1")))==target_id:return value
	return {}

func _force_selected(row:Dictionary,action_id:String,target_id:int)->void:
	row["selected_action_id"]=action_id;row["selected_target_id"]=str(target_id)
	for value in row.get("candidates",[]):
		if value is Dictionary:value["selected"]=str(value.get("action_id",""))==action_id \
				and int(str(value.get("target_id","-1")))==target_id

func _perceived_targets(actor)->Array:
	var result:Array=[]
	for target_id in _active_ids():
		if target_id==actor.entity_id:continue
		var target=state.actors[target_id]
		if _chebyshev(actor.position,target.position)<=PERCEPTION_RANGE:result.append(target)
	return result

func _decision_inputs(actor,target)->Dictionary:
	var relation:Dictionary=relation_assessment(actor.entity_id,target.entity_id)
	var distance:int=_chebyshev(actor.position,target.position);var health:int=actor.hp*10
	var injury:int=1000-health;var dot:int=1000 if not actor.status_effect.is_empty() else 0
	var threat:=clampi((target.power-actor.power)*8+(PERCEPTION_RANGE-distance)*80,0,1000)
	var opportunity:=clampi(500+(actor.power-target.power)*10+(200 if actor.armed else -300),0,1000)
	var hp_crisis:=_hp_crisis(actor.hp);var dot_danger:=_dot_danger(actor)*333
	var recent_interrupt:=1000 if actor.decision_interrupt_version!=actor.intent_interrupt_version else 0
	var power_disadvantage:=_power_disadvantage(target.power-actor.power)
	var survival_crisis:=_survival_crisis(hp_crisis,recent_interrupt,dot_danger,power_disadvantage)
	var effective:=int(relation.effective);var shared_threat:=_shared_threat(actor.entity_id,target.entity_id)
	return {"HEXACO":{"H":actor.profile.value("H"),"E":actor.profile.value("E"),
		"X":actor.profile.value("X"),"A":actor.profile.value("A"),
		"C":actor.profile.value("C"),"O":actor.profile.value("O")},
		"STATE":{"health":health,"hp_ratio":health,"hp_crisis":hp_crisis,"injury":injury,
			"dot":dot,"dot_danger":dot_danger,"recent_interrupt":recent_interrupt,
			"survival_crisis":survival_crisis,"armed":1000 if actor.armed else 0,
			"power":actor.power*10,"power_gap":maxi(0,target.power-actor.power)*10,
			"power_disadvantage":power_disadvantage,"supplies":1000 if actor.supplies>0 else 0,
			"treatment_need":maxi(injury,dot)},
		"RELATION":{"species_prior":int(relation.species_prior),
			"memory_modifier":int(relation.memory_modifier),"affinity":clampi((effective+100)*5,0,1000),
			"hostility":clampi(-effective*10,0,1000),
			"fear_pressure":clampi((-int(relation.memory_modifier))*12,0,1000),
			"neutrality":clampi(1000-absi(effective)*10,0,1000),"shared_threat":shared_threat},
		"CONTEXT":{"distance":distance,"other_alive":1000,"escape_reached":1000 if _on_boundary(actor.position) else 0,
			"escape_space":1000,"approach_pressure":distance*140,"opportunity":opportunity,
			"threat":threat,"uncertainty":500}}

func _self_decision_inputs(actor,target_contexts:Array)->Dictionary:
	var base:Dictionary
	if target_contexts.is_empty():
		base={"HEXACO":{"H":actor.profile.value("H"),"E":actor.profile.value("E"),
			"X":actor.profile.value("X"),"A":actor.profile.value("A"),"C":actor.profile.value("C"),
			"O":actor.profile.value("O")},"STATE":{},"RELATION":{},"CONTEXT":{}}
		var health:int=actor.hp*10;var injury:int=1000-health
		var dot:int=1000 if not actor.status_effect.is_empty() else 0
		base.STATE={"health":health,"hp_ratio":health,"hp_crisis":_hp_crisis(actor.hp),
			"injury":injury,"dot":dot,"dot_danger":_dot_danger(actor)*333,
			"recent_interrupt":1000 if actor.decision_interrupt_version!=actor.intent_interrupt_version else 0,
			"survival_crisis":_hp_crisis(actor.hp),"armed":1000 if actor.armed else 0,
			"power":actor.power*10,"power_gap":0,"power_disadvantage":0,
			"supplies":1000 if actor.supplies>0 else 0,"treatment_need":maxi(injury,dot)}
		base.RELATION={"species_prior":0,"memory_modifier":0,"affinity":0,"hostility":0,
			"fear_pressure":0,"neutrality":1000,"shared_threat":0}
		base.CONTEXT={"distance":MAP_SIZE,"other_alive":0,"escape_reached":1000 if _on_boundary(actor.position) else 0,
			"escape_space":1000,"approach_pressure":0,"opportunity":0,"threat":0,"uncertainty":500}
		return base
	base=target_contexts[0].inputs.duplicate(true)
	for context in target_contexts:
		base.CONTEXT.threat=maxi(int(base.CONTEXT.threat),int(context.inputs.CONTEXT.threat))
		base.STATE.survival_crisis=maxi(int(base.STATE.survival_crisis),int(context.inputs.STATE.survival_crisis))
	return base

func _inputs_for_target(target_id:int,target_contexts:Array,self_inputs:Dictionary)->Dictionary:
	if target_id<1:return self_inputs
	for context in target_contexts:
		if int(context.target_id)==target_id:return context.inputs
	return self_inputs

func _shared_threat(observer_id:int,threat_id:int)->int:
	for index in range(state.events.size()-1,-1,-1):
		var event:Dictionary=state.events[index]
		if state.turn_index-int(str(event.turn_index))>3:break
		if event.type!="DAMAGE" or int(str(event.actor_id))!=threat_id:continue
		var victim_id:=int(str(event.target_id))
		if victim_id==observer_id or victim_id<1 or victim_id>ACTOR_COUNT:continue
		if int(relation_assessment(observer_id,victim_id).get("effective",-100))>=25:return 1000
	return 0

func _actor_dto(actor)->Dictionary:
	var relations:Array=[]
	for target_id in range(1,ACTOR_COUNT+1):
		if target_id!=actor.entity_id:relations.append(relation_assessment(actor.entity_id,target_id))
	return {"id":str(actor.entity_id),"name":actor.display_name,"species_id":actor.species_id,
		"position":[actor.position.x,actor.position.y],"hp":actor.hp,"max_hp":actor.max_hp,
		"alive":actor.alive,"presence":actor.presence,"dot":actor.status_effect.duplicate(true),
		"armed":actor.armed,"weapon":actor.weapon_id,"power":actor.power,"supplies":actor.supplies,
		"memories":actor.memories.duplicate(true),"relations":relations,
		"intent":{"action_id":actor.current_intent_id,"target_id":str(actor.intent_target_id),
			"started_turn":str(actor.intent_started_turn),"commitment_until_turn":str(actor.commitment_until_turn),
			"decision_episode_id":str(actor.decision_episode_id),
			"turn_count":0 if actor.current_intent_id.is_empty() else state.turn_index-actor.intent_started_turn+1,
			"reason_code":actor.intent_reason_code},"hexaco":actor.profile.to_dict()}

func _active_ids()->Array:
	var result:Array=[]
	for actor_id in range(1,ACTOR_COUNT+1):
		if state.actors[actor_id].presence=="ACTIVE":result.append(actor_id)
	return result

func _approach_destination(origin:Vector2i,target:Vector2i)->Vector2i:
	return origin+Vector2i(signi(target.x-origin.x),signi(target.y-origin.y))

func _flee_destination(actor,primary_target_id:int,occupied:Dictionary)->Vector2i:
	var threats:Array=[];var total_weight:=0;var weighted_x:=0;var weighted_y:=0
	for target in _perceived_targets(actor):
		var relation:Dictionary=relation_assessment(actor.entity_id,target.entity_id)
		var weight:=maxi(0,-int(relation.effective)*10)+maxi(0,target.power-actor.power)*8 \
			+int(_shared_threat(actor.entity_id,target.entity_id)/2)
		if target.entity_id==primary_target_id:weight=maxi(weight,200)
		if weight<=0:continue
		threats.append(target);total_weight+=weight;weighted_x+=target.position.x*weight
		weighted_y+=target.position.y*weight
	if threats.is_empty() or total_weight<=0:return actor.position
	var best:Vector2i=actor.position;var best_score:int=-1
	for dy in range(-1,2):
		for dx in range(-1,2):
			if dx==0 and dy==0:continue
			var candidate:Vector2i=actor.position+Vector2i(dx,dy)
			if not _in_bounds(candidate) or occupied.has(_position_key(candidate)):continue
			var delta_x:int=candidate.x*total_weight-weighted_x
			var delta_y:int=candidate.y*total_weight-weighted_y
			var score:int=delta_x*delta_x+delta_y*delta_y
			if score>best_score or (score==best_score and _cell_before(candidate,best)):
				best=candidate;best_score=score
	return best

func _movement_winner(contenders:Array,destination:Vector2i)->int:
	var winner:=int(contenders[0]);var best:=2147483647
	for value in contenders:
		var actor_id:=int(value)
		var priority:=HexacoScript.sample(state.seed,actor_id,
			"move_conflict/"+str(state.turn_index)+"/"+_position_key(destination),2147483647)
		if priority<best or (priority==best and actor_id<winner):winner=actor_id;best=priority
	return winner

func _apply_seed_stratum(seed:int,stratum:int)->void:
	var positions:Array
	match stratum:
		0:positions=[Vector2i(8,10),Vector2i(9,10),Vector2i(11,9),Vector2i(12,10),Vector2i(10,13)]
		1:positions=[Vector2i(7,10),Vector2i(11,10),Vector2i(9,7),Vector2i(13,8),Vector2i(10,14)]
		2:positions=[Vector2i(8,10),Vector2i(12,10),Vector2i(10,8),Vector2i(10,13),Vector2i(6,7)]
		_:positions=[Vector2i(6,10),Vector2i(14,10),Vector2i(10,6),Vector2i(10,14),Vector2i(10,10)]
	for actor_id in range(1,ACTOR_COUNT+1):state.actors[actor_id].position=positions[actor_id-1]
	if stratum==0:
		state.actors[1].species_id="human";state.actors[2].species_id="goblin"
		state.actors[3].species_id="human";state.actors[4].species_id="dwarf";state.actors[5].species_id="goblin"
		state.actors[1].set_memory(2,"HARMED");state.actors[2].set_memory(1,"EXILED")
		state.actors[3].set_memory(1,"HELPED")
		_set_armed(state.actors[1],true,seed,"cluster");_set_armed(state.actors[2],true,seed,"cluster")
	elif stratum==1:
		state.actors[1].set_memory(2,"HARMED");state.actors[4].set_memory(5,"HARMED")
	elif stratum==2:
		var vulnerable=state.actors[1+HexacoScript.sample(seed,0,"vulnerable",ACTOR_COUNT)]
		vulnerable.hp=25+HexacoScript.sample(seed,vulnerable.entity_id,"vulnerable_hp",26)
		vulnerable.status_effect={"status_id":"BLEEDING","remaining_quanta":3,"tick_damage":3}
		vulnerable.set_memory(1 if vulnerable.entity_id!=1 else 2,"HARMED")
	else:
		state.actors[1].species_id="human";state.actors[2].species_id="human"
		state.actors[3].species_id="dwarf";state.actors[4].species_id="dwarf"
		state.actors[1].set_memory(2,"HELPED")

func _set_armed(actor,armed:bool,seed:int,key:String)->void:
	actor.armed=armed;actor.weapon_id=(["SPEAR","SWORD"][HexacoScript.sample(
		seed,actor.entity_id,key+"/weapon",2)] if armed else "NONE")

func _mark_interrupt(actor)->void:actor.decision_interrupt_version+=1
func _interrupt_signature(actor)->Array:return [_hp_band(actor.hp),_dot_danger(actor),actor.presence]
func _hp_band(hp:int)->int:
	if hp<=25:return 0
	if hp<=50:return 1
	if hp<=75:return 2
	return 3
func _hp_crisis(hp:int)->int:
	if hp<=15:return 1000
	if hp<=25:return 850
	if hp<=40:return 650
	if hp<=60:return 300
	return 0
func _power_disadvantage(gap:int)->int:
	if gap<=0:return 0
	if gap<=15:return 250
	if gap<=35:return 600
	return 1000
func _survival_crisis(hp_crisis:int,recent_interrupt:int,dot_danger:int,power_disadvantage:int)->int:
	var result:=maxi(hp_crisis,dot_danger)
	if recent_interrupt>0:result+=180
	if power_disadvantage>=600:result+=160
	if hp_crisis>=650 and (recent_interrupt>0 or power_disadvantage>=600):result+=180
	if dot_danger>=666 and recent_interrupt>0:result+=150
	return clampi(result,0,1000)
func _dot_danger(actor)->int:
	if actor.status_effect.is_empty():return 0
	var projected:=int(actor.status_effect.tick_damage)*int(actor.status_effect.remaining_quanta)
	if projected>=actor.hp:return 3
	if projected*2>=actor.hp:return 2
	return 1

func _event_emitted_this_turn(type:String,actor_id:int)->bool:
	for index in range(state.events.size()-1,-1,-1):
		var event:Dictionary=state.events[index]
		if int(str(event.turn_index))<state.turn_index:return false
		if event.type==type and int(str(event.actor_id))==actor_id:return true
	return false

func _event_message(event:Dictionary)->String:
	var actor=state.actors[int(str(event.actor_id))];var name:=str(actor.display_name)
	var target_name:=""
	if int(str(event.target_id))>=1:target_name=str(state.actors[int(str(event.target_id))].display_name)
	match str(event.type):
		"ACTION":return "%s가 %s을 선택했다."%[name,str(event.action_id)]
		"DAMAGE":return "%s가 %s에게 %d 피해를 줬다."%[name,target_name,int(event.magnitude)]
		"MOVE":return "%s가 움직였다."%name
		"HEAL":return "%s가 스스로를 치료했다."%name
		"STATUS_TICK":return "%s의 상태이상이 %d 피해를 냈다."%[name,int(event.magnitude)]
		"MEMORY":return "%s가 %s의 공격을 기억했다."%[name,target_name]
		"DEATH":return "%s가 쓰러졌다."%name
		"ESCAPED":return "%s가 조우에서 벗어났다."%name
	return "%s에게 사건이 일어났다."%name

func _emit(type:String,actor_id:int,target_id:int,action_id:String,magnitude:int,position:Vector2i)->void:
	state.events.append({"event_id":str(state.next_event_id),"turn_index":str(state.turn_index),
		"world_time":str(state.world_time),"type":type,"actor_id":str(actor_id),
		"target_id":str(target_id),"action_id":action_id,"magnitude":magnitude,
		"position":[position.x,position.y]})
	state.next_event_id+=1
	if state.events.size()>512:state.events.pop_front()

func _action_definition_map()->Dictionary:
	var rows:Dictionary={}
	for action_id in registry.action_ids():rows[action_id]=registry.definition(action_id)
	return rows

func _chebyshev(first:Vector2i,second:Vector2i)->int:
	return maxi(absi(first.x-second.x),absi(first.y-second.y))
func _in_bounds(position:Vector2i)->bool:
	return position.x>=0 and position.y>=0 and position.x<MAP_SIZE and position.y<MAP_SIZE
func _on_boundary(position:Vector2i)->bool:
	return position.x==0 or position.y==0 or position.x==MAP_SIZE-1 or position.y==MAP_SIZE-1
func _position_key(position:Vector2i)->String:return "%d,%d"%[position.x,position.y]
func _cell_before(first:Vector2i,second:Vector2i)->bool:
	return first.y<second.y or (first.y==second.y and first.x<second.x)
