class_name WeaponDefinition
extends RefCounted

const PROFICIENCY_IDS := ["SWORD", "AXE", "BLUNT", "SPEAR", "RANGED", "UNARMED"]
const ATTACK_FORMS := ["SLASH", "PIERCE", "IMPACT"]
const AMMO_KINDS := ["NONE", "ARROW", "BOLT"]
const TRAIT_IDS := ["NONE", "AXE_CLEAVE", "SPEAR_REACH", "BLUNT_STUN",
	"FAST_UNARMED", "BOW_REPEAT", "CROSSBOW_RELOAD"]
const STAT_IDS := ["STR", "DEX", "INT"]
const SCALING_GRADES := ["NONE", "E", "D", "C", "B", "A"]

var weapon_id: String
var label: String
var proficiency_id: String
var attack_form: String
var range_min: int
var range_max: int
var base_damage: int
var accuracy_milli: int
var armor_penetration_flat: int
var attack_time: int
var ammo_kind: String
var ammo_cost: int
var reload_required: bool
var reload_time: int
var trait_id: String
var secondary_damage_milli: int
var stun_chance_milli: int
var two_handed: bool
var body_attack:Dictionary
var scaling: Dictionary
var natural_weapon: bool


func _init(row: Dictionary = {}) -> void:
	weapon_id = str(row.get("weapon_id", ""))
	label = str(row.get("label", ""))
	proficiency_id = str(row.get("proficiency_id", ""))
	attack_form = str(row.get("attack_form", ""))
	range_min = int(row.get("range_min", 1))
	range_max = int(row.get("range_max", 1))
	base_damage = int(row.get("base_damage", 0))
	accuracy_milli = int(row.get("accuracy_milli", 0))
	armor_penetration_flat = int(row.get("armor_penetration_flat", 0))
	attack_time = int(row.get("attack_time", 100))
	ammo_kind = str(row.get("ammo_kind", "NONE"))
	ammo_cost = int(row.get("ammo_cost", 0))
	reload_required = bool(row.get("reload_required", false))
	reload_time = int(row.get("reload_time", 0))
	trait_id = str(row.get("trait_id", "NONE"))
	secondary_damage_milli = int(row.get("secondary_damage_milli", 0))
	stun_chance_milli = int(row.get("stun_chance_milli", 0))
	two_handed = bool(row.get("two_handed", false))
	body_attack={}
	var body_source:Variant=row.get("body_attack",{})
	if body_source is Dictionary:
		for key in ["base_force","penetration","contact_size","stagger_force",
				"reference_damage"]:
			body_attack[key]=body_source.get(key,-1)
	scaling = {}
	var source:Variant=row.get("scaling",{})
	if source is Dictionary:
		for stat_id in STAT_IDS:scaling[stat_id]=str(source.get(stat_id,"NONE"))
	natural_weapon = bool(row.get("natural_weapon",false))


func validation_error() -> String:
	if weapon_id.is_empty() or label.is_empty(): return "invalid_weapon_identity"
	if proficiency_id not in PROFICIENCY_IDS: return "invalid_weapon_proficiency"
	if attack_form not in ATTACK_FORMS: return "invalid_weapon_attack_form"
	if range_min < 1 or range_max < range_min or range_max > 12: return "invalid_weapon_range"
	if base_damage < 0 or base_damage > 1000: return "invalid_weapon_damage"
	if accuracy_milli < -500 or accuracy_milli > 500: return "invalid_weapon_accuracy"
	if armor_penetration_flat < 0 or armor_penetration_flat > 1000: return "invalid_weapon_penetration"
	if attack_time < 1 or attack_time > 10000: return "invalid_weapon_attack_time"
	if ammo_kind not in AMMO_KINDS: return "invalid_weapon_ammo_kind"
	if ammo_cost < 0 or ammo_cost > 100: return "invalid_weapon_ammo_cost"
	if (ammo_kind == "NONE") != (ammo_cost == 0): return "invalid_weapon_ammo_contract"
	if reload_required != (trait_id == "CROSSBOW_RELOAD"): return "invalid_weapon_reload_contract"
	if reload_required and reload_time <= 0: return "invalid_weapon_reload_time"
	if not reload_required and reload_time != 0: return "invalid_weapon_reload_time"
	if trait_id not in TRAIT_IDS: return "invalid_weapon_trait"
	if secondary_damage_milli < 0 or secondary_damage_milli > 1000: return "invalid_weapon_secondary_damage"
	if stun_chance_milli < 0 or stun_chance_milli > 1000: return "invalid_weapon_stun_chance"
	if not two_handed is bool: return "invalid_weapon_hands"
	var body_keys:Array=body_attack.keys();body_keys.sort()
	if body_keys!=["base_force","contact_size","penetration","reference_damage",
			"stagger_force"]:return "invalid_weapon_body_attack"
	for key in body_keys:
		if not body_attack[key] is int or int(body_attack[key])<0 \
				or int(body_attack[key])>100000:return "invalid_weapon_body_attack"
	if int(body_attack.contact_size)<=0 or int(body_attack.reference_damage)<=0:
		return "invalid_weapon_body_attack"
	if scaling.keys().size()!=STAT_IDS.size():return "invalid_weapon_scaling_shape"
	for stat_id in STAT_IDS:
		if not scaling.has(stat_id) or str(scaling[stat_id]) not in SCALING_GRADES:
			return "invalid_weapon_scaling_grade"
	if (trait_id == "AXE_CLEAVE") != (secondary_damage_milli > 0): return "invalid_weapon_cleave_contract"
	if (trait_id == "BLUNT_STUN") != (stun_chance_milli > 0): return "invalid_weapon_stun_contract"
	return ""


func to_dict() -> Dictionary:
	return {
		"weapon_id": weapon_id, "label": label, "proficiency_id": proficiency_id,
		"attack_form": attack_form, "range_min": range_min, "range_max": range_max,
		"base_damage": base_damage, "accuracy_milli": accuracy_milli,
		"armor_penetration_flat": armor_penetration_flat, "attack_time": attack_time,
		"ammo_kind": ammo_kind, "ammo_cost": ammo_cost,
		"reload_required": reload_required, "reload_time": reload_time,
		"trait_id": trait_id, "secondary_damage_milli": secondary_damage_milli,
		"stun_chance_milli": stun_chance_milli,
		"two_handed": two_handed,
		"body_attack":body_attack.duplicate(true),
		"scaling":scaling.duplicate(true), "natural_weapon":natural_weapon,
	}.duplicate(true)
