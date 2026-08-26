class_name Simulation
extends RefCounted

const TICKS_PER_SECOND := 10
const TICK_SECONDS := 0.1

var state: GameState
var interaction_paused: bool = false


func _init(p_state: GameState = null) -> void:
	state = p_state


func set_state(p_state: GameState) -> void:
	state = p_state


func set_interaction_pause(paused: bool) -> void:
	interaction_paused = paused


func advance_ticks(tick_count: int) -> CommandResult:
	if state == null:
		return CommandResult.failure(&"STATE_NOT_READY")
	if tick_count < 0:
		return CommandResult.failure(&"INVALID_TICK_COUNT")
	if interaction_paused:
		return CommandResult.success({"advanced_ticks": 0})

	for _tick: int in range(tick_count):
		_advance_one_tick()
	return CommandResult.success({"advanced_ticks": tick_count})


func _advance_one_tick() -> void:
	# M0 only owns deterministic time. Gameplay systems are attached in later milestones.
	state.simulation_tick += 1
