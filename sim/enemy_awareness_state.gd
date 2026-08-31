class_name EnemyAwarenessState
extends RefCounted

const SCHEMA_VERSION := 1
const STATES := ["UNAWARE", "SUSPICIOUS", "ALERT", "HUNTING", "SEARCHING", "RETURNING"]
const MAX_SUSPICION := 1000
const MAX_SEARCH_TURNS := 12
const Int64CodecScript = preload("res://sim/int64_codec.gd")

var enemy_id: int = -1
var awareness_state := "UNAWARE"
var suspicion: int = 0
var home_position := Vector2i.ZERO
var last_known_target_position := Vector2i(-1, -1)
var last_seen_step: int = -1
var last_seen_time: int = -1
var search_turns_remaining: int = 0

func _init(p_enemy_id:int=-1,p_home_position:Vector2i=Vector2i.ZERO)->void:
	enemy_id=p_enemy_id
	home_position=p_home_position

func to_dict()->Dictionary:
	return {"schema_version":SCHEMA_VERSION,"enemy_id":str(enemy_id),
		"awareness_state":awareness_state,"suspicion":suspicion,
		"home_position":[home_position.x,home_position.y],
		"last_known_target_position":[last_known_target_position.x,last_known_target_position.y],
		"last_seen_step":str(last_seen_step),"last_seen_time":str(last_seen_time),
		"search_turns_remaining":search_turns_remaining}

static func from_dict(row:Dictionary):
	var state=load("res://sim/enemy_awareness_state.gd").new()
	state.enemy_id=Int64CodecScript.parse(row.enemy_id,"awareness enemy ID")
	state.awareness_state=str(row.awareness_state)
	state.suspicion=int(row.suspicion)
	state.home_position=Vector2i(int(row.home_position[0]),int(row.home_position[1]))
	state.last_known_target_position=Vector2i(int(row.last_known_target_position[0]),
		int(row.last_known_target_position[1]))
	state.last_seen_step=Int64CodecScript.parse(row.last_seen_step,"awareness last seen step")
	state.last_seen_time=Int64CodecScript.parse(row.last_seen_time,"awareness last seen time")
	state.search_turns_remaining=int(row.search_turns_remaining)
	return state

static func wire_error(row:Variant,width:int,height:int)->String:
	if not row is Dictionary:return "invalid_enemy_awareness_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["awareness_state","enemy_id","home_position","last_known_target_position",
		"last_seen_step","last_seen_time","schema_version","search_turns_remaining","suspicion"]:
		return "invalid_enemy_awareness_keys"
	if not _integer(row.get("schema_version")) \
			or int(row.get("schema_version"))!=SCHEMA_VERSION:
		return "unsupported_enemy_awareness_schema"
	if not Int64CodecScript.is_canonical(row.get("enemy_id")) \
			or not Int64CodecScript.is_canonical(row.get("last_seen_step")) \
			or not Int64CodecScript.is_canonical(row.get("last_seen_time")):
		return "noncanonical_enemy_awareness_integer"
	if Int64CodecScript.parse(row.enemy_id,"awareness enemy ID")<=0 \
			or str(row.get("awareness_state","")) not in STATES:
		return "invalid_enemy_awareness_identity"
	if not _integer(row.get("suspicion")) or int(row.suspicion)<0 \
			or int(row.suspicion)>MAX_SUSPICION:
		return "invalid_enemy_suspicion"
	if not _position(row.get("home_position"),width,height):return "invalid_enemy_home_position"
	var last:Variant=row.get("last_known_target_position")
	var last_is_empty:bool=last is Array and last.size()==2 and _integer(last[0]) \
		and _integer(last[1]) and int(last[0])==-1 and int(last[1])==-1
	if not last_is_empty and not _position(last,width,height):return "invalid_enemy_last_known_position"
	var last_step:=Int64CodecScript.parse(row.last_seen_step,"last seen step")
	var last_time:=Int64CodecScript.parse(row.last_seen_time,"last seen time")
	if last_step < -1 or last_time < -1 or (last_step==-1)!=(last_time==-1):
		return "invalid_enemy_last_seen"
	if not _integer(row.get("search_turns_remaining")) \
			or int(row.search_turns_remaining)<0 \
			or int(row.search_turns_remaining)>MAX_SEARCH_TURNS:
		return "invalid_enemy_search_turns"
	if str(row.awareness_state) in ["UNAWARE","SUSPICIOUS","ALERT","RETURNING"] \
			and int(row.search_turns_remaining)!=0:
		return "invalid_enemy_search_state"
	return ""

static func _position(value:Variant,width:int,height:int)->bool:
	return value is Array and value.size()==2 and _integer(value[0]) and _integer(value[1]) \
		and int(value[0])>=0 and int(value[1])>=0 \
		and int(value[0])<width and int(value[1])<height

static func _integer(value:Variant)->bool:
	return value is int or (value is float and is_finite(value) and value==floor(value))
