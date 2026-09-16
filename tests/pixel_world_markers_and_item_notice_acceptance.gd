extends SceneTree

const GridView=preload("res://playtest/party_grid_view.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

var failures:Array[String]=[]

func check(ok:bool,label:String)->void:
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)

func _init()->void:
	call_deferred("run")

func run()->void:
	var grid:=GridView.new()
	var style:Dictionary=grid.world_marker_style_spec()
	check(style.primitive=="PIXEL_CORNERS","world markers use pixel corners")
	check(style.pickup=="PIXEL_PLUS_BADGE","ground items use a pixel plus badge")
	check(bool(style.pixel_snap),"world marker coordinates are pixel snapped")
	check(not bool(style.antialiased),"world marker edges disable antialiasing")
	check(bool(style.cell_shaped_targets),"tile targets follow the projected cell")
	grid.free()

	var sandbox:=Sandbox.new()
	var notice:String=sandbox.ground_item_arrival_notice([
		{"label":"치유 물약"},{"display_name":"화염 두루마리"},{"label":"치유 물약"}])
	check("발밑 아이템 3개" in notice,"arrival notice reports the ground item count")
	check("치유 물약" in notice and "화염 두루마리" in notice,
		"arrival notice names every visible item type")
	check(notice.count("치유 물약")==1,"arrival notice avoids duplicate item names")
	sandbox.free()

	print("PIXEL_WORLD_MARKERS_AND_ITEM_NOTICE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
