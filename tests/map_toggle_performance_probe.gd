extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Perf=preload("res://sim/perf_probe.gd")
func _init():call_deferred("run")
func run():
	root.size=Vector2i(390,800)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	session.start_new_run_with_species("human",true,true)
	session.town_life_command({"action":"START"});session.depart_town()
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	for phase in ["before","after"]:
		if phase=="after":
			for i in range(5):ui._toggle_map_overlay();ui._toggle_map_overlay()
		Perf.reset();Perf.enabled=true
		var started:=Time.get_ticks_usec()
		for i in range(6):
			ui._on_explore(Vector2i.ZERO);await process_frame
		Perf.enabled=false
		print("MAP ",phase," six_wait_us=",Time.get_ticks_usec()-started," rebuilds=",ui.minimap.full_rebuild_count)
		print(Perf.report())
	print("VALID ",session.sim.world.world_state_error())
	ui.queue_free();await process_frame;quit()
