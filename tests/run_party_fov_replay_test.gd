extends SceneTree

func _init()->void:
	var script=load("res://tests/test_party_playtest_session.gd")
	var test_case=script.new()
	var completed=test_case.test_fov_memory_is_reconstructed_purely_from_hero_move_history_and_replays()
	if completed and test_case.errors.is_empty():
		print("PASS focused party FOV memory replay")
		quit(0);return
	for error in test_case.errors:print("FAIL focused party FOV memory replay -- ",error)
	quit(1)
