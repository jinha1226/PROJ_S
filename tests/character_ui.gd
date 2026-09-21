extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://expedition/main.gd").new(); root.add_child(scene)
	await process_frame
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
			for tab in ["상태","성격","기억","숙련","이능"]:
				scene.show_character(member,tab)
				for frame in range(4): await process_frame
				check(scene.details_popup.size.x <= viewport.x,"popup fits portrait width: "+tab)
				check(scene.details_popup.size.y <= viewport.y,"popup fits portrait height: "+tab)
				check(scene.tactics_actor == member,"selected character retained")
				if tab == "숙련": check(scene.modal_content.find_child("MasteryGrid",true,false).columns == 2,"two-column mastery cards")
				var folio: Control = scene.modal_content.find_child("CharacterFolio",true,false)
				check(folio.size == Vector2(390,844),"approved design dimensions")
				check(folio.get_node("CharacterTabs").position.y == 110,"fixed tab placement")
				check(folio.get_node("CharacterClose").position.y == 768,"fixed close placement")
				if "--capture" in OS.get_cmdline_user_args() and viewport == Vector2i(390,844) and member == 1:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/folio-"+str(["상태","성격","기억","숙련","이능"].find(tab))+".png")
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
	scene.session.party[1].learned_abilities.append("BOMB")
	scene.session.party[1].rules.append(scene.Session.Rules.make_rule("BOMB","NEAREST","ALWAYS"))
	scene.show_character(1,"이능")
	check(scene.modal_content.find_children("EquippedAbility*","PanelContainer",true,false).size() == 2,"unequipped ability hidden")
	scene.CharacterUI.replace(scene,0)
	await process_frame
	var choices: Array = scene.item_detail.find_children("*","Button",true,false)
	var bomb = choices.filter(func(b): return b.text == "폭탄 투척")[0]
	bomb.pressed.emit()
	check(scene.session.party[1].equipped_abilities[0] == "BOMB","replace targets originating card")
	check(scene.session.party[1].equipped_abilities[1] == "GUARD","other slot unchanged")
	check(scene.session.party[0].equipped_abilities[0] == "PUSH","other actor unchanged")
	for frame in range(3): await process_frame
	var policies: Array = scene.modal_content.find_children("*","Button",true,false).filter(func(b): return b.text.begins_with("사용 방침"))
	policies[0].pressed.emit(); await process_frame
	check(scene.item_popup.visible,"policy opens child popup")
	scene.item_popup.hide()
	scene.queue_free(); await process_frame
	print("Character UI: %d failures" % failures); quit(1 if failures else 0)
