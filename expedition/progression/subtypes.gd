extends RefCounted
## One descriptive subtype per effect. These labels never grant a bonus.
const IDS := ["DEFENSE","EVASION","REGEN","REFLECT","BLEED","CRUSH","VITAL","FURY","SNIPE","VOLLEY","VENOM","ELEMENT","SUMMON","DEATH","HEAL","HEX","BOOST"]
const NAMES := {"DEFENSE":"방어","EVASION":"회피","REGEN":"재생","REFLECT":"반사","BLEED":"출혈","CRUSH":"분쇄","VITAL":"급소","FURY":"광폭","SNIPE":"저격","VOLLEY":"연사","VENOM":"맹독","ELEMENT":"원소","SUMMON":"소환","DEATH":"사령","HEAL":"회복","HEX":"저주","BOOST":"강화"}
const GROUP := {"DEFENSE":"TANK","EVASION":"TANK","REGEN":"TANK","REFLECT":"TANK","BLEED":"MELEE","CRUSH":"MELEE","VITAL":"MELEE","FURY":"MELEE","SNIPE":"RANGED","VOLLEY":"RANGED","VENOM":"RANGED","ELEMENT":"MAGIC","SUMMON":"MAGIC","DEATH":"MAGIC","HEAL":"SUPPORT","HEX":"SUPPORT","BOOST":"SUPPORT"}
const GROUP_NAMES := {"TANK":"탱커","MELEE":"근딜","RANGED":"원딜","MAGIC":"마딜","SUPPORT":"지원"}
## Internal tactical fit channels remain numeric; display and loot use subtype ids.
const LEGACY_FAMILY := {"BLEED":1,"CRUSH":2,"VITAL":3,"FURY":4,"DEFENSE":5,"EVASION":5,"REGEN":5,"REFLECT":5,"SNIPE":6,"VOLLEY":6,"ELEMENT":7,"HEX":8,"VENOM":9,"SUMMON":10,"DEATH":11,"HEAL":12,"BOOST":12}
static var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).effects

static func of(effect_id: String) -> String:
	var value: String = str(effects.get(effect_id,{}).get("subtype",""))
	return value if value in IDS else ""

static func label(subtype: String) -> String:
	return str(NAMES.get(subtype,""))

static func long_label(subtype: String) -> String:
	return "%s · %s" % [GROUP_NAMES[GROUP[subtype]],NAMES[subtype]] if NAMES.has(subtype) else ""
