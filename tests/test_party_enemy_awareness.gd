extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const DungeonMap=preload("res://playtest/deterministic_dungeon_map.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")
const PerceptionRegistry=preload("res://sim/enemy_perception_registry.gd")
const WorldState=preload("res://sim/world_state.gd")

func test_product_roster_is_deterministic_reachable_and_spawn_safe()->bool:
	for seed in [44,45,46]:
		var first:Dictionary=DungeonMap.generate(96,96,seed)
		var second:Dictionary=DungeonMap.generate(96,96,seed)
		check_eq(first.enemy_roster,second.enemy_roster,"same seed has exact enemy roster")
		check(first.enemy_roster.size()>=10 and first.enemy_roster.size()<=12,
			"product roster contains ten to twelve monsters")
		var occupied:Dictionary={}
		var hazard_positions:Dictionary={}
		for hazard in first.hazards:hazard_positions[hazard.position]=true
		var species:Dictionary={}
		for row in first.enemy_roster:
			var position:Vector2i=row.position
			species[str(row.species_id)]=true
			check(not occupied.has(position),"enemy spawns do not overlap")
			occupied[position]=true
			check(position not in [first.entry_position,first.exit_position] \
				and position not in first.door_positions and not hazard_positions.has(position),
				"enemy avoids entry exit door and hazard")
			check(DungeonMap.reachable(first,first.entry_position,position),
				"every enemy spawn is reachable")
		check(species.has("goblin") and species.has("kobold"),
			"product roster contains goblin and kobold")
	var legacy:Dictionary=DungeonMap.generate_legacy(48,48,44)
	check_eq(legacy.enemy_positions.size(),1,"legacy 48 map keeps one enemy")
	return finish()

func test_los_contest_is_monotonic_and_six_states_are_reachable()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var world=session.sim.world;var state=world.party_encounter
	var hero=world.entities[state.protagonist_id];var enemy=world.entities[state.enemy_ids[0]]
	var awareness=state.enemy_awareness(enemy.id)
	# Opening spawn is guaranteed on a clear five-cell line.
	var previous:=0
	for turn in range(1,9):
		check(session.sim.party_coordinator._update_enemy_awareness(enemy.id,turn),
			"awareness update succeeds")
		check(awareness.suspicion>=previous,"suspicion is monotonic while LOS is held")
		previous=awareness.suspicion
	check(awareness.awareness_state=="ALERT",
		"stable repeated sight reaches alert without rerolling")
	# Adjacency is an unconditional canonical HUNTING transition.
	enemy.position=hero.position+Vector2i.UP
	check(session.sim.party_coordinator._update_enemy_awareness(enemy.id,9) \
		and awareness.awareness_state=="HUNTING","adjacency forces hunting")
	# Losing LOS walks through SEARCHING then RETURNING. Moving home completes
	# the sixth state without a random check.
	enemy.position=awareness.home_position
	hero.position=session._map_layout.exit_position
	check(session.sim.party_coordinator._update_enemy_awareness(enemy.id,10) \
		and awareness.awareness_state=="SEARCHING","lost hunting target starts search")
	for turn in range(11,14):
		check(session.sim.party_coordinator._update_enemy_awareness(enemy.id,turn),
			"search countdown advances")
	check(awareness.awareness_state=="RETURNING","search exhaustion returns home")
	check(session.sim.party_coordinator._update_enemy_awareness(enemy.id,14) \
		and awareness.awareness_state=="UNAWARE","home arrival resets unaware")
	var transition_states:Dictionary={}
	for event in world.events:
		if event.type=="enemy.awareness_changed":transition_states[str(event.data.to_state)]=true
	for expected in ["SUSPICIOUS","ALERT","HUNTING","SEARCHING","RETURNING","UNAWARE"]:
		check(transition_states.has(expected),"transition event exists for %s"%expected)
	var blocked=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var blocked_state=blocked.sim.world.party_encounter
	var blocked_hero=blocked.sim.world.entities[blocked_state.protagonist_id]
	var blocked_enemy=blocked.sim.world.entities[blocked_state.enemy_ids[0]]
	blocked_enemy.position=blocked_hero.position+Vector2i(4,0)
	# Party bootstrap emits deterministic progression events, so its guarded
	# bootstrap terrain API is closed. This focused authority fixture changes the
	# immutable terrain ID directly before any simulated turn.
	blocked.sim.world.tile_at(blocked_hero.position+Vector2i(2,0)).terrain="wall"
	var blocked_awareness=blocked_state.enemy_awareness(blocked_enemy.id)
	check(blocked.sim.party_coordinator._update_enemy_awareness(blocked_enemy.id,1) \
		and blocked_awareness.suspicion==0,"wall blocks the deterministic sight contest")
	check(PerceptionRegistry.suspicion_gain("goblin",4,700) \
		<PerceptionRegistry.suspicion_gain("goblin",4,300),
		"higher hero stealth deterministically lowers suspicion gain")
	return finish()

func test_distant_monsters_do_not_join_combat_and_visible_dto_never_leaks_to_memory()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var near_id:=int(state.enemy_ids[0]);var far_id:=int(state.enemy_ids.back())
	state.enemy_awareness(near_id).awareness_state="HUNTING"
	state.enemy_awareness(near_id).suspicion=1000
	var far_forecast:Dictionary=session.sim.party_coordinator.forecast_enemy_action(far_id)
	check(not bool(far_forecast.accepted) and far_forecast.reason=="enemy_not_combat_aware",
		"distant unaware enemy cannot enter combat batch")
	var observation:Dictionary=session.observe_party_world()
	var visible_enemy:Dictionary={}
	for cell in observation.cells:
		for actor in cell.actors:
			if int(actor.entity_id)==near_id:visible_enemy=actor
	check(visible_enemy.has_all(["awareness_state","suspicion","sight_range",
		"perception","last_known_position","display_name","species_id"]),
		"visible enemy exposes awareness inspection fields")
	for cell in observation.cells:
		if str(cell.visibility_state)!="VISIBLE":
			check(cell.actors.is_empty(),"memory and unseen cells leak no awareness actor")
	var wire:Array=state.to_dict().enemy_awareness_rows
	for index in range(1,wire.size()):
		check(int(wire[index-1].enemy_id)<int(wire[index].enemy_id),
			"awareness wire rows stay entity-id sorted")
	var canonical=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var canonical_state=canonical.sim.world.party_encounter
	var canonical_hero=canonical.sim.world.entities[canonical_state.protagonist_id]
	var canonical_enemy=canonical.sim.world.entities[canonical_state.enemy_ids[0]]
	var direction:=Vector2i(signi(canonical_enemy.position.x-canonical_hero.position.x),
		signi(canonical_enemy.position.y-canonical_hero.position.y))
	check(bool(canonical.commit_exploration_direction(direction).accepted),
		"canonical movement advances awareness")
	var restored=Session.new(1,2,Session.SOLO_COMBAT_SCENARIO_ID)
	var load_result:Dictionary=restored.load_session_json(canonical.save_session_json())
	check(bool(load_result.accepted),"awareness save restores: %s"%str(load_result))
	if bool(load_result.accepted):check_eq(restored.sim.snapshot(),canonical.sim.snapshot(),
		"awareness save/load is exact")
	return finish()

func test_two_encounter_cycles_restore_with_strict_history()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var layout:Dictionary=DungeonMap.generate(96,96,44)
	var first_position:Vector2i=layout.enemy_positions[0]
	var second_position:=_second_opening_spawn(layout,first_position)
	var third_position:Vector2i=layout.enemy_positions.back()
	check(second_position!=Vector2i(-1,-1),"two-cycle fixture has a second opening-room spawn")
	check(third_position not in [first_position,second_position],
		"two-cycle fixture retains a distant survivor")
	if second_position==Vector2i(-1,-1) or third_position in [first_position,second_position]:
		return finish()
	layout.enemy_positions=[first_position,second_position,third_position]
	layout.enemy_roster=[{"position":first_position,"species_id":"goblin"},
		{"position":second_position,"species_id":"kobold"},
		{"position":third_position,"species_id":"goblin"}]
	check(session.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID,layout),
		"two-cycle compact product fixture initializes")
	var sandbox=Sandbox.new()
	sandbox.initialize_for_headless_test(session,true)
	var product_grid=sandbox.grid
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var first_enemy_id:=int(state.enemy_ids[0])
	check(_advance_product_input_to_threat(sandbox,session,hero_id,first_enemy_id),
		"first threat is internally ready in its triggering move")
	check(product_grid==sandbox.grid and not sandbox.phase_panel.visible,
		"first threat keeps the same product grid and hides internal phase chrome")
	check(sandbox.product_attack_button!=null and not sandbox.product_attack_button.visible \
		and sandbox.product_wait_guard_button.text=="[WAIT]",
		"solo product exposes bump movement without combat-only controls")
	check(_finish_visible_enemy(sandbox,session,hero_id,first_enemy_id),
		"first enemy is removed through same-grid movement and bump input")
	check_eq(session.party_status().safe_phase,"GROUPED",
		"surviving distant monsters do not pin global combat")
	var second_enemy_id:=int(state.enemy_ids[1])
	check(_advance_product_input_to_threat(sandbox,session,hero_id,second_enemy_id),
		"continued product movement reaches a second threat without a manual mode step")
	check(_finish_visible_enemy(sandbox,session,hero_id,second_enemy_id),
		"second enemy is removed and movement resumes: phase=%s life=%s error=%s"%[
			session.party_status().safe_phase,
			session.sim.world.combatant_states[second_enemy_id].life_state,
			session.sim.world.world_state_error()])
	check(product_grid==sandbox.grid and session.party_status().safe_phase=="GROUPED",
		"second removal returns to movement on the original grid")
	var error:String=session.sim.world.world_state_error()
	check_eq(error,"","two-cycle history remains canonical")
	var snapshot:Dictionary=session.sim.snapshot()
	var restored=WorldState.from_snapshot(snapshot)
	check(restored!=null,"two-cycle snapshot save/load restores")
	if restored!=null:check_eq(restored.snapshot(),snapshot,
		"two-cycle snapshot restores exactly")
	sandbox.free()
	return finish()

func _advance_product_input_to_threat(sandbox,session,hero_id:int,enemy_id:int)->bool:
	for ignored in range(40):
		if str(session.party_status().safe_phase)=="ENGAGED":return true
		if str(session.party_status().safe_phase)!="GROUPED":return false
		var enemy=session.sim.world.entities[enemy_id]
		var route:Dictionary=session.sim.pathfinder.find_path_to_any(hero_id,
			_adjacent_goals(enemy.position))
		if not bool(route.get("found",false)) or route.path.size()<2:return false
		var destination:Vector2i=route.path[1]
		var direction:Vector2i=destination-session.sim.world.entities[hero_id].position
		sandbox._on_product_direction(direction)
		sandbox._refresh()
	return str(session.party_status().safe_phase)=="ENGAGED"

func _finish_visible_enemy(sandbox,session,hero_id:int,enemy_id:int)->bool:
	if str(session.party_status().safe_phase)!="ENGAGED":return false
	for ignored in range(8):
		var hero=session.sim.world.entities[hero_id]
		var enemy=session.sim.world.entities[enemy_id]
		if maxi(absi(hero.position.x-enemy.position.x),
				absi(hero.position.y-enemy.position.y))<=1:break
		var route:Dictionary=session.sim.pathfinder.find_path_to_any(hero_id,
			_adjacent_goals(enemy.position))
		if not bool(route.get("found",false)) or route.path.size()<2:return false
		var destination:Vector2i=route.path[1]
		sandbox._on_product_direction(destination-hero.position)
	var hero=session.sim.world.entities[hero_id]
	var enemy=session.sim.world.entities[enemy_id]
	if maxi(absi(hero.position.x-enemy.position.x),
			absi(hero.position.y-enemy.position.y))>1:return false
	enemy.health=1
	for ignored in range(8):
		if str(session.sim.world.combatant_states[enemy_id].life_state)=="DEAD":break
		hero=session.sim.world.entities[hero_id]
		enemy=session.sim.world.entities[enemy_id]
		var direction:=Vector2i(signi(enemy.position.x-hero.position.x),
			signi(enemy.position.y-hero.position.y))
		sandbox._on_product_direction(direction)
	sandbox._refresh()
	return str(session.sim.world.combatant_states[enemy_id].life_state)=="DEAD" \
		and str(session.party_status().safe_phase)=="GROUPED"

func _second_opening_spawn(layout:Dictionary,first_position:Vector2i)->Vector2i:
	var entry:Vector2i=layout.entry_position
	var candidates:Array[Vector2i]=[]
	for y in range(maxi(1,entry.y-6),mini(int(layout.height)-1,entry.y+7)):
		for x in range(maxi(1,entry.x-6),mini(int(layout.width)-1,entry.x+7)):
			var position:=Vector2i(x,y)
			var distance:=maxi(absi(position.x-entry.x),absi(position.y-entry.y))
			if distance not in [5,6] or position==first_position \
					or DungeonMap.terrain_at(layout,position)=="wall" \
					or position in layout.door_positions:continue
			if not DungeonMap._terrain_line_of_sight(layout.terrain,int(layout.width),
					entry,position):continue
			candidates.append(position)
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):
		var ad:=maxi(absi(a.x-first_position.x),absi(a.y-first_position.y))
		var bd:=maxi(absi(b.x-first_position.x),absi(b.y-first_position.y))
		return ad>bd if ad!=bd else (a.y<b.y if a.y!=b.y else a.x<b.x))
	return Vector2i(-1,-1) if candidates.is_empty() else candidates[0]

func _adjacent_goals(position:Vector2i)->Array:
	var rows:Array=[]
	for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,
		Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
		rows.append(position+direction)
	return rows
