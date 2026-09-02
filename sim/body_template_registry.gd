class_name BodyTemplateRegistry
extends RefCounted

const ContentLoaderScript=preload("res://sim/json_content_loader.gd")
const SpeciesCatalogScript=preload("res://sim/species_catalog_registry.gd")
const RULESET_ID:="body-simulation-b0-v1"
const PART_IDS:=["HEAD","TORSO","LEFT_ARM","RIGHT_ARM","LEFT_LEG","RIGHT_LEG"]
const LAYER_IDS:=["SKIN","SOFT_TISSUE","BONE"]
const SCALAR_IDS:=["blood_capacity","shock_threshold","consciousness_threshold",
	"skin_toughness","soft_tissue_cushioning","bone_fracture_threshold"]
static var _TEMPLATES:Dictionary=_body_templates()


static func template_ids()->Array[String]:
	var result:Array[String]=[]
	for template_id in _TEMPLATES:result.append(str(template_id))
	result.sort();return result


static func player_species_ids()->Array[String]:
	return SpeciesCatalogScript.playable_ids()


static func template_definition(template_id:String)->Dictionary:
	return _TEMPLATES[template_id].duplicate(true) if _TEMPLATES.has(template_id) else {}


static func template_for_species(species_id:String)->Dictionary:
	for template_id in template_ids():
		var row:Dictionary=_TEMPLATES[template_id]
		if str(row.species_id)==species_id:return row.duplicate(true)
	return template_definition("generic_humanoid")


static func registry_error()->String:
	var catalog_error:=SpeciesCatalogScript.registry_error()
	if not catalog_error.is_empty():return catalog_error
	if not _TEMPLATES.has("generic_humanoid") or not _TEMPLATES.has("goblin"):
		return "missing_non_player_body_template"
	var players:Array[String]=[]
	var seen_species:Dictionary={}
	for template_id in template_ids():
		var row:Dictionary=_TEMPLATES[template_id]
		if str(row.get("template_id",""))!=template_id:return "body_template_key_mismatch"
		var error:=template_error(row)
		if not error.is_empty():return error
		if seen_species.has(str(row.species_id)):return "duplicate_body_species_template"
		seen_species[str(row.species_id)]=true
		if bool(row.player_template):players.append(str(row.species_id))
	players.sort()
	if players!=SpeciesCatalogScript.playable_ids():return "invalid_player_body_template_set"
	return ""


static func _body_templates()->Dictionary:
	var result:Dictionary={}
	for species_id in SpeciesCatalogScript.all_ids():
		result[species_id]=SpeciesCatalogScript.body_template(species_id)
	return result


static func template_error(row:Variant)->String:
	if not row is Dictionary:return "invalid_body_template_shape"
	var keys:Array=row.keys();keys.sort()
	if keys!=["parts","player_template","scalars","species_id","systemic",
			"template_id","variation"]:return "invalid_body_template_keys"
	if not row.template_id is String or str(row.template_id).is_empty() \
			or not row.species_id is String or str(row.species_id).is_empty() \
			or not row.player_template is bool or not row.parts is Array \
			or row.parts.size()!=PART_IDS.size():return "invalid_body_template_shape"
	for index in range(PART_IDS.size()):
		var part:Variant=row.parts[index]
		if not part is Dictionary:return "invalid_body_template_part"
		var part_keys:Array=part.keys();part_keys.sort()
		if part_keys!=["layers","part_id","vital_tags"] \
				or str(part.get("part_id",""))!=PART_IDS[index] \
				or part.get("layers")!=LAYER_IDS or not part.get("vital_tags") is Array:
			return "invalid_body_template_part"
		var expected_vitals:Array=["BRAIN"] if PART_IDS[index]=="HEAD" else (
			["HEART_LUNG"] if PART_IDS[index]=="TORSO" else [])
		if part.vital_tags!=expected_vitals:return "invalid_body_template_vital_tags"
	for scalar_group in [[row.systemic,["blood_capacity","consciousness_threshold",
		"shock_threshold"]],[row.scalars,["bone_fracture_threshold","skin_toughness",
		"soft_tissue_cushioning"]],[row.variation,["blood_capacity",
		"bone_fracture_threshold","consciousness_threshold","shock_threshold",
		"skin_toughness","soft_tissue_cushioning"]]]:
		if not scalar_group[0] is Dictionary:return "invalid_body_template_scalars"
		var scalar_keys:Array=scalar_group[0].keys();scalar_keys.sort()
		if scalar_keys!=scalar_group[1]:return "invalid_body_template_scalars"
		for value in scalar_group[0].values():
			if not value is int or int(value)<0 or int(value)>100000:
				return "invalid_body_template_scalar"
	if int(row.systemic.blood_capacity)<=0 or int(row.systemic.shock_threshold)<=0 \
			or int(row.systemic.consciousness_threshold)<=0:
		return "invalid_body_template_scalar"
	return ""


static func scalar_baseline(template:Dictionary,scalar_id:String)->int:
	return int(template.systemic.get(scalar_id,template.scalars.get(scalar_id,0)))


static func scalars_within_template(values:Variant,template:Dictionary)->bool:
	if not values is Dictionary:return false
	var keys:Array=values.keys();keys.sort()
	var expected:Array=SCALAR_IDS.duplicate();expected.sort()
	if keys!=expected:return false
	for scalar_id in SCALAR_IDS:
		if not values[scalar_id] is int:return false
		var baseline:=scalar_baseline(template,scalar_id)
		var variation:=int(template.variation[scalar_id])
		if absi(int(values[scalar_id])-baseline)>variation:return false
	return true
