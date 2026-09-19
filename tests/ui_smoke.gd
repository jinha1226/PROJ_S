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
	event.position = scene.minimap.room_rect(target).get_center()
	scene.minimap._gui_input(event)
	await process_frame
	if not scene.map_popup.visible or scene.session.room != 0:
		failed = true; push_error("minimap must expand without moving")
	if scene.minimap.size.x > 100 or scene.board.size.x < 340:
		failed = true; push_error("minimap must stay small and board must use full width")
	scene.board.geometry()
	if absf(scene.board.size.x-scene.size.x) > 1 or absf(scene.board.half_width*16-scene.size.x) > 1:
		failed = true; push_error("board and projected room must fill screen width")
	for y in range(8):
		for x in range(8):
			var cell := Vector2i(x,y)
			if scene.board.cell_at(scene.board.cell_center(cell)) != cell:
				failed = true; push_error("isometric hit test failed")
	if scene.skill_buttons.size() != 6 or scene.item_buttons.size() != 6 or scene.portrait_buttons.size() != 3:
		failed = true; push_error("v4 slot counts")
	for node in scene.item_buttons + scene.skill_buttons:
		if node.size.x < 48 or node.size.y < 48 or not scene.get_global_rect().encloses(node.get_global_rect()):
			failed = true; push_error("touch target outside screen or too small")
	event.position = scene.map_view.room_rect(target).get_center()
	scene.map_view._gui_input(event)
	await process_frame
	if scene.session.room != target: failed = true; push_error("map click did not travel")
	if scene.map_popup.visible: failed = true; push_error("map must close after selecting a room")
	Fixture.clear_battle(scene.session)
	var door: Vector2i = scene.session.doors().keys()[0]
	var destination: int = scene.session.doors()[door]
	scene.on_cell(door)
	await process_frame
	if scene.session.room != destination: failed = true; push_error("door click did not travel")
	Fixture.reach(scene.session,Fixture.kind_id(scene.session,"battle"))
	scene.refresh()
	await process_frame
	if scene.session.phase == "BATTLE":
		var control: Button = scene.end_turn_button
		if control == null or control.size.x < 96 or control.size.y < 48 or not scene.board.get_global_rect().encloses(control.get_global_rect()):
			failed = true; push_error("end turn must be inside board at bottom right")
		for y in range(8):
			for x in range(8):
				if control.get_rect().has_point(scene.board.cell_center(Vector2i(x,y))):
					failed = true; push_error("end turn covers a playable tile")
		var round_before: int = scene.session.round_number
		control.pressed.emit()
		await process_frame
		if scene.session.phase == "BATTLE" and scene.session.round_number != round_before + 1:
			failed = true; push_error("end turn did not advance one round")
		var before: int = scene.session.room
		scene.show_map()
		scene.on_room(scene.session.rooms[before].links[0])
		if scene.session.room != before: failed = true; push_error("expanded map bypassed combat lock")
		scene.map_popup.hide()
	scene.on_cell(Vector2i(2,2))
	if scene.session.phase == "BATTLE": scene.run_action(scene.session.end_round)
	await process_frame
	scene.run_action(scene.session.retreat)
	await process_frame
	print("UI smoke: mobile v4 slots, touch targets, 64 isometric cells, map travel and combat lock")
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)
