class_name ModularTopdownAssets
extends RefCounted

## Pure 2D paper-doll asset registry. Simulation coordinates never enter here.
## Every character/equipment atlas uses the same fixed 2x2 order:
## SOUTH | NORTH
## WEST  | EAST

const ATLAS_CELL_SIZE := 512.0

const BODY_ATLASES := {
	"human": preload("res://assets/generated/modular_topdown_v1/runtime/body/human_body_4dir_1024.png"),
	"elf": preload("res://assets/generated/modular_topdown_v1/runtime/body/elf_body_4dir_1024.png"),
	"dwarf": preload("res://assets/generated/modular_topdown_v1/runtime/body/dwarf_body_4dir_1024.png"),
	"orc": preload("res://assets/generated/modular_topdown_v1/runtime/body/orc_body_4dir_1024.png"),
	"beastkin": preload("res://assets/generated/modular_topdown_v1/runtime/body/beastkin_body_4dir_1024.png"),
	"goblin": preload("res://assets/generated/modular_topdown_v1/runtime/body/goblin_body_4dir_1024.png"),
}

const ITEM_ATLASES := {
	"ARMOR_LEATHER": preload("res://assets/generated/modular_topdown_v1/runtime/items/armor_leather_4dir_1024.png"),
	"ARMOR_PADDED": preload("res://assets/generated/modular_topdown_v1/runtime/items/armor_padded_4dir_1024.png"),
	"SHIELD_WOOD": preload("res://assets/generated/modular_topdown_v1/runtime/items/shield_wood_4dir_1024.png"),
	"WEAPON_SHORT_SWORD": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_short_sword_4dir_1024.png"),
	"WEAPON_THRUSTING_SWORD": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_thrusting_sword_4dir_1024.png"),
	"WEAPON_HAND_AXE": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_hand_axe_4dir_1024.png"),
	"WEAPON_MACE": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_mace_4dir_1024.png"),
	"WEAPON_SPEAR": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_spear_4dir_1024.png"),
	"WEAPON_BOW": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_bow_4dir_1024.png"),
	"WEAPON_CROSSBOW": preload("res://assets/generated/modular_topdown_v1/runtime/items/weapon_crossbow_4dir_1024.png"),
}

const TERRAIN_TEXTURES := {
	"floor_a": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/dirt.png"),
	"floor_b": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/dry_earth.png"),
	"stone_a": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/stone_a.png"),
	"stone_b": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/stone_b.png"),
	"wall": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/wall_cap_moss.png"),
	"water": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/shallow_water.png"),
	"wood": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/wood_floor.png"),
	"metal": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/iron_plate.png"),
	"rubble": preload("res://assets/generated/modular_topdown_v1/runtime/terrain/rubble.png"),
}

const FEATURE_TEXTURES := {
	"run_entry": preload("res://assets/generated/modular_topdown_v1/runtime/props/campfire.png"),
	"run_exit_locked": preload("res://assets/generated/modular_topdown_v1/runtime/props/chest_closed.png"),
	"run_exit_open": preload("res://assets/generated/modular_topdown_v1/runtime/props/exit_stairs.png"),
	"door_closed": preload("res://assets/generated/modular_topdown_v1/runtime/props/door_closed.png"),
	"door_open": preload("res://assets/generated/modular_topdown_v1/runtime/props/door_open.png"),
	"shrine": preload("res://assets/generated/modular_topdown_v1/runtime/props/shrine.png"),
}

const BLOOD_TEXTURE := preload("res://assets/generated/modular_topdown_v1/runtime/props/blood_pool.png")
const CAMPFIRE_TEXTURE := preload("res://assets/generated/modular_topdown_v1/runtime/props/campfire.png")
const SPIKES_TEXTURE := preload("res://assets/generated/modular_topdown_v1/runtime/terrain/spikes.png")

const UI_TEXTURES := {
	"attack": preload("res://assets/generated/modular_topdown_v1/runtime/ui/attack.png"),
	"auto_explore": preload("res://assets/generated/modular_topdown_v1/runtime/ui/auto_explore.png"),
	"guard": preload("res://assets/generated/modular_topdown_v1/runtime/ui/guard.png"),
	"interact": preload("res://assets/generated/modular_topdown_v1/runtime/ui/interact.png"),
	"inventory": preload("res://assets/generated/modular_topdown_v1/runtime/ui/inventory.png"),
	"journal": preload("res://assets/generated/modular_topdown_v1/runtime/ui/journal.png"),
	"map": preload("res://assets/generated/modular_topdown_v1/runtime/ui/map.png"),
	"person": preload("res://assets/generated/modular_topdown_v1/runtime/ui/person.png"),
	"pickup": preload("res://assets/generated/modular_topdown_v1/runtime/ui/pickup.png"),
	"skill": preload("res://assets/generated/modular_topdown_v1/runtime/ui/skill.png"),
	"wait": preload("res://assets/generated/modular_topdown_v1/runtime/ui/wait.png"),
	"zoom": preload("res://assets/generated/modular_topdown_v1/runtime/ui/zoom.png"),
}

static func direction_id(actor: Dictionary) -> String:
	var raw: Variant = actor.get("facing", [0, 1])
	if not raw is Array or raw.size() != 2:
		return "south"
	var facing := Vector2(float(raw[0]), float(raw[1]))
	if absf(facing.x) > absf(facing.y):
		return "east" if facing.x >= 0.0 else "west"
	return "south" if facing.y >= 0.0 else "north"

static func direction_region(direction: String) -> Rect2:
	match direction.to_lower():
		"north": return Rect2(ATLAS_CELL_SIZE, 0.0, ATLAS_CELL_SIZE, ATLAS_CELL_SIZE)
		"west": return Rect2(0.0, ATLAS_CELL_SIZE, ATLAS_CELL_SIZE, ATLAS_CELL_SIZE)
		"east": return Rect2(ATLAS_CELL_SIZE, ATLAS_CELL_SIZE, ATLAS_CELL_SIZE, ATLAS_CELL_SIZE)
		_: return Rect2(0.0, 0.0, ATLAS_CELL_SIZE, ATLAS_CELL_SIZE)

static func body_texture(species_id: String) -> Texture2D:
	var normalized := species_id.to_lower()
	if normalized == "generic_humanoid":
		normalized = "human"
	return BODY_ATLASES.get(normalized, BODY_ATLASES["human"])

static func item_texture(definition_id: String) -> Texture2D:
	return ITEM_ATLASES.get(definition_id.to_upper(), null)

static func terrain_texture(terrain_id: String, position: Vector2i) -> Texture2D:
	var broad_variation := (floori(float(position.x) / 3.0) + floori(float(position.y) / 3.0)) & 1
	match terrain_id.to_lower():
		"wall": return TERRAIN_TEXTURES["wall"]
		"stone_floor": return TERRAIN_TEXTURES["stone_a"] if ((position.x + position.y) & 1) == 0 else TERRAIN_TEXTURES["stone_b"]
		"shallow_water": return TERRAIN_TEXTURES["water"]
		"wood_floor": return TERRAIN_TEXTURES["wood"]
		"metal": return TERRAIN_TEXTURES["metal"]
		"rubble": return TERRAIN_TEXTURES["rubble"]
		_: return TERRAIN_TEXTURES["floor_a"] if broad_variation == 0 else TERRAIN_TEXTURES["floor_b"]

static func feature_texture(feature_id: String) -> Texture2D:
	return FEATURE_TEXTURES.get(feature_id.to_lower(), null)

static func ui_texture(icon_id: String) -> Texture2D:
	return UI_TEXTURES.get(icon_id.to_lower(), null)

static func atlas_texture(texture: Texture2D, direction: String) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = texture
	result.region = direction_region(direction)
	return result
