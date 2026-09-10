extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	for width in [360,450]:
		root.content_scale_size=Vector2i(width,800)
		root.size=Vector2i(width,800)
		for i in range(3):await process_frame
		ui._refresh()
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/living-world-dark-ui-%d.png"%width)
	ui._on_product_tactics()
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/living-world-dark-ui-tactics.png")
	ui.product_tactics_popup.hide()
	session.town_life_command({"action":"START"});ui._refresh()
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/living-world-dark-ui-town.png")
	ui.queue_free();await process_frame
	quit()
