extends "res://playtest/party_auto_explore.gd"
## Frozen 4227de3 search oracle, not loaded by the product scene.
func _nearest_safe_frontier(snapshot: Dictionary, cells: Dictionary,
		start: Vector2i) -> Dictionary:
	plan_builds+=1
	var start_key := _key(start)
	if not cells.has(start_key):
		return {"found":false, "reason":"auto_explore_no_frontier"}
	# Exit seeking: when the run publishes an exit, every candidate is scored by
	# steps + Chebyshev distance from the candidate to the exit, so AUTO explores
	# toward the exit instead of hugging its own reveal boundary around the map
	# edge. Without an exit the score is the step count, which is the old
	# nearest-frontier rule. An open, known, reachable exit is walked to directly.
	var exit := _wire_position(snapshot.get("exit_position", [-1, -1]))
	var seek_exit := exit.x >= 0 and exit.y >= 0
	var exit_open := seek_exit and bool(snapshot.get("exit_open", false))
	# Step count is the primary BFS key, so process one layer at a time and sort
	# that layer once. Storing only a parent avoids copying a growing path array
	# for every candidate.
	var open: Array[Dictionary] = [{"position":start, "steps":0, "cost":0,
		"sequence":0}]
	var best: Dictionary = {start_key:[0, 0]}
	var parents: Dictionary = {}
	var visited: Dictionary = snapshot.get("visited", {})
	var use_visited_fallback := snapshot.has("visited")
	var best_frontier: Dictionary = {}
	var best_unvisited: Dictionary = {}
	var sequence := 1
	while not open.is_empty():
		open.sort_custom(_frontier_open_less)
		# Every node of a layer shares its step count and the exit distance is
		# never negative, so once the layer's steps exceed the best frontier score
		# no later candidate can win. Keep searching while an open exit may still
		# be reached, since reaching it beats every frontier.
		if not exit_open and not best_frontier.is_empty() \
				and int(open[0].steps) > int(best_frontier.score):
			break
		var next_open: Array[Dictionary] = []
		for node in open:
			var position: Vector2i = node.position
			if best.get(_key(position), []) != [int(node.steps), int(node.cost)]:
				continue
			if exit_open and position == exit and position != start:
				return {"found":true, "target":position,
					"visibility_state":str(cells[_key(position)].get(
						"visibility_state", "MEMORY")),
					"path":_frontier_path(start, position, parents),
					"steps":int(node.steps), "cost":int(node.cost),
					"target_kind":"EXIT", "exit_distance":0}
			var exit_distance := _exit_distance(position, exit) if seek_exit else 0
			var candidate := {"position":position, "steps":int(node.steps),
				"cost":int(node.cost), "score":int(node.steps) + exit_distance,
				"exit_distance":exit_distance if seek_exit else -1}
			if position != start and not _exhausted_frontiers.has(_key(position)) \
					and not visited.has(_key(position)) and _is_frontier(position, cells,
					int(snapshot.get("width", 0)), int(snapshot.get("height", 0))):
				if best_frontier.is_empty() \
						or _frontier_candidate_less(candidate, best_frontier):
					best_frontier = candidate
			# Visibility frontiers remain the first priority. Remember the best
			# reachable safe cell the hero has never actually occupied, then use it
			# only when this whole known component has no unseen frontier left.
			elif use_visited_fallback and position != start \
					and not visited.has(_key(position)) \
					and (best_unvisited.is_empty() \
						or _frontier_candidate_less(candidate, best_unvisited)):
				best_unvisited = candidate
			for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
				var next := position + direction
				if not _known_step_is_safe(position, next, cells):
					continue
				var cell: Dictionary = cells[_key(next)]
				var candidate_steps := int(node.steps) + 1
				var candidate_cost := int(node.cost) + int(cell.get("move_time_cost", 0))
				var old: Array = best.get(_key(next), [])
				if not old.is_empty() and [candidate_steps, candidate_cost] >= old:
					continue
				var next_key := _key(next)
				best[next_key] = [candidate_steps, candidate_cost]
				parents[next_key] = position
				next_open.append({"position":next, "steps":candidate_steps,
					"cost":candidate_cost, "sequence":sequence})
				sequence += 1
		open = next_open
	var chosen := best_frontier
	var target_kind := "FRONTIER"
	if chosen.is_empty():
		chosen = best_unvisited
		target_kind = "UNVISITED"
	if chosen.is_empty():
		return {"found":false, "reason":"auto_explore_no_frontier"}
	var target: Vector2i = chosen.position
	var cell: Dictionary = cells[_key(target)]
	return {"found":true, "target":target,
		"visibility_state":str(cell.get("visibility_state", "MEMORY")),
		"path":_frontier_path(start, target, parents),
		"steps":int(chosen.steps), "cost":int(chosen.cost),
		"target_kind":target_kind, "exit_distance":int(chosen.exit_distance)}


func _exit_distance(position: Vector2i, exit: Vector2i) -> int:
	return maxi(absi(exit.x - position.x), absi(exit.y - position.y))


func _frontier_candidate_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.score) != int(b.score): return int(a.score) < int(b.score)
	if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
	if int(a.cost) != int(b.cost): return int(a.cost) < int(b.cost)
	var a_position: Vector2i = a.position
	var b_position: Vector2i = b.position
	if a_position.y != b_position.y: return a_position.y < b_position.y
	return a_position.x < b_position.x


func _frontier_open_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.steps) != int(b.steps): return int(a.steps) < int(b.steps)
	if int(a.cost) != int(b.cost): return int(a.cost) < int(b.cost)
	var a_position: Vector2i = a.position
	var b_position: Vector2i = b.position
	if a_position.y != b_position.y: return a_position.y < b_position.y
	if a_position.x != b_position.x: return a_position.x < b_position.x
	return int(a.sequence) < int(b.sequence)


func _frontier_path(start: Vector2i, goal: Vector2i,
		parents: Dictionary) -> Array:
	var reversed: Array = [goal]
	var cursor := goal
	while cursor != start:
		var parent: Variant = parents.get(_key(cursor), null)
		if not parent is Vector2i: return []
		cursor = parent
		reversed.append(cursor)
	reversed.reverse()
	return reversed
