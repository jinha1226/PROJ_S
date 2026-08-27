class_name AgentProfileRegistry
extends RefCounted

const RULESET_ID := "agent-profiles-v1"

const ZONES := {
	"north_farm": [[7, 4], [8, 4], [7, 5], [8, 5]],
	"south_farm": [[15, 18], [16, 18], [15, 19], [16, 19]],
	"smithy": [[5, 10], [6, 10]],
	"clinic": [[17, 9], [18, 9]],
	"herb_garden": [[19, 7], [19, 8]],
	"market": [[11, 11], [12, 11], [11, 12], [12, 12]],
	"bakery": [[8, 15], [9, 15]],
	"inn": [[14, 14], [15, 14], [14, 15], [15, 15]],
	"warehouse": [[19, 15], [20, 15]],
	"square": [[11, 10], [12, 10], [10, 11], [13, 11], [10, 12], [13, 12]],
	"north_gate": [[11, 1]], "south_gate": [[12, 22]],
	"west_gate": [[1, 11]], "east_gate": [[22, 12]],
	"home_doran": [[4, 5]], "home_sera": [[18, 19]],
	"home_borin": [[4, 9]], "home_hana": [[18, 6]],
	"home_tae": [[20, 16]], "home_nari": [[7, 16]],
	"home_mira": [[16, 16]], "home_rook": [[3, 12]],
	"home_sena": [[20, 12]], "home_ido": [[20, 17]],
}

const ROSTER := [
	{"profile_id":"doran", "name":"Doran", "species":"human", "role_id":"north_farmer", "role_glyph":"1", "home":"home_doran", "work":"north_farm", "meal":"inn", "social":"square"},
	{"profile_id":"sera", "name":"Sera", "species":"human", "role_id":"south_farmer", "role_glyph":"2", "home":"home_sera", "work":"south_farm", "meal":"inn", "social":"square"},
	{"profile_id":"borin", "name":"Borin", "species":"dwarf", "role_id":"blacksmith", "role_glyph":"3", "home":"home_borin", "work":"smithy", "meal":"inn", "social":"square"},
	{"profile_id":"hana", "name":"Hana", "species":"human", "role_id":"healer", "role_glyph":"4", "home":"home_hana", "work":"clinic", "meal":"inn", "social":"herb_garden"},
	{"profile_id":"tae", "name":"Tae", "species":"human", "role_id":"merchant", "role_glyph":"5", "home":"home_tae", "work":"market", "meal":"inn", "social":"square"},
	{"profile_id":"nari", "name":"Nari", "species":"human", "role_id":"baker", "role_glyph":"6", "home":"home_nari", "work":"bakery", "meal":"inn", "social":"square"},
	{"profile_id":"mira", "name":"Mira", "species":"human", "role_id":"innkeeper", "role_glyph":"7", "home":"home_mira", "work":"inn", "meal":"inn", "social":"inn"},
	{"profile_id":"rook", "name":"Rook", "species":"human", "role_id":"west_guard", "role_glyph":"8", "home":"home_rook", "work":"west_gate", "meal":"inn", "social":"square"},
	{"profile_id":"sena", "name":"Sena", "species":"human", "role_id":"east_guard", "role_glyph":"9", "home":"home_sena", "work":"east_gate", "meal":"inn", "social":"square"},
	{"profile_id":"ido", "name":"Ido", "species":"goblin", "role_id":"carrier", "role_glyph":"0", "home":"home_ido", "work":"warehouse", "meal":"inn", "social":"market"},
]


static func has(profile_id: String) -> bool:
	return not definition(profile_id).is_empty()


static func definition(profile_id: String) -> Dictionary:
	for row in ROSTER:
		if row["profile_id"] == profile_id:
			var result: Dictionary = row.duplicate(true)
			result["home_position"] = zone_positions(str(row["home"]))[0]
			result["work_positions"] = zone_positions(str(row["work"]))
			result["meal_positions"] = zone_positions(str(row["meal"]))
			result["social_positions"] = zone_positions(str(row["social"]))
			result["patrol_points"] = _patrol_for(profile_id)
			result["need_rates_per_minute"] = {"hunger": 3, "fatigue": 2, "social_need": 2}
			result["need_thresholds"] = {"hunger": 700, "fatigue": 800, "social_need": 600}
			result["routine_blocks"] = _routines(row)
			return result
	return {}


static func zone_positions(zone_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw in ZONES.get(zone_id, []):
		result.append(Vector2i(int(raw[0]), int(raw[1])))
	return result


static func current_block(profile_id: String, minute_of_day: int) -> Dictionary:
	var profile := definition(profile_id)
	for block in profile.get("routine_blocks", []):
		var start := int(block["start_minute_of_day"])
		var end := int(block["end_minute_of_day"])
		var active := (minute_of_day >= start and minute_of_day < end) if start < end else (minute_of_day >= start or minute_of_day < end)
		if active:
			return block.duplicate(true)
	return {"start_minute_of_day": 0, "end_minute_of_day": 420, "activity": "REST", "target_zone_id": profile.get("home", "")}


static func next_block(profile_id: String, minute_of_day: int) -> Dictionary:
	var profile := definition(profile_id)
	var best: Dictionary = {}
	var best_delta := 1441
	for block in profile.get("routine_blocks", []):
		var delta: int = (int(block["start_minute_of_day"]) - minute_of_day + 1440) % 1440
		if delta > 0 and delta < best_delta:
			best_delta = delta
			best = block
	return best.duplicate(true)


static func _routines(row: Dictionary) -> Array:
	return [
		{"start_minute_of_day": 420, "end_minute_of_day": 720, "activity":"WORK", "target_zone_id":row["work"]},
		{"start_minute_of_day": 720, "end_minute_of_day": 780, "activity":"EAT", "target_zone_id":row["meal"]},
		{"start_minute_of_day": 780, "end_minute_of_day": 1080, "activity":"WORK", "target_zone_id":row["work"]},
		{"start_minute_of_day": 1080, "end_minute_of_day": 1200, "activity":"SOCIALIZE", "target_zone_id":row["social"]},
		{"start_minute_of_day": 1200, "end_minute_of_day": 420, "activity":"REST", "target_zone_id":row["home"]},
	]


static func _patrol_for(profile_id: String) -> Array[Vector2i]:
	if profile_id == "rook":
		return [Vector2i(1,11), Vector2i(11,10), Vector2i(11,1)]
	if profile_id == "sena":
		return [Vector2i(22,12), Vector2i(13,12), Vector2i(12,22)]
	if profile_id == "ido":
		return [Vector2i(19,15), Vector2i(11,11), Vector2i(5,10), Vector2i(17,9)]
	return []
