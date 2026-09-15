extends SceneTree
const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array=[]
func _initialize():call_deferred("run")
func check(value:bool,label:String):
	if not value:failures.append(label);push_error(label)
func run():
	var grid=Grid.new();root.add_child(grid);grid.size=Vector2(360,360)
	var cell:Dictionary={"position":[2,2],"terrain":"floor","visibility_state":"VISIBLE","actors":[],"ground_item_glyph":"*"}
	var observation:Dictionary={"grid_size":[8,8],"cells":[cell]}
	grid.set_observation(observation)
	check(not grid.ground_item_draw_spec(Vector2i(2,2)).is_empty(),"item initially drawn")
	cell.ground_item_glyph=""
	grid.set_observation(observation)
	check(not grid.ground_item_draw_spec(Vector2i(2,2)).get("visible",false),"pickup removes marker")
	grid.set_observation({"grid_size":[8,8],"cells":[]})
	grid.set_observation(observation)
	check(not grid.ground_item_draw_spec(Vector2i(2,2)).get("visible",false),"revisit cannot restore marker")
	grid.queue_free()
	print("SRPG_ITEM_PROJECTION ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
