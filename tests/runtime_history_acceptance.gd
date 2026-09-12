extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Event=preload("res://sim/sim_event.gd")
const Index=preload("res://sim/runtime_history_index.gd")
const Survival=preload("res://sim/party_survival_rules.gd")
const Formation=preload("res://sim/field_turn_rules.gd")
const Fixtures=preload("res://tests/test_party_auto_explore.gd")
const Perf=preload("res://sim/perf_probe.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var world=session.sim.world
	var snapshot:Dictionary=session.sim.snapshot()
	Index.sync(world)
	check(session.sim.snapshot()==snapshot,"derived cache does not change save authority")
	var original_count:int=world.events.size()
	var hero:int=world.party_control_actor_id()
	world.events.append(Event.new(100000,0,0,"party.field_formation_selected",hero,-1,Vector2i.ZERO,0,-1,-1,{"formation":"LINE"}))
	check(Formation.formation(world)=="LINE","append updates formation")
	world.events[-1]=Event.new(100000,0,0,"party.field_formation_selected",hero,-1,Vector2i.ZERO,0,-1,-1,{"formation":"WEDGE"})
	check(Formation.formation(world)=="WEDGE","same-length tail replacement invalidates cache")
	world.events.resize(original_count)
	check(Formation.formation(world)=="NONE","truncation invalidates cache")
	check(Survival.control_id(world)==hero,"no explicit selection falls back to current hero")
	check(session._party_observation_context(false).ground_items_by_cell.is_empty(),"AUTO context skips item decoration")
	# Real canonical AUTO hops, not padded history. Enemies are frozen/hidden by
	# the existing safe fixture; stop normally on actual threats/terminal state.
	var fixture=Fixtures.new()
	session=fixture._safe_product_session(77)
	var times:Array[int]=[]
	Perf.reset();Perf.enabled=true
	var result:Dictionary={}
	for i in range(256):
		var start:=Time.get_ticks_usec()
		result=session.start_auto_explore() if i==0 else session.continue_auto_explore()
		session.observe_party_ui(15,true,19,i%4==0)
		times.append(Time.get_ticks_usec()-start)
		if not result.get("running",false):break
	Perf.enabled=false
	check(int(result.get("steps_committed",0))>=32,"AUTO advances at least 32 canonical hops")
	check(session.sim.world.world_state_error().is_empty(),"AUTO history validates")
	print("AUTO SOAK hops=",result.get("steps_committed",0)," stop=",result.get("stop_reason",""),
		" events=",session.sim.world.events.size()," first16_mean_us=",mean(times.slice(0,16)),
		" last16_mean_us=",mean(times.slice(maxi(0,times.size()-16))))
	print(Perf.report())
	# Also exercise the actual town -> dungeon, unified field-turn entry path.
	session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(session.town_life_command({"action":"START"}).accepted,"campaign town starts")
	check(session.depart_town().accepted,"campaign departure")
	check(session.field_turns_active(),"campaign uses unified field turns")
	times.clear()
	for i in range(256):
		var start:=Time.get_ticks_usec()
		result=session.start_auto_explore() if i==0 else session.continue_auto_explore()
		session.observe_party_ui(15,true,19,i%4==0)
		times.append(Time.get_ticks_usec()-start)
		if not result.get("running",false):break
	check(int(result.get("steps_committed",0))>0,"campaign AUTO advances")
	check(session.sim.world.world_state_error().is_empty(),"campaign AUTO history validates")
	print("CAMPAIGN AUTO hops=",result.get("steps_committed",0)," stop=",result.get("stop_reason",""),
		" events=",session.sim.world.events.size()," first16_mean_us=",mean(times.slice(0,16)),
		" last16_mean_us=",mean(times.slice(maxi(0,times.size()-16))))
	var restored=Session.new()
	check(restored.load_session_json(session.save_session_json()).accepted,"campaign AUTO save replays")
	check(restored.sim.snapshot()==session.sim.snapshot(),"campaign AUTO replay exact")
	var command_tests=load("res://tests/test_party_exception_commands.gd")
	for method in command_tests.get_script_method_list():
		if not str(method.name).begins_with("test_"):continue
		var test=command_tests.new()
		check(test.call(method.name)==true,"command regression: "+str(method.name)+" "+str(test.errors))
	print("RUNTIME HISTORY: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
func mean(values:Array)->int:
	var total:=0
	for value in values:total+=int(value)
	return total/maxi(1,values.size())
