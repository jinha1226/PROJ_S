class_name RunnerCombatTests
extends RefCounted

const CombatModel = preload("res://game/runner/runner_combat_model.gd")
const RUN_CLIP_PATH := "res://assets/mocap/cmu/09_06_fast_run_2d.json"


func run() -> Array[String]:
	var failures: Array[String] = []
	var combat = CombatModel.new()
	if not combat.request_attack():
		failures.append("attack should start while running")
	combat.advance(0.14)
	if not combat.is_attack_active():
		failures.append("attack should expose a deterministic active window")
	var first_attack_id: int = combat.attack_id
	combat.advance(0.1)
	if not combat.request_attack():
		failures.append("attack should queue during the cancel window")
	combat.advance(0.2)
	if combat.attack_id <= first_attack_id or combat.combo_step != 1:
		failures.append("queued attack should advance the combo")

	combat.reset()
	if not combat.request_dodge():
		failures.append("dodge should start while running")
	combat.advance(0.12)
	if not combat.is_invulnerable():
		failures.append("dodge should become invulnerable after startup")
	if combat.receive_hit():
		failures.append("invulnerable dodge should reject damage")
	combat.advance(0.4)
	if combat.state != CombatModel.State.RUN:
		failures.append("dodge should return to running")

	combat.reset()
	for index in range(4):
		combat.receive_hit()
		if index < 3:
			combat.advance(CombatModel.HURT_DURATION)
	if combat.state != CombatModel.State.DEAD:
		failures.append("four hits should end the run")

	var file := FileAccess.open(RUN_CLIP_PATH, FileAccess.READ)
	if file == null:
		failures.append("runner mocap clip should exist")
		return failures
	var clip: Variant = JSON.parse_string(file.get_as_text())
	if not clip is Dictionary:
		failures.append("runner mocap clip should parse")
		return failures
	var frames: Array = clip.get("frames", [])
	var roots: Array = clip.get("root_forward", [])
	if frames.size() < 20 or frames.size() != roots.size():
		failures.append("runner mocap should contain a complete stride and matching root data")
	elif absf(float(roots[-1]) - float(roots[0])) < 2.5:
		failures.append("runner mocap should preserve enough forward travel to synchronize foot speed")
	return failures
