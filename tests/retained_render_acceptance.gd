extends SceneTree
const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func settle(grid)->void:
	grid.queue_redraw()
	for i in range(3):await process_frame
func mesh_parity(grid,label:String)->void:
	var mesh:ArrayMesh=grid._build_radial_darkness_mesh()
	check(mesh!=null,label+" mesh exists")
	if mesh==null:return
	var data:=mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=data[Mesh.ARRAY_VERTEX]
	var colors:PackedColorArray=data[Mesh.ARRAY_COLOR]
	var max_error:=0.0
	var cpu_error:=0.0
	for i in range(vertices.size()):
		var expected:Color=grid._darkness_vertex_color(grid._composite_darkness_at(Vector2(vertices[i].x,vertices[i].y)))
		max_error=maxf(max_error,absf(expected.a-colors[i].a))
		var actual:Color=grid._cached_darkness_vertex_color(Vector2(vertices[i].x,vertices[i].y))
		cpu_error=maxf(cpu_error,absf(expected.a-actual.a))
	check(cpu_error<0.00001,label+" CPU samples match reference: "+str(cpu_error))
	# ArrayMesh stores vertex colors at 8-bit precision on the GL backend.
	check(max_error<=1.0/255.0+0.00001,label+" mesh stays within color quantization: "+str(max_error))
func run()->void:
	root.size=Vector2i(390,390)
	root.content_scale_size=Vector2i(390,390)
	if "--capture" in OS.get_cmdline_user_args():DisplayServer.window_set_size(Vector2i(390,390))
	var grid=Grid.new();grid.size=Vector2(390,390);root.add_child(grid)
	grid.animate_passive_terrain=false
	var cells:Array=[]
	for y in range(25):
		for x in range(25):
			cells.append({"position":[x,y],"terrain_id":"wall" if x==7 and y%5!=0 else "floor",
				"visibility_state":"VISIBLE" if x<16 else "MEMORY","actors":[],
				"feature_id":"landmark_camp" if x==12 and y==12 else ""})
	var observation:={"width":25,"height":25,"phase":{"floor_index":1},"cells":cells}
	grid.set_observation(observation);grid.set_hero_centered_view(Vector2i(12,12),15,77)
	await settle(grid)
	check(grid._retained_terrain!=null,"product uses retained terrain child")
	if grid._retained_terrain==null:quit(1);return
	var layer=grid._retained_terrain
	var rebuilds:int=layer.rebuild_count;var meshes:int=grid._darkness_mesh_builds
	var rays:int=grid._presentation_light_los_build_count
	await settle(grid)
	check(layer.rebuild_count==rebuilds and grid._darkness_mesh_builds==meshes,"animation-only redraw retains tile commands and fog mesh")
	mesh_parity(grid,"initial lights")
	# A nonvisual scalar observation change rebuilds projection, not tile/fog.
	cells[10*25+10]["probe_revision"]=1
	meshes=grid._darkness_mesh_builds
	grid.set_observation(observation);await settle(grid)
	check(layer.rebuild_count==rebuilds,"nonvisual observation retains chunks")
	check(grid._darkness_mesh_builds==meshes,"nonvisual observation retains darkness")
	check(grid._presentation_light_los_build_count==rays,"unchanged topology retains light rays")
	cells[10*25+10]["terrain_id"]="wood_floor"
	grid.set_observation(observation);await settle(grid)
	check(layer.rebuild_count==rebuilds+1,"one tile edit redraws one 4x4 chunk")
	check(grid._presentation_light_los_build_count==rays,"nonblocking material change retains rays")
	# Local fog change should only resample vertices in the affected cell; mesh
	# upload is still batched. Moving hero/zooming must fully invalidate samples.
	var samples:int=grid._darkness_sample_builds
	cells[10*25+10]["visibility_state"]="MEMORY"
	grid.set_observation(observation);await settle(grid)
	var partial:int=grid._darkness_sample_builds-samples
	check(partial>0 and partial<100,"one-cell fog change resamples locally: "+str(partial))
	mesh_parity(grid,"one-cell memory")
	cells[12*25+11]["terrain_id"]="wall"
	grid.set_observation(observation);await settle(grid)
	check(grid._presentation_light_los_build_count>rays,"local wall change invalidates affected sources")
	mesh_parity(grid,"wall occlusion")
	cells[12*25+12]["feature_id"]="";cells[12*25+12]["fire_intensity"]=30
	grid.set_observation(observation);await settle(grid);mesh_parity(grid,"campfire becomes weaker fire")
	rebuilds=layer.rebuild_count
	grid.set_hero_centered_view(Vector2i(13,12),15,77);await settle(grid)
	check(layer.rebuild_count-rebuilds<layer.chunks.size(),"camera shift retains interior chunks")
	mesh_parity(grid,"camera moves")
	grid.size=Vector2(450,360);await settle(grid);mesh_parity(grid,"resize")
	grid.size=Vector2(390,390);observation.phase.floor_index=2
	grid.set_observation(observation);await settle(grid);mesh_parity(grid,"floor theme")
	meshes=grid._darkness_mesh_builds;rebuilds=layer.rebuild_count
	cells[12*25+13]["actors"]=[{"entity_id":77,"faction_id":"party","species_id":"human",
		"roster_slot":0,"is_protagonist":true,"equipment_visual":{"off_hand_torch_lit":true}}]
	grid.set_observation(observation);await settle(grid);mesh_parity(grid,"equip handheld torch")
	check(grid._darkness_mesh_builds>meshes and layer.rebuild_count==rebuilds,"equipment light updates fog without rebuilding tiles")
	# At identical state, compare actual GPU output to the previous immediate
	# terrain painter. Flicker and actor animations are absent in this fixture.
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var retained:Image=root.get_texture().get_image()
		retained.save_png("/tmp/retained-terrain.png")
		grid._retain_terrain_commands=false;await settle(grid)
		await RenderingServer.frame_post_draw
		var immediate:Image=root.get_texture().get_image()
		immediate.save_png("/tmp/immediate-terrain.png")
		var error:=0.0;var changed:=0
		for y in range(retained.get_height()):
			for x in range(retained.get_width()):
				var a:=retained.get_pixel(x,y);var b:=immediate.get_pixel(x,y)
				var delta:float=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
				error+=delta
				if delta>0.02:changed+=1
		var pixels:=retained.get_width()*retained.get_height()
		print("TERRAIN GPU mean_error=",error/pixels," changed_fraction=",float(changed)/pixels)
		check(error/pixels<0.005 and float(changed)/pixels<0.03,"retained painter visually matches immediate painter")
	grid.queue_free();await process_frame
	print("RETAINED RENDER: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
