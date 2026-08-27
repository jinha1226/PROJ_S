extends SceneTree

const Scene = preload("res://playtest/playtest_sandbox.tscn")
const Session = preload("res://playtest/playtest_session.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for viewport_size in [Vector2i(450, 800), Vector2i(360, 640)]:
		root.size = viewport_size
		var sandbox = Scene.instantiate()
		root.add_child(sandbox)
		sandbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
		sandbox.size = viewport_size
		sandbox.session = Session.new()
		await process_frame
		await process_frame
		_check_layout(sandbox, viewport_size, "closed")
		sandbox._toggle_event_log()
		await process_frame
		_check_layout(sandbox, viewport_size, "event-log")
		var log_time: int = sandbox.session.lab_status().world_time
		sandbox._advance(1)
		if sandbox.session.lab_status().world_time <= log_time:
			failures.append("%s event log blocked progress" % viewport_size)
		sandbox._toggle_drawer()
		await process_frame
		_check_layout(sandbox, viewport_size, "drawer")
		var before: int = sandbox.session.lab_status().world_time
		sandbox._toggle_auto(); sandbox._advance(1); sandbox.auto_timer.timeout.emit()
		if sandbox.session.lab_status().world_time != before or sandbox.auto_running:
			failures.append("%s drawer allowed progress" % viewport_size)
		sandbox.free()
	if failures.is_empty(): print("UI_LAYOUT_SMOKE PASS 450x800 360x640")
	else:
		for failure in failures: printerr("UI_LAYOUT_SMOKE FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)

func _check_layout(sandbox: Control, viewport_size: Vector2i, label: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var layout: Control = sandbox.get_node("LabLayout")
	var visible_rows: Array[Control] = []
	for child in layout.get_children():
		if child is Control and child.visible:
			visible_rows.append(child)
			var rect: Rect2 = child.get_global_rect()
			if rect.position.x < -0.5 or rect.position.y < -0.5 \
					or rect.end.x > bounds.end.x + 0.5 or rect.end.y > bounds.end.y + 0.5:
				failures.append("%s %s overflow %s %s" % [viewport_size, label, child.name, rect])
	for i in range(visible_rows.size()):
		for j in range(i + 1, visible_rows.size()):
			if visible_rows[i].get_global_rect().intersection(visible_rows[j].get_global_rect()).has_area():
				failures.append("%s %s overlap %s/%s" % [viewport_size, label,
					visible_rows[i].name, visible_rows[j].name])
