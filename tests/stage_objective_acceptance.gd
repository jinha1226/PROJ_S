extends "res://tests/first_floor_stages_acceptance.gd"
const Stage=preload("res://sim/stage_counterplay.gd")
const Catalog=preload("res://sim/stage_catalog.gd")
const Generator=preload("res://sim/nine_room_generator.gd")
func run():
	var layout:Dictionary=Generator.generate(44,1)
	for room in layout.rooms:
		check(room.has("stage") and room.stage.has("reinforcements") and room.stage.has("objective"),"room carries stage config %d"%room.room_id)
		var authored:Dictionary=Catalog.room(1,int(room.room_id))
		var expected:Array=Catalog.wave_enemies(authored,0)
		var placed:Array=layout.enemy_roster.filter(func(e):return e.group_id=="ROOM_%d"%room.room_id)
		check(placed.size()==expected.size(),"authored wave 0 count %d"%room.room_id)
		for i in range(mini(placed.size(),expected.size())):
			check(placed[i].species_id==expected[i].kind,"authored kind %d"%room.room_id)
	var second:Dictionary=Generator.generate(44,2)
	check(second.rooms.all(func(r):return r.stage.objective.type=="ELIMINATE"),"floor 2 default objective")
	# SURVIVE objective opens the room without killing everyone.
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach guard room")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter guard room")
	var objective:Dictionary=Stage.config(w).objective
	check(objective.type=="SURVIVE","guard room is a survive stage")
	check(not Stage.cleared(w),"not cleared on entry")
	for i in range(int(objective.rounds)):Stage.current(w).turn=i;check(not Stage.cleared(w) or i>=int(objective.rounds),"not cleared before rounds")
	Stage.current(w).turn=int(objective.rounds)
	check(Stage.cleared(w),"cleared after surviving")
	check(Stage.status(w).objective_done,"status reports objective")
	check(Stage.retreat_allowed(w),"retreat allowed by default")
	print("STAGE_OBJECTIVE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
