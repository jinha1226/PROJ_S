class_name OpeningEventSystem
extends RefCounted

const ItemOperationsScript = preload("res://sim/world_item_operations.gd")
const ItemRegistryScript = preload("res://sim/item_registry.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const CHOICE_TIME_COST := 100
const GRATITUDE_MAGNITUDE := 60
const REENCOUNTER_SIGHT_RANGE := 6

var world
var movement
var pathfinder
var relationships


func _init(p_world, p_movement, p_pathfinder, p_relationships) -> void:
	world = p_world
	movement = p_movement
	pathfinder = p_pathfinder
	relationships = p_relationships


func preview_choice(choice_action: String) -> Dictionary:
	var state = world.party_encounter if world != null else null
	var opening = state.opening_event if state != null else null
	if opening == null: return _rejected("opening_event_unavailable")
	if opening.choice != "PENDING": return _rejected("opening_choice_already_committed")
	if choice_action not in ["GIVE_POTION", "PASS"]:
		return _rejected("unknown_opening_choice")
	var hero = world.entities.get(state.protagonist_id)
	var npc = world.entities.get(opening.npc_entity_id)
	var hero_life = world.combatant_states.get(state.protagonist_id)
	var npc_life = world.combatant_states.get(opening.npc_entity_id)
	if hero == null or npc == null or hero_life == null or npc_life == null:
		return _rejected("opening_actor_missing")
	if hero_life.life_state != "ACTIVE" or npc_life.life_state != "ACTIVE":
		return _rejected("opening_actor_unavailable")
	if _distance(hero.position, npc.position) != 1:
		return _rejected("opening_npc_not_adjacent")
	var result := {"accepted":true, "reason":"ok", "choice_action":choice_action,
		"npc_entity_id":opening.npc_entity_id, "time_cost":CHOICE_TIME_COST,
		"potion_instance_id":""}
	if choice_action == "GIVE_POTION":
		var inventory = world.inventory_of(state.protagonist_id)
		if inventory == null: return _rejected("opening_actor_missing")
		var potion_id := _healing_potion_instance_id(inventory)
		if potion_id.is_empty(): return _rejected("opening_healing_potion_missing")
		var item_preview: Dictionary = ItemOperationsScript.preview_use(world,
			state.protagonist_id, potion_id)
		if not bool(item_preview.get("accepted", false)) \
				or str(item_preview.get("definition_id", "")) != "POTION_HEALING" \
				or str(item_preview.get("use_kind", "")) != "HEALING":
			return _rejected("opening_healing_potion_missing")
		result.potion_instance_id = potion_id
	return result.duplicate(true)


func commit_preflighted_choice(preview: Dictionary) -> Dictionary:
	if not bool(preview.get("accepted", false)):
		return _rejected("opening_choice_not_preflighted")
	var fresh := preview_choice(str(preview.get("choice_action", "")))
	if not bool(fresh.get("accepted", false)) \
			or str(fresh.get("potion_instance_id", "")) \
			!= str(preview.get("potion_instance_id", "")):
		return _rejected(str(fresh.get("reason", "opening_choice_stale")))
	var state = world.party_encounter
	var opening = state.opening_event
	var hero = world.entities[state.protagonist_id]
	var npc = world.entities[opening.npc_entity_id]
	var choice_action := str(preview.choice_action)
	var stored_choice := "GAVE_POTION" if choice_action == "GIVE_POTION" else "PASSED"
	var root = world.emit_event("opening.choice_committed", state.protagonist_id,
		opening.npc_entity_id, npc.position, 0, -1,
		{"schema_version":1, "choice":stored_choice})
	if root == null: return _rejected("opening_choice_event_failed")
	var event_ids: Array[int] = [root.id]
	var healed_amount := 0
	if choice_action == "GIVE_POTION":
		var instance_id := str(preview.potion_instance_id)
		var consumed: Dictionary = ItemOperationsScript.commit_use_without_event(
			world, state.protagonist_id, instance_id)
		if not bool(consumed.get("accepted", false)):
			return _rejected(str(consumed.get("reason", "opening_potion_consume_failed")))
		var given = world.emit_event("opening.potion_given", state.protagonist_id,
			opening.npc_entity_id, npc.position, 1, root.id,
			{"schema_version":1, "instance_id":instance_id,
				"definition_id":"POTION_HEALING"})
		if given == null: return _rejected("opening_choice_event_failed")
		healed_amount = mini(ItemRegistryScript.HEALING_POTION_RESTORE,
			int(npc.max_health) - int(npc.health))
		if healed_amount <= 0: return _rejected("opening_heal_not_needed")
		npc.health += healed_amount
		var restored = world.emit_event("opening.health_restored", state.protagonist_id,
			opening.npc_entity_id, npc.position, healed_amount, given.id,
			{"schema_version":1, "ruleset_id":"opening-healing-potion-v1",
				"health_after":int(npc.health)})
		if restored == null or not relationships.record_gratitude_only(
				opening.npc_entity_id, state.protagonist_id, restored.id,
				GRATITUDE_MAGNITUDE):
			return _rejected("opening_gratitude_failed")
		event_ids.append_array([given.id, restored.id, world.events[-1].id])
	opening.choice = stored_choice
	opening.current_behavior = "TRAVEL"
	opening.choice_event_id = root.id
	state.revision += 1
	return {"accepted":true, "reason":"ok", "choice":stored_choice,
		"npc_entity_id":opening.npc_entity_id, "choice_event_id":root.id,
		"event_ids":event_ids, "healed_amount":healed_amount,
		"time_cost":CHOICE_TIME_COST}.duplicate(true)


func process_tick(processed_step_index: int, tick_start_can_act_ids: Dictionary) -> bool:
	if world == null or world.party_encounter == null: return true
	var state = world.party_encounter
	var opening = state.opening_event
	if opening == null or opening.choice == "PENDING": return true
	# Once the reencounter recruit joins, ordinary grouped-party movement owns the
	# same entity. The opening traveller AI must no longer issue independent moves.
	if state.member(opening.npc_entity_id) != null:return true
	var npc = world.entities.get(opening.npc_entity_id)
	var combatant = world.combatant_states.get(opening.npc_entity_id)
	if npc == null or combatant == null: return false
	if combatant.life_state == "DEAD": return true
	if not tick_start_can_act_ids.has(opening.npc_entity_id) \
			or not world.can_act(opening.npc_entity_id, world.world_time):
		return true
	if not _record_reencounter_if_visible(processed_step_index): return false
	if npc.position != opening.convergence_goal:
		var route: Dictionary = pathfinder.find_path(opening.npc_entity_id,
			opening.convergence_goal)
		if bool(route.get("found", false)) and int(route.get("steps", 0)) > 0:
			var path: Array = route.get("path", [])
			if path.size() < 2: return false
			var destination: Vector2i = path[1]
			var assessment = movement.assess_move(opening.npc_entity_id, destination)
			if not assessment.accepted: return false
			if movement.commit_preflighted_move(opening.npc_entity_id, destination,
					str(assessment.terrain_id),
					int(TerrainRegistryScript.definition(assessment.terrain_id).move_time_cost)) == null:
				return false
	if not _record_reencounter_if_visible(processed_step_index): return false
	return true


func _record_reencounter_if_visible(processed_step_index: int) -> bool:
	var state = world.party_encounter
	var opening = state.opening_event
	if opening.reencounter_event_id != -1: return true
	var npc = world.entities[opening.npc_entity_id]
	if npc.position not in opening.convergence_band: return true
	var hero = world.entities[state.protagonist_id]
	if _distance(hero.position, npc.position) > REENCOUNTER_SIGHT_RANGE \
			or not _line_of_sight(hero.position, npc.position):
		return true
	var event = world.emit_event("opening.reencountered", state.protagonist_id,
		opening.npc_entity_id, npc.position, 0, opening.choice_event_id,
		{"schema_version":1, "choice":opening.choice,
			"processed_step_index":str(processed_step_index)})
	if event == null: return false
	opening.reencounter_event_id = event.id
	state.revision += 1
	return true


func _line_of_sight(origin: Vector2i, target: Vector2i) -> bool:
	var x0 := origin.x; var y0 := origin.y
	var x1 := target.x; var y1 := target.y
	var dx := absi(x1 - x0); var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0); var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while x0 != x1 or y0 != y1:
		var doubled := 2 * error
		if doubled >= dy: error += dy; x0 += sx
		if doubled <= dx: error += dx; y0 += sy
		if Vector2i(x0, y0) == target: return true
		if str(world.tile_at(Vector2i(x0, y0)).terrain) == "wall": return false
	return true


func _healing_potion_instance_id(inventory) -> String:
	var candidates: Array[String] = []
	for item in inventory.backpack:
		if str(item.definition_id) == "POTION_HEALING" and int(item.quantity) > 0:
			candidates.append(str(item.instance_id))
	candidates.sort()
	return "" if candidates.is_empty() else candidates[0]


func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _rejected(reason: String) -> Dictionary:
	return {"accepted":false, "reason":reason}.duplicate(true)
