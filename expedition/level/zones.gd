extends RefCounted
## Four three-floor zones, each ending in a boss room.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const FINAL_DEPTH := 12
const FLOORS_PER_ZONE := 3
const ZONE_COUNT := 4
const THEMES := ["F1_RUINS","F2_MINES","F3_TEMPLE","F4_CRYPT"]
const NAMES := ["무너진 성채 지하","불타는 폐광","잠긴 지하 신전","망자의 묘역"]
const BOSS_TEMPLATES := ["throne_room","foundry","binding_altar","crypt_heart"]
const ELEMENTS := {1:["poison"],2:["fire","air"],3:["ice","poison"],4:["will"]}
const FIRST_ELEMENT_DEPTH := 3

static func zone_of(depth: int) -> int:
	return clampi((maxi(1,depth)-1)/FLOORS_PER_ZONE+1,1,ZONE_COUNT)

static func first_floor(zone: int) -> int:
	return (clampi(zone,1,ZONE_COUNT)-1)*FLOORS_PER_ZONE+1

static func last_floor(zone: int) -> int:
	return clampi(zone,1,ZONE_COUNT)*FLOORS_PER_ZONE

static func theme_id(depth: int) -> String:
	return str(THEMES[zone_of(depth)-1])

static func zone_name(zone: int) -> String:
	return str(NAMES[clampi(zone,1,ZONE_COUNT)-1])

static func is_boss_floor(depth: int) -> bool:
	return depth > 0 and depth % FLOORS_PER_ZONE == 0

static func elements(zone: int) -> Array:
	return (ELEMENTS.get(clampi(zone,1,ZONE_COUNT),[]) as Array).duplicate()

static func floor_element(s, depth: int) -> String:
	if depth < FIRST_ELEMENT_DEPTH: return ""
	var pool := elements(zone_of(depth))
	if pool.is_empty(): return ""
	return str(pool[Hexaco.sample(int(s.seed_value),depth,"zone_element",pool.size())])

static func boss_template(zone: int) -> String:
	return str(BOSS_TEMPLATES[clampi(zone,1,ZONE_COUNT)-1])
