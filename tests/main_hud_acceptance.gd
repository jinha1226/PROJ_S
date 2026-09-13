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
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human",false);ui._refresh()
	var pixel_font=preload("res://assets/fonts/Galmuri14.ttf")
	check(ui.ration_label.get_theme_font("font")==pixel_font,"HUD pixel font")
	check(ui.product_menu_button.get_theme_font("font")==pixel_font,"button pixel font")
	check(pixel_font.antialiasing==TextServer.FONT_ANTIALIASING_NONE,"crisp pixel font import")
	for character in "상태관계숙련이능식량횃불0123HP":
		check(pixel_font.has_char(character.unicode_at(0)),"font glyph "+character)
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	for item in world.inventory_of(hero).backpack:
		check(item.definition_id!="TORCH","no starting torch")
	for row in session.town_market_stock():check(row.definition_id!="TORCH","no torch sales")
	var before:Dictionary=session.sim.snapshot()
	var spec:Dictionary=ui.expedition_hud_spec()
	check(not spec.has("torch_count"),"torch HUD projection removed")
	check(before==session.sim.snapshot(),"HUD read-only")
	check(ui.find_child("TorchHUD",true,false)==null,"no torch HUD node")
	check(ui.find_child("TorchTimer",true,false)==null,"no torch timer node")
	check(not session.ignite_torch("OLD_TORCH").accepted,"ignition retired")
	check(not session.extinguish_torch("OLD_TORCH").accepted,"extinguishing retired")
	check(preload("res://sim/torch_rules.gd").active_light_sources(world).is_empty(),"no carried lights")
	check(not preload("res://sim/world_item_operations.gd").commit_grant(world,hero,"TORCH",1,world.entities[hero].position,"RETIRED_TEST").accepted,"torch creation retired")
	check(before==session.sim.snapshot(),"retired actions do not consume time or mutate world")
	check(ui.food_meter.value==spec.ration,"food gauge authoritative")
	for i in range(8):await process_frame
	check(ui.ration_label.size.x>=30,"supply text has visible width")
	ui.food_icon.configure(0.0);check(ui.food_icon.level==0,"empty food silhouette")
	ui.food_icon.configure(1.0);check(ui.food_icon.level==4,"full food silhouette")

	ui._refresh()
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
