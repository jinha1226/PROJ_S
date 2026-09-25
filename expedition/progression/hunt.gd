extends RefCounted
## Who took part in bringing a monster down: whoever struck, shot or cast at it.
## `Session.hunt_recipients` reads this to share the kill's level XP and loot.
static func record(actor: Dictionary, enemy_id: int) -> void:
	if enemy_id < 0: return
	if not actor.has("usage"): actor.usage = {}
	actor.usage[enemy_id] = int(actor.usage.get(enemy_id,0))+1
