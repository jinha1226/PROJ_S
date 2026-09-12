extends RefCounted
## Kenney Tiny Dungeon 1.0, CC0. Native 16px atlas, cached regions only.
const ATLAS=preload("res://assets/kenney/tiny-dungeon/tilemap_packed.png")
const BODIES={"human":88,"elf":85,"dwarf":100,"orc":111,"beastkin":110,
	"goblin":112,"kobold":110,"slime":108,"beetle":124}
const ITEMS={"WEAPON_SHORT_SWORD":104,"WEAPON_THRUSTING_SWORD":103,
	"WEAPON_HAND_AXE":119,"WEAPON_MACE":117,"WEAPON_SPEAR":125,
	"WEAPON_BOW":131,"WEAPON_CROSSBOW":131,"SHIELD_WOOD":101,
	"ARMOR_PADDED":97,"ARMOR_LEATHER":97,"TORCH":29,
	"POTION_HEALING":115,"POTION_UNSPECIFIED":113,"FOOD_RATION":123,
	"SCROLL_UNSPECIFIED":125,"ACCESSORY_BRASS_CHARM":102,"GOBLIN_EAR":112,
	"MATERIAL_UNSPECIFIED":12,"MAGIC_STONE":59,"ACCESSORY_UNSPECIFIED":59,
	"TIMBER":63,"STONE":0,"HERBS":108,"DROPPED_ITEM":89,"LOOT_SACK":90,
	"TOWN_GOLD":59}
static var regions:Dictionary={}
static func texture(index:int)->Texture2D:
	if not regions.has(index):
		var result:=AtlasTexture.new();result.atlas=ATLAS
		result.region=Rect2((index%12)*16,(index/12)*16,16,16)
		result.filter_clip=true;regions[index]=result
	return regions[index]
static func item(id:String)->Texture2D:
	var key:=id.to_upper()
	if key.begins_with("ESSENCE_"):return texture(116)
	return texture(int(ITEMS[key])) if ITEMS.has(key) else null
static func actor_spec(actor:Dictionary)->Dictionary:
	var species:=str(actor.get("species_id","human")).to_lower()
	var equipment:Dictionary=actor.get("equipment_visual",actor.get("equipment",{}))
	var weapon:=str(equipment.get("weapon_definition_id",actor.get("weapon_definition_id",""))).to_upper()
	if weapon.is_empty():
		var id:=str(equipment.get("weapon_id",actor.get("weapon_id",""))).to_upper()
		if not id.is_empty() and id!="UNARMED_STRIKE":weapon="WEAPON_"+id
	var offhand:=str(equipment.get("off_hand_definition_id",actor.get("off_hand_definition_id",""))).to_upper()
	var body_index:int=BODIES.get(species,88)
	if species=="human" and str(actor.get("role",""))!="PROTAGONIST":
		var variants:=[84,85,86,87,88,98,99,109]
		body_index=int(variants[posmod(int(actor.get("entity_id",0)),variants.size())])
	return {"uses_sprite":true,"asset_family":"KENNEY_TINY_DUNGEON","species_id":species,
		"body_texture":texture(body_index),"monster_sprite":species in ["goblin","kobold","slime","beetle"],
		"supports_walk":false,"visual_cell_ratio":1.15,"source_canvas_size":Vector2(16,16),
		"foot_anchor_ratio":1.0,"visual_center_offset_source_px":Vector2.ZERO,
		"armor_texture":null,"foreground_texture":null,"weapon_texture":item(weapon),
		"offhand_texture":item(offhand),"weapon_definition_id":weapon,"off_hand_definition_id":offhand,
		"armor_definition_id":str(equipment.get("armor_definition_id","")),
		"equipment_fit_supported":true,"equipment_layers_enabled":true,
		"equipment_fit_fallback_base_only":false,"fixed_front":true,"direction_index":0,
		"layer_order":["body","offhand","weapon"]}
static func draw_actor(canvas:CanvasItem,spec:Dictionary,bounds:Rect2,tint:Color=Color.WHITE)->void:
	canvas.draw_texture_rect(spec.body_texture,bounds,false,tint)
	# Separate pack icons, positioned at the hands; not fitted armor artwork.
	for entry in [["offhand_texture",Vector2(-0.16,0.37),0.61],["weapon_texture",Vector2(0.57,0.24),0.70]]:
		var part:Texture2D=spec.get(entry[0])
		if part!=null:canvas.draw_texture_rect(part,Rect2(bounds.position+bounds.size*entry[1],bounds.size*float(entry[2])),false,tint)
