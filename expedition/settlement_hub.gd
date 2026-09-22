extends Control
## Painted settlement with normalized touch regions; no expedition HUD.
const BACKGROUND = preload("res://assets/ui/settlement-hub-v1.png")

func build(ui) -> void:
	name = "SettlementHub"
	size_flags_vertical = SIZE_EXPAND_FILL
	clip_contents = true
	var art := TextureRect.new()
	art.texture = BACKGROUND
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(art); art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hotspot("TownGate","원정문",Rect2(0.40,0.13,0.24,0.14),ui.depart)
	hotspot("TownShop","상점",Rect2(0.08,0.29,0.34,0.17),ui.show_shop)
	hotspot("TownInfirmary","요양소",Rect2(0.65,0.29,0.33,0.18),ui.show_infirmary)
	hotspot("TownLodging","숙소",Rect2(0.08,0.53,0.36,0.20),func(): ui.show_town_roster(false))
	hotspot("TownTraining","훈련장",Rect2(0.63,0.53,0.35,0.20),func(): ui.show_town_roster(true))
	var edit := hotspot("TownEdit","편집",Rect2(0.85,0.735,0.14,0.065),func(): pass)
	edit.disabled = true; edit.tooltip_text = "편집 준비 중"
	var shade := ColorRect.new(); shade.color = Color(0,0,0,0.45); shade.mouse_filter = MOUSE_FILTER_IGNORE
	edit.add_child(shade); shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hotspot("TownDepart","출정",Rect2(0.035,0.895,0.93,0.073),ui.depart)
	# Playtest-only entry point; last in the preparation row, above 출정.
	if ui.session.floor_mode and ui.session.phase == "TOWN":
		var loadout = ui.button(self,"시험 로드아웃",func(): ui.run_action(ui.session.grant_test_loadout))
		loadout.name = "TownTestLoadout"; loadout.tooltip_text = "플레이테스트 · 모든 이능 습득"
		loadout.custom_minimum_size = Vector2(44,44)
		loadout.anchor_left = 0.035; loadout.anchor_top = 0.812
		loadout.anchor_right = 0.66; loadout.anchor_bottom = 0.877
		loadout.offset_left = 0; loadout.offset_top = 0; loadout.offset_right = 0; loadout.offset_bottom = 0
	var top := PanelContainer.new(); top.name = "TownHeader"
	var panel := StyleBoxFlat.new(); panel.bg_color = Color("141719"); panel.border_color = Color("8f7748"); panel.border_width_bottom = 2
	panel.content_margin_left = 12; panel.content_margin_right = 6
	top.add_theme_stylebox_override("panel",panel)
	add_child(top); top.set_anchors_and_offsets_preset(PRESET_TOP_WIDE); top.anchor_bottom = 0.05; top.custom_minimum_size.y = 48
	var row := HBoxContainer.new(); top.add_child(row)
	var title = ui.label(row,"잿빛 정착지",18); title.size_flags_horizontal = SIZE_EXPAND_FILL; title.clip_text = true
	var funds = ui.label(row,"자금 %d" % ui.session.bank,16); funds.name = "TownFunds"; funds.clip_text = true; funds.custom_minimum_size.x = 90
	funds.tooltip_text = "자금 %d" % ui.session.bank
	var settings = ui.button(row,"설정",ui.show_town_settings); settings.name = "TownSettings"; settings.size_flags_horizontal = SIZE_SHRINK_END; settings.custom_minimum_size.x = 44

func hotspot(id: String, caption: String, area: Rect2, action: Callable) -> Button:
	var node := Button.new(); node.name = id; node.text = caption; node.tooltip_text = caption
	node.custom_minimum_size = Vector2(44,44)
	for state in ["normal","disabled"]: node.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["hover","pressed","focus"]:
		var box := StyleBoxFlat.new(); box.bg_color = Color(0.9,0.7,0.3,0.12 if state != "pressed" else 0.25)
		box.border_color = Color("d7b56b"); box.set_border_width_all(1); box.set_corner_radius_all(4)
		node.add_theme_stylebox_override(state,box)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]: node.add_theme_color_override(state,Color.TRANSPARENT)
	node.pressed.connect(action); add_child(node)
	node.anchor_left = area.position.x; node.anchor_top = area.position.y
	node.anchor_right = area.end.x; node.anchor_bottom = area.end.y
	return node
