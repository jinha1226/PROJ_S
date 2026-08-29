extends SceneTree

const LabScene = preload("res://playtest/duel_decision_lab.tscn")
const FakeSimulator = preload("res://tests/duel_decision_ui_fake.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in [Vector2i(360, 640), Vector2i(450, 800)]:
		root.size = viewport_size
		var lab = LabScene.instantiate()
		lab.initialize_for_headless_test(FakeSimulator.new(22002))
		root.add_child(lab)
		lab.set_anchors_preset(Control.PRESET_TOP_LEFT)
		lab.size = viewport_size
		await process_frame
		await process_frame
		_check_layout(lab, viewport_size, "actor-a")
		lab._select_actor_index(1)
		await process_frame
		_check_layout(lab, viewport_size, "actor-b")
		lab._step()
		lab._show_events()
		await process_frame
		_check_layout(lab, viewport_size, "events")
		if lab.simulator.step_calls != 1:
			failures.append("%s step was not exactly once" % viewport_size)
		lab.free()
	if failures.is_empty():
		print("DUEL_DECISION_LAYOUT_SMOKE PASS 360x640 450x800")
	else:
		for failure in failures:
			printerr("DUEL_DECISION_LAYOUT_SMOKE FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)


func _check_layout(lab: Control, viewport_size: Vector2i, mode: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var visible_rows: Array[Control] = []
	for child in lab.root_layout.get_children():
		if not child is Control or not child.visible:
			continue
		visible_rows.append(child)
		var rect: Rect2 = child.get_global_rect()
		if rect.position.x < -0.5 or rect.position.y < -0.5 \
				or rect.end.x > bounds.end.x + 0.5 or rect.end.y > bounds.end.y + 0.5:
			failures.append("%s %s overflow %s %s" % [viewport_size, mode, child.name, rect])
	for index in range(visible_rows.size() - 1):
		if visible_rows[index].get_global_rect().intersection(visible_rows[index + 1].get_global_rect()).has_area():
			failures.append("%s %s overlap %s/%s" % [viewport_size, mode,
				visible_rows[index].name, visible_rows[index + 1].name])
	var local_grid_rect: Rect2 = lab.grid.grid_rect()
	var global_grid_rect := Rect2(lab.grid.get_global_rect().position + local_grid_rect.position,
		local_grid_rect.size)
	if not bounds.encloses(global_grid_rect):
		failures.append("%s %s grid overflow %s" % [viewport_size, mode, global_grid_rect])
	if lab.grid.cell_size_px() < 15.0:
		failures.append("%s %s cell too small %.2f" % [viewport_size, mode, lab.grid.cell_size_px()])
	if lab.grid.actor_count() != 2:
		failures.append("%s %s actor count is not two" % [viewport_size, mode])
	for button in [lab.step_button, lab.restart_button, lab.actor_buttons[0], lab.actor_buttons[1], lab.event_button]:
		if button.size.y < 43.5:
			failures.append("%s %s touch target too short %s %.1f" % [
				viewport_size, mode, button.name, button.size.y])
