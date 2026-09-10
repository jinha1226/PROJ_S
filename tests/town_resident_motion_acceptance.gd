extends SceneTree
const Motion=preload("res://playtest/town_resident_motion.gd")
const Map=preload("res://playtest/base_settlement_view.gd")
const Service=preload("res://playtest/town_life_service.gd")
var failures:Array[String]=[]
var picked:=-1
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var overview:Dictionary={"phase":"TOWN","settlement":Service._public_map(),"residents":[]}
	for id in range(1,17):overview.residents.append({"entity_id":id,"tile":[11,5],"species_id":"human","display_name":"주민%d"%id})
	overview.residents[15].is_player=true
	var before:Dictionary=overview.duplicate(true)
	var motion=Motion.new();motion.configure(overview)
	check(motion.actors.size()==16,"all residents have ambient positions")
	var initial:Dictionary=motion.actors.duplicate(true)
	var visited:Dictionary={}
	for i in range(400):
		motion.tick(0.1)
		var occupied:Dictionary={}
		for id in motion.actors:
			var row:Dictionary=motion.actors[id]
			check(motion.walkable.has(row.from) and motion.walkable.has(row.to),"resident stays on walkable ground")
			check(not occupied.has(row.to),"destinations do not overlap")
			occupied[row.to]=true
			if row.from!=initial[id].from:visited[id]=true
	check(visited.size()>=12,"residents explore instead of clustering")
	check(motion.actors[16].from==initial[16].from,"player is not autonomously moved")
	check(overview==before,"ambient movement never mutates authoritative observer")
	var retained:Dictionary=motion.actors.duplicate(true);motion.configure(overview)
	check(motion.actors==retained,"same overview refresh retains positions")
	var map=Map.new();map.fit_map_height=true;map.size=Vector2(390,360);root.add_child(map);map.present(overview,"");map.set_process(false)
	for i in range(80):map.resident_motion.tick(0.1)
	map.resident_selected.connect(func(id):picked=id)
	var row:Dictionary=overview.residents[0]
	var pos:Vector2=map.resident_center(row)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=pos
		root.push_input(event,true)
	check(picked==1,"click follows moving visible NPC")
	map._pointer_down=true
	retained=map.resident_motion.actors.duplicate(true);map._process(0.1)
	check(map.resident_motion.actors==retained,"NPC pauses while player presses map")
	map.queue_free();await process_frame
	print("TOWN RESIDENT MOTION: ",failures)
	quit(0 if failures.is_empty() else 1)
