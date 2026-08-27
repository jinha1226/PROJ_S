class_name DamageSystem
extends RefCounted

var world


func _init(p_world) -> void:
	world = p_world


func apply_damage(entity, amount: int, damage_type: String, cause_id: int) -> int:
	if entity == null or not entity.is_alive() or amount <= 0:
		return 0
	var damage := mini(entity.health, maxi(1, amount))
	entity.health -= damage
	var damage_event = world.emit_event(
		"combat.%s_damage" % damage_type, -1, entity.id, entity.position,
		damage, cause_id, {"damage_type": damage_type}
	)
	if entity.health == 0:
		world.emit_event(
			"entity.died", -1, entity.id, entity.position, 0, damage_event.id,
			{"damage_type": damage_type}
		)
	return damage
