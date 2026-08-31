class_name EnemyPerceptionRegistry
extends RefCounted

const RULESET_ID := "enemy-perception-v1"
const HERO_BASE_STEALTH := 500
const ACTIVE_COMBAT_RANGE := 10
const SEARCH_TURNS := 3
const ALERT_THRESHOLD := 1000
const SUSPICION_DECAY := 180

const PROFILES := {
	"goblin":{"species_id":"goblin","display_name":"고블린","glyph":"g",
		"sight_range":6,"perception":520,"max_health":60,"entity_kind":"melee_enemy"},
	"kobold":{"species_id":"kobold","display_name":"코볼트","glyph":"K",
		"sight_range":7,"perception":650,"max_health":48,"entity_kind":"kobold_enemy"},
}

static func profile(species_id:String)->Dictionary:
	return PROFILES.get(species_id,{}).duplicate(true)

static func suspicion_gain(species_id:String,distance:int,hero_stealth:int=HERO_BASE_STEALTH)->int:
	var row:Dictionary=profile(species_id)
	if row.is_empty():return 0
	# Integer-only and keyed solely by canonical state: repeated preview/save/replay
	# never rerolls perception. Near targets build suspicion faster.
	return clampi(260+int(row.perception)-hero_stealth-maxi(0,distance-1)*35,80,600)

static func registry_error()->String:
	for species_id in PROFILES:
		var row:Dictionary=PROFILES[species_id]
		var keys:Array=row.keys();keys.sort()
		if keys!=["display_name","entity_kind","glyph","max_health","perception",
			"sight_range","species_id"] or str(row.species_id)!=species_id:
			return "invalid_enemy_perception_profile"
		if int(row.sight_range)<1 or int(row.sight_range)>15 \
				or int(row.perception)<0 or int(row.perception)>1000 \
				or int(row.max_health)<1:
			return "invalid_enemy_perception_scalar"
	return ""
