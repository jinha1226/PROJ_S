extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	root.size=Vector2i(390,844)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human");ui._refresh()
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	# Canonical test-only grant; production starts are unchanged.
	var grant:Dictionary=preload("res://sim/world_item_operations.gd").commit_grant(world,hero,"TORCH",1,world.entities[hero].position,"HUD_TEST")
	check(grant.get("accepted",false),"test torch grant")
	var count:=0;var torch_id:=""
	for item in world.inventory_of(hero).backpack:
		if item.definition_id=="TORCH":count+=int(item.quantity);torch_id=str(item.instance_id)
	var before:Dictionary=session.sim.snapshot()
	var spec:Dictionary=ui.expedition_hud_spec()
	check(spec.torch_count==count,"inventory count")
	check(spec.torch_band=="NONE","unequipped state")
	check(before==session.sim.snapshot(),"HUD read-only")
	check(not torch_id.is_empty(),"starting torch available")
	if not torch_id.is_empty():
		check(session.equip_inventory_item(torch_id,"OFF_HAND").accepted,"equip torch")
		check(ui.expedition_hud_spec().torch_count==count,"equipped torch counted once")
		check(session.ignite_torch(torch_id).accepted,"ignite")
		ui._refresh();spec=ui.expedition_hud_spec()
		check(spec.torch_band in ["LIT","WARNING"],"lit state")
		check(ui.torch_meter.value==spec.torch_remaining,"fuel gauge authoritative")
		check(ui.food_meter.value==spec.ration,"food gauge authoritative")
		check(ui.torch_timer_label.text.contains("×%d"%count),"owned count visible")
	for i in range(8):await process_frame
	check(ui.phase_panel.get_global_rect().end.x<=ui.size.x,"HUD fits viewport")
	check(ui.product_menu_button.get_global_rect().end.x<=ui.size.x,"menu fits viewport")
	check(ui.grid.get_global_rect().position.y>=ui.phase_panel.get_global_rect().end.y,"HUD does not overlay game")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/main-hud-runtime.png")
	check(world.world_state_error().is_empty(),"valid world")
	ui.queue_free();await process_frame
	print("MAIN HUD: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
