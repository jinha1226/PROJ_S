class_name BodyCombatRules
extends RefCounted

const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const BodyRegistryScript=preload("res://sim/body_template_registry.gd")
const CONTENT_PATH:="res://data/content/body_combat_rules.json"
const MAX_PACKET_VALUE:=100000
static var _CONTENT:Dictionary=ContentLoaderScript.load_document(CONTENT_PATH)
static var RULESET_ID:String=str(_CONTENT.get("ruleset_id",""))


static func content_version()->String:return str(_CONTENT.get("content_version",""))


static func registry_error()->String:
	var error:=ContentLoaderScript.document_error(_CONTENT,"BODY_COMBAT_RULES",[
		"content_schema_version","content_version","content_type","ruleset_id",
		"hit_locations","armor_projection","layer_loss_milli","disable_zero_layers",
		"sever_form","sever_zero_layers"])
	if not error.is_empty():return error
	if RULESET_ID!="body-combat-b1-v1":return "body_combat_ruleset_mismatch"
	var rows:Variant=_CONTENT.get("hit_locations")
	if not rows is Array or rows.size()!=BodyRegistryScript.PART_IDS.size():
		return "invalid_body_hit_locations"
	var total:=0
	for index in range(rows.size()):
		var row:Variant=rows[index]
		if not row is Dictionary:return "invalid_body_hit_locations"
		var keys:Array=row.keys();keys.sort()
		if keys!=["part_id","weight"] \
				or str(row.get("part_id",""))!=BodyRegistryScript.PART_IDS[index] \
				or not row.get("weight") is int or int(row.weight)<=0:
			return "invalid_body_hit_locations"
		total+=int(row.weight)
	if total!=1000:return "invalid_body_hit_weight_total"
	var armor:Variant=_CONTENT.get("armor_projection")
	if not _exact_nonnegative_ints(armor,["impact_padding_per_flat",
			"pierce_protection_per_flat","rigidity_per_flat",
			"slash_protection_per_flat"]):return "invalid_body_armor_projection"
	var layers:Variant=_CONTENT.get("layer_loss_milli")
	if not _exact_nonnegative_ints(layers,BodyRegistryScript.LAYER_IDS):
		return "invalid_body_layer_loss"
	for value in layers.values():
		if int(value)>10000:return "invalid_body_layer_loss"
	if _CONTENT.get("disable_zero_layers")!=["SOFT_TISSUE","BONE"] \
			or _CONTENT.get("sever_form")!="SLASH" \
			or _CONTENT.get("sever_zero_layers")!=BodyRegistryScript.LAYER_IDS:
		return "invalid_body_condition_rules"
	return ""


static func hit_locations()->Array:
	return _CONTENT.get("hit_locations",[]).duplicate(true)


static func select_part(body,commitment_hash:String,target_id:int)->String:
	if not registry_error().is_empty() or body==null \
			or not body.has_method("validation_error") \
			or not body.validation_error().is_empty() or commitment_hash.is_empty() \
			or target_id!=body.entity_id:return ""
	var eligible:Array=[];var total:=0
	for row in _CONTENT.hit_locations:
		if body.part_condition(str(row.part_id))=="SEVERED":continue
		eligible.append(row);total+=int(row.weight)
	if eligible.is_empty() or total<=0:return ""
	var digest:PackedByteArray=("%s|commitment=%s|target=%d|lane=BODY_PART"%[
		RULESET_ID,commitment_hash,target_id]).sha256_buffer()
	var roll:=(((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3]))%total
	var cursor:=0
	for row in eligible:
		cursor+=int(row.weight)
		if roll<cursor:return str(row.part_id)
	return str(eligible[-1].part_id)


static func attack_packet(weapon,raw_damage:int)->Dictionary:
	if not registry_error().is_empty() or weapon==null \
			or not weapon.has_method("validation_error") \
			or not weapon.validation_error().is_empty() or raw_damage<=0 \
			or raw_damage>MAX_PACKET_VALUE:return {}
	var reference:=int(weapon.body_attack.reference_damage)
	var force:=_scaled(int(weapon.body_attack.base_force),raw_damage,reference)
	var stagger:=_scaled(int(weapon.body_attack.stagger_force),raw_damage,reference)
	if force>MAX_PACKET_VALUE or stagger>MAX_PACKET_VALUE:return {}
	return {"form":str(weapon.attack_form),"base_force":force,
		"penetration":int(weapon.body_attack.penetration),
		"contact_size":int(weapon.body_attack.contact_size),
		"stagger_force":stagger}.duplicate(true)


static func armor_packet(armor_flat:int)->Dictionary:
	if not registry_error().is_empty() or armor_flat<0 or armor_flat>MAX_PACKET_VALUE:return {}
	var row:Dictionary=_CONTENT.armor_projection
	var result:={"slash_protection":armor_flat*int(row.slash_protection_per_flat),
		"pierce_protection":armor_flat*int(row.pierce_protection_per_flat),
		"impact_padding":armor_flat*int(row.impact_padding_per_flat),
		"rigidity":armor_flat*int(row.rigidity_per_flat)}
	for value in result.values():
		if int(value)>MAX_PACKET_VALUE:return {}
	return result.duplicate(true)


static func layer_loss_milli(layer_id:String)->int:
	return int(_CONTENT.get("layer_loss_milli",{}).get(layer_id,-1))


static func disable_zero_layers()->Array:
	return _CONTENT.get("disable_zero_layers",[]).duplicate()


static func sever_zero_layers()->Array:
	return _CONTENT.get("sever_zero_layers",[]).duplicate()


static func sever_form()->String:return str(_CONTENT.get("sever_form",""))


static func _scaled(value:int,numerator:int,denominator:int)->int:
	if value==0:return 0
	return maxi(1,int(value*numerator/denominator))


static func _exact_nonnegative_ints(row:Variant,expected_keys:Array)->bool:
	if not row is Dictionary:return false
	var keys:Array=row.keys();keys.sort();var expected:Array=expected_keys.duplicate();expected.sort()
	if keys!=expected:return false
	for key in keys:
		if not row[key] is int or int(row[key])<0 or int(row[key])>MAX_PACKET_VALUE:
			return false
	return true
