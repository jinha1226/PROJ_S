extends SceneTree

func _initialize() -> void:
	call_deferred("exercise")

func exercise() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.run_action(scene.session.depart)
	await process_frame
	scene.run_action(func(): return scene.session.travel(1))
	await process_frame
	scene.on_cell(Vector2i(2,2))
	scene.run_action(scene.session.end_round)
	await process_frame
	scene.run_action(scene.session.retreat)
	await process_frame
	print("UI smoke: town, route, battle, cell input, enemy round, return rendered headlessly")
	scene.queue_free()
	await process_frame
	quit()
