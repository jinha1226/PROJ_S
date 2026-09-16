class_name AbilityBindingRules
extends RefCounted

const RULESET_ID := "ability-binding-v1"
const MAX_SLOTS := 6
const REMOVAL_POLICY := "LOCKED_UNTIL_POLICY_DEFINED"
const ALIASES := {
	# Keep aliases explicit so an old/content-facing name cannot create a second
	# effect or bypass duplicate detection.
	"FIRE_BOLT": "FIREBOLT",
}
const ActiveSkillRegistryScript = preload("res://sim/abilities/active_skill_registry.gd")

static func dual_mode(id:String)->bool:
	return preload("res://sim/abilities/monster_ability_definitions.gd").has(canonical_id(id))


static func canonical_id(ability_id: String) -> String:
	var value := str(ability_id)
	return str(ALIASES.get(value, value))


static func has(ability_id: String) -> bool:
	return not ActiveSkillRegistryScript.definition(canonical_id(ability_id)).is_empty() \
		and (canonical_id(ability_id) not in ActiveSkillRegistryScript.GROUND_SKILLS or canonical_id(ability_id)=="WATER_SAC")


static func definition(ability_id: String) -> Dictionary:
	return ActiveSkillRegistryScript.definition(canonical_id(ability_id))


static func slot_limit(level: int) -> int:
	return clampi(int(level), 0, MAX_SLOTS)


static func binding_ids_error(ids: Variant) -> String:
	if not ids is Array:
		return "invalid_ability_binding_ids"
	if ids.size() > MAX_SLOTS:
		return "ability_binding_slots_overflow"
	var previous := ""
	var seen: Dictionary = {}
	for raw_id in ids:
		if not raw_id is String or str(raw_id).is_empty():
			return "invalid_ability_binding_id"
		var canonical := canonical_id(str(raw_id))
		if canonical != str(raw_id) or not has(canonical):
			return "invalid_ability_binding_id"
		if seen.has(canonical):
			return "duplicate_ability_binding"
		if not previous.is_empty() and canonical <= previous:
			return "noncanonical_ability_binding_order"
		seen[canonical] = true
		previous = canonical
	return ""


static func effect_preview(ability_id: String) -> Dictionary:
	var canonical := canonical_id(ability_id)
	var row := definition(canonical)
	if row.is_empty():
		return {}
	var preview:Dictionary={"ability_id": canonical, "label": str(row.get("name", canonical)),
		"kind": "ACTIVE", "cost": int(row.get("cost", 0)),
		"range": int(row.get("range", 0)), "effect": str(row.get("effect", "")),
		"power": int(row.get("power", 0)),"dual_mode":dual_mode(canonical)}
	if canonical=="FIREBOLT":
		preview.passive="일반 공격 적중 시 기본 화염 피해 6 추가 · 추가 MP 소모 없음"
		preview.active="화염탄 · 기본 위력 32 · MP 3 · 사거리 5"
	elif dual_mode(canonical):
		preview.passive=str(row.passive)
		preview.active="%s · MP %d · %s"%[row.name,int(row.cost),"자신" if row.target=="SELF" else "사거리 %d"%int(row.range)]
		if row.effect in ["DAMAGE","EXECUTE","LEAP","ACID","SIPHON","DISCHARGE"]:preview.active+=" · 기본 위력 %d"%int(row.power)
		preview.active+=str({"WATER":" · 대상 칸에 물 80 · 젖음·전도·냉각 기반","COLD":" · 대상 칸 냉각 1800 · 물이 있으면 결빙 가능","ELECTRIC":" · 대상 칸 출력 45 방전 · 전도 경로의 아군도 피해","EXECUTE":" · 다친 적에게 +12","LEAP":" · 적 옆 빈칸으로 도약","HIDE":" · 방어 +8, 300시간","SHELL":" · 방어 +12, 200시간 이동 불가","ACID":" · HP 5 소모","FROST":" · 대상 주변 1칸 둔화 지대, 300시간","POISON":" · 독 3중첩, 300시간","REGENERATE":" · 식량 10 소모, HP 24 회복","STONE":" · 방어 +10, 300시간 이동 불가","VEIL":" · 은폐 300시간, 공격하면 해제","ECHO":" · 6칸 탐지, 300시간","DEEP":" · 바라보는 방향 6칸 탐지, 300시간","DISCHARGE":" · 주변 2칸 방전, 전하당 +6 후 소모","SIPHON":" · 피해만큼 회복"}.get(str(row.effect),""))
	var catalog:Dictionary=preload("res://sim/abilities/monster_ability_catalog.gd").for_ability(canonical)
	if not catalog.is_empty():preview.label=str(catalog.label)
	return preview
