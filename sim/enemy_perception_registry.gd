class_name EnemyPerceptionRegistry
extends RefCounted

const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")

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

static func has_line_of_sight(world,origin:Vector2i,target:Vector2i)->bool:
	if world==null or not world.in_bounds(origin) or not world.in_bounds(target):return false
	var x0:=origin.x;var y0:=origin.y;var x1:=target.x;var y1:=target.y
	var dx:=absi(x1-x0);var sx:=1 if x0<x1 else -1
	var dy:=-absi(y1-y0);var sy:=1 if y0<y1 else -1
	var error:=dx+dy
	while x0!=x1 or y0!=y1:
		var doubled:=2*error
		if doubled>=dy:error+=dy;x0+=sx
		if doubled<=dx:error+=dx;y0+=sy
		if Vector2i(x0,y0)==target:return true
		var definition:Dictionary=TerrainRegistryScript.definition(
			str(world.tile_at(Vector2i(x0,y0)).terrain))
		if definition.is_empty() or not bool(definition.get("passable",false)):return false
	return true

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
