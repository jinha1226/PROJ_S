extends RefCounted

# Our data adapter. Combat, status, AI and injury algorithms remain the host's.
const Loader=preload("res://sim/json_content_loader.gd")
const PATH:="res://data/content/dcss_enemies.json"
static var _content:Dictionary=Loader.load_document(PATH)
static var DEFINITIONS:Dictionary=Loader.index_rows(_content.get("definitions",[]),"species_id")

static func profile(species_id:String)->Dictionary:
	return DEFINITIONS.get(species_id,{}).duplicate(true)

static func profile_id(species_id:String)->String:
	return str(DEFINITIONS.get(species_id,{}).get("combat_profile",{}).get("profile_id",""))

static func loadout_id(species_id:String)->String:
	return str(DEFINITIONS.get(species_id,{}).get("loadout_id",""))

static func content_version()->String:
	return str(_content.get("content_version",""))

static func registry_error()->String:
	var error:=Loader.document_error(_content,"DCSS_ENEMIES",["content_schema_version","content_version","content_type","definitions"])
	if not error.is_empty():return error
	error=Loader.rows_error(_content.get("definitions",[]),"species_id")
	if not error.is_empty():return error
	for row in DEFINITIONS.values():
		var keys:Array=row.keys();keys.sort()
		if keys!=["body_proxy","combat_profile","default_attack_time","display_name","entity_kind","glyph","hd","loadout_id","max_health","perception","reference_id","sight_range","species_id"]:return "invalid_dcss_enemy_keys"
		if not str(row.species_id).begins_with("dcss_") or str(row.display_name).is_empty() or row.entity_kind!="melee_enemy" or not row.combat_profile is Dictionary:return "invalid_dcss_enemy_identity"
		for key in ["hd","max_health","perception","sight_range","default_attack_time"]:
			if not row[key] is int:return "invalid_dcss_enemy_scalar"
		if int(row.hd)<1 or int(row.max_health)<1 or int(row.perception)<0 or int(row.perception)>1000 or int(row.sight_range)<1 or int(row.sight_range)>15 or int(row.default_attack_time)!=100:return "invalid_dcss_enemy_range"
	return ""

static func spawn_species(floor_index:int,seed:int,group_index:int,member_index:int)->String:
	# Only early-game monsters are registered. F1 HD1, F2 HD1/2.
	var pool:Array[String]=["goblin","kobold"]
	var max_hd:=1 if floor_index<=1 else 2
	var ids:Array=DEFINITIONS.keys();ids.sort()
	for id in ids:
		if int(DEFINITIONS[id].hd)>max_hd:continue
		# Weight weak early monsters higher than the occasional gnoll/river rat.
		for repetition in range(3 if int(DEFINITIONS[id].hd)==1 else 1):pool.append(str(id))
	# Preserve the first tutorial encounter while expanding the remaining groups.
	if group_index==0:return "kobold" if member_index%4==0 else "goblin"
	var digest:PackedByteArray=("dcss-spawn-v1/%d/%d/%d/%d"%[seed,floor_index,group_index,member_index]).sha256_buffer()
	return pool[(int(digest[0])*256+int(digest[1]))%pool.size()]
