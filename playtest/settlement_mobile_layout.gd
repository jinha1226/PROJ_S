extends RefCounted
const Glyph=preload("res://playtest/settlement_mobile_glyph.gd")

static func surface()->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color("20272f")
	style.border_color=Color("414954");style.set_border_width_all(1);style.set_corner_radius_all(12)
	style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=8;style.content_margin_bottom=8
	return style

static func icon(kind:String,extent:float)->Control:
	var glyph=Glyph.new();glyph.kind=kind;glyph.custom_minimum_size=Vector2.ONE*extent
	return glyph

static func style_button(button:Button)->void:
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=surface();style.set_corner_radius_all(7)
		style.bg_color=Color("695738") if state=="pressed" else Color("29323b")
		style.border_color=Color("c4a773") if state in ["pressed","focus"] else Color("414954")
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_color",Color("e4ddd0"))

static func mount(panel,sections:Array)->void:
	var map=panel.find_child("BaseSettlementMap",true,false)
	panel.remove_child(map)
	for child in panel.get_children():panel.remove_child(child);child.queue_free()
	var stage:=Control.new();stage.name="SettlementMobileStage"
	stage.custom_minimum_size.y=maxf(560,panel.get_viewport_rect().size.y-16)
	stage.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_child(stage)
	stage.add_child(map);map.custom_minimum_size=Vector2.ZERO;map.immersive_map=true
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.offset_bottom=-panel._touch_target()-22
	var hud:=PanelContainer.new();hud.name="SettlementResourceHUD";hud.add_theme_stylebox_override("panel",surface())
	stage.add_child(hud);hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left=8;hud.offset_right=-8;hud.offset_top=8
	var header:=VBoxContainer.new();hud.add_child(header)
	var title_row:=HBoxContainer.new();header.add_child(title_row)
	var title:=Label.new();title.text="피난처";title.add_theme_font_size_override("font_size",20)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_row.add_child(title)
	var menu:Button=panel._button("☰","SettlementMenu");menu.text="☰";menu.custom_minimum_size.x=panel._touch_target()
	menu.pressed.connect(func():panel.menu_requested.emit());title_row.add_child(menu)
	var resources:=HBoxContainer.new();resources.name="SettlementResources";header.add_child(resources)
	for resource in ["TIMBER","STONE","HERBS","FOOD"]:
		var row:=HBoxContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;resources.add_child(row)
		row.add_child(icon(resource,24))
		var count:=Label.new();count.name="SettlementCount"+resource;count.text="0";count.add_theme_font_size_override("font_size",16);row.add_child(count)
	var feedback:=Label.new();feedback.name="SettlementFeedback";feedback.text=panel.feedback_text
	feedback.visible=not panel.feedback_text.is_empty();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.max_lines_visible=2;feedback.add_theme_font_size_override("font_size",12);header.add_child(feedback)
	var sheet:=PanelContainer.new();sheet.name="SettlementBottomSheet";sheet.add_theme_stylebox_override("panel",surface())
	stage.add_child(sheet);sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left=8;sheet.offset_right=-8;sheet.offset_bottom=-panel._touch_target()-36
	sheet.offset_top=sheet.offset_bottom-230
	var contents:=VBoxContainer.new();contents.name="SettlementSheetContent";sheet.add_child(contents)
	var heading:=HBoxContainer.new();contents.add_child(heading)
	var label:=Label.new();label.name="SettlementSheetTitle";label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",20);heading.add_child(label)
	var close:Button=panel._button("×","SettlementSheetClose");close.text="×";close.custom_minimum_size.x=panel._touch_target()
	close.pressed.connect(func():panel.close_sheet());heading.add_child(close)
	for i in range(sections.size()):
		var scroll:=ScrollContainer.new();scroll.name="BaseSectionScroll%d"%i
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y=130;contents.add_child(scroll)
		var stack:=VBoxContainer.new();stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stack.add_theme_constant_override("separation",8);scroll.add_child(stack)
		for node in sections[i]:stack.add_child(node)
	var nav:=PanelContainer.new();nav.name="SettlementBottomNavigation";nav.add_theme_stylebox_override("panel",surface())
	stage.add_child(nav);nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top=-panel._touch_target()-26;nav.offset_bottom=-4
	var bar:=HBoxContainer.new();bar.name="BaseSectionTabs";nav.add_child(bar)
	var entries:Array=[["건설","BUILD",0],["주민","RESIDENT",3],["작업","WORK",1],["원정","EXPEDITION",4]]
	for entry in entries:
		var button:Button=panel._button("","BaseSectionTab%d"%int(entry[2]));button.text=""
		button.custom_minimum_size.y=panel._touch_target()+4;button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for state in ["normal","hover","pressed","focus"]:
			var style:=surface();style.bg_color=Color("514735") if state in ["pressed","focus"] else Color("20272f")
			style.border_color=Color("c9ad77") if state in ["pressed","focus"] else Color("20272f")
			button.add_theme_stylebox_override(state,style)
		button.pressed.connect(func():panel.select_section(int(entry[2])))
		bar.add_child(button)
		var column:=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(column)
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);column.offset_top=4;column.offset_bottom=-4
		var glyph:=icon(str(entry[1]),24);glyph.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;column.add_child(glyph)
		var text:=Label.new();text.text=str(entry[0]);text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;text.mouse_filter=Control.MOUSE_FILTER_IGNORE;text.add_theme_font_size_override("font_size",14);column.add_child(text)
	panel.select_section(panel.section_tab,false)
	update(panel)

static func update(panel)->void:
	for resource in ["TIMBER","STONE","HERBS","FOOD"]:
		var label=panel.find_child("SettlementCount"+resource,true,false)
		if label!=null:label.text=str(int(panel._overview.get("food",0)) if resource=="FOOD" else int(panel._overview.get("stock",{}).get(resource,0)))
