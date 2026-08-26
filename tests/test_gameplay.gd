class_name TestGameplay
extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	failures.clear()
	_test_assign_001_teach_logging()
	_test_assign_invalid_target()
	_test_reassignment_preserves_skill()
	_test_job_reward_only_on_completion()
	_test_facility_slot_is_deterministic()
	_test_normal_coaching_once_per_cycle()
	_test_perfect_coaching_completes_next_tick()
	_test_proficiency_level_up()
	_test_gameplay_tick_determinism()
	return failures


func _test_assign_001_teach_logging() -> void:
	var session := _fixture_session()
	var result := session.teach(&"slime_000001", &"forest", &"job_logging")
	var slime := session.state.slimes[&"slime_000001"] as SlimeState
	var forest := session.state.facilities[&"forest"] as FacilityState
	_expect_true(result.ok, "ASSIGN-001 teach succeeds")
	_expect_true(slime.skill_memories.has(&"logging"), "ASSIGN-001 logging learned")
	_expect_equal(slime.routine.size(), 1, "ASSIGN-001 routine created")
	_expect_equal(str(slime.current_job.phase), "IDLE", "ASSIGN-001 no slot reserved in command")
	_expect_equal(forest.active_worker_ids.size(), 0, "ASSIGN-001 no immediate reservation")
	session.advance_ticks(1)
	_expect_equal(str(slime.current_job.phase), "MOVING", "ASSIGN-001 starts next tick")
	_expect_equal(forest.active_worker_ids.size(), 1, "ASSIGN-001 worker slot reserved")


func _test_assign_invalid_target() -> void:
	var session := _fixture_session()
	session.state.unlocked_content_ids["ark"] = true
	var before_hash := session.state.canonical_hash()
	var result := session.teach(&"slime_000001", &"ark", &"job_logging")
	_expect_true(not result.ok, "ASSIGN-002 invalid target fails")
	_expect_equal(str(result.code), "INVALID_TARGET", "ASSIGN-002 error code")
	_expect_equal(session.state.canonical_hash(), before_hash, "ASSIGN-002 state unchanged")


func _test_reassignment_preserves_skill() -> void:
	var session := _fixture_session()
	session.teach(&"slime_000001", &"forest", &"job_logging")
	var slime := session.state.slimes[&"slime_000001"] as SlimeState
	var progress := slime.skill_memories[&"logging"] as SkillProgress
	progress.level = 3
	progress.xp = 15
	session.advance_ticks(5)
	var result := session.teach(&"slime_000001", &"forest", &"job_logging")
	_expect_true(result.ok, "ASSIGN-004 reassignment succeeds")
	_expect_equal(progress.level, 3, "ASSIGN-004 level preserved")
	_expect_equal(progress.xp, 15, "ASSIGN-004 XP preserved")
	_expect_equal(session.inventory_system.get_amount(&"town_storage", &"wood"), 0, "ASSIGN-004 cancelled cycle gives no output")


func _test_job_reward_only_on_completion() -> void:
	var session := _fixture_session()
	session.teach(&"slime_000001", &"forest", &"job_logging")
	session.advance_ticks(12)
	var slime := session.state.slimes[&"slime_000001"] as SlimeState
	var progress := slime.skill_memories[&"logging"] as SkillProgress
	_expect_equal(session.inventory_system.get_amount(&"town_storage", &"wood"), 0, "JOB-001 no early wood")
	_expect_equal(progress.xp, 0, "JOB-001 no early XP")
	_expect_equal(slime.division_meter, 12, "JOB-001 no early division progress")
	session.advance_ticks(1)
	_expect_equal(session.inventory_system.get_amount(&"town_storage", &"wood"), 1, "JOB-002 wood once")
	_expect_equal(progress.xp, 1, "JOB-002 passive XP once")
	_expect_equal(progress.total_cycles, 1, "JOB-002 cycle count once")
	_expect_equal(slime.division_meter, 13, "JOB-002 division progress once")
	session.advance_ticks(1)
	_expect_equal(session.inventory_system.get_amount(&"town_storage", &"wood"), 1, "JOB-002 no duplicate output")


func _test_facility_slot_is_deterministic() -> void:
	var session := _fixture_session()
	var second_id := session.state.allocate_slime_id()
	var second := SlimeState.new(second_id)
	second.display_name = "Pipi"
	second.division_meter = 12
	session.state.slimes[second_id] = second
	session.teach(&"slime_000001", &"forest", &"job_logging")
	session.teach(second_id, &"forest", &"job_logging")
	session.advance_ticks(1)
	var first := session.state.slimes[&"slime_000001"] as SlimeState
	var forest := session.state.facilities[&"forest"] as FacilityState
	_expect_equal(str(first.current_job.phase), "MOVING", "JOB-004 lower ID wins slot")
	_expect_equal(str(second.current_job.phase), "BLOCKED", "JOB-004 second slime waits")
	_expect_equal(str(second.current_job.blocked_reason), "FACILITY_FULL", "JOB-004 blocked reason")
	_expect_equal(forest.active_worker_ids.size(), 1, "JOB-004 slot not exceeded")


func _test_normal_coaching_once_per_cycle() -> void:
	var session := _fixture_session()
	session.teach(&"slime_000001", &"forest", &"job_logging")
	session.advance_ticks(3)
	var slime := session.state.slimes[&"slime_000001"] as SlimeState
	var cycle_id := slime.current_job.cycle_id
	var result := session.coach(slime.id, cycle_id)
	var progress := slime.skill_memories[&"logging"] as SkillProgress
	_expect_true(result.ok, "COACH-001 normal coaching succeeds")
	_expect_equal(str(result.payload["result_type"]), "NORMAL", "COACH-001 normal result")
	_expect_equal(slime.current_job.elapsed_ticks, 2, "COACH-001 adds configured progress")
	_expect_equal(progress.xp, 1, "COACH-001 grants XP")
	var repeated := session.coach(slime.id, cycle_id)
	_expect_true(not repeated.ok, "COACH-003 repeated coaching fails")
	_expect_equal(str(repeated.code), "COACHING_ALREADY_USED", "COACH-003 error code")
	_expect_equal(progress.xp, 1, "COACH-003 no repeated XP")


func _test_perfect_coaching_completes_next_tick() -> void:
	var session := _fixture_session()
	session.teach(&"slime_000001", &"forest", &"job_logging")
	session.advance_ticks(3)
	var slime := session.state.slimes[&"slime_000001"] as SlimeState
	slime.current_job.elapsed_ticks = slime.current_job.duration_ticks - 2
	var result := session.coach(slime.id, slime.current_job.cycle_id)
	_expect_equal(str(result.payload["result_type"]), "PERFECT", "COACH-002 perfect result")
	_expect_true(slime.current_job.completion_requested, "COACH-002 completion requested")
	_expect_equal(session.inventory_system.get_amount(&"town_storage", &"wood"), 0, "COACH-002 no same-command reward")
	session.advance_ticks(1)
	_expect_equal(session.inventory_system.get_amount(&"town_storage", &"wood"), 1, "COACH-002 completes next tick")


func _test_proficiency_level_up() -> void:
	var session := _fixture_session()
	session.teach(&"slime_000001", &"forest", &"job_logging")
	var slime := session.state.slimes[&"slime_000001"] as SlimeState
	var progress := slime.skill_memories[&"logging"] as SkillProgress
	progress.xp = 19
	session.proficiency_system.grant_xp(slime.id, &"logging", 1)
	_expect_equal(progress.level, 2, "PROF-001 level up")
	_expect_equal(progress.xp, 0, "PROF-001 XP remainder")


func _test_gameplay_tick_determinism() -> void:
	var session_a := _fixture_session()
	var session_b := _fixture_session()
	session_a.teach(&"slime_000001", &"forest", &"job_logging")
	session_b.teach(&"slime_000001", &"forest", &"job_logging")
	session_a.advance_ticks(80)
	for _index: int in range(8):
		session_b.advance_ticks(10)
	_expect_equal(session_a.state.canonical_hash(), session_b.state.canonical_hash(), "SIM gameplay split ticks")


func _fixture_session() -> GameSession:
	var session := GameSession.new()
	session.new_game()
	var job := session.content_registry.get_job(&"job_logging")
	job.base_duration_ticks = 10
	job.movement_duration_ticks = 2
	job.min_duration_ticks = 1
	job.normal_coaching_progress_ratio = 0.20
	job.perfect_window_ticks = 2
	return session


func _expect_true(condition: bool, label: String) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
