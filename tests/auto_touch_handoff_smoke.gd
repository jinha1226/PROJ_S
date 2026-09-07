extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Fixtures=preload("res://tests/test_party_auto_explore.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _run()->void:
	root.size=Vector2i(360,640)
	var fixtures=Fixtures.new()
	var session=fixtures._safe_product_session(44)
	var sandbox=Sandbox.new()
	sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session)
	root.add_child(sandbox)
	await process_frame
	await process_frame
	var started:Dictionary=session.start_auto_explore()
	if not started.get("advanced",false):failures.append("AUTO fixture did not move")
	sandbox._refresh_continuous_exploration_surface(session.party_status(),true)
	await process_frame
	var hero:Array=session.party_status().protagonist_position
	var origin:=Vector2i(hero[0],hero[1])
	var target:=Vector2i(-1,-1)
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var candidate:Vector2i=origin+offset
		if session.preview_exploration_route(candidate).get("accepted",false):
			target=candidate
			break
	if target==Vector2i(-1,-1):
		printerr("No manual target");quit(1);return
	var press:=InputEventScreenTouch.new()
	press.index=0;press.pressed=true
	press.position=sandbox.grid.world_to_pixel_center(target)
	sandbox.grid._gui_input(press)
	if not sandbox.grid.pointer_gesture_state().active:failures.append("tap not captured")
	# Reproduce a deferred presentation refresh landing between touch-down/up.
	sandbox._refresh()
	if not sandbox.grid.pointer_gesture_state().active:failures.append("refresh erased tap")
	var release:=InputEventScreenTouch.new()
	release.index=0;release.position=press.position
	sandbox.grid._gui_input(release)
	var after:Array=session.party_status().protagonist_position
	if Vector2i(after[0],after[1])!=target:failures.append("manual move not committed")
	if session.auto_explore_state().running:failures.append("AUTO still running")
	await process_frame
	if sandbox._refresh_after_pointer:failures.append("refresh not resumed")
	sandbox.queue_free()
	await process_frame
	for failure in failures:printerr(failure)
	print("AUTO to touch handoff: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
