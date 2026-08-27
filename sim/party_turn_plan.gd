class_name PartyTurnPlan
extends RefCounted

var _data: Dictionary
func _init(p_data: Dictionary = {}) -> void: _data = p_data.duplicate(true)
func to_dict() -> Dictionary: return _data.duplicate(true)
func get_value(key: String, fallback: Variant = null) -> Variant:
	var value: Variant = _data.get(key, fallback)
	return value.duplicate(true) if value is Dictionary or value is Array else value
