class_name RunnerCombatModel
extends RefCounted

enum State {
	RUN,
	ATTACK,
	DODGE,
	HURT,
	DEAD,
}

const ATTACK_DURATIONS := [0.38, 0.42, 0.48]
const ATTACK_WINDOWS := [Vector2(0.12, 0.23), Vector2(0.13, 0.26), Vector2(0.16, 0.31)]
const ATTACK_REACH := [118.0, 128.0, 150.0]
const DODGE_DURATION := 0.46
const DODGE_INVULNERABLE := Vector2(0.08, 0.39)
const HURT_DURATION := 0.54

var state := State.RUN
var action_time := 0.0
var combo_step := 0
var queued_attack := false
var attack_id := 0
var health := 4
var kills := 0
var combo := 0
var best_combo := 0


func reset() -> void:
	state = State.RUN
	action_time = 0.0
	combo_step = 0
	queued_attack = false
	attack_id = 0
	health = 4
	kills = 0
	combo = 0
	best_combo = 0


func advance(delta: float) -> void:
	if state == State.RUN or state == State.DEAD:
		return
	action_time += delta
	match state:
		State.ATTACK:
			if action_time >= attack_duration():
				if queued_attack:
					combo_step = (combo_step + 1) % ATTACK_DURATIONS.size()
					_begin_attack()
				else:
					state = State.RUN
					action_time = 0.0
					combo_step = 0
		State.DODGE:
			if action_time >= DODGE_DURATION:
				state = State.RUN
				action_time = 0.0
		State.HURT:
			if action_time >= HURT_DURATION:
				state = State.RUN
				action_time = 0.0


func request_attack() -> bool:
	if state == State.RUN:
		combo_step = 0
		_begin_attack()
		return true
	if state == State.ATTACK and action_time >= attack_duration() * 0.52:
		queued_attack = true
		return true
	return false


func request_dodge() -> bool:
	if state != State.RUN:
		return false
	state = State.DODGE
	action_time = 0.0
	queued_attack = false
	combo_step = 0
	return true


func receive_hit() -> bool:
	if is_invulnerable() or state == State.DEAD:
		return false
	health -= 1
	combo = 0
	queued_attack = false
	combo_step = 0
	action_time = 0.0
	state = State.DEAD if health <= 0 else State.HURT
	return true


func register_kill() -> void:
	kills += 1
	combo += 1
	best_combo = maxi(best_combo, combo)


func is_attack_active() -> bool:
	if state != State.ATTACK:
		return false
	var window: Vector2 = ATTACK_WINDOWS[combo_step]
	return action_time >= window.x and action_time <= window.y


func is_invulnerable() -> bool:
	return state == State.DODGE and action_time >= DODGE_INVULNERABLE.x and action_time <= DODGE_INVULNERABLE.y


func attack_duration() -> float:
	return ATTACK_DURATIONS[combo_step]


func attack_reach() -> float:
	return ATTACK_REACH[combo_step]


func action_progress() -> float:
	match state:
		State.ATTACK:
			return clampf(action_time / attack_duration(), 0.0, 1.0)
		State.DODGE:
			return clampf(action_time / DODGE_DURATION, 0.0, 1.0)
		State.HURT:
			return clampf(action_time / HURT_DURATION, 0.0, 1.0)
	return 0.0


func _begin_attack() -> void:
	state = State.ATTACK
	action_time = 0.0
	queued_attack = false
	attack_id += 1
