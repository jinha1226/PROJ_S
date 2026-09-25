extends SceneTree
## Reading an identify scroll from the bag opens the "감정할 것" choice at
## once, not on the next action.
const Session = preload("res://expedition/run/session.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene)
	for f in range(4): await process_frame
	s.grant_item("identify",1,true); s.grant_item("healing",1); s.grant_item("teleportation",1)
	scene.refresh()
	scene.Popups.show_supplies(scene)
	for f in range(3): await process_frame
	var scroll: String = scene.Popups.inventory_rows(scene).map(func(r): return str(r.id)).filter(func(i): return i.contains("identify"))[0]
	scene.Popups.show_item_detail(scene,scroll)
	for f in range(2): await process_frame
	var read: Array = scene.item_detail.find_children("*","Button",true,false).filter(func(b): return b.text == "읽는다")
	check(read.size() == 1,"the scroll offers 읽는다")
	read[0].pressed.emit()
	check(not s.pending_choice.is_empty(),"reading leaves a choice pending")
	for f in range(3): await process_frame
	check(scene.details_popup.visible,"the choice is on screen right after reading")
	var labels: Array = scene.modal_content.find_children("*","Label",true,false).map(func(l): return l.text)
	check("감정할 것" in labels,"and it is the identify choice")
	var picks: Array = scene.modal_content.find_children("*","Button",true,false)
	check(picks.size() == 2,"one button per unknown item")
	picks[0].pressed.emit()
	for f in range(3): await process_frame
	check(s.pending_choice.is_empty() and not scene.details_popup.visible,"picking closes it")
	print("Identify UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
