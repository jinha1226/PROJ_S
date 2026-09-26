extends SceneTree
const Camp = preload("res://expedition/ui/screens/camp_screen.gd")
const Session = preload("res://expedition/run/session.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)

func run() -> void:
	root.size = Vector2i(320,568)
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = Session.new_run(7712)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	scene.show_supplies()
	for frame in range(3): await process_frame
	var slots: Node = scene.find_child("EquippedSlots",true,false)
	check(slots != null and slots.get_child_count() == 5,"bag has five equipped slots")
	for id in ["weapon","offhand","armour","ring1","ring2"]:
		check(scene.find_child("Equipped_"+id,true,false) != null,id+" is visible")
	var weapon: Button = scene.find_child("Equipped_weapon",true,false)
	check(weapon.find_children("*","TextureRect",true,false).size() == 1,"equipped weapon has an icon")
	check(weapon.get_global_rect().size.x > 40,"equipped slots remain readable on a narrow screen")
	check(scene.get_global_rect().encloses(Rect2(scene.details_popup.position,scene.details_popup.size)),"bag fits a short phone")
	check(Rect2(Vector2.ZERO,scene.details_popup.size).encloses(scene.find_child("InventorySelection",true,false).get_global_rect()),"item details remain inside the bag")
	scene.inventory_filter = "파츠"
	scene.show_supplies()
	for frame in range(3): await process_frame
	var popup_bounds := Rect2(Vector2.ZERO,scene.details_popup.size)
	check(Rect2(Vector2.ZERO,scene.get_viewport_rect().size).encloses(Rect2(scene.details_popup.position,scene.details_popup.size)),"parts tab popup stays within the viewport")
	for id in ["ManualInventory","InventoryTabs","InventorySelection","EquippedSlots"]:
		var control: Control = scene.find_child(id,true,false)
		check(popup_bounds.encloses(control.get_global_rect()),"parts "+id+" fits the popup")
	scene.inventory_filter = "전체"
	scene.show_supplies()
	await process_frame
	weapon = scene.find_child("Equipped_weapon",true,false)
	weapon.pressed.emit()
	await process_frame
	check(scene.item_popup.visible,"tapping an equipped item opens its detail")
	scene.item_popup.hide()
	var ring: Button = scene.find_child("Equipped_ring1",true,false)
	ring.pressed.emit()
	await process_frame
	check(scene.inventory_filter == "장비" and scene.find_child("EquippedSlots",true,false) != null,"empty slot opens equipment in the bag")
	scene.details_popup.hide()
	scene.session.party.append(scene.session.make_actor(1,"브란",false))
	scene.session.party[1].gear.weapon = {"type":"axe","enchant":0}
	scene.show_supplies()
	await process_frame
	var member: Button = scene.find_child("EquippedMember1",true,false)
	check(member != null,"companions get an equipment selector")
	member.pressed.emit()
	await process_frame
	check(scene.inventory_actor == 1 and scene.find_child("Equipped_weapon",true,false).tooltip_text.begins_with("브란"),"selector shows companion gear")
	check(scene.get_global_rect().encloses(Rect2(scene.details_popup.position,scene.details_popup.size)),"companion gear still fits a short phone")
	scene.details_popup.hide()
	scene.session.manual_mode = false
	scene.show_supplies()
	await process_frame
	check(scene.find_child("EquippedSlots",true,false) != null,"automatic mode also shows equipped gear")
	check(scene.get_global_rect().encloses(Rect2(scene.details_popup.position,scene.details_popup.size)),"automatic bag fits a short phone")

	# New item names, five occupied slots and a three-person party still fit a phone.
	scene.session.party.append(scene.session.make_actor(2,"긴이름의세번째동료",false))
	var item := {"type":"power","tier":"randart","name":"깨어난 공허의 오랜 서약을 새긴 반지","props":[{"key":"hp","value":15},{"key":"res_fire","value":40}],"affix":"GEAR_AMP_12","uid":8123}
	scene.session.gear_bag.append(item)
	root.size = Vector2i(360,640); scene.inventory_filter = "장비"; scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.details_popup.size.x <= root.size.x and scene.details_popup.size.y <= root.size.y,"long randart names and three companions keep the bag within the phone")
	var item_row: Dictionary = scene.inventory_rows().filter(func(r): return r.get("item",{}).get("uid",0) == 8123)[0]
	scene.show_item_detail(str(item_row.id))
	for frame in range(3): await process_frame
	check(scene.item_popup.size.x <= root.size.x and scene.item_popup.size.y <= root.size.y,"long randart detail wraps without stretching the phone")
	var choices: Array = scene.item_detail.find_children("*","Button",true,false).filter(func(b): return b.text.contains("반지") and b.text.contains("장착"))
	check(choices.size() == 6,"three members each have explicit choices for both rings")
	scene.item_popup.hide(); scene.details_popup.hide(); scene.session.phase = "CAMP"
	Camp.show_gear(scene,0)
	for frame in range(3): await process_frame
	check(scene.details_popup.size.x <= root.size.x and scene.details_popup.size.y <= root.size.y,"camp equipment list scrolls within a short phone")
	scene.queue_free()
	await process_frame
	print("Equipped inventory: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
