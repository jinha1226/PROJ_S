class_name DungeonDuelActorState
extends RefCounted

const SCHEMA_VERSION:=3
const MEMORY_KINDS:=["EXILED","HARMED","HELPED"]
const PRESENCES:=["ACTIVE","DEAD","ESCAPED"]
const INTENT_REASONS:=["CHALLENGER","COMMITMENT","GOAL_COMPLETE","ILLEGAL","INTERRUPT","NEW","NONE"]
const HexacoScript=preload("res://sim/dungeon_population/hexaco_profile.gd")
const Int64CodecScript=preload("res://sim/int64_codec.gd")

var entity_id:int=1
var display_name:="인물"
var species_id:="human"
var position:=Vector2i.ZERO
var max_hp:int=100
var hp:int=100
var armed:=true
var weapon_id:="SPEAR"
var power:int=50
var supplies:int=1
var memories:Array[Dictionary]=[]
var status_effect:Dictionary={}
var alive:=true
var presence:="ACTIVE"
var profile
var current_intent_id:=""
var intent_started_turn:int=-1
var commitment_until_turn:int=-1
var intent_target_id:int=-1
var decision_episode_id:int=0
var intent_interrupt_version:int=0
var decision_interrupt_version:int=0
var intent_reason_code:="NONE"

func memory_for(target_id:int)->Dictionary:
	for row in memories:
		if int(row.target_id)==target_id:return row.duplicate(true)
	return {"target_id":str(target_id),"kind":"NONE","modifier":0}

func set_memory(target_id:int,kind:String)->void:
	for index in range(memories.size()-1,-1,-1):
		if int(memories[index].target_id)==target_id:memories.remove_at(index)
	if kind!="NONE":
		memories.append({"target_id":str(target_id),"kind":kind,
			"modifier":int({"HELPED":15,"HARMED":-35,"EXILED":-55}[kind])})
	memories.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.target_id)<int(b.target_id))

func to_dict()->Dictionary:
	return {"schema_version":SCHEMA_VERSION,"entity_id":str(entity_id),
		"display_name":display_name,"species_id":species_id,"position":[position.x,position.y],
		"max_hp":max_hp,"hp":hp,"armed":armed,"weapon_id":weapon_id,"power":power,
		"supplies":supplies,"memories":memories.duplicate(true),
		"status_effect":status_effect.duplicate(true),"alive":alive,"presence":presence,
		"profile":profile.to_dict(),"current_intent_id":current_intent_id,
		"intent_started_turn":str(intent_started_turn),
		"commitment_until_turn":str(commitment_until_turn),"intent_target_id":str(intent_target_id),
		"decision_episode_id":str(decision_episode_id),
		"intent_interrupt_version":str(intent_interrupt_version),
		"decision_interrupt_version":str(decision_interrupt_version),
		"intent_reason_code":intent_reason_code}

static func from_dict(row:Dictionary):
	var actor=load("res://sim/dungeon_population/dungeon_actor_state.gd").new()
	actor.entity_id=Int64CodecScript.parse(row.entity_id,"duel actor")
	actor.display_name=str(row.display_name);actor.species_id=str(row.species_id)
	actor.position=Vector2i(int(row.position[0]),int(row.position[1]))
	actor.max_hp=int(row.max_hp);actor.hp=int(row.hp);actor.armed=bool(row.armed)
	actor.weapon_id=str(row.weapon_id);actor.power=int(row.power);actor.supplies=int(row.supplies)
	actor.memories.clear()
	for value in row.memories:
		actor.memories.append({"target_id":str(value.target_id),"kind":str(value.kind),
			"modifier":int(value.modifier)})
	actor.status_effect={}
	if not row.status_effect.is_empty():
		actor.status_effect={"status_id":str(row.status_effect.status_id),
			"remaining_quanta":int(row.status_effect.remaining_quanta),
			"tick_damage":int(row.status_effect.tick_damage)}
	actor.alive=bool(row.alive);actor.presence=str(row.presence)
	actor.profile=HexacoScript.from_dict(row.profile);actor.current_intent_id=str(row.current_intent_id)
	actor.intent_started_turn=Int64CodecScript.parse(row.intent_started_turn,"duel intent start")
	actor.commitment_until_turn=Int64CodecScript.parse(row.commitment_until_turn,"duel commitment")
	actor.intent_target_id=Int64CodecScript.parse(row.intent_target_id,"duel intent target")
	actor.decision_episode_id=Int64CodecScript.parse(row.decision_episode_id,"duel decision episode")
	actor.intent_interrupt_version=Int64CodecScript.parse(row.intent_interrupt_version,"duel intent interrupt")
	actor.decision_interrupt_version=Int64CodecScript.parse(row.decision_interrupt_version,"duel decision interrupt")
	actor.intent_reason_code=str(row.intent_reason_code)
	return actor

static func wire_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_duel_actor_shape"
	var keys:Array=row.keys();keys.sort()
	if keys != ["alive","armed","commitment_until_turn","current_intent_id",
			"decision_episode_id","decision_interrupt_version","display_name","entity_id","hp",
			"intent_interrupt_version","intent_reason_code","intent_started_turn","intent_target_id",
			"max_hp","memories","position","power","presence","profile","schema_version",
			"species_id","status_effect","supplies","weapon_id"] or row.schema_version!=SCHEMA_VERSION:
		return "invalid_duel_actor_wire"
	if not Int64CodecScript.is_canonical(row.entity_id):return "invalid_duel_actor_id"
	var actor_id:=Int64CodecScript.parse(row.entity_id,"duel actor")
	if actor_id<1 or actor_id>5:return "invalid_duel_actor_id"
	if not row.display_name is String or str(row.display_name).is_empty() \
			or row.species_id not in ["amphibian","dwarf","goblin","human"] \
			or row.presence not in PRESENCES:return "invalid_duel_actor_identity"
	if not row.position is Array or row.position.size()!=2 or not _integer(row.position[0]) \
			or not _integer(row.position[1]) or int(row.position[0])<0 or int(row.position[0])>=21 \
			or int(row.position[1])<0 or int(row.position[1])>=21:return "invalid_duel_actor_position"
	for value in [row.max_hp,row.hp,row.power,row.supplies]:
		if not _integer(value):return "invalid_duel_actor_scalar"
	if int(row.max_hp)!=100 or int(row.hp)<0 or int(row.hp)>100 or int(row.power)<0 \
			or int(row.power)>100 or int(row.supplies)<0 or int(row.supplies)>3 \
			or not row.armed is bool or not row.alive is bool \
			or bool(row.alive)!=(row.presence!="DEAD") \
			or (row.presence=="DEAD")!=(int(row.hp)==0):return "invalid_duel_actor_scalar"
	if row.weapon_id not in ["NONE","SPEAR","SWORD"] or (bool(row.armed)!=(row.weapon_id!="NONE")):
		return "invalid_duel_actor_weapon"
	if not row.memories is Array or row.memories.size()>4:return "invalid_duel_memories"
	var previous_target:=0
	for memory in row.memories:
		if not memory is Dictionary:return "invalid_duel_memory"
		var memory_keys:Array=memory.keys();memory_keys.sort()
		if memory_keys != ["kind","modifier","target_id"] or not Int64CodecScript.is_canonical(memory.target_id):
			return "invalid_duel_memory"
		var target_id:=Int64CodecScript.parse(memory.target_id,"duel memory target")
		if target_id<=previous_target or target_id<1 or target_id>5 or target_id==actor_id \
				or memory.kind not in MEMORY_KINDS or not _integer(memory.modifier):return "invalid_duel_memory"
		if int(memory.modifier)!=int({"HELPED":15,"HARMED":-35,"EXILED":-55}[str(memory.kind)]):
			return "duel_memory_modifier_mismatch"
		previous_target=target_id
	for key in ["intent_started_turn","commitment_until_turn","intent_target_id","decision_episode_id",
			"intent_interrupt_version","decision_interrupt_version"]:
		if not Int64CodecScript.is_canonical(row.get(key)):return "noncanonical_duel_intent"
	var intent_start:=Int64CodecScript.parse(row.intent_started_turn,"duel intent start")
	var commitment:=Int64CodecScript.parse(row.commitment_until_turn,"duel commitment")
	var intent_target:=Int64CodecScript.parse(row.intent_target_id,"duel intent target")
	var episode:=Int64CodecScript.parse(row.decision_episode_id,"duel decision episode")
	var intent_interrupt:=Int64CodecScript.parse(row.intent_interrupt_version,"duel intent interrupt")
	var decision_interrupt:=Int64CodecScript.parse(row.decision_interrupt_version,"duel decision interrupt")
	if not row.current_intent_id is String or row.intent_reason_code not in INTENT_REASONS \
			or intent_start < -1 or commitment < -1 or intent_target < -1 or intent_target>5 \
			or episode < 0 or intent_interrupt < 0 \
			or decision_interrupt < intent_interrupt:return "invalid_duel_intent_state"
	if str(row.current_intent_id).is_empty():
		if intent_start!=-1 or commitment!=-1 or intent_target!=-1 or episode!=0 \
				or intent_interrupt!=0 or row.intent_reason_code!="NONE":return "invalid_empty_duel_intent"
	elif intent_start<0 or commitment<intent_start or episode<=0 or row.intent_reason_code=="NONE":
		return "invalid_active_duel_intent"
	if not row.status_effect is Dictionary:return "invalid_duel_status"
	if not row.status_effect.is_empty():
		var status_keys:Array=row.status_effect.keys();status_keys.sort()
		if status_keys != ["remaining_quanta","status_id","tick_damage"] \
				or row.status_effect.status_id not in ["BLEEDING","POISONED"] \
				or not _integer(row.status_effect.remaining_quanta) \
				or int(row.status_effect.remaining_quanta)<1 or int(row.status_effect.remaining_quanta)>8 \
				or not _integer(row.status_effect.tick_damage) or int(row.status_effect.tick_damage)<1 \
				or int(row.status_effect.tick_damage)>10:return "invalid_duel_status"
	return HexacoScript.wire_error(row.profile)

static func _integer(value:Variant)->bool:return value is int or (value is float and value==floor(value))
