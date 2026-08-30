extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Grid=preload("res://playtest/party_grid_view.gd")
const Minimap=preload("res://playtest/party_minimap.gd")


func test_full_observer_stays_detached_while_ui_uses_world_coordinate_viewport_and_compact_minimap()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var full:Dictionary=session.observe_party_world()
	check_eq([full.width,full.height,full.cells.size()],[48,48,2304],
		"public observer keeps the established full rich map")
	var original_terrain:=str(full.cells[0].terrain_id)
	full.cells[0].terrain_id="CORRUPTED"
	check_eq(str(session.observe_party_world().cells[0].terrain_id),original_terrain,
		"public observer remains detached from presentation cache")

	var ui:Dictionary=session.observe_party_ui(15)
	var grid:Dictionary=ui.grid
	var minimap:Dictionary=ui.minimap
	var status:Dictionary=session.party_status()
	var hero:=Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var expected_origin:=hero-Vector2i(7,7)
	check_eq([grid.width,grid.height,grid.grid_mapping.origin,
		grid.grid_mapping.cell_count],[48,48,[expected_origin.x,expected_origin.y],225],
		"grid DTO retains world dimensions and hero-centered world origin")
	check(grid.cells.size()<=225,"grid DTO contains at most one 15x15 rich viewport")
	for cell in grid.cells:
		var position:=Vector2i(int(cell.position[0]),int(cell.position[1]))
		check(Rect2i(expected_origin,Vector2i(15,15)).has_point(position),
			"grid row stays inside world-coordinate viewport")

	# Seed a distant presentation-only explored origin to exercise MEMORY wire
	# safety without mutating canonical simulation history.
	session._cache_explored_origin(Vector2i(24,24))
	minimap=session.observe_party_ui(15).minimap
	var memory_count:=0
	for cell in minimap.cells:
		var keys:Array=cell.keys();keys.sort()
		check_eq(keys,["marker","position","terrain_id","visibility_state"],
			"compact minimap row has no rich live fields")
		if str(cell.visibility_state)=="MEMORY":
			memory_count+=1
			check(str(cell.marker).is_empty(),"memory row never carries a live marker")
	check(memory_count>0,"compact fixture includes distant terrain memory")
	check(minimap.cells.size()<2304,"never-seen minimap rows are omitted")
	return finish()


func test_explored_cache_processes_suffix_and_rebuilds_on_history_topology_reset_and_load()->bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	session.observe_party_world()
	var initial_cache:Dictionary=session._explored_presentation_cache
	var initial_visited:=int((initial_cache.visited as Dictionary).size())
	check_eq(int(initial_cache.scanned_event_count),session.sim.world.events.size(),
		"cold cache scans the canonical history once")
	var second:Dictionary=session.observe_party_world()
	check_eq(int(session._explored_presentation_cache.visited.size()),initial_visited,
		"unchanged refresh adds no LOS origins")
	check_eq(second,session.observe_party_world(),"warm cache observation stays exact")

	check(session.commit_exploration_direction(Vector2i.RIGHT).accepted,
		"fixture appends a canonical hero move suffix")
	session.observe_party_world()
	check_eq(int(session._explored_presentation_cache.scanned_event_count),
		session.sim.world.events.size(),"cache advances to the new canonical suffix")
	check(int(session._explored_presentation_cache.visited.size())>initial_visited,
		"new hero move contributes an explored origin")

	var removed_event=session.sim.world.events.pop_back()
	session.observe_party_world()
	check_eq(int(session._explored_presentation_cache.scanned_event_count),
		session.sim.world.events.size(),"history regression forces a bounded rebuild")
	session.sim.world.events.append(removed_event)
	session.observe_party_world()
	check_eq(int(session._explored_presentation_cache.scanned_event_count),
		session.sim.world.events.size(),"restored suffix is consumed again")

	var topology_before:=int(session._explored_presentation_cache.topology_fingerprint)
	var tile=session.sim.world.tile_at(Vector2i(1,1));var terrain_before:=str(tile.terrain)
	tile.terrain="wall" if terrain_before!="wall" else "stone_floor"
	session.observe_party_world()
	check(int(session._explored_presentation_cache.topology_fingerprint)!=topology_before,
		"topology change invalidates explored LOS cache")
	tile.terrain=terrain_before

	var encoded:=session.save_session_json()
	check(session.reset_party(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID),
		"reset fixture accepted")
	check(session._explored_presentation_cache.is_empty(),"reset clears presentation cache")
	check(session.load_session_json(encoded).accepted,"saved fixture reloads")
	check(session._explored_presentation_cache.is_empty(),"load clears presentation cache")
	return finish()


func test_grid_normalizes_once_preserves_actor_motion_and_minimap_accepts_legacy_rows()->bool:
	var grid=Grid.new();grid.size=Vector2(345,345)
	var first:=_actor_observation(Vector2i(7,7))
	grid.set_observation(first)
	first.cells[0].terrain_id="CORRUPTED"
	first.cells[0].actors[0].display_name="CORRUPTED"
	check(str(grid._cells["7:7"].terrain_id)!="CORRUPTED" \
		and str(grid._actors[0].display_name)!="CORRUPTED",
		"grid owns normalized cell and actor presentation rows")
	check_eq(grid._cells["7:7"].actors,[],"cell store does not retain rich actor payload")
	grid.arm_actor_motion([77],150)
	grid.set_observation(_actor_observation(Vector2i(8,7)))
	check(grid.actor_motion_state().has(77),
		"reduced previous visibility state still arms one-step actor motion")

	var minimap=Minimap.new()
	minimap.set_observation(_actor_observation(Vector2i(8,7)))
	check_eq(minimap.cell_draw_spec(Vector2i(8,7)).marker,"HERO",
		"minimap remains compatible with legacy rich observation rows")
	var stored_keys:Array=minimap._cells["8:7"].keys();stored_keys.sort()
	check_eq(stored_keys,["marker","terrain_id","visibility_state"],
		"minimap stores only compact scalar state")
	grid.free();minimap.free();return finish()


func test_sandbox_refresh_consumes_viewport_and_compact_minimap_without_ui_regression()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(412,915)
	sandbox.initialize_for_headless_test(session,false)
	check(sandbox.grid._cells.size()<=225,
		"sandbox main grid receives only the hero viewport")
	check(sandbox.minimap._cells.size()<2304,
		"sandbox minimap omits never-seen cells")
	for row in sandbox.minimap._cells.values():
		var keys:Array=row.keys();keys.sort()
		check_eq(keys,["marker","terrain_id","visibility_state"],
			"sandbox minimap retains no rich actor feature or hazard payload")
	check(sandbox.member_detail_panel!=null and sandbox.member_progression_window!=null \
		and sandbox.member_item_window!=null,
		"performance refresh remains compatible with skill and item windows")
	sandbox.free();return finish()


func _actor_observation(position:Vector2i)->Dictionary:
	return {"width":15,"height":15,"cells":[{"position":[position.x,position.y],
		"terrain_id":"floor","feature_id":"","visibility_state":"VISIBLE",
		"fire_intensity":0,"wetness":0,"effective_conductivity":0,"actors":[{
			"entity_id":77,"display_name":"Hero","position":[position.x,position.y],
			"logical_position":[position.x,position.y],
			"display_position":[position.x,position.y],"is_protagonist":true,
			"is_enemy":false,"faction_id":"party","roster_slot":0,
			"display_role":"PROTAGONIST"}]}]}
