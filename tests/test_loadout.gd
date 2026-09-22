extends SceneTree
## Playtest test loadout: session grant rules, idempotence, town gating, and the settlement button.
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	session_layer()
	await scene_layer()
	print("Test loadout: %d failures" % failures); quit(1 if failures else 0)

func session_layer() -> void:
	var s = Session.new(731,false,false,true)
	var hero: Dictionary = s.party[0]
	var equipped_before: Array = hero.equipped_abilities.duplicate()
	var rules_before: int = hero.rules.size()
	var bag_before: Dictionary = s.parts_bag.duplicate(true)
	check(s.grant_test_loadout(),"test loadout succeeds in town")
	var newly: Array = []
	for id in Session.Abilities.DEFINITIONS:
		check(s.parts_bag.get(id,0) >= 1,"every catalog part is in the bag: "+id)
		if int(bag_before.get(id,0)) <= 0: newly.append(id)
	check(not newly.is_empty(),"the grant adds the parts the bag lacked")
	check(hero.equipped_abilities == equipped_before and hero.rules.size() == rules_before,"equipment and rules untouched")
	check(s.log_lines[-1] == "시험 로드아웃 · 파츠 %d종 지급 — 파츠 탭에서 장착하세요." % newly.size(),"grant reports the granted count")

	var bag: Dictionary = s.parts_bag.duplicate(true)
	check(s.grant_test_loadout(),"second call still succeeds")
	check(s.parts_bag == bag,"second call adds nothing")
	check(s.log_lines[-1] == "시험 로드아웃 · 이미 전부 보유","idempotent call reports nothing new")

	s.depart()
	check(not s.grant_test_loadout(),"test loadout refused outside town")

	var room_mode = Session.new(731,false,false,false)
	check(not room_mode.grant_test_loadout(),"test loadout refused outside floor mode")

func scene_layer() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,false,false,true)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(4): await process_frame
	var hub = scene.find_child("SettlementHub",true,false)
	var loadout: Button = scene.find_child("TownTestLoadout",true,false)
	check(loadout != null and loadout.text == "시험 로드아웃","town shows the test loadout button")
	check(hub.get_global_rect().encloses(loadout.get_global_rect()),"test loadout button fits the settlement")
	check(scene.get_global_rect().encloses(loadout.get_global_rect()),"test loadout button fits the viewport")
	loadout.pressed.emit()
	for frame in range(4): await process_frame
	for id in Session.Abilities.DEFINITIONS:
		check(s.parts_bag.get(id,0) >= 1,"button press grants "+id)
	check(s.equip_part(0,0,"PUSH") and s.equip_part(0,1,"GUARD"),"granted parts can be equipped")
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	var cards: Array = scene.modal_content.find_children("PartSlot*","PanelContainer",true,false)
	check(cards.size() == 2,"the parts tab renders the equipped cards")
	scene.CharacterUI.replace(scene,0)
	for frame in range(3): await process_frame
	var offered: Array = scene.item_detail.find_children("*","Button",true,false).map(func(b): return b.text)
	for id in Session.Abilities.DEFINITIONS:
		if id in s.party[0].equipped_abilities: continue
		check(Session.Rules.skill(id).name+" ×1" in offered,"the granted bag is offered for the slot: "+id)
	scene.item_popup.hide()
	scene.details_popup.hide()
	s.depart()
	scene.refresh()
	for frame in range(2): await process_frame
	check(scene.find_child("TownTestLoadout",true,false) == null,"test loadout button hidden on the floor")
	scene.queue_free(); await process_frame
