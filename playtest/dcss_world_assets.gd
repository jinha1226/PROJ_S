extends RefCounted
## CC0 export sprites. Appearance only; no simulation or FOV reads.
const PATH:="res://assets/dcss-cc0/world/"
const BODIES:={"human":"mon__human.png","elf":"mon__elf.png","dwarf":"mon__deep_dwarf.png","orc":"mon__orc_warrior.png","beastkin":"mon__gnoll.png","goblin":"mon__goblin.png","kobold":"mon__kobold.png","dcss_gnoll":"mon__gnoll.png","dcss_hobgoblin":"mon__hobgoblin.png","dcss_orc":"mon__orc.png","dcss_frilled_lizard":"mon__animals__giant_newt.png","dcss_rat":"mon__undead__zombies__zombie_rat.png","dcss_river_rat":"mon__undead__zombies__zombie_rat.png","slime":"mon__amorphous__jelly.png","beetle":"mon__animals__boulder_beetle.png","wolf":"mon__animals__wolf.png","boar":"mon__animals__hog.png","bat":"mon__animals__bat.png","fire_lizard":"mon__animals__iguana.png","frost_spider":"mon__animals__spider.png","electric_eel":"mon__aquatic__electric_eel.png","viper":"mon__animals__adder.png","troll":"mon__deep_troll.png","stone_golem":"mon__nonliving__iron_golem.png","shadow_beast":"mon__animals__hell_hound.png","leech":"mon__animals__giant_leech.png","aberration":"mon__animals__brain_worm.png"}
const TERRAIN:={"floor":["dngn__floor__grey_dirt0.png","dngn__floor__grey_dirt1.png"],"stone_floor":["dngn__floor__limestone0.png","dngn__floor__limestone1.png","dngn__floor__limestone2.png"],"wall":["dngn__wall__brick_gray0.png","dngn__wall__brick_gray1.png"],"rubble":["dngn__floor__grey_dirt2.png"],"shallow_water":["dngn__water__shallow_water2.png"],"wood_floor":["dngn__floor__sandstone_floor0.png"],"metal":["dngn__floor__limestone3.png"]}
static var cache:Dictionary={}
static func texture(key:String)->Texture2D:
	if not cache.has(key):cache[key]=load(PATH+key)
	return cache[key]
static func body_texture(species:String)->Texture2D:
	return texture(BODIES.get(species.to_lower(),BODIES.human))
static func item(id:String)->Texture2D:
	return preload("res://playtest/dcss_item_assets.gd").texture_for_id(id)
static func actor_spec(actor:Dictionary)->Dictionary:
	var species:=str(actor.get("species_id","human")).to_lower()
	var body:=body_texture(species)
	return {"uses_sprite":true,"asset_family":"DCSS_CC0","species_id":species,
		"body_key":BODIES.get(species,BODIES.human),"body_texture":body,"monster_sprite":species not in ["human","elf","dwarf","orc","beastkin"],
		"supports_walk":false,"visual_cell_ratio":1.0,"source_canvas_size":Vector2(32,32),"foot_anchor_ratio":1.0,"visual_center_offset_source_px":Vector2.ZERO,
		"armor_texture":null,"foreground_texture":null,"weapon_texture":null,"offhand_texture":null,
		"equipment_fit_supported":false,"equipment_layers_enabled":false,"equipment_fit_fallback_base_only":true,
		"fixed_front":true,"direction_index":0,"layer_order":["body"]}
static func tile_spec(cell:Dictionary,position:Vector2i,depth:int)->Dictionary:
	var visibility:=str(cell.get("visibility_state","UNSEEN"))
	if visibility=="UNSEEN":return {"visible":false,"texture":null,"draw_image":false,"visibility_state":visibility,"changes_mapping":false,"changes_fov":false}
	var terrain:=str(cell.get("terrain_id","floor"))
	var choices:Array=TERRAIN.get(terrain,TERRAIN.floor)
	var index:=posmod(position.x*73856093 ^ position.y*19349663 ^ depth*83492791,choices.size())
	var key:String=choices[index];var image:=texture(key)
	return {"visible":true,"texture":image,"region":Rect2(Vector2.ZERO,image.get_size()),"is_wall":terrain=="wall","asset_family":"DCSS_CC0","sprite_key":key,"floor_index":depth,"tile_index":index,"tint":Color.WHITE,"visibility_state":visibility,"changes_mapping":false,"changes_fov":false,"draw_image":true}
