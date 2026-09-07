extends SceneTree


const Session = preload("res://playtest/party_playtest_session.gd")
const BasePanel = preload("res://playtest/base_progress_panel.gd")

const WORLD_SEED := 44
const PERSONALITY_SEED := 20260828
const DUO := "DUO_AUTOBATTLE_V1"
const BUILDABLE_TYPES := ["CLINIC", "MARKET", "ARMORY"]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _canonical_build_save_replay()
	await _placement_guards_and_legacy_load()
	await _real_pointer_placement_flow()
	if failures.is_empty():
		print("PASS base settlement build acceptance: canonical build, placement guards, legacy load, 360/390 pointers")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL ", failure)
	quit(1)


func _canonical_build_save_replay() -> void:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var entry_return: Dictionary = session.base_return_assessment()
	_check(bool(entry_return.get("accepted", false)),
		"a fresh DUO can safely extract from its authored entry")
	if not bool(entry_return.get("accepted", false)):
		return
	var returned: Dictionary = session.base_return()
	_check(bool(returned.get("accepted", false)), "entry extraction enters the canonical town phase")
	if not bool(returned.get("accepted", false)):
		return

	var town: Dictionary = session.base_overview()
	_check_eq(str(town.get("phase", "")), "TOWN", "canonical build starts in town")
	var baseline: Dictionary = town.get("settlement", {})
	var baseline_buildings: Array = baseline.get("buildings", [])
	_check_eq(baseline_buildings.size(), 3,
		"new settlement baseline contains STORAGE, LODGE, and fixed GATE only")
	var gate: Dictionary = _building_of_type(baseline_buildings, "GATE")
	_check(bool(gate.get("fixed", false)) and not bool(gate.get("movable", true)),
		"the authored gate is fixed and not a movable construction target")
	_check_eq(gate.get("tile_origin", []), [6, 13], "the gate keeps its authored tile origin")

	var clinic_position: Vector2i = _find_build_position(session, "CLINIC")
	_check(clinic_position.x >= 0, "starter stock exposes at least one legal clinic placement")
	if clinic_position.x < 0:
		return
	var assessment_before: String = _snapshot_json(session)
	var assessment: Dictionary = session.base_build_assessment("CLINIC", clinic_position)
	_check(bool(assessment.get("accepted", false)),
		"clinic placement assessment accepts a DTO-derived legal tile")
	_check(_snapshot_json(session) == assessment_before,
		"preview assessment does not mutate world state or banked materials")
	if not bool(assessment.get("accepted", false)):
		return

	var stock_before: Dictionary = town.get("stock", {}).duplicate(true)
	var build_events_before := _count_events(session, "base.building_constructed")
	var built: Dictionary = session.base_build("CLINIC", clinic_position)
	_check(bool(built.get("accepted", false)), "canonical clinic confirmation commits once")
	_check_eq(_count_events(session, "base.building_constructed"), build_events_before + 1,
		"one clinic confirmation emits one construction event")
	if not bool(built.get("accepted", false)):
		return
	var stock_after: Dictionary = session.base_overview().get("stock", {})
	var cost: Dictionary = assessment.get("cost", {})
	for resource_id in ["TIMBER", "STONE", "HERBS"]:
		_check_eq(int(stock_after.get(resource_id, 0)),
			int(stock_before.get(resource_id, 0)) - int(cost.get(resource_id, 0)),
			"clinic construction consumes only its %s cost" % resource_id)
	_check(session._base_building_built("CLINIC"), "clinic construction unlocks the clinic service")
	var clinic_service: Dictionary = session.town_clinic_assessment(
		int(session.party_status().get("party_member_ids", [0])[0]))
	_check(str(clinic_service.get("reason", "")) != "base_clinic_not_built",
		"clinic service is no longer gated as unbuilt")

	# A second confirmation for the same type must be a read-only denial.  This
	# catches duplicate taps as well as callers that try a different tile.
	var duplicate_snapshot: String = _snapshot_json(session)
	var duplicate_events := _count_events(session, "base.building_constructed")
	var duplicate: Dictionary = session.base_build("CLINIC", Vector2i(10, 8))
	_check(not bool(duplicate.get("accepted", false)), "duplicate clinic confirmation is denied")
	_check_eq(str(duplicate.get("reason", "")), "base_building_already_built",
		"duplicate construction reports an already-built reason")
	_check_eq(_snapshot_json(session), duplicate_snapshot,
		"duplicate construction does not charge or append state")
	_check_eq(_count_events(session, "base.building_constructed"), duplicate_events,
		"duplicate construction emits no second event")

	var encoded: String = session.save_session_json()
	var restored = Session.new(999, 888, DUO)
	var loaded: Dictionary = restored.load_session_json(encoded)
	_check(bool(loaded.get("accepted", false)), "built settlement save loads through the public session API")
	if bool(loaded.get("accepted", false)):
		_check_eq(_snapshot_json(restored), _snapshot_json(session),
			"save/load preserves the constructed settlement exactly")
		_check_eq(restored.base_overview().get("settlement", {}),
			session.base_overview().get("settlement", {}),
			"save/load preserves tile positions and construction DTOs exactly")
		_check(restored._base_building_built("CLINIC"),
			"loaded construction continues to unlock the clinic service")


func _placement_guards_and_legacy_load() -> void:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var returned: Dictionary = session.base_return()
	_check(bool(returned.get("accepted", false)), "guard fixture reaches town through the entry API")
	if not bool(returned.get("accepted", false)):
		return
	var baseline: String = _snapshot_json(session)
	_assert_assessment_denied(session, "UNKNOWN", Vector2i(2, 8), "base_building_type_unknown",
		"unknown building id")
	_assert_assessment_denied(session, "CLINIC", "not-a-tile", "base_building_position_invalid",
		"malformed tile position")
	_assert_assessment_denied(session, "CLINIC", Vector2i(15, 15), "base_building_out_of_bounds",
		"out-of-bounds footprint")
	_assert_assessment_denied(session, "CLINIC", Vector2i(0, 0), "base_building_terrain_blocked",
		"blocked terrain")
	_assert_assessment_denied(session, "CLINIC", Vector2i(1, 2), "base_building_overlap",
		"overlapping authored building")
	_assert_assessment_denied(session, "GATE", Vector2i(6, 13), "base_building_type_unknown",
		"fixed gate cannot be constructed as a free building")
	_assert_assessment_denied(session, "MARKET", Vector2i(9, 8), "base_resources_insufficient",
		"unaffordable market cannot reserve or spend stock")
	_check_eq(_snapshot_json(session), baseline,
		"all invalid and preview assessments leave the town authority unchanged")

	# The authored gate route is a reserved corridor.  A free building cannot
	# close that corridor, which is the public placement form of the gate-access
	# invariant (the fixed gate itself is checked above).
	_assert_assessment_denied(session, "CLINIC", Vector2i(4, 4),
		"base_building_reserved", "gate-access corridor placement")

	# A DUO save created through the compatibility bootstrap has no settlement
	# marker.  It is an explicit old-save fixture, not a direct world mutation;
	# loading it must retain the historical six-landmark layout and services.
	var old_source = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var old_reset: bool = old_source.reset_party(WORLD_SEED, PERSONALITY_SEED, DUO,
		{}, true, "human", false)
	_check(old_reset, "compatibility fixture can create a pre-marker DUO save")
	if not old_reset:
		return
	var old_encoded: String = old_source.save_session_json()
	var old_restored = Session.new(7, 9, DUO)
	var old_loaded: Dictionary = old_restored.load_session_json(old_encoded)
	_check(bool(old_loaded.get("accepted", false)), "old DUO save loads after settlement schema introduction")
	if bool(old_loaded.get("accepted", false)):
		var old_settlement: Dictionary = old_restored.base_overview().get("settlement", {})
		var old_buildings: Array = old_settlement.get("buildings", [])
		_check_eq(old_buildings.size(), 6, "old DUO save retains all six historical landmarks")
		for type_id in ["STORAGE", "LODGE", "CLINIC", "MARKET", "ARMORY", "GATE"]:
			_check(not _building_of_type(old_buildings, type_id).is_empty(),
				"old DUO save retains %s" % type_id)
		_check(old_restored._base_building_built("MARKET"),
			"legacy market remains a usable service after migration")
		_check(old_restored._base_building_built("CLINIC"),
			"legacy clinic remains a usable service after migration")
		_check_eq(_snapshot_json(old_restored), _snapshot_json(old_source),
			"legacy replay preserves the old save snapshot exactly")


func _real_pointer_placement_flow() -> void:
	# The two viewport sizes use separate sessions so each run starts with the
	# exact starter stock and can prove that one real confirm spends once.
	await _pointer_build_at_width(360, false)
	await _pointer_build_at_width(390, true)
	await _pointer_cancel_and_read_only()


func _pointer_build_at_width(viewport_width: int, use_touch: bool) -> void:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var returned: Dictionary = session.base_return()
	_check(bool(returned.get("accepted", false)), "%dpx pointer fixture reaches town" % viewport_width)
	if not bool(returned.get("accepted", false)):
		return
	var position: Vector2i = _find_build_position(session, "CLINIC")
	_check(position.x >= 0, "%dpx pointer fixture has a legal clinic tile" % viewport_width)
	if position.x < 0:
		return

	root.size = Vector2i(viewport_width, 640)
	await process_frame
	var panel = BasePanel.new()
	panel.name = "SettlementBuildPointerPanel%d" % viewport_width
	panel.position = Vector2.ZERO
	panel.size = Vector2(viewport_width, 640)
	panel.custom_minimum_size = Vector2(viewport_width, 640)
	panel.configure_build_assessment(Callable(session, "base_build_assessment"))
	panel.construction_confirm_requested.connect(
		_on_panel_construction_confirmed.bind(session, panel), CONNECT_DEFERRED)
	root.add_child(panel)
	panel.present(session.base_overview(), false, "STORAGE")
	await process_frame
	await process_frame

	var open := panel.find_child("BaseConstructionOpen", true, false) as Button
	_check(open != null and not open.disabled,
		"%dpx town panel exposes an enabled construction entry" % viewport_width)
	if open == null:
		panel.queue_free();await process_frame;return
	# Godot's headless Button controls receive mouse input; the map itself also
	# handles ScreenTouch, so use the latter for the placement gesture while
	# keeping the editor controls on the same real mouse path at both widths.
	await _pointer_click(open.get_global_rect().get_center(), false)
	await process_frame
	var clinic_option := panel.find_child("BaseBuildOptionCLINIC", true, false) as Button
	_check(clinic_option != null and not clinic_option.disabled,
		"%dpx clinic option is affordable in the starter town" % viewport_width)
	if clinic_option == null or clinic_option.disabled:
		panel.queue_free();await process_frame;return
	await _pointer_click(clinic_option.get_global_rect().get_center(), false)
	await process_frame
	var map := panel.find_child("BaseSettlementMap", true, false) as Control
	_check(map != null, "%dpx placement editor exposes the real tile map" % viewport_width)
	if map == null:
		panel.queue_free();await process_frame;return
	var tile_point := _map_tile_point(map, position)
	await _pointer_click(tile_point, use_touch)
	await process_frame
	var confirm := panel.find_child("BasePlacementConfirm", true, false) as Button
	_check(confirm != null and not confirm.disabled,
		"%dpx real tile pointer enables construction confirmation" % viewport_width)
	var construction_events_before := _count_events(session, "base.building_constructed")
	if confirm != null and not confirm.disabled:
		await _pointer_click(confirm.get_global_rect().get_center(), false)
	await process_frame
	await process_frame
	_check(session._base_building_built("CLINIC"),
		"%dpx pointer confirmation constructs the clinic" % viewport_width)
	_check_eq(_count_events(session, "base.building_constructed"), construction_events_before + 1,
		"%dpx pointer confirmation charges/emits exactly once" % viewport_width)
	var stock_after_first: String = _snapshot_json(session)
	# A stale/repeated confirmation cannot be clicked into a second charge; the
	# production panel rebuilds from the authoritative DTO after the first commit.
	var stale_confirm := panel.find_child("BasePlacementConfirm", true, false) as Button
	if stale_confirm != null:
		await _pointer_click(stale_confirm.get_global_rect().get_center(), use_touch)
	await process_frame
	_check_eq(_snapshot_json(session), stock_after_first,
		"%dpx repeated pointer confirmation is a no-op" % viewport_width)
	panel.queue_free()
	await process_frame


func _pointer_cancel_and_read_only() -> void:
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var returned: Dictionary = session.base_return()
	_check(bool(returned.get("accepted", false)), "cancel fixture reaches town")
	if not bool(returned.get("accepted", false)):
		return
	root.size = Vector2i(360, 640)
	var panel = BasePanel.new()
	panel.name = "SettlementBuildCancelPanel"
	panel.size = Vector2(360, 640)
	panel.custom_minimum_size = Vector2(360, 640)
	panel.configure_build_assessment(Callable(session, "base_build_assessment"))
	root.add_child(panel)
	panel.present(session.base_overview(), false, "STORAGE")
	await process_frame
	await process_frame
	var before_cancel := _snapshot_json(session)
	var open := panel.find_child("BaseConstructionOpen", true, false) as Button
	if open != null:
		await _pointer_click(open.get_global_rect().get_center(), false)
		await process_frame
	var option := panel.find_child("BaseBuildOptionCLINIC", true, false) as Button
	if option != null:
		await _pointer_click(option.get_global_rect().get_center(), false)
		await process_frame
	var cancel := panel.find_child("BasePlacementCancel", true, false) as Button
	_check(cancel != null, "placement editor exposes a real cancel action")
	if cancel != null:
		await _pointer_click(cancel.get_global_rect().get_center(), false)
		await process_frame
	_check_eq(_snapshot_json(session), before_cancel,
		"canceling placement spends no materials and emits no construction event")
	panel.queue_free()
	await process_frame

	# The dungeon preview is read-only even though the same panel receives the
	# settlement DTO.  No construction entry or mutation may leak into it.
	var dungeon = Session.new(WORLD_SEED, PERSONALITY_SEED, DUO)
	var before_preview := _snapshot_json(dungeon)
	var preview = BasePanel.new()
	preview.name = "SettlementReadOnlyPreviewPanel"
	preview.size = Vector2(360, 640)
	preview.custom_minimum_size = Vector2(360, 640)
	preview.configure_build_assessment(Callable(dungeon, "base_build_assessment"))
	root.add_child(preview)
	preview.present(dungeon.base_overview(), true, "STORAGE")
	await process_frame
	_check(preview.find_child("BaseConstructionOpen", true, false) == null,
		"read-only dungeon preview exposes no construction entry")
	_check(preview.find_child("BasePlacementConfirm", true, false) == null,
		"read-only dungeon preview exposes no confirmation action")
	_check_eq(_snapshot_json(dungeon), before_preview,
		"read-only preview does not spend or append state")
	preview.queue_free()
	await process_frame


func _on_panel_construction_confirmed(type_id: String, tile_origin: Vector2i,
		session, panel) -> void:
	var result: Dictionary = session.base_build(type_id, tile_origin)
	if bool(result.get("accepted", false)):
		panel.present(session.base_overview(), false, type_id)
	else:
		panel.apply_placement_assessment(result)


func _find_build_position(session, type_id: String) -> Vector2i:
	# This is the authored open pad used by the legacy layout.  Keep the DTO
	# assessment authoritative, with a bounded scan only as a seed/layout
	# compatibility fallback.
	var authored := Vector2i(1, 8)
	var authored_result: Dictionary = session.base_build_assessment(type_id, authored)
	if bool(authored_result.get("accepted", false)):
		return authored
	var settlement: Dictionary = session.base_overview().get("settlement", {})
	for value in settlement.get("tiles", []):
		if not value is Dictionary:
			continue
		var raw: Variant = value.get("position", [])
		if not raw is Array or raw.size() != 2:
			continue
		var candidate := Vector2i(int(raw[0]), int(raw[1]))
		var result: Dictionary = session.base_build_assessment(type_id, candidate)
		if bool(result.get("accepted", false)):
			return candidate
	return Vector2i(-1, -1)


func _find_position_for_reason(session, type_id: String, reason: String) -> Vector2i:
	var settlement: Dictionary = session.base_overview().get("settlement", {})
	for value in settlement.get("tiles", []):
		if not value is Dictionary:
			continue
		var raw: Variant = value.get("position", [])
		if not raw is Array or raw.size() != 2:
			continue
		var candidate := Vector2i(int(raw[0]), int(raw[1]))
		var result: Dictionary = session.base_build_assessment(type_id, candidate)
		if str(result.get("reason", "")) == reason:
			return candidate
	return Vector2i(-1, -1)


func _assert_assessment_denied(session, type_id: String, position: Variant,
		reason: String, label: String) -> void:
	var before := _snapshot_json(session)
	var result: Dictionary = session.base_build_assessment(type_id, position)
	_check(not bool(result.get("accepted", false)), "%s is denied" % label)
	_check_eq(str(result.get("reason", "")), reason, "%s reason" % label)
	_check_eq(_snapshot_json(session), before, "%s is read-only" % label)


func _map_tile_point(map: Control, tile: Vector2i) -> Vector2:
	var origin: Vector2 = map.call("_map_origin")
	var cell_size: float = float(map.call("_cell_size"))
	return map.get_global_position() + origin + (Vector2(tile) + Vector2(0.5, 0.5)) * cell_size


func _pointer_click(position: Vector2, use_touch: bool) -> void:
	if use_touch:
		var press := InputEventScreenTouch.new()
		press.index = 0;press.position = position;press.pressed = true
		root.push_input(press, true);await process_frame
		var release := InputEventScreenTouch.new()
		release.index = 0;release.position = position;release.pressed = false
		root.push_input(release, true);await process_frame
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT;press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position;press.global_position = position;press.pressed = true
	root.push_input(press, true);await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT;release.position = position
	release.global_position = position;release.pressed = false
	root.push_input(release, true);await process_frame


func _building_of_type(rows: Array, type_id: String) -> Dictionary:
	for value in rows:
		if value is Dictionary and str(value.get("type_id", "")) == type_id:
			return value
	return {}


func _count_events(session, type_id: String) -> int:
	var count := 0
	for event in session.sim.world.events:
		if str(event.type) == type_id:
			count += 1
	return count


func _snapshot_json(session) -> String:
	return JSON.stringify(session.sim.snapshot())


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _check_eq(got: Variant, expected: Variant, label: String) -> void:
	if got != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(got)])
