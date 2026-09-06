class_name FixedFrontTopdownAssets
extends RefCounted

## Fixed-front paper-doll registry for the product's flat top-down camera.
## Every layer owns the same 96x96 transparent canvas and anchor. Direction is
## deliberately ignored: movement and combat never swap or mirror these assets.

const SOURCE_CANVAS_SIZE := Vector2(96.0, 96.0)
const FOOT_ANCHOR_RATIO := 0.94

const BODY_TEXTURES := {
	"human": preload("res://assets/topdown_fixed_front/actors/base/human.png"),
	"elf": preload("res://assets/topdown_fixed_front/actors/base/elf.png"),
	"dwarf": preload("res://assets/topdown_fixed_front/actors/base/dwarf.png"),
	"orc": preload("res://assets/topdown_fixed_front/actors/base/orc.png"),
	"beastkin": preload("res://assets/topdown_fixed_front/actors/base/beastkin.png"),
}

const ARMOR_TEXTURES := {
	"ARMOR_PADDED": preload("res://assets/topdown_fixed_front/equipment/armor/cloth.png"),
	"ARMOR_CLOTH": preload("res://assets/topdown_fixed_front/equipment/armor/cloth.png"),
	"ARMOR_LEATHER": preload("res://assets/topdown_fixed_front/equipment/armor/leather.png"),
	"ARMOR_STEEL": preload("res://assets/topdown_fixed_front/equipment/armor/steel.png"),
	"ARMOR_MITHRIL": preload("res://assets/topdown_fixed_front/equipment/armor/mythril.png"),
	"ARMOR_MYTHRIL": preload("res://assets/topdown_fixed_front/equipment/armor/mythril.png"),
	"ARMOR_HOOD": preload("res://assets/topdown_fixed_front/equipment/armor/hood.png"),
	"ARMOR_HELMET": preload("res://assets/topdown_fixed_front/equipment/armor/helmet.png"),
}

const WEAPON_TEXTURES := {
	"WEAPON_SHORT_SWORD": preload("res://assets/topdown_fixed_front/equipment/weapons/short_sword.png"),
	# The first sheet has one sword silhouette. Keep the alternate definition on
	# that honest fallback until it receives its own authored layer.
	"WEAPON_THRUSTING_SWORD": preload("res://assets/topdown_fixed_front/equipment/weapons/short_sword.png"),
	"WEAPON_HAND_AXE": preload("res://assets/topdown_fixed_front/equipment/weapons/hand_axe.png"),
	"WEAPON_MACE": preload("res://assets/topdown_fixed_front/equipment/weapons/mace.png"),
	"WEAPON_SPEAR": preload("res://assets/topdown_fixed_front/equipment/weapons/spear.png"),
	"WEAPON_BOW": preload("res://assets/topdown_fixed_front/equipment/weapons/bow.png"),
	"WEAPON_CROSSBOW": preload("res://assets/topdown_fixed_front/equipment/weapons/crossbow.png"),
}


static func body_texture(species_id:String)->Texture2D:
	return BODY_TEXTURES.get(species_id.to_lower(),null)


static func armor_texture(definition_id:String)->Texture2D:
	return ARMOR_TEXTURES.get(definition_id.to_upper(),null)


static func weapon_texture(definition_id:String)->Texture2D:
	return WEAPON_TEXTURES.get(definition_id.to_upper(),null)


static func actor_layer_spec(actor:Dictionary)->Dictionary:
	var equipment_value:Variant=actor.get("equipment_visual",actor.get("equipment",{}))
	var equipment:Dictionary=equipment_value if equipment_value is Dictionary else {}
	var species_id:=str(actor.get("species_id","")).to_lower()
	var armor_definition_id:=str(equipment.get("armor_definition_id",
		actor.get("armor_definition_id",""))).to_upper()
	var weapon_definition_id:=str(equipment.get("weapon_definition_id",
		actor.get("weapon_definition_id",""))).to_upper()
	if weapon_definition_id.is_empty():
		var weapon_id:=str(equipment.get("weapon_id",actor.get("weapon_id",""))).to_upper()
		if not weapon_id.is_empty() and weapon_id!="UNARMED_STRIKE":
			weapon_definition_id="WEAPON_%s"%weapon_id
	return {
		"uses_sprite":BODY_TEXTURES.has(species_id),
		"species_id":species_id,
		"body_texture":body_texture(species_id),
		"armor_definition_id":armor_definition_id,
		"armor_texture":armor_texture(armor_definition_id),
		"weapon_definition_id":weapon_definition_id,
		"weapon_texture":weapon_texture(weapon_definition_id),
		"fixed_front":true,
		"source_canvas_size":SOURCE_CANVAS_SIZE,
		"foot_anchor_ratio":FOOT_ANCHOR_RATIO,
	}.duplicate(true)
