extends SceneTree
const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var grid=Grid.new();grid.size=Vector2(390,500)
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			var actors:Array=[]
			if y==7 and x in range(5,10):
				var id:=x-4
				actors.append({"entity_id":id,"is_protagonist":id==1,"roster_slot":id-1,
					"is_enemy":id>=4,"health":40,"display_name":"Actor%d"%id})
			cells.append({"position":[x,y],"terrain_id":"floor","visibility_state":"VISIBLE","actors":actors})
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid.set_view_window(15);grid.set_selection(1,4)
	grid.set_party_focus({"command_id":"ATTACK_TARGET","target_id":5,"event_id":7})
	grid.set_intent_overlays([
		{"actor_id":2,"type":"MELEE","target_id":5},
		{"actor_id":3,"type":"SKILL","target_id":4},
		{"actor_id":4,"type":"MELEE","target_id":1}])
	var targets:=grid.selection_overlay_draw_specs().filter(func(row):return row.kind=="TARGET")
	check(targets.size()==2,"split targets both marked")
	for row in targets:
		if row.entity_id==4:check(row.attackers==["동료2","나"],"shared target combines attackers")
		if row.entity_id==5:check(row.attackers==["동료1"],"independent companion marked")
	check(grid.party_focus_draw_spec().entity_id==5,"party focus remains independent")
	grid.set_intent_overlays([{"actor_id":2,"type":"SKILL","target_id":1},
		{"actor_id":3,"type":"HOLD","target_id":4}])
	targets=grid.selection_overlay_draw_specs().filter(func(row):return row.kind=="TARGET")
	check(targets.size()==1 and targets[0].attackers==["나"],"healing and hold do not retain attack markers")
	for cell in cells:
		if cell.position==[8,7]:cell.visibility_state="MEMORY"
	grid.set_observation({"width":15,"height":15,"cells":cells})
	check(grid.selection_overlay_draw_specs().all(func(row):return row.kind!="TARGET"),"unseen target disappears")
	grid.free()
	print("INDIVIDUAL TARGET MARKERS: ",failures)
	quit(0 if failures.is_empty() else 1)
