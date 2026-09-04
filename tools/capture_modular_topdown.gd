extends SceneTree

const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const Session = preload("res://playtest/party_playtest_session.gd")

func _init()->void:
	call_deferred("_capture")

func _capture()->void:
	root.size=Vector2i(450,800)
	var sandbox=Sandbox.new()
	sandbox.size=Vector2(450,800)
	sandbox.initialize_for_headless_test(Session.new(44,20260904,
		Session.SOLO_COMBAT_SCENARIO_ID),false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sandbox.size=Vector2(450,800)
	root.add_child(sandbox)
	await process_frame
	await process_frame
	await process_frame
	var image:=root.get_texture().get_image()
	var error:=image.save_png("res://assets/generated/modular_topdown_v1/product_portrait_preview.png")
	if error!=OK:
		printerr("capture failed: ",error)
		quit(1)
		return
	print("CAPTURED modular_topdown_v1/product_portrait_preview.png")
	quit(0)
