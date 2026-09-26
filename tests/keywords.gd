extends SceneTree
## Keyword chips (legibility spec §2): every keyword has a meaning, and a chip
## opens it.
const Session = preload("res://expedition/run/session.gd")
const KeywordPopup = preload("res://expedition/ui/screens/keyword_popup.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).effects
	for id in effects:
		for word in effects[id].get("keywords",[]):
			check(KeywordPopup.words.has(word) and not str(KeywordPopup.words[word]).is_empty(),"%s has a meaning (%s)" % [word,id])
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = Session.new_run(731); root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(3): await process_frame
	var holder := VBoxContainer.new(); scene.modal_content.add_child(holder)
	KeywordPopup.chips(scene,holder,["출혈"])
	var chip: Button = holder.find_child("KeywordChip_출혈",true,false)
	check(chip != null,"a chip is made")
	chip.pressed.emit()
	for _i in range(3): await process_frame
	check(scene.details_popup.visible and scene.details_popup.find_child("KeywordPopup",true,false) != null,"pressing it opens the meaning")
	var child: PopupPanel = scene.details_popup.get_node("KeywordPopupWindow")
	var holder_id: int = holder.get_instance_id()
	child.find_child("KeywordClose",true,false).pressed.emit()
	for _i in range(3): await process_frame
	check(not child.visible and is_instance_valid(holder) and holder.get_instance_id() == holder_id,"closing keyword preserves the original content")
	check(scene.modal_content.get_child_count() == 1,"original card is not replaced")
	scene.details_popup.hide()
	var s = scene.session
	s.grant_gear({"type":"axe","unrand":"AXE","affix":"UNRAND_AXE","cost_effect":"COST_AXE","tier":"unrand","name":"피 먹는 도끼"})
	scene.show_supplies()
	preload("res://expedition/ui/screens/popups.gd").show_item_detail(scene,"gear:0")
	for _i in range(3): await process_frame
	var selected: String = scene.inventory_selected
	var item_window_id: int = scene.item_detail.get_instance_id()
	var item_chip: Button = scene.item_detail.find_child("KeywordChip_장비",true,false)
	check(item_chip != null,"equipment detail has actual effect keyword chips")
	item_chip.pressed.emit()
	for _i in range(3): await process_frame
	var overlay: PopupPanel = scene.item_popup.get_node("KeywordPopupWindow")
	check(overlay.visible and scene.item_popup.visible,"keyword overlays rather than replaces the inventory detail")
	overlay.find_child("KeywordClose",true,false).pressed.emit()
	check(scene.item_popup.visible and scene.item_detail.get_instance_id() == item_window_id and scene.inventory_selected == selected,"closing returns to the same item selection")
	print("Keywords: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
