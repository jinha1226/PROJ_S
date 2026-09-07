class_name FixedFrontTopdownAssets
extends RefCounted

## Fixed-front paper-doll registry for the product's flat top-down camera.
## Visible bases use the approved native 24x24 transparent pixel canvas and common anchor.
## Direction is deliberately ignored: movement and combat never swap or mirror
## these assets.

const SOURCE_CANVAS_SIZE := Vector2(24.0, 24.0)
const FOOT_ANCHOR_RATIO := 0.94
# Keep the first full-body readability pass honest: equipment remains registered
# but is not composited until its silhouettes are authored against these bodies.
const EQUIPMENT_LAYERS_ENABLED := false

const BODY_TEXTURES := {
	"human": preload("res://assets/topdown_fixed_front/actors/base/human.png"),
	"elf": preload("res://assets/topdown_fixed_front/actors/base/elf.png"),
	"dwarf": preload("res://assets/topdown_fixed_front/actors/base/dwarf.png"),
	"orc": preload("res://assets/topdown_fixed_front/actors/base/orc.png"),
	"beastkin": preload("res://assets/topdown_fixed_front/actors/base/beastkin.png"),
}

const MONSTER_TEXTURES := {
	"goblin": preload("res://assets/topdown_fixed_front/monsters/goblin.png"),
	"kobold": preload("res://assets/topdown_fixed_front/monsters/kobold.png"),
}

# The texture rectangle is centered on the logical cell, but a few authored
# silhouettes are not centered inside their transparent 24x24 canvas. These
# source-pixel offsets center the visible body mass without changing occupancy,
# hit testing, pathfinding, or the shared foot anchor.
const VISUAL_CENTER_OFFSETS_SOURCE_PX := {
	"human": Vector2(-1.5, 0.0),
	"elf": Vector2(-0.5, 0.0),
	"dwarf": Vector2.ZERO,
	"orc": Vector2(0.5, 0.0),
	"beastkin": Vector2(0.5, 0.0),
	"goblin": Vector2(-1.0, 0.0),
	"kobold": Vector2(-0.5, 0.0),
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


static func monster_texture(species_id:String)->Texture2D:
	return MONSTER_TEXTURES.get(species_id.to_lower(),null)


static func armor_texture(definition_id:String)->Texture2D:
	return ARMOR_TEXTURES.get(definition_id.to_upper(),null)


static func weapon_texture(definition_id:String)->Texture2D:
	return WEAPON_TEXTURES.get(definition_id.to_upper(),null)


static func actor_layer_spec(actor:Dictionary)->Dictionary:
	var equipment_value:Variant=actor.get("equipment_visual",actor.get("equipment",{}))
	var equipment:Dictionary=equipment_value if equipment_value is Dictionary else {}
	var species_id:=str(actor.get("species_id","")).to_lower()
	# Goblin/kobold currently share one neutral fixed-front base across factions.
	# Faction tint and combat markers remain presentation state; a recruited NPC
	# must not fall back to an ASCII portrait merely because its base lives in the
	# monster atlas directory.
	var uses_monster_sprite:=not BODY_TEXTURES.has(species_id) \
		and MONSTER_TEXTURES.has(species_id)
	var base_texture:Texture2D=monster_texture(species_id) if uses_monster_sprite \
		else body_texture(species_id)
	var armor_definition_id:=str(equipment.get("armor_definition_id",
		actor.get("armor_definition_id",""))).to_upper()
	var weapon_definition_id:=str(equipment.get("weapon_definition_id",
		actor.get("weapon_definition_id",""))).to_upper()
	if weapon_definition_id.is_empty():
		var weapon_id:=str(equipment.get("weapon_id",actor.get("weapon_id",""))).to_upper()
		if not weapon_id.is_empty() and weapon_id!="UNARMED_STRIKE":
			weapon_definition_id="WEAPON_%s"%weapon_id
	return {
		"uses_sprite":base_texture!=null,
		"species_id":species_id,
		"body_texture":base_texture,
		"monster_sprite":uses_monster_sprite,
		"visual_cell_ratio":1.30 if uses_monster_sprite else 1.50,
		"armor_definition_id":armor_definition_id,
		"armor_texture":armor_texture(armor_definition_id) if EQUIPMENT_LAYERS_ENABLED else null,
		"weapon_definition_id":weapon_definition_id,
		"weapon_texture":weapon_texture(weapon_definition_id) if EQUIPMENT_LAYERS_ENABLED else null,
		"equipment_layers_enabled":EQUIPMENT_LAYERS_ENABLED,
		"fixed_front":true,
		"source_canvas_size":SOURCE_CANVAS_SIZE,
		"visual_center_offset_source_px":VISUAL_CENTER_OFFSETS_SOURCE_PX.get(
			species_id,Vector2.ZERO),
		"foot_anchor_ratio":FOOT_ANCHOR_RATIO,
	}.duplicate(true)
