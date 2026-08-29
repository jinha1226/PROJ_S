class_name DungeonDuelActorState
extends RefCounted

const SCHEMA_VERSION:=1
const MEMORIES:=["EXILED","HARMED","HELPED","NONE"]
const HexacoScript=preload("res://sim/dungeon_population/hexaco_profile.gd")
const Int64CodecScript=preload("res://sim/int64_codec.gd")

var entity_id:int=1
var display_name:="인물 A"
var species_id:="human"
var position:=Vector2i.ZERO
var max_hp:int=100
var hp:int=100
var armed:=true
var weapon_id:="SPEAR"
var power:int=50
var supplies:int=1
var memory_kind:="NONE"
var memory_modifier:int=0
var status_effect:Dictionary={}
var alive:=true
var profile

func to_dict()->Dictionary:
	return {"schema_version":SCHEMA_VERSION,"entity_id":str(entity_id),
		"display_name":display_name,"species_id":species_id,"position":[position.x,position.y],
		"max_hp":max_hp,"hp":hp,"armed":armed,"weapon_id":weapon_id,"power":power,
		"supplies":supplies,"memory_kind":memory_kind,"memory_modifier":memory_modifier,
		"status_effect":status_effect.duplicate(true),"alive":alive,"profile":profile.to_dict()}

static func from_dict(row:Dictionary):
	var actor=load("res://sim/dungeon_population/dungeon_actor_state.gd").new()
	actor.entity_id=Int64CodecScript.parse(row.entity_id,"duel actor")
	actor.display_name=str(row.display_name);actor.species_id=str(row.species_id)
	actor.position=Vector2i(int(row.position[0]),int(row.position[1]))
	actor.max_hp=int(row.max_hp);actor.hp=int(row.hp);actor.armed=bool(row.armed)
	actor.weapon_id=str(row.weapon_id);actor.power=int(row.power);actor.supplies=int(row.supplies)
	actor.memory_kind=str(row.memory_kind);actor.memory_modifier=int(row.memory_modifier)
	actor.status_effect={}
	if not row.status_effect.is_empty():
		actor.status_effect={"status_id":str(row.status_effect.status_id),
			"remaining_quanta":int(row.status_effect.remaining_quanta),
			"tick_damage":int(row.status_effect.tick_damage)}
	actor.alive=bool(row.alive);actor.profile=HexacoScript.from_dict(row.profile)
	return actor

static func wire_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_duel_actor_shape"
	var keys:Array=row.keys();keys.sort()
	if keys != ["alive","armed","display_name","entity_id","hp","max_hp","memory_kind",
			"memory_modifier","position","power","profile","schema_version","species_id",
			"status_effect","supplies","weapon_id"] or row.schema_version!=SCHEMA_VERSION:
		return "invalid_duel_actor_wire"
	if not Int64CodecScript.is_canonical(row.entity_id) \
			or Int64CodecScript.parse(row.entity_id,"duel actor") not in [1,2]:return "invalid_duel_actor_id"
	if not row.display_name is String or str(row.display_name).is_empty() \
			or row.species_id not in ["amphibian","dwarf","goblin","human"] \
			or row.memory_kind not in MEMORIES:return "invalid_duel_actor_identity"
	if not row.position is Array or row.position.size()!=2 or not _integer(row.position[0]) or not _integer(row.position[1]) \
			or int(row.position[0])<0 or int(row.position[0])>=15 or int(row.position[1])<0 or int(row.position[1])>=15:
		return "invalid_duel_actor_position"
	for value in [row.max_hp,row.hp,row.power,row.supplies,row.memory_modifier]:
		if not _integer(value):return "invalid_duel_actor_scalar"
	if int(row.max_hp)!=100 or int(row.hp)<0 or int(row.hp)>100 or int(row.power)<0 or int(row.power)>100 \
			or int(row.supplies)<0 or int(row.supplies)>3 or int(row.memory_modifier)<-60 or int(row.memory_modifier)>20 \
			or not row.armed is bool or not row.alive is bool or bool(row.alive)!=(int(row.hp)>0):
		return "invalid_duel_actor_scalar"
	if row.weapon_id not in ["NONE","SPEAR","SWORD"] or (bool(row.armed)!=(row.weapon_id!="NONE")):
		return "invalid_duel_actor_weapon"
	var expected_modifier:int=int({"NONE":0,"HELPED":15,"HARMED":-35,"EXILED":-55}[str(row.memory_kind)])
	if int(row.memory_modifier)!=expected_modifier:return "duel_memory_modifier_mismatch"
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
