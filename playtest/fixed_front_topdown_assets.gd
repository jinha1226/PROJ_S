class_name FixedFrontTopdownAssets
extends RefCounted

## Fixed-front paper-doll registry for the product's flat top-down camera.
## Visible bases use a native 24x24 transparent pixel canvas and common anchor.
## Direction is deliberately ignored: movement and combat never swap or mirror
## these assets.

const SOURCE_CANVAS_SIZE := Vector2(24.0, 24.0)
const FOOT_ANCHOR_RATIO := 0.94
const EQUIPMENT_LAYERS_ENABLED := true
const BIPED_WALK_SPECIES := ["human","elf","dwarf","orc","beastkin","goblin","kobold"]
const FITTED_EQUIPMENT_SPECIES := ["human","elf","dwarf","orc","beastkin"]

const BODY_TEXTURES := {
	"human": preload("res://assets/pixel24_v3/runtime/actors/base/human.png"),
	"elf": preload("res://assets/pixel24_v3/runtime/actors/base/elf.png"),
	"dwarf": preload("res://assets/pixel24_v3/runtime/actors/base/dwarf.png"),
	"orc": preload("res://assets/pixel24_v3/runtime/actors/base/orc.png"),
	"beastkin": preload("res://assets/pixel24_v3/runtime/actors/base/beastkin.png"),
}

const MONSTER_TEXTURES := {
	"goblin": preload("res://assets/pixel24_v3/runtime/monsters/goblin.png"),
	"kobold": preload("res://assets/pixel24_v3/runtime/monsters/kobold.png"),
	"slime": preload("res://assets/pixel24_v3/runtime/monsters/slime.png"),
	"beetle": preload("res://assets/pixel24_v3/runtime/monsters/beetle.png"),
}

const ARMOR_TEXTURES := {
	"ARMOR_PADDED": {
		"human":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/padded_human.png"),"elf":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/padded_elf.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/padded_dwarf.png"),"orc":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/padded_orc.png"),"beastkin":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/padded_beastkin.png")},
	"ARMOR_LEATHER": {
		"human":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/leather_human.png"),"elf":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/leather_elf.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/leather_dwarf.png"),"orc":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/leather_orc.png"),"beastkin":preload("res://assets/pixel24_v3/fit_v2/equipment/armor/leather_beastkin.png")},
}

const WEAPON_TEXTURES := {
	"WEAPON_SHORT_SWORD":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/short_sword.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_short_sword.png")},
	"WEAPON_THRUSTING_SWORD":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/thrusting_sword.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_thrusting_sword.png")},
	"WEAPON_HAND_AXE":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/hand_axe.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_hand_axe.png")},
	"WEAPON_MACE":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/mace.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_mace.png")},
	"WEAPON_SPEAR":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/spear.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_spear.png")},
	"WEAPON_BOW":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/bow.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_bow.png")},
	"WEAPON_CROSSBOW":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/crossbow.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/weapons/dwarf_crossbow.png")},
}

const OFFHAND_TEXTURES := {
	"SHIELD_WOOD":{"standard":preload("res://assets/pixel24_v3/fit_v2/equipment/offhand/shield_wood.png"),"dwarf":preload("res://assets/pixel24_v3/fit_v2/equipment/offhand/dwarf_shield_wood.png")},
}

const FOREGROUND_TEXTURES := {
	"human":preload("res://assets/pixel24_v3/fit_v2/foreground/human.png"),
	"elf":preload("res://assets/pixel24_v3/fit_v2/foreground/elf.png"),
	"dwarf":preload("res://assets/pixel24_v3/fit_v2/foreground/dwarf.png"),
	"orc":preload("res://assets/pixel24_v3/fit_v2/foreground/orc.png"),
	"beastkin":preload("res://assets/pixel24_v3/fit_v2/foreground/beastkin.png"),
}


static func body_texture(species_id:String)->Texture2D:
	return BODY_TEXTURES.get(species_id.to_lower(),null)


static func monster_texture(species_id:String)->Texture2D:
	return MONSTER_TEXTURES.get(species_id.to_lower(),null)


static func armor_texture(definition_id:String,species_id:String="human")->Texture2D:
	var variants:Variant=ARMOR_TEXTURES.get(definition_id.to_upper(),{})
	return variants.get(species_id.to_lower(),null) \
		if variants is Dictionary else null


static func weapon_texture(definition_id:String,species_id:String="human")->Texture2D:
	if species_id.to_lower() not in FITTED_EQUIPMENT_SPECIES:return null
	var variants:Variant=WEAPON_TEXTURES.get(definition_id.to_upper(),{})
	if not variants is Dictionary:return null
	return variants.get("dwarf" if species_id.to_lower()=="dwarf" else "standard",null)


static func offhand_texture(definition_id:String,species_id:String="human")->Texture2D:
	if species_id.to_lower() not in FITTED_EQUIPMENT_SPECIES:return null
	var variants:Variant=OFFHAND_TEXTURES.get(definition_id.to_upper(),{})
	if not variants is Dictionary:return null
	return variants.get("dwarf" if species_id.to_lower()=="dwarf" else "standard",null)


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
	var off_hand_definition_id:=str(equipment.get("off_hand_definition_id",
		actor.get("off_hand_definition_id",""))).to_upper()
	var fitted_species:=species_id in FITTED_EQUIPMENT_SPECIES
	var fitted_armor:=armor_texture(armor_definition_id,species_id) \
		if EQUIPMENT_LAYERS_ENABLED and fitted_species else null
	var fitted_weapon:=weapon_texture(weapon_definition_id,species_id) \
		if EQUIPMENT_LAYERS_ENABLED and fitted_species else null
	var fitted_offhand:=offhand_texture(off_hand_definition_id,species_id) \
		if EQUIPMENT_LAYERS_ENABLED and fitted_species else null
	var has_fitted_equipment:=fitted_armor!=null or fitted_weapon!=null or fitted_offhand!=null
	return {
		"uses_sprite":base_texture!=null,
		"species_id":species_id,
		"body_texture":base_texture,
		"monster_sprite":uses_monster_sprite,
		"supports_walk":species_id in BIPED_WALK_SPECIES,
		"visual_cell_ratio":1.18 if uses_monster_sprite else 1.32,
		"armor_definition_id":armor_definition_id,
		"armor_texture":fitted_armor,
		"weapon_definition_id":weapon_definition_id,
		"weapon_texture":fitted_weapon,
		"off_hand_definition_id":off_hand_definition_id,
		"offhand_texture":fitted_offhand,
		"foreground_texture":FOREGROUND_TEXTURES.get(species_id,null) if has_fitted_equipment else null,
		"equipment_fit_supported":fitted_species,
		"equipment_fit_fallback_base_only":not fitted_species and (not armor_definition_id.is_empty() \
			or not weapon_definition_id.is_empty() or not off_hand_definition_id.is_empty()),
		"layer_order":["body","armor","offhand","weapon","foreground"],
		"equipment_layers_enabled":EQUIPMENT_LAYERS_ENABLED,
		"fixed_front":true,
		"source_canvas_size":SOURCE_CANVAS_SIZE,
		"visual_center_offset_source_px":Vector2.ZERO,
		"foot_anchor_ratio":FOOT_ANCHOR_RATIO,
	}.duplicate(true)
