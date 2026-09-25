extends SceneTree
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
	check(slots != null and slots.get_child_count() == 4,"bag has four equipped slots")
	for id in ["weapon","armour","shield","ring"]:
		check(scene.find_child("Equipped_"+id,true,false) != null,id+" is visible")
	var weapon: Button = scene.find_child("Equipped_weapon",true,false)
	check(weapon.find_children("*","TextureRect",true,false).size() == 1,"equipped weapon has an icon")
	check(weapon.get_global_rect().size.x > 40,"equipped slots remain readable on a narrow screen")
	check(scene.get_global_rect().encloses(Rect2(scene.details_popup.position,scene.details_popup.size)),"bag fits a short phone")
	check(Rect2(Vector2.ZERO,scene.details_popup.size).encloses(scene.find_child("InventorySelection",true,false).get_global_rect()),"item details remain inside the bag")
	weapon.pressed.emit()
	await process_frame
	check(scene.item_popup.visible,"tapping an equipped item opens its detail")
	scene.item_popup.hide()
	var ring: Button = scene.find_child("Equipped_ring",true,false)
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
	scene.queue_free()
	await process_frame
	print("Equipped inventory: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
