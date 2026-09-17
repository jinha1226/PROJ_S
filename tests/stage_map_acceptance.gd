extends "res://tests/first_floor_stages_acceptance.gd"
const MapModel=preload("res://sim/stage_map_model.gd")
func node(map:Dictionary,id:int)->Dictionary:
	for n in map.nodes:
		if int(n.id)==id:return n
	return {}
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"species");check(s.town_life_command({"action":"START"}).accepted,"town");check(s.depart_town().accepted,"depart")
	var w=s.sim.world
	var map:Dictionary=MapModel.build(w)
	check(map.current==4 and map.floor_index==1 and not map.in_combat,"start at entry")
	check(node(map,4).visited and node(map,4).current and node(map,4).cleared,"entry visited")
	for id in [3,5,7]:check(node(map,id).reachable and not node(map,id).visited and node(map,id).name=="미탐색","adjacent discovered %d"%id)
	check(node(map,1).is_empty() and node(map,0).is_empty(),"undiscovered rooms hidden")
	check(map.edges.size()==3,"three discovered edges")
	check(node(map,4).role=="SAFE" and node(map,4).biome=="dungeon","entry role/biome")
	check(node(map,7).role=="COMBAT","room 7 combat role")
	var before:Dictionary=s.sim.snapshot();MapModel.build(w);check(s.sim.snapshot()==before,"model is read only")
	check(s.stage_map()==map,"session stage_map")
	var rev:int=int(w.party_encounter.nine_room_floor.revision);var time:int=w.world_time
	check(not s.request_room_travel(1,rev).accepted,"undiscovered room rejected")
	var moved:Dictionary=s.request_room_travel(5,rev)
	check(moved.accepted,"travel east "+str(moved.get("reason")))
	check(int(w.party_encounter.nine_room_floor.active_room_id)==5,"active room 5")
	check(w.world_time==time,"travel costs no time")
	check("1:5" in w.party_encounter.nine_room_floor.visited,"room 5 visited")
	for id in w.party_encounter.active_party_member_ids:check(Rooms.current(w,w.entities[id].position),"party inside room 5")
	check(w.party_encounter.nine_room_floor.pending_pursuit.is_empty(),"no pursuit on travel")
	check(not s.request_room_travel(4,rev).accepted,"stale revision rejected")
	check(s.request_room_travel(4,int(w.party_encounter.nine_room_floor.revision)).accepted,"travel back")
	check(s.request_room_travel(7,int(w.party_encounter.nine_room_floor.revision)).accepted,"travel into combat room")
	check(w.party_encounter.round_combat.phase=="DEPLOYMENT","combat room starts deployment")
	map=MapModel.build(w)
	check(map.in_combat and map.nodes.all(func(n):return not n.reachable),"no travel during combat")
	check(not s.request_room_travel(4,int(w.party_encounter.nine_room_floor.revision)).accepted,"travel rejected in combat")
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted,"travel journal replay "+str(loaded.get("reason")))
	if loaded.accepted:check(clone.sim.snapshot()==s.sim.snapshot(),"travel replay exact")
	check(w.world_state_error().is_empty(),"world audit "+w.world_state_error())
	print("STAGE_MAP ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
