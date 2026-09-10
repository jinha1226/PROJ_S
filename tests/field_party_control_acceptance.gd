extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var world=session.sim.world
	var hero:int=world.party_control_actor_id()
	var allies:Array=world.party_encounter.active_party_member_ids.duplicate();allies.erase(hero)
	check(not allies.is_empty(),"fixture has companion")
	if allies.is_empty():quit(1);return
	var ally:int=allies[0]
	var time:int=world.world_time
	check(session.set_exploration_formation("COLUMN").accepted,"set column")
	check(session.FieldRules.formation(world)=="COLUMN","formation persisted in world")
	check(session.select_field_actor(ally).accepted,"select companion")
	check(world.party_control_actor_id()==ally,"companion is input actor")
	check(world.world_time==time,"settings do not advance time")
	check(world.world_state_error().is_empty(),"selection validates: "+world.world_state_error())
	var result:Dictionary=session.commit_field_action(Action.hold(ally))
	check(result.accepted,"companion direct action: "+str(result.get("reason","")))
	check(world.world_state_error().is_empty(),"companion action validates: "+world.world_state_error())
	var moved:=false
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var action=Action.move_to(ally,world.entities[ally].position+direction)
		if not session.FieldTurns.assess(session.sim,action).accepted:continue
		var movement:Dictionary=session.commit_field_action(action)
		check(movement.accepted,"selected ally moves: "+str(movement.get("reason","")))
		moved=movement.accepted;break
	check(moved,"companion has direct movement")
	check(world.world_state_error().is_empty(),"companion move validates: "+world.world_state_error())
	check(session.issue_party_command("STOP_ATTACK").accepted,"selected companion can command remaining party")
	check(preload("res://sim/party_exception_command.gd").effective_for_actor(world,
		world.party_encounter,hero).command_id=="STOP_ATTACK","original hero obeys AI orders when not controlled")
	check(world.world_state_error().is_empty(),"command after switch validates: "+world.world_state_error())
	check(not session.select_field_actor(world.party_encounter.enemy_ids[0]).accepted,"cannot control enemy")
	var saved:String=session.save_session_json()
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(saved)
	check(restored.accepted,"selection and formation replay: "+str(restored.get("reason","")))
	if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"replay matches")
	world.party_encounter.member(hero).busy_until=world.world_time+50
	var before:Dictionary=session.sim.snapshot()
	check(not session.select_field_actor(hero).accepted,"busy actor cannot gain extra action by switching")
	check(before==session.sim.snapshot(),"rejected switch is nonmutating")
	for preset in ["LINE","WEDGE","NONE"]:
		check(session.set_exploration_formation(preset).accepted,"set "+preset)
		check(session.FieldRules.formation(world)==preset,"read "+preset)
	print("FIELD PARTY CONTROL: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
