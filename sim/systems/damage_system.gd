class_name DamageSystem
extends RefCounted

var world


func _init(p_world) -> void:
	world = p_world


func apply_damage(entity, amount: int, damage_type: String, cause_id: int,
		event_position: Vector2i = Vector2i(-1, -1)) -> int:
	if entity == null or not entity.is_alive() or amount <= 0:
		return 0
	var damage := mini(entity.health, maxi(1, amount))
	entity.health -= damage
	var resolved_position: Vector2i = entity.position if event_position == Vector2i(-1, -1) else event_position
	var damage_event = world.emit_event(
		"combat.%s_damage" % damage_type, -1, entity.id, resolved_position,
		damage, cause_id, {"damage_type": damage_type}
	)
	if entity.health == 0:
		world.emit_event(
			"entity.died", -1, entity.id, resolved_position, 0, damage_event.id,
			{"damage_type": damage_type}
		)
	return damage
