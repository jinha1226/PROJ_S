extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Perf=preload("res://sim/perf_probe.gd")
func _init():call_deferred("run")
func run():
	root.size=Vector2i(390,800)
	for wet in [false,true]:
		var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
		var hero:int=session.sim.world.party_control_actor_id()
		var start:Vector2i=session.sim.world.entities[hero].position
		if wet:
			for y in range(start.y-4,start.y+5):
				for x in range(start.x-4,start.x+5):
					var pos=Vector2i(x,y)
					if session.sim.world.in_bounds(pos):session.sim.world.bootstrap_set_surface(pos,"WATER",500)
		var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
		for i in range(4):await process_frame
		Perf.reset();Perf.enabled=true
		var begun:=Time.get_ticks_usec()
		for i in range(6):
			var command_start:=Perf.begin()
			ui._on_explore(Vector2i.RIGHT if i%2==0 else Vector2i.LEFT)
			Perf.end("probe.command",command_start)
			var frame_start:=Perf.begin()
			await process_frame
			Perf.end("probe.frame_wait",frame_start)
		var elapsed:=Time.get_ticks_usec()-begun
		Perf.enabled=false
		print("WATERSIDE wet=",wet," time_us=",elapsed," world_time=",session.sim.world.world_time," error=",session.sim.world.world_state_error())
		print(Perf.report())
		ui.queue_free();await process_frame
	quit()
