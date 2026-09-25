extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
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
	var s = Session.new_run(7714)
	s.party.append(s.make_actor(1,"브란",false))
	s.formation = [0,1]
	s.companions = true
	var center: Vector2i = Fixture.arena(s,8)
	s.party[1].pos = center+Vector2i.RIGHT
	s.floor_state.observe(s)
	check(s.can_submit(s.party[0],"SWAP",s.party[1].pos),"adjacent companion can exchange positions")
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = s
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var hp: Label = scene.find_child("HeroHP",true,false)
	var state: Label = scene.find_child("HeroState",true,false)
	check(hp != null and hp.text.contains("HP") and hp.text.contains("MP"),"portrait shows HP and MP on one line")
	check(state != null and state.text.contains("스트레스"),"portrait reserves a separate state line")
	check(hp.get_global_rect().end.y <= state.get_global_rect().position.y,"state line sits below HP and MP")
	s.party[0].statuses["burn"] = s.time+100
	scene.refresh()
	await process_frame
	check(scene.find_child("HeroState",true,false).text.contains("화상"),"status effect appears in reserved line")
	var before_time: int = s.time
	scene.on_cell(s.party[1].pos)
	await process_frame
	check(s.party[0].pos == center+Vector2i.RIGHT and s.party[1].pos == center and s.time > before_time,"tapping a blocking companion swaps positions and takes a turn")
	check(not scene.details_popup.visible,"companion tap does not open character details")
	check(scene.get_global_rect().encloses(scene.find_child("PortraitRow",true,false).get_global_rect()),"portrait row fits a short phone")
	scene.queue_free()
	await process_frame
	print("Party swap portraits: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
