class_name TestBossBattle
extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	failures.clear()
	_test_dynamic_camera()
	_test_auto_attack()
	_test_perfect_dodge()
	_test_part_break_changes_pattern_pool()
	return failures


func _fixture() -> BossBattleView:
	var battle := BossBattleView.new()
	battle.size = Vector2(720.0, 1280.0)
	battle._restart_battle()
	return battle


func _test_dynamic_camera() -> void:
	var battle := _fixture()
	battle._player_position = Vector2(410.0, 1260.0)
	for _index: int in range(120):
		battle._update_camera(1.0 / 60.0)
	var far_zoom: float = battle._camera_zoom
	battle._player_position = Vector2(410.0, 505.0)
	for _index: int in range(120):
		battle._update_camera(1.0 / 60.0)
	_expect_true(battle._camera_zoom > far_zoom + 0.20, "BOSS-CAMERA-001 close range zooms in")
	battle.free()


func _test_auto_attack() -> void:
	var battle := _fixture()
	battle._selected_part = &"core"
	var target: Vector2 = battle._part_position(&"core")
	battle._player_position = target + Vector2(0.0, BossBattleView.ATTACK_RANGE - 12.0)
	var health_before: float = battle._boss_health
	battle._update_auto_attack(0.01)
	for _index: int in range(8):
		battle._update_auto_attack(0.04)
	_expect_true(battle._boss_health < health_before, "BOSS-COMBAT-001 entering range triggers auto attack")
	battle.free()


func _test_perfect_dodge() -> void:
	var battle := _fixture()
	battle._player_health = 100.0
	battle._dodge_timer = BossBattleView.DODGE_DURATION - 0.08
	battle._perfect_dodge_used = false
	battle._try_boss_hit(30.0)
	_expect_close(battle._player_health, 100.0, "BOSS-COMBAT-002 dodge prevents damage")
	_expect_true(battle._counter_bonus, "BOSS-COMBAT-002 precise dodge primes counter")
	battle.free()


func _test_part_break_changes_pattern_pool() -> void:
	var battle := _fixture()
	battle._damage_boss_part(&"left_arm", 999.0)
	_expect_true(not battle._part_is_alive(&"left_arm"), "BOSS-PART-001 arm can be destroyed")
	battle._boss_pattern_index = 0
	battle._begin_next_pattern()
	_expect_true(battle._boss_pattern != &"SWEEP", "BOSS-PART-001 broken sweep arm removes sweep pattern")
	battle.free()


func _expect_true(condition: bool, label: String) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _expect_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
