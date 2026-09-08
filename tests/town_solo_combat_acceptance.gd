extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.town_life_command({"action":"START"}).get("accepted",false),"start inn")
	check(session.depart_town().get("accepted",false),"depart solo")
	var world=session.sim.world;var party=world.party_encounter;var leader:int=world.party_control_actor_id()
	var best:Dictionary={}
	for id in session._current_floor_enemy_ids():
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var path:Dictionary=session.find_exploration_path(leader,world.entities[id].position+direction)
			if path.get("found",false) and (best.is_empty() or path.path.size()<best.path.size()):best=path
	check(not best.is_empty(),"reachable entry encounter")
	if best.is_empty():quit(1);return
	for p in best.path.slice(1):
		var moved:Dictionary=session.commit_exploration(Command.move_to(leader,p))
		check(moved.get("accepted",false),"approach encounter: "+str(moved.get("reason")))
		if not moved.get("accepted",false) or party.safe_phase=="CONTACT":break
	check(party.safe_phase=="CONTACT","solo encounter begins")
	var preview:Dictionary=session.preview_deployment("LINE",[])
	check(preview.get("accepted",false),"solo formation accepts no companions")
	if not preview.get("accepted",false):print(preview);quit(1);return
	check(session.commit_deployment().get("accepted",false),"enter individual action combat")
	for step in range(100):
		if party.safe_phase in ["GROUPED","GROUPED_COMPLETE","PARTY_DEFEATED"]:break
		var result:Dictionary=session.individual_battle.commit()
		check(result.get("accepted",false),"individual action: "+str(result.get("reason")))
		if not result.get("accepted",false):break
	check(party.safe_phase in ["GROUPED","GROUPED_COMPLETE"],"solo clears opening encounter")
	check(world.combatant_states[leader].life_state=="ACTIVE","solo survives")
	var loaded=Session.new()
	check(loaded.load_session_json(session.save_session_json()).get("accepted",false),"solo battle and population save replays")
	print("SOLO_RESULT HP=",world.entities[leader].health," phase=",party.safe_phase)
	print("TOWN_SOLO_COMBAT_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
