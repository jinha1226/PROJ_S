extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/party_rescue_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(s.enable_party_rescue().accepted,"enable new rules")
	check(s.commit_field_action(Action.hold(s.sim.world.party_control_actor_id())).accepted,"journalled wait")
	var saved:String=s.save_session_json()
	check(not saved.is_empty(),"save new rules")
	var loaded:Dictionary=s.load_session_json(saved)
	check(loaded.accepted,"replay new rules: "+str(loaded.get("reason","")))
	check(Rules.enabled(s.sim.world),"activation survives load")
	check(s.sim.world.world_state_error().is_empty(),"restored audit")
	print("PARTY RESCUE REPLAY: ","PASS" if failures.is_empty() else "FAIL",failures)
	quit(0 if failures.is_empty() else 1)
