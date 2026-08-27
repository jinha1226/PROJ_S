class_name SimEntity
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

var id: int
var kind: String
var display_name: String
var position: Vector2i
var health: int
var max_health: int
var tags: Array[String]
var species_id: String
var faction_id: String


func _init(
		p_id: int,
		p_kind: String,
		p_display_name: String,
		p_position: Vector2i,
		p_max_health: int = 100,
		p_tags: Array[String] = [],
		p_species_id: String = "",
		p_faction_id: String = ""
	) -> void:
	id = p_id
	kind = p_kind
	display_name = p_display_name
	position = p_position
	max_health = p_max_health
	health = p_max_health
	tags = p_tags.duplicate()
	species_id = p_species_id if not p_species_id.is_empty() else p_kind
	faction_id = p_faction_id


func is_alive() -> bool:
	return health > 0


func to_dict() -> Dictionary:
	return {
		"id": str(id),
		"kind": kind,
		"display_name": display_name,
		"position": [position.x, position.y],
		"health": health,
		"max_health": max_health,
		"tags": tags.duplicate(),
		"species_id": species_id,
		"faction_id": faction_id,
	}


static func from_dict(row: Dictionary) -> SimEntity:
	var position_data: Array = row["position"]
	var raw_tags: Array = row.get("tags", [])
	var typed_tags: Array[String] = []
	for tag in raw_tags:
		typed_tags.append(str(tag))
	var entity := SimEntity.new(
		Int64CodecScript.parse(row["id"], "entity ID"), str(row["kind"]), str(row["display_name"]),
		Vector2i(int(position_data[0]), int(position_data[1])),
		int(row["max_health"]), typed_tags,
		str(row.get("species_id", row["kind"])), str(row.get("faction_id", ""))
	)
	entity.health = int(row["health"])
	return entity
