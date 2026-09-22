extends RefCounted

static func path(s, target: int) -> Array:
	var queue: Array = [[s.room]]
	var seen: Array = [s.room]
	while not queue.is_empty():
		var route: Array = queue.pop_front()
		if route.back() == target: return route.slice(1)
		for next in s.rooms[route.back()].links:
			if next not in seen:
				seen.append(next); queue.append(route + [next])
	return []

static func clear_battle(s) -> void:
	if s.phase != "BATTLE": return
	for enemy in s.enemies: s.damage(enemy,1000,0,"SLASH")
	s.check_battle_end()

static func reach(s, target: int) -> bool:
	for next in path(s,target):
		clear_battle(s)
		if not s.travel(next): return false
	return s.room == target

static func kind_id(s, kind: String) -> int:
	for row in s.rooms:
		if row.kind == kind: return row.id
	return -1

## Equips the two basics on every member with their default rules, the
## pre-parts starting state most suites assume.
static func equip_basics(s) -> void:
	var abilities = load("res://expedition/abilities.gd")
	for actor in s.party:
		actor.equipped_abilities = ["PUSH","GUARD"]
		actor.rules = [abilities.default_rule("PUSH"),abilities.default_rule("GUARD")]
