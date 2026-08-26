class_name TestBossBattle3D
extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	failures.clear()
	var battle := BossBattle3D.new()
	battle._ready()
	_test_scene_bootstrap(battle)
	_test_damage_transfer(battle)
	_test_part_break_changes_moveset(battle)
	_test_parry_rules(battle)
	_test_active_pattern_timer(battle)
	battle.free()
	return failures


func _test_scene_bootstrap(battle: BossBattle3D) -> void:
	_expect_true(battle._camera != null and battle._camera.current, "BOSS3D-SCENE-001 active camera exists")
	_expect_true(battle._hud != null, "BOSS3D-SCENE-002 portrait HUD exists")
	_expect_true(battle._player_root != null, "BOSS3D-SCENE-003 player model exists")
	_expect_true(battle._boss_root != null, "BOSS3D-SCENE-004 boss model exists")


func _test_damage_transfer(battle: BossBattle3D) -> void:
	battle._restart_battle()
	battle._damage_part(&"core", 18.0)
	_expect_close(battle._boss_health, 302.0, "BOSS3D-DAMAGE-001 core sends full damage to global HP")
	battle._restart_battle()
	battle._damage_part(&"weapon_arm", 20.0)
	_expect_close(float(battle._part_health[&"weapon_arm"]), 55.0, "BOSS3D-DAMAGE-002 arm has local HP")
	_expect_close(battle._boss_health, 308.0, "BOSS3D-DAMAGE-003 arm sends 60 percent to global HP")


func _test_part_break_changes_moveset(battle: BossBattle3D) -> void:
	battle._restart_battle()
	battle._damage_part(&"weapon_arm", 75.0)
	_expect_true(not battle._part_alive(&"weapon_arm"), "BOSS3D-PART-001 hook arm can break")
	_expect_close(battle._boss_health, 257.0, "BOSS3D-PART-002 break adds global HP damage")
	_expect_true(not battle._boss_weapon.visible, "BOSS3D-PART-003 broken hook disappears")
	battle._boss_pattern_index = 0
	battle._begin_pattern()
	_expect_true(battle._boss_pattern != &"SWEEP", "BOSS3D-PART-004 broken hook removes sweep")


func _test_parry_rules(battle: BossBattle3D) -> void:
	battle._restart_battle()
	battle._parry_active = 0.2
	battle._try_boss_damage(24.0, true)
	_expect_close(battle._player_health, 100.0, "BOSS3D-PARRY-001 sweep can be parried")
	_expect_true(battle._counter_bonus, "BOSS3D-PARRY-002 successful parry primes counter")
	battle._restart_battle()
	battle._parry_active = 0.2
	battle._try_boss_damage(33.0, false)
	_expect_close(battle._player_health, 67.0, "BOSS3D-PARRY-003 slam ignores parry")


func _test_active_pattern_timer(battle: BossBattle3D) -> void:
	battle._restart_battle()
	battle._boss_state = &"ACTIVE"
	battle._boss_pattern = &"CHARGE"
	battle._boss_timer = 0.62
	battle._boss_locked_direction = Vector3(0.0, 0.0, 1.0)
	battle._update_boss(0.10)
	_expect_close(battle._boss_timer, 0.52, "BOSS3D-PATTERN-001 active timer advances once per frame")


func _expect_true(condition: bool, label: String) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _expect_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
