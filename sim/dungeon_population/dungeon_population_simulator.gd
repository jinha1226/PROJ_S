class_name DungeonDuelSimulator
extends RefCounted

const SESSION_FORMAT_VERSION:=1
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
				"selected_reason_ko":"이미 쓰러져 행동할 수 없다.","candidates":[]})
		else:rows.append(registry.evaluate_actor(actor,other,_decision_inputs(actor,other),state.seed,state.turn_index))
	return rows.duplicate(true)

func step()->Dictionary:
	if state.phase!="ACTIVE":return {"accepted":false,"reason":"duel_complete"}
	var rollback:Dictionary=snapshot();var decisions:Array=decision_breakdowns()
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
	state.phase="COMPLETE" if not state.actors[1].alive or not state.actors[2].alive else "ACTIVE"
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
			"escape_space":1000 if state.distance<12 else 0,"approach_pressure":state.distance*140,
			"threat":threat,"uncertainty":500}}

func _actor_dto(actor)->Dictionary:
	return {"id":str(actor.entity_id),"name":actor.display_name,"species_id":actor.species_id,
		"position":[actor.position.x,actor.position.y],"hp":actor.hp,"max_hp":actor.max_hp,
		"alive":actor.alive,"dot":actor.status_effect.duplicate(true),"armed":actor.armed,
		"weapon":actor.weapon_id,"power":actor.power,"supplies":actor.supplies,
		"memory":{"kind":actor.memory_kind,"modifier":actor.memory_modifier},
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
	return "%s에게 사건이 일어났다."%name
