extends SceneTree
const Art=preload("res://playtest/handcrafted_tile_assets.gd")
const Layer=preload("res://playtest/tactical_board_layer.gd")
const ProjectionRules=preload("res://playtest/tactical_board_projection.gd")
const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init()->void:call_deferred("run")
func run()->void:
	for biome in range(3):
		check(Art.obstacle(biome).get_size()==Vector2(64,64),"native obstacle size")
		for column in [0,1,2,3,5]:
			var texture:Texture2D=Art.tile(biome,column)
			check(texture.get_size()==Vector2(64,32),"native diamond size")
			check(texture==Art.tile(biome,column),"cached texture identity")
			var pixels:Image=texture.get_image()
			check(pixels.get_pixel(0,0).a==0,"source margins excluded")
			check(pixels.get_pixel(32,16).a>0.9,"opaque floor center")
		check(Art.tile(biome,0).get_image().get_data()!=Art.tile(biome,1).get_image().get_data(),
			"floor variety")
	for column in [0,3]:
		check(Art.wall(column).get_size()==Vector2(32,48),"wall pixel density")
	var layer=Layer.new();root.add_child(layer)
	var viewport:=Rect2(0,0,390,400);var rows:Dictionary={}
	# Use cells from the middle of an 80x80 world. The layer must not depend on
	# the removed 8x8 room model.
	for y in range(33,48):
		for x in range(33,48):
			var world:=Vector2i(x,y);var local:=world-Vector2i(33,33)
			rows[world]={"position":world,
				"polygon":ProjectionRules.polygon(local,viewport,15),
				"visibility_state":"MEMORY" if x==47 else "VISIBLE",
				"terrain":{"terrain_id":"shallow_water" if y==40 else "stone_floor"},
				"tile_spec":{"visible":true,"is_wall":x==40 and y==40}}
	for theme in ["dungeon","cave","forest"]:
		layer.synchronize(rows,viewport,Vector2i(33,33),15,theme)
		await process_frame
		check(layer.biome==Art.biome_index(theme),"theme bound to renderer")
		check(layer.cells.size()==225,"full-map camera window reaches tile renderer")
		check(layer.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"nearest pixel sampling")
	layer.queue_free();await process_frame
	var grid=Grid.new();grid.size=Vector2(390,390);root.add_child(grid)
	var integration_cells:Array=[]
	for y in range(15):
		for x in range(15):
			var actors:Array=[]
			if Vector2i(x,y)==Vector2i(7,7):
				actors.append({"entity_id":1,"position":[7,7],"logical_position":[7,7],
					"faction_id":"party","species_id":"human","is_protagonist":true,
					"life_state":"ACTIVE","health":10,"max_health":10})
			integration_cells.append({"position":[x,y],
				"terrain_id":"wall" if Vector2i(x,y)==Vector2i(8,7) else "floor",
				"visibility_state":"VISIBLE","actors":actors})
	grid.set_observation({"width":80,"height":80,"cells":integration_cells})
	grid.set_graphics_mode(Grid.GRAPHICS_MODE_TACTICAL)
	grid.set_hero_centered_view(Vector2i(7,7),15,1)
	await process_frame;await process_frame
	var rendered_layer=grid.get_node_or_null("TacticalTerrain")
	check(rendered_layer!=null and rendered_layer.visible,
		"live isometric grid owns the visible tile layer")
	check(bool(grid.fixed_front_actor_render_spec({"entity_id":1,"position":[7,7],
		"logical_position":[7,7],"faction_id":"party","species_id":"human",
		"is_protagonist":true,"life_state":"ACTIVE"}).get("uses_sprite",false)),
		"live isometric grid renders actors as pixel sprites")
	if rendered_layer!=null:
		check(rendered_layer.cells.any(func(row):return bool(row.get("tile_spec",{}).get(
			"is_wall",false))),"live tile layer receives authoritative wall cells")
	grid.queue_free();await process_frame
	print("HANDCRAFTED_TILE_ASSETS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
