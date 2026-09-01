extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const DungeonMap = preload("res://playtest/deterministic_dungeon_map.gd")
const Command = preload("res://sim/sim_command.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Style = preload("res://playtest/ascii_visual_style.gd")


func test_opening_anchors_actor_and_hexaco_are_seeded_safe_and_exact() -> bool:
	for seed in [1, 44, 99173, 20260901]:
		var layout: Dictionary = DungeonMap.generate(96, 96, seed)
		var anchors: Dictionary = DungeonMap.opening_event_anchors(layout, seed)
		var repeated: Dictionary = DungeonMap.opening_event_anchors(layout, seed)
		check_eq(anchors, repeated, "same seed opening anchors exact")
		check(not anchors.is_empty(), "seed %d produces opening anchors" % seed)
		if anchors.is_empty(): continue
		var path: Array = anchors.entry_exit_path
		var denominator := maxi(1, path.size() - 1)
		var goal_ratio := float(int(anchors.goal_index)) / float(denominator)
		check(goal_ratio >= 0.35 and goal_ratio <= 0.50,
			"seed %d convergence goal is in 35-50%% band" % seed)
		check(int(anchors.spawn_route_index) >= 6 \
				and int(anchors.spawn_route_index) <= 10,
			"seed %d opening actor is staged 6-10 route steps inside" % seed)
		var spawn: Vector2i = anchors.spawn_position
		var entry: Vector2i = layout.entry_position
		check(absi(spawn.x-entry.x)+absi(spawn.y-entry.y)>1,
			"opening actor is not collapsed directly beside the entrance")
		check(DungeonMap.reachable(layout, entry, spawn),
			"opening actor remains reachable from the entrance")
		check(DungeonMap.terrain_at(layout,spawn) not in ["", "wall"],
			"opening spawn is passable")
		check(spawn not in layout.enemy_positions,
			"opening spawn does not overlap an enemy")

	var a = Session.new(44, 11, Session.SOLO_COMBAT_SCENARIO_ID)
	var b = Session.new(44, 999, Session.SOLO_COMBAT_SCENARIO_ID)
	var c = Session.new(45, 11, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = a.sim.world.party_encounter
	var opening = state.opening_event
	check(opening != null, "SOLO_COMBAT bootstraps fixed opening event")
	if opening == null: return finish()
	var npc = a.sim.world.entities[opening.npc_entity_id]
	check_eq(opening.npc_entity_id, a.sim.world.entities.keys().max(),
		"opening NPC is spawned after the enemy roster")
	check(opening.npc_entity_id not in state.party_member_ids \
		and opening.npc_entity_id not in state.enemy_ids,
		"opening NPC is neither party nor enemy")
	check_eq([npc.health, npc.max_health,
		str(a.sim.world.combatant_states[npc.id].life_state)],
		[18, 90, "ACTIVE"], "opening NPC uses actual 20 percent ACTIVE health")
	check_eq(opening.hexaco_profile.to_dict(),
		b.sim.world.party_encounter.opening_event.hexaco_profile.to_dict(),
		"personality seed does not affect opening HEXACO")
	check(opening.hexaco_profile.to_dict() \
		!= c.sim.world.party_encounter.opening_event.hexaco_profile.to_dict(),
		"world seed changes opening HEXACO")
	var before := a.save_session_json()
	var dto: Dictionary = a.opening_event_status()
	dto.hexaco_profile.H = -1
	check_eq(a.save_session_json(), before, "opening observation is detached and pure")
	var generated_style:Dictionary=opening.hexaco_profile.style_summary()
	check_eq(dto.personality_style,generated_style,
		"opening HEXACO combination exposes its exact generated style")
	check(str(generated_style.label).split(" ").size()>=2,
		"opening HEXACO style is a concise combined phrase")
	check(a.opening_event_status().scene_summary.contains(
		"성격 인상 · %s"%str(generated_style.label)),
		"opening presentation explains the combination in player-facing words")
	check_eq(Hexaco.new({"H":900,"E":100,"X":500,"A":500,"C":500,"O":500}) \
		.style_summary().label, "대담한 원칙주의자",
		"HEXACO summary combines the strongest and second strongest poles")
	check_eq(Hexaco.new().style_summary().label, "균형 잡힌 현실주의자",
		"near-center profile receives a stable balanced style")
	check(not a.opening_event_status().can_interact,
		"opening choice is not exposed before the player finds the actor")
	check(_approach_opening(a), "player can follow the opening trail to the actor")
	check(a.opening_event_status().can_interact,
		"adjacent wounded actor exposes the choice")
	var blood_cells:Array=[]
	for cell in a.observe_party_world().get("cells",[]):
		if cell is Dictionary and str(cell.get("ground_mark_id",""))=="blood" \
				and str(cell.get("visibility_state","UNSEEN"))!="UNSEEN":
			blood_cells.append(cell)
	check(blood_cells.size()>=3,"opening route exposes a sparse readable blood trail")
	if not blood_cells.is_empty():
		var blood_spec:Dictionary=Style.ground_mark_spec(blood_cells[0])
		check_eq([blood_spec.glyph,blood_spec.color_hex],[";","#a42f3f"],
			"floor blood uses one fixed dried-red semicolon glyph")
	var story_bubbles:Array=a.world_speech_bubbles()
	check_eq(story_bubbles.size(),1,"opening choice publishes one major story bubble")
	if not story_bubbles.is_empty():
		check_eq([story_bubbles[0].actor_id,story_bubbles[0].dialogue_kind],
			[int(dto.npc_entity_id),"STORY_DIALOGUE"],
			"opening bubble stays attached to the wounded actor")
		story_bubbles[0].text="변조"
		check(a.world_speech_bubbles()[0].text!="변조",
			"story bubble projection is detached")
	var auto_step_before:=int(a.sim.world.step_index)
	var auto_stop:Dictionary=a.start_auto_explore()
	check_eq([auto_stop.running,auto_stop.stop_reason,
		a.sim.world.step_index-auto_step_before],
		[false,"auto_explore_interaction_discovered",0],
		"AUTO stops on the opening choice before spending another turn")
	check_eq(a.sim.world.world_state_error(), "", "opening bootstrap is canonical")
	return finish()


func test_give_and_pass_use_existing_authorities_and_duplicate_is_atomic_noop() -> bool:
	var give = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var give_state = give.sim.world.party_encounter
	var opening = give_state.opening_event
	var npc_id := int(opening.npc_entity_id)
	var hero_id := int(give_state.protagonist_id)
	var inventory_before := _potion_quantity(give)
	var hp_before := int(give.sim.world.entities[npc_id].health)
	var trust_before := int(give.sim.relationships.effective_relation(
		npc_id, hero_id).trust)
	var party_before: Array = give_state.party_member_ids.duplicate()
	check(_approach_opening(give), "GIVE fixture reaches the wounded actor")
	var result: Dictionary = give.commit_opening_event_choice("GIVE_POTION")
	check(result.accepted, "GIVE commits")
	check_eq(_potion_quantity(give), inventory_before - 1,
		"GIVE consumes exactly one existing potion")
	check_eq(give.sim.world.entities[npc_id].health,
		hp_before + 35, "GIVE restores actual NPC HP")
	var relation: Dictionary = give.sim.relationships.effective_relation(npc_id, hero_id)
	check_eq([relation.gratitude, relation.trust, relation.personal.trust_delta],
		[60, trust_before, 0], "gratitude changes without rewriting trust")
	check_eq(give.sim.world.party_encounter.party_member_ids, party_before,
		"aid does not recruit the NPC")
	check_eq(str(give.sim.world.party_encounter.opening_event.choice),
		"GAVE_POTION", "GIVE choice is authoritative")
	check_eq(give.sim.world.world_state_error(), "", "GIVE world remains canonical")
	var duplicate_before := give.save_session_json()
	var duplicate_journal: Array = give.command_journal.duplicate(true)
	var duplicate_time: int = give.sim.world.world_time
	var duplicate_rng: int = give.sim.world.rng.state
	var duplicate: Dictionary = give.commit_opening_event_choice("GIVE_POTION")
	check_eq([duplicate.accepted, duplicate.reason],
		[false, "opening_choice_already_committed"], "duplicate GIVE is rejected")
	check_eq([give.save_session_json(), give.command_journal,
		give.sim.world.world_time, give.sim.world.rng.state],
		[duplicate_before, duplicate_journal, duplicate_time, duplicate_rng],
		"duplicate choice changes no snapshot, journal, time, or RNG")
	var restored = Session.new(1, 2, Session.SOLO_COMBAT_SCENARIO_ID)
	var loaded: Dictionary = restored.load_session_json(give.save_session_json())
	check(loaded.accepted, "GIVE save loads")
	check_eq(JSON.parse_string(restored.save_session_json()),
		JSON.parse_string(give.save_session_json()),
		"GIVE save/load/journal replay is structurally exact")

	var passed = Session.new(45, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var pass_state = passed.sim.world.party_encounter
	var pass_npc := int(pass_state.opening_event.npc_entity_id)
	var pass_hero := int(pass_state.protagonist_id)
	var pass_inventory: Dictionary = pass_state.protagonist_inventory.to_dict()
	var pass_hp := int(passed.sim.world.entities[pass_npc].health)
	var pass_relation: Dictionary = passed.sim.relationships.effective_relation(pass_npc, pass_hero)
	check(_approach_opening(passed), "PASS fixture reaches the wounded actor")
	var pass_result: Dictionary = passed.commit_opening_event_choice("PASS")
	check(pass_result.accepted, "PASS commits")
	check_eq([pass_state.protagonist_inventory.to_dict(),
		passed.sim.world.entities[pass_npc].health,
		passed.sim.relationships.effective_relation(pass_npc, pass_hero)],
		[pass_inventory, pass_hp, pass_relation],
		"PASS leaves inventory, HP, and relation unchanged")
	check_eq(passed.sim.world.world_state_error(), "", "PASS world remains canonical")
	return finish()


func test_same_actor_travels_adjacent_and_reencounter_records_once() -> bool:
	var session = Session.new(77, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	state.party_detection_radius = 0
	state.enemy_detection_radius = 0
	for enemy_id in state.enemy_ids: state.enemy_busy_rows[enemy_id] = 1000000
	check_eq(session.sim.world.world_state_error(), "", "quiet travel fixture is valid")
	check(_approach_opening(session), "travel fixture reaches the wounded actor")
	check(session.commit_opening_event_choice("PASS").accepted,
		"travel fixture commits PASS")
	var opening = state.opening_event
	var npc_id := int(opening.npc_entity_id)
	var hero_id := int(state.protagonist_id)
	var guard := 0
	while session.sim.world.entities[npc_id].position != opening.convergence_goal \
			and guard < 256:
		var wait_result: Dictionary = session.commit_exploration(Command.wait(hero_id))
		check(wait_result.accepted, "NPC travel wait %d commits" % guard)
		if not wait_result.accepted: break
		guard += 1
	check(guard < 256, "opening NPC reaches convergence goal")
	var move_rows: Array = []
	for event in session.sim.world.events:
		if event.type == "action.move" and event.actor_id == npc_id:
			move_rows.append(event)
	check(not move_rows.is_empty(), "opening NPC uses actual movement events")
	for event in move_rows:
		var from := Vector2i(int(event.data.from_position[0]),
			int(event.data.from_position[1]))
		check(maxi(absi(event.position.x-from.x),absi(event.position.y-from.y))==1,
			"opening NPC movement is adjacent, never teleport")

	var target: Vector2i = opening.convergence_band[0]
	var best_distance := 999999
	for candidate in opening.convergence_band:
		if candidate == opening.convergence_goal: continue
		var distance := maxi(absi(candidate.x-opening.convergence_goal.x),
			absi(candidate.y-opening.convergence_goal.y))
		if distance < best_distance and session.sim.world.blocking_entity_at(candidate)==null:
			best_distance = distance; target = candidate
	var route: Dictionary = session.sim.find_path(hero_id, target)
	check(route.found, "hero can approach convergence band canonically")
	if route.get("found", false):
		for index in range(1, route.path.size()):
			var moved: Dictionary = session.commit_exploration(
				Command.move_to(hero_id, route.path[index]))
			check(moved.accepted, "hero convergence approach step commits")
			if not moved.accepted: break
			if state.opening_event.reencounter_event_id > 0: break
	if state.opening_event.reencounter_event_id == -1:
		check(session.commit_exploration(Command.wait(hero_id)).accepted,
			"reencounter observation wait commits")
	check(state.opening_event.reencounter_event_id > 0,
		"central-band LOS records reencounter")
	var reencounter_count := 0
	for event in session.sim.world.events:
		if event.type == "opening.reencountered": reencounter_count += 1
	check(session.commit_exploration(Command.wait(hero_id)).accepted,
		"post-reencounter wait commits")
	var after_count := 0
	for event in session.sim.world.events:
		if event.type == "opening.reencountered": after_count += 1
	check_eq([reencounter_count, after_count], [1, 1],
		"reencounter is recorded at most once")
	check_eq(session.sim.world.world_state_error(), "",
		"travel and reencounter remain canonical")
	return finish()


func test_legacy_nullable_migration_corpse_observation_and_mobile_choices() -> bool:
	var legacy = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(legacy.reset_party(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID,
		{}, false), "legacy bootstrap-off fixture resets")
	var legacy_wire: Dictionary = JSON.parse_string(legacy.save_session_json())
	legacy_wire.snapshot.party_encounter.schema_version = 9
	legacy_wire.snapshot.party_encounter.erase("opening_event")
	var legacy_target = Session.new(55, 66, Session.SOLO_COMBAT_SCENARIO_ID)
	var legacy_load: Dictionary = legacy_target.load_session_json(
		JSON.stringify(legacy_wire))
	check(legacy_load.accepted, "schema-9 save migrates with nullable opening event")
	check(legacy_target.sim.world.party_encounter.opening_event == null,
		"legacy replay does not bootstrap a new opening NPC")

	var corpse = Session.new(88, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var corpse_state = corpse.sim.world.party_encounter
	var corpse_id := int(corpse_state.opening_event.npc_entity_id)
	var corpse_entity = corpse.sim.world.entities[corpse_id]
	check(_approach_opening(corpse), "corpse fixture reaches the wounded actor")
	var tile = corpse.sim.world.tile_at(corpse_entity.position)
	tile.flammability = 100
	var ignition = corpse.sim.step(Command.ignite(corpse_entity.position, 100,
		corpse_state.protagonist_id))
	check(ignition.accepted, "canonical ignition starts corpse fixture")
	for index in range(6):
		if corpse.sim.world.combatant_states[corpse_id].life_state == "DEAD": break
		corpse.sim.step(Command.wait(corpse_state.protagonist_id))
	check_eq(str(corpse.sim.world.combatant_states[corpse_id].life_state),
		"DEAD", "opening NPC can actually die")
	check(not corpse.sim.world.occupies_tile(corpse_id),
		"dead opening NPC does not occupy the tile")
	var corpse_cell: Dictionary = _cell(corpse.observe_party_world(),
		corpse_entity.position)
	var corpse_row: Dictionary = {}
	for actor in corpse_cell.get("actors", []):
		if int(actor.entity_id) == corpse_id: corpse_row = actor
	check(not corpse_row.is_empty() and corpse_row.life_state == "DEAD" \
		and bool(corpse_row.get("is_corpse", false)),
		"same dead actor is presented as a visible corpse")

	for viewport_size in [Vector2(360,640), Vector2(450,800)]:
		var sandbox = Sandbox.new(); sandbox.size = viewport_size
		var mobile_session = Session.new(44, 20260828,
			Session.SOLO_COMBAT_SCENARIO_ID)
		check(_approach_opening(mobile_session),
			"%s mobile fixture reaches the wounded actor" % viewport_size)
		sandbox.initialize_for_headless_test(mobile_session)
		sandbox.grid.size=Vector2(viewport_size.x,viewport_size.x)
		check_eq([sandbox.product_auto_button.text,
			sandbox.product_interact_button.text],
			["[물약 주기]", "[돕지 않기]"],
			"%s exposes both opening choices" % viewport_size)
		check(sandbox.product_auto_button.custom_minimum_size.y >= 44.0 \
			and sandbox.product_interact_button.custom_minimum_size.y >= 44.0,
			"%s opening choice touch targets are at least 44px" % viewport_size)
		var opening_bubbles:Array=sandbox.grid.speech_bubble_draw_specs()
		check_eq(opening_bubbles.size(),1,
			"%s opening dialogue is visible over the map"%viewport_size)
		if not opening_bubbles.is_empty():
			var bubble_rect:Rect2=opening_bubbles[0].rect
			check(sandbox.grid.grid_rect().grow(-3.0).encloses(bubble_rect),
				"%s opening bubble stays inside the map"%viewport_size)
		var journal_before: int = sandbox.session.command_journal.size()
		sandbox._activate_product_control("ProductAuto")
		check_eq(sandbox.session.command_journal.size(), journal_before + 1,
			"%s one activation commits one choice" % viewport_size)
		check_eq(str(sandbox.session.sim.world.party_encounter.opening_event.choice),
			"GAVE_POTION", "%s touch GIVE reaches authority" % viewport_size)
		sandbox.free()
	return finish()


func _potion_quantity(session) -> int:
	var item = session.sim.world.party_encounter.protagonist_inventory.item(
		"START_POTION_001")
	return int(item.quantity) if item != null else 0


func _approach_opening(session) -> bool:
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var npc = session.sim.world.entities.get(state.opening_event.npc_entity_id)
	if npc == null: return false
	# Follow the authored blood-trail corridor first. Generic shortest-path ties
	# may cut diagonally toward the visible tutorial monster, which is deliberately
	# outside this fixed-event unit test's concern.
	var anchors: Dictionary = DungeonMap.opening_event_anchors(
		session._map_layout, session.world_seed)
	var opening_route: Array = anchors.get("entry_exit_path", [])
	var spawn_route_index := int(anchors.get("spawn_route_index", -1))
	if spawn_route_index > 0 and opening_route.size() > spawn_route_index:
		for index in range(1, spawn_route_index + 1):
			if bool(session.opening_event_status().get("can_interact", false)):
				return true
			var result: Dictionary = session.commit_exploration(
				Command.move_to(hero_id, opening_route[index]))
			if not bool(result.get("accepted", false)): return false
	if bool(session.opening_event_status().get("can_interact", false)): return true
	var best: Dictionary = {}
	for direction in [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
			Vector2i(-1,0), Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1),
			Vector2i(1,1)]:
		var route: Dictionary = session.find_exploration_path(
			hero_id, npc.position + direction)
		if not bool(route.get("found", false)): continue
		if best.is_empty() or int(route.get("steps", 999999)) \
				< int(best.get("steps", 999999)):
			best = route
	if best.is_empty(): return false
	for index in range(1, best.path.size()):
		var result: Dictionary = session.commit_exploration(
			Command.move_to(hero_id, best.path[index]))
		if not bool(result.get("accepted", false)): return false
	return bool(session.opening_event_status().get("can_interact", false))


func _cell(observation: Dictionary, position: Vector2i) -> Dictionary:
	for cell in observation.get("cells", []):
		if cell.position == [position.x, position.y]: return cell
	return {}
