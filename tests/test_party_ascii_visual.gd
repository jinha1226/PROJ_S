extends "res://tests/test_case.gd"

const Style = preload("res://playtest/ascii_visual_style.gd")
const Portrait = preload("res://playtest/ascii_actor_portrait.gd")
const Grid = preload("res://playtest/party_grid_view.gd")
const Diorama = preload("res://playtest/ascii_diorama_projection.gd")


func test_seven_terrain_glyphs_and_visibility_contract() -> bool:
	var expected := {
		"floor":"", "stone_floor":"돌", "wood_floor":"나", "metal":"쇠",
		"rubble":"깨", "shallow_water":"물", "wall":"벽",
	}
	var glyph_colors:Array[Color]=[]
	var glyph_hexes:Array[String]=[]
	for terrain_id in expected:
		var spec: Dictionary = Style.terrain_spec({"terrain_id":terrain_id})
		check_eq(spec.glyph,expected[terrain_id],"%s Hangul material glyph"%terrain_id)
		check(not str(spec.base_hex).is_empty(),"%s has a base color"%terrain_id)
		check(spec.glyph_primary and spec.registered and not spec.draw_image \
			and not spec.draw_tile_border,"%s glyph is primary over a code-native projected floor"%terrain_id)
		check(bool(spec.draw_cell_surface),
			"%s owns the selected coloured perspective surface"%terrain_id)
		var base:=Color(str(spec.base_hex));var glyph:=Color(str(spec.glyph_hex))
		glyph_colors.append(glyph);glyph_hexes.append(str(spec.glyph_hex))
		check(glyph.get_luminance()>base.get_luminance()+0.025,
			"%s glyph remains readable against its restrained substrate"%terrain_id)
	check_eq(glyph_hexes.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),expected.size(),"seven terrain roles have distinct glyph colors")
	for walkable_id in ["floor","stone_floor","wood_floor","metal","rubble","shallow_water"]:
		check_eq(Style.terrain_spec({"terrain_id":walkable_id}).slab_ratio,Vector2(0.96,0.96),
			"%s uses the target's .48-to-.48 projected tile footprint"%walkable_id)
	check(Style.terrain_spec({"terrain_id":"wall"}).slab_ratio!=Vector2.ZERO,
		"walls retain a structural projected top")
	check(Style.terrain_spec({"terrain_id":"tree"}).glyph.is_empty() \
		and not Style.terrain_spec({"terrain_id":"tree"}).registered,
		"unregistered tree terrain is not invented for presentation")
	for walkable_id in ["floor","stone_floor","wood_floor","metal","rubble","shallow_water"]:
		check(str(Style.terrain_spec({"terrain_id":walkable_id}).glyph)!="#",
			"walkable %s never borrows the wall glyph"%walkable_id)
	check_eq([Style.feature_spec("run_entry").glyph,
		Style.feature_spec("run_exit_locked").glyph,
		Style.feature_spec("run_exit_open").glyph],["입","닫","출"],
		"stairs and exits use direct Hangul state words")
	check(Style.feature_spec("run_entry").glyph!=Style.terrain_spec({"terrain_id":"floor"}).glyph \
		and Style.feature_spec("run_exit_locked").glyph!=Style.terrain_spec({"terrain_id":"floor"}).glyph,
		"entry and exit glyphs cannot merge with ordinary floor")
	check_eq(Style.feature_spec("open_door").glyph,"문","open door uses its Hangul material word")
	var memory: Dictionary = Style.visibility_spec("MEMORY")
	check(memory.draw_terrain and not memory.draw_hazards and not memory.draw_actors,
		"memory draws terrain only")
	check(not memory.accepts_actor_input and memory.opacity<1.0,"memory is dim and non-interactive")
	var unseen: Dictionary = Style.visibility_spec("UNSEEN")
	check(not unseen.draw_terrain and not unseen.draw_actors and unseen.opacity==0.0,
		"unseen draws and accepts nothing")
	check(Color(str(memory.background_hex)).get_luminance() \
			>Color(str(unseen.background_hex)).get_luminance()*3.0,
		"visited terrain is visibly darker than live space but cannot merge with unseen black")
	return finish()


func test_primary_terrain_glyph_projection_is_fov_safe_and_mapping_neutral() -> bool:
	var cells:=_visible_cells()
	var terrain_ids:=["floor","stone_floor","wood_floor","metal","rubble","shallow_water","wall"]
	for index in range(terrain_ids.size()):
		cells[index].terrain_id=terrain_ids[index]
	cells[7].terrain_id="wall";cells[7].visibility_state="MEMORY"
	cells[8].terrain_id="shallow_water";cells[8].visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping:=grid.mapping_signature()
	for index in range(terrain_ids.size()):
		var spec:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(index,0))
		check(spec.visible and spec.glyph==Style.terrain_spec({"terrain_id":terrain_ids[index]}).glyph,
			"registered %s projects its primary glyph"%terrain_ids[index])
		check(not spec.draw_image and not spec.draw_tile_border,
			"terrain glyph adds no image, tile card, or input surface")
		check(bool(spec.draw_cell_surface),
			"%s emits a coloured projected surface polygon"%terrain_ids[index])
	var memory:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(7,0))
	check(memory.visible and memory.visibility_state=="MEMORY" and memory.opacity<1.0,
		"memory keeps only a dim static terrain glyph")
	var unseen:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(8,0))
	check(not unseen.visible and unseen.glyph.is_empty() and unseen.terrain_id.is_empty(),
		"unseen terrain emits no glyph or terrain identity")
	check_eq(grid.mapping_signature(),mapping,"glyph projection leaves mapping and hits unchanged")
	grid.free();return finish()


func test_product_projection_has_pitched_perspective_wall_height_and_exact_hits()->bool:
	var viewport:=Rect2(Vector2.ZERO,Vector2(390,390));var count:=13
	var projection:Dictionary=Diorama.perspective_projection_spec(viewport,count)
	check(is_equal_approx(float(projection.pitch_degrees),30.0) \
			and is_equal_approx(float(projection.perspective),0.78),
		"product camera keeps the chosen 30-degree / 78-percent visual target")
	var far:=Diorama.perspective_cell_polygon(Vector2i(6,0),viewport,count)
	var middle:=Diorama.perspective_cell_polygon(Vector2i(6,6),viewport,count)
	var near:=Diorama.perspective_cell_polygon(Vector2i(6,12),viewport,count)
	var far_bounds:=Diorama.polygon_bounds(far)
	var middle_bounds:=Diorama.polygon_bounds(middle)
	var near_bounds:=Diorama.polygon_bounds(near)
	check(near_bounds.size.x>middle_bounds.size.x*1.08 \
			and middle_bounds.size.x>far_bounds.size.x*1.08,
		"near tiles visibly widen while distant tiles recede")
	check(far_bounds.get_center().y<viewport.get_center().y \
			and near_bounds.get_center().y>viewport.get_center().y,
		"pitched floor recedes above and expands below the centered hero")
	check((middle[2].x-middle[3].x)>(middle[1].x-middle[0].x),
		"each floor cell is a perspective trapezoid instead of a square card")
	var wall:Dictionary=Diorama.perspective_wall_block(middle)
	check(bool(wall.visible) and float(wall.height)>=8.0 \
			and (wall.top as PackedVector2Array).size()==4 \
			and (wall.front as PackedVector2Array).size()==4,
		"wall owns a raised top and a real four-point front face")
	check(Diorama.polygon_bounds(wall.top).get_center().y \
			<Diorama.polygon_bounds(middle).get_center().y-float(wall.height)*0.8,
		"wall top is lifted clearly above the projected floor")

	var grid=Grid.new();grid.size=viewport.size
	grid.set_observation({"width":15,"height":15,"cells":_visible_cells()})
	grid.set_hero_centered_view(Vector2i(7,7),count,77)
	check(grid.world_to_pixel_center(Vector2i(7,7)).distance_to(viewport.get_center())<0.01,
		"perspective camera keeps the protagonist at the exact screen center")
	for position in [Vector2i(1,1),Vector2i(7,7),Vector2i(13,13)]:
		check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(position)),position,
			"projected cell center round-trips to canonical world authority")
	grid.free();return finish()


func test_flat_2d_and_diorama_2_5d_are_pure_switchable_projection_modes()->bool:
	var grid=Grid.new();grid.size=Vector2(390,390)
	grid.set_observation({"width":15,"height":15,"cells":_visible_cells()})
	grid.set_hero_centered_view(Vector2i(7,7),13,77)
	var observation_before:Dictionary=grid._cells.duplicate(true)
	var flat_mapping:=grid.mapping_signature()
	check_eq(grid.graphics_mode_id(),Grid.GRAPHICS_MODE_FLAT_2D,
		"product defaults to the Hangul flat top-view camera")
	var far_2d:=grid.world_cell_rect(Vector2i(7,1))
	var near_2d:=grid.world_cell_rect(Vector2i(7,13))
	check(far_2d.size.is_equal_approx(near_2d.size) \
			and is_equal_approx(far_2d.size.x,grid.cell_size_px()),
		"2D mode restores uniform axis-aligned square cells")
	for position in [Vector2i(1,1),Vector2i(7,7),Vector2i(13,13)]:
		check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(position)),position,
			"flat 2D keeps exact canonical hit mapping")
	check(not grid.set_graphics_mode("INVALID") \
			and grid.graphics_mode_id()==Grid.GRAPHICS_MODE_FLAT_2D,
		"unknown graphics option is a total no-op")
	check(grid.set_graphics_mode(Grid.GRAPHICS_MODE_DIORAMA_2_5D),
		"2.5D remains an accepted presentation option")
	var far_25d:=grid.world_cell_rect(Vector2i(7,1))
	var near_25d:=grid.world_cell_rect(Vector2i(7,13))
	check(near_25d.size.x>far_25d.size.x,
		"2.5D option retains visible perspective scaling")
	check(grid.set_graphics_mode(Grid.GRAPHICS_MODE_FLAT_2D) \
			and grid.mapping_signature()==flat_mapping,
		"switching back restores the exact default 2D mapping")
	check_eq(grid._cells,observation_before,
		"graphics mode never changes observation or simulation-facing data")
	grid.free();return finish()


func test_visibility_light_pool_memory_unseen_and_void_are_immediately_distinct() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[1,0]:cell.visibility_state="MEMORY"
		elif cell.position==[2,0]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	var visible_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(0,0))
	var memory_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(1,0))
	var unseen_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(2,0))
	var void_ground:Dictionary=grid.visibility_ground_draw_spec(Vector2i(-1,0))
	check_eq([visible_ground.visibility_state,memory_ground.visibility_state,
		unseen_ground.visibility_state,void_ground.visibility_state],
		["VISIBLE","MEMORY","UNSEEN","VOID"],"four spatial knowledge states remain explicit")
	var visible_luma:=Color(str(visible_ground.color_hex)).get_luminance()
	var memory_luma:=Color(str(memory_ground.color_hex)).get_luminance()
	var unseen_luma:=Color(str(unseen_ground.color_hex)).get_luminance()
	var void_luma:=Color(str(void_ground.color_hex)).get_luminance()
	check(visible_luma>memory_luma and memory_luma>unseen_luma and unseen_luma>void_luma,
		"flat light pool steps clearly from visible to memory, unseen, and void")
	check(visible_ground.draw_terrain and memory_ground.draw_terrain \
		and not unseen_ground.draw_terrain and not void_ground.draw_terrain,
		"only visible and remembered cells expose static terrain")
	check(not memory_ground.draw_actors and not memory_ground.draw_hazards \
		and not unseen_ground.draw_actors and not unseen_ground.draw_hazards,
		"memory and unseen states leak no actors or live hazards")
	var visible_glyph:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(0,0))
	var memory_glyph:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(1,0))
	var unseen_glyph:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(2,0))
	var visible_color:Color=visible_glyph.rendered_glyph_color
	var memory_color:Color=memory_glyph.rendered_glyph_color
	var visible_chroma:=maxf(visible_color.r,maxf(visible_color.g,visible_color.b)) \
		-minf(visible_color.r,minf(visible_color.g,visible_color.b))
	var memory_chroma:=maxf(memory_color.r,maxf(memory_color.g,memory_color.b)) \
		-minf(memory_color.r,minf(memory_color.g,memory_color.b))
	check(visible_color.a>memory_color.a+0.5 and visible_chroma>memory_chroma,
		"remembered glyph is visibly darker and less saturated than current FOV")
	check(not unseen_glyph.visible and str(unseen_glyph.glyph).is_empty(),
		"unseen terrain emits no glyph")
	var layers:Array=grid.diorama_layer_order()
	check(layers.find("GROUND_FEATURES")>layers.find("WALL_TOPS_AND_FACES") \
		and layers.find("GROUND_FEATURES")>layers.find("MATERIAL_MARKS"),
		"stairs and doors remain above every terrain glyph layer")
	grid.free();return finish()


func test_product_floor_draw_paths_have_no_image_texture_or_tile_atlas() -> bool:
	for path in ["res://playtest/party_grid_view.gd", "res://playtest/duel_decision_grid.gd"]:
		var source:=FileAccess.get_file_as_string(path)
		check(not source.is_empty(),"product grid source is readable: %s"%path)
		for forbidden in ["character_atlas.png","Texture2D","ImageTexture","AtlasTexture",
				"Sprite2D","draw_texture","_draw_connected_material_blob"]:
			check(not source.contains(forbidden),
				"%s contains no floor image/atlas path: %s"%[path,forbidden])
	var empty_grid=Grid.new()
	var empty_spec:Dictionary=empty_grid.terrain_glyph_draw_spec(Vector2i.ZERO)
	check_eq([empty_spec.draw_image,empty_spec.draw_tile_border],[false,false],
		"empty product grid defaults to no image and no tile card")
	empty_grid.free()
	return finish()


func test_hazard_cues_are_layered_and_visibility_safe() -> bool:
	var visible: Dictionary = Style.hazard_spec({
		"visibility_state":"VISIBLE", "fire_intensity":60, "wetness":40,
		"effective_conductivity":70,
	})
	var kinds: Array = []
	for cue in visible.cues:kinds.append(cue.kind)
	check_eq(kinds,["FIRE","WET"],"only live fire and wetness have floor cues")
	check_eq(visible.fire,60,"fire value")
	check_eq(visible.wetness,40,"wet value")
	check(not visible.has("conductivity"),"conductivity is inspection data, not a visual spec")
	check(Style.hazard_spec({"conductivity":100}).cues.is_empty(),
		"conductivity never creates a persistent lightning floor cue")
	check(Style.hazard_spec({"visibility_state":"MEMORY","fire":100,"wetness":100,
		"conductivity":100}).cues.is_empty(),"memory cannot leak live hazard state")
	return finish()


func test_actor_glyph_pose_facing_status_and_guard_contract() -> bool:
	var hero: Dictionary = Style.actor_spec({"is_protagonist":true,"facing":[1,-1]})
	var human: Dictionary = Style.actor_spec({"faction_id":"party","species_id":"human"})
	var goblin: Dictionary = Style.actor_spec({"faction_id":"party","species_id":"goblin"})
	var enemy: Dictionary = Style.actor_spec({"faction_id":"enemy","species_id":"goblin"})
	var unknown: Dictionary = Style.actor_spec({"faction_id":"enemy","species_id":"slime"})
	check_eq([hero.glyph,human.glyph,goblin.glyph,enemy.glyph,unknown.glyph],
		["ㅇ","ㅇ","ㄱ","ㄱ","ㅈ"],"species choseong actor grammar")
	for spec in [hero,human,goblin,enemy,unknown]:
		check(spec.glyph_is_body and not spec.detached_head and not spec.draw_head,
			"Hangul glyph is the body with no detached head primitive")
		check_eq([spec.glyph_weight,spec.glyph_outline_passes],
			["INK_STAMP",4],"actor glyph uses a compact deterministic ink stamp")
		check(spec.underlay_ratio.x>0.0 and spec.underlay_opacity>0.0,
			"actor identity owns a glyph-local background slab")
		check(not spec.draw_limbs and spec.limb_segments.is_empty(),
			"actor grammar contains no artificial arm or leg strokes")
		check(not spec.draw_equipment and spec.equipment_primitive_count==0,
			"unequipped actor adds no equipment overlay")
	check_eq([hero.body_class,hero.glyph_scale,hero.presence_class,
		hero.glyph_font_weight,hero.glyph_weight_passes],
		["NORMAL",1.0,"HERO","BOLD",2],
		"hero presence uses the real bold face without changing physical size")
	check_eq([goblin.body_class,goblin.glyph_scale,goblin.glyph_font_weight,
		goblin.glyph_weight_passes],["SMALL",0.88,"REGULAR",1],
		"goblin body size is independent from ordinary presence")
	var elite_goblin:=Style.actor_spec({"faction_id":"enemy","species_id":"goblin",
		"threat_id":"DANGEROUS"})
	var ordinary_orc:=Style.actor_spec({"faction_id":"enemy","species_id":"orc",
		"threat_id":"EVEN"})
	check_eq([elite_goblin.glyph_scale,elite_goblin.glyph_font_weight,
		ordinary_orc.glyph_scale,ordinary_orc.glyph_font_weight],
		[0.88,"BOLD",1.15,"REGULAR"],
		"body scale and threat weight remain orthogonal 88/100/115 and regular/bold")
	check_eq(hero.facing,[1,-1],"diagonal facing remains explicit")
	var moving:Dictionary=Style.actor_spec({"faction_id":"party","visual_stance":"MOVING",
		"facing":[1,0]})
	var idle:Dictionary=Style.actor_spec({"faction_id":"party","visual_stance":"IDLE",
		"facing":[1,0]})
	check(moving.limb_segments.is_empty() and idle.limb_segments.is_empty() \
			and moving.glyph_center==idle.glyph_center,
		"movement never recreates limbs or moves the glyph identity anchor")
	var weapon_cases:={"SHORT_SWORD":["SWORD","/"],
		"THRUSTING_SWORD":["SWORD","|"],"HAND_AXE":["AXE","7"],
		"MACE":["MACE","!"],"SPEAR":["SPEAR","^"],
		"BOW":["BOW",")"],"CROSSBOW":["CROSSBOW","+"]}
	var weapon_glyphs:Array=[]
	for weapon_id in weapon_cases:
		var armed:=Style.actor_spec({"is_protagonist":true,"equipment_visual":{
			"weapon_id":weapon_id,"armor_definition_id":""}})
		check(armed.draw_equipment and armed.equipment_primitive_count==1 \
				and str(armed.equipment.weapon_family)==weapon_cases[weapon_id][0] \
				and str(armed.equipment.weapon_glyph)==weapon_cases[weapon_id][1] \
				and str(armed.glyph)=="ㅇ" \
				and not bool(armed.equipment.changes_core_glyph),
			"%s draws a static ASCII mark without changing the body"%weapon_id)
		weapon_glyphs.append(str(armed.equipment.weapon_glyph))
	check_eq(weapon_glyphs.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),weapon_cases.size(),
		"seven weapons remain visually distinct as static ASCII marks")
	var leather:=Style.actor_spec({"is_protagonist":true,"equipment_visual":{
		"weapon_id":"SHORT_SWORD","armor_definition_id":"ARMOR_LEATHER"}})
	var padded:=Style.actor_spec({"is_protagonist":true,"equipment_visual":{
		"weapon_id":"SHORT_SWORD","armor_definition_id":"ARMOR_PADDED"}})
	check_eq([leather.glyph,padded.glyph,leather.equipment.armor_left_glyph,
		leather.equipment.armor_right_glyph,padded.equipment.primitive_count],
		["ㅇ","ㅇ","[","]",3],
		"armor brackets and a weapon surround the unchanged Hangul body")
	var guarded: Dictionary = Style.actor_spec({"faction_id":"party","guarded":true,
		"status_ids":["BLEEDING"]})
	check(guarded.bleeding and guarded.guard_segments.size()==3,
		"bleeding and guard have independent visuals")
	var downed: Dictionary = Style.actor_spec({"faction_id":"party","life_state":"DOWNED"})
	check_eq(downed.pose,"DOWNED","downed pose")
	check(downed.opacity<1.0 and not downed.draw_limbs,"downed body stays legible without limbs")
	var dead: Dictionary = Style.actor_spec({"faction_id":"party","life_state":"DEAD"})
	check_eq(dead.glyph,"흔","dead glyph")
	check(not dead.draw_head and not dead.draw_limbs,"dead state does not look standing")
	var ghost: Dictionary = Style.actor_spec({"faction_id":"party"},true)
	check(ghost.ghost and ghost.opacity<1.0,"proposal ghost is translucent")
	return finish()


func test_hangul_body_stays_stable_with_ascii_equipment()->bool:
	var human_bare:=Style.actor_spec({"faction_id":"party","species_id":"human"})
	var human_armor:=Style.actor_spec({"faction_id":"party","species_id":"human",
		"equipment_visual":{"weapon_id":"UNARMED_STRIKE",
			"armor_definition_id":"ARMOR_LEATHER"}})
	var human_sword:=Style.actor_spec({"faction_id":"party","species_id":"human",
		"equipment_visual":{"weapon_id":"SHORT_SWORD",
			"armor_definition_id":"ARMOR_LEATHER"}})
	var human_thrust:=Style.actor_spec({"faction_id":"party","species_id":"human",
		"equipment_visual":{"weapon_id":"THRUSTING_SWORD",
			"armor_definition_id":"ARMOR_LEATHER"}})
	var goblin_bare:=Style.actor_spec({"faction_id":"enemy","species_id":"goblin"})
	var goblin_armor:=Style.actor_spec({"faction_id":"enemy","species_id":"goblin",
		"equipment_visual":{"weapon_id":"UNARMED_STRIKE",
			"armor_definition_id":"ARMOR_LEATHER"}})
	var goblin_sword:=Style.actor_spec({"faction_id":"enemy","species_id":"goblin",
		"equipment_visual":{"weapon_id":"SHORT_SWORD",
			"armor_definition_id":"ARMOR_LEATHER"}})
	var goblin_thrust:=Style.actor_spec({"faction_id":"enemy","species_id":"goblin",
		"equipment_visual":{"weapon_id":"THRUSTING_SWORD",
			"armor_definition_id":"ARMOR_LEATHER"}})
	check_eq([human_bare.glyph,human_armor.glyph,human_sword.glyph,human_thrust.glyph],
		["ㅇ","ㅇ","ㅇ","ㅇ"],"human body stays ㅇ across equipment")
	check_eq([goblin_bare.glyph,goblin_armor.glyph,goblin_sword.glyph,goblin_thrust.glyph],
		["ㄱ","ㄱ","ㄱ","ㄱ"],"goblin body stays ㄱ across equipment")
	for spec in [human_armor,human_sword,human_thrust,goblin_armor,goblin_sword,
			goblin_thrust]:
		check(str(spec.grammar_id)=="HANGUL_BODY_ASCII_EQUIPMENT_V1" \
				and not bool(spec.composition.is_composed) and spec.draw_equipment \
				and str(spec.equipment.composition_mode)=="STATIC_ASCII",
			"stable Hangul body explicitly owns static ASCII equipment")
	return finish()


func test_ground_fire_lights_neighboring_visible_tiles_and_actor_without_fog_leak()->bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.fire_intensity=80
		elif cell.position==[8,7]:
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true})
		elif cell.position==[9,7]:cell.visibility_state="MEMORY"
		elif cell.position==[7,9]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var source:=grid.fire_light_draw_spec(Vector2i(7,7),75)
	var near:=grid.fire_light_draw_spec(Vector2i(8,7),75)
	var edge:=grid.fire_light_draw_spec(Vector2i(8,8),75)
	check(source.active and near.active and edge.active \
			and source.brightness>near.brightness and near.brightness>=edge.brightness,
		"fire uses a bounded distance falloff across surrounding cells")
	check(not grid.fire_light_draw_spec(Vector2i(9,7),75).active \
			and not grid.fire_light_draw_spec(Vector2i(7,9),75).active,
		"fire light cannot reveal MEMORY or UNSEEN cells")
	var lit_actor:=grid.actor_draw_spec(grid._actor_by_id(77),false,75)
	check(bool(lit_actor.environment_light.active) \
			and lit_actor.has("base_color_hex") \
			and Color(str(lit_actor.color_hex)).get_luminance() \
				>Color(str(lit_actor.base_color_hex)).get_luminance(),
		"neighboring fire brightens the actor glyph without changing actor state")
	grid.free();return finish()


func test_world_glyph_fits_15px_cell_and_preserves_hit_fov_contract() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true,"facing":[1,0],
				"equipment_visual":{"weapon_id":"HAND_AXE",
					"armor_definition_id":"ARMOR_PADDED"},
				"logical_position":[7,7]})
	var grid=Grid.new();grid.size=Vector2(225,225)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping:=grid.mapping_signature();var hit:=grid.actor_hit_rect(77)
	var spec:Dictionary=grid.actor_glyph_draw_spec(77)
	check(spec.visible and spec.font_size>=9,"15px cell keeps a readable central glyph")
	var figure_bounds:=Rect2(spec.figure_bounds);var glyph_rect:=Rect2(spec.glyph_rect)
	check(float(spec.top_overlap_px)<=spec.cell_rect.size.y*0.20 \
			and spec.glyph_rect.position.x>=spec.cell_rect.position.x \
			and spec.glyph_rect.end.x<=spec.cell_rect.end.x \
			and figure_bounds.grow(2.0).encloses(glyph_rect),
		"top-view Hangul body fills its tile while staying laterally bounded: %s vs %s" \
		%[spec.glyph_rect,spec.cell_rect])
	check(not spec.detached_head and spec.outline_passes==8 and not spec.selected_outline,
		"world actor has no head or yellow selection outline")
	check(spec.draw_equipment and spec.equipment_primitive_count==3 \
			and str(spec.equipment.weapon_family)=="AXE" \
			and bool(spec.equipment.armor_visible) and str(spec.glyph)=="ㅇ" \
			and str(spec.equipment.weapon_glyph)=="7",
		"party map surrounds the stable body with static ASCII equipment: %s"%spec)
	check(spec.limb_segments.is_empty() and not bool(spec.equipment.changes_core_glyph) \
			and str(spec.equipment.composition_mode)=="STATIC_ASCII",
		"world actor has no detached limbs or core-glyph mutation")
	check_eq(grid.mapping_signature(),mapping,"glyph presentation cannot alter mapping")
	check_eq(grid.actor_hit_rect(77),hit,"glyph presentation cannot alter actor hit authority")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7))),77,
		"logical target center remains immediately hittable")
	grid.free()
	return finish()


func test_actor_pseudo_depth_proportions_are_bounded_at_360_and_450()->bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"species_id":"human","roster_slot":0,"is_protagonist":true})
		elif cell.position==[7,6]:cell.actors.append({"entity_id":88,"faction_id":"enemy",
			"species_id":"goblin"})
	var observation:={"width":15,"height":15,"cells":cells}
	for viewport in [360,450]:
		var grid=Grid.new();grid.size=Vector2(viewport,viewport)
		grid.set_observation(observation);grid.set_hero_centered_view(Vector2i(7,7),15,77)
		var mapping:=grid.mapping_signature();var hero_hit:=grid.actor_hit_rect(77)
		var hero:Dictionary=grid.actor_glyph_draw_spec(77)
		var neighbor:Dictionary=grid.actor_glyph_draw_spec(88)
		check(bool(hero.one_cell_one_glyph) and str(hero.glyph)=="ㅇ" \
				and float(hero.top_overlap_px)<=grid.world_cell_rect(Vector2i(7,7)).size.y*0.20,
			"%dpx body owns one full-cell top-view Hangul glyph overlap=%s cell=%s" \
			%[viewport,hero.top_overlap_px,grid.cell_size_px()])
		check(hero.limb_segments.is_empty() and float(hero.feet_bottom_margin_px)==0.0,
			"%dpx actor silhouette contains no artificial limbs"%viewport)
		check(Rect2(hero.figure_bounds).size.is_equal_approx(Rect2(neighbor.figure_bounds).size) \
				and int(hero.font_size)>=int(neighbor.font_size) \
				and grid.world_to_pixel_center(Vector2i(7,7)).y \
					>grid.world_to_pixel_center(Vector2i(7,6)).y \
				and grid.actor_render_order()==[88,77],
			"%dpx flat actors share tile scale and retain stable y render order"%viewport)
		var goblin_color:=Color(str(grid.actor_draw_spec(grid._actor_by_id(88)).color_hex))
		check(str(neighbor.glyph)=="ㄱ" and goblin_color.g>goblin_color.r*1.25 \
				and goblin_color.g>goblin_color.b*1.25,
			"%dpx visible enemy goblin owns an unmistakable green core glyph"%viewport)
		check_eq([grid.mapping_signature(),grid.actor_hit_rect(77),
			grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7)))],
			[mapping,hero_hit,77],"%dpx pseudo-depth remains draw-only"%viewport)
		grid.free()
	return finish()


func test_brackets_portrait_and_specs_are_detached() -> bool:
	var segments: Array = Style.bracket_segments(Rect2(Vector2.ZERO,Vector2(40,40)))
	check_eq(segments.size(),8,"four-corner bracket uses eight strokes")
	var actor := {"entity_id":7,"faction_id":"party","species_id":"goblin"}
	var portrait = Portrait.new()
	portrait.set_actor(actor)
	actor["species_id"]="human"
	check_eq(portrait.actor_dto().species_id,"goblin","portrait owns a detached actor DTO")
	var returned: Dictionary = portrait.actor_dto()
	returned["species_id"]="orc"
	check_eq(portrait.actor_dto().species_id,"goblin","portrait getter is detached")
	check_eq(portrait.actor_draw_spec().glyph,"ㄱ","portrait consumes shared actor grammar")
	portrait.free()
	return finish()


func test_grid_filters_non_visible_actors_and_sorts_y_x_id() -> bool:
	var grid = Grid.new()
	grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":[
		{"position":[3,4],"terrain_id":"floor","visibility_state":"VISIBLE","actors":[
			{"entity_id":4,"faction_id":"enemy","roster_slot":9}]},
		{"position":[1,2],"terrain_id":"floor","visibility_state":"VISIBLE","actors":[
			{"entity_id":5,"faction_id":"party","roster_slot":1},
			{"entity_id":3,"faction_id":"enemy","roster_slot":9}]},
		{"position":[4,4],"terrain_id":"floor","visibility_state":"MEMORY","actors":[
			{"entity_id":90,"faction_id":"enemy","roster_slot":9}]},
		{"position":[5,4],"terrain_id":"floor","visibility_state":"UNSEEN","actors":[
			{"entity_id":91,"faction_id":"enemy","roster_slot":9}]},
	]})
	check_eq(grid.actor_render_order(),[3,5,4],"actors draw by y then x then stable id")
	check_eq(grid.actor_in_world_cell(Vector2i(4,4)),-1,"memory actor is not selectable")
	check_eq(grid.actor_in_world_cell(Vector2i(5,4)),-1,"unseen actor is not selectable")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(4,4))),-1,
		"memory cell pointer cannot hit a stale actor")
	grid.free()
	return finish()


func test_follower_display_position_controls_visual_hit_without_moving_logical_cell() -> bool:
	var cells: Array = []
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor","visibility_state":"VISIBLE",
				"actors":[]})
	for cell in cells:
		if cell.position==[6,8]:
			cell.actors.append({"entity_id":12,"faction_id":"party","species_id":"goblin",
				"roster_slot":1,"display_role":"FOLLOWER","logical_position":[7,7],
				"display_position":[6,8]})
	var grid = Grid.new()
	grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	check_eq(grid.actor_in_world_cell(Vector2i(7,7)),-1,
		"logical occupancy cell is not reused as presentation hit area")
	check_eq(grid.actor_in_world_cell(Vector2i(6,8)),12,
		"follower display position owns visual input")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(6,8))),12,
		"display-position figure has the actor hit target")
	var stored: Dictionary = grid._actors[0]
	check_eq(stored.logical_position,[7,7],"renderer retains logical position for tether only")
	check_eq(stored.position,[6,8],"renderer projects follower at display position")
	var follower: Dictionary = Style.follower_spec(stored)
	check(follower.visible and follower.dash_count==4,
		"follower separation requests dotted tether and party footprint")
	check_eq(follower.logical_position,[7,7],"tether starts at supplied logical position")
	check_eq(follower.display_position,[6,8],"tether ends at presentation position")
	grid.free()
	return finish()


func test_contact_follower_never_suppresses_deployment_ghost_but_ghosts_dedupe() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[6,8]:
			cell.actors.append({"entity_id":12,"faction_id":"party","species_id":"goblin",
				"roster_slot":1,"display_role":"FOLLOWER","logical_position":[7,7],
				"display_position":[6,8]})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells},[
		{"entity_id":12,"faction_id":"party","roster_slot":1,"position":[5,8]},
		{"entity_id":12,"faction_id":"party","roster_slot":1,"position":[5,8]},
		{"entity_id":12,"faction_id":"party","roster_slot":1,"position":[6,8]},
	])
	check_eq(grid._ghosts.size(),2,"follower never suppresses a deployment ghost")
	var ghost_positions:Array=[]
	for ghost in grid._ghosts:ghost_positions.append(ghost.position)
	check_eq(ghost_positions,[[5,8],[6,8]],
		"prior ghost dedupes same id and position while follower does not")
	grid.free();return finish()


func test_unseen_cell_emits_no_short_long_or_nearby_actor_signal() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.visibility_state="UNSEEN"
		if cell.position==[6,7]:cell.actors.append({"entity_id":42,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var pointer:=grid.world_cell_rect(Vector2i(7,7)).position+Vector2(1,grid.cell_size_px()*0.5)
	check_eq(grid.pixel_to_world_cell(pointer),Vector2i(7,7),"mapping still resolves unseen cell")
	check_eq(grid.actor_at_pointer(pointer),-1,
		"compressed perspective hit slop cannot reach through an unseen cell")
	var emitted:Array=[]
	grid.world_cell_pressed.connect(func(_position):emitted.append("CELL"))
	grid.actor_pressed.connect(func(_entity_id):emitted.append("ACTOR"))
	grid.tile_long_pressed.connect(func(_position):emitted.append("LONG"))
	grid.pointer_gesture_started.connect(func():emitted.append("START"))
	grid.pointer_gesture_finished.connect(func(_outcome):emitted.append("FINISH"))
	var press:=InputEventScreenTouch.new();press.index=3;press.pressed=true;press.position=pointer
	var release:=InputEventScreenTouch.new();release.index=3;release.pressed=false;release.position=pointer
	grid._gui_input(press);grid._gui_input(release)
	grid._begin_pointer_gesture("TOUCH",4,pointer)
	grid._on_long_press_timeout(int(grid.pointer_gesture_state().generation))
	check(emitted.is_empty(),"unseen short, long, and nearby actor gestures emit no signal")
	check(not bool(grid.pointer_gesture_state().active),"unseen cell never owns a gesture")
	grid.free();return finish()


func test_hero_centered_world_padding_is_explicit_void_and_never_interactive() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[0,0]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	check_eq(grid.view_origin,Vector2i(-7,-7),"edge hero keeps camera center without clamping")
	var padding_position:=Vector2i(-7,-7)
	var padding:Dictionary=grid.void_padding_draw_spec(padding_position)
	var pointer:Vector2=padding.rect.get_center()
	check(bool(padding.visible) and str(padding.color_hex)=="#010203" \
		and not bool(padding.accepts_input),"outside-world camera cell is an explicit void surface")
	check_eq(grid.pixel_to_world_cell(pointer),Vector2i(-1,-1),
		"void padding rejects pixel-to-world mapping")
	check_eq(grid.actor_at_pointer(pointer),-1,"void padding cannot hit the nearby centered hero")
	check(not grid.intent_draw_spec({"type":"MOVE","from_position":[0,0],
		"destination":[-1,0]}).visible,"intent endpoint cannot leak into world padding")
	check(not grid.visual_effect_draw_spec({"effect_id":"padding","event_id":1,
		"kind":"SLASH","world_position":[-1,0]}).visible,
		"effect cannot render in world padding")
	grid.set_route_overlay([[-1,0],[0,0]],0,true)
	var route:Dictionary=grid.route_draw_spec()
	check_eq(route.path,[[0,0]],"out-of-world route point is rejected before projection")
	check(not bool(route.valid),"route cannot become valid through void padding")
	var emitted:Array=[]
	grid.world_cell_pressed.connect(func(_position):emitted.append("CELL"))
	grid.actor_pressed.connect(func(_entity_id):emitted.append("ACTOR"))
	grid.tile_long_pressed.connect(func(_position):emitted.append("LONG"))
	grid._begin_pointer_gesture("TOUCH",5,pointer)
	grid._on_long_press_timeout(int(grid.pointer_gesture_state().generation))
	check(emitted.is_empty() and not bool(grid.pointer_gesture_state().active),
		"void padding owns neither short nor long-press gesture authority")
	grid.free();return finish()


func test_unseen_route_sections_are_present_but_not_drawable() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_route_overlay([[6,7],[7,7],[8,7]],0,true)
	var spec:Dictionary=grid.route_draw_spec()
	check_eq(spec.path,[[6,7],[7,7],[8,7]],"route mapping keeps unseen coordinate")
	check_eq([spec.tiles[0].visible,spec.tiles[1].visible,spec.tiles[2].visible],
		[true,false,true],"unseen route tile is hidden")
	check_eq([spec.segments[0].visible,spec.segments[1].visible],[false,false],
		"segments touching unseen cells are hidden")
	check_eq([spec.direction_cues[0].visible,spec.direction_cues[1].visible],[false,false],
		"direction cues touching unseen cells are hidden")
	check(spec.markers.is_empty() and not bool(spec.draw_endpoint_markers),
		"route keeps its FOV-safe path but emits no start/goal circle markers")
	grid.free();return finish()


func test_unseen_intent_endpoints_are_not_drawable() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.visibility_state="UNSEEN"
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	check(not grid.intent_draw_spec({"type":"MOVE","from_position":[6,7],
		"destination":[7,7]}).visible,"move destination cannot leak into unseen")
	check(not grid.intent_draw_spec({"type":"MELEE","from_position":[6,7],
		"target_position":[7,7]}).visible,"melee target cannot leak into unseen")
	check(not grid.intent_draw_spec({"type":"HOLD","from_position":[7,7]}).visible,
		"unseen hold origin cannot leak")
	check(grid.intent_draw_spec({"type":"MOVE","from_position":[6,7],
		"destination":[6,8]}).visible,"fully visible intent remains drawable")
	grid.free();return finish()


func test_melee_intent_sources_keep_target_marker_without_plan_connector() -> bool:
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation({"width":15,"height":15,"cells":_visible_cells()})
	for source in ["DIRECT","OVERRIDE","SUGGESTED","ENEMY_FORECAST"]:
		var spec:Dictionary=grid.intent_draw_spec({"type":"MELEE","source":source,
			"from_position":[7,7],"target_position":[8,7]})
		check(bool(spec.visible) and spec.primitive=="TARGET_MARKER" \
			and not bool(spec.draw_connector) and not str(spec.marker_style).is_empty(),
			"%s melee intent keeps target feedback without an attacker-target line"%source)
	var move:Dictionary=grid.intent_draw_spec({"type":"MOVE","source":"SUGGESTED",
		"from_position":[7,7],"destination":[8,7]})
	check(bool(move.draw_connector),"movement planning retains its distinct route arrow")
	grid.free();return finish()


func test_follow_plan_is_detached_offset_dashed_cued_risked_and_clearable() -> bool:
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":_visible_cells()})
	var path:=[[6,7],[7,7],[8,7]]
	var dto:={"schema_version":1,"accepted":true,"path":path,"completed_steps":0,
		"next_position":[7,7],"companion_rows":[
			{"entity_id":12,"roster_slot":1,"path":path.duplicate(true),
				"next_position":[7,7],"max_total_risk":12,"component_maxima":{"fire":12}},
			{"entity_id":13,"roster_slot":2,"path":path.duplicate(true),
				"next_position":[7,7],"max_total_risk":70,"component_maxima":{"fire":70}},
		]}
	grid.set_exploration_companion_follow_plan(dto)
	dto.path[0][0]=99;dto.companion_rows[0].path[0][0]=98
	var spec:Dictionary=grid.exploration_companion_follow_draw_spec()
	check(spec.active and spec.path[0]==[6,7],"setter owns a deep detached plan")
	check_eq(spec.rows.size(),2,"two companion lanes")
	check(spec.rows[0].offset_px!=spec.rows[1].offset_px,"roster slots use distinct path offsets")
	for row in spec.rows:
		check_eq(row.segments.size(),2,"each follower uses the shared path")
		check(row.segments[0].dash_count==4 and row.segments[0].visible,
			"follow lane is visible and dotted")
		check(row.next_cue.visible and row.next_cue.glyph==">","next-step cue is explicit")
		check(row.risk_badge.visible,"risk badge is projected")
	check_eq([spec.rows[0].risk_badge.value,spec.rows[1].risk_badge.value],[12,70],
		"risk badges retain per-companion totals")
	check_eq(grid.actor_at_pointer(spec.rows[0].next_cue.pixel_center),-1,
		"follow overlays never join actor hit testing")
	spec.rows[0].segments.clear()
	check_eq(grid.exploration_companion_follow_draw_spec().rows[0].segments.size(),2,
		"returned draw spec is detached")
	grid.set_exploration_companion_follow_plan({})
	var cleared:Dictionary=grid.exploration_companion_follow_draw_spec()
	check(not cleared.active and cleared.rows.is_empty(),"empty DTO clears follow rendering")
	grid.free();return finish()


func test_diorama_connected_masks_cover_all_cardinals_without_unseen_leak() -> bool:
	var wall := {"terrain_id":"wall","visibility_state":"VISIBLE"}
	var floor := {"terrain_id":"stone_floor","visibility_state":"VISIBLE"}
	var directions := ["N","E","S","W"]
	for expected_mask in range(16):
		var neighbors: Dictionary = {}
		for bit in range(4):
			neighbors[directions[bit]] = (wall if expected_mask & (1 << bit) else floor).duplicate(true)
		var spec: Dictionary = Diorama.cell_spec(Vector2i(7,7),wall,neighbors)
		check_eq(spec.connected_mask,expected_mask,"cardinal connected mask %d"%expected_mask)
	var memory_wall:=wall.duplicate(true);memory_wall.visibility_state="MEMORY"
	var unseen_wall:=wall.duplicate(true);unseen_wall.visibility_state="UNSEEN"
	var mixed:Dictionary=Diorama.cell_spec(Vector2i(7,7),wall,{
		"N":memory_wall,"E":unseen_wall,"S":floor,"W":floor,
		"NE":wall,
	})
	check_eq(mixed.connected_mask,Diorama.NORTH,
		"known memory connects while unseen and diagonal data do not")
	var hidden:Dictionary=Diorama.cell_spec(Vector2i(7,7),unseen_wall,{
		"N":wall,"E":wall,"S":wall,"W":wall,
	})
	check(not hidden.visible and hidden.connected_mask==0 and hidden.terrain_id.is_empty(),
		"unseen center exposes neither terrain nor silhouette")
	return finish()


func test_wall_roles_light_bands_and_tile_material_rules_are_quantized() -> bool:
	var role_vectors:=[
		[0,"END"],[Diorama.NORTH,"END"],
		[Diorama.NORTH|Diorama.SOUTH,"STRAIGHT"],
		[Diorama.NORTH|Diorama.EAST,"CORNER"],
		[Diorama.NORTH|Diorama.EAST|Diorama.SOUTH,"JUNCTION"],
		[Diorama.ALL_CARDINALS,"SOLID"],
	]
	for row in role_vectors:
		check_eq(Diorama.wall_role_spec(int(row[0]),0).role,row[1],
			"connected wall role %d"%int(row[0]))
	var south_face:Dictionary=Diorama.wall_role_spec(Diorama.NORTH,Diorama.SOUTH)
	check(south_face.face_visible and south_face.face_glyph=="ㅂ",
		"exposed south wall becomes a darker Hangul face")
	check(not Diorama.wall_role_spec(Diorama.NORTH,Diorama.EAST).face_visible,
		"non-south exposure adds no false face")

	var near:Dictionary=Diorama.quantized_light_spec(Vector2i(7,7),Vector2i(7,7),"VISIBLE")
	var mid:Dictionary=Diorama.quantized_light_spec(Vector2i(11,7),Vector2i(7,7),"VISIBLE")
	var edge:Dictionary=Diorama.quantized_light_spec(Vector2i(13,7),Vector2i(7,7),"VISIBLE")
	var memory:Dictionary=Diorama.quantized_light_spec(Vector2i(7,7),Vector2i(7,7),"MEMORY")
	check_eq([near.band,mid.band,edge.band,memory.band],["NEAR","MID","EDGE","MEMORY"],
		"hero light uses four explicit knowledge-safe bands")
	check(near.foreground_multiplier>mid.foreground_multiplier \
		and mid.foreground_multiplier>edge.foreground_multiplier,
		"foreground ink falls in three discrete visible steps")
	check(memory.saturation<=0.14,"memory remains consistently near-monochrome")

	var material_families:Array=[]
	for terrain_id in ["floor","stone_floor","wood_floor","metal","rubble",
			"shallow_water","wall"]:
		var terrain:Dictionary=Style.terrain_spec({"terrain_id":terrain_id})
		material_families.append(terrain.ink_family)
		check(terrain.glyph_offset is Vector2 and terrain.slab_ratio is Vector2,
			"%s material owns placement and local background rules"%terrain_id)
		check(int(terrain.outline_passes)<=2 and int(terrain.weight_passes)<=2,
			"%s limits glyph overprint cost"%terrain_id)
	check_eq(material_families.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),7,"seven terrain roles use seven material families")
	return finish()


func test_fake_depth_specs_raise_walls_and_shadow_actors_without_fov_leaks() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:
			cell.terrain_id="wall"
		elif cell.position==[8,7]:
			cell.terrain_id="wall";cell.visibility_state="MEMORY"
		elif cell.position==[9,7]:
			cell.terrain_id="wall";cell.visibility_state="UNSEEN"
		elif cell.position==[6,7]:
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true})
		elif cell.position==[6,8]:
			cell.visibility_state="MEMORY"
			cell.actors.append({"entity_id":88,"faction_id":"enemy","species_id":"goblin"})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var floor_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(6,7))
	var wall_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(7,7))
	var memory_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(8,7))
	var unseen_depth:Dictionary=grid.terrain_depth_draw_spec(Vector2i(9,7))
	check(not floor_depth.raised and floor_depth.extrusion_px==0.0,
		"walkable floor stays low and flat")
	check(wall_depth.raised and wall_depth.extrusion_px>=2.0 \
		and wall_depth.extrusion_px<=4.0 and wall_depth.shadow_offset.length()>0.0,
		"wall has a small dark side and directional shadow")
	check(memory_depth.raised and memory_depth.opacity<wall_depth.opacity,
		"remembered wall keeps subdued depth")
	check(not unseen_depth.visible and not unseen_depth.raised,
		"unseen terrain emits no extrusion or shadow")
	check(not wall_depth.draw_cell_border and not wall_depth.draw_image,
		"fake depth adds neither cell borders nor images")
	var actor:Dictionary=grid.actor_glyph_draw_spec(77)
	check(actor.visible and actor.shadow.visible and actor.shadow.directional \
		and actor.shadow.radius.x>actor.shadow.radius.y,
		"world actor carries a compact offset ground shadow")
	check(not grid.actor_glyph_draw_spec(88).visible,
		"remembered actor and its shadow are both FOV-safe")
	grid.free();return finish()


func test_hero_camera_settle_is_move_only_centered_pure_and_input_safe() -> bool:
	var first:=_actor_observation(Vector2i.ZERO,"VISIBLE")
	var second:=_actor_observation(Vector2i(1,0),"VISIBLE")
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation(first);grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	check(not grid.camera_settle_draw_spec().active,"initial camera observation snaps")
	grid.set_observation(second);grid.set_hero_centered_view(Vector2i(1,0),15,77)
	var started:=int(grid._camera_settle.started_at_ms)
	var sample0:Dictionary=grid.camera_settle_draw_spec(started)
	var sample35:Dictionary=grid.camera_settle_draw_spec(started+35)
	var sample70:Dictionary=grid.camera_settle_draw_spec(started+70)
	check_eq(grid.view_origin,Vector2i(-6,-7),"logical camera immediately follows hero-(7,7)")
	check(grid.world_to_pixel_center(Vector2i(1,0)).distance_to(grid.grid_rect().get_center())<0.01,
		"hero logical/pixel center is immediate and fixed")
	check(sample0.active and sample0.offset_px.x>0.0 \
		and sample35.offset_px.x<sample0.offset_px.x and sample35.offset_px.x>0.0 \
		and not sample70.active and sample70.offset_px==Vector2.ZERO,
		"world settle decays from the prior camera to zero in 70ms")
	check_eq(sample0.hero_counter_offset_px,-sample0.offset_px,
		"hero draw pass cancels world settle and stays at center")
	grid.set_hero_centered_view(Vector2i(1,0),15,77)
	check_eq(int(grid._camera_settle.started_at_ms),started,
		"refresh and phase-only camera calls never rearm settle")
	check_eq(grid.pixel_to_world_cell(grid.grid_rect().get_center()),Vector2i(1,0),
		"canonical pixel mapping remains exact during presentation settle")
	check_eq(grid.actor_at_pointer(grid.grid_rect().get_center()),-1,
		"actor/world gestures are safely blocked during the brief settle")
	var emitted:Array=[];grid.world_cell_pressed.connect(func(position):emitted.append(position))
	grid._begin_pointer_gesture("TOUCH",2,grid.grid_rect().get_center())
	check(emitted.is_empty() and not bool(grid.pointer_gesture_state().active),
		"settling camera owns no stale world gesture")
	check(grid.void_padding_draw_spec(Vector2i(-1,0)).visible,
		"edge void contract survives visual camera offset")
	grid._camera_settle.started_at_ms=Time.get_ticks_msec()-71
	check_eq(grid.actor_at_pointer(grid.grid_rect().get_center()),77,
		"canonical hero hit returns after settle")
	grid.set_hero_centered_view(Vector2i(10,10),15,77)
	check(not grid.camera_settle_draw_spec().active,"teleport/load-style camera changes snap")
	grid.free()
	var continuous_grid=Grid.new();continuous_grid.size=Vector2(345,345)
	continuous_grid.set_observation(first)
	continuous_grid.set_hero_centered_view(Vector2i.ZERO,15,77)
	continuous_grid.set_observation(_actor_observation(Vector2i(1,0),"VISIBLE"))
	continuous_grid.set_hero_centered_view(Vector2i(1,0),15,77,160)
	var continuous_started:=int(continuous_grid._camera_settle.started_at_ms)
	var continuous0:Dictionary=continuous_grid.camera_settle_draw_spec(continuous_started)
	var continuous80:Dictionary=continuous_grid.camera_settle_draw_spec(continuous_started+80)
	check_eq(continuous0.curve,"LINEAR_CONTINUOUS",
		"continuous travel uses a non-braking camera curve")
	check(absf(continuous80.offset_px.length()/continuous0.offset_px.length()-0.5)<0.02,
		"continuous travel keeps constant halfway velocity instead of cubic braking")
	continuous_grid.free();return finish()


func test_product_hit_timeline_preserves_actor_glyph_and_emits_local_ascii_feedback() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[6,7]:cell.actors.append({"entity_id":1,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
		elif cell.position==[7,7]:cell.actors.append({"entity_id":2,"faction_id":"enemy",
			"species_id":"goblin"})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_hero_centered_view(Vector2i(6,7),15,1);grid.set_neutral_phase_map(true)
	var target_before:Dictionary=grid._actors[1].duplicate(true)
	var target_style_before:Dictionary=grid.actor_draw_spec(grid._actors[1])
	var target_bounds_before:Rect2=grid._actor_figure_bounds(grid._actors[1],grid.cell_size_px(),false)
	var hit:={"effect_id":"42:hit","event_id":42,"order":0,"kind":"HIT_FLASH",
		"world_position":[7,7],"target_id":2,"instigator_id":1,"damage_type":"physical"}
	var amount:={"effect_id":"42:amount","event_id":42,"order":1,"kind":"FLOATING_AMOUNT",
		"world_position":[7,7],"target_id":2,"instigator_id":1,"damage_type":"physical","text":"-22"}
	check_eq(grid.play_effects([hit,amount]),2,"product effects consume each id once")
	check_eq(grid.play_effects([hit,amount]),0,"product effects remain exactly once")
	var started:=int(grid._active_visual_effects[0].started_at_ms)
	var hit0:Dictionary=grid.visual_effect_draw_spec(grid._active_visual_effects[0],started)
	var hit130:Dictionary=grid.visual_effect_draw_spec(grid._active_visual_effects[0],started+130)
	check_eq(hit0.primitive,"GLYPH_FLASH","product hit removes the circular ring")
	check(hit0.flash_active and hit0.particle_count>=3 and hit0.particle_count<=6,
		"early generic hit emits three to six local particles")
	check(hit0.particles.all(func(row):return str(row.get("glyph","")) in [".",":","*"]),
		"hit shards stay legible as the compact ASCII impact alphabet")
	check_eq(hit0.particles,grid.visual_effect_draw_spec(grid._active_visual_effects[0],started).particles,
		"hit shards are event-id deterministic")
	check(not hit130.flash_active,"generic particle registration ends by 130ms")
	check_eq([grid._actors[1],grid.actor_draw_spec(grid._actors[1]).glyph,
		grid.actor_draw_spec(grid._actors[1]).color_hex,
		grid._actor_figure_bounds(grid._actors[1],grid.cell_size_px(),false)],
		[target_before,target_style_before.glyph,target_style_before.color_hex,
		target_bounds_before],"hit feedback never mutates target glyph, color, or position")
	var amount_row:Dictionary=grid._active_visual_effects[1]
	var amount0:Dictionary=grid.visual_effect_draw_spec(amount_row,started)
	var amount325:Dictionary=grid.visual_effect_draw_spec(amount_row,started+325)
	var amount650:Dictionary=grid.visual_effect_draw_spec(amount_row,started+650)
	check(amount0.font_size>=17 and amount0.font_size<=20 \
			and amount0.text=="-22" and amount0.color_hex=="#ffd98a",
		"physical damage is a compact readable warm number")
	var target_center:=grid.world_to_pixel_center(Vector2i(7,7))
	var start_height_cells:float=(target_center.y-float(amount0.pixel_center.y)) \
		/grid.cell_size_px()
	check(start_height_cells>=0.75 and start_height_cells<=1.1,
		"damage number starts above the target glyph instead of covering it")
	check(amount325.pixel_center.y<amount0.pixel_center.y \
		and amount650.pixel_center.y<amount325.pixel_center.y,
		"damage number continues easing upward from its head-clear start")
	check(amount0.opacity==1.0 and amount650.opacity==0.0,
		"floating damage fades fully over 650ms")
	check_eq(grid.play_effects([{"effect_id":"43:amount","event_id":43,"order":1,
		"kind":"FLOATING_AMOUNT","world_position":[7,7],"target_id":2,
		"damage_type":"physical","text":"-9"},
		{"effect_id":"44:amount","event_id":44,"order":1,
		"kind":"FLOATING_AMOUNT","world_position":[7,7],"target_id":2,
		"damage_type":"physical","text":"-7"}]),2,
		"rapid damage rows remain independently visible")
	var stacked_centers:Array=[]
	for effect in grid._active_visual_effects:
		if str(effect.get("kind",""))=="FLOATING_AMOUNT":
			stacked_centers.append(grid.visual_effect_draw_spec(effect,
				int(effect.started_at_ms)).pixel_center)
	check(stacked_centers.size()==3 \
		and Vector2(stacked_centers[0]).distance_to(Vector2(stacked_centers[1])) \
			>=grid.cell_size_px()*0.9 \
		and Vector2(stacked_centers[1]).distance_to(Vector2(stacked_centers[2])) \
			>=grid.cell_size_px()*0.55,
		"rapid damage numbers fan far enough apart for a double attack")
	var top_amount:=grid.visual_effect_draw_spec({"effect_id":"top:amount","event_id":90,
		"kind":"FLOATING_AMOUNT","world_position":[7,0],"text":"-3",
		"started_at_ms":started},started)
	check(float(top_amount.pixel_center.y)+float(top_amount.camera_offset_px.y) \
		>=grid.grid_rect().position.y+float(top_amount.font_size)*0.58,
		"top-row damage number clamps inside the visible grid")
	var miss:=grid.visual_effect_draw_spec({"effect_id":"43:miss","event_id":43,
		"kind":"MISS","world_position":[7,7],"text":"빗나감","started_at_ms":started},started)
	var slash:=grid.visual_effect_draw_spec({"effect_id":"44:slash","event_id":44,
		"kind":"SLASH","world_position":[7,7],"started_at_ms":started},started)
	var death_early:=grid.visual_effect_draw_spec({"effect_id":"45:death","event_id":45,
		"kind":"DEATH","world_position":[7,7],"started_at_ms":started},started+80)
	var death_late:=grid.visual_effect_draw_spec({"effect_id":"45:death","event_id":45,
		"kind":"DEATH","world_position":[7,7],"started_at_ms":started},started+300)
	check(miss.font_size<amount0.font_size and miss.text=="빗나감",
		"miss cue is smaller and quieter than damage")
	check_eq(slash.primitive,"NONE","legacy inline slash path is inert")
	check(not slash.has("attack_glyphs"),"legacy slash exposes no ASCII burst")
	check(death_early.opacity==0.0 and death_late.opacity>0.0 and death_late.opacity<=0.48,
		"death cross arrives late and weak so it cannot cover the damage number")
	var offscreen:=hit.duplicate(true);offscreen.world_position=[14,14]
	check(not grid.visual_effect_draw_spec(offscreen,started).visible,
		"off-FOV hit feedback emits no field primitive")
	grid.free();return finish()


func test_melee_vfx_is_separate_target_local_overlay_without_inline_attack_glyphs() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[6,7]:cell.actors.append({"entity_id":1,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
		elif cell.position==[7,7]:cell.actors.append({"entity_id":2,"faction_id":"enemy",
			"species_id":"goblin"})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid._ensure_melee_vfx()
	var legacy:=grid.visual_effect_draw_spec({"effect_id":"legacy","event_id":41,
		"kind":"SLASH","world_position":[7,7],"started_at_ms":Time.get_ticks_msec()})
	check_eq(legacy.primitive,"NONE","inline grid slash has no draw primitive")
	check(not legacy.has("lead_glyph") and not legacy.has("attack_glyphs"),
		"inline grid exposes no attack glyph vocabulary")
	check_eq(grid.play_effects([{"effect_id":"41:melee_vfx","event_id":41,
		"kind":"MELEE_VFX","attacker_grid_pos":[6,7],"target_grid_pos":[7,7]}]),1,
		"grid routes canonical position pair to melee overlay")
	var started:=int(grid.melee_vfx.active_effects()[0].started_at_ms)
	var spec:Dictionary=grid.melee_vfx.effect_draw_specs(started)[0]
	check(grid.melee_vfx is Node2D and spec.primitive=="BROKEN_SLASH" \
		and spec.slash_glyph.is_empty() and not bool(spec.draw_connector),
		"slash exists only as a target-local Node2D impact without a connector")
	grid.free();return finish()


func test_diorama_hash_marks_and_layer_order_are_fixed_and_detached() -> bool:
	var vectors := [
		[Vector2i(0,0),0,0],
		[Vector2i(7,11),0,310339678],
		[Vector2i(7,11),1,377919465],
		[Vector2i(-3,5),9,1539742877],
		[Vector2i(14,14),97,1329410547],
	]
	for row in vectors:
		check_eq(Diorama.visual_hash(row[0],row[1]),row[2],
			"stable visual hash %s/%s"%[row[0],row[1]])
	var first:Dictionary=Diorama.material_mark_spec(Vector2i(5,12),"wood_floor")
	var second:Dictionary=Diorama.material_mark_spec(Vector2i(5,12),"wood_floor")
	check_eq(first,second,"material marks are coordinate-deterministic")
	first.kind="CORRUPTED"
	check(Diorama.material_mark_spec(Vector2i(5,12),"wood_floor").kind!="CORRUPTED",
		"material mark specs are detached")
	var expected_layers := ["VOID","MEMORY_GROUND","VISIBLE_GROUND","MATERIAL_MARKS",
		"WALL_SHADOWS","WALL_TOPS_AND_FACES","GROUND_FEATURES","VISIBLE_HAZARDS",
		"GROUND_ROUTES","ACTOR_GROUNDING","ACTORS","INTENTS_AND_SELECTION",
		"EFFECTS","FOV_EDGE_AND_VIGNETTE"]
	var layers:Array=Diorama.layer_order()
	check_eq(layers,expected_layers,"diorama draw layers are explicit")
	layers.clear()
	check_eq(Diorama.layer_order(),expected_layers,"layer order getter is detached")
	return finish()


func test_diorama_sanitizer_and_hazards_are_memory_unseen_safe() -> bool:
	var raw := {"position":[4,5],"terrain_id":"wall","feature_id":"run_exit_open",
		"visibility_state":"MEMORY","fire_intensity":90,"fire":91,"wetness":92,
		"effective_conductivity":93,"conductivity":94,"base_conductivity":95,
		"actors":[{"entity_id":9}],"secret":"must disappear"}
	var memory:Dictionary=Diorama.sanitize_observed_cell(raw)
	check_eq(memory,{"visibility_state":"MEMORY","terrain_id":"wall"},
		"memory sanitizer whitelists static terrain only")
	var memory_hazard:Dictionary=Diorama.hazard_floor_spec(Vector2i(4,5),raw)
	check_eq([memory_hazard.visible,memory_hazard.fire,memory_hazard.wetness],
		[false,0,0],"memory aliases cannot leak live hazards")
	check(not memory_hazard.has("conductivity") and not memory_hazard.has("arc_alpha"),
		"diorama has no conductive floor primitive")
	var unseen_raw:=raw.duplicate(true);unseen_raw.visibility_state="UNSEEN"
	check_eq(Diorama.sanitize_observed_cell(unseen_raw),{"visibility_state":"UNSEEN"},
		"unseen sanitizer exposes no authoritative fields")
	var visible_raw:=raw.duplicate(true);visible_raw.visibility_state="VISIBLE"
	var visible_hazard:Dictionary=Diorama.hazard_floor_spec(Vector2i(4,5),visible_raw)
	check(visible_hazard.visible and visible_hazard.fire==90 and visible_hazard.wetness==92,
		"visible fire and wetness produce a floor-layer spec")
	check(not visible_hazard.has("conductivity") and not visible_hazard.has("arc_alpha"),
		"visible conductive terrain still has no arc visual")
	memory.terrain_id="CORRUPTED"
	check_eq(str(raw.terrain_id),"wall","sanitizer output is detached from observation")
	return finish()


func test_actor_equipment_projection_is_detached_tile_local_and_accessory_free() -> bool:
	var actor:={"is_protagonist":true,"equipment_visual":{"weapon_id":"BOW",
		"armor_definition_id":"ARMOR_LEATHER",
		"off_hand_definition_id":"SHIELD_WOOD","accessory_definition_id":"ACCESSORY_BRASS_CHARM"}}
	var before:=actor.duplicate(true);var spec:=Style.actor_spec(actor)
	check_eq(actor,before,"visual projection never mutates canonical equipment data")
	check(spec.draw_equipment and spec.equipment_primitive_count==3 \
			and str(spec.equipment.weapon_family)=="BOW" \
			and str(spec.equipment.weapon_glyph)==")" \
			and str(spec.equipment.armor_kind)=="LEATHER" and str(spec.glyph)=="ㅇ",
		"weapon and armor remain static ASCII around the stable actor glyph")
	check(not spec.equipment.has("accessory_definition_id") \
			and not spec.equipment.has("off_hand_definition_id") \
			and bool(spec.equipment.tile_local),
		"accessories and off-hand data add no actor clutter")
	return finish()


func test_diorama_route_style_preserves_mapping_and_actor_hit_authority() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells})
	var mapping:=grid.mapping_signature();var hit:=grid.actor_hit_rect(77)
	check_eq(grid.diorama_layer_order(),Diorama.layer_order(),
		"grid forwards pure layer order")
	check_eq(grid.diorama_cell_draw_spec(Vector2i(7,7)).connected_mask,15,
		"visible same-terrain cross connects")
	grid.set_route_overlay([[6,7],[7,7],[8,7]],0,true)
	grid.set_cursor_preview(77,Vector2i(6,7),Vector2i(8,7),true)
	var route:Dictionary=grid.route_draw_spec()
	check_eq([route.render_style,route.draw_tile_cards],["CHALK_CENTERLINE",false],
		"route renders as chalk centerline without tile cards")
	check(route.markers.is_empty() and not bool(route.draw_endpoint_markers) \
		and not bool(route.draw_ground_markers),
		"route path has no circular start, next, or goal markers")
	check(not bool(grid.cursor_preview_draw_spec().visible) \
		and bool(grid.cursor_preview_draw_spec().suppressed_by_route),
		"route destination also suppresses the generic circular cursor preview")
	check_eq(grid.mapping_signature(),mapping,"diorama and route never alter grid mapping")
	check_eq(grid.actor_hit_rect(77),hit,"equipment never enlarges actor hit authority")
	check_eq(grid.pixel_to_world_cell(grid.world_to_pixel_center(Vector2i(7,7))),Vector2i(7,7),
		"logical cell center roundtrip remains exact")
	check_eq(grid.actor_at_pointer(grid.world_to_pixel_center(Vector2i(7,7))),77,
		"visual equipment adds no competing hit surface")
	grid.free();return finish()


func test_selected_actor_has_no_yellow_overlay_but_target_and_ghost_remain() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":1,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
		if cell.position==[8,7]:cell.actors.append({"entity_id":2,"faction_id":"enemy",
			"roster_slot":99})
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,"cells":cells},[
		{"entity_id":3,"faction_id":"party","roster_slot":1,"position":[6,7]}])
	grid.set_selection(1,2)
	var overlays:Array=grid.selection_overlay_draw_specs()
	check_eq(overlays.map(func(row):return row.kind),["TARGET","DEPLOYMENT_GHOST"],
		"selected party actor emits no map bracket")
	check_eq([overlays[0].entity_id,overlays[0].color_hex],[2,"#ff6b70"],
		"enemy target retains red selection semantics")
	check_eq(overlays[1].entity_id,3,"deployment proposal retains cyan ghost bracket")
	overlays[0].kind="CORRUPTED"
	check_eq(grid.selection_overlay_draw_specs()[0].kind,"TARGET","overlay specs are detached")
	grid.free();return finish()


func test_actor_motion_eases_draw_only_and_snaps_without_canonical_arm() -> bool:
	var grid=Grid.new();grid.size=Vector2(345,345)
	var initial:=_actor_observation(Vector2i(7,7),"VISIBLE")
	grid.set_observation(initial)
	var mapping:=grid.mapping_signature()
	check(grid.actor_motion_state().is_empty(),"initial observation snaps")
	grid.arm_actor_motion([77],150);grid.set_observation(_actor_observation(Vector2i(8,7),"VISIBLE"))
	var motion:Dictionary=grid.actor_motion_state()[77]
	var started:=int(motion.started_at_ms)
	var sample0:Dictionary=grid.actor_motion_draw_spec(77,started)
	var sample75:Dictionary=grid.actor_motion_draw_spec(77,started+75)
	var sample150:Dictionary=grid.actor_motion_draw_spec(77,started+150)
	check_eq(sample0.world_position,Vector2(7,7),"motion starts at prior presentation cell")
	check(absf(float(sample75.eased_progress)-0.875)<0.0001,
		"75ms cubic ease-out reaches deterministic 87.5 percent")
	check_eq(sample150.world_position,Vector2(8,7),"150ms motion ends at target")
	check_eq(grid.actor_in_world_cell(Vector2i(8,7)),77,"authoritative hit cell changes immediately")
	check(grid.actor_hit_rect(77).has_point(grid.world_to_pixel_center(Vector2i(8,7))),
		"authoritative target center owns hit immediately")
	check_eq(grid.mapping_signature(),mapping,"animation never changes grid mapping")
	grid.set_observation(_actor_observation(Vector2i(10,7),"VISIBLE"))
	check(grid.actor_motion_state().is_empty(),"unarmed observation change snaps")
	grid.arm_actor_motion([77],150);grid.set_observation(_actor_observation(Vector2i(12,7),"VISIBLE"))
	check(grid.actor_motion_state().is_empty(),"two-cell teleport snaps even when armed")
	grid.free();return finish()


func test_consecutive_actor_and_hero_camera_hops_retarget_current_draw_position() -> bool:
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation(_actor_observation(Vector2i(7,7),"VISIBLE"))
	grid.set_hero_centered_view(Vector2i(7,7),15,77)
	grid.arm_actor_motion([77],150)
	grid.set_observation(_actor_observation(Vector2i(8,7),"VISIBLE"))
	grid._actor_motions[77].started_at_ms=Time.get_ticks_msec()-75
	var actor_before:Vector2=grid._actor_visual_world_position(77)
	grid.arm_actor_motion([77],150)
	grid.set_observation(_actor_observation(Vector2i(9,7),"VISIBLE"))
	var actor_motion:Dictionary=grid.actor_motion_state()[77]
	check(Vector2(actor_motion.from_world).distance_to(actor_before)<0.08 \
		and Vector2(actor_motion.to_world)==Vector2(9,7),
		"consecutive actor hop retargets from the current interpolated draw position")
	check_eq(grid.actor_in_world_cell(Vector2i(9,7)),77,
		"actor interpolation never delays logical occupancy")

	grid.set_hero_centered_view(Vector2i(8,7),15,77)
	grid._camera_settle.started_at_ms=Time.get_ticks_msec()-35
	var camera_before:Dictionary=grid.camera_settle_draw_spec()
	var reference_world:=Vector2i(10,7)
	var screen_before:=grid.world_to_pixel_center(reference_world)+Vector2(camera_before.offset_px)
	grid.set_hero_centered_view(Vector2i(9,7),15,77)
	var retarget_started:=int(grid._camera_settle.started_at_ms)
	var camera_after:Dictionary=grid.camera_settle_draw_spec(retarget_started)
	var screen_after:=grid.world_to_pixel_center(reference_world)+Vector2(camera_after.offset_px)
	check(screen_after.distance_to(screen_before)<0.25,
		"consecutive hero-camera hop preserves the current drawn world position")
	check_eq(grid.pixel_to_world_cell(grid.grid_rect().get_center()),Vector2i(9,7),
		"camera retarget remains draw-only and preserves canonical center mapping")
	grid.free();return finish()


func test_deterministic_ascii_wall_torches_are_fov_safe_quantized_and_bounded() -> bool:
	var cells:=_visible_cells()
	var visible_walls:=[Vector2i(1,1),Vector2i(4,1),Vector2i(7,1),Vector2i(10,1),
		Vector2i(13,1),Vector2i(1,4),Vector2i(4,4),Vector2i(7,4)]
	var memory_walls:=[Vector2i(1,8),Vector2i(4,8),Vector2i(7,8)]
	var unseen_walls:=[Vector2i(1,13),Vector2i(4,13),Vector2i(7,13)]
	for cell in cells:
		var position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
		if position in visible_walls:cell.terrain_id="wall"
		elif position in memory_walls:
			cell.terrain_id="wall";cell.visibility_state="MEMORY"
		elif position in unseen_walls:
			cell.terrain_id="wall";cell.visibility_state="UNSEEN"
		elif position==Vector2i(7,7):
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true})
	var observation:={"width":15,"height":15,"cells":cells}
	var expected_positions:Array=[]
	for viewport in [360,450]:
		var grid=Grid.new();grid.size=Vector2(viewport,viewport)
		grid.set_observation(observation);grid.set_hero_centered_view(Vector2i(7,7),15,77)
		var mapping:=grid.mapping_signature();var actor_color:=str(grid.actor_draw_spec(
			grid._actor_by_id(77)).color_hex)
		var at_zero:Array=grid.torch_draw_specs(0)
		var at_same_tick:Array=grid.torch_draw_specs(74)
		var at_next_tick:Array=grid.torch_draw_specs(75)
		var stats:Dictionary=grid.torch_cache_stats()
		var positions:=at_zero.map(func(row):return row.position)
		if expected_positions.is_empty():expected_positions=positions
		check_eq(positions,expected_positions,
			"%dpx torch placement is deterministic and viewport-independent"%viewport)
		check(int(stats.visible_count)<=4 and int(stats.cached_count)<=8 \
			and float(stats.flicker_hz)>=13.0 and float(stats.flicker_hz)<=14.0,
			"%dpx close torch cadence is visibly faster while sources stay bounded"%viewport)
		for left_index in range(positions.size()):
			for right_index in range(left_index+1,positions.size()):
				var left:=Vector2i(int(positions[left_index][0]),int(positions[left_index][1]))
				var right:=Vector2i(int(positions[right_index][0]),int(positions[right_index][1]))
				check(maxi(absi(left.x-right.x),absi(left.y-right.y))>=5,
					"%dpx selected torches keep five-cell spacing"%viewport)
		check(at_zero.all(func(row):return str(row.glyph)=="불" \
			and int(row.glyph_count)==1 and not bool(row.draw_image) \
			and row.texture==null and str(row.visibility_state)!="UNSEEN"),
			"%dpx torches are one-cell Hangul with no image or unseen row"%viewport)
		check_eq(at_zero.map(func(row):return row.brightness),
			at_same_tick.map(func(row):return row.brightness),
			"%dpx torch flicker is fixed within its 75ms quantum"%viewport)
		var visible_changed:=false;var memory_fixed:=true
		for index in range(at_zero.size()):
			if bool(at_zero[index].animated):
				visible_changed=visible_changed or float(at_zero[index].brightness) \
					!=float(at_next_tick[index].brightness)
			else:
				memory_fixed=memory_fixed and float(at_zero[index].brightness) \
					==float(at_next_tick[index].brightness) \
					and int(at_next_tick[index].flicker_tick)==0
		check(visible_changed and memory_fixed,
			"%dpx visible flames quantize while MEMORY stays fixed and dark"%viewport)
		var visible_source:Vector2i=Vector2i(-1,-1)
		for row in at_zero:
			if bool(row.animated):
				visible_source=Vector2i(int(row.position[0]),int(row.position[1]));break
		check(visible_source!=Vector2i(-1,-1) \
			and float(grid.torch_draw_specs(75).filter(func(row):return row.position \
				==[visible_source.x,visible_source.y])[0].brightness)>=0.78 \
			and float(grid.torch_draw_specs(75).filter(func(row):return row.position \
				==[visible_source.x,visible_source.y])[0].brightness)<=0.86,
			"%dpx source 불 remains legible at restrained brightness"%viewport)
		var lit_floor_found:=false;var lit_wall_found:=false
		for y in range(15):
			for x in range(15):
				var position:=Vector2i(x,y);var light:Dictionary=grid.torch_light_draw_spec(position,75)
				if not bool(light.active) or int(light.distance)<=0:continue
				if position in visible_walls:lit_wall_found=true
				else:lit_floor_found=true
				check(str(light.visibility_state)=="VISIBLE" \
					and float(light.composite_alpha)>=0.04 \
					and float(light.composite_alpha)<=0.151,
					"%dpx warm pool only composites on visible cells"%viewport)
		check(lit_floor_found and lit_wall_found,
			"%dpx torch pool visibly reaches neighboring floor and wall cells"%viewport)
		check(not bool(grid.torch_light_draw_spec(memory_walls[0],75).active),
			"%dpx live torch pool cannot illuminate MEMORY"%viewport)
		check(not bool(grid.torch_light_draw_spec(unseen_walls[0],75).active),
			"%dpx torch pool cannot illuminate an UNSEEN cell"%viewport)
		check_eq([grid.mapping_signature(),str(grid.actor_draw_spec(
			grid._actor_by_id(77)).color_hex)],[mapping,actor_color],
			"%dpx torches alter neither mapping nor actor semantic color"%viewport)
		var rebuilds:=int(stats.rebuild_count)
		grid.torch_draw_specs(5000)
		check_eq(grid.torch_cache_stats().rebuild_count,rebuilds,
			"%dpx flicker reuses the static torch cache"%viewport)
		grid.free()
	return finish()


func test_static_projection_cache_is_viewport_bounded_and_motion_phase_is_free() -> bool:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[7,7]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation({"width":48,"height":48,"cells":cells})
	grid.set_hero_centered_view(Vector2i(7,7),15,77)
	var initial:Dictionary=grid.static_projection_cache_stats()
	check_eq([initial.cell_count,initial.viewport_capacity],[225,225],
		"static projection cache is bounded to the 15x15 camera")
	check(initial.world_cell_count<=225,"cache does not require a 48x48 presentation copy")
	var occupied:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(7,7))
	var clear:Dictionary=grid.terrain_glyph_draw_spec(Vector2i(8,7))
	check(occupied.occupied and not clear.occupied \
		and (occupied.rendered_glyph_color as Color).a \
		< (clear.rendered_glyph_color as Color).a,
		"actor tile suppresses floor ink without adding a selection ring")
	var rebuilds:=int(initial.rebuild_count)
	var moved_cells:=_visible_cells()
	for cell in moved_cells:
		if cell.position==[8,7]:cell.actors.append({"entity_id":77,"faction_id":"party",
			"roster_slot":0,"is_protagonist":true})
	grid.set_observation({"width":48,"height":48,"cells":moved_cells})
	check_eq(grid.static_projection_cache_stats().rebuild_count,rebuilds,
		"actor-only movement leaves the static terrain/light projection intact")
	check(not grid.terrain_glyph_draw_spec(Vector2i(7,7)).occupied \
		and grid.terrain_glyph_draw_spec(Vector2i(8,7)).occupied,
		"dynamic occupancy updates independently from static terrain")
	grid.set_hero_centered_view(Vector2i(7,7),15,77)
	check_eq(grid.static_projection_cache_stats().rebuild_count,rebuilds,
		"same hero/view does not invalidate static ink")
	grid.play_effects([{"effect_id":"cache:hit","event_id":901,"order":0,
		"kind":"HIT_FLASH","world_position":[7,7],"target_id":77}])
	check_eq(grid.static_projection_cache_stats().rebuild_count,rebuilds,
		"transient hit animation does not rebuild static cells")
	grid.set_hero_centered_view(Vector2i(8,7),15,77)
	var shifted:Dictionary=grid.static_projection_cache_stats()
	check_eq(shifted.rebuild_count,rebuilds+1,
		"hero/light/view change invalidates exactly once")
	check(int(shifted.content_hit_count)>int(initial.content_hit_count) \
		and int(shifted.content_cache_count)<=225,
		"adjacent camera shift reuses bounded world-coordinate static content")

	var contact:Dictionary=grid.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,0,150)
	var passing:Dictionary=grid.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,75,150)
	var settle:Dictionary=grid.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,150,150)
	check_eq([contact.step_phase,passing.step_phase,settle.step_phase],
		["CONTACT","PASS","SETTLE"],"one movement owns three compact glyph phases")
	check(contact.stride_sign==1 and passing.stride_sign==-1 and settle.stride_sign==0,
		"step phase alternates limbs and returns to neutral")
	check(passing.glyph_bob_ratio<0.0 and not settle.active,
		"bob exists only during the already-active movement process")
	grid.free();return finish()


func test_wide_zoom_freezes_idle_torch_flicker_but_keeps_restrained_light() -> bool:
	var count:=25;var hero:=Vector2i(48,48);var cells:Array=[]
	for y in range(hero.y-count/2,hero.y-count/2+count):
		for x in range(hero.x-count/2,hero.x-count/2+count):
			var wall:bool=(x+y)%9==0
			var actors:Array=[]
			if Vector2i(x,y)==hero:actors.append({"entity_id":77,"faction_id":"party",
				"species_id":"human","roster_slot":0,"is_protagonist":true})
			cells.append({"position":[x,y],"terrain_id":"wall" if wall else "stone_floor",
				"visibility_state":"VISIBLE","feature_id":"","fire_intensity":0,
				"wetness":0,"effective_conductivity":0,"actors":actors,"ground_items":[]})
	var grid=Grid.new();grid.size=Vector2(450,450)
	grid.set_observation({"width":96,"height":96,"cells":cells})
	grid.set_hero_centered_view(hero,count,77)
	var stats:Dictionary=grid.torch_cache_stats()
	var torches:Array=grid.torch_draw_specs(125)
	check(not bool(stats.timer_redraw_enabled) and float(stats.flicker_hz)==0.0,
		"19+ cell camera does not repaint the full grid for idle flame flicker")
	check(not torches.is_empty() and torches.all(func(row):return bool(row.visible) \
		and not bool(row.animated) and bool(row.draw_light_pool)),
		"wide zoom keeps stable visible torch glyphs and light pools")
	var source:=Vector2i(int(torches[0].position[0]),int(torches[0].position[1]))
	var light:Dictionary=grid.torch_light_draw_spec(source,125)
	check(bool(light.active) and int(light.radius_cells)==3 \
		and float(light.composite_alpha)>=0.04 \
		and float(light.composite_alpha)<=0.151,
		"wide torch light remains visible with reduced radius and alpha")
	check(int(grid.static_projection_cache_stats().content_cache_count)<=count*count,
		"wide static content cache remains viewport bounded")
	grid.free();return finish()


func test_colorful_terrain_palette_keeps_role_glyphs_high_contrast_and_distinct() -> bool:
	var terrain_ids:=["floor","stone_floor","wood_floor","metal","rubble","shallow_water","wall"]
	var brightest_ground:=0.0
	var terrain_glyph_hexes:Array[String]=[]
	var terrain_base_hexes:Array[String]=[]
	for terrain_id in terrain_ids:
		var terrain:Dictionary=Style.terrain_spec({"terrain_id":terrain_id})
		var base:=Color(str(terrain.base_hex));var glyph:=Color(str(terrain.glyph_hex))
		brightest_ground=maxf(brightest_ground,base.get_luminance())
		terrain_base_hexes.append(str(terrain.base_hex))
		terrain_glyph_hexes.append(str(terrain.glyph_hex))
		check(glyph.get_luminance()>base.get_luminance()+0.025,
			"%s restrained glyph clears its coloured ground"%terrain_id)
		var chroma:=maxf(glyph.r,maxf(glyph.g,glyph.b))-minf(glyph.r,minf(glyph.g,glyph.b))
		check(chroma<0.34,"%s terrain ink stays subordinate to saturated actors"%terrain_id)
	check_eq(terrain_glyph_hexes.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),terrain_ids.size(),"terrain glyph palette is role-distinct")
	check_eq(terrain_base_hexes.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),terrain_ids.size(),
		"blue, brown, steel and water projected surfaces remain role-distinct")
	var role_specs:=[
		Style.actor_spec({"is_protagonist":true,"roster_slot":0}),
		Style.actor_spec({"faction_id":"party","species_id":"human","roster_slot":1}),
		Style.actor_spec({"faction_id":"party","species_id":"human","roster_slot":2}),
		Style.actor_spec({"faction_id":"party","species_id":"goblin","roster_slot":2}),
		Style.actor_spec({"faction_id":"enemy","species_id":"goblin"}),
	]
	var colors:Array=[]
	for spec in role_specs:
		var color:=Color(str(spec.color_hex));colors.append(str(spec.color_hex))
		check(color.get_luminance()>brightest_ground+0.16,"actor glyph clears dark terrain")
	check_eq(colors.duplicate().reduce(func(accum,value):
		if value not in accum:accum.append(value)
		return accum,[]).size(),5,"gold/cyan/blue/green/red roles are color-distinct")
	var palette:Dictionary=Style.diorama_palette_spec()
	check(Color(str(palette.void_hex)).get_luminance()<Color(str(palette.substrate_hex)).get_luminance(),
		"void remains darker than neutral substrate")
	return finish()


func _actor_observation(position:Vector2i,visibility_state:String)->Dictionary:
	var cells:=_visible_cells()
	for cell in cells:
		if cell.position==[position.x,position.y]:
			cell.visibility_state=visibility_state
			cell.actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true,"logical_position":[position.x,position.y]})
	return {"width":15,"height":15,"cells":cells}


func _visible_cells()->Array:
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor","visibility_state":"VISIBLE",
				"actors":[]})
	return cells
