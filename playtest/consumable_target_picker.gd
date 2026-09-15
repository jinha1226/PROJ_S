extends RefCounted
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
static func open(ui,rows:Array,choose:Callable)->void:
	var panel:=PopupPanel.new();panel.name="ConsumableTargetPicker"
	ui.add_child(panel)
	var frame:=PanelContainer.new();panel.add_child(frame);DarkSkin.apply_panel(frame,"SECTION")
	var layout:=VBoxContainer.new();frame.add_child(layout)
	var title:=Label.new();title.text="대상 선택 · 취소하면 소모 없음";title.add_theme_font_override("font",DarkSkin.PixelFont);title.add_theme_font_size_override("font_size",14);layout.add_child(title)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(300,320);layout.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	for row in rows:
		var button:=Button.new();button.text=str(row.label);button.custom_minimum_size.y=48;list.add_child(button)
		DarkSkin.apply_action_button(button,DarkSkin.CYAN)
		# Defer the choice until the closing popup has left the tree. Chained
		# recipient -> use-mode pickers otherwise race under one parent/name.
		button.pressed.connect(func():panel.hide();choose.call_deferred(row.selection))
	var cancel:=Button.new();cancel.text="취소";cancel.custom_minimum_size.y=48;layout.add_child(cancel)
	DarkSkin.apply_action_button(cancel,DarkSkin.CYAN)
	cancel.pressed.connect(panel.hide);panel.popup_hide.connect(panel.queue_free)
	panel.popup_centered(Vector2i(320,420))
