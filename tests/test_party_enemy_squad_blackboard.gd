extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Blackboard = preload("res://sim/enemy_squad_blackboard.gd")
const Awareness = preload("res://sim/enemy_awareness_state.gd")


func test_enemy_squad_blackboard_is_exact_pure_and_claims_visible_targets() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	_add_visible_enemies(world, state, 3)
	var before := JSON.stringify(world.snapshot())
	var board: Dictionary = Blackboard.build(world)
	var keys: Array = board.keys(); keys.sort()
	check_eq(keys, ["active_enemy_ids", "claims", "deployed_party_ids",
		"focus_target_id", "schema_version", "target_pressure", "visible_targets"],
		"blackboard has exact detached projection keys")
	check_eq(board, Blackboard.build(world), "same world produces the same board")
	check_eq(JSON.stringify(world.snapshot()), before, "blackboard mutates no authority")
	check_eq(board.deployed_party_ids, state.active_party_member_ids,
		"all deployed party members participate in tactics")
	check(int(board.focus_target_id) in board.deployed_party_ids,
		"focus is a visible deployed party member")
	var coverage := {}
	for target_id in board.claims.values():
		coverage[int(target_id)] = int(coverage.get(int(target_id), 0)) + 1
	for count in coverage.values():
		check(int(count) <= Blackboard.CLAIM_CAP,
			"multiple visible targets cap initial focus coverage")
	return finish()


func test_companion_sight_drives_hunting_and_combat_relevance_without_hero() -> bool:
	var session = _engaged()
	var world = session.sim.world
	var state = world.party_encounter
	var hero_id := int(state.protagonist_id)
	var companion_id := int(state.active_party_member_ids[1])
	var enemy_id := int(state.enemy_ids[0])
	var enemy = world.entities[enemy_id]
	var hero = world.entities[hero_id]
	var companion = world.entities[companion_id]
	hero.position = _far_corner(world, enemy.position)
	companion.position = _adjacent_position(world, enemy.position)
	var awareness = state.enemy_awareness(enemy_id)
	awareness.awareness_state = "UNAWARE"
	awareness.suspicion = 0
	awareness.last_known_target_position = Vector2i(-1, -1)
	check(session.sim.party_coordinator._update_enemy_awareness(enemy_id, 77),
		"companion observation updates awareness")
	check_eq(awareness.awareness_state, "HUNTING",
		"adjacent companion triggers hunting while hero is out of range")
	check_eq(awareness.last_known_target_position, companion.position,
		"last known position belongs to the observed companion")
	var transition = world.events.back()
	check_eq(int(transition.target_id), companion_id,
		"awareness transition identifies the observed party member")
	check(session.sim.party_coordinator._has_active_combat_enemy(),
		"enemy near a companion remains combat-active without a nearby hero")
	return finish()


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"fixture reaches contact")
	session.preview_deployment("WEDGE", session.available_companion_ids())
	check(session.commit_deployment().accepted, "fixture deploys party")
	return session


func _add_visible_enemies(world, state, count: int) -> void:
	var spawned := 0
	var anchor: Vector2i = world.entities[state.protagonist_id].position
	for radius in range(2, 6):
		for y in range(anchor.y - radius, anchor.y + radius + 1):
			for x in range(anchor.x - radius, anchor.x + radius + 1):
				if spawned >= count:
					return
				var position := Vector2i(x, y)
				if not world.in_bounds(position) \
						or maxi(absi(x - anchor.x), absi(y - anchor.y)) != radius \
						or world.blocking_entity_at(position) != null:
					continue
				var enemy = world.add_entity("melee_enemy", "전술 증원 %d" % spawned,
					position, 60, ["party_enemy"], "goblin", "enemy")
				if enemy == null:
					continue
				state.enemy_ids.append(enemy.id); state.enemy_ids.sort()
				state.enemy_busy_rows[enemy.id] = 0
				state.enemy_awareness_rows[enemy.id] = Awareness.new(enemy.id, position)
				spawned += 1


func _far_corner(world, origin: Vector2i) -> Vector2i:
	var corners := [Vector2i(0, 0), Vector2i(world.width - 1, world.height - 1)]
	return corners[1] if _distance(origin, corners[1]) > _distance(origin, corners[0]) \
		else corners[0]


func _adjacent_position(world, origin: Vector2i) -> Vector2i:
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = origin + Vector2i(direction)
		if world.in_bounds(candidate):
			return candidate
	return origin


func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
