extends SceneTree
## Town provisioning: minimum kit, purchases with funds, same-visit refunds, return liquidation.
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func button_named(parent: Node, title: String) -> Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text.begins_with(title): return child
	return null

func run() -> void:
	var s = Session.new(731,true,false,true)
	check(s.bank == Session.STARTING_FUNDS and s.bank == 45,"solo starts with provisioning funds")
	check(Session.new(731).bank == 0,"room mode keeps its old economy")
	check(s.price("food") == 1 and s.price("torch") == 4 and s.price("supply:0") == 8 and s.price("tool:KEY") == 6,"catalog prices")
	check(s.price("nope") < 0 and not s.buy("nope"),"unknown goods rejected")
	var food: int = s.food
	check(food == Session.MIN_KIT.food and s.torches == 2 and s.supplies == [1,0,0,0,0,1],"minimum kit is stocked before shopping")
	check(s.buy("food") and s.food == food+1 and s.bank == 44,"buying food deducts one")
	check(s.buy("supply:0") and s.supplies[0] == 2 and s.bank == 36,"potion purchase")
	check(s.buy("tool:KEY") and s.exploration_tools.KEY == 2 and s.bank == 30,"tool purchase")
	check(s.refund("supply:0") and s.supplies[0] == 1 and s.bank == 38,"same-visit refund at full price")
	check(not s.refund("supply:0"),"cannot refund what was not bought this visit")
	s.bank = 3
	check(not s.buy("torch") and s.bank == 3,"insufficient funds refused")
	s.bank = 60
	for i in range(60): s.buy("food")
	check(s.bank == 0 and s.food == food+61,"funds spend down to zero")
	# Minimum kit tops up what is missing and never removes purchases.
	s = Session.new(731,true,false,true)
	s.buy("supply:1"); s.buy("torch"); s.buy("torch")
	var spent: int = s.bank
	check(s.depart(),"depart with purchases")
	check(s.food == Session.MIN_KIT.food and s.torches == Session.MIN_KIT.torches+2 and s.supplies == [1,1,0,0,0,1] and s.exploration_tools == {"KEY":1,"SHOVEL":1},"purchases add on top of the minimum kit")
	check(s.bank == spent and s.light == 90,"depart never charges again; a fresh torch is lit")
	check(not s.buy("food") and not s.refund("torch"),"no trading on the floor")
	for enemy in s.enemies: enemy.hp = 0
	s.food = 20; s.supplies[1] = 0; s.torches = 0
	s.return_home()
	check(s.food == Session.MIN_KIT.food and s.torches == Session.MIN_KIT.torches and s.supplies[1] == 0,"return clears leftovers before granting the new minimum kit")
	s.refit()
	check(not s.refund("torch"),"previous visit purchases are not refundable")
	check(s.depart() and s.food == Session.MIN_KIT.food and s.torches == 2,"departure changes no stock")
	s.abandon(); s.refit()
	check(s.bank == spent,"funds persist across expeditions")
	# UI: shop popup from the town screen.
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	var shop := button_named(scene.root_layout,"상점")
	check(shop != null,"town screen offers the shop")
	shop.pressed.emit(); await process_frame
	check(scene.details_popup.visible and scene.details_popup.size.y <= root.size.y and scene.details_popup.size.x <= root.size.x,"shop popup fits portrait screen")
	var funds: int = s.bank
	var plus := button_named(scene.modal_content,"+")
	check(plus != null,"shop rows have buy buttons")
	var torches: int = s.torches
	var torch_plus: Button = null
	for row in scene.modal_content.find_children("ShopRow*","HBoxContainer",true,false):
		if row.name == "ShopRow_torch": torch_plus = button_named(row,"+")
	torch_plus.pressed.emit(); await process_frame
	check(s.torches == torches+1 and s.bank == funds-4,"shop buy button purchases one torch")
	var torch_minus: Button = null
	for row in scene.modal_content.find_children("ShopRow*","HBoxContainer",true,false):
		if row.name == "ShopRow_torch": torch_minus = button_named(row,"−")
	torch_minus.pressed.emit(); await process_frame
	check(s.torches == torches and s.bank == funds,"shop refund button returns the torch")
	s.depart(); scene.refresh(); await process_frame
	check(button_named(scene.root_layout,"상점") == null,"no shop on the floor")
	scene.queue_free(); await process_frame
	print("Solo provisioning: %d failures" % failures); quit(1 if failures else 0)
