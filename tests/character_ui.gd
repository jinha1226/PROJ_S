extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://expedition/main.gd").new()
	# Default play is solo; this test covers the companion character sheets.
	scene.session = scene.Session.new(731,true,true,true); root.add_child(scene)
	await process_frame
	scene.session.phase = "CAMP"
	var actor: Dictionary = scene.session.party[0]
	var presentation = preload("res://expedition/body_presentation.gd")
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
			for tab in ["상태","성격","기억","숙련","파츠"]:
				scene.show_character(member,tab)
				for frame in range(4): await process_frame
				check(scene.details_popup.size.x <= viewport.x,"popup fits portrait width: "+tab)
				check(scene.details_popup.size.y <= viewport.y,"popup fits portrait height: "+tab)
				check(scene.tactics_actor == member,"selected character retained")
				if tab == "숙련": check(scene.modal_content.find_child("MasteryGrid",true,false).columns == 2,"two-column mastery cards")
				var folio: Control = scene.modal_content.find_child("CharacterFolio",true,false)
				check(folio.size == Vector2(390,844),"approved design dimensions")
				check(folio.get_node("CharacterTabs").position.y == 168,"mockup tab placement")
				check(folio.get_node("CharacterClose").position.y == 768,"fixed close placement")
				if "--capture" in OS.get_cmdline_user_args() and viewport == Vector2i(390,844) and member == 1:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/folio-"+str(["상태","성격","기억","숙련","파츠"].find(tab))+".png")
	scene.session.party[1].growth.points = 2
	scene.show_character(1,"숙련")
	var before: int = scene.session.party[1].growth.ranks.MELEE
	scene.CharacterUI.preview(scene,"MELEE")
	await process_frame
	var dialogs: Array = scene.details_popup.find_children("*","ConfirmationDialog",true,false)
	check(dialogs.size() == 1,"investment opens confirmation")
	check(scene.session.party[1].growth.ranks.MELEE == before,"preview spends nothing")
	dialogs[0].confirmed.emit()
	await process_frame
	check(scene.session.party[1].growth.ranks.MELEE == before+1,"confirmation invests in companion")
	check(scene.session.party[0].growth.ranks.MELEE == 0,"hero unaffected")
	scene.session.party[1].equipped_abilities = ["PUSH","GUARD"]
	scene.session.party[1].rules = [scene.Session.Abilities.default_rule("PUSH"),scene.Session.Abilities.default_rule("GUARD")]
	scene.session.parts_bag["BOMB"] = 1
	check(scene.session.equip_part(1,0,"BOMB") and scene.session.party[1].equipped_abilities == ["BOMB","GUARD"] and scene.session.parts_bag.BOMB == 0,"equipping fills the chosen slot only")
	check(scene.session.parts_bag.get("PUSH",0) == 2,"the replaced part returns to the bag")
	check(scene.session.party[0].equipped_abilities == ["",""],"other members keep their own slots")
	# A rule for a part nobody has equipped stays out of the sheet.
	scene.session.party[1].rules.append(scene.Session.Rules.make_rule("PUSH","NEAREST","ALWAYS"))
	scene.show_character(1,"파츠")
	check(scene.modal_content.find_children("PartSlot*","PanelContainer",true,false).size() == 2,"one card per slot, not per rule")
	for frame in range(3): await process_frame
	check(scene.modal_content.find_children("*","Button",true,false).all(func(b): return not b.text.begins_with("사용 방침") and not b.text.begins_with("자동 ")),"the slot card carries no rule policy and no auto toggle")
	# Camp equipping goes through the chooser the card opens.
	scene.session.phase = "CAMP"
	check(scene.session.unequip_part(1,0) and scene.session.parts_bag.BOMB == 1,"unequipping returns the part to the bag")
	scene.show_character(1,"파츠")
	for frame in range(3): await process_frame
	scene.CharacterUI.replace(scene,0)
	for frame in range(3): await process_frame
	var picks: Array = scene.item_detail.find_children("*","Button",true,false).filter(func(b): return b.text == "폭탄 투척 ×1")
	check(picks.size() == 1 and not picks[0].disabled,"the chooser offers the bagged part in camp")
	picks[0].pressed.emit()
	for frame in range(3): await process_frame
	check(scene.session.party[1].equipped_abilities[0] == "BOMB","the chooser equips into the chosen slot")
	scene.item_popup.hide()
	scene.queue_free(); await process_frame
	print("Character UI: %d failures" % failures); quit(1 if failures else 0)
