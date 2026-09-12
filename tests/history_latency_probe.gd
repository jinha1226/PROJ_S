extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Event=preload("res://sim/sim_event.gd")
const Perf=preload("res://sim/perf_probe.gd")
func _init()->void:run.call_deferred()
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	# Synthetic history isolates read-side scaling; this is NOT a valid save or
	# a mobile FPS benchmark. Never execute commands against the padded world.
	for size in [0,10000,50000]:
		while session.sim.world.events.size()<size:
			var n:int=session.sim.world.events.size()
			session.sim.world.events.append(Event.new(n+100000,0,0,"probe.noop"))
		session._party_observation_context()
		session._auto_explore_fog_snapshot()
		Perf.reset();Perf.enabled=true
		var start:=Time.get_ticks_usec()
		for i in range(10):
			session._party_observation_context()
			session._auto_explore_fog_snapshot()
		print("HISTORY events=",session.sim.world.events.size()," pair_mean_us=",(Time.get_ticks_usec()-start)/10)
		print(Perf.report());Perf.enabled=false
	quit()
