class_name PartyActionCommand
extends RefCounted

const TYPES := ["HOLD", "MOVE", "MELEE"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
var type: String
var actor_id: int
var destination := Vector2i(-1, -1)
var target_id: int = -1

func _init(p_type: String = "HOLD", p_actor_id: int = -1, p_destination := Vector2i(-1,-1), p_target_id: int = -1) -> void:
	type = p_type; actor_id = p_actor_id; destination = p_destination; target_id = p_target_id

static func hold(actor_id: int): return load("res://sim/party_action_command.gd").new("HOLD", actor_id)
static func move_to(actor_id: int, destination: Vector2i): return load("res://sim/party_action_command.gd").new("MOVE", actor_id, destination)
static func melee(actor_id: int, target_id: int): return load("res://sim/party_action_command.gd").new("MELEE", actor_id, Vector2i(-1,-1), target_id)

func to_dict() -> Dictionary:
	return {"type": type, "actor_id": str(actor_id), "destination": [destination.x, destination.y], "target_id": str(target_id)}

static func from_dict(row: Variant):
	if not wire_error(row).is_empty(): return null
	return load("res://sim/party_action_command.gd").new(str(row.type), Int64CodecScript.parse(row.actor_id,"party actor"), Vector2i(int(row.destination[0]), int(row.destination[1])), Int64CodecScript.parse(row.target_id,"party target"))

static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_party_action_shape"
	var keys:Array=row.keys();keys.sort()
	if keys != ["actor_id","destination","target_id","type"] or row.type not in TYPES:return "invalid_party_action_keys_or_type"
	if not Int64CodecScript.is_canonical(row.actor_id) or Int64CodecScript.parse(row.actor_id,"actor")<=0:return "noncanonical_party_actor_id"
	if not Int64CodecScript.is_canonical(row.target_id):return "noncanonical_party_target_id"
	if not row.destination is Array or row.destination.size()!=2:return "invalid_party_destination"
	for value in row.destination:
		if not (value is int or value is float and value == floor(value)) \
				or int(value) < -2147483648 or int(value) > 2147483647:return "invalid_party_destination"
	var target:=Int64CodecScript.parse(row.target_id,"target")
	if row.type=="MELEE" and target<=0:return "melee_target_required"
	if row.type!="MELEE" and target!=-1:return "party_target_forbidden"
	if row.type=="MOVE" and Vector2i(int(row.destination[0]),int(row.destination[1]))==Vector2i(-1,-1):return "move_destination_required"
	if row.type!="MOVE" and Vector2i(int(row.destination[0]),int(row.destination[1]))!=Vector2i(-1,-1):return "party_destination_forbidden"
	return ""
