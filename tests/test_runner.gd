extends SceneTree

const StateValidationSuite = preload("res://tests/test_state_validation.gd")
const GameplaySuite = preload("res://tests/test_gameplay.gd")
const WorkshopCameraSuite = preload("res://tests/test_workshop_camera.gd")
const BossBattleSuite = preload("res://tests/test_boss_battle.gd")
const BossBattle3DSuite = preload("res://tests/test_boss_battle_3d.gd")


func _init() -> void:
	var failures: Array[String] = []
	var state_suite = StateValidationSuite.new()
	failures.append_array(state_suite.run())
	var gameplay_suite = GameplaySuite.new()
	failures.append_array(gameplay_suite.run())
	var camera_suite = WorkshopCameraSuite.new()
	failures.append_array(camera_suite.run())
	var boss_battle_suite = BossBattleSuite.new()
	failures.append_array(boss_battle_suite.run())
	var boss_battle_3d_suite = BossBattle3DSuite.new()
	failures.append_array(boss_battle_3d_suite.run())

	if failures.is_empty():
		print("TESTS PASSED (legacy systems and 2D/3D boss combat prototypes)")
		quit(0)
		return

	printerr("M0 TESTS FAILED: %d failure(s)" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)
