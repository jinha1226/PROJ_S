extends SceneTree


const Session = preload("res://playtest/party_playtest_session.gd")
const BaseRules = preload("res://sim/base_progression_rules.gd")
const BasePanel = preload("res://playtest/base_progress_panel.gd")
const SettlementView = preload("res://playtest/base_settlement_view.gd")
const ProgressionAcceptance = preload("res://tests/base_progression_acceptance.gd")

const WORLD_SEED := 44
const PERSONALITY_SEED := 20260828
const DUO := "DUO_AUTOBATTLE_V1"
const LANDMARK_IDS := ["STORAGE", "LODGE", "GATE"]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = _prepare_town_session()
	if session == null:
		_finish()
		return
	var town_overview: Dictionary = session.base_overview()
	_check(str(town_overview.get("phase", "")) == "TOWN",
		"visual smoke starts from a canonical town return")

	var panel_360 = await _mount_panel(town_overview, 360, false, "STORAGE")
	var map_360 = panel_360.find_child("BaseSettlementMap", true, false) as Control
	_check_map_budget(panel_360, map_360, 360)
	var level_one_state: Dictionary = {}
	var level_one_cost := ""
	if map_360 != null:
		level_one_state = map_360.building_visual_state("STORAGE")
	var level_one_cost_label := panel_360.find_child("BaseFacilityCostSTORAGE", true, false) as Label
	if level_one_cost_label != null:
		level_one_cost = level_one_cost_label.text
	await _check_real_selection_and_drag(panel_360, map_360)

	panel_360.queue_free()
	await process_frame
	var panel_390 = await _mount_panel(town_overview, 390, false, "STORAGE")
	var map_390 = panel_390.find_child("BaseSettlementMap", true, false) as Control
	_check_map_budget(panel_390, map_390, 390)
	panel_390.queue_free()
	await process_frame

	# This is the real authoritative upgrade: the haul was gathered and extracted
	# through the public session facade in _prepare_town_session().
	var upgrade_events_before := _count_world_events(session, "base.facility_upgraded")
	var stock_before: Dictionary = town_overview.get("stock", {}).duplicate(true)
	var upgrade: Dictionary = session.base_upgrade("STORAGE")
	_check(bool(upgrade.get("accepted", false)),
		"canonical STORAGE upgrade is affordable and commits")
	_check_eq(_count_world_events(session, "base.facility_upgraded"),
		upgrade_events_before + 1, "one upgrade action emits one authoritative event")
	var upgraded_overview: Dictionary = session.base_overview()
	var storage_cost: Dictionary = BaseRules.cost("STORAGE", 2)
	for resource_id in BaseRules.RESOURCE_IDS:
		_check_eq(int(upgraded_overview.stock.get(resource_id, 0)),
			int(stock_before.get(resource_id, 0)) - int(storage_cost.get(resource_id, 0)),
			"upgrade consumes only the published %s cost" % resource_id)

	# Rebuilding the production panel with the current selection keeps the detail
	# open, while the same view reports the changed visual stage.
	var rebuilt_panel = await _mount_panel(upgraded_overview, 360, false, "LODGE")
	var rebuilt_map = rebuilt_panel.find_child("BaseSettlementMap", true, false) as Control
	var rebuilt_state: Dictionary = {}
	if rebuilt_map != null:
		rebuilt_state = rebuilt_map.building_visual_state("LODGE")
	_check(bool(rebuilt_state.get("selected", false)),
		"panel rebuild preserves the selected building")
	var selection_heading := rebuilt_panel.find_child("BaseSelectionHeading", true, false) as Label
	_check(selection_heading != null and "숙소" in selection_heading.text,
		"rebuild keeps the selected building detail visible")
	_check(rebuilt_panel.find_child("BaseFacilityLODGE", true, false) != null,
		"selected facility detail is present after rebuild")
	if rebuilt_map != null:
		var upgraded_storage_state: Dictionary = rebuilt_map.building_visual_state("STORAGE")
		_check(str(upgraded_storage_state.get("visual_stage", "")) != str(
			level_one_state.get("visual_stage", "")),
			"canonical upgrade changes the visible storage stage")
	rebuilt_panel.present(upgraded_overview, false, "STORAGE")
	await process_frame
	await process_frame
	var upgraded_cost_label := rebuilt_panel.find_child("BaseFacilityCostSTORAGE", true, false) as Label
	_check(upgraded_cost_label != null and upgraded_cost_label.text != level_one_cost,
		"canonical upgrade refreshes the selected building cost snapshot")
	rebuilt_panel.queue_free()
	await process_frame

	await _check_three_visual_stages(upgraded_overview)

	var departure: Dictionary = session.depart_town()
	_check(bool(departure.get("accepted", false)),
		"canonical upgraded session can depart for dungeon preview")
	var dungeon_overview: Dictionary = session.base_overview()
	var preview_panel = await _mount_panel(dungeon_overview, 360, true, "MARKET")
	_check(preview_panel.find_child("BaseLandmarkOpenMARKET", true, false) == null,
		"dungeon preview exposes no spendable landmark service")
	_check(preview_panel.find_child("BaseLandmarkReasonMARKET", true, false) != null,
		"dungeon preview explains town-only landmark service")
	_check(preview_panel.find_child("BaseTradeHeading", true, false) == null,
		"dungeon preview exposes no secured-stock trade controls")
	preview_panel.present(dungeon_overview, true, "STORAGE")
	await process_frame
	await process_frame
	var dungeon_snapshot := JSON.stringify(session.sim.snapshot())
	var preview_upgrade := preview_panel.find_child("BaseFacilityUpgradeSTORAGE", true, false) as Button
	_check(preview_upgrade != null and preview_upgrade.disabled,
		"dungeon preview keeps the selected storage upgrade disabled")
	var denied_upgrade: Dictionary = session.base_upgrade("STORAGE")
	_check(not bool(denied_upgrade.get("accepted", false))
		and str(denied_upgrade.get("reason", "")) == "base_upgrade_town_required",
		"dungeon preview cannot spend through the canonical facade")
	_check(JSON.stringify(session.sim.snapshot()) == dungeon_snapshot,
		"dungeon preview denial leaves authoritative state unchanged")
	preview_panel.queue_free()
	await process_frame

	_finish()


func _prepare_town_session():
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var helper = ProgressionAcceptance.new()
	var rows: Array[Dictionary] = helper._expected_cache_rows(session, 1)
	var safe_rows: Array[Dictionary] = helper._safe_cache_rows(session, rows)
	var timber_rows: Array[Dictionary] = []
	var stone_rows: Array[Dictionary] = []
	for value in safe_rows:
		var row: Dictionary = value
		if str(row.get("resource_id", "")) == "TIMBER":
			timber_rows.append(row)
		elif str(row.get("resource_id", "")) == "STONE":
			stone_rows.append(row)
	_check(timber_rows.size() >= 2 and not stone_rows.is_empty(),
		"canonical visual fixture exposes the same timber/stone haul as progression")
	if timber_rows.size() < 2 or stone_rows.is_empty():
		return null
	for row_value in [timber_rows[0], stone_rows[0], timber_rows[1]]:
		var row: Dictionary = row_value
		var position := _row_position(row)
		_check(helper._walk_to_position(session, position),
			"canonical visual fixture reaches %s" % str(row.get("cache_id", "")))
		var gathered: Dictionary = session.base_gather()
		_check(bool(gathered.get("accepted", false)),
			"canonical visual fixture gathers %s" % str(row.get("cache_id", "")))
	var entry: Vector2i = helper._entry_position(session)
	_check(helper._walk_to_position(session, entry),
		"canonical visual fixture returns to the authored entry")
	var returned: Dictionary = session.base_return()
	_check(bool(returned.get("accepted", false)),
		"canonical visual fixture extracts once into town")
	return session


func _mount_panel(overview: Dictionary, viewport_width: int, read_only: bool,
		selected_id: String):
	root.size = Vector2i(viewport_width, 640)
	await process_frame
	var panel = BasePanel.new()
	panel.name = "SettlementVisualSmokePanel"
	panel.position = Vector2.ZERO
	panel.size = Vector2(viewport_width, 640)
	panel.custom_minimum_size = Vector2(viewport_width, 640)
	root.add_child(panel)
	panel.present(overview, read_only, selected_id)
	await process_frame
	await process_frame
	return panel


func _check_map_budget(panel, map, viewport_width: int) -> void:
	_check(map != null, "%dpx production panel embeds the settlement map" % viewport_width)
	if map == null:
		return
	var map_rect: Rect2 = map.get_global_rect()
	_check(map_rect.position.y < 640.0 and map_rect.end.y <= 640.0,
		"%dpx settlement map remains above the initial portrait fold" % viewport_width)
	_check(panel.get_global_rect().size.x <= float(viewport_width) + 1.0,
		"%dpx base panel does not overflow the viewport width" % viewport_width)
	var hit_rects: Array[Rect2] = []
	for building_id in LANDMARK_IDS:
		var button := map.find_child("SettlementHit%s" % building_id, true, false) as Button
		_check(button != null, "%dpx has a hit target for %s" % [viewport_width, building_id])
		if button == null:
			continue
		var rect: Rect2 = button.get_global_rect()
		_check(rect.size.x >= 48.0 and rect.size.y >= 48.0,
			"%dpx %s hit target is at least 48px" % [viewport_width, building_id])
		_check(map_rect.has_point(rect.position)
			and map_rect.has_point(rect.end - Vector2.ONE),
			"%dpx %s hit target stays inside map" % [viewport_width, building_id])
		for previous in hit_rects:
			_check(not previous.intersects(rect),
				"%dpx landmark hit targets do not overlap" % viewport_width)
		hit_rects.append(rect)
	var detail := panel.find_child("BaseFacilitySTORAGE", true, false) as Control
	_check(detail != null and detail.get_global_rect().position.y >= map_rect.end.y - 1.0,
		"%dpx selected detail follows the map in the portrait flow" % viewport_width)


func _check_real_selection_and_drag(panel, map) -> void:
	if map == null:
		return
	var selected_ids: Array[String] = []
	var services: Array[String] = []
	panel.building_selected.connect(func(id: String): selected_ids.append(id))
	panel.service_requested.connect(func(id: String): services.append(id))
	var lodge := map.find_child("SettlementHitLODGE", true, false) as Button
	if lodge == null:
		return
	await _mouse_click(lodge.get_global_rect().get_center())
	_check(selected_ids == ["LODGE"],
		"real mouse selection emits exactly one building id")
	_check(panel.find_child("BaseFacilityLODGE", true, false) != null,
		"selecting a landmark opens its facility detail")
	var service := panel.find_child("BaseFacilityServiceLODGE", true, false) as Button
	_check(service != null and not service.disabled,
		"selected facility exposes its service action")
	if service != null:
		await _mouse_click(service.get_global_rect().get_center())
	_check(services == ["LODGE"],
		"real mouse service dispatches once after selection rebuild")

	# Rebuild to a known selection, then drag off the hit target. A drag must not
	# synthesize a second building selection on release.
	panel.present(panel.overview(), false, "STORAGE")
	await process_frame
	await process_frame
	selected_ids.clear()
	var fresh_map := panel.find_child("BaseSettlementMap", true, false) as Control
	var storage := fresh_map.find_child("SettlementHitSTORAGE", true, false) as Button
	var blank := fresh_map.get_global_rect().get_center()
	if storage != null:
		await _mouse_drag(storage.get_global_rect().get_center(), blank)
	_check(selected_ids.is_empty(), "dragging across the settlement does not select a building")
	var final_map := panel.find_child("BaseSettlementMap", true, false) as Control
	var storage_state: Dictionary = final_map.building_visual_state("STORAGE")
	_check(bool(storage_state.get("selected", false)),
		"drag cancellation leaves the prior selected building unchanged")


func _check_three_visual_stages(overview: Dictionary) -> void:
	var view = SettlementView.new()
	view.position = Vector2.ZERO
	view.size = Vector2(360, 320)
	root.add_child(view)
	var stages := ["CAMP", "TIMBER", "STONE"]
	var states: Array[Dictionary] = []
	for level in [1, 2, 3]:
		var fixture: Dictionary = overview.duplicate(true)
		var settlement: Dictionary = fixture.get("settlement", {})
		var buildings: Array = settlement.get("buildings", [])
		for index in range(buildings.size()):
			var building: Dictionary = buildings[index]
			if str(building.get("type_id", "")) == "STORAGE":building["level"] = level
		view.present(fixture, "STORAGE")
		await process_frame
		var state: Dictionary = view.building_visual_state("STORAGE")
		states.append(state)
		_check_eq(str(state.get("visual_stage", "")), stages[level - 1],
			"storage level %d exposes its authored visual stage" % level)
	_check(states.size() == 3 and states[0] != states[1] and states[1] != states[2],
		"storage levels 1/2/3 expose distinct visual state DTOs")
	view.queue_free()
	await process_frame


func _mouse_click(point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = point
	down.global_position = point
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = point
	up.global_position = point
	root.push_input(up, true)
	await process_frame
	await process_frame


func _mouse_drag(start: Vector2, finish: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = start
	down.global_position = start
	root.push_input(down, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = finish
	motion.global_position = finish
	root.push_input(motion, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = finish
	up.global_position = finish
	root.push_input(up, true)
	await process_frame
	await process_frame


func _row_position(row: Dictionary) -> Vector2i:
	var value: Variant = row.get("position", [])
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


func _count_world_events(session, event_type: String) -> int:
	var count := 0
	for event in session.sim.world.events:
		if str(event.type) == event_type:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _check_eq(got: Variant, expected: Variant, label: String) -> void:
	if got != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(got)])


func _finish() -> void:
	for failure in failures:
		printerr("FAIL ", failure)
	print("---- Base settlement visual smoke: %d failed ----" % failures.size())
	quit(1 if not failures.is_empty() else 0)
