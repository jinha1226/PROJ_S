extends SceneTree

const Grid=preload("res://playtest/party_grid_view.gd")
var failures:Array[String]=[]

func check(value:bool,label:String)->void:
	if not value:failures.append(label);printerr("FAIL ",label)

func cells_with_target_state(state:String)->Array:
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor",
				"visibility_state":state if Vector2i(x,y)==Vector2i(8,7) else "VISIBLE",
				"actors":[]})
	return cells

func _init()->void:call_deferred("run")

func run()->void:
	var grid=Grid.new();grid.size=Vector2(345,345)
	grid.set_observation({"width":15,"height":15,
		"cells":cells_with_target_state("VISIBLE")})
	grid.set_hero_centered_view(Vector2i(7,7),15,1)
	var visible_amount:={"effect_id":"visible:amount","event_id":1,"order":0,
		"kind":"FLOATING_AMOUNT","world_position":[8,7],"text":"-7"}
	check(grid.play_effects([visible_amount])==1,
		"VISIBLE combat amount enters the active presentation list")
	var active:Dictionary=grid._active_visual_effects[0]
	check(bool(grid.visual_effect_draw_spec(active).visible),
		"VISIBLE combat amount receives a drawable spec")

	grid.set_observation({"width":15,"height":15,
		"cells":cells_with_target_state("MEMORY")})
	check(not bool(grid.visual_effect_draw_spec(active).visible),
		"active combat amount disappears immediately when its cell becomes MEMORY")
	var memory_rows:Array=[
		{"effect_id":"memory:amount","event_id":2,"order":0,
			"kind":"FLOATING_AMOUNT","world_position":[8,7],"text":"-9"},
		{"effect_id":"memory:miss","event_id":3,"order":1,
			"kind":"MISS","world_position":[8,7],"text":"빗나감"},
		{"effect_id":"memory:death","event_id":4,"order":2,
			"kind":"DEATH","world_position":[8,7],"text":"g"},
		{"effect_id":"memory:melee","event_id":5,"order":3,"kind":"MELEE_VFX",
			"world_position":[8,7],"attacker_grid_pos":[7,7],"target_grid_pos":[8,7]}]
	check(grid.play_effects(memory_rows)==0 and grid._active_visual_effects.size()==1 \
			and grid.melee_vfx.active_effect_count()==0,
		"MEMORY combat effects never enter either generic or melee active lists")
	check(memory_rows.all(func(row):return grid.has_played_effect(str(row.effect_id))),
		"hidden committed effects are consumed once instead of replaying after discovery")

	grid.set_observation({"width":15,"height":15,
		"cells":cells_with_target_state("UNSEEN")})
	var unseen:={"effect_id":"unseen:amount","event_id":6,"order":0,
		"kind":"FLOATING_AMOUNT","world_position":[8,7],"text":"-11"}
	check(grid.play_effects([unseen])==0 and grid.has_played_effect("unseen:amount"),
		"UNSEEN combat amount is suppressed and consumed")
	grid.free()
	print("COMBAT VFX VISIBILITY: ",failures)
	quit(0 if failures.is_empty() else 1)
