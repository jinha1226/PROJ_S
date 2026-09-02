class_name WeaponLoadoutState
extends RefCounted

const SCHEMA_VERSION := 1
const RegistryScript = preload("res://sim/weapon_registry.gd")
const AMMO_KINDS := ["ARROW", "BOLT"]

var schema_version := SCHEMA_VERSION
var equipped_weapon_id := "UNARMED_STRIKE"
var ammo_pools := {"ARROW": 0, "BOLT": 0}
var crossbow_loaded := false


func _init(weapon_id: String = "UNARMED_STRIKE", arrows: int = 0, bolts: int = 0) -> void:
	equipped_weapon_id = weapon_id if RegistryScript.has(weapon_id) else "UNARMED_STRIKE"
	ammo_pools = {"ARROW": maxi(0, arrows), "BOLT": maxi(0, bolts)}


func equip(weapon_id: String) -> bool:
	if not RegistryScript.has(weapon_id) or weapon_id == equipped_weapon_id: return false
	equipped_weapon_id = weapon_id
	return true


func attack_error() -> String:
	var weapon = RegistryScript.definition(equipped_weapon_id)
	if weapon == null: return "unknown_equipped_weapon"
	if weapon.ammo_kind == "NONE": return ""
	if int(ammo_pools.get(weapon.ammo_kind, 0)) < weapon.ammo_cost: return "ammo_empty"
	if weapon.reload_required and not crossbow_loaded: return "reload_required"
	return ""


func consume_attack() -> Dictionary:
	var error := attack_error()
	if not error.is_empty(): return {"accepted": false, "reason": error}
	var weapon = RegistryScript.definition(equipped_weapon_id)
	if weapon.ammo_kind != "NONE":
		ammo_pools[weapon.ammo_kind] = int(ammo_pools[weapon.ammo_kind]) - weapon.ammo_cost
	if weapon.reload_required: crossbow_loaded = false
	return {"accepted": true, "reason": "", "weapon_id": equipped_weapon_id,
		"ammo_kind": weapon.ammo_kind, "ammo_remaining": int(ammo_pools.get(weapon.ammo_kind, 0)),
		"reload_required": weapon.reload_required and not crossbow_loaded}.duplicate(true)


func reload() -> Dictionary:
	var weapon = RegistryScript.definition(equipped_weapon_id)
	if weapon == null: return {"accepted": false, "reason": "unknown_equipped_weapon"}
	if not weapon.reload_required: return {"accepted": false, "reason": "weapon_does_not_reload"}
	if crossbow_loaded: return {"accepted": false, "reason": "already_loaded"}
	if int(ammo_pools.get(weapon.ammo_kind, 0)) < weapon.ammo_cost:
		return {"accepted": false, "reason": "ammo_empty"}
	crossbow_loaded = true
	return {"accepted": true, "reason": "", "weapon_id": equipped_weapon_id,
		"reload_time": weapon.reload_time}.duplicate(true)


func to_dict() -> Dictionary:
	return {"schema_version": schema_version, "equipped_weapon_id": equipped_weapon_id,
		"ammo_pools": [{"ammo_kind":"ARROW", "amount":int(ammo_pools.ARROW)},
			{"ammo_kind":"BOLT", "amount":int(ammo_pools.BOLT)}],
		"crossbow_loaded": crossbow_loaded}.duplicate(true)


static func from_dict(row: Dictionary):
	var value = load("res://sim/weapon_loadout_state.gd").new(str(row.equipped_weapon_id))
	value.schema_version = SCHEMA_VERSION
	value.ammo_pools = {"ARROW": 0, "BOLT": 0}
	for ammo_row in row.ammo_pools:
		value.ammo_pools[str(ammo_row.ammo_kind)] = int(ammo_row.amount)
	value.crossbow_loaded = bool(row.crossbow_loaded)
	return value


static func wire_error(row: Variant) -> String:
	if not row is Dictionary: return "invalid_weapon_loadout_shape"
	var keys: Array = row.keys(); keys.sort()
	if keys != ["ammo_pools", "crossbow_loaded", "equipped_weapon_id", "schema_version"]:
		return "invalid_weapon_loadout_keys"
	if row.schema_version != SCHEMA_VERSION or not RegistryScript.has(str(row.equipped_weapon_id)):
		return "invalid_weapon_loadout_identity"
	if not row.crossbow_loaded is bool or not row.ammo_pools is Array \
			or row.ammo_pools.size() != AMMO_KINDS.size():
		return "invalid_weapon_loadout_ammo_shape"
	for index in range(AMMO_KINDS.size()):
		var ammo_row = row.ammo_pools[index]
		if not ammo_row is Dictionary or ammo_row.keys().size() != 2 \
				or str(ammo_row.get("ammo_kind", "")) != AMMO_KINDS[index] \
				or not _integer(ammo_row.get("amount")) or int(ammo_row.amount) < 0:
			return "invalid_weapon_loadout_ammo_row"
	return ""


static func _integer(value:Variant)->bool:
	return value is int or (value is float and value==floor(value))
