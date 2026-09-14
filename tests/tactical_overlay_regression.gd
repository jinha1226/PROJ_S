extends SceneTree
const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var grid=Grid.new();grid.size=Vector2(390,480);root.add_child(grid)
	grid.set_graphics_mode(Grid.GRAPHICS_MODE_TACTICAL)
	grid.world_grid_size=Vector2i(30,30)
	grid.set_hero_centered_view(Vector2i(10,10),13,-1,0)
	for y in range(4,17):
		for x in range(4,17):grid._cells["%d:%d"%[x,y]]={"position":[x,y],"terrain_id":"stone_floor","visibility_state":"VISIBLE"}
	for cell in [Vector2i(10,10),Vector2i(11,10),Vector2i(10,11)]:
		var p:PackedVector2Array=grid.cell_overlay_polygon(cell)
		var tile:PackedVector2Array=grid.world_cell_polygon(cell)
		var center:Vector2=grid.world_to_pixel_center(cell)
		check(p.size()==4,"four polygon corners")
		for i in range(4):check(p[i].is_equal_approx(tile[i].lerp(center,0.08)),"same inset tile projection")
		check(is_equal_approx(p[0].x,p[2].x) and is_equal_approx(p[1].y,p[3].y),"diamond axes")
		check(is_equal_approx(p[1].distance_to(p[3]),2*p[0].distance_to(p[2])),"2:1 diamond")
	grid.set_route_overlay([[10,10],[11,10],[11,11]])
	var route:Dictionary=grid.route_draw_spec()
	check(route.draw_tile_cards and route.render_style=="TACTICAL_CELLS","tactical route rendering")
	check(route.tiles[1].polygon==grid.cell_overlay_polygon(Vector2i(11,10)),"route uses shared polygon")
	var intents:Array=[{"type":"MOVE","from_position":[10,10],"destination":[11,10],"source_color":"#e8bd68"},
		{"type":"MELEE","from_position":[11,10],"target_position":[10,10],"source_color":"#ff756b","draw_connector":true}]
	for intent in intents:check(grid.intent_draw_spec(intent).visible,"visible intent")
	check(not grid.intent_draw_spec({"type":"MOVE","from_position":[10,10],"destination":[29,29]}).visible,"offscreen intent suppressed")
	grid.set_intent_overlays(intents);grid.set_skill_reach_cells([[10,10],[11,10]])
	grid.queue_redraw()
	for i in range(3):await process_frame
	grid.set_graphics_mode(Grid.GRAPHICS_MODE_FLAT_2D)
	check(not grid.route_draw_spec().draw_tile_cards,"flat route compatibility")
	grid.queue_free();await process_frame
	print("TACTICAL OVERLAYS: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
