extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
func _init():run.call_deferred()
func capture(path:String):
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run():
	root.size=Vector2i(390,844);root.content_scale_size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_procedural_run_with_species("human",15,13)
	var id:int=s.sim.world.party_control_actor_id()
	var inventory=s.sim.world.inventory_of(id)
	var items:Array=inventory.backpack.duplicate()
	items.append(preload("res://sim/item_instance.gd").new("PREVIEW_FIRE_PART","ESSENCE_FIRE_BOLT",1))
	s.sim.world.item_state.inventory_rows[id]=preload("res://sim/inventory_state.gd").new(items,inventory.equipped)
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	for i in range(5):await process_frame
	ui._open_hero_detail_tab("ITEM")
	ui._on_item_row_selected("PREVIEW_FIRE_PART","")
	await capture("/tmp/monster-part-unknown.png")
	ui._on_item_use_selected({},"PREVIEW_FIRE_PART",id)
	await capture("/tmp/monster-part-learned.png")
	quit()
