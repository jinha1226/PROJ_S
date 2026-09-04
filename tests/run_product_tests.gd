extends SceneTree


# CI gates the surfaces a player actually reaches. Long-running balance models,
# seed matrices, standalone LAB scenes, and low-level simulation suites remain
# available for focused local work through run_tests.gd.
const PRODUCT_TEST_FILES := [
	"test_dark_fantasy_ascii_ui.gd",
	"test_deterministic_dungeon_map.gd",
	"test_item_ascii_presentation.gd",
	"test_melee_vfx_overlay.gd",
	"test_monster_awareness_ui.gd",
	"test_opening_fixed_event.gd",
	"test_party_ascii_visual.gd",
	"test_party_auto_explore.gd",
	"test_party_mvp_run.gd",
	"test_party_playtest_session.gd",
	"test_party_playtest_ui.gd",
	"test_product_tab_attack.gd",
	"test_progression_vertical_slice.gd",
	"test_weapon_vertical_slice.gd",
]


func _init() -> void:
	var total := 0
	var failed := 0
	var skipped := 0
	var directory := DirAccess.open("res://tests")
	if directory == null:
		printerr("FAIL: could not open res://tests")
		quit(1)
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) \
				or file == "test_case.gd":
			continue
		if file not in PRODUCT_TEST_FILES:
			skipped += 1
			continue
		var script = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			printerr("FAIL %s :: script failed to load" % file)
			failed += 1
			continue
		var probe = script.new()
		for method in probe.get_method_list():
			if not method.name.begins_with("test_"):
				continue
			total += 1
			var test_case = script.new()
			var completed = test_case.call(method.name)
			if typeof(completed) != TYPE_BOOL:
				test_case.errors.append("test did not return explicit true completion")
			elif completed == false and test_case.errors.is_empty():
				test_case.errors.append("test returned false without a recorded assertion")
			if test_case.errors.is_empty():
				print("PASS %s :: %s" % [file, method.name])
			else:
				failed += 1
				for error in test_case.errors:
					print("FAIL %s :: %s -- %s" % [file, method.name, error])
	if total == 0:
		printerr("FAIL: zero product tests discovered")
		failed += 1
	print("---- %d product tests, %d failed, %d non-product files skipped ----" % [
		total, failed, skipped])
	quit(1 if failed > 0 else 0)
