extends "res://tests/stage_context_ui_acceptance.gd"
func run():
	root.size=Vector2i(360,800);root.content_scale_size=Vector2i(360,800)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"species");check(s.town_life_command({"action":"START"}).accepted,"town");check(s.depart_town().accepted,"depart")
	var ui=Sandbox.new();ui.size=Vector2(360,800);ui.initialize_for_headless_test(s,true);test_ui=ui
	root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	check(ui.stage_context_bar.map_button.is_visible_in_tree(),"map button in exploration")
	check(ui.stage_context_bar.map_button.size.y>=44,"44px map button")
	await tap(ui.stage_context_bar.map_button)
	check(ui.stage_map_view.visible,"map overlay opens")
	var node_button=ui.stage_map_view.node_button(5)
	check(node_button!=null and not node_button.disabled,"east room selectable")
	check(ui.stage_map_view.node_button(1)==null,"undiscovered room not drawn")
	await tap(node_button)
	check(not ui.stage_map_view.visible,"overlay closes after travel")
	check(int(s.sim.world.party_encounter.nine_room_floor.active_room_id)==5,"travelled east by tap")
	await tap(ui.stage_context_bar.map_button)
	await tap(ui.stage_map_view.node_button(4));await tap(ui.stage_context_bar.map_button);await tap(ui.stage_map_view.node_button(7))
	check(s.round_status().phase=="DEPLOYMENT","combat room deployment via map")
	check(not ui.stage_context_bar.map_button.is_visible_in_tree(),"map button hidden during combat")
	# Tapping the old doorway cell must no longer trigger a room exit outside combat.
	ui._on_cell(Vector2i(11,15))
	check(int(s.sim.world.party_encounter.nine_room_floor.active_room_id)==7,"doorway tap does not travel")
	print("STAGE_MAP_UI ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
