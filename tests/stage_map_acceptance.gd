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
	var before:Dictionary=s.sim.snapshot();MapModel.build(w);check(s.sim.snapshot()==before,"model is read only")
	print("STAGE_MAP ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
