extends RefCounted
## A small child popup; closing it returns to the unchanged card below.
static var words: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/keywords.json")).get("keywords",{})

static func chips(ui, parent: Node, keywords: Array) -> HFlowContainer:
	var row := HFlowContainer.new(); row.name = "KeywordChips"; row.add_theme_constant_override("h_separation",4); parent.add_child(row)
	for word in keywords:
		var chip = ui.button(row,str(word),func(): show(ui,str(word)))
		chip.name = "KeywordChip_"+str(word); chip.custom_minimum_size = Vector2(0,32)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		chip.add_theme_font_size_override("font_size",11)
	return row

static func show(ui, keyword: String) -> void:
	if not words.has(keyword): return
	var parent: Node = ui.item_popup if ui.item_popup.visible else ui.details_popup
	if not parent.visible: parent.popup_centered()
	var popup: PopupPanel = parent.get_node_or_null("KeywordPopupWindow")
	if popup == null:
		popup = PopupPanel.new(); popup.name = "KeywordPopupWindow"
		popup.transient = true; popup.exclusive = true; parent.add_child(popup)
	for child in popup.get_children(): popup.remove_child(child); child.queue_free()
	popup.reset_size()
	var box := VBoxContainer.new(); box.name = "KeywordPopup"; box.custom_minimum_size.x = ui.popup_width()-16; popup.add_child(box)
	ui.label(box,keyword,18)
	var text = ui.label(box,str(words[keyword]),13)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(box,"닫기",func(): popup.hide()).name = "KeywordClose"
	popup.popup_centered()
