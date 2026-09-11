extends SceneTree

const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array[String]=[]

func check(value:bool,label:String)->void:
	if not value:failures.append(label);printerr("FAIL ",label)

func _init()->void:call_deferred("run")

func run()->void:
	var center:=Grid.radial_darkness_sample(0.0,false,1)
	var middle:=Grid.radial_darkness_sample(3.0,false,1)
	var edge:=Grid.radial_darkness_sample(6.0,false,1)
	var torch_center:=Grid.radial_darkness_sample(0.0,true,1)
	var torch_middle:=Grid.radial_darkness_sample(3.0,true,1)
	check(center.alpha<middle.alpha and middle.alpha<edge.alpha,
		"unlit darkness fades monotonically")
	check(torch_center.alpha<center.alpha and torch_middle.alpha<middle.alpha,
		"held torch brightens a circular area")
	check(torch_center.radius_cells>center.radius_cells,
		"held torch widens the soft light radius")
	check(center.alpha<=0.05 and edge.alpha<=0.62,
		"floor one ambient darkness stays gently brighter")
	var forward_distance:=Grid.directional_darkness_distance(Vector2(4,0),Vector2i.RIGHT,false)
	var side_distance:=Grid.directional_darkness_distance(Vector2(0,4),Vector2i.RIGHT,false)
	var rear_distance:=Grid.directional_darkness_distance(Vector2(-4,0),Vector2i.RIGHT,false)
	check(is_equal_approx(forward_distance,side_distance)
		and is_equal_approx(side_distance,rear_distance),
		"unlit darkness is character-centred and radial")
	check(is_equal_approx(Grid.directional_darkness_distance(Vector2(4,0),Vector2i.RIGHT,true),
		Grid.directional_darkness_distance(Vector2(-4,0),Vector2i.RIGHT,true)),
		"held torch keeps a circular light pool")
	for viewport in [360,450]:
		root.size=Vector2i(viewport,viewport);root.content_scale_size=root.size
		var grid=Grid.new();grid.size=Vector2(viewport,viewport);root.add_child(grid)
		var cells:Array=[]
		for y in range(15):
			for x in range(15):
				var state:="VISIBLE" if x<=7 else ("MEMORY" if x<=12 else "UNSEEN")
				var actors:Array=[]
				if x==7 and y==7:
					actors.append({"entity_id":77,"faction_id":"party","species_id":"human",
						"roster_slot":0,"is_protagonist":true,
						"equipment_visual":{"off_hand_torch_lit":true}})
				cells.append({"position":[x,y],
					"terrain_id":"wall" if x==10 and y==7 else "floor",
					"visibility_state":state,"actors":actors})
		grid.set_observation({"width":15,"height":15,"phase":{"floor_index":1},
			"cells":cells})
		grid.set_hero_centered_view(Vector2i(7,7),15,77)
		var specs:=grid.radial_darkness_draw_specs()
		check(specs.size()>Grid.RADIAL_DARKNESS_SEGMENTS,
			"%dpx uses multi-ring radial sampling"%viewport)
		check(specs.all(func(row):return Vector2i(row.sample_cell).x<=7),
			"%dpx dynamic darkness and light stay inside current sight"%viewport)
		check(not bool(grid.torch_light_draw_spec(Vector2i(10,7),260).active),
			"%dpx remembered wall torch keeps no live light pool"%viewport)
		check(grid._presentation_light_line_open(Vector2i(10,7),Vector2i(8,7)),
			"%dpx wall torch reaches known terrain along open LOS"%viewport)
		var blocker:Dictionary=grid._cells["9:7"]
		blocker["terrain_id"]="wall";grid._cells["9:7"]=blocker
		check(not grid._presentation_light_line_open(Vector2i(10,7),Vector2i(8,7)),
			"%dpx wall blocks remembered torch light"%viewport)
		check(specs.all(func(row):return row.polygon.size()>=3),
			"%dpx radial pieces are drawable polygons"%viewport)
		var mesh:ArrayMesh=grid._build_radial_darkness_mesh()
		check(mesh!=null and mesh.get_surface_count()==1,
			"%dpx radial gradient batches into one draw surface"%viewport)
		var los_builds:=int(grid.torch_cache_stats().los_build_count)
		for repeat in range(4):
			grid.radial_darkness_draw_specs()
			grid.torch_light_draw_spec(Vector2i(7,7),repeat*260)
		check(int(grid.torch_cache_stats().los_build_count)==los_builds,
			"%dpx redraws reuse cached light LOS"%viewport)
		if "--capture" in OS.get_cmdline_user_args():
			grid.queue_redraw();await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"/tmp/radial-darkness-%d.png"%viewport)
		grid.queue_free();await process_frame
	print("RADIAL DARKNESS: ",failures)
	quit(0 if failures.is_empty() else 1)
