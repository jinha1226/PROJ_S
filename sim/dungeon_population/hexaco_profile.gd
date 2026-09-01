class_name DungeonHexacoProfile
extends RefCounted

const SCHEMA_VERSION := 1
const FACETS := ["H", "E", "X", "A", "C", "O"]
const STYLE_AXES := {
	"H":{"high_modifier":"원칙적인", "low_modifier":"실리적인",
		"high_noun":"원칙주의자", "low_noun":"실리주의자"},
	"E":{"high_modifier":"섬세한", "low_modifier":"대담한",
		"high_noun":"감성가", "low_noun":"행동가"},
	"X":{"high_modifier":"사교적인", "low_modifier":"과묵한",
		"high_noun":"사교가", "low_noun":"관찰자"},
	"A":{"high_modifier":"온화한", "low_modifier":"직선적인",
		"high_noun":"중재자", "low_noun":"독립가"},
	"C":{"high_modifier":"신중한", "low_modifier":"즉흥적인",
		"high_noun":"계획가", "low_noun":"개척자"},
	"O":{"high_modifier":"탐구적인", "low_modifier":"현실적인",
		"high_noun":"탐구가", "low_noun":"실무가"}}

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

func style_summary() -> Dictionary:
	var ranked: Array[Dictionary] = []
	for facet in FACETS:
		var facet_value := value(facet)
		ranked.append({"facet":facet, "value":facet_value,
			"deviation":absi(facet_value - 500), "high":facet_value >= 500})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.deviation) > int(b.deviation) if a.deviation != b.deviation \
			else FACETS.find(str(a.facet)) < FACETS.find(str(b.facet)))
	var primary: Dictionary = ranked[0]
	if int(primary.deviation) < 120:
		return {"label":"균형 잡힌 현실주의자", "primary_facet":str(primary.facet),
			"secondary_facet":"", "schema_version":1}.duplicate(true)
	var secondary: Dictionary = ranked[1]
	var primary_terms: Dictionary = STYLE_AXES[str(primary.facet)]
	var secondary_terms: Dictionary = STYLE_AXES[str(secondary.facet)]
	var noun := str(primary_terms.high_noun if bool(primary.high) \
		else primary_terms.low_noun)
	var modifier := str(secondary_terms.high_modifier if bool(secondary.high) \
		else secondary_terms.low_modifier)
	return {"label":"%s %s" % [modifier, noun],
		"primary_facet":str(primary.facet),
		"secondary_facet":str(secondary.facet), "schema_version":1}.duplicate(true)

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
