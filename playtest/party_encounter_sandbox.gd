class_name PartyEncounterSandbox
extends Control

const SessionScript = preload("res://playtest/party_playtest_session.gd")
const GridScript = preload("res://playtest/party_grid_view.gd")
const KoreanFont: FontFile = preload("res://assets/fonts/NanumSquareR.ttf")

var session
var grid
var phase_label: Label
var cards: HBoxContainer
var deck: VBoxContainer
var log_label: Label
var selected_member_id := -1
var selected_target_id := -1
var notice_text := ""

func _ready() -> void:
	_build_ui()
	if session == null: session = SessionScript.new()
	_refresh()

func initialize_for_headless_test(custom_session = null) -> void:
	if grid == null: _build_ui()
	session = custom_session if custom_session != null else SessionScript.new()
	_refresh()

func _build_ui() -> void:
	if grid != null: return
	var ui_theme := Theme.new(); ui_theme.default_font = KoreanFont; ui_theme.default_font_size = 11; theme = ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color("#09111b"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var root := VBoxContainer.new(); root.name = "PartyLayout"; root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 6; root.offset_right = -6; root.offset_top = 4; root.offset_bottom = -4
	root.add_theme_constant_override("separation", 3); add_child(root)
	phase_label = Label.new(); phase_label.name = "PhaseStatus"; phase_label.custom_minimum_size.y = 40
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; root.add_child(phase_label)
	grid = GridScript.new(); grid.name = "PartyGrid"; grid.custom_minimum_size = Vector2(300,300)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; grid.world_cell_pressed.connect(_on_cell); grid.actor_pressed.connect(_on_actor); root.add_child(grid)
	cards = HBoxContainer.new(); cards.name = "PartyCards"; cards.custom_minimum_size.y = 96
	cards.add_theme_constant_override("separation", 3); root.add_child(cards)
	deck = VBoxContainer.new(); deck.name = "ContextDeck"; deck.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck.add_theme_constant_override("separation", 2); root.add_child(deck)
	log_label = Label.new(); log_label.name = "NarrativeLog"; log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.max_lines_visible = 1; log_label.custom_minimum_size.y = 28; root.add_child(log_label)

func _refresh() -> void:
	if session == null: return
	_apply_portrait_budget()
	var status: Dictionary = session.party_status()
	if not bool(status.get("ok", false)): return
	if selected_member_id not in status.party_member_ids: selected_member_id = int(status.protagonist_id)
	if selected_target_id not in status.visible_enemy_ids: selected_target_id = -1
	var contact_text: String = {"NONE":"탐색 중", "DETECTED":"상호 발견", "PARTY_AMBUSH":"파티 선제", "ENEMY_AMBUSH":"적 매복"}.get(str(status.contact_kind), "탐색 중")
	phase_label.text = "%s · 시간 %d · %s" % [_phase(str(status.safe_phase)), int(status.world_time), contact_text]
	var deployment: Dictionary = session.deployment_draft()
	var ghosts: Array = deployment.placements if str(status.view_mode) == "ENCOUNTER_PREVIEW" else []
	grid.set_observation(session.observe_party_world(), ghosts)
	grid.set_selection(selected_member_id, selected_target_id)
	_clear_container(cards)
	for row in session.party_cards(): _add_member_card(row)
	_clear_container(deck)
	match str(status.view_mode):
		"EXPLORATION": _exploration_deck(status)
		"ENCOUNTER_PREVIEW": _deployment_deck(deployment)
		"COMBAT": _combat_deck(status, session.current_turn_preview())
		"REGROUP": _regroup_deck()
	var logs: Array = session.recent_event_log(2 if size.x >= 450 else 1)
	log_label.text = "\n".join(logs.map(func(row): return str(row.message))) if not logs.is_empty() else "방향을 골라 세계를 탐험하세요."

func _add_member_card(row: Dictionary) -> void:
	var button := Button.new(); var member_id := int(row.entity_id); button.name = "MemberCard%d" % member_id
	button.custom_minimum_size = Vector2(44, cards.custom_minimum_size.y); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = false; button.text = ""; button.clip_contents = true
	var portrait := AtlasTexture.new(); portrait.atlas = GridScript.CHARACTER_ATLAS
	var portrait_frame := 0 if str(row.role) == "PROTAGONIST" else 4
	portrait.region = Rect2(Vector2((portrait_frame % GridScript.CHARACTER_ATLAS_COLUMNS) * GridScript.CHARACTER_FRAME_SIZE.x,
		floori(float(portrait_frame) / GridScript.CHARACTER_ATLAS_COLUMNS) * GridScript.CHARACTER_FRAME_SIZE.y),
		Vector2(GridScript.CHARACTER_FRAME_SIZE))
	var selected := member_id == selected_member_id
	var condition := "정상" if row.status_ids.is_empty() else ",".join(row.status_ids)
	var expected := "행동 미지정"
	var expected_color := Color("#aeb8c6")
	if row.expected_action is Dictionary:
		expected = _compact_action(row.expected_action)
		expected_color = Color(str(row.expected_action.source_color))
	button.modulate = Color("#d8f3ff") if selected else Color.WHITE

	# A controlled child layout keeps the portrait and four required information
	# rows inside a 3-way 360 px card. The children ignore pointer input so the
	# entire Button remains the deterministic 44 px accessible hit target.
	var inset := MarginContainer.new(); inset.name = "CardContent"
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 3); inset.add_theme_constant_override("margin_right", 3)
	inset.add_theme_constant_override("margin_top", 2); inset.add_theme_constant_override("margin_bottom", 2)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(inset)
	var stack := VBoxContainer.new(); stack.name = "CardStack"; stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE; inset.add_child(stack)
	var heading := HBoxContainer.new(); heading.name = "CardHeading"; heading.add_theme_constant_override("separation", 2)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE; stack.add_child(heading)
	var portrait_view := TextureRect.new(); portrait_view.name = "Portrait"; portrait_view.texture = portrait
	portrait_view.custom_minimum_size = Vector2(18,22); portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; portrait_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(portrait_view)
	var name_label := _card_label(("▶" if selected else "") + str(row.display_name), "MemberName", 9)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(name_label)
	stack.add_child(_card_label("HP%d/%d %s·%s" % [int(row.health), int(row.max_health), condition,
		_presence(str(row.presence))], "MemberState", 8))
	stack.add_child(_card_label("불%d 물%d 전%d 독%d" % [int(row.element_exposure.fire_score),
		int(row.element_exposure.water_score), int(row.element_exposure.electric_score),
		int(row.element_exposure.poison_score)], "MemberElements", 8))
	var action_label := _card_label(expected, "ExpectedAction", 8); action_label.add_theme_color_override("font_color", expected_color)
	stack.add_child(action_label)
	button.tooltip_text = "%s / 총 위험 %d / 스트레스 %d" % [expected, int(row.element_exposure.total_risk), int(row.stress)]
	button.pressed.connect(_select_member.bind(member_id, str(row.display_name)))
	cards.add_child(button)

func _card_label(value: String, node_name: String, font_size: int) -> Label:
	var label := Label.new(); label.name = node_name; label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _compact_action(action: Dictionary) -> String:
	var source := str(action.get("source_label", "자동")); var action_type := str(action.get("type", "HOLD"))
	if action_type == "MOVE":
		var destination: Array = action.get("destination", [-1,-1])
		return "%s 이동 %d,%d" % [source, int(destination[0]), int(destination[1])]
	if action_type == "MELEE":
		return "%s 공격 %s" % [source, str(action.get("target_name", "적"))]
	return "%s 대기" % source

func _exploration_deck(_status: Dictionary) -> void:
	_add_notice("탐험: 8방향 이동 또는 대기")
	var controls := GridContainer.new(); controls.name = "ExplorationControls"; controls.columns = 3; deck.add_child(controls)
	var entries := [[Vector2i(-1,-1),"↖","ExploreNW"],[Vector2i.UP,"↑","ExploreN"],[Vector2i(1,-1),"↗","ExploreNE"],
		[Vector2i.LEFT,"←","ExploreW"],[Vector2i.ZERO,"대기","ExploreHold"],[Vector2i.RIGHT,"→","ExploreE"],
		[Vector2i(-1,1),"↙","ExploreSW"],[Vector2i.DOWN,"↓","ExploreS"],[Vector2i(1,1),"↘","ExploreSE"]]
	for entry in entries:
		var direction: Vector2i = entry[0]
		_add_button(controls, str(entry[1]), str(entry[2]), _on_explore.bind(direction))

func _deployment_deck(deployment: Dictionary) -> void:
	var preset_label: String = {"WEDGE":"쐐기", "LINE":"횡대", "COLUMN":"종대", "NONE":"미선택"}.get(str(deployment.preset_id), "미선택")
	_add_notice(notice_text if not notice_text.is_empty() else "배치 대형: %s · %s" % [preset_label, str(deployment.message)])
	var controls := HBoxContainer.new(); controls.name = "FormationControls"; deck.add_child(controls)
	for preset in ["WEDGE", "LINE", "COLUMN"]:
		var selected_preset: String = preset
		var button := _add_button(controls, {"WEDGE":"쐐기", "LINE":"횡대", "COLUMN":"종대"}[preset], "Preset%s" % preset,
			_on_preset.bind(selected_preset))
		button.toggle_mode = true
		button.button_pressed = str(deployment.preset_id) == preset
	var confirm := _add_button(deck, "배치 확정", "DeployConfirm", _on_deploy_confirm)
	confirm.disabled = not bool(deployment.accepted)

func _combat_deck(status: Dictionary, preview: Dictionary) -> void:
	if bool(status.terminal):
		var terminal := Label.new(); terminal.name = "TerminalOverlay"; terminal.text = "파티가 패배했습니다. 주인공이 쓰러져 더 행동할 수 없습니다."
		terminal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; terminal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		terminal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL; deck.add_child(terminal)
		return
	var actor_name := "파티원"
	for row in session.party_cards():
		if int(row.entity_id) == selected_member_id: actor_name = str(row.display_name); break
	var instruction := "%s 선택 · 빈 칸=이동, 적=공격" % actor_name
	if not notice_text.is_empty(): instruction = notice_text
	elif not bool(preview.get("accepted", false)): instruction += " · %s" % str(preview.get("message", "주인공 행동을 먼저 지정하세요."))
	_add_notice(instruction)
	var controls := HBoxContainer.new(); controls.name = "CombatControls"; deck.add_child(controls)
	_add_button(controls, "선택 대기", "ActorHold", _on_actor_hold)
	var clear := _add_button(controls, "지시 해제", "OverrideClear", _on_override_clear)
	clear.disabled = selected_member_id == int(status.protagonist_id)
	var confirm := _add_button(controls, "턴 확정", "TurnConfirm", _on_turn_confirm)
	confirm.disabled = not bool(preview.get("accepted", false))

func _regroup_deck() -> void:
	_add_notice(notice_text if not notice_text.is_empty() else "승리했습니다. 배치 토큰을 확인한 뒤 재집결하세요.")
	_add_button(deck, "재집결", "RegroupConfirm", _on_regroup_confirm)

func _select_member(member_id: int, display_name: String) -> void:
	selected_member_id = member_id; selected_target_id = -1; notice_text = "%s 선택" % display_name; _request_refresh()

func _on_explore(direction: Vector2i) -> void:
	_record_result(session.commit_exploration_direction(direction)); _request_refresh()

func _on_preset(preset: String) -> void:
	var result: Dictionary = session.preview_deployment(preset, session.available_companion_ids())
	notice_text = "%s 대형: %s" % [{"WEDGE":"쐐기", "LINE":"횡대", "COLUMN":"종대"}[preset], str(result.message)]
	_request_refresh()

func _on_deploy_confirm() -> void:
	var draft: Dictionary = session.deployment_draft()
	if not bool(draft.accepted): notice_text = str(draft.message)
	else: _record_result(session.commit_deployment())
	_request_refresh()

func _on_actor_hold() -> void:
	_record_result(session.set_actor_action(selected_member_id, "HOLD")); _request_refresh()

func _on_override_clear() -> void:
	_record_result(session.clear_companion_override(selected_member_id)); _request_refresh()

func _on_turn_confirm() -> void:
	var current: Dictionary = session.current_turn_preview()
	if not bool(current.get("accepted", false)): notice_text = str(current.get("message", "행동을 확인하세요."))
	else: _record_result(session.commit_turn())
	_request_refresh()

func _on_regroup_confirm() -> void:
	_record_result(session.regroup()); _request_refresh()

func _on_cell(position: Vector2i) -> void:
	var status: Dictionary = session.party_status()
	if status.view_mode != "COMBAT" or bool(status.terminal): return
	selected_target_id = -1
	_record_result(session.set_actor_action(selected_member_id, "MOVE", [position.x,position.y]))
	_request_refresh()

func _on_actor(entity_id: int) -> void:
	var status: Dictionary = session.party_status()
	if entity_id in status.visible_enemy_ids:
		selected_target_id = entity_id
		if status.view_mode == "COMBAT" and not bool(status.terminal):
			_record_result(session.set_actor_action(selected_member_id, "MELEE", [], entity_id))
		_request_refresh(); return
	if entity_id in status.party_member_ids:
		selected_member_id = entity_id; selected_target_id = -1; notice_text = "파티원을 선택했습니다."; _request_refresh()

func _request_refresh() -> void:
	call_deferred("_refresh")

func _record_result(result: Dictionary) -> void:
	if bool(result.get("accepted", false)):
		notice_text = ""
	else:
		notice_text = str(result.get("message", session.reason_message(str(result.get("reason", "invalid_party_action")))))

func _add_notice(value: String) -> Label:
	var label := Label.new(); label.name = "ActionStatus"; label.text = value; label.custom_minimum_size.y = 20
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.max_lines_visible = 2; deck.add_child(label); return label

func _add_button(parent: Control, value: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new(); button.name = node_name; button.text = value; button.custom_minimum_size = Vector2(44,44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.pressed.connect(callback); parent.add_child(button); return button

func _clear_container(container: Control) -> void:
	for child in container.get_children(): container.remove_child(child); child.free()

func _phase(value: String) -> String:
	return {"GROUPED":"탐험", "CONTACT":"조우 배치", "ENGAGED":"파티 전투", "REGROUP_READY":"재집결 대기",
		"GROUPED_COMPLETE":"탐험 재개", "PARTY_DEFEATED":"패배"}.get(value,value)

func _presence(value: String) -> String:
	return {"DEPLOYED":"배치", "GROUPED":"동행", "DORMANT":"대기", "DEFEATED":"쓰러짐"}.get(value,value)

func _apply_portrait_budget() -> void:
	var wide: bool = size.x >= 450.0
	phase_label.custom_minimum_size.y = 48 if wide else 40
	grid.custom_minimum_size = Vector2(330,330) if wide else Vector2(300,300)
	cards.custom_minimum_size.y = 116 if wide else 96
	log_label.custom_minimum_size.y = 34 if wide else 22
	log_label.max_lines_visible = 2 if wide else 1
