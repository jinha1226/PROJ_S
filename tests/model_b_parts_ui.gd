extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var s = Session.new_run(7712)
	var center: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities = ["PUSH",""]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = center+Vector2i(1,0)
	foe.alert = true; foe.ready_at = 1000
	s.phase = "BATTLE"
	s.floor_state.observe(s)
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = s
	root.size = Vector2i(390,915)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var entry: Button = scene.find_child("Tactics",true,false)
	check(entry != null and not entry.disabled,"manual combat shows tactics entry")
	if entry != null: entry.pressed.emit()
	await process_frame
	var menu: Node = scene.find_child("ManualTactics",true,false)
	check(menu != null,"tactics menu opens")
	var push_button: Button = null
	if menu != null:
		for candidate in menu.find_children("*","Button",true,false):
			if candidate.text == "밀치기": push_button = candidate
	check(push_button != null and not push_button.disabled,"equipped PUSH is available")
	if push_button != null: push_button.pressed.emit()
	await process_frame
	check(scene.mode == "PUSH","part action waits for a target")
	var before_time: int = s.time
	scene.on_cell(foe.pos)
	await process_frame
	check(s.time > before_time and scene.mode.is_empty(),"targeted part consumes time and clears targeting")
	scene.queue_free()
	await process_frame
	print("Model B parts UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
