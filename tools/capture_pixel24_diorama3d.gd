extends SceneTree

const LabScene = preload("res://playtest/pixel24_diorama3d_lab.tscn")
const OUTPUT_DIR := "res://docs/results/pixel24-diorama3d"

var lab: Pixel24Diorama3DLab
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(432, 560))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	lab = LabScene.instantiate() as Pixel24Diorama3DLab
	root.add_child(lab)
	await _settle(3)

	lab.reset_demo()
	var default_image := await _capture("topview_432.png")
	if default_image.is_empty():
		for failure in failures:
			printerr("FAIL ", failure)
		lab.queue_free()
		quit(1)
		return
	_save_nearest(default_image, "topview_nearest_3x.png", 3)
	_save_actor_comparison(default_image)
	_save_building_crop(default_image)

	lab.set_sword_equipped(false)
	await _capture("topview_sword_off_432.png")
	lab.set_sword_equipped(true)

	lab.set_evidence_pitch(true)
	await _capture("pitched_volume_evidence.png")
	lab.set_evidence_pitch(false)

	lab.reset_demo()
	lab.try_move(Vector2i.UP)
	var canopy_image := await _capture("canopy_occlusion_432.png")
	_save_nearest(canopy_image, "canopy_occlusion_nearest_3x.png", 3)

	lab.reset_demo()
	await _settle(2)
	if not lab.is_vertical_camera():
		failures.append("capture did not leave the lab in the default vertical camera")
	var metrics := await _collect_metrics()
	_write_json("render_metrics.json", metrics)
	_write_json("source_mapping.json", lab.source_mapping())

	if failures.is_empty():
		print("PASS LW-D3D-01 capture: %s" % OUTPUT_DIR)
	else:
		for failure in failures:
			printerr("FAIL ", failure)
	lab.queue_free()
	quit(0 if failures.is_empty() else 1)


func _settle(frames: int) -> void:
	for _index in range(frames):
		RenderingServer.force_draw(false, 0.0)
		await process_frame


func _capture(filename: String) -> Image:
	await _settle(2)
	var texture: ViewportTexture = lab.lab_viewport.get_texture()
	if texture == null:
		failures.append("%s has no viewport texture; use a real display/rendering driver" % filename)
		return Image.new()
	var image := texture.get_image()
	if image == null:
		failures.append("%s could not be read back from the viewport" % filename)
		return Image.new()
	if image.is_empty() or image.get_size() != Vector2i(432, 432):
		failures.append("%s was not a rendered 432x432 image" % filename)
		return image
	var error: Error = image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		failures.append("could not save %s: %s" % [filename, error_string(error)])
	return image


func _save_nearest(source: Image, filename: String, scale: int) -> void:
	if source.is_empty():
		return
	var enlarged := source.duplicate()
	enlarged.resize(source.get_width() * scale, source.get_height() * scale,
		Image.INTERPOLATE_NEAREST)
	var error: Error = enlarged.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		failures.append("could not save %s: %s" % [filename, error_string(error)])


func _actor_cell_region(render: Image, cell: Vector2i) -> Image:
	var center := lab.cell_to_screen(cell).round()
	var rect := Rect2i(Vector2i(center) - Vector2i(12, 12), Vector2i(24, 24))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, render.get_size()))
	return render.get_region(rect)


func _save_actor_comparison(render: Image) -> void:
	var sources := [
		"res://assets/pixel24_v3/runtime/actors/base/human.png",
		"res://assets/pixel24_v3/runtime/actors/base/dwarf.png",
		"res://assets/pixel24_v3/runtime/monsters/goblin.png",
	]
	var cells := [lab.HUMAN_START, lab.DWARF_CELL, lab.GOBLIN_CELL]
	var comparison := Image.create(80, 52, false, Image.FORMAT_RGBA8)
	comparison.fill(Color("#0c1010"))
	for index in range(3):
		var source_texture := load(sources[index]) as Texture2D
		if source_texture == null:
			failures.append("could not load actor comparison source %s" % sources[index])
			continue
		var source := source_texture.get_image()
		comparison.blit_rect(source, Rect2i(Vector2i.ZERO, Vector2i(24, 24)),
			Vector2i(index * 28, 0))
		var rendered := _actor_cell_region(render, cells[index])
		comparison.blit_rect(rendered, Rect2i(Vector2i.ZERO, rendered.get_size()),
			Vector2i(index * 28, 28))
	var error: Error = comparison.save_png(OUTPUT_DIR.path_join("actors_2d3d_native24.png"))
	if error != OK:
		failures.append("could not save native actor comparison")
	_save_nearest(comparison, "actors_2d3d_nearest_6x.png", 6)


func _save_building_crop(render: Image) -> void:
	var points := [
		lab.cell_to_screen(Vector2i(1, 1)),
		lab.cell_to_screen(Vector2i(14, 5)),
	]
	var left := mini(int(points[0].x), int(points[1].x)) - 12
	var top := mini(int(points[0].y), int(points[1].y)) - 12
	var right := maxi(int(points[0].x), int(points[1].x)) + 12
	var bottom := maxi(int(points[0].y), int(points[1].y)) + 12
	var rect := Rect2i(left, top, right - left, bottom - top)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, render.get_size()))
	var crop := render.get_region(rect)
	var error: Error = crop.save_png(OUTPUT_DIR.path_join("buildings_topview.png"))
	if error != OK:
		failures.append("could not save building crop")
	_save_nearest(crop, "buildings_topview_nearest_3x.png", 3)


func _collect_metrics() -> Dictionary:
	var samples_ms: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _index in range(60):
		await process_frame
		var now := Time.get_ticks_usec()
		samples_ms.append(float(now - previous) / 1000.0)
		previous = now
	samples_ms.sort()
	var sum := 0.0
	for sample in samples_ms:
		sum += sample
	var projection := lab.projection_measurement()
	var roundtrip: Vector2i = projection.roundtrip_cell
	projection["roundtrip_cell"] = [roundtrip.x, roundtrip.y]
	var contract := lab.demo_contract()
	var forward: Vector3 = contract.camera_forward
	contract["camera_forward"] = [forward.x, forward.y, forward.z]
	contract["render_size"] = [432, 432]
	contract["human_cell"] = [lab.human_cell.x, lab.human_cell.y]
	contract["storage_footprint"] = [lab.STORAGE_FOOTPRINT.x, lab.STORAGE_FOOTPRINT.y]
	contract["armory_footprint"] = [lab.ARMORY_FOOTPRINT.x, lab.ARMORY_FOOTPRINT.y]
	return {
		"experiment_id": "LW-D3D-01",
		"godot_version": Engine.get_version_info().string,
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"contract": contract,
		"projection": projection,
		"render_info": {
			"objects_in_frame": RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			"primitives_in_frame": RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"draw_calls_in_frame": RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		},
		"frame_interval_sample": {
			"scope": "60 process-frame wall intervals during X11 software-render capture; not GPU time",
			"mean_ms": sum / float(samples_ms.size()),
			"p95_ms": samples_ms[int(floor(float(samples_ms.size() - 1) * 0.95))],
			"min_ms": samples_ms.front(),
			"max_ms": samples_ms.back(),
		},
		"camera_left_vertical_after_capture": lab.is_vertical_camera(),
	}


func _write_json(filename: String, value: Variant) -> void:
	var file := FileAccess.open(OUTPUT_DIR.path_join(filename), FileAccess.WRITE)
	if file == null:
		failures.append("could not open %s for writing" % filename)
		return
	file.store_string(JSON.stringify(value, "  ") + "\n")
