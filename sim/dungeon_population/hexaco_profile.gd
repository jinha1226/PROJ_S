class_name DungeonHexacoProfile
extends RefCounted

const SCHEMA_VERSION := 1
const FACETS := ["H", "E", "X", "A", "C", "O"]

var values: Dictionary = {}

func _init(p_values: Dictionary = {}) -> void:
	for facet in FACETS:
		values[facet] = clampi(int(p_values.get(facet, 500)), 0, 1000)

static func generated(seed: int, actor_id: int):
	var sampled: Dictionary = {}
	for facet in FACETS:
		sampled[facet] = _sample(seed, actor_id, facet, 1001)
	return load("res://sim/dungeon_population/hexaco_profile.gd").new(sampled)

func value(facet: String) -> int:
	return int(values.get(facet, 500))

func to_dict() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION,"H":value("H"),"E":value("E"),
		"X":value("X"),"A":value("A"),"C":value("C"),"O":value("O")}

static func from_dict(row: Dictionary):
	return load("res://sim/dungeon_population/hexaco_profile.gd").new(row)

static func wire_error(row: Variant) -> String:
	if not row is Dictionary:return "invalid_hexaco_shape"
	var keys:Array=row.keys();keys.sort()
	if keys != ["A","C","E","H","O","X","schema_version"] \
			or row.get("schema_version") != SCHEMA_VERSION:
		return "invalid_hexaco_wire"
	for facet in FACETS:
		if not _integer(row.get(facet)) or int(row[facet])<0 or int(row[facet])>1000:
			return "invalid_hexaco_value"
	return ""

static func sample(seed: int, actor_id: int, lane: String, modulus: int) -> int:
	return _sample(seed, actor_id, lane, modulus)

static func _sample(seed: int, actor_id: int, lane: String, modulus: int) -> int:
	var digest := (str(seed)+"/"+str(actor_id)+"/"+lane).sha256_text()
	return int(digest.substr(0, 8).hex_to_int() % maxi(1, modulus))

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value==floor(value))
