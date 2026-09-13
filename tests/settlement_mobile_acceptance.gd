extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Rules=preload("res://sim/settlement_work_rules.gd")
var failures:Array=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human")
	ui._refresh()
	for i in range(6):await process_frame
	for viewport in [Vector2i(360,640),Vector2i(390,844)]:
		root.size=viewport
		ui._on_town_facility_selected("HOUSE");ui._refresh()
		for i in range(8):await process_frame
		var panel=ui.find_child("TownBaseProgress",true,false)
		check(panel!=null,"real shell contains settlement panel")
		if panel==null:quit(1);return
		var map=panel.find_child("BaseSettlementMap",true,false)
		var identity:int=map.get_instance_id()
		var tab=panel.find_child("BaseSectionTab1",true,false)
		tab.pressed.emit()
		for i in range(4):await process_frame
		check(panel.section_tab==1,"gather tab opens without reconstructing map")
		check(map.get_instance_id()==identity,"tab preserves map")
		var toggle=panel.find_child("BaseGatherTIMBER",true,false)
		toggle.set_pressed_no_signal(true);toggle.toggled.emit(true)
		check(bool(Rules.state(s.sim.world).get("gathering",{}).get("TIMBER",false)),"real UI enables gathering policy")
		var logical_width:float=ui.get_viewport_rect().size.x
		check(panel.get_global_rect().end.x<=logical_width,"panel fits stretched viewport")
		check(tab.size.y*float(viewport.x)/logical_width>=48,"tab touch target after mobile scaling")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/settlement-mobile-%d.png"%viewport.x)
		panel.select_section(3)
		for i in range(4):await process_frame
		var scroll=panel.find_child("BaseSectionScroll3",true,false)
		scroll.scroll_vertical=200
		for i in range(4):await process_frame
		check(scroll.scroll_vertical>0,"resident details scroll independently")
		check(map.get_instance_id()==identity,"scroll preserves map")
	ui.queue_free();await process_frame
	print("SETTLEMENT_MOBILE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
