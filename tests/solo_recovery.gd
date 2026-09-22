extends SceneTree
## Player-visible recovery, collapse penalty, and walking home without teleporting.
const Session = preload("res://expedition/session.gd")
var failures := 0

func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func button_named(parent: Node, title: String) -> Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text == title: return child
	return null

func run() -> void:
	var s = Session.new(0,true,false,true)
	s.bank = 0 # Provisioning funds are covered elsewhere; this case starts broke.
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	scene.show_infirmary()
	var rest := button_named(scene.modal_content,"요양 · 20 자금")
	check(rest != null and rest.disabled,"solo preparation shows unaffordable rest disabled")
	scene.details_popup.hide()
	s.depart()
	for enemy in s.enemies: enemy.hp = 0
	s.loot = 100
	check(s.return_home(),"return with funds from entry")
	s.party[0].hp = 5; s.party[0].stress = 200
	scene.refresh(); await process_frame
	button_named(scene.root_layout,"정비하기").pressed.emit(); await process_frame
	check(s.party[0].hp == ceili(s.party[0].max_hp*0.8) and s.party[0].stress == 60,"free refit gives 80 percent health and reduces stress")
	check(s.bank == 100,"free refit keeps earned funds")
	scene.show_infirmary()
	rest = button_named(scene.modal_content,"요양 · 20 자금")
	check(rest != null and not rest.disabled,"solo can access paid recovery after refit")
	rest.pressed.emit(); await process_frame
	check(s.bank == 80 and s.party[0].hp == s.party[0].max_hp and s.party[0].stress == 20,"rest button spends funds and heals the same hero")
	for viewport in [Vector2i(390,844),Vector2i(412,915)]:
		root.size = viewport; scene.refresh()
		for frame in range(4): await process_frame
		rest = scene.find_child("TownInfirmary",true,false)
		check(scene.get_global_rect().encloses(rest.get_global_rect()),"rest button fits portrait viewport")
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"town layout fits portrait viewport")
	# Damage changes at collapse, then calming restores the ordinary damage rule.
	check(s.buy("supply:1"),"calming supply bought in town")
	s.depart()
	for enemy in s.enemies: enemy.hp = 0
	var hero: Dictionary = s.party[0]
	hero.stress = 149; var hp: int = hero.hp
	s.damage(hero,5,999,"IMPACT")
	check(hero.hp == hp-5,"below collapse receives ordinary damage")
	hero.stress = 150; hp = hero.hp
	s.damage(hero,5,999,"IMPACT")
	check(hero.hp == hp-6,"solo collapse adds exactly one damage")
	check(s.use_supply(1) and hero.stress < 150,"calming supply removes collapse")
	hp = hero.hp; s.damage(hero,5,999,"IMPACT")
	check(hero.hp == hp-5,"calming prevents the extra damage")
	var duo = Session.new(0,true,true,true); duo.depart()
	duo.party[0].stress = 150; hp = duo.party[0].hp
	duo.damage(duo.party[0],5,999,"IMPACT")
	check(duo.party[0].hp == hp-5,"solo penalty does not change companion combat")
	# Walk out from entry using public actions, then walk back over known ground.
	s.abandon(); s.refit(); s.depart()
	for enemy in s.enemies: enemy.hp = 0
	var entry: Vector2i = s.entry_position()
	for i in range(4): check(s.act("MOVE",s.party[0].pos+Vector2i.RIGHT),"walk away from entry")
	scene.refresh(); scene.show_objective(); await process_frame
	var before: Vector2i = s.party[0].pos
	button_named(scene.modal_content,"입구까지 이동").pressed.emit()
	check(scene.navigation.active and s.party[0].pos == before,"return button starts navigation without teleporting")
	await process_frame
	for i in range(12):
		if not scene.navigation.active: break
		scene.navigation_tick()
		await process_frame
	check(s.party[0].pos == entry and not scene.navigation.active,"return walk reaches the entry and stops")
	check(s.phase == "BATTLE" and s.result.is_empty(),"arriving does not settle without confirmation")
	scene.show_objective(); await process_frame
	button_named(scene.modal_content,"입구까지 이동").pressed.emit(); await process_frame
	check(scene.details_popup.visible and button_named(scene.modal_content,"귀환 확정") != null,"at entry the button opens return confirmation")
	scene.details_popup.hide(); s.abandon(); s.refit(); s.depart()
	s.enemies[0].pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s)
	scene.show_objective(); await process_frame
	check(button_named(scene.modal_content,"입구까지 이동").disabled,"visible enemies disable return navigation")
	scene.start_return_walk()
	check(not scene.navigation.active and s.phase == "BATTLE","direct return action cannot bypass visible enemies")
	scene.queue_free(); await process_frame
	print("Solo recovery: %d failures" % failures); quit(1 if failures else 0)
