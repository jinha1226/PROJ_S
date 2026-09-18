extends SceneTree
## Room-repeat lab: boot a session, travel straight to --room, and attach the
## interactive sandbox UI. Needs a display (X11); diagnostic, not a test.
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")

func arg(name:String,default:String)->String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s="%name):return a.substr(name.length()+3)
	return default

func has_flag(name:String)->bool:
	return "--%s"%name in OS.get_cmdline_user_args()

func _init():call_deferred("run")

func route(s,target:int)->bool:
	# Travel through discovered rooms only; breadth-first over the 3x3 graph.
	var w=s.sim.world;var s_floor:Dictionary=w.party_encounter.nine_room_floor
	var edges:Array=Rooms.current_floor(w).portals.map(func(p):return [int(p.a),int(p.b)])
	var prev:Dictionary={int(s_floor.active_room_id):-1};var todo:Array=[int(s_floor.active_room_id)]
	for a in todo:
		for e in edges:
			var b:int=e[1] if e[0]==a else (e[0] if e[1]==a else -1)
			if b>=0 and not prev.has(b):prev[b]=a;todo.append(b)
	if not prev.has(target):return false
	var path:Array=[];var cur:int=target
	while cur!=-1:path.push_front(cur);cur=prev[cur]
	for id in path.slice(1):
		if not s.request_room_travel(id,int(w.party_encounter.nine_room_floor.revision)).accepted:return false
		if Rules.active(w):return id==target
	return true

func run():
	var room:int=int(arg("room","7"))
	var s=Session.new(1,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_new_run_with_species("human",true,true);s.town_life_command({"action":"START"});s.depart_town()
	var reached:bool=route(s,room)
	print("stage_lab: target room=%d reached=%s"%[room,reached])
	if has_flag("headless-check"):
		quit(0 if reached else 1);return
	root.size=Vector2i(360,800)
	var ui=Sandbox.new();ui.size=Vector2(360,800);ui.initialize_for_headless_test(s,true)
	root.add_child(ui)
