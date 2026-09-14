extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")
const Field=preload("res://sim/field_turn_rules.gd")
const Board=preload("res://sim/enemy_squad_blackboard.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_encounter.protagonist_id
	check(Field.visible_cells(w).size()==64,"all starting room cells revealed")
	for i in range(3):check(s.commit_field_action(Action.move_to(hero,w.entities[hero].position+Vector2i.DOWN)).accepted,"approach exit")
	check(s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision)).accepted,"enter combat room")
	check(s.round_active(),"planning immediately on entry")
	check(Field.visible_cells(w).size()==64,"all combat room cells revealed")
	check(s._presentation_visible_cells(w.entities[hero].position).size()==64,"presentation reveals walls and distant tiles")
	var round:Dictionary=w.party_encounter.round_combat
	var count:=0;var outside:Dictionary={}
	for id in w.party_encounter.enemy_ids:
		if Rooms.actor_active(w,id):
			count+=1
			check(Field.visible(w,id),"all active enemies visible")
			check(str(id) in round.participants,"all active enemies participate immediately")
			check(hero in Board.visible_party_ids(w,id),"enemy knows party regardless of wall or distance")
			var plan:Dictionary=round.plans.get(str(id),{})
			check(not plan.is_empty() and plan.path.is_empty() and plan.action.type=="HOLD","enemy waits for deployment confirmation")
		else:
			outside[id]=w.entities[id].position
			check(not Field.visible(w,id) and str(id) not in round.participants,"other rooms remain hidden and inactive")
	check(count==3,"entire authored encounter participates")
	var before:Dictionary=s.sim.snapshot()
	for i in range(3):s.round_preview();s.observe_party_ui(8,true,8)
	check(before==s.sim.snapshot(),"inspection does not resolve combat")
	check(s.confirm_round(round.round_id,round.plan_revision).accepted,"resolve first round")
	for id in outside:check(outside[id]==w.entities[id].position,"inactive room enemies do not move")
	check(w.world_state_error().is_empty(),"world audit")
	var saved:String=s.save_session_json();var clone=Session.new();var loaded:Dictionary=clone.load_session_json(saved)
	check(loaded.accepted,"stage save replay "+str(loaded.get("reason","")))
	if loaded.accepted:check(s.sim.snapshot()==clone.sim.snapshot(),"stage replay exact")
	print("OPEN_ROOM_STAGE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
