extends SceneTree

const LabScene=preload("res://playtest/low_poly_3d_lab.tscn")

func _init()->void:
	call_deferred("_capture")

func _capture()->void:
	DisplayServer.window_set_size(Vector2i(450,800))
	var lab=LabScene.instantiate();root.add_child(lab)
	await process_frame
	await process_frame
	lab.set_view_mode(lab.VIEW_TOPDOWN)
	RenderingServer.force_draw(false,0.0)
	await process_frame
	root.get_texture().get_image().save_png("res://build/topdown_cutout_idle.png")
	lab.pawn.set_walking(true)
	lab.pawn._process(0.12)
	RenderingServer.force_draw(false,0.0)
	await process_frame
	root.get_texture().get_image().save_png("res://build/topdown_cutout_walk.png")
	lab.pawn.set_walking(false)
	lab.pawn.play_attack()
	lab.pawn._process(0.26)
	RenderingServer.force_draw(false,0.0)
	await process_frame
	root.get_texture().get_image().save_png("res://build/topdown_cutout_attack.png")
	quit()
