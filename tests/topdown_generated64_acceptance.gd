extends SceneTree
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
var failures:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init()->void:call_deferred("run")
func run()->void:
	var visible:={"terrain_id":"floor","feature_id":"","visibility_state":"VISIBLE"}
	var floor:Dictionary=Tiles.tile_spec(visible,Vector2i(4,5),1)
	check(floor.asset_family==Tiles.FAMILY and floor.texture.get_size()==Vector2(64,64),
		"ordinary floor uses the generated native 64px family")
	for terrain in ["rubble","shallow_water","deep_water","lava","metal","spikes",
			"pillar","low_cover","crate"]:
		var row:=visible.duplicate();row.terrain_id=terrain
		var spec:Dictionary=Tiles.tile_spec(row,Vector2i(3,6),1)
		check(spec.texture.get_size()==Vector2(64,64),"%s resolves to native 64px art"%terrain)
	var wall_one:Dictionary=Tiles.tile_spec({"terrain_id":"wall",
		"visibility_state":"VISIBLE"},Vector2i(2,2),1)
	var wall_two:Dictionary=Tiles.tile_spec({"terrain_id":"wall",
		"visibility_state":"VISIBLE"},Vector2i(2,2),2)
	check(wall_one.sprite_key=="wall_00","unexposed wall uses joined stone cap")
	check(wall_two.sprite_key=="wall_00","approved stone pack is shared across floors")
	var north_south:={"N":visible,"S":visible}
	for state in ["closed","open"]:
		var door:Dictionary=Tiles.tile_spec({"terrain_id":"door_"+state,
			"visibility_state":"VISIBLE"},Vector2i(5,5),1,north_south)
		check(door.sprite_key=="door_"+state,
			"%s door uses state and corridor orientation"%state)
	var exit_row:=visible.duplicate();exit_row.feature_id="floor_transition_portal"
	check(Tiles.tile_spec(exit_row,Vector2i(7,7),1).sprite_key=="stairs_down",
		"floor transition uses generated descending stairs")
	var memory:=visible.duplicate();memory.visibility_state="MEMORY"
	var unseen:=visible.duplicate();unseen.visibility_state="UNSEEN"
	check(Tiles.tile_spec(memory,Vector2i.ZERO,1).visible \
		and not Tiles.tile_spec(unseen,Vector2i.ZERO,1).visible,
		"memory retains art and unseen remains hidden")
	print("TOPDOWN_GENERATED64 ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
