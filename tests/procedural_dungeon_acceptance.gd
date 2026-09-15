extends SceneTree
const Generator=preload("res://playtest/procedural_campaign_floor.gd")
const Campaign=preload("res://playtest/campaign_world_map.gd")
const Opening=preload("res://playtest/deterministic_dungeon_map.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var signatures:Dictionary={};var near:=false;var far:=false
	for seed in range(1,101):
		var floor:Dictionary=Generator.generate(seed)
		check(floor==Generator.generate(seed),"reproducible seed %d"%seed)
		signatures[hash(floor.terrain)]=true
		var distances:Dictionary=Generator.distances(floor.terrain,floor.entry_position)
		var count:=0
		for tile in floor.terrain:
			if tile!="wall":count+=1
		check(count==distances.size(),"all floor tiles connected %d"%seed)
		check(distances.has(floor.exit_position) and int(distances[floor.exit_position])>=20,"exit reachable and separated")
		check(floor.room_links.size()>=floor.rooms.size()+1,"extra connections")
		var anchors:Dictionary=Opening.opening_event_anchors(floor,seed)
		check(not anchors.is_empty(),"opening always generated")
		var spawn:Vector2i=anchors.spawn_position
		check(distances.has(spawn) and spawn not in floor.enemy_positions and spawn!=floor.entry_position and spawn!=floor.exit_position,"opening reachable and unoccupied")
		near=near or int(distances[spawn])<20;far=far or int(distances[spawn])>50
		for enemy in floor.enemy_positions:check(int(distances[enemy])>=12 and enemy.distance_to(floor.entry_position)>8,"safe entry")
		if seed<=6:
			var picture:=Image.create(64,64,false,Image.FORMAT_RGB8)
			for y in range(64):
				for x in range(64):picture.set_pixel(x,y,Color("#121820") if floor.terrain[y*64+x]=="wall" else Color("#697065"))
			for p in floor.enemy_positions:picture.set_pixel(p.x,p.y,Color("#d06055"))
			picture.set_pixel(floor.entry_position.x,floor.entry_position.y,Color("#5de39a"))
			picture.set_pixel(floor.exit_position.x,floor.exit_position.y,Color("#60aaff"))
			picture.set_pixel(spawn.x,spawn.y,Color("#ffe36a"));picture.resize(512,512,Image.INTERPOLATE_NEAREST)
			picture.save_png("/tmp/procedural-map-%d.png"%seed)
	check(signatures.size()==100,"100 distinct topologies")
	check(near and far,"opening has near and far encounters across seeds")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.rescue_new_runs=true
	check(s.start_procedural_run_with_species("human",137,20260829).accepted,"product procedural start")
	check(s.sim.world.party_encounter.opening_event!=null,"opening connected to runtime")
	check(not s.town_life_enabled(),"no town initialization")
	var held:Dictionary=s.commit_field_action(preload("res://sim/party_action_command.gd").hold(s.sim.world.party_control_actor_id()))
	check(held.get("accepted",false),"first procedural turn accepted")
	var save:String=s.save_session_json()
	var restored=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var legacy_save:String=restored.save_session_json()
	check(restored.load_session_json(legacy_save).get("accepted",false),"legacy authored save remains loadable")
	var loaded:Dictionary=restored.load_session_json(save)
	check(loaded.get("accepted",false),"load procedural save: "+str(loaded.get("reason","")))
	check(restored.sim.snapshot()==s.sim.snapshot(),"exact snapshot after load")
	print("PROCEDURAL DUNGEON: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
