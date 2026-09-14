# Diagnostic only, not a required acceptance gate. A naive solo policy may die.
extends "res://tests/first_floor_stages_acceptance.gd"
const Moves=[Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
func clear_combat(s)->bool:
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	for turn in range(100):
		if w.entities[hero].health<=0:return false
		if not s.round_active():return true
		if not w.can_act(hero,w.world_time):return false
		var r:Dictionary=w.party_encounter.round_combat
		for id in w.party_encounter.active_party_member_ids:
			if not r.plans.has(str(id)):continue
			var enemies:Array=[]
			for enemy in w.party_encounter.enemy_ids:
				if Rooms.actor_active(w,enemy) and w.is_unresolved_enemy(enemy):enemies.append(enemy)
			enemies.sort_custom(func(a,b):return Rooms.distance(w.entities[id].position,w.entities[a].position)<Rooms.distance(w.entities[id].position,w.entities[b].position))
			var action=Action.hold(id);var path:Array=[]
			for enemy in enemies:
				if s.sim.melee.can_attack(id,enemy):action=Action.melee(id,enemy);break
			if action.type=="HOLD":
				var goals:Array=[]
				for enemy in enemies:
					for delta in Moves:
						var cell:Vector2i=w.entities[enemy].position+delta
						if w.in_bounds(cell) and Rooms.current(w,cell):goals.append(cell)
				var route:Dictionary=s.sim.pathfinder.find_path_to_any(id,goals)
				if route.get("found",false) and route.path.size()>1:path=[[route.path[1].x,route.path[1].y]]
			var edited:Dictionary=s.edit_round_plan(id,{"action":action.to_dict(),"path":path},int(r.plan_revision))
			if not edited.accepted:printerr("ROUTE edit ",edited.get("reason"));return false
		var resolved:Dictionary=s.confirm_round(int(r.round_id),int(r.plan_revision))
		if not resolved.accepted:printerr("ROUTE round ",resolved.get("reason"));return false
	return false
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"solo species selection")
	check(s.town_life_command({"action":"START"}).accepted,"town start")
	check(s.depart_town().accepted,"departure")
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var visited:Dictionary={4:true}
	for target in [5,2,1,0,3,6,7,8,5,4]:
		var current:int=w.party_encounter.nine_room_floor.active_room_id
		var portal:Dictionary={}
		for p in Rooms.portals(w):
			if current in [int(p.a),int(p.b)] and target in [int(p.a),int(p.b)]:portal=p;break
		check(not portal.is_empty(),"route has portal");if portal.is_empty():break
		var exit:Vector2i=Rooms.cell(w,portal,current)
		var goals:Array=[]
		for delta in Moves:
			var cell:Vector2i=exit+delta
			if Rooms.current(w,cell) and cell!=exit:goals.append(cell)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		check(route.get("found",false),"route reaches exit");if not route.get("found",false):break
		check(walk(s,route.path.back()),"walk across stage")
		var entered:Dictionary=s.request_room_exit(hero,portal.portal_id,int(w.party_encounter.nine_room_floor.revision))
		check(entered.accepted,"enter room "+str(target));if not entered.accepted:break
		check(int(w.party_encounter.nine_room_floor.active_room_id)==target,"transition completes to "+str(target))
		if int(w.party_encounter.nine_room_floor.active_room_id)!=target:print(entered);break
		visited[target]=true
		var cleared:bool=clear_combat(s)
		check(cleared,"clear room "+str(target));if not cleared:break
		for i in range(4):
			if w.combatant_states[hero].status_rows.is_empty():break
			s.commit_field_action(Action.hold(hero))
		for i in range(6):
			var offer:Dictionary=s.personal_rest_preview()
			if not offer.accepted:break
			check(s.request_personal_rest(offer.revision,offer.request_id).accepted,"paid rest")
		print("F1_ROUTE room=",target," hp=",w.entities[hero].health," food=",w.party_encounter.ration_milli/1000)
	check(visited.size()==9,"all nine rooms visited with normal actions")
	check(w.world_state_error().is_empty(),"final world audit")
	var alive:=0
	for id in w.party_encounter.enemy_ids:
		if "campaign_floor:1" in w.entities[id].tags and w.is_unresolved_enemy(id):alive+=1
	check(alive==0,"all twelve first-floor monsters defeated")
	print("FIRST_FLOOR_ROUTE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
