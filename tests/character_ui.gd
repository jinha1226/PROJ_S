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
				if tab == "영혼석": check(scene.modal_content.find_child("EssenceSlots",true,false).get_child_count() == 10,"ten essence slots")
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
	check(slots.get_child_count() == 10,"a second level opens a second slot in the grid")
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("영혼석 슬롯"))
	check(not heading.is_empty() and heading[0].text.ends_with("/ 2"),"the heading counts the open slots")
	check(scene.session.party[1].equipped_abilities.size() == 2,"the companion's row grew")
	check(scene.session.party[0].equipped_abilities.size() == 1,"hero unaffected")
	check(not scene.modal_content.find_children("*","Button",true,false).any(func(b): return b.text.contains("투자")),"nothing to invest")
	scene.session.party[1].equipped_abilities = ["GOBLIN_SHIV","RAT_GNAW"]
	scene.session.party[1].essences = {"GOBLIN_SHIV":1,"RAT_GNAW":1}
	scene.session.party[1].rules = [scene.Session.Abilities.default_rule("GOBLIN_SHIV"),scene.Session.Abilities.default_rule("RAT_GNAW")]
	scene.session.parts_bag["ORC_CLEAVER"] = 1
	check(scene.session.equip_part(1,0,"ORC_CLEAVER") and scene.session.party[1].equipped_abilities == ["ORC_CLEAVER","RAT_GNAW"] and scene.session.parts_bag.ORC_CLEAVER == 0,"equipping fills the chosen slot only")
	check(scene.session.parts_bag.get("GOBLIN_SHIV",0) == 0 and scene.session.party[1].essences.has("GOBLIN_SHIV"),"the replaced essence stays absorbed")
	check(scene.session.party[0].equipped_abilities == [""],"other members keep their own slots")
	# A rule for a part nobody has equipped stays out of the sheet.
	scene.session.party[1].rules.append(scene.Session.Rules.make_rule("GOBLIN_SHIV","NEAREST","ALWAYS"))
	scene.show_character(1,"영혼석")
	check(scene.modal_content.find_child("EssenceSlots",true,false).get_child_count() == 10,"one card per slot, not per rule")
	for frame in range(3): await process_frame
	check(scene.modal_content.find_children("*","Button",true,false).all(func(b): return not b.text.begins_with("사용 방침") and not b.text.begins_with("자동 ")),"the slot card carries no rule policy and no auto toggle")
	# Camp equipping goes through the chooser the card opens.
	scene.session.phase = "CAMP"
	check(scene.session.unequip_part(1,0) and scene.session.parts_bag.ORC_CLEAVER == 0 and scene.session.party[1].essences.has("ORC_CLEAVER"),"unequipping keeps the essence absorbed")
	scene.show_character(1,"영혼석")
	for frame in range(3): await process_frame
	EssenceTab.chooser(scene,0)
	for frame in range(3): await process_frame
	var picks: Array = scene.item_detail.find_children("*","Button",true,false).filter(func(b): return b.name == "EssencePick_ORC_CLEAVER")
	check(picks.size() == 1 and not picks[0].disabled,"the chooser offers the bagged part in camp")
	picks[0].pressed.emit()
	for frame in range(3): await process_frame
	check(scene.session.party[1].equipped_abilities[0] == "ORC_CLEAVER","the chooser equips into the chosen slot")
	scene.item_popup.hide()
	scene.queue_free(); await process_frame
	print("Character UI: %d failures" % failures); quit(1 if failures else 0)
