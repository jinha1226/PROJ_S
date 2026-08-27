class_name SpeciesRelationTable
extends RefCounted

const NEUTRAL := {"base_trust": 0, "base_fear": 0, "base_hostility": 0}

var _rows: Dictionary = {}


func set_relation(
		observer_species_id: String,
		subject_species_id: String,
		base_trust: int,
		base_fear: int,
		base_hostility: int
	) -> void:
	if not _rows.has(observer_species_id):
		_rows[observer_species_id] = {}
	_rows[observer_species_id][subject_species_id] = {
		"base_trust": clampi(base_trust, -100, 100),
		"base_fear": clampi(base_fear, 0, 100),
		"base_hostility": clampi(base_hostility, 0, 100),
	}


func get_relation(observer_species_id: String, subject_species_id: String) -> Dictionary:
	if not _rows.has(observer_species_id):
		return NEUTRAL.duplicate()
	return _rows[observer_species_id].get(subject_species_id, NEUTRAL).duplicate()


func to_dict() -> Dictionary:
	var rows: Array = []
	var observers: Array = _rows.keys()
	observers.sort()
	for observer in observers:
		var subjects: Array = _rows[observer].keys()
		subjects.sort()
		for subject in subjects:
			var values: Dictionary = _rows[observer][subject]
			rows.append({
				"observer_species_id": observer,
				"subject_species_id": subject,
				"base_trust": values["base_trust"],
				"base_fear": values["base_fear"],
				"base_hostility": values["base_hostility"],
			})
	return {"rows": rows}


static func from_dict(data: Dictionary):
	var table = load("res://sim/species_relation_table.gd").new()
	for row in data.get("rows", []):
		table.set_relation(
			str(row["observer_species_id"]), str(row["subject_species_id"]),
			int(row["base_trust"]), int(row["base_fear"]), int(row["base_hostility"])
		)
	return table
