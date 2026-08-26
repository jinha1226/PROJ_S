class_name TestBackviewDuel
extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	failures.clear()
	_test_perspective_projection()
	_test_four_direction_movement()
	_test_attack_range_and_posture()
	_test_deflect_rules()
	_test_position_evades_thrust()
	_test_posture_break_deathblow()
	return failures


func _fixture() -> BackviewDuelView:
	var duel := BackviewDuelView.new()
	duel.size = Vector2(720.0, 1280.0)
	duel._restart_battle()
	return duel


func _test_perspective_projection() -> void:
	var duel := _fixture()
	duel._player_depth = 0.30
	var far_y := duel._player_screen_position().y
	var far_height := duel._player_sprite_height()
	duel._player_depth = 0.90
	_expect_true(duel._player_screen_position().y > far_y, "DUEL-PROJECTION-001 near player renders lower")
	_expect_true(duel._player_sprite_height() > far_height, "DUEL-PROJECTION-002 near player renders larger")
	duel.free()


func _test_four_direction_movement() -> void:
	var duel := _fixture()
	duel._player_x = 0.0
	duel._player_depth = 0.70
	duel._move_input = Vector2(0.8, -0.6).normalized()
	duel._update_player(0.25)
	_expect_true(duel._player_x > 0.0, "DUEL-MOVE-001 lateral input strafes")
	_expect_true(duel._player_depth < 0.70, "DUEL-MOVE-002 forward input approaches boss")
	duel.free()


func _test_attack_range_and_posture() -> void:
	var duel := _fixture()
	duel._player_depth = 0.46
	duel._player_x = 0.0
	duel._try_attack()
	duel._update_player_actions(BackviewDuelView.ATTACK_HIT_TIME + 0.01)
	_expect_close(duel._boss_health, 95.0, "DUEL-ATTACK-001 close attack damages vitality")
	_expect_close(duel._boss_posture, 13.0, "DUEL-ATTACK-002 close attack builds posture")
	duel._restart_battle()
	duel._player_depth = 0.82
	duel._try_attack()
	duel._update_player_actions(BackviewDuelView.ATTACK_HIT_TIME + 0.01)
	_expect_close(duel._boss_health, 100.0, "DUEL-ATTACK-003 distant attack misses")
	duel.free()


func _test_deflect_rules() -> void:
	var duel := _fixture()
	duel._deflect_timer = 0.30
	duel._deflect_elapsed = 0.10
	duel._receive_boss_strike(25.0, true)
	_expect_close(duel._player_health, 100.0, "DUEL-DEFLECT-001 perfect deflect prevents vitality damage")
	_expect_close(duel._boss_posture, 22.0, "DUEL-DEFLECT-002 perfect deflect pressures boss")
	duel._restart_battle()
	duel._deflect_timer = 0.30
	duel._deflect_elapsed = 0.10
	duel._receive_boss_strike(25.0, false)
	_expect_close(duel._player_health, 75.0, "DUEL-DEFLECT-003 unblockable attack defeats deflect")
	duel.free()


func _test_position_evades_thrust() -> void:
	var duel := _fixture()
	duel._boss_pattern = &"THRUST"
	duel._boss_locked_x = 0.0
	duel._player_x = 0.55
	duel._player_depth = 0.48
	duel._resolve_boss_strike()
	_expect_close(duel._player_health, 100.0, "DUEL-SPACING-001 lateral movement evades locked thrust")
	duel.free()


func _test_posture_break_deathblow() -> void:
	var duel := _fixture()
	duel._add_boss_posture(100.0)
	_expect_equal(str(duel._boss_state), "BROKEN", "DUEL-POSTURE-001 full posture opens deathblow")
	duel._player_depth = 0.44
	duel._player_x = 0.0
	duel._resolve_player_attack()
	_expect_close(duel._boss_health, 66.0, "DUEL-POSTURE-002 deathblow damages boss vitality")
	duel.free()


func _expect_true(condition: bool, label: String) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _expect_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
