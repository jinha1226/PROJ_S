extends SceneTree
## Wall-clock probe for the product loop: session construction, one sandbox
## refresh, and hero steps through the real sandbox input path. Prints a
## Perf report; exit code 1 only when the world state validation fails.
## Run: godot --headless --path . --script res://tests/product_step_performance_probe.gd
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Perf=preload("res://sim/perf_probe.gd")
const STEP_COUNT:=12
func _init()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(390,844)
	var started:=Time.get_ticks_usec()
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var session_us:=Time.get_ticks_usec()-started
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	Perf.reset();Perf.enabled=true
	started=Time.get_ticks_usec()
	ui._request_refresh();await process_frame;await process_frame
	var refresh_us:=Time.get_ticks_usec()-started
	var command_us:=0;var frame_us:=0;var accepted:=0
	var directions:=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
	for i in range(STEP_COUNT):
		var before:Vector2i=world.entities[hero].position
		var direction:Vector2i=directions[(i/2)%directions.size()]
		started=Time.get_ticks_usec()
		ui._on_explore(direction)
		command_us+=Time.get_ticks_usec()-started
		if world.entities[hero].position!=before:accepted+=1
		started=Time.get_ticks_usec()
		await process_frame;await process_frame
		frame_us+=Time.get_ticks_usec()-started
	Perf.enabled=false
	var error:String=world.world_state_error()
	print("PRODUCT_STEP session_us=",session_us," first_refresh_us=",refresh_us," steps=",STEP_COUNT,
		" accepted=",accepted," command_mean_us=",command_us/STEP_COUNT," frames_mean_us=",frame_us/STEP_COUNT," error=",error)
	print(Perf.report())
	ui.queue_free();await process_frame
	quit(1 if not error.is_empty() else 0)
