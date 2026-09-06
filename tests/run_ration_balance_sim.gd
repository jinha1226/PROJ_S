extends SceneTree

## Headless balance probe: runs seeded solo expeditions on AUTO until the party
## returns to town, dies, or the step budget ends, and prints ration outcomes.
## Not a pass/fail test; read the table and tune data/content/hunger_rules.json.
##
## The probe drives everything AUTO EXPLORE refuses to drive itself, so a run can
## actually reach the expedition deadline: the opening interaction, contact
## deployment, the engaged combat turns, the floor portal, and the short detour to
## a ration lying on the floor. Every choice is fixed (no RNG and no wall clock in
## the driver), so the table is a pure function of the seed list and the rules JSON.
##
## The hot loop reads the party state fields it needs straight off the world
## instead of calling party_status() 1500 times: that projection rescans the whole
## event log for the latest contact warning, which turns a full-length expedition
## into an O(steps^2) walk. party_status() is still the source for combat targets,
## where it is called a handful of times per run.

const Session = preload("res://playtest/party_playtest_session.gd")
const Rules = preload("res://sim/party_ration_rules.gd")
const Command = preload("res://sim/sim_command.gd")
const SEEDS := [44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
const STEP_BUDGET := 1500
const BAND_ORDER := {"FED": 0, "HUNGRY": 1, "STARVING": 2}
## A player detours for food they can see but does not cross the floor for it, and
## a route the fog still rejects is not re-planned on every single hop.
const FOOD_SEEK_RADIUS := 12
const FOOD_SEEK_COOLDOWN := 8


func _init() -> void:
	print("rules: %s" % [_rules_line()])
	print("seed | steps | outcome | min_band | starve_ticks | starve_damage | rations_eaten | rations_found | left")
	var starved := 0
	var outcomes: Dictionary = {}
	var stuck_reasons: Dictionary = {}
	for seed in SEEDS:
		var row := _run(seed)
		if int(row.starve_ticks) > 0: starved += 1
		outcomes[str(row.outcome)] = int(outcomes.get(str(row.outcome), 0)) + 1
		if not str(row.stuck_reason).is_empty():
			stuck_reasons[str(row.stuck_reason)] = int(stuck_reasons.get(str(row.stuck_reason), 0)) + 1
		print("%d | %d | %s | %s | %d | %d | %d | %d | %d" % [seed, row.steps, row.outcome,
			row.min_band, row.starve_ticks, row.starve_damage, row.eaten, row.found, row.left])
	print("---- starving runs: %d / %d (target solo <= 20%%) ----" % [starved, SEEDS.size()])
	print("---- outcomes: %s ----" % [_sorted_pairs(outcomes)])
	if not stuck_reasons.is_empty():
		print("---- stuck reasons: %s ----" % [_sorted_pairs(stuck_reasons)])
	quit(0)


func _run(seed: int) -> Dictionary:
	var session = Session.new(seed, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var food_id := str(Rules.rules().food_definition_id)
	var steps := 0
	var outcome := "BUDGET"
	var found := 0
	var idle := 0
	var seek_ready_at := 0
	var stuck_reason := ""
	session.start_auto_explore()
	while steps < STEP_BUDGET:
		var state = session.sim.world.party_encounter
		if str(state.safe_phase) == "PARTY_DEFEATED": outcome = "DEAD"; break
		if str(session.expedition_cycle_status().get("phase", "")) == "TOWN":
			outcome = "RETURNED"; break
		# Standing on the last implemented floor's exit ends the run: from here the
		# session refuses every exploration, route and item command, so this is a
		# finished expedition and not a jammed driver.
		if bool(session.run_progress().get("complete", false)): outcome = "COMPLETE"; break
		var phase := str(state.safe_phase)
		var progressed := false
		if phase == "CONTACT": progressed = _deploy(session)
		elif phase == "ENGAGED": progressed = _fight_one_turn(session)
		else:
			if _resolve_opening(session): progressed = true
			elif _pickup_food(session, food_id): progressed = true; found += 1
			else:
				var seek := _seek_food(session, food_id) if steps >= seek_ready_at else 0
				if seek > 0: progressed = true
				else:
					# A refused plan means the ration is still behind fog. Let AUTO
					# reveal more before paying for another route preview.
					if seek < 0: seek_ready_at = steps + FOOD_SEEK_COOLDOWN
					if bool(session.floor_transition_assessment().get("accepted", false)):
						progressed = bool(session.advance_campaign_floor().get("accepted", false))
						session.start_auto_explore()
					else: progressed = _explore_one_hop(session)
		if not progressed:
			# Nothing legal advanced the world this iteration. A run that can never
			# progress again is reported as STUCK rather than silently spun on.
			idle += 1
			if idle >= 3:
				outcome = "STUCK"
				stuck_reason = str(session.commit_exploration(
					Command.wait(int(state.protagonist_id))).get("reason", ""))
				break
			continue
		idle = 0
		steps += 1
	var starve_ticks := 0
	var starve_damage := 0
	var eaten := 0
	# The gauge dips below FED and is refilled inside the same tick, so the worst
	# band a run ever reached is only visible in the band-change ledger.
	var min_band := Rules.band(int(session.sim.world.party_encounter.ration_milli))
	for event in session.sim.world.events:
		match str(event.type):
			"party.ration_starve_tick": starve_ticks += 1
			"combat.starvation_damage": starve_damage += int(event.magnitude)
			"party.ration_eaten": eaten += 1
			"party.ration_changed":
				var after := str(event.data.get("after", "FED"))
				if int(BAND_ORDER.get(after, 0)) > int(BAND_ORDER.get(min_band, 0)):
					min_band = after
	return {"steps": steps, "outcome": outcome, "min_band": min_band,
		"starve_ticks": starve_ticks, "starve_damage": starve_damage, "eaten": eaten,
		"found": found, "left": int(session.sim.world.party_encounter.ration_milli / 1000),
		"stuck_reason": stuck_reason}


func _explore_one_hop(session) -> bool:
	if not bool(session.auto_explore_state().get("running", false)):
		session.start_auto_explore()
	if bool(session.auto_explore_state().get("running", false)) \
			and bool(session.continue_auto_explore().get("advanced", false)):
		return true
	# AUTO refuses to move (no safe frontier, an enemy already in view, …): spend
	# one WAIT so the world still advances and hunger keeps ticking.
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	return bool(session.commit_exploration(Command.wait(hero_id)).get("accepted", false))


func _resolve_opening(session) -> bool:
	# The wounded traveller blocks AUTO while the choice is pending. PASS keeps the
	# party solo, which is the party size the spec's target band is written for.
	var opening = session.sim.world.party_encounter.opening_event
	if opening == null or str(opening.choice) != "PENDING": return false
	var status: Dictionary = session.opening_event_status()
	if not bool(status.get("pass_enabled", false)): return false
	return bool(session.commit_opening_event_choice("PASS").get("accepted", false))


func _pickup_food(session, food_id: String) -> bool:
	var world = session.sim.world
	var hero = world.entities.get(int(world.party_encounter.protagonist_id))
	if hero == null: return false
	for row in world.item_state.ground_items.rows:
		if row.position != hero.position or str(row.item.definition_id) != food_id: continue
		if bool(session.pickup_ground_item(str(row.item.instance_id)).get("accepted", false)):
			return true
	return false


func _seek_food(session, food_id: String) -> int:
	## 1: committed one hop toward a ration lying on the floor. -1: a ration is in
	## range but no legal route reaches it yet. 0: nothing worth detouring for.
	## AUTO EXPLORE only chases unseen frontier, so without this a run walks past
	## the floor ration and the goblin drops and starves with food on the ground.
	var world = session.sim.world
	var hero = world.entities.get(int(world.party_encounter.protagonist_id))
	if hero == null: return 0
	var goal := Vector2i(-1, -1)
	var best := 0
	for row in world.item_state.ground_items.rows:
		if str(row.item.definition_id) != food_id or row.position == hero.position: continue
		var distance := maxi(absi(row.position.x - hero.position.x),
			absi(row.position.y - hero.position.y))
		if distance > FOOD_SEEK_RADIUS: continue
		# Nearest wins; ties resolve by row then column so the goal is seed-stable.
		if goal.x >= 0 and (distance > best or (distance == best \
				and (row.position.y > goal.y \
				or (row.position.y == goal.y and row.position.x > goal.x)))): continue
		best = distance
		goal = row.position
	if goal.x < 0: return 0
	var route: Dictionary = session.exploration_route_state()
	if bool(route.get("active", false)) and route.get("goal", []) == [goal.x, goal.y]:
		if bool(session.continue_exploration_route().get("accepted", false)): return 1
		session.cancel_exploration_route()
		return -1
	var preview: Dictionary = session.preview_exploration_route(goal)
	if not bool(preview.get("accepted", false)): return -1
	if bool(session.auto_explore_state().get("running", false)):
		session.cancel_auto_explore("auto_explore_user_command")
	if bool(route.get("active", false)): session.cancel_exploration_route()
	if not bool(session.start_exploration_route(goal,
			str(preview.get("plan_hash", ""))).get("accepted", false)):
		return -1
	return 1


func _deploy(session) -> bool:
	for preset in ["WEDGE", "LINE", "COLUMN"]:
		if not bool(session.preview_deployment(preset,
			session.available_companion_ids()).get("accepted", false)): continue
		return bool(session.commit_deployment().get("accepted", false))
	return false


func _fight_one_turn(session) -> bool:
	var status: Dictionary = session.party_status()
	var hero := int(status.protagonist_id)
	var hero_position := Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var targets: Array = session.enemy_targets()
	if targets.is_empty(): return false
	var enemy: Dictionary = targets[0]
	var enemy_position := Vector2i(int(enemy.position[0]), int(enemy.position[1]))
	var staged: Dictionary = {"accepted": false}
	if maxi(absi(hero_position.x - enemy_position.x),
			absi(hero_position.y - enemy_position.y)) == 1:
		staged = session.set_actor_action(hero, "MELEE", [], int(enemy.entity_id))
	else:
		for direction in [Vector2i(signi(enemy_position.x - hero_position.x),
				signi(enemy_position.y - hero_position.y)),
				Vector2i(signi(enemy_position.x - hero_position.x), 0),
				Vector2i(0, signi(enemy_position.y - hero_position.y))]:
			if direction == Vector2i.ZERO: continue
			staged = session.set_actor_action(hero, "MOVE",
				[hero_position.x + direction.x, hero_position.y + direction.y])
			if bool(staged.get("accepted", false)): break
	if not bool(staged.get("accepted", false)):
		staged = session.set_actor_action(hero, "HOLD")
	if not bool(staged.get("accepted", false)): return false
	return bool(session.commit_turn().get("accepted", false))


func _rules_line() -> String:
	var rules := Rules.rules()
	return "version=%s ration_max=%d hungry_below=%d drain=%d/+%d starve=%d/%d food=%d" % [
		str(rules.content_version), int(rules.ration_max), int(rules.hungry_below),
		int(rules.drain_per_interval_milli), int(rules.drain_extra_member_milli),
		int(rules.starve_damage), int(rules.starve_stress), int(rules.food_nutrition)]


func _sorted_pairs(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys: parts.append("%s=%d" % [str(key), int(counts[key])])
	return ", ".join(parts)
