class_name SpeciesCatalogRegistry
extends RefCounted

const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const CONTENT_PATH:="res://data/content/species_catalog.json"
const RULESET_ID:="species-catalog-v1"
const FALLBACK_SPECIES_ID:="generic_humanoid"

static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var _PLAYABLE:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("playable_species",[]),"species_id")
static var _NON_PLAYER:Dictionary=ContentLoaderScript.index_rows(
	_CONTENT.get("non_player_species",[]),"species_id")


static func playable_ids()->Array[String]:
	var result:Array[String]=[]
	for species_id in _PLAYABLE:result.append(str(species_id))
	result.sort();return result


static func picker_ids()->Array[String]:
	var result:Array[String]=[]
	for species_id in _CONTENT.get("picker_order",[]):result.append(str(species_id))
	return result


static func all_ids()->Array[String]:
	var result:=playable_ids()
	for species_id in _NON_PLAYER:result.append(str(species_id))
	result.sort();return result


static func has_playable(species_id:String)->bool:
	return _PLAYABLE.has(species_id)


static func catalog_row(species_id:String)->Dictionary:
	if _PLAYABLE.has(species_id):return _PLAYABLE[species_id].duplicate(true)
	return _NON_PLAYER[species_id].duplicate(true) if _NON_PLAYER.has(species_id) else {}


static func growth_definition(species_id:String)->Dictionary:
	if not _PLAYABLE.has(species_id):return {}
	var row:Dictionary=_PLAYABLE[species_id]
	var growth:Dictionary=row.growth.duplicate(true)
	growth["species_id"]=species_id;growth["label"]=str(row.label)
	return growth


static func body_template(species_id:String)->Dictionary:
	var resolved_id:=species_id if species_id in all_ids() else FALLBACK_SPECIES_ID
	var row:=catalog_row(resolved_id)
	if row.is_empty():return {}
	var body:Dictionary=row.body.duplicate(true)
	body["template_id"]=resolved_id;body["species_id"]=resolved_id
	body["player_template"]=_PLAYABLE.has(resolved_id)
	return body


static func base_stats(species_id:String)->Dictionary:
	var row:=catalog_row(species_id)
	return row.get("base_stats",{}).duplicate(true) if not row.is_empty() else {}


static func natural_weapon_id(species_id:String)->String:
	var row:=catalog_row(species_id)
	return str(row.get("natural_weapon_id",""))


static func content_version()->String:
	return str(_CONTENT.get("content_version",""))


static func registry_error()->String:
	var document_error:=ContentLoaderScript.document_error(_CONTENT,"SPECIES_CATALOG",[
		"content_schema_version","content_version","content_type","ruleset_id",
		"picker_order","playable_species","non_player_species"])
	if not document_error.is_empty():return document_error
	if str(_CONTENT.get("ruleset_id",""))!=RULESET_ID:return "species_ruleset_mismatch"
	var playable_error:=ContentLoaderScript.rows_error(
		_CONTENT.get("playable_species",[]),"species_id")
	if not playable_error.is_empty():return playable_error
	var non_player_error:=ContentLoaderScript.rows_error(
		_CONTENT.get("non_player_species",[]),"species_id")
	if not non_player_error.is_empty():return non_player_error
	var players:=playable_ids();var picker:=picker_ids()
	if players.is_empty():return "invalid_playable_species_set"
	var sorted_picker:Array[String]=picker.duplicate();sorted_picker.sort()
	var unique_picker:Dictionary={}
	for species_id in picker:
		if unique_picker.has(species_id):return "invalid_species_picker_order"
		unique_picker[species_id]=true
	if sorted_picker!=players:return "invalid_species_picker_order"
	var seen:Dictionary={}
	for species_id in playable_ids():
		var row:Dictionary=_PLAYABLE[species_id]
		var keys:Array=row.keys();keys.sort()
		if keys!=["base_stats","body","growth","label","natural_weapon_id","species_id"] \
				or str(row.species_id)!=species_id or str(row.label).is_empty() \
				or not row.growth is Dictionary or not row.body is Dictionary:
			return "invalid_playable_species_row"
		var combat_error:=_combat_identity_error(row)
		if not combat_error.is_empty():return combat_error
		seen[species_id]=true
	for species_id in _NON_PLAYER:
		if seen.has(species_id):return "duplicate_species_identity"
		var row:Dictionary=_NON_PLAYER[species_id]
		var keys:Array=row.keys();keys.sort()
		if keys!=["base_stats","body","label","natural_weapon_id","species_id"] \
				or str(row.species_id)!=species_id or str(row.label).is_empty() \
				or not row.body is Dictionary:
			return "invalid_non_player_species_row"
		var combat_error:=_combat_identity_error(row)
		if not combat_error.is_empty():return combat_error
		seen[species_id]=true
	if not _NON_PLAYER.has(FALLBACK_SPECIES_ID) or not _NON_PLAYER.has("goblin"):
		return "missing_required_non_player_species"
	return ""


static func _combat_identity_error(row:Dictionary)->String:
	if not row.get("base_stats") is Dictionary:return "invalid_species_base_stats"
	var keys:Array=row.base_stats.keys();keys.sort()
	if keys!=["DEX","INT","STR"]:return "invalid_species_base_stats"
	for stat_id in ["STR","DEX","INT"]:
		if not row.base_stats[stat_id] is int or int(row.base_stats[stat_id])<0:
			return "invalid_species_base_stats"
	var weapon_id:=str(row.get("natural_weapon_id",""))
	var weapon=WeaponRegistryScript.definition(weapon_id)
	if weapon==null or not bool(weapon.natural_weapon):return "invalid_species_natural_weapon"
	return ""
