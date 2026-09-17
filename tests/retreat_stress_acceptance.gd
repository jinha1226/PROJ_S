extends "res://tests/first_floor_stages_acceptance.gd"
const Stage=preload("res://sim/stage_counterplay.gd")
const Stress=preload("res://sim/json_content_loader.gd")
const RoundRules=preload("res://sim/round_combat_rules.gd")
func stress_of(w)->Dictionary:
	var out:Dictionary={}
	for id in w.party_encounter.active_party_member_ids:out[id]=int(w.party_encounter.member(id).stress)
	return out
func advance(s)->Dictionary:
	var r:Dictionary=s.sim.world.party_encounter.round_combat
	return s.resume_round(r.round_id,r.plan_revision) if r.phase=="INTERRUPTED" else s.confirm_round(r.round_id,r.plan_revision)
func until_hero(s,hero:int)->bool:
	# Individual turns: the hero must own the cursor before a retreat request.
	for i in range(6):
		if RoundRules.current_actor(s.sim.world)==hero:return true
		if not advance(s).accepted:return false
	return RoundRules.current_actor(s.sim.world)==hero
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach combat room")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter")
	check(s.stage_round_action(preload("res://sim/party_action_command.gd").move_to(hero,Vector2i(10,17))).accepted,"deploy")
	var r:Dictionary=w.party_encounter.round_combat
	check(s.confirm_round(r.round_id,r.plan_revision).accepted,"deployment confirmed")
	check(until_hero(s,hero),"hero owns the turn cursor")
	var before:Dictionary=stress_of(w)
	# Retreat: the hero stands next to the north exit (11,16) after deployment at (10,17).
	var result:Dictionary=s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision))
	check(result.accepted,"retreat request accepted "+str(result.get("reason")))
	var cost:int=int(Stress.load_document("res://data/content/stage_stress.json").retreat_attempt)
	for id in before:check(int(w.party_encounter.member(id).stress)>=before[id]+cost-50,"retreat stress applied to %d"%id)
	check(w.events.any(func(e):return e.type=="party.morale_changed" and "RETREAT" in e.data.trigger_codes),"RETREAT trigger recorded")
	check(w.events.filter(func(e):return e.type=="party.morale_changed" and "RETREAT" in e.data.trigger_codes).size()==before.size(),"retreat stress applied once per member")
	check(w.world_state_error().is_empty(),"world audit "+w.world_state_error())
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted and clone.sim.snapshot()==s.sim.snapshot(),"retreat replay exact "+str(loaded.get("reason")))
	# Forbidden room: re-enter the started stage (planning resumes at the door,
	# no second deployment), flip the objective flag on the live floor and expect
	# rejection. The flag is restored afterwards because every step validator
	# regenerates the topology and compares it with the live dictionary.
	check(s.request_room_travel(7,int(w.party_encounter.nine_room_floor.revision)).accepted,"re-enter guard room")
	check(RoundRules.active(w) and until_hero(s,hero),"hero owns the turn cursor again")
	check(preload("res://sim/room_transition_rules.gd").distance(w.entities[hero].position,Vector2i(11,16))<=1,"hero beside the north door "+str(w.entities[hero].position))
	var snapshot_before:Dictionary=s.sim.snapshot()
	var floor:Dictionary=preload("res://sim/room_transition_rules.gd").current_floor(w)
	floor.rooms[7].stage.objective.retreat_allowed=false
	var forbidden:Dictionary=s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision))
	check(not forbidden.accepted and str(forbidden.reason)=="room_retreat_forbidden","retreat forbidden "+str(forbidden.get("reason")))
	floor.rooms[7].stage.objective.retreat_allowed=true
	check(s.sim.snapshot()==snapshot_before,"forbidden retreat mutates nothing")
	var allowed:Dictionary=s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision))
	check(allowed.accepted,"retreat allowed again "+str(allowed.get("reason")))
	check(w.world_state_error().is_empty(),"final world audit "+w.world_state_error())
	print("RETREAT_STRESS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
