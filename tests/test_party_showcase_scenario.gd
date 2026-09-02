extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Action = preload("res://sim/party_action_command.gd")
const Command = preload("res://sim/sim_command.gd")
const TerrainRegistry = preload("res://sim/terrain_registry.gd")


func test_showcase_fixture_is_exact_deterministic_and_provenance_safe() -> bool:
	var first = Session.new(44, 20260828, "SHOWCASE_V1")
	var second = Session.new(44, 20260828, "SHOWCASE_V1")
	check(first.sim != null and second.sim != null, "showcase sessions initialize")
	check_eq(first.sim.snapshot(), second.sim.snapshot(), "same seeds produce exact showcase snapshot")
	check_eq(first.sim.world.world_state_error(), "", "showcase world is settled and valid")
	var state = first.sim.world.party_encounter
	check_eq([state.party_detection_radius, state.enemy_detection_radius], [3, 3],
		"showcase detection radii")
	check_eq(first.sim.world.entities[state.protagonist_id].position, Vector2i(2, 12),
		"showcase hero position")
	check_eq(first.sim.world.entities[state.enemy_ids[0]].position, Vector2i(6, 11),
		"showcase enemy position")
	var expected_rows := [
		"###############", "#......#......#", "#......#......#",
		"#......#......#", "#......#......#", "#......#......#",
		"#..rr..+......#", "#......#......#", "#.www..#..rr..#",
		"#.www..#..rr..#", "#.mmm..#......#", "#.....E#......#",
		"#.@.ff.#......#", "#......#......#", "###############",
	]
	var terrain_by_glyph := {"#":"wall", ".":"stone_floor", "+":"stone_floor",
		"@":"stone_floor", "E":"stone_floor", "r":"rubble",
		"w":"shallow_water", "m":"metal", "f":"wood_floor"}
	for y in range(expected_rows.size()):
		for x in range(expected_rows[y].length()):
			check_eq(first.sim.world.tile_at(Vector2i(x, y)).terrain,
				terrain_by_glyph[expected_rows[y][x]], "showcase terrain %d,%d" % [x, y])
	var wet_metal = first.sim.world.tile_at(Vector2i(3, 10))
	var wet_wood = first.sim.world.tile_at(Vector2i(4, 12))
	var fire = first.sim.world.tile_at(Vector2i(5, 12))
	check_eq([wet_metal.wetness, wet_wood.wetness, fire.fire], [80, 60, 80],
		"showcase exact hazards")
	check(wet_metal.wetness_source_event_id > 0 and wet_wood.wetness_source_event_id > 0
		and fire.fire_source_event_id > 0, "showcase hazards retain source events")
	check_eq(first.sim.world.events.map(func(event): return event.type),
		["environment.water_applied", "environment.water_applied", "environment.ignited",
			"party.rescue_discovered"],
		"showcase bootstrap event order")
	check(first.reset_party(44,303030,"SHOWCASE_V1"),"new-personality reset rebuilds showcase")
	var reset_state=first.sim.world.party_encounter
	check_eq(first.sim.world.entities[reset_state.enemy_ids[0]].position,Vector2i(6,11),
		"new-personality reset preserves world-seed monster spawn")
	return finish()


func test_showcase_observation_has_los_fog_renderer_fields_and_no_hidden_leaks() -> bool:
	var session = Session.new(44, 20260828, "SHOWCASE_V1")
	var state = session.sim.world.party_encounter
	var snapshot_before: Dictionary = session.sim.snapshot()
	var observation: Dictionary = session.observe_party_world()
	var hero_cell := _cell(observation, Vector2i(2, 12))
	var fire_cell := _cell(observation, Vector2i(5, 12))
	var door_cell := _cell(observation, Vector2i(7, 6))
	var blocked_cell := _cell(observation, Vector2i(8, 12))
	var enemy_cell := _cell(observation, Vector2i(6, 11))
	check_eq(hero_cell.visibility_state, "VISIBLE", "hero cell visible")
	check_eq(fire_cell.visibility_state, "VISIBLE", "near fire visible")
	check_eq([fire_cell.terrain_id, fire_cell.fire_intensity], ["wood_floor", 80],
		"visible fire is rendered from authoritative tile")
	check_eq([door_cell.visibility_state, door_cell.feature_id], ["VISIBLE", "open_door"],
		"radius-six doorway visible")
	for hidden in [blocked_cell]:
		check_eq(hidden.visibility_state, "UNSEEN", "hidden cell visibility")
		check_eq([hidden.terrain_id, hidden.fire_intensity, hidden.wetness,
			hidden.effective_conductivity, hidden.feature_id, hidden.actors],
			["unknown", 0, 0, 0, "", []], "hidden cell leaks no renderer state")
	check_eq(enemy_cell.visibility_state,"VISIBLE","distant showcase monster starts inside FOV")
	check_eq(enemy_cell.actors.size(),1,"visible monster is an authoritative actor glyph")
	check_eq([enemy_cell.actors[0].entity_id,enemy_cell.actors[0].display_role],
		[state.enemy_ids[0],"ENEMY"],"initial monster observation identity")
	check_eq(session.party_status().safe_phase,"GROUPED","visible range four monster does not auto-contact")
	check_eq(hero_cell.actors.size(), 1, "only deployed hero occupies initial visible cell")
	var hero: Dictionary = hero_cell.actors[0]
	for key in ["kind", "species_id", "max_health", "life_state", "status_ids",
			"guarded", "facing"]:
		check(hero.has(key), "renderer actor field %s" % key)
	check_eq([hero.kind, hero.species_id, hero.max_health, hero.life_state],
		["hero", "human", 120, "ACTIVE"], "hero renderer semantics")
	check_eq([hero.logical_position, hero.display_position, hero.display_role],
		[[2, 12], [2, 12], "PROTAGONIST"], "hero display identity")
	var party_actors: Array = []
	for cell in observation.cells:
		for actor in cell.actors:
			if str(actor.faction_id) == "party": party_actors.append(actor)
	party_actors.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.roster_slot) < int(b.roster_slot))
	check_eq(party_actors.size(), 3, "all grouped party members remain visible")
	check_eq([party_actors[1].display_position, party_actors[2].display_position],
		[[1, 12], [2, 11]], "followers prefer trail then fixed adjacent fallback")
	for follower in party_actors.slice(1):
		check_eq([follower.logical_position, follower.display_role, follower.presence],
			[[2, 12], "FOLLOWER", "GROUPED"], "follower is presentation-only")
		check_eq(_cell(observation, Vector2i(int(follower.display_position[0]),
			int(follower.display_position[1]))).visibility_state, "VISIBLE",
			"follower never leaks through unseen fog")
	check_eq(session.sim.snapshot(), snapshot_before,
		"follower projection does not mutate authoritative simulation")
	var detached := session.observe_party_world()
	detached.cells[0].terrain_id = "corrupted"
	detached.cells[0].actors.append({"entity_id":999})
	hero.status_ids.append("CORRUPTED")
	party_actors[1].display_position[0] = 999
	var fresh := session.observe_party_world()
	check(fresh.cells[0].terrain_id != "corrupted" and fresh.cells[0].actors.is_empty(),
		"observation cells are detached")
	check(not "CORRUPTED" in _cell(fresh, Vector2i(2, 12)).actors[0].status_ids,
		"nested actor status rows are detached")
	check_eq(_cell(fresh, Vector2i(1, 12)).actors[0].display_position, [1, 12],
		"nested follower display position is detached")
	return finish()


func test_grouped_followers_stay_visible_when_trail_crosses_wall_and_facing_changes() -> bool:
	var session = Session.new(44, 20260828, "SHOWCASE_V1")
	var state = session.sim.world.party_encounter
	var fixtures := [
		# Facing left makes the second nominal trail cell (8,5) sit behind the
		# solid x=7 wall. It must be rejected as presentation-hidden.
		{"anchor":Vector2i(6,5), "facing":Vector2i.LEFT},
		# A corner-facing case leaves several out-of-bounds/wall candidates.
		{"anchor":Vector2i(1,1), "facing":Vector2i.RIGHT},
	]
	for fixture in fixtures:
		var anchor:Vector2i=fixture.anchor
		state.group_anchor=anchor;state.facing=fixture.facing
		for member_id in state.party_member_ids:
			session.sim.world.entities[int(member_id)].position=anchor
		var before:Dictionary=session.sim.snapshot()
		var observation:Dictionary=session.observe_party_world()
		var party_actors:Array=[]
		for cell in observation.cells:
			for actor in cell.actors:
				if str(actor.faction_id)=="party":party_actors.append(actor)
		check_eq(party_actors.size(),3,
			"hero plus both followers remain visible at %s facing %s"%[anchor,fixture.facing])
		var follower_ids:Array=[]
		for actor in party_actors:
			if str(actor.display_role)!="FOLLOWER":continue
			follower_ids.append(int(actor.entity_id))
			var display:=Vector2i(int(actor.display_position[0]),int(actor.display_position[1]))
			check_eq(_cell(observation,display).visibility_state,"VISIBLE",
				"follower display cell remains presentation-visible")
			var terrain:=TerrainRegistry.definition(str(session.sim.world.tile_at(display).terrain))
			check(session.sim.world.in_bounds(display) and bool(terrain.get("passable",false)),
				"distinct/fallback follower display stays on valid terrain")
		check_eq(follower_ids.size(),2,"both grouped follower DTOs retained")
		check_eq(session.sim.snapshot(),before,"follower placement remains observation-only")
	return finish()


func test_showcase_session_v4_save_load_replays_scenario_and_rejects_tamper() -> bool:
	var source = Session.new(91, 92, "SHOWCASE_V1")
	var hero := int(source.party_status().protagonist_id)
	check(source.commit_exploration(Command.move_to(hero, Vector2i(3, 11))).accepted,
		"showcase journal move")
	var encoded := source.save_session_json()
	var wire: Dictionary = JSON.parse_string(encoded)
	check_eq(wire.keys().size(), 7, "session v5 exact top key count")
	check_eq([int(wire.session_format_version), wire.scenario_id], [5, "SHOWCASE_V1"],
		"session v5 scenario identity")
	var restored = Session.new(1, 2)
	var loaded: Dictionary = restored.load_session_json(encoded)
	check(bool(loaded.accepted), "showcase v4 load accepted: %s" % str(loaded))
	check_eq(restored.scenario_id, "SHOWCASE_V1", "loaded scenario identity")
	check_eq(restored.sim.snapshot(), source.sim.snapshot(), "showcase journal replay exact")
	var before: Dictionary = restored.sim.snapshot()
	var before_journal: Array = restored.command_journal.duplicate(true)
	var bad := wire.duplicate(true); bad.scenario_id = "UNKNOWN_SCENARIO"
	var rejected: Dictionary = restored.load_session_json(JSON.stringify(bad))
	check(not bool(rejected.accepted), "unknown scenario rejected")
	check_eq([restored.sim.snapshot(), restored.command_journal], [before, before_journal],
		"scenario tamper is transactional")
	return finish()


func test_auto_combat_placeholder_is_pure_uncommittable_and_replace_keeps_overrides() -> bool:
	var session = _engaged_regression()
	var state = session.sim.world.party_encounter
	var hero := int(state.protagonist_id)
	var companion := int(state.party_member_ids[1])
	var before_world: Dictionary = session.sim.snapshot()
	var before_journal: Array = session.command_journal.duplicate(true)
	var prepared: Dictionary = session.prepare_auto_combat_plan()
	check(bool(prepared.active) and bool(prepared.placeholder), "placeholder planning active")
	check(not bool(prepared.commit_ready), "placeholder cannot commit")
	var cards: Array[Dictionary] = session.party_cards()
	var hero_card: Dictionary = cards.filter(func(row: Dictionary):
		return int(row.entity_id) == hero)[0]
	check(hero_card.expected_action == null and hero_card.override_state == "PENDING",
		"placeholder hero remains explicit input-waiting presentation")
	var overlays: Array[Dictionary] = session.turn_intent_overlays()
	check_eq(overlays.size(), 2, "placeholder keeps two companion suggestions visible")
	for overlay in overlays:
		check(int(overlay.actor_id) != hero and str(overlay.source) == "SUGGESTED",
			"placeholder hero overlay absent and companion suggestion retained")
	check_eq(session.turn_summary_lines().size(), 2,
		"placeholder hero HOLD is absent from summary")
	check_eq([session.sim.snapshot(), session.command_journal], [before_world, before_journal],
		"placeholder preparation does not touch world or journal")
	var rejected: Dictionary = session.commit_turn()
	check(not bool(rejected.accepted), "placeholder commit rejected")
	check_eq([session.sim.snapshot(), session.command_journal], [before_world, before_journal],
		"placeholder commit rejection is pure")
	check(session.override_companion(companion, Action.hold(companion)).accepted,
		"placeholder accepts companion override")
	var replaced: Dictionary = session.replace_auto_combat_protagonist_action(Action.hold(hero))
	check(bool(replaced.active) and not bool(replaced.placeholder) and bool(replaced.commit_ready),
		"real protagonist action makes plan commit-ready")
	var source_by_actor := {}
	for row in replaced.preview.actor_rows: source_by_actor[int(row.actor_id)] = str(row.source)
	check_eq(source_by_actor[companion], "OVERRIDE", "protagonist replacement preserves override")
	var detached: Dictionary = session.auto_combat_planning_state()
	detached.preview.actor_rows.clear()
	check(not session.auto_combat_planning_state().preview.actor_rows.is_empty(),
		"planning DTO is detached")
	return finish()


func test_showcase_companion_follow_plan_is_pure_same_path_risk_projection() -> bool:
	var session = Session.new(44, 20260828, "SHOWCASE_V1")
	var before: Dictionary = session.sim.snapshot()
	var journal_before: Array = session.command_journal.duplicate(true)
	var route: Dictionary = session.preview_exploration_route(Vector2i(7, 6))
	check(bool(route.accepted) and int(route.total_steps) >= 2, "showcase door route preview")
	var plan: Dictionary = session.exploration_companion_follow_plan(route)
	check(bool(plan.accepted), "companion follow plan accepted")
	check_eq(plan.path, route.path, "followers project the same grouped route")
	check_eq(plan.companion_rows.size(), 2, "two living grouped companion suggestions")
	for row in plan.companion_rows:
		check_eq([row.source, row.mode, row.path], ["SUGGESTED", "FOLLOW_ROUTE", route.path],
			"follower semantic and path")
		check(row.max_total_risk >= 0 and row.component_maxima.keys().size() == 5,
			"follower aggregates existing member risk ceilings")
	check_eq([session.sim.snapshot(), session.command_journal], [before, journal_before],
		"follow planning is pure")
	plan.path[0][0] = 999; plan.companion_rows[0].path[0][0] = 998
	var fresh: Dictionary = session.exploration_companion_follow_plan(route)
	check(fresh.path[0][0] != 999 and fresh.companion_rows[0].path[0][0] != 998,
		"follow planning DTO is detached")
	return finish()


func _engaged_regression():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"auto-plan contact fixture")
	check(session.preview_deployment("LINE", session.available_companion_ids()).accepted,
		"auto-plan deployment preview")
	check(session.commit_deployment().accepted, "auto-plan deployment")
	return session


func _cell(observation: Dictionary, position: Vector2i) -> Dictionary:
	for row in observation.get("cells", []):
		if row is Dictionary and row.get("position", []) == [position.x, position.y]:
			return row
	return {}
