class_name PersonalTalentRules
extends RefCounted

# Tags persist with the entity; the versioned seed event makes later guild
# arrivals deterministic without consuming combat/personality random streams.
const EVENT_ID := "campaign.personal_talents_initialized"
const RULESET_ID := "human-personal-talents-v1"
const TAG_PREFIX := "personal_talent:"
const IDS := ["STRONG", "DEXTEROUS", "ARCANE", "TOUGH", "NIMBLE", "STEADY"]
const DEFINITIONS := {
	"STRONG": {"label":"타고난 근력", "description":"힘 +1", "stats":{"STR":1}, "combat":{}},
	"DEXTEROUS": {"label":"정교한 손", "description":"민첩 +1", "stats":{"DEX":1}, "combat":{}},
	"ARCANE": {"label":"마력 감응", "description":"지능 +1 · 마법 사용 조건은 아닙니다", "stats":{"INT":1}, "combat":{}},
	"TOUGH": {"label":"강인한 체질", "description":"방어 +1", "stats":{}, "combat":{"armor_flat":1}},
	"NIMBLE": {"label":"날렵한 반사신경", "description":"회피 +3%p", "stats":{}, "combat":{"dodge_milli":30}},
	"STEADY": {"label":"안정된 방어", "description":"막기 +3%p", "stats":{}, "combat":{"parry_milli":30}},
}

static func seed_event(world):
	for event in world.events:
		if event.type == EVENT_ID:return event
	return null

static func generated_id(seed_value:String, entity_id:int)->String:
	var digest := (RULESET_ID+"|"+seed_value+"|"+str(entity_id)).sha256_buffer()
	return str(IDS[int(digest[0]) % IDS.size()])

static func for_entity(entity)->Dictionary:
	if entity == null:return {}
	for tag in entity.tags:
		if str(tag).begins_with(TAG_PREFIX):
			var talent_id := str(tag).trim_prefix(TAG_PREFIX)
			if not DEFINITIONS.has(talent_id):return {}
			var row:Dictionary = DEFINITIONS[talent_id].duplicate(true)
			row["id"] = talent_id
			return row
	return {}

static func apply_stats(entity, base:Dictionary)->Dictionary:
	var result := base.duplicate(true)
	for stat_id in for_entity(entity).get("stats",{}):
		result[stat_id] = int(result.get(stat_id,0)) + int(for_entity(entity).stats[stat_id])
	return result

static func apply_combat(entity, modifiers:Dictionary)->Dictionary:
	var talent := for_entity(entity)
	if talent.is_empty():return modifiers
	var result := modifiers.duplicate(true)
	var totals:Dictionary = result.get("totals",{}).duplicate(true)
	for key in talent.combat:
		totals[key] = int(totals.get(key,0)) + int(talent.combat[key])
	result["totals"] = totals
	result["personal_talent"] = talent
	return result

static func snapshot_enabled(snapshot:Dictionary)->bool:
	for row in snapshot.get("events",[]):
		if row is Dictionary and str(row.get("type","")) == EVENT_ID:return true
	return false
