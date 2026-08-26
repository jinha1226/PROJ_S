class_name TestWorkshopCamera
extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	failures.clear()
	_test_fit_zoom_anchor_pan_and_reset()
	return failures


func _test_fit_zoom_anchor_pan_and_reset() -> void:
	var world := WorkshopWorld.new()
	world.size = Vector2(720.0, 700.0)
	world._configure_camera()
	_expect_true(world._min_zoom > 0.0, "CAMERA-001 fit zoom is positive")
	_expect_close(world._zoom, world._min_zoom, "CAMERA-001 starts at overview fit")
	_expect_vector_close(world._camera_center, WorkshopWorld.WORLD_SIZE * 0.5, "CAMERA-001 starts centered")

	var focal_point := Vector2(300.0, 300.0)
	var anchor_before := world._screen_to_world(focal_point)
	world._zoom_at(focal_point, world._min_zoom * 2.0)
	var anchor_after := world._screen_to_world(focal_point)
	_expect_vector_close(anchor_after, anchor_before, "CAMERA-002 zoom preserves focal world point")

	var center_before_pan: Vector2 = world._camera_center
	world._pan_camera(Vector2(40.0, 0.0))
	_expect_true(world._camera_center.x < center_before_pan.x, "CAMERA-003 drag pans camera")

	world._reset_camera()
	_expect_close(world._zoom, world._min_zoom, "CAMERA-004 reset restores overview fit")
	_expect_vector_close(world._camera_center, WorkshopWorld.WORLD_SIZE * 0.5, "CAMERA-004 reset recenters map")

	var first_touch := InputEventScreenTouch.new()
	first_touch.index = 0
	first_touch.position = Vector2(250.0, 300.0)
	first_touch.pressed = true
	world._handle_screen_touch(first_touch)
	var second_touch := InputEventScreenTouch.new()
	second_touch.index = 1
	second_touch.position = Vector2(450.0, 300.0)
	second_touch.pressed = true
	world._handle_screen_touch(second_touch)
	var pinch_drag := InputEventScreenDrag.new()
	pinch_drag.index = 1
	pinch_drag.position = Vector2(510.0, 300.0)
	pinch_drag.relative = Vector2(60.0, 0.0)
	world._handle_screen_drag(pinch_drag)
	_expect_true(world._zoom > world._min_zoom, "CAMERA-005 two-touch pinch changes zoom")
	world.free()


func _expect_true(condition: bool, label: String) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _expect_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_vector_close(actual: Vector2, expected: Vector2, label: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
