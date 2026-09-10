class_name EnvironmentArmorRegistry
extends RefCounted

const BodyRegistry = preload("res://sim/body_template_registry.gd")
const Materials = preload("res://sim/material_registry.gd")

# Gameplay coefficients authored for this project. They are not measured
# material properties. The item wire keeps stable definition IDs; this table
# adds only the environmental interpretation needed by the damage bridge.
const _DEFINITIONS := {
	"ARMOR_CLOTH_ROBE": {
		"material_id":"TEXTILE",
		"coverage":["TORSO", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"],
		"fire_reduction_milli":500, "electric_reduction_milli":600,
		"wet_electric_retention_milli":200,
	},
	"ARMOR_LEATHER": {
		"material_id":"LEATHER",
		"coverage":["TORSO", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"],
		"fire_reduction_milli":250, "electric_reduction_milli":300,
		"wet_electric_retention_milli":500,
	},
	"ARMOR_PADDED": {
		"material_id":"TEXTILE",
		"coverage":["TORSO", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"],
		"fire_reduction_milli":450, "electric_reduction_milli":550,
		"wet_electric_retention_milli":250,
	},
	"ARMOR_CHAIN": {
		"material_id":"IRON",
		"coverage":["TORSO", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"],
		"fire_reduction_milli":150, "electric_reduction_milli":100,
		"wet_electric_retention_milli":850,
	},
	"ARMOR_PLATE": {
		"material_id":"IRON",
		"coverage":["TORSO", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"],
		"fire_reduction_milli":200, "electric_reduction_milli":150,
		"wet_electric_retention_milli":900,
	},
	"SHIELD_WOOD": {
		"material_id":"WOOD", "coverage":["LEFT_ARM"],
		"fire_reduction_milli":150, "electric_reduction_milli":200,
		"wet_electric_retention_milli":400,
	},
	"SHIELD_IRON": {
		"material_id":"IRON", "coverage":["LEFT_ARM"],
		"fire_reduction_milli":100, "electric_reduction_milli":50,
		"wet_electric_retention_milli":950,
	},
}


static func definition(definition_id:String)->Dictionary:
	return _DEFINITIONS.get(definition_id,{}).duplicate(true)


static func registry_error()->String:
	for definition_id in _DEFINITIONS:
		var row:Variant=_DEFINITIONS[definition_id]
		var keys:Array=row.keys();keys.sort()
		if keys!=["coverage","electric_reduction_milli","fire_reduction_milli",
				"material_id","wet_electric_retention_milli"] \
				or not row.material_id is String or not Materials.has(str(row.material_id)) \
				or not row.coverage is Array or row.coverage.is_empty():
			return "invalid_environment_armor_definition"
		var seen:Dictionary={}
		for part_id in row.coverage:
			if part_id not in BodyRegistry.PART_IDS or seen.has(part_id):
				return "invalid_environment_armor_coverage"
			seen[part_id]=true
		for key in ["fire_reduction_milli","electric_reduction_milli",
				"wet_electric_retention_milli"]:
			if not row[key] is int or int(row[key])<0 or int(row[key])>1000:
				return "invalid_environment_armor_coefficient"
	return ""


static func assess(world,entity_id:int,damage_type:String,raw_damage:int,
		part_id:String,wetness:int)->Dictionary:
	var rejected:={"accepted":false,"reason":"invalid_environment_armor_input"}
	if world==null or not world.entities.has(entity_id) \
			or damage_type not in ["fire","electric"] or raw_damage<=0 \
			or raw_damage>100000 or part_id not in BodyRegistry.PART_IDS \
			or wetness<0 or wetness>100 or not registry_error().is_empty():
		return rejected.duplicate(true)
	var inventory=world.item_state.inventory(entity_id) if world.item_state!=null else null
	if inventory==null:return rejected.duplicate(true)
	var best_reduction:=0;var source_id:="";var material_id:=""
	for slot in ["ARMOR","OFF_HAND"]:
		var item=inventory.equipped_item(slot)
		if item==null:continue
		var row:Dictionary=definition(str(item.definition_id))
		if row.is_empty() or part_id not in row.coverage:continue
		var reduction:=int(row.fire_reduction_milli) if damage_type=="fire" \
			else int(row.electric_reduction_milli)
		if damage_type=="electric" and wetness>0:
			var retention:=1000-(1000-int(row.wet_electric_retention_milli))*wetness/100
			reduction=reduction*retention/1000
		if reduction>best_reduction:
			best_reduction=reduction;source_id=str(item.definition_id)
			material_id=str(row.material_id)
	var final_damage:=maxi(1,raw_damage*(1000-best_reduction)/1000)
	return {"accepted":true,"reason":"","part_id":part_id,
		"raw_damage":raw_damage,"final_damage":final_damage,
		"reduction_milli":best_reduction,"armor_definition_id":source_id,
		"material_id":material_id,"wetness":wetness}.duplicate(true)
