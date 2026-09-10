extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.sim!=null,"field session initializes")
	if session.sim==null:quit(1);return
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	check(session.field_turns_active(),"new expedition uses field turns")
	check(world.world_state_error().is_empty(),"initial world validates: "+world.world_state_error())
	for id in world.party_encounter.active_party_member_ids:
		check(world.party_encounter.member(id).presence=="DEPLOYED","companions occupy field cells")
	var before:Dictionary=world.snapshot()
	var rejected:Dictionary=session.strike_enemy(-1)
	check(not rejected.accepted and world.snapshot()==before,"invalid attack is atomic")
	var waited:Dictionary=session.commit_field_action(Action.hold(hero))
	check(waited.accepted,"ordinary wait succeeds: "+str(waited.get("reason","")))
	check(session.sim.world.world_time==100,"one wait consumes 100 world units")
	check(session.sim.world.party_encounter.safe_phase=="GROUPED","wait does not enter combat")
	check(session.sim.world.world_state_error().is_empty(),"post-turn world validates: "+session.sim.world.world_state_error())
	var rollback_before:Dictionary=session.sim.snapshot()
	var journal_before:Array=session.command_journal.duplicate(true)
	session.sim.party_coordinator.fail_point="after_environment_tick"
	var failed:Dictionary=session.commit_field_action(Action.hold(hero))
	check(not failed.accepted,"injected environment failure rejects whole turn")
	check(session.sim.snapshot()==rollback_before and session.command_journal==journal_before,
		"failed turn rolls back time, actors, events, RNG, cooldowns and journal")
	var order:Dictionary=session.issue_party_command("STOP_ATTACK")
	check(order.accepted,"orders work before contact: "+str(order.get("reason","")))
	var attacks:=0
	for turn in range(30):
		world=session.sim.world
		if world.party_encounter.safe_phase=="PARTY_DEFEATED":break
		var best:Dictionary={};var target:=-1
		for enemy_id in session.party_status().enemies_in_view:
			var ep:Vector2i=world.entities[enemy_id].position
			var hp:Vector2i=world.entities[hero].position
			if maxi(absi(ep.x-hp.x),absi(ep.y-hp.y))<=1:target=enemy_id;break
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var path:Dictionary=session.sim.pathfinder.find_path(hero,ep+direction)
				if path.get("found",false) and path.path.size()>1 \
					and (best.is_empty() or path.path.size()<best.path.size()):best=path
		var result:Dictionary
		if target>0:
			result=session.strike_with_skill("STRIKE",target) if attacks==0 else session.strike_enemy(target)
			attacks+=int(result.accepted)
		elif not best.is_empty():result=session.commit_field_action(Action.move_to(hero,best.path[1]))
		else:
			# Explore toward the nearest reachable enemy using this fixture's map.
			for enemy_id in world.party_encounter.enemy_ids:
				if not world.is_autonomous_target(enemy_id):continue
				var ep:Vector2i=world.entities[enemy_id].position
				for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var path:Dictionary=session.sim.pathfinder.find_path(hero,ep+direction)
					if path.get("found",false) and path.path.size()>1 \
						and (best.is_empty() or path.path.size()<best.path.size()):best=path
			result=session.commit_field_action(Action.move_to(hero,best.path[1])) if not best.is_empty() \
				else session.commit_field_action(Action.hold(hero))
		check(result.accepted,"field action %d succeeds: %s"%[turn,str(result.get("reason",""))])
		if not result.accepted:break
		var error:String=session.sim.world.world_state_error()
		check(error.is_empty(),"action %d snapshot validates: %s"%[turn,error])
		if not error.is_empty():break
		if attacks>=3:break
	check(attacks>0,"direct field attack resolves")
	for event in session.sim.world.events:
		check(event.type not in ["encounter.detected","encounter.party_ambush","encounter.enemy_ambush",
			"party.deployment_completed","party.regroup_completed"],"no encounter/deployment/regroup transition")
	var saved:String=session.save_session_json()
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(saved)
	check(restored.accepted,"field save journal replays: "+str(restored.get("reason","")))
	if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"replay exactly matches field world")
	var town=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var started:Dictionary=town.town_life_command({"action":"START"})
	check(started.accepted,"town start works: "+str(started.get("reason","")))
	if started.accepted:
		var departed:Dictionary=town.depart_town()
		check(departed.accepted,"town party enters field: "+str(departed.get("reason","")))
		if departed.accepted:
			check(town.sim.world.world_state_error().is_empty(),"floor entry validates: "+town.sim.world.world_state_error())
			for id in town.sim.world.party_encounter.active_party_member_ids:
				check(town.sim.world.party_encounter.member(id).presence=="DEPLOYED","town companions retain own cells")
	print("FIELD TURN: ","PASS" if failures.is_empty() else "FAIL", " ",failures)
	quit(0 if failures.is_empty() else 1)
