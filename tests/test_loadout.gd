extends SceneTree
## Playtest loadout helper and camp-only part editing.
const Session = preload("res://expedition/run/session.gd")
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
	check(s.grant_test_loadout(),"test loadout succeeds for an idle test session")
	var newly: Array = []
	for id in Session.Essences.content.rows:
		check(s.parts_bag.get(id,0) >= 1,"every catalog part is in the bag: "+id)
		if int(bag_before.get(id,0)) <= 0: newly.append(id)
	check(not newly.is_empty(),"the grant adds the parts the bag lacked")
	check(hero.equipped_abilities == equipped_before and hero.rules.size() == rules_before,"equipment and rules untouched")
	check(s.log_lines[-1] == "시험 로드아웃 · 영혼석 %d종" % newly.size(),"grant reports the granted count")

	var bag: Dictionary = s.parts_bag.duplicate(true)
	check(s.grant_test_loadout(),"second call still succeeds")
	check(s.parts_bag == bag,"second call adds nothing")
	check(s.log_lines[-1] == "시험 로드아웃 · 이미 전부 보유","idempotent call reports nothing new")

	s.depart()
	check(s.grant_test_loadout() and s.parts_bag == bag,"test loadout stays idempotent during a run")

	var room_mode = Session.new(731,false,false,false)
	check(room_mode.grant_test_loadout(),"legacy constructor flag does not change the run helper")

func scene_layer() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(4): await process_frame
	var loadout: Button = scene.find_child("TownTestLoadout",true,false)
	check(loadout == null,"run HUD has no test loadout button")
	check(scene.find_child("BottomActions",true,false) != null,"run HUD offers direct actions")
	check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"run HUD fits viewport")
	check(s.grant_test_loadout(),"test fixture grants parts through session API")
	for frame in range(4): await process_frame
	for id in Session.Essences.content.rows:
		check(s.parts_bag.get(id,0) >= 1,"fixture grants "+id)
	s.phase = "CAMP"; scene.refresh()
	s.gain_level_xp(s.party[0],65)
	check(s.equip_part(0,0,"RAT_GNAW") and s.equip_part(0,1,"GOBLIN_SHIV"),"granted parts can be equipped")
	scene.show_character(0,"영혼석")
	for frame in range(4): await process_frame
	var cards: Array = scene.modal_content.find_children("EssenceSlot*","Button",true,false)
	check(cards.size() == 10,"the essence tab renders ten slot cells")
	scene.find_child("EssenceSlot0",true,false).pressed.emit()
	for frame in range(3): await process_frame
	for id in Session.Essences.content.rows:
		if id in s.party[0].equipped_abilities: continue
		check(scene.modal_content.find_child("EssenceAbsorb_"+id,true,false) != null,"the granted bag offers absorption: "+id)
	scene.item_popup.hide()
	scene.details_popup.hide()
	s.phase = "BATTLE"
	scene.refresh()
	for frame in range(2): await process_frame
	check(scene.find_child("TownTestLoadout",true,false) == null and not s.equip_part(0,0,"BOMB"),"floor has no test button and forbids part edits")
	scene.queue_free(); await process_frame
