class_name PersonalityDefinitionRegistry
extends RefCounted

const PersonalityProfileScript = preload("res://sim/personality_profile.gd")

const SCHEMA_ID := "personality-facets-v1"
const GENERATOR_RULESET_ID := "personality-lab-latin-hypercube-v1"
const KEYED_HASH_RULESET_ID := "sha256-u31-v1"
const FACET_IDS := ["aggression", "altruism", "boldness", "composure"]

class PersonalityFacetDef extends RefCounted:
	var def_version: int
	var facet_id: String
	var min_value: int
	var neutral_value: int
	var max_value: int
	var low_label: String
	var high_label: String

	func _init(p_id: String, p_low: String, p_high: String) -> void:
		def_version = 1
		facet_id = p_id
		min_value = 0
		neutral_value = 500
		max_value = 999
		low_label = p_low
		high_label = p_high

const LABELS := {
	"aggression": ["온건", "호전"], "altruism": ["자기중심", "이타"],
	"boldness": ["신중", "대담"], "composure": ["동요", "침착"],
}


static func definitions() -> Array:
	var rows: Array = []
	for facet_id in FACET_IDS:
		rows.append(PersonalityFacetDef.new(facet_id, LABELS[facet_id][0], LABELS[facet_id][1]))
	return rows


static func validation_error() -> String:
	var rows: Array = definitions()
	if rows.size() != FACET_IDS.size(): return "missing_personality_facet_definition"
	var previous := ""
	for index in range(rows.size()):
		var definition = rows[index]
		if definition.def_version != 1 or definition.facet_id != FACET_IDS[index] \
				or (index > 0 and definition.facet_id <= previous): return "invalid_personality_facet_identity"
		if definition.min_value != 0 or definition.neutral_value != 500 or definition.max_value != 999 \
				or definition.low_label.is_empty() or definition.high_label.is_empty():
			return "invalid_personality_facet_definition"
		previous = definition.facet_id
	return ""


static func profile_error(profile) -> String:
	if profile == null or profile.profile_schema_version != 1:
		return "unsupported_personality_profile_schema"
	if profile.generation_ruleset_id != GENERATOR_RULESET_ID:
		return "unsupported_personality_generator"
	if profile.facet_rows.size() != FACET_IDS.size():
		return "missing_personality_facet"
	var previous := ""
	for index in range(profile.facet_rows.size()):
		var row: Dictionary = profile.facet_rows[index]
		if not (row.get("facet_id") is String) or not (row.get("base_value") is int):
			return "invalid_personality_facet_row"
		var facet_id: String = row.facet_id
		if not FACET_IDS.has(facet_id): return "unknown_personality_facet"
		if index > 0 and facet_id <= previous: return "duplicate_or_unsorted_personality_facet"
		if int(row.base_value) < 0 or int(row.base_value) > 999: return "personality_facet_out_of_range"
		previous = facet_id
	return ""


static func profile_wire_error(row: Variant) -> String:
	if not (row is Dictionary): return "invalid_personality_profile"
	var exact_keys: Array = row.keys(); exact_keys.sort()
	if exact_keys != ["facet_rows", "generation_ruleset_id", "profile_schema_version"]:
		return "invalid_personality_profile_keys"
	if row.get("profile_schema_version") != 1: return "unsupported_personality_profile_schema"
	if row.get("generation_ruleset_id") != GENERATOR_RULESET_ID: return "unsupported_personality_generator"
	if not (row.get("facet_rows") is Array): return "invalid_personality_facet_rows"
	if row.facet_rows.size() != FACET_IDS.size(): return "missing_personality_facet"
	var previous := ""
	for index in range(row.facet_rows.size()):
		var facet_row: Variant = row.facet_rows[index]
		if not (facet_row is Dictionary): return "invalid_personality_facet_row"
		var facet_keys: Array = facet_row.keys(); facet_keys.sort()
		var base_value: Variant = facet_row.get("base_value")
		var base_is_integer_number: bool = base_value is int or (base_value is float and base_value == floor(base_value))
		if facet_keys != ["base_value", "facet_id"] or not (facet_row.get("facet_id") is String) \
				or not base_is_integer_number: return "invalid_personality_facet_row"
		var facet_id: String = facet_row.facet_id
		if not FACET_IDS.has(facet_id): return "unknown_personality_facet"
		if index > 0 and facet_id <= previous: return "duplicate_or_unsorted_personality_facet"
		if int(facet_row.base_value) < 0 or int(facet_row.base_value) > 999: return "personality_facet_out_of_range"
		previous = facet_id
	return profile_error(PersonalityProfileScript.from_dict(row))


static func generate(personality_seed: int, trial_slot: int):
	if trial_slot < 0 or trial_slot > 3: return null
	var rows: Array = []
	for facet_id in FACET_IDS:
		var ranks: Array[Dictionary] = []
		for slot in range(4):
			ranks.append({"slot": slot, "u31": _keyed_u31(personality_seed, facet_id, slot, "perm")})
		ranks.sort_custom(func(a: Dictionary, b: Dictionary):
			return int(a.u31) < int(b.u31) if int(a.u31) != int(b.u31) else int(a.slot) < int(b.slot))
		var stratum := 0
		for rank in range(4):
			if int(ranks[rank].slot) == trial_slot: stratum = rank
		var jitter := _keyed_u31(personality_seed, facet_id, trial_slot, "jitter") % 250
		rows.append({"facet_id": facet_id, "base_value": stratum * 250 + jitter})
	return PersonalityProfileScript.new(GENERATOR_RULESET_ID, rows)


static func _keyed_u31(personality_seed: int, facet_id: String, slot: int, purpose: String) -> int:
	var key := "%s|%d|%s|%d|%s" % [GENERATOR_RULESET_ID, personality_seed, facet_id, slot, purpose]
	var digest: PackedByteArray = key.sha256_buffer()
	return ((int(digest[0]) & 0x7f) << 24) | (int(digest[1]) << 16) | (int(digest[2]) << 8) | int(digest[3])
