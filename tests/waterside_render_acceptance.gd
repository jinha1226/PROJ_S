extends SceneTree
const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var cells:Array=[]
	for y in range(15):
		for x in range(15):cells.append({"position":[x,y],"terrain_id":"shallow_water","visibility_state":"VISIBLE","actors":[]})
	for animated in [true,false]:
		var grid=Grid.new();grid.size=Vector2(345,345);grid.animate_passive_terrain=animated;root.add_child(grid)
		grid.set_observation({"width":15,"height":15,"cells":cells})
		var stats:Dictionary=grid.torch_cache_stats()
		check(bool(stats.timer_redraw_enabled)==animated,"water-only idle redraw matches presentation policy")
		var motion:Dictionary=grid.environment_motion_draw_spec(Vector2i(3,3),900)
		check(motion.visible and bool(motion.animated)==animated,"water remains visible without animation")
		if not animated:
			check(grid._torch_timer.is_stopped(),"water does not schedule full-map idle repaints")
			cells[48].fire_intensity=60
			grid.set_observation({"width":15,"height":15,"cells":cells})
			check(grid.torch_cache_stats().timer_redraw_enabled,"real fire retains animation")
			check(grid.environment_motion_draw_spec(Vector2i(3,3),900).animated,"fire on water still animates")
		grid.queue_free();await process_frame
	print("WATERSIDE RENDER: ",failures)
	quit(0 if failures.is_empty() else 1)
