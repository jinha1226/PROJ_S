class_name PartyActionCommand
extends RefCounted

const TYPES := ["HOLD", "MOVE", "MELEE", "SKILL"]
const ACTIVE_SKILL_IDS := ["STRIKE","SHOVE","FIREBOLT","MEND","FIREBALL"]
const Int64CodecScript = preload("res://sim/int64_codec.gd")
var type: String
var actor_id: int
var destination := Vector2i(-1, -1)
var target_id: int = -1
var skill_id: String = ""

func _init(p_type: String = "HOLD", p_actor_id: int = -1,
		p_destination := Vector2i(-1,-1), p_target_id: int = -1,
		p_skill_id: String = "") -> void:
	type = p_type; actor_id = p_actor_id; destination = p_destination
	target_id = p_target_id; skill_id = p_skill_id

static func hold(actor_id: int): return load("res://sim/party_action_command.gd").new("HOLD", actor_id)
static func move_to(actor_id: int, destination: Vector2i): return load("res://sim/party_action_command.gd").new("MOVE", actor_id, destination)
static func melee(actor_id: int, target_id: int): return load("res://sim/party_action_command.gd").new("MELEE", actor_id, Vector2i(-1,-1), target_id)
static func skill(actor_id: int, skill_id: String, target_id: int):
	return load("res://sim/party_action_command.gd").new("SKILL", actor_id,
		Vector2i(-1,-1), target_id, skill_id)

static func skill_at(actor_id:int, skill_id:String, position:Vector2i):
	return load("res://sim/party_action_command.gd").new("SKILL", actor_id, position, -1, skill_id)

func to_dict() -> Dictionary:
	var row:={"type": type, "actor_id": str(actor_id),
		"destination": [destination.x, destination.y],
		"target_id": str(target_id)}
	if type=="SKILL":row["skill_id"]=skill_id
	return row

static func from_dict(row: Variant):
	if not wire_error(row).is_empty(): return null
	return load("res://sim/party_action_command.gd").new(str(row.type),
		Int64CodecScript.parse(row.actor_id,"party actor"),
		Vector2i(int(row.destination[0]), int(row.destination[1])),
		Int64CodecScript.parse(row.target_id,"party target"),str(row.get("skill_id","")))

static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_party_action_shape"
	var keys:Array=row.keys();keys.sort()
	var legacy_keys := ["actor_id","destination","target_id","type"]
	var current_keys := ["actor_id","destination","skill_id","target_id","type"]
	if (row.get("type")=="SKILL" and keys!=current_keys) \
			or (row.get("type")!="SKILL" and keys!=legacy_keys):
		return "invalid_party_action_keys_or_type"
	if row.type not in TYPES:return "invalid_party_action_keys_or_type"
	# The action type is the discriminator: historical actions remain exact
	# four-key wires; SKILL is an exact five-key wire.
	if row.type=="SKILL" and (not row.skill_id is String \
			or str(row.skill_id).is_empty()):
		return "invalid_party_skill_id"
	if row.type=="SKILL" and row.skill_id not in ACTIVE_SKILL_IDS:
		return "invalid_party_skill_id"
	if not Int64CodecScript.is_canonical(row.actor_id) or Int64CodecScript.parse(row.actor_id,"actor")<=0:return "noncanonical_party_actor_id"
	if not Int64CodecScript.is_canonical(row.target_id):return "noncanonical_party_target_id"
	if not row.destination is Array or row.destination.size()!=2:return "invalid_party_destination"
	for value in row.destination:
		if not (value is int or value is float and value == floor(value)) \
				or int(value) < -2147483648 or int(value) > 2147483647:return "invalid_party_destination"
	var target:=Int64CodecScript.parse(row.target_id,"target")
	if row.type=="SKILL" and row.skill_id=="FIREBALL":
		if target!=-1:return "party_target_forbidden"
		if int(row.destination[0])<0 or int(row.destination[1])<0:return "skill_destination_required"
		return ""
	if row.type in ["MELEE","SKILL"] and target<=0:return "party_target_required"
	if row.type not in ["MELEE","SKILL"] and target!=-1:return "party_target_forbidden"
	if row.type=="MOVE" and Vector2i(int(row.destination[0]),int(row.destination[1]))==Vector2i(-1,-1):return "move_destination_required"
	if row.type!="MOVE" and Vector2i(int(row.destination[0]),int(row.destination[1]))!=Vector2i(-1,-1):return "party_destination_forbidden"
	return ""
