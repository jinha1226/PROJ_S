extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:=0
func check(value:bool,message:String)->void:
	if not value:failures+=1;printerr(message)
func _init()->void:call_deferred("run")
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.sim!=null,"world initialized")
	if session.sim==null:quit(1);return
	var state=session.sim.world.party_encounter
	check(state.party_member_ids.size()==2,"starts with two")
	check(session.sim.world.world_state_error().is_empty(),"valid initial state")
	var hero:int=state.protagonist_id
	var goal:Vector2i=session.sim.world.entities[state.enemy_ids[0]].position
	var best:Dictionary={}
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var path:Dictionary=session.find_exploration_path(hero,goal+direction)
		if path.get("found",false) and (best.is_empty() or path.path.size()<best.path.size()):best=path
	check(not best.is_empty(),"route to first encounter")
	if best.is_empty():quit(1);return
	for cell in best.path.slice(1):
		if session.party_status().safe_phase=="CONTACT":break
		var step:Dictionary=session.commit_exploration(Command.move_to(hero,cell))
		check(step.accepted,"manual exploration advances")
		if not step.accepted:break
	check(session.party_status().safe_phase=="CONTACT","encounter detected")
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true);root.add_child(ui)
	ui.set_process(false)
	for i in range(6):await process_frame
	check(session.party_status().safe_phase=="ENGAGED","automatic deployment")
	check(session.issue_party_command("STOP_ATTACK").accepted,"command accepted")
	var stopped:Dictionary=session.sim.party_coordinator.suggest_protagonist_turn()
	check(stopped.action.type=="HOLD","hero respects stop attack")
	check(session.issue_party_command("FOLLOW").accepted,"resume autonomous combat")
	ui.autonomous_battle_clock.paused=true
	var before:int=session.sim.world.step_index
	ui._tick_autonomous_battle(1.0)
	check(session.sim.world.step_index==before,"pause blocks turns")
	ui.autonomous_battle_clock.paused=false
	for i in range(32):
		if session.party_status().safe_phase!="ENGAGED":break
		ui._tick_autonomous_battle(1.0)
		await process_frame
	check(session.sim.world.step_index>before,"autonomous party advances without taps")
	check(not ui.autonomous_battle_clock.paused,"automatic decisions accepted")
	print("After autonomous battle: ",session.party_status().safe_phase)
	var hero_attacks:int=session.sim.world.events.filter(func(event):return event.type=="action.melee_attack" and event.actor_id==hero).size()
	print("Autonomous hero attacks: ",hero_attacks)
	check(hero_attacks>0,"hero attacks instead of only advancing idle turns")
	if session.party_status().safe_phase in ["GROUPED","GROUPED_COMPLETE"]:
		var end_step:int=session.sim.world.step_index
		ui._tick_autonomous_battle(1.0)
		check(session.sim.world.step_index==end_step,"exploration never auto-advances")
		var route:Dictionary=session.find_exploration_path(hero,session.sim.world.entities[hero].position+Vector2i.LEFT)
		if route.get("found",false) and route.path.size()>1:
			check(session.commit_exploration(Command.move_to(hero,route.path[1])).accepted,"manual movement resumes after victory")
	if session.party_status().safe_phase=="ENGAGED":
		check(session.issue_party_command("STOP_ATTACK").accepted,"command accepted")
		var suggestion:Dictionary=session.sim.party_coordinator.suggest_protagonist_turn()
		check(suggestion.action.type=="HOLD","hero respects stop attack")
	var loaded=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
	print("World after battle/movement: ",session.sim.world.world_state_error())
	var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.accepted,"autobattle journal reloads: "+str(restored.get("reason","")))
	check(loaded.sim.snapshot()==session.sim.snapshot(),"restored state identical")
	ui.queue_free();await process_frame
	print("Duo autobattle: %d failures"%failures);quit(0 if failures==0 else 1)
