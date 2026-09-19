extends SceneTree
const Fixture = preload("res://tests/map_fixture.gd")
var failed := false

func _initialize() -> void:
	call_deferred("exercise")

func exercise() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.run_action(scene.session.depart)
	await process_frame
	var target: int = scene.session.rooms[0].links[0]
	var event := InputEventMouseButton.new()
	event.pressed = true; event.button_index = MOUSE_BUTTON_LEFT
	event.position = scene.map_view.room_rect(target).get_center()
	scene.map_view._gui_input(event)
	await process_frame
	if scene.session.room != target: failed = true; push_error("map click did not travel")
	Fixture.clear_battle(scene.session)
	var door: Vector2i = scene.session.doors().keys()[0]
	var destination: int = scene.session.doors()[door]
	scene.on_cell(door)
	await process_frame
	if scene.session.room != destination: failed = true; push_error("door click did not travel")
	Fixture.reach(scene.session,Fixture.kind_id(scene.session,"battle"))
	scene.refresh()
	await process_frame
	scene.on_cell(Vector2i(2,2))
	if scene.session.phase == "BATTLE": scene.run_action(scene.session.end_round)
	await process_frame
	scene.run_action(scene.session.retreat)
	await process_frame
	print("UI smoke: map hit-test, room door input, board and return")
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)
