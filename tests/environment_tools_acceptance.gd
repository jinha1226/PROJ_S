extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(390,800)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	var hero:int=session.sim.world.party_control_actor_id()
	var pos:Vector2i=session.sim.world.entities[hero].position+Vector2i.RIGHT
	for menu_id in [20,21,23,20,22]:
		var before:int=session.sim.world.world_time
		ui._on_product_menu_id(menu_id)
		check(not ui._battle_target_mode.is_empty(),"menu selects test spell %d"%menu_id)
		ui._on_cell(pos);ui._refresh()
		check(session.sim.world.world_time==before+120,"one cast advances 120: %d"%menu_id)
		check(ui._battle_target_mode.is_empty(),"cast completes: %d"%menu_id)
		check(session.sim.world.world_state_error().is_empty(),"valid world: "+session.sim.world.world_state_error())
		for i in range(2):await process_frame
	var event_types:Array=[]
	for event in session.sim.world.events:event_types.append(str(event.type))
	for expected in ["environment.water_applied","environment.cold_applied","environment.water_frozen","environment.ice_melted","environment.electric_arc"]:
		check(expected in event_types,"reaction occurred: "+expected)
	var loaded=Session.new();var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.accepted,"test tools replay: "+str(restored.get("reason","")))
	if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"test tools replay exactly")
	ui.queue_free();await process_frame
	print("ENVIRONMENT TOOLS: ",failures)
	quit(0 if failures.is_empty() else 1)
