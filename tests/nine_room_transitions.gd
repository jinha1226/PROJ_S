extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/room_transition_rules.gd")
const System=preload("res://sim/systems/room_transition_system.gd")
const G=preload("res://sim/nine_room_generator.gd")
const Sim=preload("res://sim/simulator.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func place(w,id:int,p:Vector2i):
	var old:Vector2i=w.entities[id].position;w.entities[id].position=p;w.reindex_entity_occupancy(id,old,p)
func snapshot_check(s,label:String):
	var error:String=s.sim.world.world_state_error();check(error.is_empty(),label+" audit "+error)
	if not error.is_empty():return
	var saved:Dictionary=s.sim.snapshot();var restored=Sim.from_snapshot(saved)
	check(restored!=null,label+" decode")
	if restored!=null:check(restored.snapshot()==saved,label+" exact")
func run():
	for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
		check(s.sim!=null,"fixture init")
		if s.sim==null:quit(1);return
		var w=s.sim.world;var state:Dictionary=w.party_encounter.nine_room_floor;var hero:int=w.party_encounter.protagonist_id
		var selected:Dictionary={};var source:int=0
		for p in Rules.portals(w):
			var d:=Vector2i(p.direction[0],p.direction[1])
			if d==direction:selected=p;source=p.a;break
			if -d==direction:selected=p;source=p.b;break
		check(not selected.is_empty(),"portal direction "+str(direction))
		if selected.is_empty():continue
		state.active_room_id=source
		var visit:="1:%d"%source
		if visit not in state.visited:state.visited.append(visit)
		var exit:=Rules.cell(w,selected,source);place(w,hero,exit-direction)
		w.party_encounter.group_anchor=w.entities[hero].position
		var before:int=w.world_time;var revision:int=state.revision
		var assessment:=s.assess_room_exit(hero,selected.portal_id)
		check(assessment.accepted,"direction preflight "+str(assessment))
		var result:=s.request_room_exit(hero,selected.portal_id,revision)
		check(result.accepted and result.get("room_result",{}).get("transitioned",false),"direction transition "+str(result))
		check(w.world_time==before+100,"safe movement cost once "+str(direction))
		check(state.active_room_id!=source,"one active room")
		check(not s.request_room_exit(hero,selected.portal_id,revision).accepted,"stale double tap")
		check(Rules.current(w,w.entities[hero].position),"world membership")
		snapshot_check(s,"direction "+str(direction))
	# Two safe rooms isolate persistence from deliberate hostile combat.
	var seed:=-1;var pair:Dictionary={}
	for candidate in range(100):
		var g:=G.generate(candidate)
		for p in g.portals:
			if 4 in [p.a,p.b] and g.rooms[p.a].role=="SAFE" and g.rooms[p.b].role=="SAFE":seed=candidate;pair=p;break
		if seed>=0:break
	check(seed>=0,"safe two-room slice")
	if seed>=0:
		var s=Session.new(seed,20260828,Session.DUO_SCENARIO_ID,"human",true);var w=s.sim.world;var state:Dictionary=w.party_encounter.nine_room_floor;var hero:int=w.party_encounter.protagonist_id
		var hp:int=w.entities[hero].health;var xp:int=w.party_encounter.protagonist_progression.xp_total
		var ids:Array=w.entities.keys();var items:Dictionary=w.item_state.to_dict()
		for trip in range(20):
			var current:int=state.active_room_id;var exit:=Rules.cell(w,pair,current)
			# Fixture walks canonically to the adjacent exit, never relocates after
			# the initial state. Only the boundary call is journaled for this slice.
			var goals:Array=[]
			for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				if Rules.same_room(w,exit,exit+d) and Rules.safe(w,exit+d):goals.append(exit+d)
			var path:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
			check(path.get("found",false),"walk to boundary")
			if not path.get("found",false):break
			for cell in path.path.slice(1):check(s.commit_field_action(Action.move_to(hero,cell)).accepted,"logged approach")
			var result:=s.request_room_exit(hero,pair.portal_id,int(state.revision));check(result.accepted,"roundtrip "+str(trip))
		check(w.entities.keys()==ids,"no entity duplication")
		check(w.entities[hero].health==hp and w.party_encounter.protagonist_progression.xp_total==xp,"HP/XP persistence")
		check(w.item_state.to_dict()==items,"item ownership persistence")
		check(state.visited.size()==2,"only two visited rooms")
		var before:Dictionary=s.sim.snapshot();var journal:Array=s.command_journal.duplicate(true)
		for n in range(10):s.room_status();s.visible_room_minimap();s.assess_room_exit(hero,pair.portal_id)
		check(before==s.sim.snapshot() and journal==s.command_journal,"status/minimap no mutation RNG")
		snapshot_check(s,"twenty roundtrips")
		var loaded=Session.new();var result:Dictionary=loaded.load_session_json(s.save_session_json())
		check(result.accepted,"twenty roundtrips journal replay "+str(result.get("reason","")))
		if result.accepted:check(loaded.sim.snapshot()==s.sim.snapshot(),"twenty roundtrips journal exact")
	print("NINE_ROOM_TRANSITIONS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
