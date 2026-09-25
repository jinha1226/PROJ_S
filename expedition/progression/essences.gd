extends RefCounted
## Essences: what a monster leaves behind and a member absorbs. Every catalog
## part is one; the caster essences have no part and give a spell instead.
## A variant id is "<BASE>@<element>": the base row with that element's tag
## and ten more points of that element's resistance.
const Abilities = preload("res://expedition/items/abilities.gd")
const ROLES := {"PACK":"무리","BERSERK":"광폭","AMBUSH":"기습","GUARD":"수호","ARCHER":"사수","CASTER":"술사"}
const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}
const MAX_TIER := 3
const MAX_LEVEL := 10
## How many spells stand ready at once: the floor HUD draws this many buttons.
const READY_SPELLS := 5
const FIRST_KILL_PERCENT := 100
const REPEAT_PERCENT := 25
const CASTER_BY_SCHOOL := {"fire":"FIRE_CALLER","ice":"FROST_IMP","air":"STORM_BAT","hex":"GOBLIN_HEXER","summon":"GNOLL_SUMMONER"}
const SPELL_CAP := {1:3,2:6,3:10}
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/essences.json"))
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

static func base_of(id: String) -> String:
	return id.get_slice("@",0)

static func variant_element(id: String) -> String:
	return id.get_slice("@",1) if id.contains("@") else ""

static func has(id: String) -> bool:
	if id.is_empty() or not content.rows.has(base_of(id)): return false
	var element := variant_element(id)
	return element.is_empty() or ELEMENTS.has(element)

static func row(id: String) -> Dictionary:
	if not has(id): return {}
	var base: Dictionary = content.rows[base_of(id)]
	var result := {"name":str(base.get("name","")),"stats":(base.get("stats",{}) as Dictionary).duplicate(),
		"role":str(base.get("role","")),"element":str(base.get("element","")),
		"school":str(base.get("school","")),"species":str(base.get("species",""))}
	var element := variant_element(id)
	if not element.is_empty():
		result.element = element
		var key := "res_"+element
		result.stats[key] = int(result.stats.get(key,0))+10
	return result

## The part's item name for a part essence, the row's own name for a caster.
static func title(id: String) -> String:
	if not has(id): return ""
	var name: String = str(row(id).name)
	if name.is_empty(): name = str(Abilities.DEFINITIONS.get(base_of(id),{}).get("item",base_of(id)))
	var element := variant_element(id)
	return name if element.is_empty() else "%s %s" % [ELEMENTS[element],name]

static func stats(id: String, tier: int) -> Dictionary:
	var result: Dictionary = {}
	var base: Dictionary = row(id).get("stats",{})
	for key in base: result[key] = int(base[key])*clampi(tier,1,MAX_TIER)
	return result

static func role(id: String) -> String: return str(row(id).get("role",""))

static func element(id: String) -> String: return str(row(id).get("element",""))

static func school(id: String) -> String: return str(row(id).get("school",""))

## The absorbed tier; an essence put straight into a slot (fixtures, sims)
## counts as tier one.
static func tier(actor: Dictionary, id: String) -> int:
	if id.is_empty(): return 0
	var known: int = int(actor.get("essences",{}).get(id,0))
	if known > 0: return mini(known,MAX_TIER)
	return 1 if id in actor.get("equipped_abilities",[]) else 0

static func equipped(actor: Dictionary) -> Array:
	return actor.get("equipped_abilities",[]).filter(func(id): return has(str(id)))

static func slot_count(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_LEVEL)

static func spell_cap(tier: int) -> int:
	return int(SPELL_CAP[clampi(tier,1,MAX_TIER)])

static func active_power(tier: int, base: int) -> int:
	return base*(100+25*(clampi(tier,1,MAX_TIER)-1))/100
