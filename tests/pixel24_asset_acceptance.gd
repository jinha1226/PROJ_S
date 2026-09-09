extends SceneTree

const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
const Grid=preload("res://playtest/party_grid_view.gd")
const Portrait=preload("res://playtest/fixed_front_actor_portrait.gd")

var failures:Array[String]=[]


func _init()->void:call_deferred("run")


func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)


func run()->void:
	_check_registry_images()
	_check_layer_resolution_is_fixed_front_and_pure()
	_check_floor_mapping_is_distinct_and_pure()
	_check_two_phase_walk_is_motion_only()
	_check_export_keeps_sources_out_of_runtime()
	if failures.is_empty():print("PASS pixel24 asset acceptance")
	else:printerr("FAIL pixel24 asset acceptance: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_registry_images()->void:
	for species_id in ["human","elf","dwarf","orc","beastkin"]:
		var texture:Texture2D=Assets.body_texture(species_id)
		check(_is_binary_rgba_24(texture),"%s base is binary-alpha 24px"%species_id)
		if texture==null:continue
		var image:=texture.get_image();var min_x:=24;var max_x:=-1
		var left_foot:=0;var right_foot:=0
		for y in range(24):
			for x in range(24):
				if image.get_pixel(x,y).a<0.5:continue
				min_x=mini(min_x,x);max_x=maxi(max_x,x)
				if y>=20:
					if x<12:left_foot+=1
					else:right_foot+=1
		# Nearest reduction may make an odd-width silhouette one source pixel
		# asymmetric even though every layer shares the same canvas pivot.
		check(max_x>=min_x and absf(float(min_x+max_x)*0.5-11.5)<=1.5,
			"%s base uses common center pivot"%species_id)
		check(left_foot>0 and right_foot>0,"%s keeps two foot regions"%species_id)
		check(_is_binary_rgba_24(Assets.FOREGROUND_TEXTURES.get(species_id,null)),
			"%s fitted foreground is binary-alpha 24px"%species_id)
	for definition_id in ["WEAPON_SHORT_SWORD","WEAPON_THRUSTING_SWORD",
			"WEAPON_HAND_AXE","WEAPON_MACE","WEAPON_SPEAR","WEAPON_BOW",
			"WEAPON_CROSSBOW"]:
		check(_is_binary_rgba_24(Assets.weapon_texture(definition_id)),
			"%s resolves a binary-alpha 24px layer"%definition_id)
	for species_id in ["human","elf","dwarf","orc","beastkin"]:
		for definition_id in ["ARMOR_PADDED","ARMOR_LEATHER"]:
			check(_is_binary_rgba_24(Assets.armor_texture(definition_id,species_id)),
				"%s/%s resolves fitted 24px armor"%[species_id,definition_id])
	for monster_id in ["goblin","kobold","slime","beetle"]:
		check(_is_binary_rgba_24(Assets.monster_texture(monster_id)),
			"%s resolves a binary-alpha 24px monster"%monster_id)
	check(Tiles.FLOOR_TEXTURES[1].get_size()==Vector2(96,96) \
		and Tiles.FLOOR_TEXTURES[2].get_size()==Vector2(96,96),
		"both terrain atlases are 4x4 logical24")


func _check_layer_resolution_is_fixed_front_and_pure()->void:
	var empty_actor:={"species_id":"human","facing":[-1,0],"equipment_visual":{}}
	var snapshot:=empty_actor.duplicate(true)
	var empty:=Assets.actor_layer_spec(empty_actor)
	check(empty_actor==snapshot,"actor layer query does not mutate DTO")
	check(empty.armor_texture==null and empty.weapon_texture==null \
		and empty.get("offhand_texture",null)==null \
		and empty.get("foreground_texture",null)==null,"empty equipment renders base only")
	var equipped:={"species_id":"human","facing":[-1,0],"equipment_visual":{
		"armor_definition_id":"ARMOR_LEATHER",
		"weapon_definition_id":"WEAPON_CROSSBOW","off_hand_definition_id":"SHIELD_WOOD"}}
	var west:=Assets.actor_layer_spec(equipped)
	equipped.facing=[1,0]
	var east:=Assets.actor_layer_spec(equipped)
	check(west.body_texture==east.body_texture and west.armor_texture==east.armor_texture \
		and west.weapon_texture==east.weapon_texture,
		"facing never selects or mirrors fixed-front textures")
	check(west.armor_texture!=null and west.weapon_texture!=null,
		"known equipped IDs change visible layers")
	check(west.foreground_texture!=null \
		and west.layer_order==["body","armor","offhand","weapon","foreground"],
		"fitted equipment restores selective foreground last")
	check("/fit_v2/" in west.armor_texture.resource_path \
		and "/fit_v2/" in west.weapon_texture.resource_path \
		and "/fit_v2/" in west.offhand_texture.resource_path,
		"approved fit_v2 supplies all human equipment layers")
	var dwarf:=Assets.actor_layer_spec({"species_id":"dwarf","equipment_visual":{
		"weapon_definition_id":"WEAPON_HAND_AXE","off_hand_definition_id":"SHIELD_WOOD"}})
	check("dwarf_hand_axe.png" in dwarf.weapon_texture.resource_path \
		and "dwarf_shield_wood.png" in dwarf.offhand_texture.resource_path,
		"dwarf selects its measured grip variants")
	for species_id in ["goblin","kobold"]:
		var friendly:=Assets.actor_layer_spec({"species_id":species_id,"faction_id":"party",
			"equipment_visual":{"armor_definition_id":"ARMOR_LEATHER",
			"weapon_definition_id":"WEAPON_SHORT_SWORD"}})
		var hostile:=Assets.actor_layer_spec({"species_id":species_id,
			"faction_id":"enemy"})
		check(friendly.body_texture==hostile.body_texture and friendly.monster_sprite,
			"%s keeps species art across faction presentation"%species_id)
		check(friendly.armor_texture==null and friendly.weapon_texture==null \
			and friendly.foreground_texture==null and friendly.equipment_fit_fallback_base_only,
			"%s safely keeps base-only art when no fitted equipment exists"%species_id)
	var portrait=Portrait.new();portrait.size=Vector2(96,96);portrait.set_actor(equipped)
	var portrait_spec:Dictionary=portrait.portrait_draw_spec()
	check(portrait_spec.foreground_texture==west.foreground_texture \
		and portrait_spec.layer_order==west.layer_order,
		"portrait and world share fitted layer metadata and order")
	portrait.free()


func _check_floor_mapping_is_distinct_and_pure()->void:
	var cell:={"visibility_state":"VISIBLE","terrain_id":"wall"}
	var snapshot:=cell.duplicate(true)
	var floor_one:=Tiles.tile_spec(cell,Vector2i(3,4),1)
	var floor_two:=Tiles.tile_spec(cell,Vector2i(3,4),2)
	check(cell==snapshot,"tile query does not mutate observation")
	check(floor_one.texture!=floor_two.texture,"floor themes use distinct atlases")
	check(Rect2(floor_one.region).size==Vector2(24,24) \
		and Rect2(floor_two.region).size==Vector2(24,24),"tile regions are logical24")
	check(not bool(floor_one.changes_mapping) and not bool(floor_one.changes_fov),
		"tile visuals do not change mapping or FOV")
	for terrain_id in ["floor","stone_floor","wood_floor","metal","rubble",
			"shallow_water","wall"]:
		for floor_index in [1,2]:
			var spec:=Tiles.tile_spec({"visibility_state":"VISIBLE",
				"terrain_id":terrain_id},Vector2i(5,6),floor_index)
			check(spec.visible and spec.tile_index>=0 and spec.tile_index<16,
				"floor %d maps %s in bounds"%[floor_index,terrain_id])
	check(Tiles.tile_spec({"visibility_state":"VISIBLE","terrain_id":"floor",
		"feature_id":"anchor_portal_inactive"},Vector2i.ZERO,1).tile_index==12,
		"inactive portal maps its authored tile")
	check(Tiles.tile_spec({"visibility_state":"VISIBLE","terrain_id":"floor",
		"feature_id":"anchor_portal_active"},Vector2i.ZERO,2).tile_index==13,
		"active portal maps its authored tile")
	check(Tiles.tile_spec({"visibility_state":"UNSEEN","terrain_id":"wall"},
		Vector2i.ZERO,1).texture==null,"unseen terrain does not leak through FOV")


func _check_two_phase_walk_is_motion_only()->void:
	var grid=Grid.new();grid.size=Vector2(360,360);grid.set_graphics_mode(Grid.GRAPHICS_MODE_FLAT_2D)
	grid.set_observation(_observation(Vector2i(7,7)))
	grid.arm_actor_motion([77],180);grid.set_observation(_observation(Vector2i(8,7)))
	var started:=int(grid.actor_motion_state()[77].started_at_ms)
	var actor:=grid._actor_by_id(77)
	var early:Dictionary=grid.fixed_front_actor_render_spec(actor,false,started+30)
	var late:Dictionary=grid.fixed_front_actor_render_spec(actor,false,started+130)
	var idle:Dictionary=grid.fixed_front_actor_render_spec(actor,false,started+181)
	var ghost:Dictionary=grid.fixed_front_actor_render_spec(actor,true,started+30)
	var downed:=actor.duplicate(true);downed["life_state"]="DEAD"
	var downed_spec:Dictionary=grid.fixed_front_actor_render_spec(downed,false,started+30)
	var slime:=actor.duplicate(true);slime["species_id"]="slime"
	var slime_spec:Dictionary=grid.fixed_front_actor_render_spec(slime,false,started+30)
	check(early.walk_active and late.walk_active and early.walk_phase!=late.walk_phase,
		"active movement exposes two alternating foot phases")
	check(not idle.walk_active and not ghost.walk_active and not downed_spec.walk_active,
		"idle, downed, and formation ghost reset to stable stance")
	check(not slime_spec.walk_active,"non-biped movement keeps a stationary silhouette")
	check(float(early.walk_body_bob_px)==0.0 \
		and Rect2(early.bounds).size==Rect2(late.bounds).size,
		"walk keeps upper-body size stable without suppressing world interpolation")
	grid.free()


func _check_export_keeps_sources_out_of_runtime()->void:
	var grid=Grid.new();root.add_child(grid)
	var portrait=Portrait.new();root.add_child(portrait)
	check(grid.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST \
		and portrait.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,
		"native24 field and portrait rendering use nearest sampling")
	grid.queue_free();portrait.queue_free()
	var preset:=FileAccess.get_file_as_string("res://export_presets.cfg")
	for excluded in ["assets/living_expedition_v2/*","assets/pixel24_v3/source/*",
			"assets/pixel24_v3/review/*"]:
		check(excluded in preset,"Web export excludes review/source path %s"%excluded)
	for registry_path in ["res://playtest/fixed_front_topdown_assets.gd",
			"res://playtest/topdown_tile_assets.gd"]:
		var registry:=FileAccess.get_file_as_string(registry_path)
		check("assets/pixel24_v3/source/" not in registry \
			and "assets/pixel24_v3/review/" not in registry \
			and "assets/living_expedition_v2/" not in registry,
			"runtime registry references runtime assets only: %s"%registry_path)


func _is_binary_rgba_24(texture:Texture2D)->bool:
	if texture==null or texture.get_size()!=Vector2(24,24):return false
	var image:=texture.get_image()
	if image.get_format()!=Image.FORMAT_RGBA8:return false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha:=image.get_pixel(x,y).a
			if alpha!=0.0 and alpha!=1.0:return false
	return true


func _observation(actor_position:Vector2i)->Dictionary:
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			var actors:Array=[]
			if Vector2i(x,y)==actor_position:
				actors.append({"entity_id":77,"species_id":"human","faction_id":"party",
					"is_protagonist":true,"position":[x,y],"logical_position":[x,y],
					"display_position":[x,y],"health":10,"max_health":10})
			cells.append({"position":[x,y],"terrain_id":"floor",
				"visibility_state":"VISIBLE","actors":actors})
	return {"width":15,"height":15,"cells":cells}
