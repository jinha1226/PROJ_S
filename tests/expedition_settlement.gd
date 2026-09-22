extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func clear_enemies(s) -> void:
	for enemy in s.enemies: enemy.hp = 0
	s.floor_state.observe(s)

func button_named(parent: Node, title: String) -> Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text == title: return child
	return null

func run() -> void:
	# A free kit must never be converted to funds, including after buy/refund.
	var s = Session.new(731,true,false,true)
	var bank: int = s.bank
	for i in range(3):
		check(s.buy("supply:0") and s.refund("supply:0"),"same visit purchase/refund")
		s.depart()
		check(s.provision_sale_value() == 0,"free provisions have no resale value")
		if i % 2 == 0: check(s.abandon(),"safe abandonment allowed at entry")
		else: check(s.return_home(),"safe partial return allowed at entry")
		check(s.bank == bank and s.result.provisions == 0,"free-kit return cannot mint money")
		s.refit()
		check(not s.finish_expedition("ABANDON") and s.bank == bank,"acknowledging result cannot settle again")
	# Bought and found goods are liquidated once; free goods are used first.
	s = Session.new(731,true,false,true)
	s.buy("supply:0"); s.buy("supply:0"); s.buy("supply:1")
	bank = s.bank; s.depart(); clear_enemies(s)
	s.party[0].hp = 20
	check(s.use_supply(0),"use free potion before paid stock")
	check(s.free_provisions["supply:0"] == 0 and s.supplies[0] == 2,"paid potions remain eligible for sale")
	s.loot = 30
	check(s.return_home(),"return liquidates bought leftovers")
	check(s.result.provisions == 2 and s.bank == bank+32,"22 gold of paid leftovers sells for two gold")
	check(s.supplies == Session.MIN_KIT.supplies and not s.refund("supply:0"),"liquidated goods neither carry nor refund")
	bank = s.bank
	check(not s.return_home() and not s.finish_expedition("PARTIAL") and s.bank == bank,"return settlement is once-only")
	# Abandon keeps actual expedition gains, growth, wounds and memories.
	s = Session.new(731,true,false,true)
	for i in range(8): s.buy("food")
	bank = s.bank; s.depart(); clear_enemies(s)
	var hero: Dictionary = s.party[0]
	var p: Vector2i = s.floor_state.features.keys().filter(func(cell): return s.floor_state.features[cell].get("curio_id","") == "DIRT_PILE")[0]
	hero.pos = p+Vector2i.LEFT; s.floor_state.observe(s)
	check(Session.Curios.resolve(s,p,"TOOL"),"recover food through a real curio")
	s.parts_bag.BOMB = 1; Session.Growth.gain(hero,100)
	s.damage(hero,5,999,"IMPACT"); hero.stress = 40
	var hp: int = hero.hp; var body: Dictionary = hero.body.to_dict()
	var memories: Dictionary = hero.memory.to_dict()
	s.objective.state = "CARRIED"
	check(s.abandon(),"abandon expedition with recovered supplies")
	check(s.result.reason == "ABANDON" and s.result.bonus == 0 and s.objective.state == "LOST","abandon never pays mission bonus")
	check(s.parts_bag.BOMB == 1 and s.party[0].growth.level == 2,"abandon preserves loot and growth")
	check(s.party[0].hp == hp and s.party[0].body.to_dict() == body and s.party[0].memory.to_dict() == memories,"abandon does not roll back health, injuries or memories")
	check(s.party[0].stress == 60,"abandon adds fixed twenty stress without trait modifiers")
	check(s.bank == bank+21 and s.result.remaining_food == 22 and s.food == 12,"found food is sold, not carried, alongside curio loot")
	# Threats block abandonment through both public entry points.
	s.refit(); s.depart()
	s.enemies[0].pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s)
	check(not s.abandon() and not s.finish_expedition("ABANDON") and s.result.is_empty(),"cannot abandon while enemies are visible")
	# Defeat retains the old permanent state but forfeits all expedition supplies.
	clear_enemies(s)
	var permanent_parts: Dictionary = s.parts_bag.duplicate(true)
	var permanent_level: int = s.party[0].growth.level
	bank = s.bank
	s.parts_bag.BOMB += 3; s.add_stock("food",100); s.add_stock("supply:0",5); s.loot = 90
	Session.Growth.gain(s.party[0],1000)
	s.damage(s.party[0],999,999,"IMPACT"); s.check_battle_end()
	check(s.result.reason == "DEFEAT" and s.result.provisions == 0 and s.bank == bank,"defeat pays neither loot nor supply salvage")
	check(s.parts_bag == permanent_parts and s.party[0].growth.level == permanent_level,"defeat restores permanent gains")
	check(s.food == 12 and s.supplies == Session.MIN_KIT.supplies,"defeat discards found goods before free restocking")
	# The result records actual resources before town grants obscure the run.
	s.refit(); s.depart(); clear_enemies(s); s.add_stock("food",-s.food)
	s.return_home()
	check(s.result.remaining_food == 0 and s.food == 12,"starved return is not reported as twelve remaining food")
	# A consumable action can kill the hero. Consume before settlement/reset.
	s.refit(); s.buy("supply:3"); s.depart(); clear_enemies(s)
	s.party[0].hp = 1; s.tile(s.party[0].pos).terrain = "wood"
	check(s.use_supply(3,s.party[0].pos),"fire scroll action accepted")
	check(s.result.get("reason","") == "DEFEAT" and s.supplies[3] == 0,"death during consumable action cannot debit the next kit")
	# The actual confirmation and result UI must use the same settlement path.
	s = Session.new(731,true,false,true); s.depart(); s.loot = 25
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	s.enemies[0].pos = s.party[0].pos+Vector2i.RIGHT; s.floor_state.observe(s)
	scene.confirm_abandon(); await process_frame
	check(button_named(scene.modal_content,"포기하고 돌아가기").disabled,"confirmation cannot bypass a visible threat")
	clear_enemies(s); scene.confirm_abandon(); await process_frame
	button_named(scene.modal_content,"포기하고 돌아가기").pressed.emit(); await process_frame
	check(s.result.reason == "ABANDON" and s.result.loot == 25 and s.bank == 70,"confirmation button keeps actual loot")
	for viewport in [Vector2i(390,844),Vector2i(412,915)]:
		root.size = viewport; scene.refresh()
		for frame in range(4): await process_frame
		var card: Control = scene.find_child("ResultCard",true,false)
		check(card != null and scene.get_global_rect().encloses(card.get_global_rect()),"abandon result fits portrait screen")
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"abandon result leaves room for footer")
		var labels: Array = card.find_children("*","Label",true,false).map(func(node): return node.text)
		check(labels.any(func(value): return value.contains("스트레스 +20")) and labels.any(func(value): return value.contains("보급품 환전")),"result explains penalty and supply liquidation")
	scene.queue_free(); await process_frame
	print("Expedition settlement: %d failures" % failures); quit(1 if failures else 0)
