extends RefCounted
## 0x72 DungeonTileset II v1.7 (CC0), original images, named cached regions.
const ATLAS=preload("res://assets/0x72/dungeon-ii/atlas.png")
const EXTENDED=preload("res://assets/0x72/dungeon-ii/extended.png")
const EXTRA={"flame":Rect2(128,336,16,16),"torch_wall":Rect2(128,352,16,32),
	"torch_floor":Rect2(128,400,16,32),"bag":Rect2(288,304,16,16),
	"door_closed":Rect2(144,256,16,32),"door_open":Rect2(144,288,16,32),"plants":Rect2(16,112,16,16)}
const RECTS=preload("res://playtest/dungeon_0x72_regions.gd").RECTS
const BODIES={"human":"knight_m_idle_anim_f0","elf":"elf_m_idle_anim_f0",
	"dwarf":"dwarf_m_idle_anim_f0","orc":"orc_warrior_idle_anim_f0",
	"beastkin":"lizard_m_idle_anim_f0","goblin":"goblin_idle_anim_f0",
	"kobold":"imp_idle_anim_f0","slime":"swampy_anim_f0","beetle":"tiny_slug_anim_f0"}
const ITEMS={"WEAPON_SHORT_SWORD":"weapon_regular_sword","WEAPON_THRUSTING_SWORD":"weapon_duel_sword",
	"WEAPON_HAND_AXE":"weapon_axe","WEAPON_MACE":"weapon_mace","WEAPON_SPEAR":"weapon_spear",
	"WEAPON_BOW":"weapon_bow","WEAPON_CROSSBOW":"weapon_bow_2",
	"ARMOR_PADDED":"knight_m_idle_anim_f0","ARMOR_LEATHER":"knight_f_idle_anim_f0",
	"TORCH":"torch_wall","POTION_HEALING":"flask_red","POTION_UNSPECIFIED":"flask_blue",
	"FOOD_RATION":"flask_big_green","SCROLL_UNSPECIFIED":"wall_banner_yellow",
	"ACCESSORY_BRASS_CHARM":"coin_anim_f0","GOBLIN_EAR":"skull","MATERIAL_UNSPECIFIED":"skull",
	"MAGIC_STONE":"flask_blue","ACCESSORY_UNSPECIFIED":"coin_anim_f0",
	"TIMBER":"crate","STONE":"floor_4","HERBS":"plants","DROPPED_ITEM":"bag",
	"LOOT_SACK":"bag","TOWN_GOLD":"coin_anim_f0"}
static var regions:Dictionary={}
static func texture(key:String)->Texture2D:
	if not RECTS.has(key) and not EXTRA.has(key):return null
	if not regions.has(key):
		var result:=AtlasTexture.new();result.atlas=EXTENDED if EXTRA.has(key) else ATLAS
		result.region=EXTRA[key] if EXTRA.has(key) else RECTS[key]
		result.filter_clip=true;regions[key]=result
	return regions[key]
static func item(id:String)->Texture2D:
	var key:=id.to_upper()
	if key.begins_with("ESSENCE_"):return texture("flask_big_blue")
	return texture(str(ITEMS[key])) if ITEMS.has(key) else null
static func actor_spec(actor:Dictionary)->Dictionary:
	var species:=str(actor.get("species_id","human")).to_lower()
	var equipment:Dictionary=actor.get("equipment_visual",actor.get("equipment",{}))
	var weapon:=str(equipment.get("weapon_definition_id",actor.get("weapon_definition_id",""))).to_upper()
	if weapon.is_empty():
		var id:=str(equipment.get("weapon_id",actor.get("weapon_id",""))).to_upper()
		if not id.is_empty() and id!="UNARMED_STRIKE":weapon="WEAPON_"+id
	var offhand:=str(equipment.get("off_hand_definition_id",actor.get("off_hand_definition_id",""))).to_upper()
	var body_key:String=BODIES.get(species,"knight_m_idle_anim_f0")
	if species=="human" and str(actor.get("role",""))!="PROTAGONIST":
		var variants:=["knight_f","knight_m","wizzard_f","wizzard_m"]
		body_key=str(variants[posmod(int(actor.get("entity_id",0)),variants.size())])+"_idle_anim_f0"
	var body:=texture(body_key)
	var facing:Variant=actor.get("facing",[0,1])
	var flip:bool=int(facing[0])<0 if facing is Array else facing.x<0
	return {"uses_sprite":true,"asset_family":"0X72_DUNGEON_II","species_id":species,
		"body_key":body_key,"body_texture":body,"monster_sprite":species in ["goblin","kobold","slime","beetle"],
		"supports_walk":RECTS.has(body_key.replace("_idle_","_run_")) and "_idle_" in body_key,
		"visual_cell_ratio":1.50 if body.get_height()>20 else 1.05,"source_canvas_size":body.get_size(),
		"foot_anchor_ratio":1.0,"visual_center_offset_source_px":Vector2.ZERO,"flip_h":flip,
		"armor_texture":null,"foreground_texture":null,"weapon_texture":item(weapon),
		"offhand_texture":item(offhand),"weapon_definition_id":weapon,"off_hand_definition_id":offhand,
		"armor_definition_id":str(equipment.get("armor_definition_id","")),
		"equipment_fit_supported":true,"equipment_layers_enabled":true,"equipment_fit_fallback_base_only":false,
		"fixed_front":true,"direction_index":0,"layer_order":["body","offhand","weapon"]}
static func fit(part:Texture2D,box:Rect2)->Rect2:
	var scale_factor:=minf(box.size.x/part.get_width(),box.size.y/part.get_height())
	var extent:=part.get_size()*scale_factor
	return Rect2(box.get_center()-extent/2,extent)
static func draw_actor(canvas:CanvasItem,spec:Dictionary,bounds:Rect2,tint:Color=Color.WHITE)->void:
	var body:Texture2D=spec.body_texture
	if bool(spec.get("walk_active",false)):
		var frame:=int(Time.get_ticks_msec()/90)%4
		var key:=str(spec.body_key).replace("_idle_anim_f0","_run_anim_f%d"%frame)
		var animated:=texture(key)
		if animated!=null:body=animated
	var body_rect:=fit(body,bounds)
	body_rect.position.y=bounds.end.y-body_rect.size.y
	if bool(spec.get("flip_h",false)):
		body_rect.position.x+=body_rect.size.x;body_rect.size.x=-body_rect.size.x
	canvas.draw_texture_rect(body,body_rect,false,tint)
	if str(spec.get("off_hand_definition_id",""))=="SHIELD_WOOD":
		draw_shield(canvas,Rect2(bounds.position+bounds.size*Vector2(0.15,0.57),bounds.size*Vector2(0.23,0.25)),tint)
	for entry in [["offhand_texture",Vector2(-0.01,0.46),Vector2(0.37,0.35)],
			["weapon_texture",Vector2(0.59,0.35),Vector2(0.35,0.65)]]:
		var part:Texture2D=spec.get(entry[0])
		if part!=null:canvas.draw_texture_rect(part,fit(part,Rect2(bounds.position+bounds.size*entry[1],bounds.size*entry[2])),false,tint)
static func draw_shield(canvas:CanvasItem,rect:Rect2,tint:Color=Color.WHITE)->void:
	# Neither pack includes shields: retain an explicit neutral equipment symbol.
	var points:=PackedVector2Array()
	for p in [Vector2(0,0),Vector2(1,0),Vector2(1,0.65),Vector2(0.5,1),Vector2(0,0.65)]:points.append(rect.position+p*rect.size)
	canvas.draw_colored_polygon(points,Color("#8f563b")*tint)
	canvas.draw_line(rect.position+rect.size*Vector2(0.5,0.12),rect.position+rect.size*Vector2(0.5,0.75),Color("#c6b7a2")*tint,maxf(1,rect.size.x*0.17))
