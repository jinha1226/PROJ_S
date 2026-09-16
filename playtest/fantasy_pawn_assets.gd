extends RefCounted
## Approved fantasy pawn art; uncovered species/items keep their legacy assets.
const Legacy=preload("res://playtest/dungeon_0x72_assets.gd")
const FAMILY:="FANTASY_PAWNS_V1"
const ITEM_IDS={
	"WEAPON_SHORT_SWORD":"sword","WEAPON_THRUSTING_SWORD":"sword",
	"WEAPON_HAND_AXE":"axe","WEAPON_BOW":"bow","WEAPON_STAFF":"staff",
	"WEAPON_DCSS_STAFF":"staff","WEAPON_DCSS_QUARTERSTAFF":"staff",
	"ARMOR_LEATHER":"armor","SHIELD_WOOD":"shield","SHIELD_IRON":"shield",
	"POTION_HEALING":"potion","POTION_UNSPECIFIED":"potion",
	"FOOD_RATION":"ration","FOOD_DRIED_MEAT":"ration","SCROLL_UNSPECIFIED":"scroll",
	"ACCESSORY_UNSPECIFIED":"ring","TOWN_GOLD":"coins",
	"ESSENCE_FIRE_BOLT":"fire_gland","ESSENCE_FROST_SILK":"cold_gland",
	"ESSENCE_CHARGE_ORGAN":"electric_organ","PART_ARC_GLAND":"electric_organ",
	"PART_COLD_GLAND":"cold_gland","PART_WATER_SAC":"water_sac"}

static func body_texture(species_id:String)->Texture2D:
	var species:=species_id.to_lower()
	if species=="generic_humanoid":species="human"
	if BODIES.has(species):return BODIES[species]
	return Legacy.texture(str(Legacy.BODIES.get(species,"knight_m_idle_anim_f0")))

static func item(value:String)->Texture2D:
	var id:=value.strip_edges().to_upper()
	if ITEM_IDS.has(id):return ICONS[ITEM_IDS[id]]
	# Prefix suffixes encode weapon variants, not new weapon categories.
	for base in ["WEAPON_SHORT_SWORD","WEAPON_THRUSTING_SWORD","WEAPON_HAND_AXE","WEAPON_BOW","WEAPON_STAFF"]:
		if id.begins_with(base+"_"):return ICONS[ITEM_IDS[base]]
	if id.begins_with("SCROLL_") or id.begins_with("MYSTERY_SCROLL_"):return ICONS.scroll
	if id.begins_with("RING_") or id.begins_with("ACCESSORY_RING_"):return ICONS.ring
	if id.begins_with("HELMET_") or id.begins_with("ARMOR_HELMET_"):return ICONS.helmet
	return Legacy.item(value)

static func actor_spec(actor:Dictionary)->Dictionary:
	var spec:=Legacy.actor_spec(actor)
	var species:=str(actor.get("species_id","human")).to_lower()
	if species=="generic_humanoid":species="human"
	if not BODIES.has(species):return spec
	return spec.merged({"asset_family":FAMILY,"body_key":species,
		"body_texture":BODIES[species],"supports_walk":false,"visual_cell_ratio":1.0,
		"source_canvas_size":Vector2(128,128),"foot_anchor_ratio":0.94,
		"flip_h":false,"weapon_texture":item(str(spec.weapon_definition_id)),
		"offhand_texture":item(str(spec.off_hand_definition_id))},true)

static func draw_actor(canvas:CanvasItem,spec:Dictionary,bounds:Rect2,tint:Color=Color.WHITE)->void:
	if str(spec.get("asset_family",""))!=FAMILY:
		Legacy.draw_actor(canvas,spec,bounds,tint)
		return
	canvas.draw_texture_rect(spec.body_texture,bounds,false,tint)
	# Inventory icons are small attachments, never stretched across the whole pawn.
	for entry in [["offhand_texture",Vector2(0.06,0.55),Vector2(0.35,0.35)],
			["weapon_texture",Vector2(0.67,0.40),Vector2(0.30,0.53)]]:
		var part:Texture2D=spec.get(entry[0])
		if part!=null:
			canvas.draw_texture_rect(part,Legacy.fit(part,
				Rect2(bounds.position+bounds.size*entry[1],bounds.size*entry[2])),false,tint)
const BODIES={
	"beastkin":preload("res://assets/fantasy_pawns_v1/species/beastkin.png"),
	"dwarf":preload("res://assets/fantasy_pawns_v1/species/dwarf.png"),
	"elf":preload("res://assets/fantasy_pawns_v1/species/elf.png"),
	"goblin":preload("res://assets/fantasy_pawns_v1/species/goblin.png"),
	"human":preload("res://assets/fantasy_pawns_v1/species/human.png"),
	"orc":preload("res://assets/fantasy_pawns_v1/species/orc.png"),
}
const ICONS={
	"armor":preload("res://assets/fantasy_pawns_v1/items/armor.png"),
	"axe":preload("res://assets/fantasy_pawns_v1/items/axe.png"),
	"bow":preload("res://assets/fantasy_pawns_v1/items/bow.png"),
	"coins":preload("res://assets/fantasy_pawns_v1/items/coins.png"),
	"cold_gland":preload("res://assets/fantasy_pawns_v1/items/cold_gland.png"),
	"electric_organ":preload("res://assets/fantasy_pawns_v1/items/electric_organ.png"),
	"fire_gland":preload("res://assets/fantasy_pawns_v1/items/fire_gland.png"),
	"helmet":preload("res://assets/fantasy_pawns_v1/items/helmet.png"),
	"potion":preload("res://assets/fantasy_pawns_v1/items/potion.png"),
	"ration":preload("res://assets/fantasy_pawns_v1/items/ration.png"),
	"ring":preload("res://assets/fantasy_pawns_v1/items/ring.png"),
	"scroll":preload("res://assets/fantasy_pawns_v1/items/scroll.png"),
	"shield":preload("res://assets/fantasy_pawns_v1/items/shield.png"),
	"staff":preload("res://assets/fantasy_pawns_v1/items/staff.png"),
	"sword":preload("res://assets/fantasy_pawns_v1/items/sword.png"),
	"water_sac":preload("res://assets/fantasy_pawns_v1/items/water_sac.png"),
}
