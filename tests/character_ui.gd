extends SceneTree
const Essences = preload("res://expedition/progression/essences.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://expedition/ui/main.gd").new()
	# Default play is solo; this test covers the companion character sheets.
	scene.session = scene.Session.new(731,true,true,true); root.add_child(scene)
	await process_frame
	scene.session.phase = "CAMP"
	var actor: Dictionary = scene.session.party[0]
	var presentation = preload("res://expedition/ui/body_presentation.gd")
	var snapshot: Dictionary = actor.body.to_dict().duplicate(true)
	check(presentation.summary(actor) == "건강 · 부위 이상 없음","healthy body has one plain summary")
	var part: Dictionary = actor.body.parts[0].duplicate(true)
	part.layers[0].integrity = 600
	check(presentation.part_state(part) == "상처","tissue damage becomes understandable wound label")
	part.condition = "DISABLED"
	check(presentation.part_state(part) == "사용 불가" and presentation.detail(part).contains("기능"),"disabled part describes functional loss")
	part.condition = "SEVERED"
	check(presentation.part_state(part) == "절단","severed part stays distinct")
	check(actor.body.to_dict() == snapshot,"presentation never mutates simulation")
	scene.show_character(0,"상태")
	var status_labels: Array = scene.modal_content.find_children("*","Label",true,false)
	check(not status_labels.any(func(l): return l.text.contains("피부 질김") or l.text.contains("뼈 강도") or l.text.contains("이동 비용")),"raw simulation numbers hidden from body overview")
	for viewport in [Vector2i(390,844),Vector2i(430,844),Vector2i(412,915)]:
		root.size = viewport
		await process_frame
		for member in range(2):
			for tab in ["상태","성격","기억","영혼석"]:
				scene.show_character(member,tab)
				for frame in range(4): await process_frame
				check(scene.details_popup.size.x <= viewport.x,"popup fits portrait width: "+tab)
				check(scene.details_popup.size.y <= viewport.y,"popup fits portrait height: "+tab)
				check(scene.tactics_actor == member,"selected character retained")
				if tab == "영혼석": check(scene.modal_content.find_child("EssenceSlots",true,false).get_child_count() == 6,"six essence slots")
				var folio: Control = scene.modal_content.find_child("CharacterFolio",true,false)
				check(folio.size == Vector2(390,844),"approved design dimensions")
				check(folio.get_node("CharacterTabs").position.y == 168,"mockup tab placement")
				check(folio.get_node("CharacterClose").position.y == 768,"fixed close placement")
				if "--capture" in OS.get_cmdline_user_args() and viewport == Vector2i(390,844) and member == 1:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/folio-"+str(["상태","성격","기억","영혼석"].find(tab))+".png")
	scene.session.gain_level_xp(scene.session.party[1],65)
	scene.show_character(1,"영혼석")
	await process_frame
	var slots: GridContainer = scene.modal_content.find_child("EssenceSlots",true,false)
	check(slots.get_child_count() == 6,"a second level opens a second slot in the grid")
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("영혼석 슬롯"))
	check(not heading.is_empty() and heading[0].text.ends_with("/ 2"),"the heading counts the open slots")
	check(scene.session.party[1].equipped_abilities.size() == 2,"the companion's row grew")
	check(scene.session.party[0].equipped_abilities.size() == 1,"hero unaffected")
	check(not scene.modal_content.find_children("*","Button",true,false).any(func(b): return b.text.contains("투자")),"nothing to invest")
	scene.session.party[1].equipped_abilities = ["GOBLIN_SHIV","RAT_GNAW"]
	scene.session.party[1].essences = {"GOBLIN_SHIV":1,"RAT_GNAW":1}
	scene.session.party[1].rules = [scene.Session.Abilities.default_rule("GOBLIN_SHIV"),scene.Session.Abilities.default_rule("RAT_GNAW")]
	scene.session.parts_bag["ORC_CLEAVER"] = 1
	check(not scene.session.equip_part(1,0,"ORC_CLEAVER") and scene.session.absorb_essence(1,"ORC_CLEAVER") == "영혼석 가득 참","a full companion cannot replace or absorb another stone")
	check(scene.session.party[1].equipped_abilities == ["GOBLIN_SHIV","RAT_GNAW"] and int(scene.session.parts_bag[Essences.canonical("ORC_CLEAVER")]) == 1,"rejected replacement preserves both stones and inventory")
	check(scene.session.party[0].equipped_abilities == [""],"other members keep their own slots")
	check(not scene.session.unequip_part(1,0),"permanent stone cannot be unequipped")
	scene.show_character(1,"영혼석")
	for frame in range(3): await process_frame
	check(scene.modal_content.find_child("EssenceSlots",true,false).get_child_count() == 6,"one card per permanent slot")
	EssenceTab.pressed_slot(scene,0)
	for frame in range(3): await process_frame
	check(scene.item_detail.find_child("EssenceUnequip",true,false) == null,"stone detail has no removal control")
	check(scene.item_detail.find_children("EssencePick_*","Button",true,false).is_empty(),"stone detail has no replacement chooser")
	scene.item_popup.hide()
	scene.queue_free(); await process_frame
	print("Character UI: %d failures" % failures); quit(1 if failures else 0)
