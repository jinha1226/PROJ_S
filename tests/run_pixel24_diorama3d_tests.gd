extends SceneTree

const LabScene = preload("res://playtest/pixel24_diorama3d_lab.tscn")
const Suite = preload("res://tests/test_pixel24_diorama3d.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(432, 560))
	var lab := LabScene.instantiate() as Pixel24Diorama3DLab
	root.add_child(lab)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var suite := Suite.new()
	var passed: bool = suite.run(lab)
	if passed:
		print("PASS LW-D3D-01 focused tests")
	else:
		printerr("FAIL LW-D3D-01 focused tests: %d failure(s)" % suite.failures.size())
	lab.queue_free()
	quit(0 if passed else 1)
