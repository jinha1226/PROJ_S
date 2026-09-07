extends "res://tests/test_case.gd"

# This suite deliberately drives the public session facade.  The only map data
# read directly here is the immutable, seeded topology used to choose a legal
# route; cache identity and availability are asserted through the observation
# DTO after the protagonist has actually walked onto the cell.
const Session = preload("res://playtest/party_playtest_session.gd")
const BaseRules = preload("res://sim/base_progression_rules.gd")
const CacheRules = preload("res://sim/base_resource_cache_rules.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const TerrainRegistry = preload("res://sim/terrain_registry.gd")

const WORLD_SEED := 44
const PERSONALITY_SEED := 20260828
const DUO := "DUO_AUTOBATTLE_V1"


func test_duo_bootstrap_exposes_floor_local_cache_contract() -> bool:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	check_eq(session.scenario_id, DUO, "base acceptance uses the default duo world")
	var overview: Dictionary = session.base_overview()
	check(bool(overview.get("enabled", false)), "base facade is enabled for the duo world")
	check_eq(str(overview.get("phase", "")), "DUNGEON", "new duo starts in the dungeon")
	check_eq(overview.get("stock", {}), BaseRules.STARTER_STOCK,
		"starter stock is secured while the expedition is active")
	check_eq(overview.get("carried", {}), {"TIMBER": 0, "STONE": 0, "HERBS": 0},
		"a new expedition carries no gathered base stock")
	check_eq(int(overview.get("capacity", 0)), 8, "storage level one capacity")
	var facilities: Array = overview.get("facilities", [])
	check_eq(facilities.size(), 3, "the three fixed base facilities are present")
	var by_id: Dictionary = {}
	for row_value in facilities:
		var row: Dictionary = row_value
		by_id[str(row.get("id", ""))] = row
	for facility_id in BaseRules.FACILITY_IDS:
		check(by_id.has(facility_id), "facility %s is visible" % facility_id)
		if not by_id.has(facility_id):
			continue
		check_eq(int(by_id[facility_id].get("level", 0)), 1,
			"%s starts at level one" % facility_id)
		check_eq(by_id[facility_id].get("cost", {}), BaseRules.cost(facility_id, 2),
			"%s publishes its level-two cost" % facility_id)

	var floor_one: Dictionary = VisualMap.product_dungeon(WORLD_SEED)
	var floor_one_rows: Array[Dictionary] = CacheRules.caches(
		session.sim.world, floor_one, WORLD_SEED, 1)
	check_eq(floor_one_rows.size(), 9, "floor one has nine deterministic cache slots")
	var f1_bounds: Rect2i = _floor_bounds(floor_one)
	for row_value in floor_one_rows:
		var row: Dictionary = row_value
		var position := _row_position(row)
		check(f1_bounds.has_point(position),
			"every F1 cache stays inside the selected F1 floor region: %s" % str(row))
		check(str(row.get("cache_id", "")).begins_with("EXP1_F1_"),
			"F1 cache id carries its expedition and floor identity")

	# The aggregate world contains both campaign floors.  Generate the second
	# floor's cache set as a read-only topology check: no F2 row may leak into the
	# F1 set even though both floor regions share one WorldState tile array.
	var floor_two: Dictionary = VisualMap.campaign_runtime_floor(2, WORLD_SEED)
	var floor_two_rows: Array[Dictionary] = CacheRules.caches(
		session.sim.world, floor_two, WORLD_SEED, 1)
	var f2_bounds: Rect2i = _floor_bounds(floor_two)
	for row_value in floor_two_rows:
		var row: Dictionary = row_value
		check(f2_bounds.has_point(_row_position(row)),
			"second-floor cache remains in the second-floor region")
		check(str(row.get("cache_id", "")).begins_with("EXP1_F2_"),
			"F2 cache id carries its floor identity")
	for row_value in floor_one_rows:
		check(not f2_bounds.has_point(_row_position(row_value)),
			"F1 cache never uses an aggregate F2 coordinate")

	var next_expedition_rows: Array[Dictionary] = CacheRules.caches(
		session.sim.world, floor_one, WORLD_SEED, 2)
	check_eq(next_expedition_rows.size(), 9,
		"the next expedition receives its own finite cache set")
	if not floor_one_rows.is_empty() and not next_expedition_rows.is_empty():
		check(str(floor_one_rows[0].get("cache_id", "")) != str(
			next_expedition_rows[0].get("cache_id", "")),
			"cache identity includes expedition number")

	# Reading detached DTOs, including the public cache-bearing observation, must
	# not advance time or append a journal row.
	var before_read: String = session.save_session_json()
	var detached: Dictionary = session.base_overview()
	detached.stock.TIMBER = 999
	var observed: Dictionary = session.observe_party_world()
	if observed.has("cells") and not observed.cells.is_empty():
		observed.cells[0].terrain_id = "forged"
	check_eq(session.save_session_json(), before_read,
		"overview and observation reads are detached and side-effect free")
	return finish()


func test_actual_movement_gathering_time_overflow_and_rejection_guards() -> bool:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var initial_snapshot: Dictionary = session.sim.snapshot()
	var distant: Dictionary = session.base_gather_assessment()
	check(not bool(distant.get("accepted", false)),
		"gathering is denied before the hero reaches a cache")
	check_eq(str(distant.get("reason", "")), "base_gather_cache_not_reached",
		"distant gathering reports the reachability gate")
	check_eq(session.sim.snapshot(), initial_snapshot,
		"a distant gather assessment does not mutate the world")

	var rows: Array[Dictionary] = _expected_cache_rows(session, 1)
	var initial_cache_positions: Array = []
	for row_value in rows:
		initial_cache_positions.append((row_value as Dictionary).get("position", []).duplicate(true))
	var candidates: Array[Dictionary] = _three_unit_safe_cache_rows(session, rows)
	check(candidates.size() >= 3,
		"seed 44 exposes at least three three-unit timber/stone routes")
	if candidates.size() < 3:
		return finish()

	var gathered_total := 0
	var first_row: Dictionary = candidates[0]
	var first_position := _row_position(first_row)
	check(_walk_to_position(session, first_position),
		"protagonist reaches the first cache through real movement")
	var first_observed: Dictionary = _observed_cache_at(session, first_position)
	check_eq(str(first_observed.get("cache_id", "")), str(first_row.get("cache_id", "")),
		"the cache is observable at the character's actual position")
	var before_gather_time := int(session.sim.world.world_time)
	var first_result: Dictionary = session.base_gather()
	check(bool(first_result.get("accepted", false)),
		"reachable cache gathers through the canonical session API")
	var first_amount := int(first_result.get("amount", 0))
	check(first_amount > 0, "a successful gather has positive amount")
	check(int(session.sim.world.world_time) > before_gather_time,
		"gathering consumes canonical action time")
	gathered_total += first_amount

	# The first cache is exhausted in one action (each selected cache has three
	# units). Repeating the tap must be a pure rejection rather than a duplicate
	# event or another time step.
	var exhausted_snapshot: Dictionary = session.sim.snapshot()
	var duplicate: Dictionary = session.base_gather()
	check(not bool(duplicate.get("accepted", false)),
		"an exhausted cache cannot be gathered twice")
	check(str(duplicate.get("reason", "")) in ["base_gather_cache_not_reached",
		"base_gather_capacity_full"], "duplicate cache denial has a finite-cache reason")
	check(_snapshot_json(session) == JSON.stringify(exhausted_snapshot),
		"duplicate gather denial is non-mutating")

	var partial_seen := false
	var capacity_seen := false
	for row_value in candidates.slice(1):
		if gathered_total >= 8:
			capacity_seen = true
			break
		var row: Dictionary = row_value
		var position := _row_position(row)
		if not _walk_to_position(session, position):
			break
		var dto_cache: Dictionary = _observed_cache_at(session, position)
		check_eq(str(dto_cache.get("cache_id", "")), str(row.get("cache_id", "")),
			"each gathered cache remains position-bound after movement")
		var expected_amount := mini(8 - gathered_total, int(row.get("amount", 0)))
		var assessment: Dictionary = session.base_gather_assessment()
		check(bool(assessment.get("accepted", false)),
			"capacity leaves room for the next cache until full")
		if not bool(assessment.get("accepted", false)):
			break
		var result: Dictionary = session.base_gather()
		check(bool(result.get("accepted", false)), "subsequent cache gathers commit")
		if not bool(result.get("accepted", false)):
			break
		check_eq(int(result.get("amount", -1)), expected_amount,
			"gather amount is clipped to remaining carry capacity")
		gathered_total += int(result.get("amount", 0))
		if int(result.get("amount", 0)) < int(row.get("amount", 0)):
			partial_seen = true
			check(int(result.get("cache_remaining_after", 0)) > 0,
				"partial overflow leaves the remainder in the cache")
			break

	check_eq(gathered_total, 8, "the finite storage cap is reached by real gathers")
	check(partial_seen, "the overflow action retains cache remainder")
	var capacity_snapshot: Dictionary = session.sim.snapshot()
	var capacity_rejection: Dictionary = session.base_gather_assessment()
	check(not bool(capacity_rejection.get("accepted", false)),
		"a full carrier rejects another gather")
	check_eq(str(capacity_rejection.get("reason", "")), "base_gather_capacity_full",
		"full carrier reports the capacity gate")
	check(_snapshot_json(session) == JSON.stringify(capacity_snapshot),
		"capacity rejection is non-mutating")
	var positions_after_movement: Array = []
	for row_value in _expected_cache_rows(session, 1):
		positions_after_movement.append((row_value as Dictionary).get("position", []).duplicate(true))
	check_eq(positions_after_movement, initial_cache_positions,
		"actual character movement cannot relocate cache positions")
	return finish()


func test_gather_return_upgrade_trade_depart_and_save_replay_exact() -> bool:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var rows: Array[Dictionary] = _expected_cache_rows(session, 1)
	# Timber slots intentionally form a nearby three-cell cluster in the seeded
	# world.  Keep that authored topology here: the first exhausted slot makes
	# the next slot (not a duplicate of the first) selectable at the same anchor.
	var safe_rows: Array[Dictionary] = _safe_cache_rows(session, rows)
	check(safe_rows.size() >= 3, "canonical progression route has three safe caches")
	if safe_rows.size() < 3:
		return finish()

	# A T3 cache, an S3 cache, then a second T cache fit exactly under the
	# starting eight-unit carrier and are enough for STORAGE level two.  The third
	# gather is intentionally clipped, preserving an observable remainder.
	var timber_rows: Array[Dictionary] = []
	var stone_rows: Array[Dictionary] = []
	for row_value in safe_rows:
		var row: Dictionary = row_value
		if str(row.get("resource_id", "")) == "TIMBER":
			timber_rows.append(row)
		elif str(row.get("resource_id", "")) == "STONE":
			stone_rows.append(row)
	check(timber_rows.size() >= 2 and not stone_rows.is_empty(),
		"seeded route exposes two timber caches and one stone cache")
	if timber_rows.size() < 2 or stone_rows.is_empty():
		return finish()

	var chosen: Array[Dictionary] = [timber_rows[0], stone_rows[0], timber_rows[1]]
	var gathered: Dictionary = {"TIMBER": 0, "STONE": 0, "HERBS": 0}
	for row_value in chosen:
		var row: Dictionary = row_value
		var position := _row_position(row)
		check(_walk_to_position(session, position),
			"canonical gather path reaches %s" % str(row.get("cache_id", "")))
		var visible_cache: Dictionary = _observed_cache_at(session, position)
		check_eq(str(visible_cache.get("cache_id", "")), str(row.get("cache_id", "")),
			"canonical gather uses the visible position-bound cache")
		var gathered_result: Dictionary = session.base_gather()
		check(bool(gathered_result.get("accepted", false)),
			"canonical gather commits before return")
		if not bool(gathered_result.get("accepted", false)):
			return finish()
		var resource_id := str(gathered_result.get("resource_id", ""))
		gathered[resource_id] = int(gathered[resource_id]) + int(
			gathered_result.get("amount", 0))

	check_eq(BaseRules.total_resources(gathered), 8,
		"canonical haul fills the starting carrier without direct fixture mutation")
	check(gathered.TIMBER >= 5 and gathered.STONE >= 3,
		"canonical haul contains enough timber and stone for storage level two")
	var dungeon_command_snapshot: Dictionary = session.sim.snapshot()
	check_eq(str(session.base_upgrade("STORAGE").get("reason", "")),
		"base_upgrade_town_required", "building is town-only")
	check_eq(str(session.base_sell("TIMBER", 1).get("reason", "")),
		"base_sell_town_required", "selling is town-only")
	check(_snapshot_json(session) == JSON.stringify(dungeon_command_snapshot),
		"dungeon build/sell attempts do not consume carried or secured stock")

	var entry: Vector2i = _entry_position(session)
	check(_walk_to_position(session, entry), "the protagonist walks back to the entry")
	var return_assessment: Dictionary = session.base_return_assessment()
	check(bool(return_assessment.get("accepted", false)),
		"manual extraction is only accepted at the safe entry")
	check_eq(str(return_assessment.get("entry_mode", "")), "ENTRY",
		"entry extraction identifies its safe portal")
	var return_result: Dictionary = session.base_return()
	check(bool(return_result.get("accepted", false)),
		"manual extraction commits one expedition return")
	check_eq(str(session.expedition_cycle_status().get("return_reason", "")),
		"MANUAL_EXTRACT", "return records the requested extraction reason")
	var return_events := _count_world_events(session, "dungeon.expedition_returned")
	check_eq(return_events, 1, "one extraction emits one canonical return event")
	var town_overview: Dictionary = session.base_overview()
	check_eq(town_overview.get("stock", {}), {
		"TIMBER": 4 + int(gathered.TIMBER),
		"STONE": 2 + int(gathered.STONE),
		"HERBS": 2 + int(gathered.HERBS)},
		"extracted haul credits secured stock exactly once")

	# Build/sell are town-only and malformed operations must leave the snapshot
	# byte-for-byte unchanged.
	var town_before_invalid: Dictionary = session.sim.snapshot()
	check(not bool(session.base_upgrade("UNKNOWN_FACILITY").get("accepted", false)),
		"unknown facility id is denied")
	check(not bool(session.base_sell("UNKNOWN_RESOURCE", 1).get("accepted", false)),
		"unknown resource id is denied")
	check(not bool(session.base_sell("TIMBER", -1).get("accepted", false)),
		"negative trade amount is denied")
	check_eq(session.sim.snapshot(), town_before_invalid,
		"unknown and negative base commands do not mutate authority")

	var upgrade: Dictionary = session.base_upgrade("STORAGE")
	check(bool(upgrade.get("accepted", false)), "storage level two upgrade commits in town")
	check_eq(int(session.base_overview().capacity), 12,
		"storage upgrade changes the real carrier capacity")
	var stock_after_upgrade: Dictionary = session.base_overview().stock
	check_eq(stock_after_upgrade, {
		"TIMBER": 4 + int(gathered.TIMBER) - 8,
		"STONE": 2 + int(gathered.STONE) - 5,
		"HERBS": 2 + int(gathered.HERBS)},
		"upgrade consumes the published resource cost")
	var sell_before: Dictionary = session.base_overview()
	var sell: Dictionary = session.base_sell("HERBS", 1)
	check(bool(sell.get("accepted", false)), "secured stock can be sold in town")
	check_eq(int(session.base_overview().stock.HERBS),
		int(sell_before.stock.HERBS) - 1, "selling consumes only secured stock")
	check_eq(int(sell.get("gold_earned", 0)), 4, "herb sale uses the canonical unit price")

	var depart: Dictionary = session.depart_town()
	check(bool(depart.get("accepted", false)), "the upgraded party can depart again")
	check_eq(str(session.expedition_cycle_status().get("phase", "")), "DUNGEON",
		"departure opens the next dungeon expedition")
	var event_count_before_replay: int = session.sim.world.events.size()
	var encoded: String = session.save_session_json()
	var restored = Session.new(999, 888, DUO)
	var loaded: Dictionary = restored.load_session_json(encoded)
	check(bool(loaded.get("accepted", false)),
		"gather-return-upgrade-trade-depart journal loads")
	check_eq(restored.sim.snapshot(), session.sim.snapshot(),
		"save/load replay preserves the canonical progression exactly")
	check_eq(restored.sim.world.events.size(), event_count_before_replay,
		"replay does not duplicate the bank/upgrade/trade history")
	var restored_before_reads: Dictionary = restored.sim.snapshot()
	for _index in range(3):
		var reopened: Dictionary = restored.base_overview()
		reopened.stock.TIMBER = 999
		restored.observe_party_world()
	check_eq(restored.sim.snapshot(), restored_before_reads,
		"reopening/loading the base view never duplicates secured stock")
	var reloaded = Session.new(101, 202, DUO)
	check(bool(reloaded.load_session_json(encoded).get("accepted", false)),
		"the same saved progression can be loaded into a fresh session")
	check_eq(reloaded.sim.snapshot(), session.sim.snapshot(),
		"fresh load remains deterministic after repeated reopen")
	return finish()


func test_old_scenario_save_still_loads_after_base_slice() -> bool:
	var old_session = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.REGRESSION_SCENARIO_ID)
	var encoded: String = old_session.save_session_json()
	var restored = Session.new(1, 2, DUO)
	var result: Dictionary = restored.load_session_json(encoded)
	check(bool(result.get("accepted", false)),
		"pre-base regression scenario save remains loadable")
	if bool(result.get("accepted", false)):
		check_eq(restored.scenario_id, Session.REGRESSION_SCENARIO_ID,
			"old scenario identity is retained on load")
		check_eq(restored.sim.snapshot(), old_session.sim.snapshot(),
			"old scenario snapshot remains exact")
	return finish()


func _expected_cache_rows(session, expedition_index: int) -> Array[Dictionary]:
	var layout: Dictionary = VisualMap.product_dungeon(int(session.world_seed))
	return CacheRules.caches(session.sim.world, layout, int(session.world_seed),
		expedition_index)


func _safe_cache_rows(session, rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ranked: Array[Dictionary] = []
	var hero = session.sim.world.entities.get(session.sim.world.party_encounter.protagonist_id)
	if hero == null:
		return result
	for row_value in rows:
		var row: Dictionary = row_value
		var path: Array[Vector2i] = _bfs_path(session, _row_position(row), true)
		if path.is_empty():
			continue
		ranked.append({"row": row, "steps": path.size(),
			"distance": maxi(absi(_row_position(row).x - hero.position.x),
				absi(_row_position(row).y - hero.position.y))})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.steps) != int(b.steps):
			return int(a.steps) < int(b.steps)
		return str(a.row.get("cache_id", "")) < str(b.row.get("cache_id", "")))
	for value in ranked:
		result.append((value.row as Dictionary).duplicate(true))
	return result


func _three_unit_safe_cache_rows(session, rows: Array[Dictionary]) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for row_value in _safe_cache_rows(session, rows):
		var row: Dictionary = row_value
		if str(row.get("resource_id", "")) not in ["TIMBER", "STONE"]:
			continue
		if int(row.get("amount", 0)) != 3:
			continue
		selected.append(row.duplicate(true))
	return selected


func _walk_to_position(session, target: Vector2i) -> bool:
	var path: Array[Vector2i] = _bfs_path(session, target, true)
	if path.is_empty():
		errors.append("no legal route to cache/portal %s" % str(target))
		return false
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	for index in range(1, path.size()):
		var current = session.sim.world.entities[hero_id].position
		var delta: Vector2i = path[index] - current
		var result: Dictionary = session.commit_exploration_direction(delta)
		if not bool(result.get("accepted", false)):
			errors.append("movement to %s rejected at %s: %s" % [
				str(target), str(path[index]), str(result)])
			return false
		if str(session.party_status().get("safe_phase", "")) not in [
				"GROUPED", "GROUPED_COMPLETE"]:
			errors.append("movement to %s left exploration safe phase: %s" % [
				str(target), str(session.party_status())])
			return false
	return session.sim.world.entities[hero_id].position == target


func _bfs_path(session, target: Vector2i, avoid_threats: bool) -> Array[Vector2i]:
	var world = session.sim.world
	var state = world.party_encounter
	var hero = world.entities.get(state.protagonist_id)
	if hero == null or not world.in_bounds(target):
		return []
	var start: Vector2i = hero.position
	if start == target:
		return [start]
	var blocked: Dictionary = {}
	for enemy_id_value in state.enemy_ids:
		var enemy = world.entities.get(int(enemy_id_value))
		if enemy == null:
			continue
		var radius := 3 if avoid_threats else 0
		for y in range(enemy.position.y - radius, enemy.position.y + radius + 1):
			for x in range(enemy.position.x - radius, enemy.position.x + radius + 1):
				if world.in_bounds(Vector2i(x, y)):
					blocked[Vector2i(x, y)] = true
	blocked.erase(start)
	blocked.erase(target)
	var queue: Array[Vector2i] = [start]
	var parents: Dictionary = {start: Vector2i(-1, -1)}
	var cursor := 0
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT,
		Vector2i.DOWN, Vector2i.LEFT]
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction in directions:
			var next: Vector2i = current + direction
			if not world.in_bounds(next) or parents.has(next) or blocked.has(next):
				continue
			var terrain: Dictionary = TerrainRegistry.definition(str(world.tile_at(next).terrain))
			if terrain.is_empty() or not bool(terrain.get("passable", false)):
				continue
			parents[next] = current
			queue.append(next)
			if next == target:
				var reversed: Array[Vector2i] = [target]
				var walk := target
				while walk != start:
					walk = parents[walk]
					reversed.append(walk)
				reversed.reverse()
				return reversed
	return []


func _observed_cache_at(session, position: Vector2i) -> Dictionary:
	var observation: Dictionary = session.observe_party_world()
	for cell_value in observation.get("cells", []):
		var cell: Dictionary = cell_value
		if cell.get("position", []) == [position.x, position.y] \
				and str(cell.get("visibility_state", "")) == "VISIBLE":
			var cache: Variant = cell.get("resource_cache", {})
			if cache is Dictionary:
				return (cache as Dictionary).duplicate(true)
	return {}


func _row_position(row: Dictionary) -> Vector2i:
	var value: Variant = row.get("position", [])
	return Vector2i(int(value[0]), int(value[1])) if value is Array and value.size() == 2 \
		else Vector2i(-1, -1)


func _entry_position(session) -> Vector2i:
	var layout: Dictionary = VisualMap.product_dungeon(int(session.world_seed))
	var value: Variant = layout.get("entry_position", Vector2i(-1, -1))
	return value if value is Vector2i else Vector2i(int(value[0]), int(value[1]))


func _floor_bounds(layout: Dictionary) -> Rect2i:
	var value: Variant = layout.get("floor_bounds", [])
	if value is Array and value.size() == 4:
		return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))
	return Rect2i()


func _count_world_events(session, type: String) -> int:
	var count := 0
	for event in session.sim.world.events:
		if str(event.type) == type:
			count += 1
	return count


func _snapshot_json(session) -> String:
	return JSON.stringify(session.sim.snapshot())
