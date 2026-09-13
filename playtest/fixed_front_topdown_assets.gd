class_name FixedFrontTopdownAssets
extends RefCounted
## Compatibility facade for product map, portraits and inventory.
## DCSS CC0 is the trial family; previous art remains preserved.
const PackAssets=preload("res://playtest/dcss_world_assets.gd")
const SOURCE_CANVAS_SIZE:=Vector2(32,32)
const FOOT_ANCHOR_RATIO:=1.0
const EQUIPMENT_LAYERS_ENABLED:=false
const FITTED_EQUIPMENT_SPECIES:=["human","elf","dwarf","orc","beastkin"]
const BIPED_WALK_SPECIES:Array=[]
const FOREGROUND_TEXTURES:Dictionary={}
static func body_texture(species_id:String)->Texture2D:
	return PackAssets.body_texture(species_id)
static func monster_texture(species_id:String)->Texture2D:
	return body_texture(species_id)
static func armor_texture(definition_id:String,_species_id:String="human")->Texture2D:
	return PackAssets.item(definition_id)
static func weapon_texture(definition_id:String,_species_id:String="human")->Texture2D:
	return PackAssets.item(definition_id)
static func offhand_texture(definition_id:String,_species_id:String="human")->Texture2D:
	return PackAssets.item(definition_id)
static func actor_layer_spec(actor:Dictionary)->Dictionary:
	return PackAssets.actor_spec(actor)
