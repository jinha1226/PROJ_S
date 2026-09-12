extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Relations=preload("res://playtest/npc_relationship_panel.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func shot(path:String)->void:
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func run()->void:
	root.size=Vector2i(390,844)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human");ui._refresh()
	var before:Dictionary=session.sim.snapshot()
	ui._open_hero_detail_tab("STATUS")
	check(ui.member_status_window.find_child("StatusCombatGrid",true,false).get_child_count()==4,"four combat cards")
	check(ui.member_status_window.find_child("StatusAttributes",true,false).get_child_count()==3,"three core attributes")
	check(ui.member_status_window.find_child("StatusBodyState",true,false).text.contains("피부 질김"),"body values preserved")
	await shot("/tmp/character-status.png")
	check(ui.member_detail_scroll.size.y>ui.size.y*0.60,"status uses most of screen for scrolling")
	ui._open_hero_detail_tab("ITEM")
	check(ui.member_item_equipment_grid.get_child_count()==6,"five real slots plus portrait, no fictional head/feet")
	ui._set_item_category("CONSUMABLE")
	for node in ui.member_item_backpack_rows.get_children():
		check(node.item_row().category=="CONSUMABLE","filter excludes non-consumables")
	ui._set_item_category("ALL")
	check(ui.member_item_backpack_rows.get_child_count()==20,"all inventory capacity restored")
	ui._on_item_row_selected("START_HAND_AXE_001","")
	check(ui.member_item_popover.get_parent()==ui.member_detail_modal,"detail floats outside inventory layout")
	check(ui.member_item_popover_compare.text.contains("→"),"before and after values")
	check(ui.member_item_equip_button.visible and not ui.member_item_use_button.visible,"weapon exposes equip not use")
	await shot("/tmp/character-items.png")
	check(before==session.sim.snapshot(),"viewing and filtering cannot mutate world")
	ui._on_item_equip_selected()
	check(session.sim.world.inventory_of(session.sim.world.party_control_actor_id()).equipped.get("MAIN_HAND")=="START_HAND_AXE_001","real equip command")
	var restored=Session.new()
	check(restored.load_session_json(session.save_session_json()).accepted,"equipment replay remains valid")
	ui._open_hero_detail_tab("RELATIONSHIP")
	var relation_fixture:={"entity_id":1,"display_name":"주인공","relation_rows":[
		{"subject_id":2,"subject_name":"아린","trust":42,"gratitude":28,"fear":5,"hostility":0,"grievance":0,"disposition":"FRIENDLY"},
		{"subject_id":3,"subject_name":"브란","trust":3,"gratitude":0,"fear":12,"hostility":5,"grievance":2,"disposition":"WARY"}]}
	ui.member_relationship_window.set_detail(relation_fixture)
	check(ui.member_relationship_window.presentation_snapshot().relationship_count==2,"relationship list count")
	check(ui.member_relationship_window.find_child("RelationshipMetrics",true,false).get_child_count()==5,"five individual metrics")
	ui.member_relationship_window._select(1)
	check(ui.member_relationship_window.find_child("RelationshipSubjectName",true,false).text=="주인공 → 브란","direction and selection truthful")
	await shot("/tmp/character-relations.png")
	check(session.sim.world.world_state_error().is_empty(),"world validates")
	ui.queue_free();await process_frame
	print("CHARACTER VIEWS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
