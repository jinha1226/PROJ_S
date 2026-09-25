extends RefCounted
## The bestiary (zones spec §2–3): which species a zone holds, what a monster
## weighs on a floor, and what a soul stone of a role gives. Every number here
## is a table the difficulty gate tunes, never a per-species constant.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_monsters.json"))
const FAMILIES := ["rat","goblin","reptile","kobold","orc","elemental","insect","gnoll","undead","bat"]
const ROLES := ["PACK","BERSERK","AMBUSH","GUARD","ARCHER","CASTER"]
const ZONE_HP := {1:30,2:70,3:110,4:160}
const ZONE_ATTACK := {1:8,2:14,3:20,4:26}
## Percent added on each floor after a zone's first.
const FLOOR_STEP := 10
const ROLE_HP := {"PACK":60,"BERSERK":110,"AMBUSH":80,"GUARD":140,"ARCHER":80,"CASTER":70}
const ROLE_ATTACK := {"PACK":80,"BERSERK":130,"AMBUSH":120,"GUARD":80,"ARCHER":100,"CASTER":110}
## The attack the part table's damage values are written for (zone one).
const ACTIVE_BASE_ATTACK := 8
const PARTY_HP_STEP := 35

static func party_percent(size: int) -> int:
	return 100+PARTY_HP_STEP*(maxi(1,size)-1)
const ROLE_POINTS := {
	"PACK":{"con":1,"ev":1,"dex":1},
	"BERSERK":{"str":2,"con":1},
	"AMBUSH":{"dex":2,"ev":1},
	"GUARD":{"con":1,"ac":1,"sh":5},
	"ARCHER":{"dex":2,"int":1},
	"CASTER":{"int":2}}
const SCHOOL_ELEMENT := {"fire":"fire","ice":"ice","air":"air","hex":"will","summon":"will"}

static func table() -> Array:
	return content.get("species",[])

static func species(id: String) -> Dictionary:
	for row in table():
		if str(row.species_id) == id: return row
	return {}

static func in_zone(zone: int) -> Array:
	return table().filter(func(row): return int(row.get("zone",0)) == zone).map(func(row): return str(row.species_id))

static func zone_of(depth: int) -> int:
	return clampi((maxi(1,depth)-1)/3+1,1,4)

static func floor_percent(depth: int) -> int:
	return 100+FLOOR_STEP*((maxi(1,depth)-1)%3)

## A monster of `species_id` on floor `depth`: zone base × floor step × role.
## `attack_percent` scales the part table's damage values (Abilities.scaled).
static func monster_stats(species_id: String, depth: int) -> Dictionary:
	var role: String = str(species(species_id).get("role","PACK"))
	var zone := zone_of(depth)
	var step := floor_percent(depth)
	var hp: int = maxi(1,int(ZONE_HP[zone])*step/100*int(ROLE_HP.get(role,100))/100)
	var attack: int = maxi(1,int(ZONE_ATTACK[zone])*step/100*int(ROLE_ATTACK.get(role,100))/100)
	return {"hp":hp,"attack":attack,"ac":(zone-1)+(3 if role == "GUARD" else 0),
		"ev":3+(4 if role == "AMBUSH" else 0),"sh":20 if role == "GUARD" else 0,
		"range":4 if role in ["ARCHER","CASTER"] else 1,
		"attack_percent":int(ZONE_ATTACK[zone])*step/ACTIVE_BASE_ATTACK}

## A tier-one soul stone of `role` (§3.1): three points; a caster adds its
## school's resistance.
static func essence_stats(role: String, school: String) -> Dictionary:
	var result: Dictionary = (ROLE_POINTS.get(role,{}) as Dictionary).duplicate()
	if role == "CASTER" and SCHOOL_ELEMENT.has(school): result["res_"+str(SCHOOL_ELEMENT[school])] = 10
	return result
