extends SceneTree
const Scene = preload("res://expedition/ui/main.tscn")
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func frames() -> void:
	await process_frame; await process_frame; await process_frame

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var ui = Scene.instantiate()
	var s = Session.new(85)
	var actor: Dictionary = s.party[0]
	actor.combat_profile = "attack_wait_v1"
	actor.level = 6; Essences.sync_slots(actor)
	var red: Array = Essences.catalog().filter(func(id): return Essences.colour(str(id)) == "red")
	var green: Array = Essences.catalog().filter(func(id): return Essences.colour(str(id)) == "green")
	Essences.bind(actor,str(red[0]))
	s.parts_bag = {str(red[1]):1,str(green[0]):1}
	s.phase = "REST"; s.depth = 3; s.stone_bag_limit = 3
	ui.session = s; root.size = Vector2i(390,844); root.add_child(ui); ui.set_process(false)
	await frames()
	check(ui.find_child("RestScreen",true,false) != null,"rest screen is routed")
	check(ui.find_child("RestSlot0",true,false) != null and ui.find_child("RestBag",true,false) != null,"slots and bag appear")
	check(ui.find_child("RestCodex",true,false) != null and ui.find_child("RestLeave",true,false) != null,"codex and next zone controls appear")
	for dimensions in [Vector2i(320,568),Vector2i(390,844),Vector2i(430,932)]:
		root.size = dimensions; ui.size = Vector2(dimensions); ui.refresh(); await frames()
		var slots: Control = ui.find_child("RestSlots",true,false)
		check(slots.get_global_rect().end.x <= dimensions.x+1 and ui.find_child("RestLeave",true,false).get_global_rect().end.y <= dimensions.y+1,"rest controls fit mobile "+str(dimensions))
	var bag_name: String = "RestBag_"+str(red[1]).replace("/","_").replace("@","_")
	ui.find_child(bag_name,true,false).pressed.emit(); await frames()
	ui.find_child("RestSlot0",true,false).pressed.emit(); await frames()
	check(actor.equipped_abilities[0] == red[1] and int(s.parts_bag.get(red[0],0)) == 1,"same colour swap works through rest screen")
	bag_name = "RestBag_"+str(green[0]).replace("/","_").replace("@","_")
	ui.find_child(bag_name,true,false).pressed.emit(); await frames()
	ui.find_child("RestSlot0",true,false).pressed.emit(); await frames()
	check(ui.details_popup.visible and ui.modal_content.find_children("*","Label",true,false).any(func(line): return line.text.contains("소멸")),"other colour requests destruction confirmation")
	ui.details_popup.hide(); ui.queue_free(); await frames()
	print("Rest UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
