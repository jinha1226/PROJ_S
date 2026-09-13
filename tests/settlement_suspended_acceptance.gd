extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START","frontier":true}).accepted,"legacy frontier start")
	var ui=Sandbox.new();ui.size=Vector2(390,844);ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false)
	for n in range(3):await process_frame
	check(ui.find_child("TownBaseProgress",true,false)==null,"legacy shelter no construction panel")
	check(ui.find_child("TownNavHOUSE",true,false)==null,"no settlement navigation")
	check(ui.product_menu_button.get_popup().get_item_index(7)==-1,"no base menu")
	ui._open_base_modal();check(not ui.base_modal.visible,"base modal blocked")
	var before:int=s.sim.world.events.size();ui.base_work_clock.tick(ui,2.0)
	check(s.sim.world.events.size()==before,"no background settlement work")
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human")
	check(s.sim.world.party_encounter.expedition_cycle.phase=="DUNGEON","default new run starts in dungeon")
	check(not preload("res://playtest/frontier_campaign.gd").enabled(s),"new run has no frontier campaign")
	ui.queue_free();await process_frame
	print("SETTLEMENT SUSPENDED ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
