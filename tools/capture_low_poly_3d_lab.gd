extends SceneTree

const LabScene=preload("res://playtest/low_poly_3d_lab.tscn")

func _init()->void:
	call_deferred("_capture")

func _capture()->void:
	DisplayServer.window_set_size(Vector2i(450,800))
	var lab=LabScene.instantiate();root.add_child(lab)
	await process_frame
	await process_frame
	lab.set_view_mode(lab.VIEW_PITCHED)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/low_poly_3d_pitched.png")
	lab.toggle_painted_skin()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/low_poly_3d_flat_comparison.png")
	lab.toggle_painted_skin()
	lab.set_view_mode(lab.VIEW_TOPDOWN)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/low_poly_3d_topdown.png")
	quit()
