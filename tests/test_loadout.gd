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
	var learned_before: Array = hero.learned_abilities.duplicate()
	var rules_before: int = hero.rules.size()
	check(s.grant_test_loadout(),"test loadout succeeds in town")
	var newly: Array = []
	for id in Session.Abilities.DEFINITIONS:
		check(id in hero.learned_abilities,"every catalog ability learned: "+id)
		if id not in learned_before: newly.append(id)
	check(hero.rules.size() == rules_before+newly.size(),"exactly one rule per newly learned ability")
	for i in range(rules_before,hero.rules.size()):
		check(Session.Rules.valid(hero.rules[i]),"granted rule is valid: "+str(hero.rules[i].skill))
	var granted: Array = []
	for i in range(rules_before,hero.rules.size()): granted.append(hero.rules[i].skill)
	granted.sort(); newly.sort()
	check(granted == newly,"granted rules match the newly learned abilities")
	check(hero.equipped_abilities == equipped_before,"equipment untouched")
	check(s.log_lines[-1].begins_with("시험 로드아웃 · 이능"),"grant reports the learned count")

	var learned: Array = hero.learned_abilities.duplicate()
	var rules: int = hero.rules.size()
	check(s.grant_test_loadout(),"second call still succeeds")
	check(hero.learned_abilities == learned and hero.rules.size() == rules,"second call adds nothing")
	check(s.log_lines[-1] == "시험 로드아웃 · 이미 전부 습득","idempotent call reports nothing new")

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
		check(id in s.party[0].learned_abilities,"button press learns "+id)
	scene.show_character(0,"이능")
	for frame in range(4): await process_frame
	var cards: Array = scene.modal_content.find_children("EquippedAbility*","PanelContainer",true,false)
	check(not cards.is_empty(),"ability tab still renders the equipped cards")
	# Newly learned abilities are unequipped, so the tab lists them through the slot chooser.
	scene.CharacterUI.replace(scene,0)
	for frame in range(3): await process_frame
	var titles: Array = scene.item_detail.find_children("*","Button",true,false).map(func(b): return b.text)
	for id in Session.Abilities.DEFINITIONS:
		check(Session.Rules.SKILLS[id].name in titles,"ability tab offers "+id+" for equipping")
	scene.item_popup.hide()
	scene.details_popup.hide()
	s.depart()
	scene.refresh()
	for frame in range(2): await process_frame
	check(scene.find_child("TownTestLoadout",true,false) == null,"test loadout button hidden on the floor")
	scene.queue_free(); await process_frame
