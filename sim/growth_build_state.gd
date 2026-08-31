class_name GrowthBuildState
extends RefCounted

const SCHEMA_VERSION := 1
const RegistryScript = preload("res://sim/growth_build_registry.gd")

var schema_version := SCHEMA_VERSION
var species_id: String
var xp_total := 0
var stat_allocations: Dictionary = _empty_stat_allocations()
var species_branch_ranks: Dictionary = {}
var unlocked_mutation_ids: Array[String] = []
var equipped_mutation_ids: Array[String] = ["", "", ""]
var processed_mutation_death_event_ids: Array[int] = []


func _init(p_species_id: String = "human") -> void:
	species_id = p_species_id
	_reset_species_branches()


func level() -> int:
	return RegistryScript.level_for_xp(xp_total)


func stat_points_available() -> int:
	var spent := 0
	for stat_id in RegistryScript.STAT_IDS: spent += int(stat_allocations.get(stat_id, 0))
	return RegistryScript.stat_points_for_level(level()) - spent


func species_points_available() -> int:
	var spent := 0
	for branch_id in RegistryScript.branch_ids(species_id):
		spent += int(species_branch_ranks.get(branch_id, 0))
	return RegistryScript.species_points_for_level(level()) - spent


func commit_award_xp(amount: int) -> Dictionary:
	if amount <= 0: return _rejected("invalid_growth_xp_award")
	if xp_total > RegistryScript.MAX_XP - amount: return _rejected("growth_xp_overflow")
	var candidate = _clone()
	candidate.xp_total += amount
	return _accepted(candidate, 0, {"level":candidate.level()})


func commit_spend_stat_point(stat_id: String) -> Dictionary:
	if validation_error() != "": return _rejected("invalid_growth_state")
	if stat_id not in RegistryScript.STAT_IDS: return _rejected("unknown_growth_stat")
	if stat_points_available() <= 0: return _rejected("no_growth_stat_points")
	var candidate = _clone()
	candidate.stat_allocations[stat_id] = int(candidate.stat_allocations[stat_id]) + 1
	return _accepted(candidate, 0)


func commit_spend_species_point(branch_id: String) -> Dictionary:
	if validation_error() != "": return _rejected("invalid_growth_state")
	if branch_id not in RegistryScript.branch_ids(species_id):
		return _rejected("unknown_growth_species_branch")
	if species_points_available() <= 0: return _rejected("no_growth_species_points")
	if int(species_branch_ranks.get(branch_id, 0)) >= 2:
		return _rejected("growth_species_branch_maxed")
	var candidate = _clone()
	candidate.species_branch_ranks[branch_id] = int(candidate.species_branch_ranks[branch_id]) + 1
	return _accepted(candidate, 0)


# The caller supplies facts from one canonical entity.died event. Every known
# family death is consumed once. The first consumed death with participation or
# LOS awards that family's trace with no RNG roll.
func commit_mutation_kill(source_death_event_id: int, monster_family_id: String,
		participated_in_damage: bool, witnessed_in_los: bool) -> Dictionary:
	if validation_error() != "": return _rejected("invalid_growth_state")
	if source_death_event_id <= 0: return _rejected("invalid_mutation_death_event")
	if source_death_event_id in processed_mutation_death_event_ids:
		return _rejected("duplicate_mutation_death_event")
	if not processed_mutation_death_event_ids.is_empty() \
			and source_death_event_id <= processed_mutation_death_event_ids[-1]:
		return _rejected("noncanonical_mutation_death_order")
	var mutation_id := RegistryScript.mutation_for_family(monster_family_id)
	if mutation_id.is_empty(): return _rejected("unknown_mutation_monster_family")
	var candidate = _clone()
	candidate.processed_mutation_death_event_ids.append(source_death_event_id)
	var already_unlocked: bool = mutation_id in candidate.unlocked_mutation_ids
	var eligible: bool = participated_in_damage or witnessed_in_los
	var acquired: bool = eligible and not already_unlocked
	if acquired:
		candidate.unlocked_mutation_ids.append(mutation_id)
		candidate.unlocked_mutation_ids.sort()
	return _accepted(candidate, 0, {
		"acquired":acquired, "eligible":eligible, "mutation_id":mutation_id,
		"reason":"" if acquired else ("mutation_family_already_acquired" \
			if already_unlocked else "mutation_kill_not_eligible"),
	})


# This is a pure transaction. On success the coordinator installs result.state
# and advances world time by result.time_cost in the same outer commit.
func commit_mutation_swap(slot_index: int, mutation_id: String, safe_phase: String) -> Dictionary:
	if validation_error() != "": return _rejected("invalid_growth_state")
	if safe_phase != RegistryScript.SAFE_MUTATION_SWAP_PHASE:
		return _rejected("mutation_swap_requires_grouped")
	if slot_index < 0 or slot_index >= RegistryScript.MUTATION_SLOT_COUNT:
		return _rejected("invalid_mutation_slot")
	if not mutation_id.is_empty() and mutation_id not in unlocked_mutation_ids:
		return _rejected("mutation_not_unlocked")
	if mutation_id == equipped_mutation_ids[slot_index]:
		return _rejected("mutation_slot_unchanged")
	if not mutation_id.is_empty() and mutation_id in equipped_mutation_ids:
		return _rejected("mutation_already_equipped")
	var candidate = _clone()
	candidate.equipped_mutation_ids[slot_index] = mutation_id
	return _accepted(candidate, RegistryScript.MUTATION_SWAP_TIME,
		{"slot_index":slot_index, "mutation_id":mutation_id})


func validation_error() -> String:
	if schema_version != SCHEMA_VERSION: return "unsupported_growth_build_schema"
	if not RegistryScript.has_species(species_id): return "unknown_growth_species"
	if xp_total < 0 or xp_total > RegistryScript.MAX_XP: return "invalid_growth_xp"
	var stat_keys: Array = stat_allocations.keys(); stat_keys.sort()
	var expected_stats: Array = RegistryScript.STAT_IDS.duplicate(); expected_stats.sort()
	if stat_keys != expected_stats: return "invalid_growth_stat_keys"
	var spent_stats := 0
	for stat_id in RegistryScript.STAT_IDS:
		if not _integer(stat_allocations[stat_id]) or int(stat_allocations[stat_id]) < 0:
			return "invalid_growth_stat_allocation"
		spent_stats += int(stat_allocations[stat_id])
	if spent_stats > RegistryScript.stat_points_for_level(level()):
		return "growth_stat_points_overspent"
	var branch_keys: Array = species_branch_ranks.keys(); branch_keys.sort()
	var expected_branches: Array = RegistryScript.branch_ids(species_id); expected_branches.sort()
	if branch_keys != expected_branches: return "invalid_growth_species_branch_keys"
	var spent_species := 0
	for branch_id in RegistryScript.branch_ids(species_id):
		if not _integer(species_branch_ranks[branch_id]) \
				or int(species_branch_ranks[branch_id]) < 0 \
				or int(species_branch_ranks[branch_id]) > 2:
			return "invalid_growth_species_branch_rank"
		spent_species += int(species_branch_ranks[branch_id])
	if spent_species > RegistryScript.species_points_for_level(level()):
		return "growth_species_points_overspent"
	var sorted_unlocked := unlocked_mutation_ids.duplicate(); sorted_unlocked.sort()
	if unlocked_mutation_ids != sorted_unlocked: return "noncanonical_unlocked_mutations"
	var seen_unlocked := {}
	for mutation_id in unlocked_mutation_ids:
		if seen_unlocked.has(mutation_id): return "duplicate_unlocked_mutation"
		seen_unlocked[mutation_id] = true
		if not RegistryScript.MUTATION_DEFINITIONS.has(mutation_id):
			return "unknown_unlocked_mutation"
	if equipped_mutation_ids.size() != RegistryScript.MUTATION_SLOT_COUNT:
		return "invalid_equipped_mutation_slots"
	var seen_equipped := {}
	for mutation_id in equipped_mutation_ids:
		if mutation_id.is_empty(): continue
		if mutation_id not in unlocked_mutation_ids: return "equipped_mutation_not_unlocked"
		if seen_equipped.has(mutation_id): return "duplicate_equipped_mutation"
		seen_equipped[mutation_id] = true
	var previous_event_id := 0
	for event_id in processed_mutation_death_event_ids:
		if not _integer(event_id) or int(event_id) <= previous_event_id:
			return "invalid_mutation_death_event_ids"
		previous_event_id = int(event_id)
	return ""


func to_dict() -> Dictionary:
	var stat_rows: Array = []
	for stat_id in RegistryScript.STAT_IDS:
		stat_rows.append({"stat_id":stat_id, "points":int(stat_allocations[stat_id])})
	var branch_rows: Array = []
	for branch_id in RegistryScript.branch_ids(species_id):
		branch_rows.append({"branch_id":branch_id, "rank":int(species_branch_ranks[branch_id])})
	return {
		"schema_version":schema_version, "species_id":species_id, "xp_total":xp_total,
		"stat_allocations":stat_rows, "species_branch_ranks":branch_rows,
		"unlocked_mutation_ids":unlocked_mutation_ids.duplicate(),
		"equipped_mutation_ids":equipped_mutation_ids.duplicate(),
		"processed_mutation_death_event_ids":processed_mutation_death_event_ids.map(
			func(event_id): return str(event_id)),
	}.duplicate(true)


static func from_dict(row: Dictionary):
	if not wire_error(row).is_empty(): return null
	var value = load("res://sim/growth_build_state.gd").new(str(row.species_id))
	value.schema_version = int(row.schema_version)
	value.xp_total = int(row.xp_total)
	value.stat_allocations.clear()
	for stat_row in row.stat_allocations:
		value.stat_allocations[str(stat_row.stat_id)] = int(stat_row.points)
	value.species_branch_ranks.clear()
	for branch_row in row.species_branch_ranks:
		value.species_branch_ranks[str(branch_row.branch_id)] = int(branch_row.rank)
	value.unlocked_mutation_ids.clear()
	for mutation_id in row.unlocked_mutation_ids:
		value.unlocked_mutation_ids.append(str(mutation_id))
	value.equipped_mutation_ids.clear()
	for mutation_id in row.equipped_mutation_ids:
		value.equipped_mutation_ids.append(str(mutation_id))
	for event_id in row.processed_mutation_death_event_ids:
		value.processed_mutation_death_event_ids.append(int(str(event_id)))
	return value


static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_growth_build_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["equipped_mutation_ids", "processed_mutation_death_event_ids",
			"schema_version", "species_branch_ranks", "species_id", "stat_allocations",
			"unlocked_mutation_ids", "xp_total"]:
		return "invalid_growth_build_keys"
	if not _integer(row.schema_version) or int(row.schema_version) != SCHEMA_VERSION:
		return "unsupported_growth_build_schema"
	if not row.species_id is String or not _integer(row.xp_total) \
			or not row.stat_allocations is Array or not row.species_branch_ranks is Array \
			or not row.unlocked_mutation_ids is Array or not row.equipped_mutation_ids is Array \
			or not row.processed_mutation_death_event_ids is Array:
		return "invalid_growth_build_shape"
	if not RegistryScript.has_species(str(row.species_id)): return "unknown_growth_species"
	if row.stat_allocations.size() != RegistryScript.STAT_IDS.size():
		return "invalid_growth_stat_rows"
	for index in range(RegistryScript.STAT_IDS.size()):
		var stat_row: Variant = row.stat_allocations[index]
		if not stat_row is Dictionary or stat_row.keys().size() != 2 \
				or not stat_row.has_all(["stat_id", "points"]) \
				or not stat_row.stat_id is String or str(stat_row.stat_id) != RegistryScript.STAT_IDS[index] \
				or not _integer(stat_row.points):
			return "invalid_growth_stat_row"
	var branch_ids := RegistryScript.branch_ids(str(row.species_id))
	if row.species_branch_ranks.size() != branch_ids.size():
		return "invalid_growth_species_branch_rows"
	for index in range(branch_ids.size()):
		var branch_row: Variant = row.species_branch_ranks[index]
		if not branch_row is Dictionary or branch_row.keys().size() != 2 \
				or not branch_row.has_all(["branch_id", "rank"]) \
				or not branch_row.branch_id is String \
				or str(branch_row.branch_id) != branch_ids[index] or not _integer(branch_row.rank):
			return "invalid_growth_species_branch_row"
	for mutation_id in row.unlocked_mutation_ids:
		if not mutation_id is String: return "invalid_unlocked_mutation_shape"
	if row.equipped_mutation_ids.size() != RegistryScript.MUTATION_SLOT_COUNT:
		return "invalid_equipped_mutation_slots"
	for mutation_id in row.equipped_mutation_ids:
		if not mutation_id is String: return "invalid_equipped_mutation_shape"
	var previous_event_id := 0
	for event_id in row.processed_mutation_death_event_ids:
		if not event_id is String or not event_id.is_valid_int() \
				or str(int(event_id)) != event_id or int(event_id) <= previous_event_id:
			return "invalid_mutation_death_event_ids"
		previous_event_id = int(event_id)
	var value = from_dict_unchecked(row)
	return value.validation_error()


static func from_dict_unchecked(row: Dictionary):
	var value = load("res://sim/growth_build_state.gd").new(str(row.species_id))
	value.schema_version = int(row.schema_version)
	value.xp_total = int(row.xp_total)
	value.stat_allocations.clear()
	for stat_row in row.stat_allocations:
		value.stat_allocations[str(stat_row.stat_id)] = int(stat_row.points)
	value.species_branch_ranks.clear()
	for branch_row in row.species_branch_ranks:
		value.species_branch_ranks[str(branch_row.branch_id)] = int(branch_row.rank)
	value.unlocked_mutation_ids.clear()
	for mutation_id in row.unlocked_mutation_ids:
		value.unlocked_mutation_ids.append(str(mutation_id))
	value.equipped_mutation_ids.clear()
	for mutation_id in row.equipped_mutation_ids:
		value.equipped_mutation_ids.append(str(mutation_id))
	value.processed_mutation_death_event_ids.clear()
	for event_id in row.processed_mutation_death_event_ids:
		value.processed_mutation_death_event_ids.append(int(str(event_id)))
	return value


func _clone():
	return from_dict(to_dict())


func _reset_species_branches() -> void:
	species_branch_ranks.clear()
	for branch_id in RegistryScript.branch_ids(species_id): species_branch_ranks[branch_id] = 0


func _accepted(candidate, time_cost: int, extra: Dictionary = {}) -> Dictionary:
	var result := {"accepted":true, "reason":"", "time_cost":time_cost, "state":candidate}
	result.merge(extra, true)
	return result


func _rejected(reason: String) -> Dictionary:
	return {"accepted":false, "reason":reason, "time_cost":0, "state":_clone()}


static func _empty_stat_allocations() -> Dictionary:
	return {"MIGHT":0, "AGILITY":0, "VITALITY":0}


static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
