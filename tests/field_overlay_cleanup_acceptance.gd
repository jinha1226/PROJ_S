extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]

func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)

func _init()->void:call_deferred("run")

func run()->void:
	root.size=Vector2i(390,844)
	var session=Session.new()
	var ui=Sandbox.new();root.add_child(ui)
	ui.initialize_for_headless_test(session,false)
	for index in range(4):await process_frame
	ui._refresh()
	check(not ui.nearby_npc_panel.visible,
		"top-left nearby NPC detail card stays removed")
	var spec:Dictionary=ui.grid.monster_list_draw_spec()
	check(not bool(spec.get("visible",true)) and spec.get("rows",[]).is_empty(),
		"bottom-right monster and NPC list stays removed")
	check(str(spec.get("mouse_filter",""))=="IGNORE" \
			and ui.grid.nearby_actor_at_pointer(Vector2(1,1))==-1,
		"retired list reserves no map pointer area")
	ui.queue_free();await process_frame
	print("FIELD_OVERLAY_CLEANUP ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
