extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const State=preload("res://sim/round_combat_state.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.sim!=null,"product bootstrap")
	if s.sim==null:quit(1);return
	var w=s.sim.world;var party=w.party_encounter
	check(Rules.enabled(w),"actual product path uses planned combat")
	for hop in range(80):
		if s.round_active():break
		var nearest:Dictionary={}
		for enemy_id in s._current_floor_enemy_ids():
			var enemy=w.entities[enemy_id]
			if not w.is_autonomous_target(enemy_id):continue
			var goals:Array=[]
			for delta in s.sim.movement.MOVE_DIRECTIONS_8:goals.append(enemy.position+delta)
			var route:Dictionary=s.sim.party_coordinator.pathfinder.find_path_to_any(party.protagonist_id,goals)
			if route.get("found",false) and route.path.size()>1 and (nearest.is_empty() or route.path.size()<nearest.path.size()):nearest=route
		if nearest.is_empty():break
		var moved=s.commit_field_action(Action.move_to(party.protagonist_id,nearest.path[1]))
		if not moved.accepted:check(false,"approach threat "+str(moved.reason));break
	print("ROUND_INITIAL ",s.round_status())
	# Force the existing visible tutorial enemies awake without changing AI choice.
	check(Plans.begin(s.sim),"begin plans")
	check(s.round_active(),"visible threat starts planning")
	if not s.round_active():quit(1);return
	check(State.wire_error(party.round_combat,w.width,w.height).is_empty(),"strict state wire")
	var before=w.snapshot();var journal=s.command_journal.duplicate(true)
	var p1=s.round_preview();var p2=s.round_preview()
	check(p1.get("accepted",false),"real sequential preview "+str(p1))
	check(p1==p2,"preview cache and outcome stable")
	check(before==w.snapshot() and journal==s.command_journal,"preview world/journal/RNG unchanged")
	var r=s.round_status();var hero:int=party.protagonist_id
	check(s.edit_round_plan(hero,{"action":Action.hold(hero).to_dict(),"path":[]},r.plan_revision).accepted,"hero edit")
	check(not s.confirm_round(r.round_id,r.plan_revision).accepted,"stale revision rejected")
	r=s.round_status();var time:int=w.world_time
	var done=s.confirm_round(r.round_id,r.plan_revision)
	check(done.accepted,"confirm "+str(done.get("reason","")))
	check(s.sim.world.world_time==time+100,"round fixed100 time")
	check(not s.confirm_round(r.round_id,r.plan_revision).accepted,"duplicate confirm refused")
	check(s.sim.world.world_state_error().is_empty(),"post-round full audit "+s.sim.world.world_state_error())
	var encoded:String=s.save_session_json();check(not encoded.is_empty(),"planning save")
	var restored=Session.new();var loaded=restored.load_session_json(encoded)
	check(loaded.accepted,"round journal load "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"round replay exact")
	print("ROUND_CORE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
