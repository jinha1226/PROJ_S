class_name FixedFrontTopdownAssets
extends RefCounted
## Compatibility facade for product map, portraits and inventory.
## 0x72 is the active family; previous art remains in Git/assets, not loaded.
const PackAssets=preload("res://playtest/dungeon_0x72_assets.gd")
const SOURCE_CANVAS_SIZE:=Vector2(16,16)
const FOOT_ANCHOR_RATIO:=1.0
const EQUIPMENT_LAYERS_ENABLED:=true
const FITTED_EQUIPMENT_SPECIES:=["human","elf","dwarf","orc","beastkin"]
const BIPED_WALK_SPECIES:Array=[]
const FOREGROUND_TEXTURES:Dictionary={}
static func body_texture(species_id:String)->Texture2D:
	return PackAssets.texture(str(PackAssets.BODIES.get(species_id.to_lower(),"knight_m_idle_anim_f0")))
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
