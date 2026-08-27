class_name MeleeCombatSystem
extends RefCounted

var world
var damage

func _init(p_world, p_damage) -> void: world = p_world; damage = p_damage

func can_attack(attacker_id: int, target_id: int) -> bool:
	if not world.entities.has(attacker_id) or not world.entities.has(target_id): return false
	var attacker = world.entities[attacker_id]; var target = world.entities[target_id]
	return attacker.is_alive() and target.is_alive() and maxi(absi(attacker.position.x - target.position.x), absi(attacker.position.y - target.position.y)) == 1

func commit_attack(attacker_id: int, target_id: int, amount: int, cause_id: int):
	if not can_attack(attacker_id, target_id) or amount <= 0: return null
	var attacker = world.entities[attacker_id]; var target = world.entities[target_id]
	var action = world.emit_event("action.melee_attack", attacker_id, target_id, target.position, amount, cause_id,
		{"combat_ruleset_id": "fixed-melee-v1"})
	if action == null: return null
	var applied := amount
	var target_state = world.agent_states.get(target_id)
	if target_state != null and world.world_time < target_state.guarded_until:
		applied = amount - (amount * 250 / 1000)
	damage.apply_damage(target, applied, "physical", action.id)
	return action
