extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Presentation = preload("res://expedition/battle_presentation.gd")
var failures := 0

func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)

func setup():
	var s = Session.new(731,true,false,true,1)
	s.depart()
	var center := Fixture.arena(s)
	s.enemies[0].pos = center+Vector2i.RIGHT
	s.enemies[0].hp = 200; s.enemies[0].max_hp = 200
	s.enemies[0].charging = false; s.enemies[0].recovery = 0
	s.floor_state.observe(s)
	return s

func actor_state(s) -> Array:
	var result: Array = []
	for actor in s.party+s.enemies:
		var row: Dictionary = actor.duplicate(true)
		row.body = actor.body.to_dict()
		row.profile = actor.profile.to_dict()
		row.memory = actor.memory.records.duplicate(true)
		result.append(row)
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var s = setup()
	var control = setup()
	var recorder = Presentation.new()
	recorder.begin(s); s.presentation = recorder
	check(s.auto_step(),"recorded action accepted")
	recorder.finish(s); s.presentation = null
	control.auto_step()
	check(actor_state(s) == actor_state(control) and s.serial == control.serial,"recording does not alter rules, injuries or RNG")
	check(recorder.frames.size() >= 2,"player and enemy resolve as separate frames")
	check(recorder.frames[0].effects[0].from == s.party[0].pos,"player impact precedes enemy")
	check(recorder.frames[0].before.actors[1].hp == 200,"snapshot preserves pre-hit HP")
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = setup()
	root.size = Vector2i(390,844); root.add_child(scene)
	await process_frame
	var expected: Dictionary = scene.session.companion_choice(scene.session.party[0])
	check(scene.board.next_action == expected,"selected preview comes from actual decision selector")
	var before := Presentation.snapshot(scene.session)
	scene.run_action(scene.session.auto_step)
	check(scene.board.is_presenting(),"UI starts presentation")
	check(scene.board.visual_state == before,"wind-up retains pre-action positions and HP")
	var called := [false]
	scene.run_action(func(): called[0] = true; return true)
	check(not called[0],"another action cannot overwrite pending presentation")
	scene.board._advance_playback(0.19)
	check(scene.board.visual_state == scene.board.playback[0].after,"HP changes at impact")
	await process_frame
	var steps := 0
	while scene.board.is_presenting() and steps < 30:
		scene.board._advance_playback(1.0); steps += 1
	check(not scene.board.is_presenting(),"queue drains and returns control")
	await process_frame
	check(scene.board.next_action == scene.session.companion_choice(scene.session.party[scene.session.selected]),"preview recomputes after playback")
	scene.queue_free(); await process_frame
	print("Battle presentation: %d failures" % failures)
	quit(1 if failures else 0)
